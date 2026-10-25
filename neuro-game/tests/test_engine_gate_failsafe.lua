require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("engine_gate_failsafe")

local STATES = require("tests.engine_cards").states()

local joker = H.flat_mult_joker

H.orch_board({ kind = "club", state = "BLIND_SELECT", states = STATES, edit = function(g)
  g.GAME.STOP_USE = 1
  g.jokers.cards = { joker("j_joker", "Joker") }
  g.shop_jokers, g.shop_vouchers, g.shop_booster = nil, nil, nil
end })

local Config = require("core.config")
local Guard = require("core.validate")
local timeout = Config.get_raw("NEURO_ENGINE_GATE_FAILSAFE")
check("failsafe has a named positive setting", type(timeout) == "number" and timeout > 0, timeout)
timeout = tonumber(timeout) or 8
check("transition guard owns the engine gate", type(Guard.engine_ready) == "function")

if type(Guard.engine_ready) == "function" then
  Guard.reset_run_state()
  check("fresh STOP_USE blocks the engine gate", Guard.engine_ready() == false)
  G.TIMERS.REAL = 1000 + timeout - 0.1
  check("STOP_USE remains blocked before the failsafe", Guard.engine_ready() == false)
  G.TIMERS.REAL = 1000 + timeout + 0.1
  check("persistent STOP_USE self-releases after the failsafe", Guard.engine_ready() == true)
  check("the same failsafe also releases the per-action STOP_USE guard",
    Guard.settling("choose_pack_card") == nil and Guard.settling("skip_pack") == nil)
  check("self-release does not mutate the engine flag", G.GAME.STOP_USE == 1)
  G.GAME.STOP_USE = 0
  check("a clear frame resets the engine gate", Guard.engine_ready() == true)
  G.GAME.STOP_USE = 1
  check("a new blockage receives a fresh grace period", Guard.engine_ready() == false)
  G.GAME.STOP_USE = 0
  Guard.reset_run_state()
  G.CONTROLLER.locked = true
  check("fresh controller lock blocks the engine gate", Guard.engine_ready() == false)
  G.TIMERS.REAL = G.TIMERS.REAL + timeout + 0.1
  check("persistent controller lock self-releases", Guard.engine_ready() == true)
  check("self-release does not mutate the controller lock", G.CONTROLLER.locked == true)
  G.CONTROLLER.locked = nil
  Guard.reset_run_state()
  G.E_MANAGER.queues.base = { { blocking = true, blockable = true } }
  check("fresh blocking event blocks the engine gate", Guard.engine_ready() == false)
  G.TIMERS.REAL = G.TIMERS.REAL + timeout + 0.1
  check("persistent blocking event self-releases", Guard.engine_ready() == true)
  check("self-release does not remove the engine event", #G.E_MANAGER.queues.base == 1)
  G.E_MANAGER.queues.base = nil
else
  check("fresh STOP_USE blocks the engine gate", false)
  check("STOP_USE remains blocked before the failsafe", false)
  check("persistent STOP_USE self-releases after the failsafe", false)
  check("self-release does not mutate the engine flag", G.GAME.STOP_USE == 1)
  check("a clear frame resets the engine gate", false)
  check("a new blockage receives a fresh grace period", false)
  check("fresh controller lock blocks the engine gate", false)
  check("persistent controller lock self-releases", false)
  check("self-release does not mutate the controller lock", false)
  check("fresh blocking event blocks the engine gate", false)
  check("persistent blocking event self-releases", false)
  check("self-release does not remove the engine event", false)
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local forces = {}
G.NEURO = H.orch_neuro({ dispatcher = Dispatcher, actions = Actions, state = "BLIND_SELECT",
  register_actions = "true", send_context = "written", send_action_result = "noop" })
function G.NEURO:force_actions(_ctx, _query, actions)
  forces[#forces + 1] = table.concat(actions, ",")
  return true
end

local Orch = require("core.orchestrator")
local Window = require("core.window")
local HudState = require("hud.state")
G.GAME.STOP_USE = 1
Guard.reset_run_state()
Orch.reset_run_state()
HudState.state_changed_at = G.TIMERS.REAL
Window.step("BLIND_SELECT")
check("orchestrator emits nothing while the engine flag is fresh", #forces == 0, #forces)
G.TIMERS.REAL = G.TIMERS.REAL + timeout + 0.1
Window.step("BLIND_SELECT")
G.TIMERS.REAL = G.TIMERS.REAL + Config.get("NEURO_FORCE_DEBOUNCE") + 0.1
Window.step("BLIND_SELECT")
check("orchestrator eventually emits through a stuck engine flag", #forces == 1, #forces)
check("the emitted force holds the open window", #forces == 1 and Window.current() ~= nil, #forces)
check("emitted force preserves the stuck engine flag", G.GAME.STOP_USE == 1)

do
  G.GAME.STOP_USE = 0
  G.STATE = STATES.SELECTING_HAND
  G.play = { cards = { {} } }
  Window.reset()
  Guard.reset_run_state()
  HudState.state_changed_at_game = G.TIMERS.REAL - 100
  local settled = Window._test.settled
  check("a hand resolving in G.play holds the hand screen", settled("SELECTING_HAND") == false)
  G.TIMERS.REAL = G.TIMERS.REAL + timeout - 0.1
  check("and still holds it before the failsafe", settled("SELECTING_HAND") == false)
  G.TIMERS.REAL = G.TIMERS.REAL + 0.2
  check("cards stuck in G.play release the hand screen after the failsafe", settled("SELECTING_HAND") == true)
  check("self-release does not touch G.play", #G.play.cards == 1)
  G.play.cards = {}
  check("an empty play area is settled at once", settled("SELECTING_HAND") == true)
  G.GAME.blind.block_play = true
  check("a new blockage receives a fresh grace period", settled("SELECTING_HAND") == false)
  G.GAME.blind.block_play = nil
end

done()
