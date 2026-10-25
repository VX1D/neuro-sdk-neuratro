require("tests.stubs").setup({ love = "zero" })
local ES = require("tests.engine_cards").states()
local H = require("tests.helpers")
local check, done = H.harness("refusal text contract")
local Registry = require("core.action_registry")

local function card(id)
  return { sort_id = id, cost = 4, sell_cost = 3, ability = { name = id, set = "Joker" },
    config = { center = { key = id, set = "Joker", loc_txt = { name = id } } } }
end
G = { STATE = ES.SHOP, STATES = ES,
  NEURO = { state = "SHOP", state_enter_serial = 3, run_generation = 1, decision_serial = 7, shop_visit_epoch = 2,
    plan = {}, joker_intents = { Alpha = { tag = "CORE" }, Beta = { tag = "CORE" } } },
  GAME = { dollars = 30, current_round = {}, round_resets = {}, used_vouchers = {} },
  jokers = { cards = { card("Alpha"), card("Beta") }, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {} }, shop_jokers = { cards = {} }, shop_booster = { cards = {} },
  FUNCS = { toggle_shop = function() end }, P_CENTERS = {}, shop = { cards = {} } }
Registry.reset(); require("core.bridge").tx.reset(); require("core.window").reset()
local OFFER = { "set_joker_order", "leave_shop", "buy_from_shop" }
H.stage_registered("SHOP", OFFER)

local seen = {}
local bridge = H.stub_bridge({ send_action_result = function(_, id, success, message, code)
    seen[#seen + 1] = { id = id, success = success, message = tostring(message), code = code }; return true, { status = "written" } end,
  send_context = "noop", register_actions = "noop", is_transition_cooldown = "false", withdraw_actions = "true" })

local n = 0
local function send(name, raw)
  n = n + 1
  local id = "r-" .. n
  local set = {}
  for _, a in ipairs(OFFER) do set[a] = true end
  G.NEURO.force_window = { id = id, phase = "forced", state = "SHOP", names = OFFER, set = set, sent_at = 0 }
  seen = {}
  require("core.dispatcher").handle_message({ command = "action", data = { id = id, name = name, data = raw } }, bridge)
  return seen[1] or {}
end

for _, raw in ipairs({ "{bad", "[1,2]", '"x"' }) do
  local r = send("set_joker_order", raw)
  local msg = tostring(r.message)
  check("malformed " .. raw .. ": the refusal names the fields a valid payload carries",
    r.success == false and msg:find("from_index", 1, true) ~= nil and msg:find("to_index", 1, true) ~= nil, msg)
end
require("core.validate").reset_streaks()

local spent
for _ = 1, 5 do spent = send("set_joker_order", "{}") end
check("a repeated missing field is still refused with success=false and names the fields",
  spent.success == false and tostring(spent.message):find("from_index", 1, true) ~= nil, tostring(spent.message))
require("core.validate").reset_streaks()
for _ = 1, 5 do spent = send("buy_from_shop", '{"area":"nowhere","index":1}') end
check("a repeated enum miss is still refused with success=false",
  spent.success == false and tostring(spent.message):find("shop_jokers", 1, true) ~= nil, tostring(spent.message))
require("core.validate").reset_streaks()

Registry.reset(); require("core.window").reset()
H.stage_registered("SHOP", OFFER)
Registry.note_unregistered({ "leave_shop" })
local gone = send("leave_shop", "{}")
check("a recently unregistered action is refused as unregistered", gone.code == "ACTION_UNREGISTERED", tostring(gone.message))

done()
