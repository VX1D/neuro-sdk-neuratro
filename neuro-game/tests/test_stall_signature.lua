_G.NEURO_TEST = true
local wall = 0
love = { timer = { getTime = function() return wall end } }
local STATES = { BLIND_SELECT = 1, SELECTING_HAND = 3, SHOP = 5, MENU = 11, SPLASH = 12, ROUND_EVAL = 8 }
_G.G = {
  STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
  GAME = { dollars = 20, round = 1, chips = 0, STOP_USE = 0,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 1, blind_choices = {}, blind_states = {} },
    used_vouchers = {}, modifiers = {}, hands = {} },
  FUNCS = {}, CONTROLLER = { locks = {} }, E_MANAGER = { queues = {} },
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  deck = { cards = {} },
  shop_jokers = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {}, config = { card_limit = 1 } },
  shop_booster = { cards = {}, config = { card_limit = 2 } },
}
_G.SMODS = { Mods = {} }
local Utils = require("util.utils")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)
local Orch = require("core.orchestrator")
local Lifecycle = require("core.neuro_lifecycle")
local S = require("hud.state")

local check, done = require("tests.helpers").harness("stall-signature")

local function fresh_neuro()
  G.NEURO = {
    enabled = true, persona = "neuro", llm_paused = false, run_generation = 1,
    state = "SHOP", reserved_dollars = 0, decision_serial = 1, state_enter_serial = 1,
    _decision_windows = {}, once_serials = {},
    update = function() end, send_context = function() end,
    send_action_result = function() end, register_actions = function() end,
    unregister_actions = function() end, force_actions = function() return false end,
  }
  S.state_changed_at, S.state_changed_at_game = 0, 0
  Orch.reset_run_state()
end

local FORCE_STALL = Config.get("NEURO_FORCE_STALL")
check("fixture: stall threshold is the expected knob", type(FORCE_STALL) == "number" and FORCE_STALL > 0,
  tostring(FORCE_STALL))

local function tick(seconds, poke_every)
  local dt, t = 1 / 60, 0
  local fired = 0
  local last_poke = -1e9
  while t < seconds do
    G.TIMERS.REAL = G.TIMERS.REAL + dt
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + dt
    wall = wall + dt
    Utils.observe_clock()
    if poke_every and (t - last_poke) >= poke_every then
      last_poke = t
      Lifecycle.mark_force_dirty()
    end
    if Orch._step_force_stall() then fired = fired + 1 end
    t = t + dt
  end
  return fired
end

wall = 0
fresh_neuro()
local fired_idle = tick(FORCE_STALL * 3)
check("idle arm: the watchdog fires repeatedly while nothing happens", fired_idle >= 2,
  "fired " .. tostring(fired_idle))

wall = 0
fresh_neuro()
local fired_live = tick(FORCE_STALL * 3, 0.12)
check("live arm: the watchdog still fires while force_dirty_at churns but everything else holds",
  fired_live >= 2, "fired " .. tostring(fired_live))

done()
