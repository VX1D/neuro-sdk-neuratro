_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-availability-parity")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Router = require("force.force_router")
local Guard = require("core.transition_guard")

local joker = require("tests.helpers").flat_mult_joker
local function tarot()
  return { ability = { set = "Tarot", consumeable = {} },
    config = { center = { key = "c_fool", set = "Tarot", name = "The Fool" } } }
end
local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7 }

local function base(state, extras)
  _G.G = {
    STATE = STATES[state], STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
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
    NEURO = { run_generation = 1, _decision_windows = {}, once_serials = {}, decision_serial = 1,
      state_enter_serial = 1, plan = { hand_plan = "x", build_plan = "y" }, reserved_dollars = 0 },
    jokers = { cards = { joker("j_joker", "Joker") }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end },
    CONTROLLER = { locks = {} },
  }
  for k, v in pairs(extras or {}) do
    if v == "NIL" then G[k] = nil else G[k] = v end
  end
  Guard.reset()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
end

local function advertised(state, name)
  local force = Router.get_force_for_state(state)
  if not force or not force.actions then return false end
  for _, a in ipairs(force.actions) do if a == name then return true end end
  return false
end

local function preflight_ok(name, payload)
  local ok, exec = pcall(Dispatcher.preflight, name, payload or {})
  return ok and type(exec) == "function"
end

local EMPTY_FUNCS = { get_poker_hand_info = function() end }

do
  base("ROUND_EVAL")
  check("cash_out: missing G.round_eval makes availability false",
    Actions.is_action_valid("cash_out") == false)
  check("cash_out: missing G.round_eval is not advertised",
    advertised("ROUND_EVAL", "cash_out") == false)

  base("ROUND_EVAL", { round_eval = true })
  check("cash_out: G.round_eval without a callback makes availability false",
    Actions.is_action_valid("cash_out") == false)
  check("cash_out: G.round_eval without a callback is not advertised",
    advertised("ROUND_EVAL", "cash_out") == false)

  base("ROUND_EVAL", { round_eval = true, FUNCS = { get_poker_hand_info = function() end, cash_out = function() end } })
  check("cash_out: a complete fixture makes availability true",
    Actions.is_action_valid("cash_out") == true)
  check("cash_out: a complete fixture returns an execution closure",
    preflight_ok("cash_out", {}))
  check("cash_out: a complete fixture is advertised",
    advertised("ROUND_EVAL", "cash_out") == true)

  Guard.mark("cash_out")
  check("cash_out: the latch remains guard-owned and availability stays true",
    Actions.is_action_valid("cash_out") == true)
  check("cash_out: the latch defers force at the guard layer",
    advertised("ROUND_EVAL", "cash_out") == false)
  G.TIMERS.REAL = 1000 + 1.2
  check("cash_out: force returns after the latch expires",
    advertised("ROUND_EVAL", "cash_out") == true)
end

do
  base("TAROT_PACK")
  check("skip_booster: a missing pack area makes availability false",
    Actions.is_action_valid("skip_booster") == false)
  check("skip_booster: a missing pack area is not advertised",
    advertised("TAROT_PACK", "skip_booster") == false)

  base("TAROT_PACK", { pack_cards = { cards = { tarot() }, config = {} } })
  check("skip_booster: a pack area without a callback makes availability false",
    Actions.is_action_valid("skip_booster") == false)
  check("skip_booster: a pack area without a callback is not advertised",
    advertised("TAROT_PACK", "skip_booster") == false)

  base("TAROT_PACK", { pack_cards = { cards = { tarot() }, config = {} },
    FUNCS = { get_poker_hand_info = function() end, skip_booster = function() end } })
  check("skip_booster: a complete fixture makes availability true",
    Actions.is_action_valid("skip_booster") == true)
  check("skip_booster: a complete fixture returns an execution closure",
    preflight_ok("skip_booster", {}))
  check("skip_booster: a complete fixture is advertised",
    advertised("TAROT_PACK", "skip_booster") == true)

  G.GAME.STOP_USE = 3
  check("skip_booster: STOP_USE is guard-owned and availability stays true",
    Actions.is_action_valid("skip_booster") == true)
  check("skip_booster: STOP_USE defers force at the guard layer",
    advertised("TAROT_PACK", "skip_booster") == false)
  local _, err = Dispatcher.preflight("skip_booster", {})
  check("skip_booster: STOP_USE makes preflight return the guard diagnostic",
    err ~= nil and tostring(err):find("resolving", 1, true) ~= nil, tostring(err))
end

do
  base("SHOP", { shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} },
    shop_booster = { cards = {}, config = {} }, shop_vouchers = { cards = {}, config = {} } })
  check("toggle_shop: missing G.shop makes availability false",
    Actions.is_action_valid("toggle_shop") == false)
  check("toggle_shop: missing G.shop is not advertised",
    advertised("SHOP", "toggle_shop") == false)

  base("SHOP", { shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} },
    shop_booster = { cards = {}, config = {} }, shop_vouchers = { cards = {}, config = {} },
    shop = {} })
  check("toggle_shop: G.shop without a callback makes availability false",
    Actions.is_action_valid("toggle_shop") == false)
  check("toggle_shop: G.shop without a callback is not advertised",
    advertised("SHOP", "toggle_shop") == false)

  base("SHOP", { shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} },
    shop_booster = { cards = {}, config = {} }, shop_vouchers = { cards = {}, config = {} },
    shop = {}, FUNCS = { get_poker_hand_info = function() end, toggle_shop = function() end } })
  check("toggle_shop: a complete fixture makes availability true",
    Actions.is_action_valid("toggle_shop") == true)
  check("toggle_shop: a complete fixture returns an execution closure",
    preflight_ok("toggle_shop", {}))
  check("toggle_shop: a complete fixture is advertised",
    advertised("SHOP", "toggle_shop") == true)

  G.CONTROLLER.locks.toggle_shop = true
  check("toggle_shop: the lock is guard-owned and availability stays true",
    Actions.is_action_valid("toggle_shop") == true)
  check("toggle_shop: the lock suppresses force at the guard layer",
    advertised("SHOP", "toggle_shop") == false)
end

done()
