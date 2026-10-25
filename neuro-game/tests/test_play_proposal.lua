require("tests.stubs").setup({ love = "zero" })
G = { TIMERS = {} }

local check, done = require("tests.helpers").harness("play-proposal")
local H = require("tests.helpers")
local ActionResult = require("core.action_result")
local Gate = require("core.gate")
local HH = require("handlers.hand_handlers")
local Actions = require("core.actions")
local json = require("util.neuro_json")
H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", decision_serial = 7, run_generation = 2, enabled = true }
G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").stub("Pair")

local _, proposal_error = HH.handle_play_hand({ indices = { 1, 2 } })
local proposal = ActionResult.normalize(proposal_error)
check("an undelivered review opens no proposal", proposal.reason_code == "CONFIRMATION_REQUIRED"
  and Gate.proposal() == nil)
Gate.delivered(proposal)
local tx = Gate.proposal()
check("delivery opens the proposal awaiting its answer", tx ~= nil and tx.phase == "ready"
  and tx.verdict == proposal.message)
check("ready exposes only resolve_play",
  Actions.get_valid_actions_for_state("SELECTING_HAND")[1] == "resolve_play"
    and #Actions.get_valid_actions_for_state("SELECTING_HAND") == 1)

local before_serial = G.NEURO.decision_serial
local stale, stale_error = HH.handle_play_hand({ indices = { 1, 2 } })
check("same play while ready is policy-acknowledged and non-mutating",
  stale == nil and stale_error.reason_code == "POLICY_ACKNOWLEDGED"
    and tx.phase == "ready")
local discard, discard_error = HH.handle_discard_hand({ indices = { 1 } })
check("discard is also blocked by resolution mode",
  discard == nil and discard_error.reason_code == "POLICY_ACKNOWLEDGED"
    and tx.phase == "ready")
check("stale mutators do not advance the decision serial", G.NEURO.decision_serial == before_serial)

check("the structured confirmation does not expose a transaction id",
  proposal.transaction_id == nil and proposal.proposal.transaction_id == nil)

local cancel = HH.handle_resolve_play({ answer = "no" })
local cancel_outcome = type(cancel) == "function" and cancel()
check("matching no terminates as an applied terminal non-mutating outcome",
  type(cancel) == "function" and cancel_outcome.status == "applied"
    and cancel_outcome.details and cancel_outcome.details.terminal_class == "DECLINED_NOOP"
    and cancel_outcome.details.state_mutated == false
    and Gate.proposal() == nil,
  cancel_outcome and (tostring(cancel_outcome.status) .. "/"
    .. tostring(cancel_outcome.details and cancel_outcome.details.terminal_class)) or "none")
check("no does not advance the gameplay serial", G.NEURO.decision_serial == before_serial)
check("no spends the only review for the unchanged hand",
  Gate.final_play_required())
local reasonless_decline = Gate.decline_context()
check("the declined selection is remembered",
  reasonless_decline and table.concat(reasonless_decline.indices, ",") == "1,2")

local played_final = false
G.FUNCS.play_cards_from_highlighted = function() played_final = true end
local same_again, same_again_error = HH.handle_play_hand({ indices = { 1, 2 }, _action_id = "final-1" })
check("live-loop regression: the exact repeated play is a final executable command",
  type(same_again) == "function" and same_again_error == nil and Gate.proposal() == nil)
local final_outcome = same_again()
check("the final command reaches gameplay instead of another successful no-op force",
  played_final and require("core.action_result").is_receipt(final_outcome))

Gate.observe_context_changed()
check("meaningful context change restores a future hand's review budget",
  not Gate.final_play_required())

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 8, run_generation = 2, enabled = true }
local _, alternate_error = HH.handle_play_hand({ indices = { 1, 2 } })
local alternate_proposal = ActionResult.normalize(alternate_error)
Gate.delivered(alternate_proposal)
local alternate_no = HH.handle_resolve_play({ answer = "no" })
alternate_no()
local remembered = Gate.decline_context()
check("the decline memory is scoped to the declined proposal",
  remembered and remembered.hand_type == "Pair")
require("force.force_selecting_hand").build()
check("a prompt rebuild does not erase the decline memory", Gate.decline_context() ~= nil)
local alternate_final, alternate_final_error = HH.handle_play_hand({ indices = { 1, 3 } })
check("live-loop regression: a different post-no selection is also final",
  type(alternate_final) == "function" and alternate_final_error == nil
    and Gate.proposal() == nil)

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 8, run_generation = 2, enabled = true }
local _, changed_error = HH.handle_play_hand({ indices = { 1, 2 } })
local changed_proposal = ActionResult.normalize(changed_error)
Gate.delivered(changed_proposal)
HH.handle_resolve_play({ answer = "no" })()
G.hand.cards[1].ability.extra = { context_changed = true }
local changed_play, changed_play_error = HH.handle_play_hand({ indices = { 1, 3 } })
Gate.delivered(changed_play_error)
check("a real hand-context change re-arms exactly one review",
  changed_play == nil and ActionResult.is_error(changed_play_error)
    and changed_play_error.reason_code == "CONFIRMATION_REQUIRED"
    and Gate.proposal() ~= nil)
