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

    -- Phase 4 will add: notification daemon, cliphist
end)
