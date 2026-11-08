-- Environment variables (plain launch, no uwsm).
-- If you move to uwsm later, these go to ~/.config/uwsm/env instead.

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Qt: Wayland first, X11 fallback (official wiki recommendation)
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- XDG session identity: helps portals pick the right backend
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Xwayland apps look pixelated with fractional scaling: stop upscaling them
-- and let each toolkit scale itself (Java/Swing: Burp Suite)
hl.config({ xwayland = { force_zero_scaling = true } })
hl.env("_JAVA_OPTIONS", "-Dsun.java2d.uiScale=1.5")
