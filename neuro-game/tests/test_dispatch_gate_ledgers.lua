require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("dispatch-gate-ledgers")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local Actions = require("core.actions")
local Lifecycle = require("core.neuro_lifecycle")
local TxCache = require("core.bridge").tx

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t)
  require("tests.helpers").selecting_hand_env({ time = t, reset_tx_cache = true })
end

local function bridge()
  return require("tests.helpers").fake_bridge({ reason = "reason", context = "emitted", register = "count", cooldown = true })
end

local Execute = require("core.execute")
local function admit(b, job)
  job.bridge, job.data, job.run_generation = b, job.data or {}, G.NEURO.run_generation
  Execute.admit(job, false)
end

do
  selecting_hand_env(100)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  admit(b, { id = "g03-1", name = "play_hand", exec = function() error("boom") end })
  check("an execution throw records the readable reason, not the phase token",
    G.NEURO.last_failed_reason == "action did not apply", tostring(G.NEURO.last_failed_reason))
  check("the failed action name is recorded with it",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
  check("an action that already answered success does not send a second result",
    #b.results == 1 and b.results[1].ok == true and b.results[1].reason == "ACTION_ACCEPTED",
    tostring(#b.results))
  local said = table.concat(b.emitted, " | ")
  check("the failure still reaches her, on the only channel left",
    said:find("did not complete successfully", 1, true) ~= nil, said)
end

do
  selecting_hand_env(200)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1 }
  local b = bridge()
  admit(b, { id = "g03-2", name = "play_hand", exec = function() return 42 end })
  check("a result with no execution evidence records the ambiguous sentence",
    G.NEURO.last_failed_reason == "execution outcome is ambiguous",
    tostring(G.NEURO.last_failed_reason))
end

local function reregister(b, session)
  if G and G.NEURO and type(G.NEURO.send_startup) ~= "function" then
    function G.NEURO:send_startup(_opts) return true end
  end
  Dispatcher.route_message({ command = "neuro-bridge/reregister_all", transport_session = session }, b)
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
  G.NEURO = require("tests.helpers").started_bridge({ enabled = true, decision_serial = 1, run_generation = 4, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions, _bridge_init_complete = true,
    register_actions = function() return true end })
  local b = bridge()
  loaded_ledger()
  reregister(b, 1)
  check("a duplicate transport session is idempotent after initialization",
    not ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("a duplicate leaves the run generation alone",
    G.NEURO.run_generation == 4, tostring(G.NEURO.run_generation))
  check("a duplicate does not fabricate a registration", b.registered == 0, b.registered)

  loaded_ledger()
  Dispatcher.route_message({ command = "neuro-bridge/reregister_all" }, b)
  check("an unstamped server request is ignored",
    not ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("an unstamped request leaves the generation alone", G.NEURO.run_generation == 4,
    tostring(G.NEURO.run_generation))

  loaded_ledger()
  reregister(b, 2)
  check("a NEW transport session keeps the stable context she already has (BEST_PRACTICES.md:45)",
    not ledger_is_reopened(), tostring(next(G.NEURO.once_serials or {})))
  check("a NEW transport session voids the run generation",
    G.NEURO.run_generation == 5, tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(350)
  G.NEURO = require("tests.helpers").started_bridge({ enabled = true, decision_serial = 1, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions, _bridge_init_complete = true,
    register_actions = function() return true end })
  local b = bridge()
  reregister(b, 2)
  check("a run with no generation does not acquire one on reconnect",
    G.NEURO.run_generation == nil, tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(400)
  G.NEURO = require("tests.helpers").started_bridge({ enabled = true, decision_serial = 1, run_generation = 7, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions, _bridge_init_complete = true,
    register_actions = function() return true end })
  local b = bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  reregister(b, 2)
  check("the reconnect bumped the generation and closed the offer with it",
    G.NEURO.run_generation == 8 and require("core.window").current() == nil,
    tostring(G.NEURO.run_generation))

  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  Dispatcher.route_message({ command = "action", run_generation = 3,
    data = { id = "gen-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local fresh = b.results[#b.results]
  check("and the frame's own stamp decides nothing",
    fresh and fresh.id == "gen-2" and fresh.reason ~= "STALE_GENERATION", fresh and tostring(fresh.reason) or "none")
end

do
  local TD = require("tests.test_deadlock")
  local scenario
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SHOP" and sc.desc:find("leave_shop must survive", 1, true) then scenario = sc end
  end
  check("the shop fixture the correction test needs is present", scenario ~= nil)
  if scenario then
    G.TIMERS.REAL = 500
    G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
      dispatcher = Dispatcher, actions = Actions, reserved_dollars = 0, shop_reroll_count = 0,
      _reservation_epoch = 0 }
    TD.apply_mock(scenario.mock())
    require("tests.helpers").in_scenario_state(scenario)
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.GAME.dollars = 0
    G.NEURO.shop_entry_dollars = 12
    G.NEURO.shop_visit_epoch = 1
    require("core.validate").reset_run_state()
    Enforce.reset_run_state()

    local b = bridge()
    local ok_gate, prose, _, code = Enforce.pre_action(b, "leave_shop", nil)
    check("the decision window refuses leave_shop", ok_gate ~= true and code == "CONFIRMATION_REQUIRED",
      tostring(code))
    local correction = tostring(prose)
    local extra = 0
    for _, def in ipairs(Actions.get_valid_actions_for_state("SHOP") or {}) do
      if def ~= "leave_shop" and correction:find(def, 1, true) then extra = extra + 1 end
    end
    check("no other callable action leaks into the retained frame", extra == 0, correction)
  end
end

do
  selecting_hand_env(700)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  require("tests.helpers").stage_registered(nil, { "discard_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "below-gate", name = "discard_hand", data = '{"indices":[99]}' } }, b)
  local refused = b.results[#b.results]
  check("the send is refused below the gate", refused and refused.id == "below-gate" and refused.ok == false,
    refused and tostring(refused.reason))
  local ok_retry, err_retry = Enforce.pre_action(b, "discard_hand", '{"indices":[2]}')
  check("a send refused below the gate does not bill the next one", ok_retry == true, tostring(err_retry))
end

do
  selecting_hand_env(900)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 3, llm_paused = true,
    dispatcher = Dispatcher, actions = Actions }
  local b = bridge()
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "action did not apply"
  Dispatcher.route_message({ command = "action", run_generation = 3,
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local last = b.results[#b.results]
  check("the paused answer goes out acknowledged",
    last and last.ok == true and last.reason == "TRANSITION_PENDING", last and tostring(last.reason) or "none")
check("the unresolved warning survives the pause",
  G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
check("pause leaves the unresolved reason intact",
  G.NEURO.last_failed_reason == "action did not apply",
  tostring(G.NEURO.last_failed_reason))
end

do
  selecting_hand_env(1100)
  G.NEURO = { enabled = true, run_generation = 11 }
  check("bump_run_generation returns the new value",
    Lifecycle.bump_run_generation() == 12 and G.NEURO.run_generation == 12,
    tostring(G.NEURO.run_generation))
  G.NEURO.run_generation = nil
  check("it refuses to invent a generation from nothing",
    Lifecycle.bump_run_generation() == nil and G.NEURO.run_generation == nil,
    tostring(G.NEURO.run_generation))
end

do
  selecting_hand_env(1300)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 9,
    joker_bought_cost = { j_joker = 6 } }
  Lifecycle.reset_run_state()
  check("lifecycle: joker_bought_cost does not leak across a run reset",
    G.NEURO.joker_bought_cost == nil, tostring(G.NEURO.joker_bought_cost))
end

do
  selecting_hand_env(1400)
  G.NEURO = require("tests.helpers").started_bridge({ enabled = true, decision_serial = 1, run_generation = 7, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions, _bridge_init_complete = true,
    register_actions = function() return true end })
  local b = bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  local Metrics = require("util.metrics")
  local function metric(name) return Metrics._counters[name] or 0 end
  local invalid_before = metric("dispatch_action_invalid_id")
  local missing_drop_before = metric("dispatch_drop_route_missing_action_id")
  Dispatcher.route_message({ command = "action",
    data = { id = string.rep("i", 1048577), name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("an unusable id is recorded as an invalid id, not as a missing one",
    metric("dispatch_action_invalid_id") == invalid_before + 1
      and metric("dispatch_drop_route_missing_action_id") == missing_drop_before,
    tostring(metric("dispatch_action_invalid_id") - invalid_before) .. "/"
      .. tostring(metric("dispatch_drop_route_missing_action_id") - missing_drop_before))
  check("and no result frame is attempted for an id no result could carry",
    #b.results == 0, tostring(#b.results))
end

done()
