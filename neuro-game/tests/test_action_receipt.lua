_G.NEURO_TEST = true

local clock = 10
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local check, done = require("tests.helpers").harness("action-receipt")
local Receipt = require("core.action_receipt")

Receipt.reset("test_start")

do
  local probes, applied, cleaned, execute_calls = 0, 0, 0, 0
  local receipt = Receipt.create({
    id = "happy",
    name = "buy_from_shop",
    run_generation = 7,
    started_at = 10,
    deadline = 15,
    execute = function() execute_calls = execute_calls + 1 end,
    probe = function()
      probes = probes + 1
      if probes == 1 then return "pending" end
      return "applied", { card = "j_test" }
    end,
    on_applied = function() applied = applied + 1 end,
    cleanup = function() cleaned = cleaned + 1 end,
  })
  check("create starts prepared and registers one receipt",
    receipt.phase == "prepared" and Receipt.get("happy") == receipt and Receipt.active_count() == 1)
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  check("valid lifecycle reaches verifying", receipt.phase == "verifying")
  check("first pending probe stays active", #Receipt.update(11, 7) == 0 and receipt.phase == "verifying")
  check("second probe applies and removes receipt",
    #Receipt.update(12, 7) == 1 and receipt.phase == "applied" and Receipt.get("happy") == nil)
  check("applied and cleanup callbacks run exactly once", applied == 1 and cleaned == 1)
  Receipt.update(13, 7)
  Receipt.complete(receipt, "failed")
  check("terminalization is idempotent", applied == 1 and cleaned == 1 and receipt.phase == "applied")
  check("receipt never owns or replays execution callback", execute_calls == 0, execute_calls)
end

do
  local failed, cleaned = 0, 0
  local receipt = Receipt.create({
    id = "deadline",
    name = "sell_card",
    run_generation = 7,
    started_at = 20,
    deadline = 22,
    timeout_outcome = "failed",
    probe = function() return "pending" end,
    on_failed = function() failed = failed + 1 end,
    cleanup = function() cleaned = cleaned + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  check("deadline does not invent success before expiry",
    #Receipt.update(21.99, 7) == 0 and receipt.phase == "verifying")
  check("deadline uses configured negative outcome",
    #Receipt.update(22, 7) == 1 and receipt.phase == "failed")
  check("deadline callbacks run once", failed == 1 and cleaned == 1)
end

do
  local failed, cleaned = 0, 0
  local receipt = Receipt.create({
    id = "generation",
    name = "play_hand",
    run_generation = 8,
    started_at = 30,
    deadline = 40,
    probe = function() return "applied" end,
    on_failed = function() failed = failed + 1 end,
    cleanup = function() cleaned = cleaned + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  Receipt.update(31, 9)
  check("stale generation becomes ambiguous", receipt.phase == "ambiguous")
  check("stale generation cleans without running failure side effects", failed == 0 and cleaned == 1)
end

do
  local invalid = Receipt.create({
    id = "invalid-probe",
    name = "use_consumable",
    run_generation = 2,
    started_at = 40,
    deadline = 50,
    probe = function() return "maybe" end,
  })
  Receipt.transition(invalid, "acknowledged")
  Receipt.transition(invalid, "executing")
  Receipt.transition(invalid, "verifying")
  Receipt.update(41, 2)
  check("invalid probe outcome is ambiguous", invalid.phase == "ambiguous"
    and invalid.details.reason == "invalid_probe_outcome")

  local throwing = Receipt.create({
    id = "throwing-probe",
    name = "use_consumable",
    run_generation = 2,
    started_at = 40,
    deadline = 50,
    probe = function() error("probe exploded") end,
  })
  Receipt.transition(throwing, "acknowledged")
  Receipt.transition(throwing, "executing")
  Receipt.transition(throwing, "verifying")
  Receipt.update(41, 2)
  check("throwing probe is ambiguous without escaping", throwing.phase == "ambiguous"
    and throwing.details.reason == "probe_error")
end

do
  local cleaned = 0
  local receipt = Receipt.create({
    id = "reset",
    name = "cash_out",
    run_generation = 4,
    started_at = 50,
    deadline = 60,
    probe = function() return "pending" end,
    cleanup = function() cleaned = cleaned + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.reset("run_reset")
  check("reset clears active receipts and cleanup", not Receipt.has_active() and cleaned == 1)
  check("reset marks receipt ambiguous with reason", receipt.phase == "ambiguous"
    and receipt.details.reason == "run_reset")
end

do
  local receipt = Receipt.create({
    id = "debug",
    name = "leave_shop",
    run_generation = 3,
    started_at = 60,
    deadline = 70,
    debug = { target = "shop", fn = function() end },
    probe = function() return "pending" end,
  })
  local snapshot = Receipt.debug_snapshot(receipt)
  check("debug snapshot contains no function values",
    type(snapshot.debug.fn) == "string" and snapshot.id == "debug")
  local duplicate_ok = pcall(Receipt.create, {
    id = "debug", name = "other", started_at = 60, deadline = 70, probe = function() end,
  })
  check("one id cannot own two active receipts", duplicate_ok == false)
  local invalid_transition = pcall(Receipt.transition, receipt, "verifying")
  check("invalid phase jumps are rejected", invalid_transition == false)
  Receipt.reset("test_end")
end

do
  local second_ran = false
  local receipt = Receipt.create({
    id = "callback-chain",
    name = "buy_from_shop",
    started_at = 80,
    deadline = 90,
    probe = function() return "applied" end,
    on_applied = function() error("first callback failed") end,
  })
  Receipt.chain_callbacks(receipt, function() second_ran = true end)
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  Receipt.update(81, 0)
  check("callback chain runs finalization even when an earlier callback throws",
    second_ran and receipt.phase == "applied" and receipt.callback_error ~= nil)
end

do
  local cleaned = 0
  local hostile_error = setmetatable({}, {
    __tostring = function() error("error formatter exploded") end,
  })
  local receipt = Receipt.create({
    id = "hostile-callback-error",
    name = "buy_from_shop",
    started_at = 90,
    deadline = 100,
    probe = function() return "applied" end,
    on_applied = function() error(hostile_error, 0) end,
    cleanup = function() cleaned = cleaned + 1 end,
  })
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  local ok = pcall(Receipt.update, 91, 0)
  check("an unprintable callback error cannot suppress terminal receipt cleanup",
    ok and not Receipt.has_active() and receipt.phase == "applied" and cleaned == 1
      and receipt.callback_error == "<unprintable value>")
end

done()
