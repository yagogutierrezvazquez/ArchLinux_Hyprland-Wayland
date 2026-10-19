-- Window look: borders, rounding, blur, animations.
-- Colors come from the wallpaper (matugen writes ../colors.lua on every
-- wallpaper change, then runs `hyprctl reload`).
local ok, colors = pcall(require, "colors")
if not ok then
    colors = { accent = "rgb(7aa2f7)" }   -- same fallback as matugen's config
end

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = colors.accent,      -- wallpaper accent, like Waybar's islands
            inactive_border = "rgba(2a2a2aff)",   -- dark grey, barely there on black
        },
        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },
    decoration = {
        rounding = 12,   -- same radius as Waybar's islands
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size    = 3,
            passes  = 1,
        },
    },
    animations = {
        enabled = true,  -- built-in defaults; custom curves come later
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper = 0,     -- no mascot wallpapers
        disable_hyprland_logo   = true,
    	disable_splash_rendering = true, -- no random quote text on the background
    },
})
