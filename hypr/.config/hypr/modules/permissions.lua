-- Hyprland permission system (from the official example config).
-- Changes here need a FULL Hyprland restart (log out/in), not a reload,
-- on purpose: a hot reload would let a compromised process rewrite its own permissions.

hl.config({
    ecosystem = {
        enforce_permissions = true,
    },
})

-- Screen capture: only these binaries may read the screen directly
hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