check("a real context change clears stale decline memory",
  Gate.decline_context() == nil)

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 9, run_generation = 3, enabled = true }
local played_after_invalidation = false
G.FUNCS.play_cards_from_highlighted = function() played_after_invalidation = true end
local _, race_error = HH.handle_play_hand({ indices = { 1, 2 } })
local race_proposal = ActionResult.normalize(race_error)
Gate.delivered(race_proposal)
local race_tx = Gate.proposal()
local race_exec = HH.handle_resolve_play({
  answer = "yes", _action_id = "race" })
check("yes reserves the ready transaction", type(race_exec) == "function"
  and race_tx.phase == "committing")
G.hand.cards[1].ability.extra = { changed = true }
Gate.observe_context_changed()
local race_outcome = race_exec()
check("invalidated committing transaction cannot execute captured gameplay",
  played_after_invalidation == false and race_outcome.status == "failed")

H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 11, run_generation = 4, enabled = true,
  actions = Actions, register_actions = function() end }
local _, wire_error = HH.handle_play_hand({ indices = { 1, 2 } })
local wire_proposal = ActionResult.normalize(wire_error)
Gate.delivered(wire_proposal)
local wire_tx = Gate.proposal()
local Registry = require("core.action_registry")
Registry.reset()
Registry.note_registered({ "resolve_play" })
require("tests.helpers").open_force("SELECTING_HAND", { "resolve_play" })
local wire_result
local bridge = {
  send_action_result = function(_, id, ok, message, reason)
    wire_result = {
      id = id, ok = ok, message = message, reason = reason,
    }
    return true, { status = "written" }
  end,
}
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "legacy-transaction-id", name = "resolve_play",
    data = json.encode({ transaction_id = 2, answer = "yes" }) } }, bridge)
check("legacy transaction-id ingress is rejected without touching the internal proposal",
  wire_result and wire_result.ok == false and wire_result.reason == "SCHEMA_INVALID"
    and Gate.proposal() == wire_tx and wire_tx.phase == "ready",
  wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)
    .. "/" .. tostring(wire_tx.phase)) or "no result")
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "injected-plan", name = "resolve_play",
    data = json.encode({ answer = "yes", plan = { boss_plan = "injected" } }) } }, bridge)
check("resolve_play ingress rejects an injected plan",
  wire_result and wire_result.ok == false and wire_result.reason == "SCHEMA_INVALID"
    and Gate.proposal() == wire_tx and wire_tx.phase == "ready",
  wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)
    .. "/" .. tostring(wire_tx.phase)) or "no result")
local failing_bridge = {
  send_action_result = function() return false, { status = "rejected" } end,
}
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "failed-no-delivery", name = "resolve_play", data = json.encode({ answer = "no" }) } },
  failing_bridge)
check("failed admission delivery preserves the ready reservation",
  Gate.proposal() == wire_tx and wire_tx.phase == "ready" and not Gate.final_play_required(),
  tostring(Gate.proposal() == wire_tx) .. "/" .. tostring(wire_tx.phase))
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "failed-yes-delivery", name = "resolve_play", data = json.encode({ answer = "yes" }) } },
  failing_bridge)
check("failed admission delivery cannot restore or alter the ready reservation",
  Gate.proposal() == wire_tx and wire_tx.phase == "ready",
  tostring(Gate.proposal() == wire_tx) .. "/" .. tostring(wire_tx.phase))
wire_result = nil
require("core.dispatcher").route_message({ command = "action", run_generation = 4,
  data = { id = "missing-transaction", name = "resolve_play", data = json.encode({ answer = "no" }) } },
  bridge)
check("missing confirmation identity is admitted then corrected without mutation",
  wire_result and wire_result.ok == true and wire_result.reason == "ACTION_ACCEPTED"
    and Gate.proposal() == nil and wire_tx.phase == "cancelled",
  (wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)) or "no result")
    .. "/" .. tostring(Gate.proposal() == wire_tx) .. "/" .. tostring(wire_tx.phase))
local plan_tx, plan_error = require("core.plan_transaction").prepare("resolve_play",
  { answer = "yes", plan = { boss_plan = "injected" } })
check("plan layer independently rejects resolve_play plan creation",
  plan_tx == nil and ActionResult.is_error(plan_error))

wire_result = nil
local _, final_proposal_error = HH.handle_play_hand({ indices = { 1, 2 } })
local final_proposal = ActionResult.normalize(final_proposal_error)
Gate.delivered(final_proposal)
local delivered_no = HH.handle_resolve_play({ answer = "no" })
local delivered_no_outcome = type(delivered_no) == "function" and delivered_no()
check("a cancelled confirmation leaves the final current-force choice armed",
  Gate.proposal() == nil and Gate.final_play_required(),
  tostring(delivered_no) .. "/" .. tostring(delivered_no_outcome and delivered_no_outcome.status)
    .. "/" .. tostring(Gate.proposal()) .. "/" .. tostring(Gate.final_play_required()))
