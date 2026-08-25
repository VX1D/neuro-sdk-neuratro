_G.NEURO_TEST = true
_G.localize = function() return "Death" end
local check, done = require("tests.helpers").harness("directional-card")
local Registry = require("core.action_registry")
require("core.dispatcher")
local Directional = require("handlers.directional_card")
local UseCard = require("handlers.use_card")

local left, right = { label = "left" }, { label = "right" }
local hand = { cards = { left, right }, highlighted = {} }
function hand:add_to_highlighted(card) card.highlighted = true; self.highlighted[#self.highlighted + 1] = card end
function hand:remove_from_highlighted(card) card.highlighted = false end
local death = {
  sort_id = 50, ability = { set = "Tarot", name = "Death",
    consumeable = { min_highlighted = 2, max_highlighted = 2 } },
  config = { center = { key = "c_death", set = "Tarot", name = "Death" } },
  can_use_consumeable = function() return true end,
}
local used
_G.G = {
  NEURO = {}, GAME = {}, hand = hand, consumeables = { cards = { death } },
  FUNCS = { use_card = function() used = { hand.highlighted[1], hand.highlighted[2] }; return true end },
}

local schema = Registry.get("use_directional_card").schema
check("wire schema requires both directional roles and target identity",
  table.concat(schema.required, ","):find("name", 1, true)
    and table.concat(schema.required, ","):find("left_index", 1, true)
    and table.concat(schema.required, ","):find("right_index", 1, true))
check("candidate generation does not choose semantic targets for Neuro",
  #Registry.candidates("use_directional_card") == 0)
local exec, err = UseCard.handle_use_card({ area = "consumeables", index = 1, hand_indices = { 1, 2 } })
check("ordinary use_card cannot bypass a directional contract", exec == nil and err.reason_code == "INVALID_SELECTION")
exec, err = Directional.handle({ area = "consumeables", index = 1, name = "Death", left_index = 2, right_index = 1 })
check("reversed roles fail live validation", exec == nil and err.reason_code == "INVALID_SELECTION")
exec, err = Directional.handle({ area = "consumeables", index = 1, name = "The Hermit", left_index = 1, right_index = 2 })
check("required name protects a shifted source row", exec == nil and err.reason_code == "STALE_TARGET")
exec, err = Directional.handle({ area = "consumeables", index = 1, name = "Death", left_index = 1, right_index = 2 })
check("valid directional selection prepares an execution closure", type(exec) == "function", err)
local message = exec and exec()
check("execution highlights the exact prepared objects in role order", used and used[1] == left and used[2] == right)
check("successful direct execution stays terse", message == "Used: Death", message)
done()
