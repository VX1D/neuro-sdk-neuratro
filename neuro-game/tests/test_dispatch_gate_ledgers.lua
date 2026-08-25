_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("dispatch-gate-ledgers")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Lifecycle = require("core.neuro_lifecycle")
local TxCache = require("core.tx_cache")

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t)
  require("tests.helpers").selecting_hand_env({ time = t, reset_tx_cache = true })
end

local function bridge()
  local b = { emitted = {}, registered = 0, results = {} }
  function b:send_context(msg) self.emitted[#self.emitted + 1] = tostring(msg) return true end
  function b:send_action_result(id, ok, message, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason = reason }
  end
  b.register_actions = function() b.registered = b.registered + 1 end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

do
  selecting_hand_env(100)
  local permanent = {}
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1,
    send_context = function(_, msg) permanent[#permanent + 1] = tostring(msg) return true end }
  local b = bridge()
  Dispatcher._test.execute_action({ id = "g03-1", name = "play_hand", data = {},
    exec = function() error("boom") end, bridge = b }, b)
  check("an execution throw records the readable reason, not the phase token",
    G.NEURO.last_failed_reason == "action did not apply", tostring(G.NEURO.last_failed_reason))
  check("the failed action name is recorded with it",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))

  local warning = require("force.force_helpers").failed_action_warning()
  check("the force warning quotes the readable failure, not a phase token",
    type(warning) == "string"
      and warning:find("Previous action rejected by game: play_hand", 1, true) ~= nil
      and warning:find("failed during execution", 1, true) ~= nil, tostring(warning))
  check("and never the bare phase token",
    type(warning) == "string" and warning:find("(failed)", 1, true) == nil, tostring(warning))

  check("finalize_failed's imperative rides the force query",
    warning:find("Inspect the current state and choose again", 1, true) ~= nil, tostring(warning))
  check("and neither the bridge nor G.NEURO gets it as permanent context",
    #b.emitted == 0 and #permanent == 0,
    table.concat(b.emitted, " | ") .. " || " .. table.concat(permanent, " | "))
end

do
  selecting_hand_env(200)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  Dispatcher._test.execute_action({ id = "g03-2", name = "play_hand", data = {},
    exec = function() return 42 end, bridge = b }, b)
  check("a result with no execution evidence records the ambiguous sentence",
    G.NEURO.last_failed_reason == "execution outcome is ambiguous",
    tostring(G.NEURO.last_failed_reason))
end

do
  selecting_hand_env(300)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, state = "SHOP" }
  local b = bridge()
  local Outcome = require("core.action_receipt").outcome
  Dispatcher._test.execute_action({ id = "t36-1", name = "reroll_shop", data = {},
    exec = function() return Outcome("applied") end, bridge = b }, b)
  check("a successful reroll_shop no longer writes a local shop_reroll_count",
    G.NEURO.shop_reroll_count == nil, tostring(G.NEURO.shop_reroll_count))
end

local function reregister(b, session)
  Dispatcher.route_message({ command = "actions/reregister_all", transport_session = session }, b)
end

local function loaded_ledger()
  G.NEURO.once_serials = { ["gloss:readable_common"] = "session" }
  G.NEURO.rules_ctx_sig = "FRAME|old"
  G.NEURO.run_ctx_sig = "run-old"
  G.NEURO.vouchers_ctx_sig = "vouchers-old"
  G.NEURO.stable_ctx_sig = "tail-old"
  G.NEURO.stable_sig_cheap = "cheap-old"
  G.NEURO.stable_refresh_due = false
end

local function ledger_is_reopened()
  return next(G.NEURO.once_serials or {}) == nil
end

