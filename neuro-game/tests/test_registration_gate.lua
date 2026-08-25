_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("registration-gate")

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7 }
local CLOCK = 5000

local Orch = require("core.orchestrator")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Metrics = require("util.metrics")

local play_card = require("tests.helpers").play_card

local forces

local function board(register_ok)
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

  forces = {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = "SELECTING_HAND",
    update = function() end,
    send_context = function() end,
    send_action_result = function() end,
    register_actions = function(_self, _defs) return register_ok end,
    unregister_actions = function() end,
    force_actions = function(_self, _ctx, _query, actions)
      forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
      return true, { status = "written", written_at = G.TIMERS.REAL }
    end,
  }
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("registration-gate")
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

local function phase() return require("tests.helpers").force_phase(FS) end

do
  CLOCK = 5000
  board(true)
  tick_for(30)
  check("fixture: with registration succeeding, a force is armed and sent",
    #forces >= 1 and phase() == Window.FORCED, #forces .. "/" .. phase())
end

do
  CLOCK = 5000
  local before = Metrics._counters["action_registration_failed"] or 0
  board(false)
  tick_for(30)
  check("no force is ever armed while registration keeps failing",
    #forces == 0 and phase() ~= Window.FORCED, #forces .. "/" .. phase())
  check("the registration failure is counted",
    (Metrics._counters["action_registration_failed"] or 0) > before,
    tostring(Metrics._counters["action_registration_failed"]))
end

done()
