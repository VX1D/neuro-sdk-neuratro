_G.NEURO_TEST = true
require("tests.stubs").setup({ love = "timers" })
local check, done = require("tests.helpers").harness("persona-memory")
local Config = require("core.config")
local saved = {}
Config.init({ settings = saved, colours = {} }, function() return true end)
_G.G = { NEURO = { persona = "hiyori" }, FUNCS = {}, GAME = {} }
local Dispatcher = require("core.dispatcher")
local State = require("core.state")
local real_state_name = State.get_state_name
local screen = "SPLASH"
State.get_state_name = function() return screen end

local function ack(character)
  Dispatcher.route_message({ command = "startup", data = { session = { characterId = character } } }, G.NEURO)
end

Dispatcher.recall_persona()
check("with nothing remembered, she still has to choose a persona", G.NEURO.persona == "hiyori", G.NEURO.persona)

ack("evil")
check("an acknowledgement before the menu shows is remembered", Config.get_raw("NEURO_SERVER_CHARACTER") == "evil")
check("and she stays logged out until the menu", G.NEURO.persona == "hiyori", G.NEURO.persona)

screen = "MENU"
Dispatcher.recall_persona()
check("at the menu she logs in as that character", G.NEURO.persona == "evil", G.NEURO.persona)
check("with the login animation from hiyori", G.NEURO.login_anim ~= nil and G.NEURO.login_anim.from == "hiyori")

G.NEURO.persona, G.NEURO.login_anim = "hiyori", nil
screen = "SPLASH"
Dispatcher.recall_persona()
screen = "MENU"
Dispatcher.recall_persona()
check("a relaunch with no acknowledgement logs in as the remembered character", G.NEURO.persona == "evil", G.NEURO.persona)

G.NEURO.login_anim = nil
ack("neuro")
check("a later acknowledgement for the other twin switches the persona", G.NEURO.persona == "neuro", G.NEURO.persona)
check("and replaces the remembered character", Config.get_raw("NEURO_SERVER_CHARACTER") == "neuro")

State.get_state_name = real_state_name
done()
