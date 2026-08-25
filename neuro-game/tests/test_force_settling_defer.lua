_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-settling-defer")

local Router = require("force.force_router")
local Guard = require("core.transition_guard")
local Actions = require("core.actions")

local joker = require("tests.helpers").flat_mult_joker

local function tarot()
  return { ability = { set = "Tarot", consumeable = {} },
    config = { center = { key = "c_fool", set = "Tarot", name = "The Fool" } } }
end

local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7 }

local function base(state)
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
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end, skip_booster = function() end,
      cash_out = function() end, toggle_shop = function() end },
    CONTROLLER = { locks = {} },
    blind_select = {},
  }
  if state == "ROUND_EVAL" then _G.G.round_eval = {} end
  if state == "SHOP" then _G.G.shop = {} end
  Guard.reset()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
end

local function signature(state)
  local force = Router.get_force_for_state(state)
  if not force then return nil end
  return table.concat(force.actions, ",")
end

do
  base("BLIND_SELECT")
  local full = signature("BLIND_SELECT")
  check("fixture reproduces the live BLIND_SELECT force",
    full == "select_blind,sell_card,set_plan", tostring(full))

  Guard.mark("select_blind")
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
  Guard.mark("select_blind")
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

  G.CONTROLLER.locks.toggle_shop = true
  local sig = signature("SHOP")
  check("a locked forfeit action alone never defers the force",
    sig ~= nil and sig:find("buy_from_shop", 1, true) ~= nil
      and sig:find("toggle_shop", 1, true) == nil, tostring(sig))
end

do
  base("SHOP")
  G.shop_jokers = { cards = { joker("j_a", "Alpha") }, config = {} }
  G.shop_booster = { cards = {}, config = {} }
  G.shop_vouchers = { cards = {}, config = {} }
  G.CONTROLLER.locks.shop_reroll = true
  local sig = signature("SHOP")
  check("a settling reroll does not defer while a purchase is still open",
    sig ~= nil and sig:find("buy_from_shop", 1, true) ~= nil
      and sig:find("reroll_shop", 1, true) == nil, tostring(sig))
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
      and sig:find("use_card", 1, true) == nil, tostring(sig))
end

do
  base("TAROT_PACK")
  G.pack_cards = { cards = { tarot() }, config = {} }
  local full = signature("TAROT_PACK")
  check("fixture builds a pack force", full == "use_card,skip_booster", tostring(full))

  G.GAME.STOP_USE = 3
  check("a pack whose every action is settling defers", signature("TAROT_PACK") == nil)
  G.TIMERS.REAL = 1000 + 4.0
  check("the defer holds while the engine flag is fresh", signature("TAROT_PACK") == nil)
  G.TIMERS.REAL = 1000 + 8.5
  check("the failsafe releases the force even if the engine never clears the flag",
    signature("TAROT_PACK") ~= nil, tostring(signature("TAROT_PACK")))

  G.GAME.STOP_USE = 0
  signature("TAROT_PACK")
  check("after engine settles: defer timestamp is cleared",
    Router._guard_defer_at == nil,
    "at=" .. tostring(Router._guard_defer_at))
  check("after engine settles: defer state is cleared",
    Router._guard_defer_state == nil,
    "state=" .. tostring(Router._guard_defer_state))

  local Config = require("core.config")
  local default_failsafe = Config.get("NEURO_ROUTER_DEFER_FAILSAFE")
  Config.set("NEURO_ROUTER_DEFER_FAILSAFE", default_failsafe + 4.0)
  local new_failsafe = Config.get("NEURO_ROUTER_DEFER_FAILSAFE")

  G.TIMERS.REAL = 1000 + 30.0
  G.GAME.STOP_USE = 3
  check("fresh STOP_USE with new clock: defer engages again", signature("TAROT_PACK") == nil)
  check("new defer timestamp equals current clock",
    Router._guard_defer_at == G.TIMERS.REAL and Router._guard_defer_state == "TAROT_PACK",
    "at=" .. tostring(Router._guard_defer_at) .. " clock=" .. tostring(G.TIMERS.REAL)
      .. " state=" .. tostring(Router._guard_defer_state))

  G.TIMERS.REAL = 1000 + 30.0 + default_failsafe + 0.5
  check("old config window would have released; current config still holds",
    signature("TAROT_PACK") == nil,
    tostring(signature("TAROT_PACK")))

  G.TIMERS.REAL = 1000 + 30.0 + new_failsafe - 0.5
  check("just before new failsafe: defer still holds", signature("TAROT_PACK") == nil)
  check("guard fields survive across the defer window",
    Router._guard_defer_at ~= nil and Router._guard_defer_state == "TAROT_PACK")

  G.TIMERS.REAL = 1000 + 30.0 + new_failsafe + 0.1
  check("after new failsafe: force returns again",
    signature("TAROT_PACK") ~= nil, tostring(signature("TAROT_PACK")))
  check("after new failsafe: force does not re-defer (defer cycle complete)",
    signature("TAROT_PACK") ~= nil)

  Config.set("NEURO_ROUTER_DEFER_FAILSAFE", default_failsafe)
end

do
  base("ROUND_EVAL")
  check("fixture builds a round-eval force", signature("ROUND_EVAL") == "cash_out")
  Guard.mark("cash_out")
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

done()
