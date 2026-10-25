require("tests.stubs").setup({ love = "zero" })
G = { TIMERS = {} }

local check, done = require("tests.helpers").harness("admission-paths")
local H = require("tests.helpers")
local ActionResult = require("core.action_result")
local Gate = require("core.gate")
local HH = require("handlers.hand_handlers")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx

local function neuro(serial)
  G.NEURO = H.started_bridge({ state = "SELECTING_HAND", state_enter_serial = 1, decision_serial = serial,
    run_generation = 2, enabled = true, persona = "neuro", dispatcher = Dispatcher, actions = Actions,
    register_actions = function() end, send_context = function() return true end })
end

local function send(id, name, payload)
  local b = H.fake_bridge({ reason = "reason_code" })
  assert(TxCache.open(id, name, G.TIMERS.REAL))
  Dispatcher.handle_message({ command = "action", data = { id = id, name = name, data = payload } }, b)
  return b.results[#b.results]
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 100 })
  neuro(1)
  H.stage_registered("SELECTING_HAND", { "play_hand" })
  local top = send("int-1", "play_hand", '{"indices":[1,2],"_action_id":"forged"}')
  check("a top-level internal field is refused as SCHEMA_INVALID",
    top and top.ok == false and top.reason_code == "SCHEMA_INVALID",
    top and tostring(top.message))
  local nested = send("int-2", "play_hand", '{"indices":[1,2],"meta":{"_hidden":1}}')
  check("a nested internal field is named by its path",
    nested and nested.ok == false and nested.reason_code == "SCHEMA_INVALID"
      and tostring(nested.message):find("'parameters.meta._hidden'", 1, true) ~= nil,
    nested and tostring(nested.message))
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 200 })
  neuro(5)
  H.stage_registered("SELECTING_HAND", { "play_hand", "resolve_play" })
  local _, review = HH.handle_play_hand({ indices = { 1, 2 } })
  Gate.delivered(ActionResult.normalize(review))
  HH.handle_resolve_play({ answer = "no" })()
  check("precondition: the declined review leaves a final play choice", Gate.final_play_required())
  local ok, message, _, code = H.pre_action("play_hand", { indices = { 1, 2 } })
  check("a play_hand outside the final-choice force is admitted", ok == true, tostring(code) .. " " .. tostring(message))
  local exec, err = Dispatcher.preflight("play_hand", { indices = { 1, 2 } })
  check("and commits as the final choice instead of opening another review",
    type(exec) == "function" and err == nil, tostring(err and (err.reason_code or err)))
  H.open_force("SELECTING_HAND", { "play_hand" })
  local forced_ok, _, _, forced_code = H.pre_action("play_hand", { indices = { 1, 2 } })
  check("the same play_hand answering that force gets the same answer",
    forced_ok == ok and forced_code == code, tostring(forced_ok) .. " " .. tostring(forced_code))
  G.NEURO.force_window = nil
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 300 })
  neuro(9)
  local _, review = HH.handle_play_hand({ indices = { 1, 2 } })
  Gate.delivered(ActionResult.normalize(review))
  local tx = Gate.proposal()
  check("precondition: the review opened a proposal", tx ~= nil and Gate.begin_commit(tx) and tx.phase == "committing")
  check("a still-valid committing proposal rolls back to ready", Gate.rollback_commit(tx) == true and tx.phase == "ready")
  Gate.begin_commit(tx)
  G.NEURO.decision_serial = G.NEURO.decision_serial + 1
  check("a committing proposal that no longer holds is not rolled back", Gate.rollback_commit(tx) == false)
  check("it is closed as invalidated instead", tx.phase == "invalidated" and Gate.proposal() == nil, tostring(tx.phase))
end

done()
