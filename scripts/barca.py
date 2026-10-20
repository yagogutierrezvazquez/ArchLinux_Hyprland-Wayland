#!/usr/bin/env python3
"""FC Barcelona matches for the Quickshell sidebar.

Fetches ESPN's public JSON (no key, but undocumented: it may change) and writes
a compact summary to ~/.cache/barca/data.json, with crests cached next to it.
On any network/format error the previous file is left untouched.

    barca.py     refresh the cache (prints nothing; exit 1 on failure)
"""
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime

TEAM = "83"                                    # ESPN id of FC Barcelona
API = "https://site.api.espn.com/apis/site/v2/sports/soccer"
CACHE = os.path.expanduser("~/.cache/barca")
CREST_HOST = "https://a.espncdn.com/"          # the only host images are taken from


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-sidebar"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def crest(team):
    """Local path of the team's crest (dark-background variant if there is one)."""
    tid = str(team.get("id", ""))
    if not tid.isdigit():
        return ""
    path = os.path.join(CACHE, "crests", tid + ".png")
    if not os.path.exists(path):
        logos = team.get("logos") or []
        dark = [l for l in logos if "dark" in l.get("rel", [])]
        url = (dark or logos or [{}])[0].get("href", "")
        if not url.startswith(CREST_HOST):
            return ""
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "quickshell-sidebar"})
            with urllib.request.urlopen(req, timeout=10) as r:
                data = r.read(2_000_000)
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
        except OSError:
            return ""
    return path


def side(c):
    t = c["team"]
    score = c.get("score")
    if isinstance(score, dict):
        score = score.get("displayValue", "")
    return {
        "id": str(t.get("id", "")),
        "name": t.get("shortDisplayName") or t.get("displayName", ""),
        "abbr": t.get("abbreviation", ""),
        "crest": crest(t),
        "score": score or "",
    }


def match(e):
    c = e["competitions"][0]
    st = c["status"]
    teams = {x.get("homeAway"): x for x in c["competitors"]}
    home, away = side(teams["home"]), side(teams["away"])
    us, them = (home, away) if home["id"] == TEAM else (away, home)
    result = ""
    if st["type"].get("completed") and us["score"] != "" and them["score"] != "":
        a, b = int(us["score"]), int(them["score"])
        result = "W" if a > b else "L" if a < b else "D"
        # Penalty shoot-outs: ESPN marks the winner even when the score is level
        mine = teams["home"] if home["id"] == TEAM else teams["away"]
        if result == "D" and "PEN" in st["type"].get("name", ""):
            result = "W" if mine.get("winner") else "L"
    date = datetime.fromisoformat(e["date"].replace("Z", "+00:00"))
    return {
        "time": int(date.timestamp() * 1000),
        "competition": re.sub(r"^UEFA ", "", e.get("league", {}).get("abbreviation", "")
                              or e.get("season", {}).get("displayName", "")),
        "state": st["type"].get("state", "pre"),          # pre / in / post
        "clock": st.get("displayClock", ""),
        "detail": st["type"].get("shortDetail", ""),
        "venue": (c.get("venue") or {}).get("fullName", ""),
        "home": home,
        "away": away,
        "result": result,
    }


def main():
    os.makedirs(os.path.join(CACHE, "crests"), mode=0o700, exist_ok=True)
    try:
        fixtures = get(f"{API}/all/teams/{TEAM}/schedule?fixture=true").get("events", [])
        results = get(f"{API}/all/teams/{TEAM}/schedule").get("events", [])
        team = get(f"{API}/esp.1/teams/{TEAM}").get("team", {})
        upcoming = [match(e) for e in fixtures[:4]]
        recent = [match(e) for e in results[:3]]
    except (OSError, ValueError, KeyError, IndexError, TypeError) as err:
        print(f"barca: {err}", file=sys.stderr)
        return 1

    # A match being played shows up in the fixtures list with state "in"
    live = next((m for m in upcoming if m["state"] == "in"), None)
    data = {
        "fetched": int(time.time() * 1000),
        "crest": crest(team),
        "standing": team.get("standingSummary", "").replace("Spanish ", ""),
        "live": live,
        "next": [m for m in upcoming if m["state"] == "pre"][:3],
        "recent": recent,
    }
    out = os.path.join(CACHE, "data.json")
    with open(out + ".tmp", "w") as f:
        json.dump(data, f)
    os.replace(out + ".tmp", out)       # atomic: the sidebar never reads half a file
    return 0


if __name__ == "__main__":
    sys.exit(main())
