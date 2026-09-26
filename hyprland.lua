-- ~/.config/hypr/hyprland.lua
-- Entry point: only loads modules. Each module handles one concern.
-- Relative requires use "." as separator (official wiki recommendation).

require("modules.env")
require("modules.monitors")
require("modules.autostart")
require("modules.look")
require("modules.input")
require("modules.binds")
require("modules.rules")
