_G.NEURO_TEST = true
local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("transport-reset-release")
local Dispatcher = require("core.dispatcher")
local ActionReceipt = require("core.action_receipt")
local Actions = require("core.actions")
local Bridge = require("core.bridge")
local Lifecycle = require("core.neuro_lifecycle")

local function fresh_round_eval(run_generation)
  _G.G = {
    STATE = 1, STATES = { MENU = 1 },
    GAME = { dollars = 20 },
    FUNCS = { cash_out = function() end },
    round_eval = true,
    NEURO = { state = "ROUND_EVAL", run_generation = run_generation },
  }
end

local function noop_bridge()
  return { send_action_result = function() return true end, record_action_phase = function() return true end }
end

local function verifying_receipt(id, run_generation)
  local receipt = ActionReceipt.create({
    id = id, name = "cash_out", run_generation = run_generation,
    deadline = ActionReceipt.now() + 100, timeout_outcome = "failed",
    probe = function() return "pending" end,
  })
  ActionReceipt.transition(receipt, "acknowledged")
  ActionReceipt.transition(receipt, "executing")
  ActionReceipt.transition(receipt, "verifying")
  return receipt
end

fresh_round_eval(5)
local b = noop_bridge()
Bridge.consume_actions(b, { "cash_out" }, "act-1")
verifying_receipt("act-1", 5)
check("case A: cash_out is withheld while act-1 is in flight",
  Actions.is_action_valid("cash_out") == false)

Lifecycle.bump_run_generation("transport reconnected")

check("case A: consumed_actions is released by the real reconnect path",
  G.NEURO.consumed_actions == nil, tostring(G.NEURO.consumed_actions))
check("case A: cash_out is offerable again after reconnect",
  Actions.is_action_valid("cash_out") == true)

fresh_round_eval(5)
local b2 = noop_bridge()
Bridge.consume_actions(b2, { "cash_out" }, "act-2")
verifying_receipt("act-2", 5)
G.NEURO.run_generation = 6
Dispatcher.update_receipts(ActionReceipt.now())

check("case B: the receipt is still resolved off the stale generation",
  ActionReceipt.get("act-2") == nil)
check("case B: but consumed_actions is left stuck without the explicit release",
  G.NEURO.consumed_actions ~= nil, tostring(G.NEURO.consumed_actions))
check("case B: cash_out stays withheld -- ROUND_EVAL's only offer would be lost",
  Actions.is_action_valid("cash_out") == false)

done()
