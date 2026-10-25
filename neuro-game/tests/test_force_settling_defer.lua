require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("force-settling-defer")

local Router = require("force.force_router")
local Guard = require("core.validate")
local Actions = require("core.actions")
local Tuning = require("core.config")

local joker = require("tests.helpers").flat_mult_joker

local tarot = require("tests.fake_cards").bare_tarot

local STATES = require("tests.engine_cards").states()

local function board(state, clock, generation)
  _G.G = {
    STATE = STATES[state], STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = clock }, SETTINGS = { GAMESPEED = 1 },
    GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0, last_tarot_planet = "c_pluto",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
      hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" } },
    NEURO = { run_generation = generation, once_serials = {}, decision_serial = 1,
      state_enter_serial = 1, plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 },
    jokers = { cards = { joker("j_joker", "Joker") }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
      select_blind = function() end, skip_booster = function() end,
      cash_out = function() end, toggle_shop = function() end },
    CONTROLLER = { locks = {} },
    blind_select = {},
  }
  Guard.reset_run_state()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
end

local function base(state)
  board(state, 1000, 1)
  G.FUNCS.use_card = function() end
  if state == "ROUND_EVAL" then require("tests.helpers").cash_out_ready(_G.G) end
  if state == "SHOP" then _G.G.shop = {} end
end

local signature = require("tests.helpers").force_signature

do
  base("BLIND_SELECT")
  local full = signature("BLIND_SELECT")
  check("fixture reproduces the live BLIND_SELECT force, its tools offered after the decision (force_router.offer)",
    full == "select_blind,sell_card,record_plan", tostring(full))

  Guard.note_applied("select_blind")
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  check("a latched progressive action defers the force instead of shipping a pruned list",
    signature("BLIND_SELECT") == nil, tostring(signature("BLIND_SELECT")))
  check("the latched action stays offerable, so she may still act on her own",
    Actions.is_action_valid("select_blind") == true)

  G.TIMERS.REAL = 1000 + 0.9
  check("the force returns with the full list once the engine latch expires",
    signature("BLIND_SELECT") == full, tostring(signature("BLIND_SELECT")))
end

do
  base("BLIND_SELECT")
  local full = signature("BLIND_SELECT")
  Guard.note_applied("select_blind")
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  local shapes, order = {}, {}
  for step = 0, 12 do
    G.TIMERS.REAL = 1000 + step * 0.12
    local sig = signature("BLIND_SELECT")
    if sig then
      order[#order + 1] = sig
      shapes[sig] = true
    end
  end
  local distinct = 0
  for _ in pairs(shapes) do distinct = distinct + 1 end
  check("polling across the latch window yields exactly one force shape",
    distinct == 1 and order[1] == full, tostring(distinct) .. " shapes")
  local aba = false
  for i = 3, #order do
    if order[i] == order[i - 2] and order[i] ~= order[i - 1] then aba = true end
  end
  check("no A/B/A alternation survives the latch window", aba == false)
end

do
  base("SHOP")
  G.shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} }
  G.shop_booster = { cards = {}, config = {} }
  G.shop_vouchers = { cards = {}, config = {} }
  local full = signature("SHOP")
  check("fixture builds a shop force", full and full:find("buy_from_shop", 1, true) ~= nil, tostring(full))

  -- The controller drops clicks while any lock is held, so shop buttons are unavailable.
  G.CONTROLLER.locks.toggle_shop = true
  local sig = signature("SHOP")
  check("a held controller lock defers the whole shop force",
    sig == nil or (sig:find("buy_from_shop", 1, true) == nil and sig:find("leave_shop", 1, true) == nil),
    tostring(sig))
end

do
  base("SHOP")
  G.shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} }
  G.shop_booster = { cards = {}, config = {} }
  G.shop_vouchers = { cards = {}, config = {} }
  G.CONTROLLER.locks.shop_reroll = true
  local sig = signature("SHOP")
  check("a settling reroll offers no purchase while its lock holds the controller",
    sig == nil or (sig:find("buy_from_shop", 1, true) == nil and sig:find("reroll_shop", 1, true) == nil),
    tostring(sig))
  G.CONTROLLER.locks.shop_reroll = nil
  sig = signature("SHOP")
  check("the purchase is offered again once the reroll lock releases",
    sig ~= nil and sig:find("buy_from_shop", 1, true) ~= nil, tostring(sig))
end

do
  base("SELECTING_HAND")
  G.hand.cards = { { sort_id = 1, base = { value = "Ace", suit = "Spades" },
    ability = { set = "Default", name = "M" }, config = { center = {} },
    juice_up = function() end, highlight = function() end } }
  G.consumeables.cards = { tarot() }
  G.GAME.STOP_USE = 3
  local sig = signature("SELECTING_HAND")
  check("a settling consumable does not defer while a hand can still be played",
    sig ~= nil and sig:find("play_hand", 1, true) ~= nil
      and sig:find("choose_pack_card", 1, true) == nil, tostring(sig))
end

