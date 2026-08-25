_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("ack-reason-taxonomy")

local Enforce = require("core.enforce")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local ActionReceipt = require("core.action_receipt")
local ActionResult = require("core.action_result")
local Protocol = require("core.bridge_protocol")
local Helpers = require("tests.helpers")

local STREAK_FAILURES = 3

local play_card = require("tests.helpers").play_card

local function tarot()
  return {
    sort_id = "c_fool", sell_cost = 1,
    ability = { set = "Tarot", name = "The Fool", consumeable = true },
    config = { center = { key = "c_fool", set = "Tarot", loc_txt = { name = "The Fool" } } },
    juice_up = function() end, highlight = function() end,
  }
end

local function selecting_hand_env() require("tests.helpers").selecting_hand_env() end

local function shop_env()
  G.TIMERS.REAL = 100
  G.STATES = { SHOP = 5 }
  G.STATE = 5
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = { dollars = 10, used_vouchers = {}, round_resets = { ante = 2 },
    current_round = {}, modifiers = {} }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = { tarot() }, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } }
  G.deck = { cards = {} }
  G.shop_jokers = { cards = {} }
  G.FUNCS = { sell_card = function() end }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
end

local function run_stream(state_name, action, payload, count)
  if state_name == "SHOP" then shop_env() else selecting_hand_env() end
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = state_name, state_enter_serial = 1 }
  local log = {}
  local bridge = {
    send_action_result = function(_, id, ok, message, code)
      log[#log + 1] = { id = id, ok = ok, message = message, code = code }
    end,
    send_context = function() end,
    register_actions = function() end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
  require("core.tx_cache").reset()
  Helpers.stage_registered(nil, { action })
  for i = 1, count do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    G.NEURO.force_inflight = false
    ActionReceipt.reset("stream")
    if state_name == "SHOP" then G.consumeables.cards = { tarot() } end
    FS.arm(state_name, { action }, { [action] = true }, 1)
    Dispatcher.handle_message({ command = "action",
      data = { id = state_name .. "-" .. action .. "-" .. i, name = action, data = payload } }, bridge)
  end
  return log
end

local function all_of(log, from, to, predicate)
  for i = from, to do
    if not predicate(log[i], i) then return false, i end
  end
  return true
end

local CASES = {
  { tag = "T1", code = "SCHEMA_INVALID", state = "SELECTING_HAND", action = "play_hand",
    payload = '{"indices":[1,2,3,4,5,6]}' },
  { tag = "T2", code = "INVALID_SELECTION", state = "SELECTING_HAND", action = "play_hand",
    payload = '{"indices":[1,2,99]}' },
  { tag = "T3", code = "PRECONDITION_FAILED", state = "SHOP", action = "sell_card",
    payload = '{"area":"consumeables","index":1}' },
}

local SENDS = 8

for _, case in ipairs(CASES) do
  local log = run_stream(case.state, case.action, case.payload, SENDS)
  local label = case.tag .. " (" .. case.code .. ")"

  check(label .. ": every send in the stream is answered", #log == SENDS, #log)

  local pre_ok, pre_at = all_of(log, 1, STREAK_FAILURES, function(entry)
    return entry.ok == false and entry.code == case.code
  end)
  check(label .. ": below the streak the answer stays unsuccessful and keeps its class",
    pre_ok, "send " .. tostring(pre_at) .. " -> "
      .. tostring(log[pre_at] and log[pre_at].code) .. "/"
      .. tostring(log[pre_at] and log[pre_at].ok))

  local post_ok, post_at = all_of(log, STREAK_FAILURES + 1, SENDS, function(entry)
    return entry.ok == true and entry.code == case.code
  end)
  check(label .. ": past the streak the answer is successful and STILL carries its class",
    post_ok, "send " .. tostring(post_at) .. " -> "
      .. tostring(log[post_at] and log[post_at].code) .. "/"
      .. tostring(log[post_at] and log[post_at].ok))

  local no_overwrite = all_of(log, 1, SENDS, function(entry)
    return entry.code ~= "POLICY_ACKNOWLEDGED"
  end)
  check(label .. ": the acknowledgement never overwrites the class with POLICY_ACKNOWLEDGED",
    no_overwrite, tostring(log[SENDS] and log[SENDS].code))

  check(label .. ": terminal prose explicitly says nothing executed and preserves the refusal",
    log[SENDS].message:find("Nothing was executed", 1, true) ~= nil
      and log[SENDS].message:find(log[1].message, 1, true) ~= nil,
    tostring(log[SENDS] and log[SENDS].message))
end

do
  local log = run_stream("SELECTING_HAND", "play_hand", '{"indices":[1,2,99]}', SENDS)
  local frame = Protocol.sanitize_for_wire(
    Protocol.result(log[SENDS].id, log[SENDS].ok, log[SENDS].message))
  local first = Protocol.sanitize_for_wire(
    Protocol.result(log[1].id, log[1].ok, log[1].message))
  check("the class rides beside the frame, never inside it -- the model reads id/success/message",
    frame.data.reason_code == nil and frame.reason_code == nil
      and frame.data.success == true
      and frame.data.message:find(first.data.message, 1, true) ~= nil,
    tostring(frame.data.message))
  check("the same message before the streak was unsuccessful",
    first.data.success == false, tostring(first.data.success))
end

do
  check("the code alone still decides -- SCHEMA_INVALID does not acknowledge",
    ActionResult.acknowledges("SCHEMA_INVALID") == false)
  check("the per-send flag is what acknowledges, beside the unchanged code",
    ActionResult.acknowledges("INVALID_SELECTION", { acknowledged = true }) == true)
  check("an absent or false flag leaves the code's own verdict alone",
    ActionResult.acknowledges("INVALID_SELECTION", { acknowledged = false }) == false
      and ActionResult.acknowledges("INVALID_SELECTION", {}) == false
      and ActionResult.acknowledges("POLICY_ACKNOWLEDGED", { acknowledged = false }) == true)
  check("an invalid payload can be terminally acknowledged with explicit prose",
    ActionResult.acknowledges("SCHEMA_INVALID", { acknowledged = true }) == true)
end

done()
