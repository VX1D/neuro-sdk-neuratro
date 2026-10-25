require("tests.stubs").setup({ love = "zero" })
local ES = require("tests.engine_cards").states()
local H = require("tests.helpers")
local check, done = H.harness("malformed-refusal")
local ActionResult = require("core.action_result")
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

local internal = ActionResult.internal_error().message
local n1 = ActionResult.normalize({ unexpected = true })
check("a table refusal without a code reads as the internal-error text", n1.message == internal, n1.message)
local n2 = ActionResult.normalize({ reason_code = "ACTION_REJECTED", message = { "x" } })
check("a coded refusal whose message is not text reads as the internal-error text", n2.message == internal, n2.message)
local n3 = ActionResult.normalize("Pick another slot.")
check("a string refusal keeps its text", n3.message == "Pick another slot." and n3.reason_code == "ACTION_REJECTED")

require("core.action_registry").reset(); require("core.bridge").tx.reset(); require("core.window").reset()
H.stage_registered("SHOP", { "set_joker_order" })
local seen = {}
local bridge = H.stub_bridge({ send_action_result = function(_, id, success, message, code)
    seen[#seen + 1] = { id = id, success = success, message = tostring(message), code = code }; return true, { status = "written" } end,
  send_context = "noop", register_actions = "noop", is_transition_cooldown = "false", withdraw_actions = "true" })

local function send(id, preflight)
  Registry.bind_preflight("set_joker_order", preflight)
  G.NEURO.force_window = { id = id, phase = "forced", state = "SHOP", names = { "set_joker_order" },
    set = { set_joker_order = true }, sent_at = 0 }
  H.dispatch("set_joker_order", id, '{"from_index":1,"to_index":2}', bridge)
  for _, r in ipairs(seen) do if r.id == id then return r end end
  return {}
end

local r1 = send("m-1", function() return nil, { oops = 1 } end)
check("a malformed refusal is answered with the internal-error text, not a table address",
  r1.success == false and r1.message == internal, tostring(r1.success) .. " " .. tostring(r1.message))
local r2 = send("m-2", function() return { not_a = "function" } end)
check("a non-function preflight result is refused before any success is sent",
  r2.success == false and r2.message == internal, tostring(r2.success) .. " " .. tostring(r2.message))
local r3 = send("m-3", function() return "go" end)
check("a string preflight result is refused too", r3.success == false and r3.message == internal,
  tostring(r3.success) .. " " .. tostring(r3.message))

done()
