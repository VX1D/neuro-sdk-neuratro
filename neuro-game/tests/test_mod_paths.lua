_G.NEURO_TEST = true
love = { filesystem = { getSaveDirectory = function() return "/save" end } }

local Paths = require("core.mod_paths")
local check, done = require("tests.helpers").harness("mod-paths")
local original_resolve = Paths.resolve_mod_path

Paths.resolve_mod_path = function() return "/save/Mods/neuro-game/" end
check("mod_relative strips the save-directory prefix",
  Paths.mod_relative("assets/test.png") == "Mods/neuro-game/assets/test.png")
check("cookie_path delegates to the shared relative-path owner",
  Paths.cookie_path() == "Mods/neuro-game/assets/cookie.png")

Paths.resolve_mod_path = function() return nil end
check("mod_relative preserves the installed-mod fallback",
  Paths.mod_relative("assets/test.png") == "Mods/neuro-game/assets/test.png")

Paths.resolve_mod_path = original_resolve
done()
