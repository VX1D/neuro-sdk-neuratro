_G.NEURO_TEST = true
love = { timer = { getTime = function() return 0 end } }
G = { TIMERS = {} }

local check, done = require("tests.helpers").harness("hand-transaction-architecture")
local H = require("tests.helpers")
local ActionResult = require("core.action_result")
local HandTx = require("core.hand_transaction")
local Evidence = require("core.confirmation_evidence")
local HH = require("handlers.hand_handlers")
local Actions = require("core.actions")

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", decision_serial = 7, run_generation = 2, enabled = true }
G.FUNCS.get_poker_hand_info = function(cards)
  return "Pair", {}, { Pair = { cards } }, cards
end

local _, proposal_error = HH.handle_play_hand({ indices = { 1, 2 } })
local proposal = ActionResult.normalize(proposal_error)
local tx = HandTx.current()
check("proposal creates one publishing transaction", tx ~= nil and tx.phase == "publishing")
check("confirmation candidate carries the transaction identity",
  proposal.confirmation_candidate ~= nil
    and proposal.confirmation_candidate.transaction_id == tx.id)

check("delivery promotion is the only publishing-to-ready transition",
  Evidence.stage(proposal.confirmation_candidate, proposal.message, { status = "written" })
    and Evidence.step_delivery()
    and tx.phase == "ready")
check("ready exposes only resolve_play",
  Actions.get_valid_actions_for_state("SELECTING_HAND")[1] == "resolve_play"
    and #Actions.get_valid_actions_for_state("SELECTING_HAND") == 1)

local before_epoch = G.NEURO.hand_decision.epoch
local before_serial = G.NEURO.decision_serial
local stale, stale_error = HH.handle_play_hand({ indices = { 1, 2 } })
check("same play while ready is policy-acknowledged and non-mutating",
  stale == nil and stale_error.reason_code == "POLICY_ACKNOWLEDGED"
    and tx.phase == "ready")
local discard, discard_error = HH.handle_discard_hand({ indices = { 1 } })
check("discard is also blocked by resolution mode",
  discard == nil and discard_error.reason_code == "POLICY_ACKNOWLEDGED"
    and tx.phase == "ready")
check("stale mutators do not advance either decision counter",
  G.NEURO.hand_decision.epoch == before_epoch and G.NEURO.decision_serial == before_serial)

local wrong, wrong_error = HH.handle_resolve_play({ transaction_id = tx.id + 1, answer = "yes" })
check("wrong transaction id cannot commit the current transaction",
  wrong == nil and wrong_error.reason_code == "POLICY_ACKNOWLEDGED"
    and HandTx.current() == tx and tx.phase == "ready")

local cancel = HH.handle_resolve_play({ transaction_id = tx.id, answer = "no" })
local cancel_outcome = type(cancel) == "function" and cancel()
check("matching no terminates the transaction at execution",
  type(cancel) == "function" and cancel_outcome.status == "applied" and HandTx.current() == nil)
check("no increments hand epoch exactly once and not gameplay serial",
  G.NEURO.hand_decision.epoch == before_epoch + 1
    and G.NEURO.decision_serial == before_serial)
check("no spends the only review for the unchanged hand",
  HandTx.final_play_required())
local reasonless_decline = HandTx.decline_context()
check("reason remains optional and the declined selection is still remembered",
  reasonless_decline and reasonless_decline.reason == nil
    and reasonless_decline.transaction_id == tx.id
    and table.concat(reasonless_decline.indices, ",") == "1,2")

local played_final = false
G.FUNCS.play_cards_from_highlighted = function() played_final = true end
local same_again, same_again_error = HH.handle_play_hand({ indices = { 1, 2 } })
check("live-loop regression: the exact repeated play is a final executable command",
  type(same_again) == "function" and same_again_error == nil and HandTx.current() == nil)
local final_outcome = same_again()
check("the final command reaches gameplay instead of another successful no-op force",
  played_final and type(final_outcome) == "string")

HandTx.observe_context_changed()
check("meaningful context change restores a future hand's review budget",
  not HandTx.final_play_required())

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 8, run_generation = 2, enabled = true }
local _, alternate_error = HH.handle_play_hand({ indices = { 1, 2 } })
local alternate_proposal = ActionResult.normalize(alternate_error)
Evidence.stage(alternate_proposal.confirmation_candidate, alternate_proposal.message,
  { status = "written" })
Evidence.step_delivery()
local alternate_tx = HandTx.current()
local raw_decline_reason = "  discard indices 3,4 toward Straight\nnow  "
local alternate_no = HH.handle_resolve_play({ transaction_id = alternate_tx.id, answer = "no",
  reason = raw_decline_reason })
alternate_no()
local remembered = HandTx.decline_context()
check("model-authored reason is retained exactly in decision state",
  G.NEURO.hand_decision.last_decline.reason == raw_decline_reason)