Registry.note_registered({ "play_hand" })
require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
local unowned_played = false
G.FUNCS.play_cards_from_highlighted = function() unowned_played = true end
local unowned_bridge = {
  is_force_answer = function() return false end,
  send_action_result = function(_, id, ok, message, reason)
    wire_result = {
      id = id, ok = ok, message = message, reason = reason,
    }
    return true, { status = "written" }
  end,
}
require("core.dispatcher").route_message(H.inbound_action("play_hand",
  "canonical-injection", { indices = { 1, 2 } }), unowned_bridge)
check("an unowned canonical play is admitted but remains non-mutating",
  wire_result and wire_result.ok == true
    and wire_result.reason == "ACTION_ACCEPTED"
    and not unowned_played and Gate.final_play_required(),
  (wire_result and (tostring(wire_result.ok) .. "/" .. tostring(wire_result.reason)
    .. "/" .. tostring(wire_result.message)) or "no result")
    .. "/" .. tostring(unowned_played) .. "/" .. tostring(Gate.final_play_required()))

local Config = require("core.config")
Config.set("NEURO_CONFIRM_HAND", "on")
H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 20,
  decision_serial = 20, run_generation = 20, enabled = true, register_actions = function() end }
local _, f8_pub_err = HH.handle_play_hand({ indices = { 1, 2 } })
check("F8 fixture: an undelivered review opens nothing", f8_pub_err and Gate.proposal() == nil)
Config.set("NEURO_CONFIRM_HAND", "off")
local direct = HH.handle_play_hand({ indices = { 1, 2 } })
check("play_hand becomes direct after F8 OFF", type(direct) == "function")

Config.set("NEURO_CONFIRM_HAND", "on")
local _, f8_ready_err = HH.handle_play_hand({ indices = { 1, 3 } })
Gate.delivered(f8_ready_err)
local f8_ready = Gate.proposal()
Config.set("NEURO_CONFIRM_HAND", "off")
check("F8 OFF invalidates a delivered ready transaction",
  Gate.proposal() == nil and f8_ready.phase == "invalidated")

Config.set("NEURO_CONFIRM_HAND", "on")
local _, f8_commit_err = HH.handle_play_hand({ indices = { 2, 3 } })
Gate.delivered(f8_commit_err)
local f8_commit = Gate.proposal()
local f8_exec = HH.handle_resolve_play({ answer = "yes", _action_id = "f8-commit" })
Config.set("NEURO_CONFIRM_HAND", "off")
check("F8 OFF preserves an already accepted committing transaction",
  Gate.proposal() == f8_commit and f8_commit.phase == "committing"
    and type(f8_exec) == "function")

local Dispatcher = require("core.dispatcher")
local Staging = require("core.staging")
Dispatcher.reset_run_state()
Staging.reset_run_state()
Config.set("NEURO_CONFIRM_HAND", "on")
H.selecting_hand_env({ reset_tx_cache = true })
G.NEURO = { state = "SELECTING_HAND", state_enter_serial = 1,
  decision_serial = 9, run_generation = 3, enabled = true, actions = Actions }
local committed_plays = 0
G.FUNCS.play_cards_from_highlighted = function() committed_plays = committed_plays + 1 end
local _, late_proposal_error = HH.handle_play_hand({ indices = { 1, 2 } })
local late_proposal = ActionResult.normalize(late_proposal_error)
Gate.delivered(late_proposal)
Registry.reset()
Registry.note_registered({ "resolve_play" })
require("tests.helpers").open_force("SELECTING_HAND", { "resolve_play" })
local late_results = {}
local late_bridge = {
  send_action_result = function(_, id, ok, message, reason)
    late_results[id] = {
      ok = ok, message = message, reason = reason,
    }
    return true, { status = "written" }
  end,
}
Dispatcher.route_message(H.inbound_action("resolve_play", "accepted-yes", { answer = "yes" }), late_bridge)
for i = 1, 100 do
  G.TIMERS.REAL = 100 + i * 0.05
  G.TIMERS.TOTAL = G.TIMERS.REAL
  Staging.update()
end
require("core.execute").step(108)
check("accepted yes reaches gameplay exactly once and reports a correction",
  committed_plays == 1 and late_results["accepted-yes"]
    and late_results["accepted-yes"].ok == true
    and late_results["accepted-yes"].reason == "ACTION_ACCEPTED"
,
  late_results["accepted-yes"] and (tostring(late_results["accepted-yes"].ok) .. "/"
    .. tostring(late_results["accepted-yes"].reason)) or "no result")
Dispatcher.route_message(H.inbound_action("resolve_play", "late-no",
  { answer = "no", reason = "Discard the other cards instead" }), late_bridge)
check("a later no with a different action id cannot undo the committed play",
  late_results["late-no"] ~= nil and committed_plays == 1 and Gate.decline_context() == nil)

done()
