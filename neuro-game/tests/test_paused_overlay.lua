_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("paused-overlay")

local STATES = { MENU = 11, SPLASH = 12, SELECTING_HAND = 3, BLIND_SELECT = 1, SHOP = 2,
  GAME_OVER = 4, TAROT_PACK = 6, ROUND_EVAL = 7 }

local overlay = {}
function overlay:get_UIE_by_ID(id)
  if id == "run_setup_seed" then return { config = {} } end
  return nil
end

_G.G = {
  STATE = STATES.MENU, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 100, TOTAL = 100 },
  SETTINGS = { GAMESPEED = 1, paused = true },
  SPEEDFACTOR = 1,
  STAGE = 1, STAGES = { MAIN_MENU = 1, RUN = 2 },
  OVERLAY_MENU = overlay,
  GAME = { dollars = 4, stake = 1, selected_back = "b_red", viewed_back = "b_red",
    current_round = {}, round_resets = { ante = 1, blind_states = {}, blind_choices = {} },
    used_vouchers = {}, modifiers = {}, hands = {}, STOP_USE = 0 },
  P_CENTER_POOLS = { Back = {} },
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  deck = { cards = {} },
  shop_jokers = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {}, config = { card_limit = 1 } },
  shop_booster = { cards = {}, config = { card_limit = 2 } },
  CHALLENGES = {},
  FUNCS = { start_setup_run = function() end, exit_overlay_menu = function() end,
    toggle_seeded_run = function() end, change_selected_back = function() end },
  CONTROLLER = { locks = {} },
  E_MANAGER = { queues = {} },
}
_G.SMODS = { Mods = {} }

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local State = require("core.state")

local forces, registers = {}, {}
G.NEURO = {
  enabled = true, persona = "neuro", run_generation = 1,
  dispatcher = Dispatcher, actions = Actions,
  _decision_windows = {}, once_serials = {}, decision_serial = 1,
  state_enter_serial = 1, reserved_dollars = 0,
  update = function() end,
  send_context = function() end,
  send_action_result = function() end,
}
function G.NEURO:register_actions(defs)
  local names = {}
  for _, d in ipairs(defs or {}) do names[#names + 1] = d.name end
  registers[#registers + 1] = names
end
function G.NEURO:unregister_actions() end
function G.NEURO:force_actions(_, _, actions)
  forces[#forces + 1] = table.concat(actions, ",")
end

local Orch = require("core.orchestrator")

local function frame(dt)
  G.TIMERS.REAL = G.TIMERS.REAL + dt
  if not G.SETTINGS.paused then
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + dt * G.SPEEDFACTOR
  end
  pcall(Orch.update, dt)
end

check("the overlay reads as RUN_SETUP", State.get_state_name() == "RUN_SETUP",
  State.get_state_name())
check("start_setup_run is valid on it, so registration is not the failure",
  Actions.is_action_valid("start_setup_run") == true)

local setup_force = require("force.menu_flow").run_setup()
check("the RUN_SETUP builder yields a force, not nil",
  type(setup_force) == "table" and #setup_force.actions > 0,
  setup_force and #setup_force.actions or "nil")

local frozen_total = G.TIMERS.TOTAL
for _ = 1, 600 do frame(1 / 60) end
check("ten wall seconds of the paused overlay leave the game clock where it was",
  G.TIMERS.TOTAL == frozen_total, G.TIMERS.TOTAL .. " vs " .. frozen_total)
check("the run-setup actions were registered", #registers > 0 and #registers[1] >= 5,
  registers[1] and #registers[1] or 0)
check("a force reaches the wire while the run-setup overlay holds the game paused",
  #forces >= 1, #forces .. " forces in 10s")
check("and it is the run-setup force, offering the action that starts the run",
  forces[1] ~= nil and forces[1]:find("start_setup_run", 1, true) ~= nil, forces[1])

done()
