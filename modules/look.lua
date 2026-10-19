-- Window look: borders, rounding, blur, animations.
-- Colors come from the wallpaper (matugen writes ../colors.lua on every
-- wallpaper change, then runs `hyprctl reload`).
local ok, colors = pcall(require, "colors")
if not ok then
    colors = { accent = "rgb(7aa2f7)", inactive = "rgb(2a2a2a)" }   -- matugen's fallback
end

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = colors.accent,      -- wallpaper accent, like Waybar's islands
            inactive_border = colors.inactive,    -- tinted dark, barely there
        },
        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },
    decoration = {
        rounding = 12,   -- same radius as Waybar's islands
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        -- Soft, wide shadow: depth without a visible edge. Lighter when unfocused.
        shadow = {
            enabled        = true,
            range          = 20,
            render_power   = 3,
            color          = 0x99000000,   -- ARGB
            color_inactive = 0x55000000,
        },
        -- Frosted glass behind see-through windows (kitty) and menus.
        -- Only shows where a window is transparent; solid apps are unaffected.
        blur = {
            enabled   = true,
            size      = 8,      -- radius per pass
            passes    = 3,      -- more passes = smoother, not just bigger
            noise     = 0.02,   -- a little grain hides color banding
            vibrancy  = 0.2,    -- keep some of the wallpaper's color
            popups    = true,   -- right-click menus too
        },
    },
    animations = {
        enabled = true,
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

-- Animations: short and snappy (same feel as Quickshell's ~200 ms easing).
-- speed is in deciseconds (4 = 400 ms). Wiki: Configuring/Advanced-and-Cool/Animations
hl.curve("outQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("linear",   { type = "bezier", points = { {0, 0},    {1, 1}    } })
-- Critically damped spring: fast settle, no wobble
hl.curve("snappy",   { type = "spring", mass = 1, stiffness = 300, dampening = 34.6 })

hl.animation({ leaf = "global",        enabled = true,  speed = 6,   bezier = "outQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4,   spring = "snappy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4,   spring = "snappy", style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.5, bezier = "linear", style = "popin 90%" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 2.5, bezier = "outQuint" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.5, bezier = "linear" })
hl.animation({ leaf = "border",        enabled = true,  speed = 3,   bezier = "outQuint" })
hl.animation({ leaf = "borderangle",   enabled = false })
hl.animation({ leaf = "layers",        enabled = true,  speed = 2.5, bezier = "outQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5, bezier = "linear",   style = "fade" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 3.5, bezier = "outQuint", style = "slide" })
