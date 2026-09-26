-- Run `hyprctl monitors` to see your output name (laptop panels are usually eDP-1).
-- Generic rule: any monitor, preferred resolution, auto position and scale.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})
