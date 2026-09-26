hl.config({
    input = {
        kb_layout    = "es",   -- Spanish keyboard
        follow_mouse = 1,
        sensitivity  = 0,      -- -1.0 to 1.0
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- 3-finger horizontal swipe switches workspaces
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})
