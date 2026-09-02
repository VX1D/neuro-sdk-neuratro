_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("context-pruning")

local CtxJokers = require("context.ctx_jokers")
local CtxShop = require("context.ctx_shop")

local STATES = { SELECTING_HAND = 1, SHOP = 5, BLIND_SELECT = 7 }

local function joker(ability)
  local ab = ability or {}
  ab.name, ab.set = ab.name or "Joker", "Joker"
  ab.mult = ab.mult or 4
  return { cost = 4, sell_cost = 3, ability = ab, debuff = false,
    config = { center = { key = "j_joker", name = "Joker", set = "Joker",
      loc_txt = { name = "Joker", description = "+4 Mult" } } } }
end

local function world(state, blind, ability)
  _G.G = {
    STATE = STATES[state], STATES = STATES,
    GAME = { dollars = 8, chips = 0, bankrupt_at = 0, used_vouchers = {},
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 2 }, probabilities = { normal = 1 },
      blind = blind, modifiers = {} },
    NEURO = {},
    jokers = { cards = { joker(ability) }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
  return CtxJokers.jokers_section() or ""
end

local LEAF = { name = "Verdant Leaf", key = "bl_final_leaf", disabled = false }
local PLANT = { name = "The Plant", key = "bl_plant", disabled = false }

local s_hand = world("SELECTING_HAND", PLANT)
check("the joker row a sell price would ride on is rendered",
  s_hand:find("1. Joker -- +4 Mult", 1, true) ~= nil, s_hand)
check("no sell value on joker rows while the round blocks selling",
  s_hand:find("(sell ", 1, true) == nil, s_hand)

local s_leaf = world("SELECTING_HAND", LEAF)
check("the sell value survives under the boss that requires selling",
  s_leaf:find("(sell $3)", 1, true) ~= nil, s_leaf)

local s_shop = world("SHOP", nil)
check("the sell value survives where selling is offered",
  s_shop:find("(sell $3)", 1, true) ~= nil, s_shop)

local s_plain = world("SHOP", nil)
check("the unstickered joker row is rendered",
  s_plain:find("1. Joker -- +4 Mult", 1, true) ~= nil, s_plain)
check("a joker with no stickers carries no empty flag marker",
  s_plain:find("[-]", 1, true) == nil, s_plain)

local s_eternal = world("SHOP", nil, { eternal = true })
check("a joker with a sticker still carries its flag group",
  s_eternal:find("[cannot be sold]", 1, true) ~= nil, s_eternal)
check("an eternal joker quotes no sell price next to 'cannot be sold'",
  s_eternal:find("(sell ", 1, true) == nil and s_eternal:find("bought", 1, true) == nil, s_eternal)

local s_rental = world("SHOP", nil, { rental = true })
check("a sellable sticker keeps its sell price",
  s_rental:find("(sell $3)", 1, true) ~= nil, s_rental)

local s_foil = world("SHOP", nil)
G.jokers.cards[1].edition = { foil = true, key = "e_foil", type = "foil" }
s_foil = CtxJokers.jokers_section() or ""
check("an edition still carries its flag group",
  s_foil:find("[Foil", 1, true) ~= nil, s_foil)

local function shop_world(dollars, stock_cost)
  _G.G = {
    STATE = STATES.SHOP, STATES = STATES,
    GAME = { dollars = dollars, bankrupt_at = 0, used_vouchers = {}, chips = 0,
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 2 }, probabilities = { normal = 1 }, modifiers = {} },
    NEURO = { reserved_dollars = 0, shop_reroll_count = 0 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { { cost = stock_cost, ability = { name = "Joker", set = "Joker" },
      config = { center = { key = "j_joker", name = "Joker", set = "Joker",
        loc_txt = { name = "Joker", description = "+4 Mult" } } } } } },
    shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    shop = { reroll_cost = 5 },
  }
end

