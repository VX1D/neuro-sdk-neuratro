require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("ack-reason-taxonomy")

local Enforce = require("tests.helpers").enforce()
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local ActionReceipt = require("core.action_result")
local ActionResult = require("core.action_result")
local Protocol = require("core.bridge").wire
local Helpers = require("tests.helpers")

local play_card = require("tests.helpers").play_card

local tarot = require("tests.fake_cards").fool

local function selecting_hand_env() require("tests.helpers").selecting_hand_env() end

local shop_env = require("tests.helpers").shop_env

local function run_stream(state_name, action, payload, count)
  if state_name == "SHOP" then shop_env() else selecting_hand_env() end
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = state_name, state_enter_serial = 1, run_generation = 7,
    transport_session = "ack-reason-taxonomy", transport_epoch = 1 }
  local log = {}
  local bridge = Helpers.stub_bridge({
    send_action_result = Helpers.result_log(log, { "id", "ok", "message", "code" }),
    send_context = "true", register_actions = "noop", is_transition_cooldown = "false",
  })
  require("core.bridge").tx.reset()
  Helpers.stage_registered(nil, { action })
  for i = 1, count do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    G.NEURO.force_window = nil
    if state_name == "SHOP" then G.consumeables.cards = { tarot() } end
    require("tests.helpers").open_force(state_name, { action })
    Dispatcher.handle_message(Helpers.inbound_action(action,
      state_name .. "-" .. action .. "-" .. i, payload), bridge)
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

  local all_ok, all_at = all_of(log, 1, SENDS, function(entry)
    return entry.ok == false and entry.code == case.code
  end)
  check(label .. ": every send stays unsuccessful and keeps its class: there is no retry budget",
    all_ok, "send " .. tostring(all_at) .. " -> "
      .. tostring(log[all_at] and log[all_at].code) .. "/"
      .. tostring(log[all_at] and log[all_at].ok))

  local no_overwrite = all_of(log, 1, SENDS, function(entry)
    return entry.code ~= "POLICY_ACKNOWLEDGED"
  end)
  check(label .. ": the acknowledgement never overwrites the class with POLICY_ACKNOWLEDGED",
    no_overwrite, tostring(log[SENDS] and log[SENDS].code))

  check(label .. ": the last refusal says what the first one said",
    log[SENDS].message:find(log[1].message, 1, true) ~= nil,
    tostring(log[SENDS] and log[SENDS].message))
end

do
  local log = run_stream("SELECTING_HAND", "play_hand", '{"indices":[1,2,99]}', SENDS)
  local frame = Protocol.result(log[SENDS].id, log[SENDS].ok, log[SENDS].message)
  local first = Protocol.result(log[1].id, log[1].ok, log[1].message)
  check("the class rides beside the frame, never inside it -- the model reads id/success/message",
    frame.data.reason_code == nil and frame.reason_code == nil
      and frame.data.success == false
      and frame.data.message:find(first.data.message, 1, true) ~= nil,
    tostring(frame.data.message))
  check("the first refusal was unsuccessful too",
    first.data.success == false, tostring(first.data.success))
end

do
  check("the code alone still decides -- SCHEMA_INVALID is retried even in a force",
    ActionResult.terminal("SCHEMA_INVALID", true) == false)
  check("a policy acknowledgement is terminal in or out of a force",
    ActionResult.terminal("POLICY_ACKNOWLEDGED", false) == true
      and ActionResult.terminal("POLICY_ACKNOWLEDGED", true) == true)
  check("a wait is terminal only as the answer to the open force",
    ActionResult.terminal("TRANSITION_PENDING", true) == true
      and ActionResult.terminal("TRANSITION_PENDING", false) == false)
end

done()
