_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-delivery-bound")

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7 }
local CLOCK = 5000

local Orch = require("core.orchestrator")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Metrics = require("util.metrics")

local play_card = require("tests.helpers").play_card

local function board()
  _G.G = {
    STATE = STATES.SELECTING_HAND, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = CLOCK }, SETTINGS = { GAMESPEED = 1 },
    OVERLAY_MENU = nil, screenwipe = nil,
    GAME = {
      dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, STOP_USE = 0,
      blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Small Blind" },
      hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_hook = { key = "bl_hook", name = "The Hook" } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = "SELECTING_HAND",
    update = function() end,
    send_context = function() end,
    send_action_result = function() end,
    register_actions = function() return true end,
    unregister_actions = function() end,
    force_actions = function() return true, { status = "buffered" } end,
    cancel_force_actions = function() return { status = "rejected" } end,
    complete_force_cancellation = function() return true end,
  }
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("force-delivery-bound")
  require("core.action_registry").reset()
  require("core.tx_cache").reset()
  Orch.reset_run_state()
end

local function tick_for(seconds)
  for _ = 1, math.floor(seconds / 0.1) do
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) break end
  end
end

local function tick_until(pred, max_seconds)
  local budget = math.floor((max_seconds or 60) / 0.1)
  for _ = 1, budget do
    if pred() then return true end
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) return false end
  end
  return pred()
end

local function phase() return require("tests.helpers").force_phase(FS) end

CLOCK = 5000
board()
local armed = tick_until(function() return phase() == Window.FORCED end, 15)
check("fixture: the force went out but is only buffered, not written",
  armed and phase() == Window.FORCED, phase())

check("force_sent_at stays nil for a buffered force -- its liveness clock has not started",
  G.NEURO.force_sent_at == nil, tostring(G.NEURO.force_sent_at))

local sent_wall = CLOCK
local before_metric = Metrics._counters["force_delivery_timeout"] or 0

tick_for(FS.FORCE_LIVENESS_TIMEOUT - 20)
check("still within the delivery bound, the window is not yet torn down",
  phase() == Window.FORCED, phase())
check("and force_sent_at is still nil this whole time -- the deadline never quietly started",
  G.NEURO.force_sent_at == nil, tostring(G.NEURO.force_sent_at))

local torn_down = tick_until(function() return phase() ~= Window.FORCED end, 60)
check("past the delivery bound the window is torn down even though force_sent_at never started",
  torn_down, phase())
check("it happens no earlier than the bound itself",
  (CLOCK - sent_wall) >= FS.FORCE_LIVENESS_TIMEOUT, CLOCK - sent_wall)
check("and it is counted as a delivery timeout, not an ordinary liveness timeout",
  (Metrics._counters["force_delivery_timeout"] or 0) > before_metric,
  tostring(Metrics._counters["force_delivery_timeout"]))

done()
