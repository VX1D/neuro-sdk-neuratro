require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("ack-reason-taxonomy")

local Enforce = require("tests.helpers").enforce()
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local ActionReceipt = require("core.action_result")
local ActionResult = require("core.action_result")
local Protocol = require("core.bridge").wire
local Helpers = require("tests.helpers")

local STREAK_FAILURES = 3

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

  check(label .. ": terminal prose preserves the refusal",
    log[SENDS].message:find(log[1].message, 1, true) ~= nil,
    tostring(log[SENDS] and log[SENDS].message))
end

local SUCCESS_MESSAGE_MAX = require("tests.helpers").SUCCESS_MESSAGE_MAX
do
  local worst, worst_case, offenders = 0, nil, {}
  for _, case in ipairs(CASES) do
    for _, entry in ipairs(run_stream(case.state, case.action, case.payload, SENDS)) do
      local text = entry.ok and entry.message or nil
      if type(text) == "string" then
        if #text > worst then worst, worst_case = #text, case.tag end
        if #text > SUCCESS_MESSAGE_MAX then
          offenders[#offenders + 1] = case.tag .. " (" .. #text .. ")"
        end
      end
    end
  end
  check("a successful result stays small (SPECIFICATION.md:189)",
    #offenders == 0,
    string.format("max %d bytes on %s; budget %d; over: %s", worst, tostring(worst_case),
      SUCCESS_MESSAGE_MAX, table.concat(offenders, ", ")))
end

do
  local log = run_stream("SELECTING_HAND", "play_hand", '{"indices":[1,2,99]}', SENDS)
  local frame = Protocol.result(log[SENDS].id, log[SENDS].ok, log[SENDS].message)
  local first = Protocol.result(log[1].id, log[1].ok, log[1].message)
  check("the class rides beside the frame, never inside it -- the model reads id/success/message",
    frame.data.reason_code == nil and frame.reason_code == nil
      and frame.data.success == true
      and frame.data.message:find(first.data.message, 1, true) ~= nil,
    tostring(frame.data.message))
  check("the same message before the streak was unsuccessful",
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
