#!/usr/bin/env bash
# Wi-Fi menu (click the network module in Waybar): rofi list from nmcli.
# Select a network to connect, the connected one to disconnect.
# Passwords are given to nmcli through passwd-file (a pipe), never as a
# command-line argument, so they don't show up in `ps` / /proc.
set -uo pipefail

theme="$HOME/.config/rofi/menu.rasi"

# Clicking the module again while a menu is open closes it (toggle)
pkill -x rofi && exit 0
menu() { rofi -dmenu -i -no-custom -format i -theme "$theme" "$@"; }
note() { notify-send -a "Wi-Fi" "Wi-Fi" "$1"; }

# Signal strength -> md-wifi-strength-1..4
signal_icon() {
    local s=$1
    if   (( s >= 75 )); then printf '\U000f0928'
    elif (( s >= 50 )); then printf '\U000f0925'
    elif (( s >= 25 )); then printf '\U000f0922'
    else                     printf '\U000f091f'
    fi
}

# ---------- Radio off: only offer to turn it on ----------
if [[ $(nmcli radio wifi) != enabled ]]; then
    pick=$(printf '%s  Turn Wi-Fi on\n' $'\U000f05a9' | menu -p $'\U000f05aa' -mesg "Wi-Fi is off") || exit 0
    nmcli radio wifi on && note "Wi-Fi on"
    exit 0
fi

# ---------- Scan ----------
# Show NetworkManager's cached list instantly (--rescan no). `--rescan auto`
# would block ~5 s whenever the list is older than 30 s. A background rescan
# keeps the list fresh for the next time the menu opens.
nmcli device wifi rescan >/dev/null 2>&1 &
# Terse output escapes ':' inside fields as '\:'; swap it out before splitting.
declare -A best_signal security
active=""
while IFS= read -r line; do
    line=${line//\\:/$'\x01'}
    IFS=: read -r inuse ssid sec sig <<< "$line"
    ssid=${ssid//$'\x01'/:}
    [[ -z $ssid ]] && continue                      # hidden networks
    [[ $inuse == '*' ]] && active=$ssid
    if [[ -z ${best_signal[$ssid]:-} ]] || (( sig > best_signal[$ssid] )); then
        best_signal[$ssid]=$sig
        security[$ssid]=$sec
    fi
done < <(nmcli -t -f IN-USE,SSID,SECURITY,SIGNAL device wifi list --rescan no)

# Strongest first
mapfile -t ssids < <(for s in "${!best_signal[@]}"; do
    printf '%s\t%s\n' "${best_signal[$s]}" "$s"
done | sort -t$'\t' -k1,1nr | cut -f2-)

# ---------- Menu ----------
rows=()
for s in "${ssids[@]}"; do
    row="$(signal_icon "${best_signal[$s]}")  $s"
    [[ ${security[$s]} != "" && ${security[$s]} != "--" ]] && row+="  "$'\U000f033e'   # md-lock
    [[ $s == "$active" ]] && row+="  "$'\U000f012c'                                   # md-check
    rows+=("$row")
done
rows+=("$(printf '\U000f05aa')  Turn Wi-Fi off")

msg="Not connected"
[[ -n $active ]] && msg="Connected to <b>${active//&/&amp;}</b> · select it to disconnect"

idx=$(printf '%s\n' "${rows[@]}" | menu -p $'\U000f05a9' -mesg "$msg") || exit 0
[[ -z $idx ]] && exit 0

# Last row: radio off
if (( idx == ${#ssids[@]} )); then
    nmcli radio wifi off && note "Wi-Fi off"
    exit 0
fi

ssid=${ssids[idx]}
sec=${security[$ssid]}

# Connected network: disconnect
if [[ $ssid == "$active" ]]; then
    nmcli connection down id "$ssid" >/dev/null 2>&1 \
        || nmcli device disconnect "$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')" >/dev/null
    note "Disconnected from $ssid"
    exit 0
fi

# Saved profile for this SSID? (profile names can differ from the SSID)
saved=""
while IFS=: read -r name type; do
    [[ $type == 802-11-wireless ]] || continue
    [[ $(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null) == "$ssid" ]] && { saved=$name; break; }
done < <(nmcli -t -f NAME,TYPE connection show)

ask_password() {
    rofi -dmenu -password -theme "$theme" -p $'\U000f033e' \
        -mesg "Password for <b>${ssid//&/&amp;}</b>" \
        -theme-str 'listview { enabled: false; } entry { placeholder: "Password"; }'
}

note "Connecting to $ssid…"

if [[ -n $saved ]]; then
    # Known network: just bring the profile up (NM has the password)
    if nmcli connection up id "$saved" >/dev/null 2>&1; then
        note "Connected to $ssid"
        exit 0
    fi
    # Stored password missing or wrong: ask and retry once
    pw=$(ask_password) || exit 0
    nmcli connection up id "$saved" passwd-file <(printf '802-11-wireless-security.psk:%s\n' "$pw") >/dev/null 2>&1 \
        && note "Connected to $ssid" || note "Could not connect to $ssid"
    exit 0
fi

# Open network
if [[ -z $sec || $sec == "--" ]]; then
    nmcli device wifi connect "$ssid" >/dev/null 2>&1 \
        && note "Connected to $ssid" || note "Could not connect to $ssid"
    exit 0
fi

# New secured network: WPA/WPA2 (psk) or WPA3 (sae). Enterprise -> use nmtui.
case $sec in
    *802.1X*) note "$ssid uses enterprise (802.1X) auth; use nmtui for that"; exit 1 ;;
    *WPA3*)   keymgmt=sae ;;
    *WPA*)    keymgmt=wpa-psk ;;
    *)        note "Unsupported security on $ssid ($sec)"; exit 1 ;;
esac

pw=$(ask_password) || exit 0
[[ -z $pw ]] && exit 0

# Create the profile without the secret, then pass it in through a pipe.
nmcli connection add type wifi con-name "$ssid" ssid "$ssid" \
    wifi-sec.key-mgmt "$keymgmt" >/dev/null 2>&1 || { note "Could not create a profile for $ssid"; exit 1; }
if nmcli connection up id "$ssid" passwd-file <(printf '802-11-wireless-security.psk:%s\n' "$pw") >/dev/null 2>&1; then
    note "Connected to $ssid"
else
    nmcli connection delete id "$ssid" >/dev/null 2>&1   # don't keep a broken profile
    note "Could not connect to $ssid (wrong password?)"
fi