check("optional no reason is normalized and scoped to the declined transaction",
  remembered and remembered.reason == "discard indices 3,4 toward Straight now"
    and remembered.transaction_id == alternate_tx.id
    and remembered.hand_type == "Pair")
local final_force = require("force.force_selecting_hand").build()
check("the post-no force repeats full decision rules and marks the action site final",
  final_force and final_force.query:find("Rules:", 1, true)
    and final_force.query:find("FINAL PLAY CHOICE", 1, true)
    and HandTx.final_play_required())
check("the post-no force preserves the model's decision continuity",
  final_force.query:find("indices [1,2] = Pair", 1, true)
    and final_force.query:find("discard indices 3,4 toward Straight now", 1, true)
    and final_force.query:find("call discard_hand now", 1, true)
    and final_force.query:find("call play_hand now", 1, true))
local rebuilt_final_force = require("force.force_selecting_hand").build()
check("a prompt rebuild does not erase the decline memory",
  rebuilt_final_force.query:find("discard indices 3,4 toward Straight now", 1, true)
    and HandTx.decline_context() ~= nil)
G.NEURO.hand_decision.last_decline.reason = string.rep("x", 700)
local bounded_echo = HandTx.decline_context()
check("only the prompt echo is bounded; accepted decision prose is not schema-bounded",
  bounded_echo and #bounded_echo.reason == 600
    and bounded_echo.reason:sub(-3) == "...")
G.NEURO.hand_decision.last_decline.reason = raw_decline_reason
local alternate_final, alternate_final_error = HH.handle_play_hand({ indices = { 1, 3 } })
check("live-loop regression: a different post-no selection is also final",
  type(alternate_final) == "function" and alternate_final_error == nil
    and HandTx.current() == nil)

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 8, run_generation = 2, enabled = true }
local _, changed_error = HH.handle_play_hand({ indices = { 1, 2 } })
local changed_proposal = ActionResult.normalize(changed_error)
Evidence.stage(changed_proposal.confirmation_candidate, changed_proposal.message,
  { status = "written" })
Evidence.step_delivery()
local changed_tx = HandTx.current()
HH.handle_resolve_play({ transaction_id = changed_tx.id, answer = "no" })()
G.hand.cards[1].ability.extra = { context_changed = true }
local changed_play, changed_play_error = HH.handle_play_hand({ indices = { 1, 3 } })
check("a real hand-context change re-arms exactly one review",
  changed_play == nil and ActionResult.is_error(changed_play_error)
    and changed_play_error.reason_code == "CONFIRMATION_REQUIRED"
    and HandTx.current() ~= nil)
check("a real context change clears stale decline memory",
  HandTx.decline_context() == nil)

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 9, run_generation = 3, enabled = true }
local played_after_invalidation = false
G.FUNCS.play_cards_from_highlighted = function() played_after_invalidation = true end
local _, race_error = HH.handle_play_hand({ indices = { 1, 2 } })
local race_proposal = ActionResult.normalize(race_error)
Evidence.stage(race_proposal.confirmation_candidate, race_proposal.message, { status = "written" })
Evidence.step_delivery()
local race_tx = HandTx.current()
local race_exec = HH.handle_resolve_play({ transaction_id = race_tx.id,
  answer = "yes", _action_id = "race" })
check("yes reserves the ready transaction", type(race_exec) == "function"
  and race_tx.phase == "committing")
G.hand.cards[1].ability.extra = { changed = true }
HandTx.observe_context_changed()
local race_outcome = race_exec()
check("invalidated committing transaction cannot execute captured gameplay",
  played_after_invalidation == false and race_outcome.status == "failed")

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 11, run_generation = 4, enabled = true,
  actions = Actions }
local _, wire_error = HH.handle_play_hand({ indices = { 1, 2 } })
local wire_proposal = ActionResult.normalize(wire_error)
Evidence.stage(wire_proposal.confirmation_candidate, wire_proposal.message, { status = "written" })
Evidence.step_delivery()
local wire_tx = HandTx.current()
local Registry = require("core.action_registry")
Registry.reset()
Registry.note_registered({ "resolve_play" })
local ForceState = require("core.force_state")
ForceState.arm("SELECTING_HAND", { "resolve_play" }, { resolve_play = true }, 100)
ForceState.mark_sent(100)
local wire_result
local bridge = {
  send_action_result = function(_, id, ok, message, reason)
    wire_result = { id = id, ok = ok, message = message, reason = reason }
    return true, { status = "written" }
  end,
}
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "injected-plan", name = "resolve_play", data = {
    transaction_id = wire_tx.id, answer = "yes", plan = { boss_plan = "injected" },
  } } }, bridge)
check("resolve_play ingress rejects an injected plan",
  wire_result and wire_result.ok == false and wire_result.reason == "SCHEMA_INVALID"
    and HandTx.current() == wire_tx and wire_tx.phase == "ready",
  wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)
    .. "/" .. tostring(wire_tx.phase)) or "no result")