do
  selecting_hand_env(300)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 4, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  loaded_ledger()
  reregister(b, 1)
  check("a duplicate transport session re-opens the delivery ledger anyway (#212)",
    ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("but leaves the run generation alone",
    G.NEURO.run_generation == 4, tostring(G.NEURO.run_generation))
  check("the duplicate is still answered with a registration", b.registered >= 1, b.registered)

  loaded_ledger()
  Dispatcher.route_message({ command = "actions/reregister_all" }, b)
  check("an unstamped server request re-opens the ledger too",
    ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("and still leaves the generation alone", G.NEURO.run_generation == 4,
    tostring(G.NEURO.run_generation))

  loaded_ledger()
  reregister(b, 2)
  check("a NEW transport session re-opens the whole stable context",
    ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("a NEW transport session voids the run generation",
    G.NEURO.run_generation == 5, tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(350)
  G.NEURO = { enabled = true, decision_serial = 1, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  reregister(b, 2)
  check("a run with no generation does not acquire one on reconnect",
    G.NEURO.run_generation == nil, tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(400)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 7, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  reregister(b, 2)
  check("the reconnect bumped the generation and closed the offer with it",
    G.NEURO.run_generation == 8 and G.NEURO.force_generation == nil,
    tostring(G.NEURO.run_generation) .. "/" .. tostring(G.NEURO.force_generation))

  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, G.TIMERS.REAL)
  FS.mark_sent(G.TIMERS.REAL)
  G.NEURO.force_generation = 7
  Dispatcher.route_message({ command = "action", run_generation = 8,
    data = { id = "gen-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local last = b.results[#b.results]
  check("an answer to a question asked in a dead generation is refused as stale",
    last and last.reason == "STALE_GENERATION", last and tostring(last.reason) or "none")

  G.NEURO.force_generation = G.NEURO.run_generation
  Dispatcher.route_message({ command = "action", run_generation = 3,
    data = { id = "gen-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local fresh = b.results[#b.results]
  check("and the frame's own stamp decides nothing -- a forged stale one still passes",
    fresh and fresh.reason ~= "STALE_GENERATION", fresh and tostring(fresh.reason) or "none")
end

do
  local TD = require("tests.test_deadlock")
  local scenario
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SHOP" and sc.desc:find("toggle_shop must survive", 1, true) then scenario = sc end
  end
  check("the shop fixture the correction test needs is present", scenario ~= nil)
  if scenario then
    G.TIMERS.REAL = 500
    G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
      dispatcher = Dispatcher, actions = Actions, reserved_dollars = 0, shop_reroll_count = 0,
      _decision_windows = {}, _reservation_epoch = 0 }
    TD.apply_mock(scenario.mock())
    G.STATES = { SHOP = 2 }
    G.STATE = 2
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.GAME.dollars = 0
    G.NEURO.shop_entry_dollars = 12
    G.NEURO.shop_visit_epoch = 1
    require("core.transition_guard").reset()
    Enforce.reset_run_state()

    local b = bridge()
    local ok_gate, _, _, code = Enforce.pre_action(b, "toggle_shop", nil)
    check("the decision window refuses toggle_shop", ok_gate ~= true and code == "CONFIRMATION_REQUIRED",
      tostring(code))
    local correction = tostring(Enforce.take_correction())
    check("the correction lead does not say wasn't applied when confirmation required",
      correction:find("wasn't applied", 1, true) == nil
        and correction:find("toggle_shop needs its pending confirmation resolved first", 1, true) ~= nil, correction)
    check("and it names nothing beyond that past event",
      correction:find("Actions you can take now", 1, true) == nil, correction)
    local extra = 0
    for _, def in ipairs(Actions.get_valid_actions_for_state("SHOP") or {}) do
      if def ~= "toggle_shop" and correction:find(def, 1, true) then extra = extra + 1 end
    end
    check("no other callable action leaks into the retained frame", extra == 0, correction)
  end
end

do
  selecting_hand_env(600)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  check("the first send passes the gate",
    Enforce.pre_action(b, "discard_hand", '{"indices":[1]}') == true)
  local ok_second, err_second = Enforce.pre_action(b, "discard_hand", '{"indices":[2]}')
  check("an immediate second send is billed the cooldown",
    ok_second ~= true, tostring(err_second))
end

do
  selecting_hand_env(700)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  check("the send that will be rejected below the gate passes it first",
    Enforce.pre_action(b, "discard_hand", '{"indices":[1]}') == true)
  Enforce.rollback_action()
  local ok_retry, err_retry = Enforce.pre_action(b, "discard_hand", '{"indices":[2]}')
  check("after the rollback the next send is not billed for it",
    ok_retry == true, tostring(err_retry))
end

do
  selecting_hand_env(800)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  Enforce.pre_action(b, "discard_hand", '{"indices":[1]}')
  Enforce.rollback_action()
  Enforce.rollback_action()
  local ok_third = Enforce.pre_action(b, "discard_hand", '{"indices":[2]}')
  check("a second rollback is a no-op, not a second refund of an older stamp",
    ok_third == true)
  local ok_fourth = Enforce.pre_action(b, "discard_hand", '{"indices":[3]}')
  check("the stamp the accepted send left still bills the one after it", ok_fourth ~= true)
end

do
  selecting_hand_env(900)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 3, llm_paused = true,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "action did not apply"
  G.NEURO.last_failed_at = G.TIMERS.REAL - 1000
  Dispatcher.route_message({ command = "action", run_generation = 3,
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local last = b.results[#b.results]
  check("the paused answer goes out acknowledged",
    last and last.reason == "TRANSITION_ACKNOWLEDGED", last and tostring(last.reason) or "none")
  check("the unresolved warning survives the pause",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
  check("with its reason", G.NEURO.last_failed_reason == "action did not apply",
    tostring(G.NEURO.last_failed_reason))
end

do
  selecting_hand_env(1000)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 3,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "action did not apply"
  G.NEURO.last_failed_at = G.TIMERS.REAL - 1000
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, G.TIMERS.REAL)
  FS.mark_sent(G.TIMERS.REAL)
  G.NEURO.force_generation = 1
  Dispatcher.route_message({ command = "action",
    data = { id = "verdict-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local last = b.results[#b.results]
  check("an acknowledged answer that IS a verdict still goes out",
    last and last.reason == "STALE_GENERATION", last and tostring(last.reason) or "none")
  check("but STALE_GENERATION is lifecycle-neutral and does not retire the warning",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
end

do
  selecting_hand_env(1100)
  G.NEURO = { enabled = true, run_generation = 11 }
  local Receipt = require("core.action_receipt")
  local cleaned = false
  Receipt.create({
    id = "generation-owned-receipt", name = "play_hand", run_generation = 11,
    started_at = 1100, deadline = 1200, probe = function() return "pending" end,
    cleanup = function() cleaned = true end,
  })
  check("bump_run_generation returns the new value",
    Lifecycle.bump_run_generation() == 12 and G.NEURO.run_generation == 12,
    tostring(G.NEURO.run_generation))
  check("bump_run_generation itself invalidates old transport work",
    cleaned and not Receipt.has_active())
  G.NEURO.run_generation = nil
  check("it refuses to invent a generation from nothing",
    Lifecycle.bump_run_generation() == nil and G.NEURO.run_generation == nil,
    tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(1200)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  Enforce.reset_run_state()
  Enforce.take_correction() -- drain anything stray so the first check below is not a false positive

  Enforce.pre_action(b, "not_a_real_action_n3f7", {})
  local first = Enforce.take_correction()
  check("send_correction: the first refusal stages a correction",
    type(first) == "string" and first ~= "", tostring(first))

  G.TIMERS.REAL = G.TIMERS.REAL + 0.01
  Enforce.pre_action(b, "not_a_real_action_n3f7", {})
  local second = Enforce.take_correction()
  check("send_correction: a second refusal inside the refresh cooldown stages nothing",
    second == nil, tostring(second))

  G.TIMERS.REAL = G.TIMERS.REAL + 1.0
  Enforce.pre_action(b, "not_a_real_action_n3f7", {})
  local third = Enforce.take_correction()
  check("send_correction: a refusal after the cooldown elapses stages a correction again",
    type(third) == "string" and third ~= "", tostring(third))
end

do
  selecting_hand_env(1300)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 9,
    joker_bought_cost = { j_joker = 6 } }
  Lifecycle.reset_run_state()
  check("lifecycle: joker_bought_cost does not leak across a run reset",
    G.NEURO.joker_bought_cost == nil, tostring(G.NEURO.joker_bought_cost))
end

done()
