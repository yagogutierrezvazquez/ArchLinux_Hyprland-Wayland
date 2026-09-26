-- Shared program names.
-- Lua `local` variables do NOT leak between files, so instead of globals
-- this module returns a table that other modules require().
return {
    terminal    = "kitty",
    fileManager = "dolphin",
    menu        = "rofi -show drun",
}
