"""Read-only agenda from Google Calendar for the Quickshell dashboard.

Calendars: ~/.local/share/agenda/calendars, one "secret address in iCal format"
per line (chmod 600; the links are keys, never print or commit them).
Runs with the venv in ~/.local/share/agenda (recurring-ical-events + icalendar):
    ~/.local/share/agenda/venv/bin/python -I agenda.py
Writes ~/.cache/agenda/data.json: events grouped by local day, from the start
of last month to two months ahead. Each calendar's last good download is kept
in ~/.cache/agenda/ so the agenda still works offline.
"""
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta

import icalendar
import recurring_ical_events

URLS = os.path.expanduser("~/.local/share/agenda/calendars")
CACHE = os.path.expanduser("~/.cache/agenda")


def download(i, url):
    """Raw iCal text of calendar i: fresh if possible, else the cached copy."""
    path = os.path.join(CACHE, f"{i}.ics")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "quickshell-agenda"})
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read(5_000_000)
        icalendar.Calendar.from_ical(data)            # only cache what parses
        with open(path + ".tmp", "wb") as f:
            f.write(data)
        os.replace(path + ".tmp", path)
        return data, True
    except Exception:                                 # offline, HTTP error, bad data
        try:
            with open(path, "rb") as f:
                return f.read(), False
        except OSError:
            return None, False


def local(dt):
    """datetime/date -> (local naive datetime, is_all_day)."""
    if isinstance(dt, datetime):
        return (dt.astimezone() if dt.tzinfo else dt).replace(tzinfo=None), False
    return datetime(dt.year, dt.month, dt.day), True


def main():
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    os.umask(0o077)
    try:
        with open(URLS) as f:
            urls = [l.strip() for l in f if l.strip().startswith("https://")]
    except OSError:
        print("agenda: no calendars file", file=sys.stderr)
        return 1

    today = date.today()
    first = (today.replace(day=1) - timedelta(days=1)).replace(day=1)   # start of last month
    last = (today.replace(day=1) + timedelta(days=95)).replace(day=1)   # start of month +3

    with ThreadPoolExecutor(max_workers=8) as pool:
        downloads = list(pool.map(lambda a: download(*a), enumerate(urls)))

    calendars, days, stale = [], {}, 0
    for index, (data, fresh) in enumerate(downloads):
        stale += not fresh
        if data is None:
            calendars.append({"name": "?", "ok": False})
            continue
        cal = icalendar.Calendar.from_ical(data)
        calendars.append({"name": str(cal.get("X-WR-CALNAME", f"Calendar {index + 1}")), "ok": True})
        for ev in recurring_ical_events.of(cal).between(first, last):
            start, all_day = local(ev.get("DTSTART").dt)
            end_prop = ev.get("DTEND")
            end = local(end_prop.dt)[0] if end_prop else start + (timedelta(days=1) if all_day else timedelta())
            item = {
                "title": str(ev.get("SUMMARY", "(no title)")),
                "location": str(ev.get("LOCATION", "")),
                "start": int(start.timestamp() * 1000),
                "end": int(end.timestamp() * 1000),
                "allDay": all_day,
                "calendar": index,
            }
            # Put it on every day it touches (all-day ends are exclusive)
            d = start.date()
            last_day = (end - timedelta(seconds=1)).date() if end > start else start.date()
            while d <= last_day:
                if first <= d < last:
                    days.setdefault(d.isoformat(), []).append(item)
                d += timedelta(days=1)

    for items in days.values():
        items.sort(key=lambda e: (not e["allDay"], e["start"], e["title"].lower()))

    out = os.path.join(CACHE, "data.json")
    with open(out + ".tmp", "w") as f:
        json.dump({"fetched": int(time.time() * 1000), "stale": stale,
                   "calendars": calendars, "days": days}, f, ensure_ascii=False)
    os.replace(out + ".tmp", out)
    return 0 if stale < len(urls) else 1


if __name__ == "__main__":
    sys.exit(main())
