# dotfiles

My Hyprland setup on Arch (EndeavourOS).

I started this to learn how Arch actually works and how to manage a Wayland
compositor like Hyprland from scratch, instead of using a ready-made desktop.
The goal is a clean, comfortable workspace for my own projects.

## What's in it

| Folder | What it is |
| --- | --- |
| `hypr` | Hyprland (Lua config, split into `modules/`), hyprlock, hypridle, hyprpaper and helper scripts |
| `quickshell` | Dock, dashboard (calendar, agenda, controls, notifications, performance), notification popups, clipboard history, wallpaper picker, media popup, translator, FC Barcelona tracker |
| `waybar` | Top bar: three floating sections |
| `rofi` | App launcher and Wi-Fi menu |
| `matugen` | Color templates: the accent color of every app comes from the current wallpaper |
| `kitty` | Terminal |
| `bash`, `bin` | `.bashrc` and small personal commands |

### Things I cared about

- **Security first**
  - Screen capture is only allowed for `grim` and the desktop portal (Hyprland permission system).
  - Clipboard history lives in RAM and skips passwords and anything copied from the password manager.
  - No `input` group.
  - Calendar links are kept outside the repo.
- **One source of color**: change the wallpaper (SUPER+W) and Waybar, Quickshell, rofi, kitty, the
  window borders and the lock screen all recolor from it.
- **Offline where possible**: the translator runs locally (CTranslate2 + Argos models); nothing is sent anywhere.
- **Windows-like keybinds**, because that's what my hands know.

## Keybinds

| Keys | Action |
| --- | --- |
| `SUPER + Q` | Terminal |
| `SUPER + E` | Files |
| `SUPER + R` | App launcher |
| `SUPER + C` | Close window |
| `SUPER + A` | Dashboard |
| `SUPER + V` | Clipboard history |
| `SUPER + W` | Wallpaper picker (Tab: desktop / lock screen) |
| `SUPER + T` | Translator (ES ↔ EN) |
| `SUPER + B` | FC Barcelona |
| `SUPER + L` | Lock |
| `SUPER + Z` / `SUPER + SHIFT + Z` | Maximize / fullscreen |
| `SUPER + SHIFT + S` | Region screenshot to clipboard |
| `SUPER + S` | Scratchpad |

## Install

Arch-based system, Hyprland 0.55+ (Lua config). Managed with GNU Stow:

```sh
git clone <this repo> ~/workspace/dotfiles
cd ~/workspace/dotfiles
./setup.sh                      # checks packages, links configs, generates colors
./setup.sh translator agenda    # optional extras
```

`setup.sh` never runs `sudo`. It prints the `pacman` command for anything missing and
stops if a real file is in the way of a link, so nothing gets overwritten.

## How I built it

I built this step by step, testing every change on my own machine. I used
[Claude](https://claude.ai) as a helper along the way, to explain things, check the
official docs with me and write parts of the code. The decisions about what to build, how it should look and how strict the security rules should be are mine.
