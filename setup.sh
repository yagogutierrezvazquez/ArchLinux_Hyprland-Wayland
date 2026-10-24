#!/usr/bin/env bash
# setup.sh: put these dotfiles in place on an Arch install.
#   ./setup.sh               check packages, link the configs with stow, first colors
#   ./setup.sh translator    + offline translator (Python venv + ~170 MB of models)
#   ./setup.sh agenda        + Google Calendar agenda (Python venv)
# Never runs sudo: missing packages are printed as a pacman command to run yourself.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"

packages=(hypr quickshell waybar rofi matugen kitty bash bin)
deps=(hyprland hyprpaper hyprlock hypridle hyprpolkitagent xdg-desktop-portal-hyprland
      quickshell waybar rofi matugen kitty fastfetch stow
      wl-clipboard cliphist grim slurp wtype brightnessctl playerctl wireplumber
      imagemagick libnotify networkmanager bluez-utils python
      ttf-jetbrains-mono-nerd breeze-icons)

# ---------- Packages ----------
missing=()
for p in "${deps[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if (( ${#missing[@]} )); then
    echo "Missing packages. Install them, then run this again:"
    echo "  sudo pacman -Syu --needed ${missing[*]}"
    exit 1
fi

# ---------- Configs ----------
# stow links each package into ~ (hypr/.config/hypr -> ~/.config/hypr, ...).
# It refuses to overwrite real files: move those away first.
if ! stow --no --target="$HOME" "${packages[@]}" 2>/dev/null; then
    echo "stow found existing files in the way:"
    stow --no --target="$HOME" "${packages[@]}" 2>&1 | grep -E 'existing target|cannot stow' || true
    echo "Back them up (e.g. mv ~/.bashrc ~/.bashrc.orig) and run this again."
    exit 1
fi
stow --target="$HOME" "${packages[@]}"
echo "Linked: ${packages[*]}"

# ---------- Wallpapers and first colors ----------
mkdir -p ~/wallpapers ~/lock_wallpapers "${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper"
first=$(find ~/wallpapers -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort | head -n1)
lock=$(find ~/lock_wallpapers -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort | head -n1)
[[ -n $lock ]] && ln -sfn "$lock" "${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper/lock"
if [[ -n $first && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    ~/.config/hypr/scripts/set-wallpaper.sh "$first"     # hyprpaper + matugen -> all color files
    echo "Colors generated from $(basename "$first")"
else
    echo "Put images in ~/wallpapers (and ~/lock_wallpapers), then pick one with SUPER+W inside Hyprland."
fi

# ---------- Optional extras ----------
for extra in "$@"; do
    case $extra in
    translator)
        # Offline ES <-> EN (hypr/scripts/translate.py). Argos Translate 1.0 models:
        # they use SentencePiece, which translate.py expects (es_en 1.9 doesn't).
        dir=~/.local/share/translator
        python -m venv "$dir/venv"
        "$dir/venv/bin/pip" install --quiet ctranslate2 sentencepiece
        for pair in es_en en_es; do
            [[ -f $dir/models/$pair/sentencepiece.model ]] && continue
            tmp=$(mktemp -d)
            curl -fL --proto '=https' -o "$tmp/m.zip" "https://argos-net.com/v1/translate-${pair}-1_0.argosmodel"
            python -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$tmp/m.zip" "$tmp/x"
            mkdir -p "$dir/models"
            mv "$(dirname "$(find "$tmp/x" -name metadata.json | head -n1)")" "$dir/models/$pair"
            rm -rf "$tmp"
        done
        echo "Translator ready (SUPER+T)."
        ;;
    agenda)
        # Read-only Google Calendar agenda in the dashboard (hypr/scripts/agenda.py)
        dir=~/.local/share/agenda
        python -m venv "$dir/venv"
        "$dir/venv/bin/pip" install --quiet icalendar recurring-ical-events
        ( umask 077; touch "$dir/calendars" ); chmod 700 "$dir"
        echo "Agenda ready. Paste each calendar's 'Secret address in iCal format', one per line, in"
        echo "  $dir/calendars   (chmod 600: those links are keys, never commit or share them)"
        ;;
    *) echo "Unknown extra: $extra (translator, agenda)"; exit 1 ;;
    esac
done
