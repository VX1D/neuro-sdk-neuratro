_G.NEURO_TEST = true

local clock = 10
love = { timer = { getTime = function() return clock end } }

local check, done = require("tests.helpers").harness("transition-tracking")
local Bridge = require("core.bridge")

local name = "MENU"
local bridge = Bridge:new({ game = "Balatro", enabled = false })
bridge:set_state_name_provider(function() return name end)
bridge:update(0)
check("state-name provider still initializes transition tracking",
  bridge.last_state == "MENU" and bridge.last_transition_at == 10)

clock = 20
name = "SHOP"
bridge:update(0)
check("state-name provider still records later transitions",
  bridge.last_state == "SHOP" and bridge.last_transition_at == 20)
check("transition cooldown still observes the recorded transition", bridge:is_transition_cooldown())

done()
