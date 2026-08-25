_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-router-latch-lifecycle")

local Router = require("force.force_router")
local Guard = require("core.transition_guard")
local Tuning = require("core.config")

local FAILSAFE = Tuning.get("NEURO_ROUTER_DEFER_FAILSAFE")

local joker = require("tests.helpers").flat_mult_joker

local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7 }

local function base(clock, generation)
  _G.G = {
    STATE = STATES.BLIND_SELECT, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = clock }, SETTINGS = { GAMESPEED = 1 },
    GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
      hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" } },
    NEURO = { run_generation = generation, _decision_windows = {}, once_serials = {},
      decision_serial = 1, state_enter_serial = 1,
      plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 },
    jokers = { cards = { joker("j_joker", "Joker") }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end, skip_booster = function() end,
      cash_out = function() end, toggle_shop = function() end },
    CONTROLLER = { locks = {} },
    blind_select = {},
  }
  Guard.reset()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  Router._guard_defer_generation = nil
end

local function deferred()
  return Router.get_force_for_state("BLIND_SELECT") == nil
end

do
  base(9000, 1)
  Guard.mark("select_blind")
  check("latch arms on the pre-reset clock", deferred() and Router._guard_defer_at == 9000,
    tostring(Router._guard_defer_at))

  G.TIMERS.REAL = 3
  G.NEURO.run_generation = 2
  Guard.mark("select_blind")
  check("the latch re-arms on the new clock instead of keeping the pre-reset stamp",
    deferred() and Router._guard_defer_at == 3, tostring(Router._guard_defer_at))

  G.TIMERS.REAL = 3 + FAILSAFE + 0.1
  Guard.mark("select_blind")
  check("the deferral expires on the new clock rather than waiting out the old one",
    not deferred(), tostring(Router._guard_defer_at))
end

do
  base(9000, 1)
  Guard.mark("select_blind")
  check("latch armed before the reconnect", deferred() and Router._guard_defer_at == 9000)

  G.NEURO = { run_generation = 4, _decision_windows = {}, once_serials = {},
    decision_serial = 1, state_enter_serial = 1,
    plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 }
  G.TIMERS.REAL = 9000 + FAILSAFE * 0.5
  Guard.mark("select_blind")
  check("a new run generation restarts the deferral window",
    deferred() and Router._guard_defer_at == 9000 + FAILSAFE * 0.5,
    tostring(Router._guard_defer_at))
  check("the latch records the generation it was armed under",
    Router._guard_defer_generation == 4, tostring(Router._guard_defer_generation))
end

do
  base(9000, 1)
  Guard.mark("select_blind")
  check("latch armed before the reconnect that reuses generation 1",
    deferred() and Router._guard_defer_at == 9000)

  G.NEURO = { run_generation = 1, _decision_windows = {}, once_serials = {},
    decision_serial = 1, state_enter_serial = 1,
    plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 }
  G.TIMERS.REAL = 5
  Guard.mark("select_blind")
  check("a rewound clock re-arms the latch even when the generation number repeats",
    deferred() and Router._guard_defer_at == 5, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 5 + FAILSAFE + 0.1
  Guard.mark("select_blind")
  check("and the deferral then expires on the rewound clock", not deferred())
end

do
  base(1000, 1)
  Guard.mark("select_blind")
  check("same run, same state: the latch keeps its original stamp",
    deferred() and Router._guard_defer_at == 1000, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 1000 + FAILSAFE * 0.5
  Guard.mark("select_blind")
  check("mid-window polling does not restart the deferral",
    deferred() and Router._guard_defer_at == 1000, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 1000 + FAILSAFE + 0.1
  Guard.mark("select_blind")
  check("the window still expires exactly once the failsafe has elapsed", not deferred())
end

do
  base(1000, 1)
  Guard.mark("select_blind")
  check("latch armed", deferred() and Router._guard_defer_generation == 1)
  Guard.reset()
  Router.get_force_for_state("BLIND_SELECT")
  check("an unpruned tick clears the whole latch",
    Router._guard_defer_at == nil and Router._guard_defer_state == nil
      and Router._guard_defer_generation == nil,
    tostring(Router._guard_defer_at) .. "/" .. tostring(Router._guard_defer_generation))
end

done()
