local ES = require("tests.engine_cards").states()
_G.NEURO_TEST = true
local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("transport-reset-release")
local Dispatcher = require("core.dispatcher")
local ActionReceipt = require("core.action_result")
local Actions = require("core.actions")

local function fresh_round_eval(run_generation)
  _G.G = {
    STATE = ES.MENU, STATES = ES,
    GAME = { dollars = 20 },
    FUNCS = { cash_out = function() end },
    round_eval = true,
    NEURO = require("tests.helpers").started_bridge({ state = "ROUND_EVAL", run_generation = run_generation,
      register_actions = function() return true end }),
  }
  require("tests.helpers").cash_out_ready(G)
end

local function noop_bridge()
  return { send_action_result = function() return true end }
end

local function verifying_receipt(id, run_generation)
  local receipt = ActionReceipt.create({
    id = id, name = "cash_out", run_generation = run_generation,
    deadline = ActionReceipt.now() + 100, timeout_outcome = "failed",
    probe = function() return "pending" end,
  })
  return receipt
end

local Execute = require("core.execute")
local Validate = require("core.validate")

local function in_flight(id)
  Execute.admit({ id = id, name = "cash_out", data = {}, bridge = noop_bridge(),
    exec = function() return verifying_receipt(id, G.NEURO.run_generation) end }, false)
end

fresh_round_eval(5)
in_flight("act-1")
check("case A: a new action waits while act-1 is in flight",
  Execute.busy() == "verifying" and Validate.busy_reason("cash_out") ~= nil)

package.loaded["core.bridge_init"] = nil
local BridgeInit = require("core.bridge_init")
G.NEURO.send_startup = function() return true end
check("case A: the real reconnect path accepts the session",
  BridgeInit.handle_transport_reconnect("reconnect-session") == true)
check("case A: the reconnect retires the in-flight action", Execute.busy() == nil)
check("case A: cash_out is offerable again after reconnect",
  Actions.is_action_valid("cash_out") == true)

fresh_round_eval(5)
in_flight("act-2")
G.NEURO.run_generation = 6
Execute.step(ActionReceipt.now())
check("case B: the receipt is resolved off the stale generation", Execute.busy() == nil)
check("case B: cash_out is offerable after stale-generation resolution",
  Actions.is_action_valid("cash_out") == true)

done()
