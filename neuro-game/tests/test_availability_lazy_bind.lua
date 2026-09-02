love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {} }

local ActionRegistry = require("core.action_registry")
require("core.actions")
local check, done = require("tests.helpers").harness("availability-lazy-bind")

check("dispatcher not preloaded", package.loaded["core.dispatcher"] == nil)

G.GAME = {
  dollars = 10,
  current_round = { hands_left = 3, discards_left = 2 },
  round_resets = { ante = 1, blind_choices = {}, blind_states = {} },
}
G.jokers = { cards = {}, config = { card_limit = 5 } }
G.consumeables = { cards = {}, config = { card_limit = 2 } }
G.shop_jokers = { cards = {} }
G.shop_vouchers = { cards = {} }
G.shop_booster = { cards = {} }
G.STATES = { SHOP = 1, BLIND_SELECT = 2 }
G.STATE = 1
G.hand = { cards = {}, config = { card_limit = 5, highlighted_limit = 5 } }

local warnings = {}
local real_print = print
_G.print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local msg = table.concat(parts, " ")
  if msg:find("overwriting availability", 1, true) then warnings[#warnings + 1] = msg end
end
local empty_sell = ActionRegistry.available("sell_card")
_G.print = real_print

check("sell_card: empty roster -> unavailable without an explicit dispatcher require",
  empty_sell == false, tostring(empty_sell))
check("lazy require bound the predicate, no overwrite warning",
  #warnings == 0, warnings[1])
check("dispatcher loaded on demand", package.loaded["core.dispatcher"] ~= nil)

check("buy_from_shop: empty shop -> unavailable",
  ActionRegistry.available("buy_from_shop") == false)
check("select_blind: nothing selectable -> unavailable",
  ActionRegistry.available("select_blind") == false)

G.jokers.cards = { { ability = {}, cost = 3, sell_cost = 1 } }
check("sell_card: card present -> available", ActionRegistry.available("sell_card") == true)

check("unknown action stays false", ActionRegistry.available("no_such_action") == false)
check("action with no predicate anywhere stays true", ActionRegistry.available("record_plan") == true)

warnings = {}
_G.print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local msg = table.concat(parts, " ")
  if msg:find("overwriting availability", 1, true) then warnings[#warnings + 1] = msg end
end
ActionRegistry.bind_availability("test_action", function() return true end)
_G.print = real_print
check("the first explicit availability binding emits no overwrite warning", #warnings == 0)
_G.print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local msg = table.concat(parts, " ")
  if msg:find("overwriting availability", 1, true) then warnings[#warnings + 1] = msg end
end
ActionRegistry.bind_availability("test_action", function() return false end)
_G.print = real_print
check("overwriting an availability predicate emits one warning naming the action",
  #warnings == 1 and warnings[1]:find("test_action", 1, true) ~= nil, warnings[1])

done()
