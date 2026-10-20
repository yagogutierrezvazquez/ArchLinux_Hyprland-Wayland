local p = require("modules.programs")
local mainMod = "SUPER"

-- Apps
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(p.terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(p.fileManager))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(p.menu))

-- Window management
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Maximize (keeps Waybar + gaps) / true fullscreen (covers everything)
hl.bind(mainMod .. " + Z",         hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

-- Exit Hyprland
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.exit()'"))

-- Focus with arrows
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mainMod .. " + " .. dir, hl.dsp.focus({ direction = dir }))
end

-- Workspaces 1-10 (key 0 = workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + CTRL + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Mouse: drag to move / resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop keys (work even on lock screen: locked = true)
local keyOpts = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), keyOpts)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), keyOpts)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), keyOpts)
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), keyOpts)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), keyOpts)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), keyOpts)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Screenshots (grim + slurp + wl-copy; files go to Pictures/Screenshots)
local shots = '"$(xdg-user-dir PICTURES)/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"'
hl.bind(mainMod .. " + SHIFT + S",
    hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy && notify-send "Screenshot" "Region copied to clipboard"'))
hl.bind("SHIFT + Print",
    hl.dsp.exec_cmd('grim -g "$(slurp)" ' .. shots .. ' && notify-send "Screenshot" "Region saved"'))
hl.bind(mainMod .. " + Print",
    hl.dsp.exec_cmd('grim ' .. shots .. ' && notify-send "Screenshot" "Full screen saved"'))

-- Clipboard history (like Windows Win+V): Quickshell panel, Enter pastes
-- into the previous window (hypr/scripts/clip-list.sh, clip-paste.sh)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))

-- Dashboard (Quickshell): clock, calendar, stats, media, controls, power (like Win+A)
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs ipc call dashboard toggle"))

-- Wallpaper carousel (Quickshell -> hyprpaper -> matugen colors).
-- Fallback rofi picker: ~/.config/rofi/scripts/wallpaper.sh
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("qs ipc call wallpapers toggle"))

-- FC Barcelona matches: ~/.config/quickshell/Barca.qml
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("qs ipc call barca toggle"))
-- Offline Spanish <-> English translator: ~/.config/quickshell/Translator.qml
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("qs ipc call translator toggle"))