do
  base("SMODS_BOOSTER_OPENED")
  G.pack_cards = { cards = { tarot() }, config = {} }
  local full = signature("SMODS_BOOSTER_OPENED")
  check("fixture builds a pack force", full == "choose_pack_card,skip_pack", tostring(full))

  G.GAME.STOP_USE = 3
  check("a pack whose every action is settling defers", signature("SMODS_BOOSTER_OPENED") == nil)
  G.TIMERS.REAL = 1000 + 4.0
  check("the defer holds while the engine flag is fresh", signature("SMODS_BOOSTER_OPENED") == nil)
  G.TIMERS.REAL = 1000 + 8.5
  check("the failsafe releases the force even if the engine never clears the flag",
    signature("SMODS_BOOSTER_OPENED") ~= nil, tostring(signature("SMODS_BOOSTER_OPENED")))

  G.GAME.STOP_USE = 0
  signature("SMODS_BOOSTER_OPENED")

  local Config = require("core.config")
  local default_failsafe = Config.get("NEURO_ROUTER_DEFER_FAILSAFE")
  Config.set("NEURO_ROUTER_DEFER_FAILSAFE", default_failsafe + 4.0)
  local new_failsafe = Config.get("NEURO_ROUTER_DEFER_FAILSAFE")

  G.TIMERS.REAL = 1000 + 30.0
  G.GAME.STOP_USE = 3
  check("fresh STOP_USE with new clock: defer engages again", signature("SMODS_BOOSTER_OPENED") == nil)

  G.TIMERS.REAL = 1000 + 30.0 + default_failsafe + 0.5
  check("old config window would have released; current config still holds",
    signature("SMODS_BOOSTER_OPENED") == nil,
    tostring(signature("SMODS_BOOSTER_OPENED")))

  G.TIMERS.REAL = 1000 + 30.0 + new_failsafe - 0.5
  check("just before new failsafe: defer still holds", signature("SMODS_BOOSTER_OPENED") == nil)

  G.TIMERS.REAL = 1000 + 30.0 + new_failsafe + 0.1
  check("after new failsafe: force returns again",
    signature("SMODS_BOOSTER_OPENED") ~= nil, tostring(signature("SMODS_BOOSTER_OPENED")))

  Config.set("NEURO_ROUTER_DEFER_FAILSAFE", default_failsafe)
end

do
  base("ROUND_EVAL")
  check("fixture builds a round-eval force", signature("ROUND_EVAL") == "cash_out")
  Guard.note_applied("cash_out")
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  check("a latched cash_out defers rather than emitting an empty round-eval force",
    signature("ROUND_EVAL") == nil)
  G.TIMERS.REAL = 1000 + 1.2
  check("cash_out comes back when its latch expires", signature("ROUND_EVAL") == "cash_out")
end

do
  base("BLIND_SELECT")
  local first = signature("BLIND_SELECT")
  local second = signature("BLIND_SELECT")
  check("a state with nothing settling is untouched by the defer path",
    first ~= nil and first == second, tostring(first))
end

local FAILSAFE = Tuning.get("NEURO_ROUTER_DEFER_FAILSAFE")

local function latch_base(clock, generation)
  board("BLIND_SELECT", clock, generation)
  Router._guard_defer_generation = nil
end

local function deferred()
  return Router.get_force_for_state("BLIND_SELECT") == nil
end

do
  latch_base(9000, 1)
  Guard.note_applied("select_blind")
  check("latch arms on the pre-reset clock", deferred() and Router._guard_defer_at == 9000,
    tostring(Router._guard_defer_at))

  G.TIMERS.REAL = 3
  G.NEURO.run_generation = 2
  Guard.note_applied("select_blind")
  check("the latch re-arms on the new clock instead of keeping the pre-reset stamp",
    deferred() and Router._guard_defer_at == 3, tostring(Router._guard_defer_at))

  G.TIMERS.REAL = 3 + FAILSAFE + 0.1
  Guard.note_applied("select_blind")
  check("the deferral expires on the new clock rather than waiting out the old one",
    not deferred(), tostring(Router._guard_defer_at))
end

do
  latch_base(9000, 1)
  Guard.note_applied("select_blind")
  check("latch armed before the reconnect", deferred() and Router._guard_defer_at == 9000)

  G.NEURO = { run_generation = 4, once_serials = {},
    decision_serial = 1, state_enter_serial = 1,
    plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 }
  G.TIMERS.REAL = 9000 + FAILSAFE * 0.5
  Guard.note_applied("select_blind")
  check("a new run generation restarts the deferral window",
    deferred() and Router._guard_defer_at == 9000 + FAILSAFE * 0.5,
    tostring(Router._guard_defer_at))
end

do
  latch_base(9000, 1)
  Guard.note_applied("select_blind")
  check("latch armed before the reconnect that reuses generation 1",
    deferred() and Router._guard_defer_at == 9000)

  G.NEURO = { run_generation = 1, once_serials = {},
    decision_serial = 1, state_enter_serial = 1,
    plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 }
  G.TIMERS.REAL = 5
  Guard.note_applied("select_blind")
  check("a rewound clock re-arms the latch even when the generation number repeats",
    deferred() and Router._guard_defer_at == 5, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 5 + FAILSAFE + 0.1
  Guard.note_applied("select_blind")
  check("and the deferral then expires on the rewound clock", not deferred())
end

do
  latch_base(1000, 1)
  Guard.note_applied("select_blind")
  check("same run, same state: the latch keeps its original stamp",
    deferred() and Router._guard_defer_at == 1000, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 1000 + FAILSAFE * 0.5
  Guard.note_applied("select_blind")
  check("mid-window polling does not restart the deferral",
    deferred() and Router._guard_defer_at == 1000, tostring(Router._guard_defer_at))
  G.TIMERS.REAL = 1000 + FAILSAFE + 0.1
  Guard.note_applied("select_blind")
  check("the window still expires exactly once the failsafe has elapsed", not deferred())
end

done()
