_G.NEURO_TEST = true

local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local check, done = require("tests.helpers").harness("receipt-dispatcher")
local Dispatcher = require("core.dispatcher")
local Receipt = require("core.action_receipt")

local function setup()
  Receipt.reset("test")
  _G.G = {
    NEURO = {
      state = "SHOP",
      run_generation = 3,
      force_dirty = false,
      once_serials = {},
      _decision_windows = {},
    },
    GAME = { current_round = {} },
    FUNCS = {},
  }
  local bridge = { phases = {}, contexts = {}, results = {} }
  function bridge:record_action_phase(_, _, phase, details)
    self.phases[#self.phases + 1] = { phase = phase, details = details }
    return true
  end
  function bridge:send_context(message)
    self.contexts[#self.contexts + 1] = message
    return true
  end
  function bridge:send_action_result(id, ok, message)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message }
  end
  return bridge
end

do
  local bridge = setup()
  local applied = false
  local job = {
    id = "async-ok",
    name = "buy_from_shop",
    ack_snapshot = {},
    exec = function()
      return Receipt.create({
        id = "async-ok",
        name = "buy_from_shop",
        run_generation = 3,
        started_at = 100,
        deadline = 105,
        applied_message = "Observed purchase applied.",
        probe = function() return applied and "applied" or "pending", { observed = applied } end,
      })
    end,
  }
  Dispatcher._test.execute_action(job, bridge)
  check("receipt enters verifying without local success", Receipt.has_active()
    and G.NEURO.action_phase == "verifying" and G.NEURO.last_action_name == nil)
  check("verifying does not emit another action result", #bridge.results == 0)
  check("journal stops at verifying",
    bridge.phases[1] and bridge.phases[1].phase == "executing"
      and bridge.phases[2] and bridge.phases[2].phase == "verifying"
      and bridge.phases[3] == nil)
  Dispatcher.update_receipts(101)
  check("pending receipt still has no success side effects",
    Receipt.has_active() and G.NEURO.last_action_name == nil)
  applied = true
  Dispatcher.update_receipts(102)
  check("applied receipt commits success effects",
    not Receipt.has_active() and G.NEURO.last_action_name == "buy_from_shop")
  check("observed success context is postcondition-driven",
    bridge.contexts[1] == "[run 3] After the completed action 'buy_from_shop': Observed purchase applied.", bridge.contexts[1])
  check("journal completes with accepted and applied",
    bridge.phases[3] and bridge.phases[3].phase == "completed"
      and bridge.phases[3].details.applied == true)
  check("terminal receipt still emits no second result", #bridge.results == 0)
end

do
  local bridge = setup()
  G.NEURO.consumed_actions = { sell_card = true }
  local Metrics = require("util.metrics")
  local original_time_begin = Metrics.time_begin
  Metrics.time_begin = function() error("timer observer exploded") end
  local executed = false
  Dispatcher._test.execute_action({
    id = "execution-setup-fault",
    name = "sell_card",
    disposable = true,
    exec = function()
      executed = true
      return Receipt.outcome("applied")
    end,
  }, bridge)
  Metrics.time_begin = original_time_begin
  check("execution setup failure cannot orphan an acknowledged disposable action",
    executed == false and G.NEURO.consumed_actions == nil and not Receipt.has_active())
  check("execution setup failure reaches the terminal failed phase",
    bridge.phases[2] and bridge.phases[2].phase == "completed"
      and bridge.phases[2].details.applied == false)
end

do
  local bridge = setup()
  G.NEURO.consumed_actions = { sell_card = true }
  local original_on_action = require("core.task_mode").on_action
  require("core.task_mode").on_action = function() error("observer exploded") end
  Dispatcher._test.execute_action({
    id = "finalizer-fault",
    name = "sell_card",
    disposable = true,
    exec = function()
      return Receipt.create({
        id = "finalizer-fault",
        name = "sell_card",
        run_generation = 3,
        started_at = 100,
        deadline = 105,
        probe = function() return "applied" end,
      })
    end,
  }, bridge)
  require("core.task_mode").on_action = original_on_action
  check("observer failure cannot strand the disposable-action lock",
    not Receipt.has_active() and G.NEURO.consumed_actions == nil)
  check("observer failure cannot suppress the terminal journal phase",
    bridge.phases[3] and bridge.phases[3].phase == "completed"
      and bridge.phases[3].details.applied == true)
  check("observer failure cannot suppress force progress bookkeeping",
    G.NEURO.last_action_name == "sell_card" and G.NEURO.force_dirty == true)
end

do
  local bridge = setup()
  local Journal = require("core.gameplay_journal")
  local event = assert(Journal.seal({ kind = "shop_reroll", paid = 5,
    used_free_reroll = false }, "journal-observer-fault"))
  local real_publish = Journal.publish
  Journal.publish = function() error("journal observer exploded", 0) end
  Dispatcher._test.execute_action({
    id = "journal-observer-fault",
    name = "reroll_shop",
    gameplay_event = event,
    exec = function() return Receipt.outcome("applied") end,
  }, bridge)
  Journal.publish = real_publish
  check("journal observer failure is fail-open for applied gameplay",
    G.NEURO.last_action_name == "reroll_shop" and G.NEURO.force_dirty == true)
  check("journal observer failure does not request a second action result", #bridge.results == 0)
end

do
  setup()
  local failed = 0
  local receipt = Receipt.create({
    id = "sibling-fault",
    name = "sell_card",
    run_generation = 3,
    started_at = 90,
    deadline = 99,
    timeout_outcome = "failed",
    probe = function() return "pending" end,
    on_failed = function() failed = failed + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  G.NEURO.update = function() error("transport exploded") end
  G.FUNCS = nil
  local ok, err = pcall(require("core.orchestrator")._step_neuro_frame, 0)
  check("transport failure is still surfaced for diagnostics",
    not ok and tostring(err):find("transport exploded", 1, true) ~= nil, tostring(err))
  check("transport failure cannot disable the receipt deadline",
    not Receipt.has_active() and receipt.phase == "failed" and failed == 1)
end

do
  setup()
  local ForceState = require("core.force_state")
  local State = require("core.state")
  local original_get_state_name = State.get_state_name
  G.NEURO.enabled = true
  G.NEURO.update = function() end
  G.FUNCS = {}
  ForceState.arm("SHOP", { "sell_card" }, { sell_card = true }, 100)
  ForceState.mark_sent(-1000)
  State.get_state_name = function() error("state adapter exploded") end
  local ok, err = pcall(require("core.orchestrator")._step_neuro_frame, 0)
  State.get_state_name = original_get_state_name
  check("state discovery failure is still surfaced for diagnostics",
    not ok and tostring(err):find("state adapter exploded", 1, true) ~= nil, tostring(err))
  check("state discovery failure cannot disable the sent-force deadline",
    G.NEURO.force_inflight == false and G.NEURO.force_last_result == "liveness_timeout")
end

do
  local Orch = require("core.orchestrator")
  Orch.init() -- make the one-shot bridge initializer inert for the isolated update below
  setup()
  G.NEURO.enabled = true
  G.NEURO.update = function() end
  G.FUNCS = nil
  local failed = 0
  local receipt = Receipt.create({
    id = "outer-frame-fault",
    name = "sell_card",
    run_generation = 3,
    started_at = 90,
    deadline = 99,
    timeout_outcome = "failed",
    probe = function() return "pending" end,
    on_failed = function() failed = failed + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  G.hand = setmetatable({}, { __index = function() error("card area exploded") end })
  local ok = pcall(Orch.update, 0, nil)
  G.hand = nil
  check("pre-frame maintenance failure cannot suppress the Neuro watchdog frame",
    ok and not Receipt.has_active() and receipt.phase == "failed" and failed == 1)
end

do
  local Orch = require("core.orchestrator")
  local BridgeInit = require("core.bridge_init")
  local original_run = BridgeInit.run
  local attempts = 0
  BridgeInit.run = function()
    attempts = attempts + 1
    if attempts == 1 then error("bridge init transient") end
  end
  Orch._reset_bridge_init()
  Orch._step_bridge_init()
  Orch._step_bridge_init()
  BridgeInit.run = original_run
  check("a transient bridge initialization failure is retried", attempts == 2, attempts)
end

do
  local bridge = setup()
  local job = {
    id = "async-fail",
    name = "sell_card",
    disposable = true,
    exec = function()
      return Receipt.create({
        id = "async-fail",
        name = "sell_card",
        run_generation = 3,
        started_at = 100,
        deadline = 101,
        timeout_outcome = "failed",
        correction = "Sale was accepted but the card remained in its area.",
        probe = function() return "pending" end,
      })
    end,
  }
  Dispatcher._test.execute_action(job, bridge)
  Dispatcher.update_receipts(101)
  check("deadline failure never records last action success", G.NEURO.last_action_name == nil)
  check("deadline failure records a correction", G.NEURO.last_failed_action == "sell_card")
  check("deadline failure states the correction on the force query and sends no action result",
    G.NEURO.last_failed_correction == "Sale was accepted but the card remained in its area."
      and require("force.force_helpers").failed_action_warning()
        :find("remained in its area", 1, true) ~= nil
      and #bridge.contexts == 0 and #bridge.results == 0,
    tostring(G.NEURO.last_failed_correction) .. " | ctx=" .. #bridge.contexts)
  check("failure journal distinguishes accepted from applied",
    bridge.phases[3] and bridge.phases[3].details.accepted == true
      and bridge.phases[3].details.applied == false
      and bridge.phases[3].details.outcome == "failed")
end

do
  local bridge = setup()
  Dispatcher._test.execute_action({
    id = "sync-outcome",
    name = "set_plan",
    exec = function() return Receipt.outcome("applied", "Plan observed.", { revision = 2 }) end,
  }, bridge)
  check("structural applied outcome bypasses legacy path", G.NEURO.last_action_name == "set_plan"
    and bridge.contexts[1] == "[run 3] After the completed action 'set_plan': Plan observed.")

  bridge = setup()
  Dispatcher._test.execute_action({
    id = "sync-failed",
    name = "set_plan",
    exec = function() return Receipt.outcome("failed", "Plan did not change.") end,
  }, bridge)
  check("structural failed outcome has no success side effects",
    G.NEURO.last_action_name == nil
      and G.NEURO.last_failed_correction == "Plan did not change."
      and #bridge.contexts == 0,
    tostring(G.NEURO.last_failed_correction) .. " | ctx=" .. #bridge.contexts)
end

do
  local bridge = setup()
  Dispatcher._test.execute_action({
    id = "missing-evidence",
    name = "set_plan",
    exec = function() return "Legacy success text" end,
  }, bridge)
  check("mutating action without evidence fails closed instead of using legacy success",
    G.NEURO.last_action_name == nil and G.NEURO.last_failed_action == "set_plan"
      and bridge.phases[2] and bridge.phases[2].details.outcome == "ambiguous")
end

do
  local bridge = setup()
  Dispatcher._test.execute_action({
    id = "leaked-receipt",
    name = "set_plan",
    exec = function()
      Receipt.create({
        id = "leaked-receipt",
        name = "set_plan",
        run_generation = 3,
        started_at = 100,
        deadline = 100000,
        probe = function() return "pending" end,
      })
      return "Legacy success text"
    end,
  }, bridge)
  check("a receipt created but not returned by exec is not left active",
    not Receipt.has_active(), Receipt.active_count())
  check("the leaked receipt is closed as the contract-violation outcome",
    bridge.phases[2] and bridge.phases[2].details.outcome == "ambiguous")
end

do
  local bridge = setup()
  Dispatcher._test.execute_action({
    id = "intents-applied", name = "set_joker_intents", ack_snapshot = {},
    exec = function()
      return Receipt.outcome("applied", 'Tagged: 1=CORE (Green Joker) note: "the engine"')
    end,
  }, bridge)
  check("an applied set_joker_intents leaves nothing on the permanent channel",
    bridge.contexts[1] == nil, tostring(bridge.contexts[1]))
  check("but it still completes as applied",
    bridge.phases[2] and bridge.phases[2].phase == "completed"
      and bridge.phases[2].details.applied == true)

  local other = setup()
  Dispatcher._test.execute_action({
    id = "sell-applied", name = "sell_card", ack_snapshot = {},
    exec = function() return Receipt.outcome("applied", "Sold: Green Joker for $2") end,
  }, other)
  check("an action with no live restatement still gets its result context",
    other.contexts[1] == "[run 3] After the completed action 'sell_card': Sold: Green Joker for $2",
    tostring(other.contexts[1]))
end

done()