shop_world(0, 6)
local broke = CtxShop.legality_section("SHOP", { buy_from_shop = true, reroll_shop = true }) or ""
check("a broke shop reports both buying and rerolling as illegal",
  broke:find("can buy something: no", 1, true) ~= nil
  and broke:find("can reroll: no", 1, true) ~= nil, broke)
check("no plan requirement is quoted for buying once the same line calls it illegal",
  broke:find("buying: include", 1, true) == nil, broke)
check("no plan requirement is quoted for rerolling once the same line calls it illegal",
  broke:find("rerolling: include", 1, true) == nil, broke)

shop_world(30, 4)
local rich = CtxShop.legality_section("SHOP", { buy_from_shop = true, reroll_shop = true }) or ""
check("a funded shop still reports buying as legal",
  rich:find("can buy something: yes", 1, true) ~= nil, rich)
check("the plan requirement for buying survives while buying is legal",
  rich:find("buying: include plan.money_plan", 1, true) ~= nil, rich)

do
  local ShopHandlers = require("handlers.shop_handlers")

  local j_bought = {
    sort_id = 501, cost = 6, sell_cost = 3,
    ability = { name = "Joker", set = "Joker" },
    config = { center = { key = "j_joker", set = "Joker" } }
  }
  local j_pack = {
    sort_id = 502, cost = 8, sell_cost = 4,
    ability = { name = "Luchador", set = "Joker" },
    config = { center = { key = "j_luchador", set = "Joker" } }
  }
  local j_free = {
    sort_id = 503, cost = 0, sell_cost = 1,
    ability = { name = "Diet Cola", set = "Joker" },
    config = { center = { key = "j_diet_cola", set = "Joker" } }
  }

  _G.G = {
    STATE = 1, STATES = { SHOP = 1 },
    GAME = { dollars = 20, used_vouchers = {}, current_round = {} },
    NEURO = { reserved_dollars = 0 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { j_bought } },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
    FUNCS = { buy_from_shop = function() return true end },
  }

  local exec = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("handle_buy_from_shop returns an execution function", type(exec) == "function")
  if type(exec) == "function" then exec() end

  check("the purchase price is recorded in G.NEURO.joker_bought_cost",
    G.NEURO.joker_bought_cost and G.NEURO.joker_bought_cost[501] == 6)
  check("purchase tracking holds no object reference and keys only by sort_id"
      .. " (the engine assigns sort_id to every card from a counter that never resets, so"
      .. " the object key was unnecessary and kept the card alive for the entire round)",
    G.NEURO.joker_bought_cost[j_bought] == nil, tostring(G.NEURO.joker_bought_cost[j_bought]))

  G.NEURO.joker_bought_cost[503] = 0

  j_bought.cost = 2

  G.jokers.cards = { j_bought, j_pack, j_free }
  local out = CtxJokers.jokers_section() or ""

  check("a purchased joker shows its real purchase price despite a later card.cost change",
    out:find("(bought $6, sell $3)", 1, true) ~= nil, out)
  check("a joker from a pack does not show a false bought annotation despite positive card.cost",
    out:find("Luchador (sell $4)", 1, true) ~= nil or out:find("Luchador — (sell $4)", 1, true) ~= nil or (out:find("Luchador", 1, true) ~= nil and out:find("(sell $4)", 1, true) ~= nil and out:find("bought $8", 1, true) == nil), out)
  check("a joker purchased for $0 shows its purchase and sell prices",
    out:find("(bought $0, sell $1)", 1, true) ~= nil, out)
end