local epoch_before_failed_no = G.NEURO.hand_decision.epoch
local failing_bridge = {
  send_action_result = function() return false, { status = "rejected" } end,
}
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "failed-no-delivery", name = "resolve_play", data = {
    transaction_id = wire_tx.id, answer = "no",
  } } }, failing_bridge)
check("failed no result delivery leaves the transaction ready and uncancelled",
  HandTx.current() == wire_tx and wire_tx.phase == "ready"
    and G.NEURO.hand_decision.epoch == epoch_before_failed_no)
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "failed-yes-delivery", name = "resolve_play", data = {
    transaction_id = wire_tx.id, answer = "yes",
  } } }, failing_bridge)
check("failed yes result delivery rolls its reservation back to ready",
  HandTx.current() == wire_tx and wire_tx.phase == "ready",
  tostring(HandTx.current() == wire_tx) .. "/" .. tostring(wire_tx.phase))
wire_result = nil
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "missing-transaction", name = "resolve_play", data = { answer = "no" } } }, bridge)
check("missing transaction_id is wire-acknowledged without mutation",
  wire_result and wire_result.ok == true and wire_result.reason == "POLICY_ACKNOWLEDGED"
    and HandTx.current() == wire_tx and wire_tx.phase == "ready",
  (wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)) or "no result")
    .. "/" .. tostring(HandTx.current() == wire_tx) .. "/" .. tostring(wire_tx.phase))
local plan_tx, plan_error = require("core.plan_transaction").prepare("resolve_play",
  { transaction_id = wire_tx.id, answer = "yes", plan = { boss_plan = "injected" } })
check("plan layer independently rejects resolve_play plan creation",
  plan_tx == nil and ActionResult.is_error(plan_error))

wire_result = nil
local delivered_no = HH.handle_resolve_play({ transaction_id = wire_tx.id, answer = "no" })
local delivered_no_outcome = type(delivered_no) == "function" and delivered_no()
check("a delivered no arms the final current-force choice",
  delivered_no_outcome and delivered_no_outcome.status == "applied"
    and HandTx.current() == nil and HandTx.final_play_required())
Registry.note_registered({ "play_hand" })
ForceState.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 101)
ForceState.mark_sent(101)
local unowned_played = false
G.FUNCS.play_cards_from_highlighted = function() unowned_played = true end
local unowned_bridge = {
  is_force_answer = function() return false end,
  send_action_result = function(_, id, ok, message, reason)
    wire_result = { id = id, ok = ok, message = message, reason = reason }
    return true, { status = "written" }
  end,
}
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "canonical-injection", name = "play_hand", data = {
    indices = { 1, 2 },
  } } }, unowned_bridge)
check("an unowned canonical play cannot steal the post-no direct commit",
  wire_result and wire_result.ok == true and wire_result.reason == "POLICY_ACKNOWLEDGED"
    and not unowned_played and HandTx.final_play_required())

local Config = require("core.config")
Config.set("NEURO_CONFIRM_HAND", "on")
H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 20,
  decision_serial = 20, run_generation = 20, enabled = true }
local _, f8_pub_err = HH.handle_play_hand({ indices = { 1, 2 } })
local f8_pub = HandTx.current()
check("F8 fixture opens a publishing transaction", f8_pub_err and f8_pub ~= nil
  and f8_pub.phase == "publishing")
Config.set("NEURO_CONFIRM_HAND", "off")
check("F8 OFF invalidates publishing transaction and releases its pointer",
  HandTx.current() == nil and f8_pub.phase == "invalidated")
local direct = HH.handle_play_hand({ indices = { 1, 2 } })
check("play_hand becomes direct after F8 OFF", type(direct) == "function")

Config.set("NEURO_CONFIRM_HAND", "on")
local _, f8_ready_err = HH.handle_play_hand({ indices = { 1, 3 } })
local f8_ready = HandTx.current()
Evidence.stage(f8_ready_err.confirmation_candidate, f8_ready_err.message, { status = "written" })
Evidence.step_delivery()
Config.set("NEURO_CONFIRM_HAND", "off")
check("F8 OFF invalidates a delivered ready transaction",
  HandTx.current() == nil and f8_ready.phase == "invalidated"
    and Evidence.current() == nil)

Config.set("NEURO_CONFIRM_HAND", "on")
local _, f8_commit_err = HH.handle_play_hand({ indices = { 2, 3 } })
local f8_commit = HandTx.current()
Evidence.stage(f8_commit_err.confirmation_candidate, f8_commit_err.message, { status = "written" })
Evidence.step_delivery()
local f8_exec = HH.handle_resolve_play({ transaction_id = f8_commit.id,
  answer = "yes", _action_id = "f8-commit" })
Config.set("NEURO_CONFIRM_HAND", "off")
check("F8 OFF preserves an already accepted committing transaction",
  HandTx.current() == f8_commit and f8_commit.phase == "committing"
    and type(f8_exec) == "function")

done()
