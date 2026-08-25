_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("engine_gate_failsafe")

local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7, MENU = 11 }

local joker = require("tests.helpers").flat_mult_joker

_G.G = {
  STATE = STATES.BLIND_SELECT, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
  GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 1,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 4,
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
      blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
    blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
    hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
  P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
    bl_big = { key = "bl_big", name = "Big Blind" },
    bl_club = { key = "bl_club", name = "The Club" } },
  jokers = { cards = { joker("j_joker", "Joker") }, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  deck = { cards = {} },
  FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end },
  CONTROLLER = { locks = {} },
  E_MANAGER = { queues = {} },
}

local Config = require("core.config")
local Guard = require("core.transition_guard")
local timeout = Config.get_raw("NEURO_ENGINE_GATE_FAILSAFE")
check("failsafe has a named positive setting", type(timeout) == "number" and timeout > 0, timeout)
timeout = tonumber(timeout) or 8
check("transition guard owns the engine gate", type(Guard.engine_ready) == "function")

if type(Guard.engine_ready) == "function" then
  Guard.reset()
  check("fresh STOP_USE blocks the engine gate", Guard.engine_ready() == false)
  G.TIMERS.REAL = 1000 + timeout - 0.1
  check("STOP_USE remains blocked before the failsafe", Guard.engine_ready() == false)
  G.TIMERS.REAL = 1000 + timeout + 0.1
  check("persistent STOP_USE self-releases after the failsafe", Guard.engine_ready() == true)
  check("the same failsafe also releases the per-action STOP_USE guard",
    Guard.reject_reason("use_card") == nil and Guard.reject_reason("skip_booster") == nil)
  check("self-release does not mutate the engine flag", G.GAME.STOP_USE == 1)
  G.GAME.STOP_USE = 0
  check("a clear frame resets the engine gate", Guard.engine_ready() == true)
  G.GAME.STOP_USE = 1
  check("a new blockage receives a fresh grace period", Guard.engine_ready() == false)
  G.GAME.STOP_USE = 0
  Guard.reset()
  G.CONTROLLER.locked = true
  check("fresh controller lock blocks the engine gate", Guard.engine_ready() == false)
  G.TIMERS.REAL = G.TIMERS.REAL + timeout + 0.1
  check("persistent controller lock self-releases", Guard.engine_ready() == true)
  check("self-release does not mutate the controller lock", G.CONTROLLER.locked == true)
  G.CONTROLLER.locked = nil
  Guard.reset()
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
G.NEURO = {
  enabled = true, persona = "neuro", run_generation = 1,
  dispatcher = Dispatcher, actions = Actions,
  _decision_windows = {}, once_serials = {}, decision_serial = 1,
  state_enter_serial = 1, reserved_dollars = 0,
  state = "BLIND_SELECT", force_dirty = true, force_dirty_at = G.TIMERS.REAL,
  update = function() end,
  register_actions = function() end,
  unregister_actions = function() end,
  send_context = function() end,
  send_action_result = function() end,
}
function G.NEURO:force_actions(_ctx, _query, actions)
  forces[#forces + 1] = table.concat(actions, ",")
end

local Orch = require("core.orchestrator")
local HudState = require("hud.state")
G.GAME.STOP_USE = 1
Guard.reset()
Orch.reset_run_state()
G.NEURO.force_dirty = true
G.NEURO.force_dirty_at = G.TIMERS.REAL
HudState.state_changed_at = G.TIMERS.REAL
Orch._step_force_arming("BLIND_SELECT", G.TIMERS.REAL)
check("orchestrator emits nothing while the engine flag is fresh", #forces == 0, #forces)
G.TIMERS.REAL = G.TIMERS.REAL + timeout + Config.get("NEURO_FORCE_DEBOUNCE") + 0.2
Orch._step_force_arming("BLIND_SELECT", G.TIMERS.REAL)
check("orchestrator eventually emits through a stuck engine flag", #forces == 1, #forces)
Orch._step_unsent_window_guard()
check("the unsent-window guard leaves a window that already reached the wire alone",
  #forces == 1 and G.NEURO.force_inflight == true, #forces)
check("emitted force preserves the stuck engine flag", G.GAME.STOP_USE == 1)

done()
