_G.NEURO_TEST = true

local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local check, done = require("tests.helpers").harness("receipt-dispatcher")
local Receipt = require("core.action_result")
local Execute = require("core.execute")

local function setup()
  Execute.abort("test")
  _G.G = {
    NEURO = {
      state = "SHOP",
      run_generation = 3,
      once_serials = {},
    },
    GAME = { current_round = {}, pseudorandom = { seed = "RECEIPT" } },
    STAGES = { MAIN_MENU = 1, RUN = 2, SANDBOX = 3 }, STAGE = 2,
    FUNCS = {},
  }
  local bridge = { contexts = {}, results = {} }
  function bridge:send_context(message)
    self.contexts[#self.contexts + 1] = message
    return true
  end
  function bridge:send_action_result(id, ok, message, reason_code)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
    return true
  end
  return bridge
end

local function admit(bridge, job)
  job.bridge, job.data, job.run_generation = bridge, job.data or {}, 3
  Execute.admit(job, false)
end

local function only_admission(bridge, id)
  return #bridge.results == 1 and bridge.results[1].id == id and bridge.results[1].ok == true
    and bridge.results[1].reason_code == "ACTION_ACCEPTED" and bridge.results[1].message == nil
end

local function failure_context(bridge)
  for _, message in ipairs(bridge.contexts) do
    if tostring(message):find("did not complete successfully", 1, true) then return message end
  end
end

do
  local bridge = setup()
  local applied = false
  admit(bridge, {
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
  })
  check("receipt enters verifying without local success",
    Execute.busy() == "verifying" and G.NEURO.last_action_name == nil)
  check("the admission result precedes execution", only_admission(bridge, "async-ok"))
  Execute.step(101)
  check("pending receipt still has no success side effects",
    Execute.busy() == "verifying" and G.NEURO.last_action_name == nil)
  applied = true
  Execute.step(102)
  check("applied receipt commits success effects",
    Execute.busy() == nil and G.NEURO.last_action_name == "buy_from_shop")
  check("an applied purchase sends no context: the next force's state restates it (BEST_PRACTICES.md:8)",
    bridge.contexts[1] == nil, tostring(bridge.contexts[1]))
  check("an applied receipt sends no second result", only_admission(bridge, "async-ok"))
end

do
  local bridge = setup()
  local Metrics = require("util.metrics")
  local original_time_begin = Metrics.time_begin
  Metrics.time_begin = function() error("timer observer exploded") end
  local executed = false
  admit(bridge, {
    id = "execution-setup-fault",
    name = "sell_card",
    exec = function()
      executed = true
      return Receipt.outcome("applied")
    end,
  })
  Metrics.time_begin = original_time_begin
  check("execution setup failure cannot orphan the admitted action",
    executed == false and Execute.busy() == nil)
  check("execution setup failure sends no second result", only_admission(bridge, "execution-setup-fault"))
  check("execution setup failure is reported as context", failure_context(bridge) ~= nil,
    table.concat(bridge.contexts, " | "))
end

do
  local bridge = setup()
  local original_note_applied = require("core.validate").note_applied
  require("core.validate").note_applied = function() error("observer exploded") end
  admit(bridge, {
    id = "finalizer-fault",
    name = "sell_card",
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
  })
  require("core.validate").note_applied = original_note_applied
  check("observer failure cannot strand the action in flight", Execute.busy() == nil)
  check("observer failure cannot suppress progress bookkeeping", G.NEURO.last_action_name == "sell_card")
  check("observer failure leaves the one admission result", only_admission(bridge, "finalizer-fault"))
end

do
  local bridge = setup()
  local Journal = require("core.gameplay_journal")
  local event = { kind = "shop_reroll", paid = 5, used_free_reroll = false }
  local real_publish = Journal.publish
  Journal.publish = function() error("journal observer exploded", 0) end
  admit(bridge, {
    id = "journal-observer-fault",
    name = "reroll_shop",
    gameplay_event = event,
    exec = function() return Receipt.outcome("applied") end,
  })
  Journal.publish = real_publish
  check("journal observer failure is fail-open for applied gameplay",
    G.NEURO.last_action_name == "reroll_shop" and Execute.busy() == nil)
  check("journal observer failure leaves the one admission result", only_admission(bridge, "journal-observer-fault"))
end

do
  local bridge = setup()
  local failed = 0
  clock = 100
  admit(bridge, {
    id = "sibling-fault",
    name = "sell_card",
    exec = function()
      return Receipt.create({
        id = "sibling-fault",
        name = "sell_card",
        run_generation = 3,
        started_at = 100,
        deadline = 101,
        timeout_outcome = "failed",
        probe = function() return "pending" end,
        on_failed = function() failed = failed + 1 end,
      })
    end,
  })
  clock = 102
  G.NEURO.update = function() error("transport exploded") end
  G.FUNCS = nil
  local ok, err = pcall(require("core.orchestrator")._step_neuro_frame, 0)
  check("transport failure is still surfaced for diagnostics",
    not ok and tostring(err):find("transport exploded", 1, true) ~= nil, tostring(err))
  check("transport failure cannot disable the receipt deadline",
    Execute.busy() == nil and failed == 1)
end

do
  setup()
  local State = require("core.state")
  local original_get_state_name = State.get_state_name
  G.NEURO.enabled = true
  G.NEURO.update = function() end
  local withdrawn
  G.NEURO.withdraw_actions = function(_, names) withdrawn = names return true end
  G.FUNCS = {}
  local sent_window = require("tests.helpers").open_force("SHOP", { "buy_from_shop" })
  clock = clock + 100000
  State.get_state_name = function() error("state adapter exploded") end
  local ok, err = pcall(require("core.orchestrator")._step_neuro_frame, 0)
  State.get_state_name = original_get_state_name
  check("state discovery failure is still surfaced for diagnostics",
    not ok and tostring(err):find("state adapter exploded", 1, true) ~= nil, tostring(err))
  check("state discovery failure still runs the sent-force deadline",
    sent_window.phase == "ended" and sent_window.ended_by == "liveness_timeout" and withdrawn ~= nil,
    tostring(sent_window.phase) .. "/" .. tostring(sent_window.ended_by))
end

do
  local Orch = require("core.orchestrator")
  Orch._step_bridge_init()
  local bridge = setup()
  G.NEURO.enabled = true
  G.NEURO.update = function() end
  G.FUNCS = nil
  local failed = 0
  clock = 200
  admit(bridge, {
    id = "outer-frame-fault",
    name = "sell_card",
    exec = function()
      return Receipt.create({
        id = "outer-frame-fault",
        name = "sell_card",
        run_generation = 3,
        started_at = 200,
        deadline = 201,
        timeout_outcome = "failed",
        probe = function() return "pending" end,
        on_failed = function() failed = failed + 1 end,
      })
    end,
  })
  clock = 202
  G.hand = setmetatable({}, { __index = function() error("card area exploded") end })
  local ok = pcall(Orch.update, 0, nil)
  G.hand = nil
  check("pre-frame maintenance failure cannot suppress the Neuro watchdog frame",
    ok and Execute.busy() == nil and failed == 1)
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
  clock = 300
  admit(bridge, {
    id = "async-fail",
    name = "sell_card",
    exec = function()
      return Receipt.create({
        id = "async-fail",
        name = "sell_card",
        run_generation = 3,
        started_at = 300,
        deadline = 301,
        timeout_outcome = "failed",
        correction = "Sale was accepted but the card remained in its area.",
        probe = function() return "pending" end,
      })
    end,
  })
  Execute.step(301)
  check("deadline failure never records last action success", G.NEURO.last_action_name == nil)
  check("deadline failure records a correction", G.NEURO.last_failed_action == "sell_card")
  local report = failure_context(bridge)
  check("deadline failure states the correction as context, beside the one admission result",
    only_admission(bridge, "async-fail") and report ~= nil
      and report:find("Sale was accepted but the card remained in its area.", 1, true) ~= nil,
    tostring(report))
end

do
  local bridge = setup()
  admit(bridge, {
    id = "sync-outcome",
    name = "record_plan",
    exec = function() return Receipt.outcome("applied", "Plan observed.", { revision = 2 }) end,
  })
  check("structural applied outcome bypasses legacy path and echoes nothing", G.NEURO.last_action_name == "record_plan"
    and bridge.contexts[1] == nil, tostring(bridge.contexts[1]))

  bridge = setup()
  admit(bridge, {
    id = "sync-failed",
    name = "record_plan",
    exec = function() return Receipt.outcome("failed", "Plan did not change.") end,
  })
  local report = failure_context(bridge)
  check("structural failed outcome has no success side effects and reports its reason",
    G.NEURO.last_action_name == nil and G.NEURO.last_failed_action == "record_plan"
      and report ~= nil and report:find("Plan did not change.", 1, true) ~= nil,
    tostring(report))
end

do
  local bridge = setup()
  admit(bridge, {
    id = "missing-evidence",
    name = "record_plan",
    exec = function() return "Legacy success text" end,
  })
  check("mutating action without evidence fails closed instead of using legacy success",
    G.NEURO.last_action_name == nil and G.NEURO.last_failed_action == "record_plan"
      and failure_context(bridge) ~= nil)
end

do
  local bridge = setup()
  admit(bridge, {
    id = "intents-applied", name = "record_joker_roles", ack_snapshot = {},
    exec = function()
      return Receipt.outcome("applied", 'Tagged: 1=CORE (Green Joker) note: "the engine"')
    end,
  })
  check("an applied record_joker_roles leaves nothing on the permanent channel",
    bridge.contexts[1] == nil, tostring(bridge.contexts[1]))
  check("but it still completes as applied", G.NEURO.last_action_name == "record_joker_roles")

  local other = setup()
  admit(other, {
    id = "sell-applied", name = "sell_card", ack_snapshot = {},
    exec = function() return Receipt.outcome("applied", "Sold: Green Joker for $2") end,
  })
  check("an applied sale echoes nothing either", other.contexts[1] == nil, tostring(other.contexts[1]))

  local used = setup()
  admit(used, {
    id = "use-applied", name = "use_consumable", ack_snapshot = {},
    exec = function()
      return Receipt.create({ id = "use-applied", name = "use_consumable", run_generation = 3, started_at = 100,
        deadline = 105, applied_message = "Used: The Wheel of Fortune -- no visible change",
        probe = function() return "applied", { use_observed = true } end })
    end,
  })
  Execute.step(101)
  check("a used card's effect is told once",
    tostring(used.contexts[1]):find("Used: The Wheel of Fortune -- no visible change", 1, true) ~= nil
      and used.contexts[2] == nil, tostring(used.contexts[1]))
end

do
  local bridge = setup()
  admit(bridge, {
    id = "failed-with-cause",
    name = "buy_from_shop",
    ack_snapshot = {},
    exec = function()
      return Receipt.create({
        id = "failed-with-cause", name = "buy_from_shop", run_generation = 3,
        started_at = 100, deadline = 105, correction = "Generic correction.",
        probe = function() return "failed", { cause = "the game refuses to use The Hermit; nothing was bought" } end,
      })
    end,
  })
  Execute.step(101)
  local said = tostring(failure_context(bridge))
  check("a failed receipt's cause reaches the failure context",
    said:find("the game refuses to use The Hermit; nothing was bought", 1, true) ~= nil, said)

  bridge = setup()
  admit(bridge, {
    id = "failed-by-deadline",
    name = "buy_from_shop",
    ack_snapshot = {},
    exec = function()
      return Receipt.create({
        id = "failed-by-deadline", name = "buy_from_shop", run_generation = 3,
        started_at = 100, deadline = 101, timeout_outcome = "failed", correction = "Generic correction.",
        probe = function() return "pending" end,
      })
    end,
  })
  Execute.step(102)
  said = tostring(failure_context(bridge))
  check("a deadline failure keeps its correction and never shows the internal reason token",
    said:find("Generic correction.", 1, true) ~= nil and said:find("deadline", 1, true) == nil, said)
end

do
  for _, case in ipairs({
    { id = "throws", exec = function() error("boom") end },
    { id = "no-evidence", exec = function() return { unexpected = true } end },
  }) do
    local bridge = setup()
    admit(bridge, { id = case.id, name = "cash_out", ack_snapshot = {}, exec = case.exec })
    local said = tostring(failure_context(bridge))
    local _, times = said:gsub("%(cash out%)", "")
    check(case.id .. ": the failure context names the move once", times == 1 and not said:find("cash_out", 1, true), said)
  end
end

done()
