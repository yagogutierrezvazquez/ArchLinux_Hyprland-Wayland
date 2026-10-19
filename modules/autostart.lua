-- Runs once when Hyprland starts (replaces the old `exec-once`).
hl.on("hyprland.start", function()
    -- Share Hyprland's environment (WAYLAND_DISPLAY, etc.) with systemd and D-Bus.
    -- Fixes the portal race we debugged: "Couldn't connect to a wayland compositor".
    -- Must run BEFORE starting any systemd user service below.
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")

    -- Polkit agent: password prompts for privilege elevation
    hl.exec_cmd("systemctl --user start hyprpolkitagent")

    -- Wallpaper daemon (config: ~/.config/hypr/hyprpaper.conf)
    hl.exec_cmd("hyprpaper")

    -- Status bar (config: ~/.config/waybar/)
    hl.exec_cmd("waybar")

    -- Quickshell (~/.config/quickshell/): dock, media popup, dashboard and the
    -- notification daemon. Started explicitly so D-Bus doesn't auto-activate
    -- another daemon (mako, Plasma's) on the first notification.
    hl.exec_cmd("qs")

    -- Clipboard history: watch every copy (text and images) and store it
    hl.exec_cmd("wl-paste --type text --watch $HOME/.config/hypr/scripts/cliphist-store.sh")
    hl.exec_cmd("wl-paste --type image --watch $HOME/.config/hypr/scripts/cliphist-store.sh")
end)