do
  local ContextCompact = require("context.context_compact")

  local no_id = { sort_id = nil, cost = 7, sell_cost = 2,
    ability = { name = "No Sort Id", set = "Joker", mult = 4 },
    config = { center = { key = "j_joker", name = "No Sort Id", set = "Joker",
      loc_txt = { name = "No Sort Id", description = "+4 Mult" } } } }
  local real_buy = { sort_id = 601, cost = 5, sell_cost = 3,
    ability = { name = "Luchador", set = "Joker" },
    config = { center = { key = "j_luchador", name = "Luchador", set = "Joker",
      loc_txt = { name = "Luchador", description = "" } } } }

  _G.G = {
    STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 100 }, FUNCS = {},
    GAME = { dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, round = 1,
      current_round = {}, round_resets = { ante = 1 }, hands = {}, probabilities = { normal = 1 } },
    NEURO = { enabled = true, run_generation = 1, jokers_sold_run = 0,
      once_serials = {}, session_once_serials = {},
      joker_bought_cost = { [601] = 5 } },
    jokers = { cards = { no_id, real_buy }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
  }
  ContextCompact.invalidate_cache()
  local ctx = ContextCompact.build("SHOP", { "sell_card" },
    { split = "volatile", no_cache = true, force_phase = true }) or ""

  check("a card without sort_id does not receive a fabricated '(bought $0)' annotation",
    ctx:find("bought $0", 1, true) == nil, ctx)
  check("a card without sort_id still shows its sell value",
    ctx:find("No Sort Id -- +4 Mult (sell $2)", 1, true) ~= nil, ctx)
  check("a genuinely purchased joker still shows its purchase price",
    ctx:find("(bought $5, sell $3)", 1, true) ~= nil, ctx)
end

do
  local OFFERS = { "play_hand", "discard_hand", "buy_from_shop", "sell_card",
    "set_joker_order", "record_joker_roles", "help", "cash_out" }
  local ROW = "1. Joker -- +4 Mult"
  local ContextCompact = require("context.context_compact")

  local function ctx_for(state, actions, jokers)
    _G.G = {
      STATE = STATES[state], STATES = STATES, STATE_COMPLETE = true,
      TIMERS = { REAL = 100 }, FUNCS = {},
      GAME = { dollars = 8, chips = 0, bankrupt_at = 0, used_vouchers = {}, modifiers = {},
        round = 1, current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
        round_resets = { ante = 2, blind_choices = {} }, hands = {}, probabilities = { normal = 1 } },
      NEURO = { enabled = true, run_generation = 1, once_serials = {}, session_once_serials = {} },
      jokers = { cards = jokers, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      deck = { cards = {} },
    }
    ContextCompact.invalidate_cache()
    return ContextCompact.build(state, actions, { no_cache = true }) or ""
  end

  for _, state in ipairs({ "SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL" }) do
    for _, name in ipairs(OFFERS) do
      local ctx = ctx_for(state, { name }, { joker() })
      check(string.format("%s carries the joker roster when the offered action is %s", state, name),
        ctx:find(ROW, 1, true) ~= nil, ctx)
    end
    local bare = ctx_for(state, { "sell_card" }, {})
    check(state .. " states no roster when the run owns no jokers",
      bare:find(ROW, 1, true) == nil, bare)
  end
end

do
  local Actions = require("core.actions")
  local Dispatcher = require("core.dispatcher")
  local TD = require("tests.test_deadlock")
  _G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }
  G.NEURO.dispatcher = Dispatcher
  G.NEURO.actions = Actions
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SELECTING_HAND" and sc.desc:find("Has usable consumable", 1, true) then
      TD.apply_mock(sc.mock()); break
    end
  end
  G.NEURO.persona = "neuro"
  G.hand = { cards = {}, highlighted = {} }
  G.jokers = { cards = { joker() }, config = { card_limit = 5 } }

  check("the undealt hand is refused by the router predicate for both hand actions",
    Actions.is_action_valid("play_hand") == false
      and Actions.is_action_valid("discard_hand") == false)
  check("the action set itself is not empty -- sell_card stays valid",
    Actions.is_action_valid("sell_card") == true)
  local force = Dispatcher.get_force_for_state("SELECTING_HAND")
  local offered = {}
  for _, name in ipairs(force and force.actions or {}) do offered[name] = true end
  check("the still-legal action survives the undealt hand",
    offered.sell_card == true, force and table.concat(force.actions, ",") or "NO FORCE")
  check("neither withdrawn hand action is offered",
    not offered.play_hand and not offered.discard_hand)
end

done()
