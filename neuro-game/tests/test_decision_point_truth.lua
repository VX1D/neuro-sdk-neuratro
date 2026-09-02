_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("decision-point-truth")
local H = require("tests.helpers")
local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local ForceShop = require("force.force_shop")
local ShopHandlers = require("handlers.shop_handlers")

local function joker(key, sid, cost)
  return { cost = cost or 4, sell_cost = 2, sort_id = sid,
    ability = { set = "Joker", name = key },
    config = { center = { key = key, name = key, set = "Joker", rarity = 1,
      loc_txt = { name = key, description = { "+4 Mult" } } } } }
end

local function booster(kind, sid)
  return { cost = 4, sell_cost = 2, sort_id = sid,
    ability = { set = "Booster", name = kind .. " Pack", extra = 1, choose = 1 },
    config = { center = { key = "p_" .. kind:lower() .. "_normal_1", name = kind .. " Pack",
      set = "Booster", kind = kind, config = { extra = 1, choose = 1 },
      loc_txt = { name = kind .. " Pack", description = { "Pick 1 of 1" } } } } }
end

local function shop_G(opts)
  opts = opts or {}
  local roster = {}
  for i = 1, 5 do roster[i] = joker("j_mock" .. i, 800 + i) end
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 }, P_BLINDS = {}, TIMERS = { REAL = 100 },
    FUNCS = { toggle_shop = function() end },
    GAME = { dollars = 31, interest_cap = 25, interest_amount = 1, modifiers = {}, round = 7,
      round_resets = { ante = 7, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 } },
    NEURO = { once_serials = {}, session_once_serials = {}, state_enter_serial = 1,
      decision_serial = 1, joker_intents = {}, reserved_dollars = 0, shop_reroll_count = 0,
      dispatcher = Dispatcher, actions = Actions },
    jokers = { cards = roster, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { joker("j_blueprint", 701, 12), joker("j_mime", 702, 6) } },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = { booster(opts.pack or "Standard", 703) } },
  }
  for _, c in ipairs(roster) do
    G.NEURO.joker_intents[c.sort_id] = { tag = "CORE" }
  end
  require("context.context_compact").invalidate_cache()
  require("facts.fact_hints").reset_pending()
end

local function shop_query()
  local res = ForceShop.build()
  return ((res or {}).query or "") .. H.drain_hints()
end

local real_valid = Actions.is_action_valid
local function with_valid(valid, fn)
  Actions.is_action_valid = function(n) return valid[n] == true end
  local ok, err = pcall(fn)
  Actions.is_action_valid = real_valid
  if not ok then error(err, 0) end
end

do
  shop_G()
  with_valid({ buy_from_shop = true, sell_card = true, leave_shop = true }, function()
    local q = shop_query()
    check("the slot-blocked shop rows are named where the decision is made",
      q:find("Your cash covers shop_jokers 1-2", 1, true) ~= nil, q)
    check("and the reason given is the slot, not the money",
      q:find("no free slot to put them in", 1, true) ~= nil, q)
    check("'Valid indices' no longer offers a shop row buy_from_shop refuses",
      q:find("shop_jokers 1", 1, true) == nil or q:find("Valid indices: shop_booster", 1, true) ~= nil,
      q:match("Valid indices:[^\n]*") or q)
    check("the row buy_from_shop does accept is still listed",
      (q:match("Valid indices:[^\n]*") or ""):find("shop_booster 1", 1, true) ~= nil,
      q:match("Valid indices:[^\n]*") or q)
    check("and the shop rows it refuses are not",
      (q:match("Valid indices:[^\n]*") or ""):find("shop_jokers", 1, true) == nil,
      q:match("Valid indices:[^\n]*") or q)
  end)
end

do
  shop_G()
  local _, err = ShopHandlers.handle_buy_from_shop({ area = "shop_jokers", index = 1 })
  check("the buy is refused with NO_SLOT",
    type(err) == "table" and err.reason_code == "NO_SLOT", tostring(err and err.reason_code))
  local msg = (type(err) == "table" and err.message) or ""
  check("and the refusal names the move that clears it, as the consumable branch does",
    msg:find("sell a joker to free one, then buy it", 1, true) ~= nil, msg)
  check("and states the slot count it is refusing on",
    msg:find("joker slots are 5/5 full", 1, true) ~= nil, msg)
end

do
  shop_G({ pack = "Standard" })
  G.consumeables.cards = {
    { sort_id = 900, sell_cost = 1, cost = 3,
      ability = { name = "The Fool", set = "Tarot", consumeable = { max_highlighted = 1,
        min_highlighted = 1 } },
      config = { center = { key = "c_fool", set = "Tarot", name = "The Fool",
        loc_txt = { name = "The Fool", text = { "Its rule" } } } } } }
  with_valid({ buy_from_shop = true, sell_card = true, leave_shop = true }, function()
    local q = shop_query()
    check("with no consumable for sale the consumable-slot rule is not restated",
      q:find("Buying a tarot/planet/spectral card TO KEEP", 1, true) == nil, q)
    check("the hand-target note explains why no action is needed here",
      q:find("will become usable once the next blind deals you a hand", 1, true) ~= nil, q)
  end)
end

do
  shop_G({ pack = "Arcana" })
  G.consumeables.cards = {
    { sort_id = 900, sell_cost = 1, cost = 3,
      ability = { name = "The Fool", set = "Tarot", consumeable = { max_highlighted = 0 } },
      config = { center = { key = "c_fool", set = "Tarot", name = "The Fool",
        loc_txt = { name = "The Fool", text = { "Its rule" } } } } },
    { sort_id = 901, sell_cost = 1, cost = 3,
      ability = { name = "Pluto", set = "Planet", consumeable = { max_highlighted = 0 } },
      config = { center = { key = "c_pluto", set = "Planet", name = "Pluto",
        loc_txt = { name = "Pluto", text = { "Its rule" } } } } } }
  with_valid({ buy_from_shop = true, sell_card = true, leave_shop = true }, function()
    local q = shop_query()
    check("with a consumable pack in stock the rule IS stated",
      q:find("Buying a tarot/planet/spectral card TO KEEP", 1, true) ~= nil, q)
  end)
end

do
  shop_G()
  G.consumeables.cards = {
    { sort_id = 900, sell_cost = 1, cost = 3,
      ability = { name = "Pluto", set = "Planet", consumeable = { max_highlighted = 0 } },
      config = { center = { key = "c_pluto", set = "Planet", name = "Pluto",
        loc_txt = { name = "Pluto", text = { "Its rule" } } } } } }
  with_valid({ buy_from_shop = true, sell_card = true, leave_shop = true }, function()
    local q = shop_query()
    local tail = q:match("Your move:(.*)") or ""
    local n = select(2, tail:gsub("sell_card|", ""))
    check("every visible sell target is an explicit identity-bearing candidate",
      n == 6, n .. " :: " .. tail)
    check("and it still renders as an offer the ORPHAN scan can read",
      tail:find("sell_card|{", 1, true) ~= nil, tail)
    check("the explicit candidates cover both sellable areas",
      tail:find('"area":"jokers"', 1, true) ~= nil
        and tail:find('"area":"consumeables"', 1, true) ~= nil, tail)
  end)
end

do
  shop_G()
  G.consumeables.cards = {}
  with_valid({ buy_from_shop = true, sell_card = true, leave_shop = true }, function()
    local tail = (shop_query():match("Your move:(.*)") or "")
    check("with nothing but jokers to sell the area is bound, not offered as a choice",
      tail:find('sell_card|{"area":"jokers"', 1, true) ~= nil, tail)
  end)
end

local CtxBlind = require("context.ctx_blind")
local CardUtil = require("facts.card_util")

do
  _G.get_blind_amount = function(ante) return 800 * ante end
  _G.G = {
    STATE = 3, STATES = { BLIND_SELECT = 3 }, TIMERS = { REAL = 100 }, FUNCS = {},
    GAME = { dollars = 10, interest_cap = 25, interest_amount = 1, modifiers = {},
      blind_on_deck = "Small", win_ante = 8,
      current_round = { hands_left = 4, discards_left = 3 },
      round_resets = { ante = 3, blind_ante = 3,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_tags = {} },
      starting_params = { ante_scaling = 1 } },
    NEURO = { once_serials = {} },
    P_BLINDS = {
      bl_small = { name = "Small Blind", mult = 1, dollars = 3 },
      bl_big = { name = "Big Blind", mult = 1.5, dollars = 4 },
      bl_hook = { name = "The Hook", mult = 2, dollars = 5, boss = { min = 1 },
        debuff = { text = "After each hand you play, 2 random cards are discarded." } },
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
  local section = CtxBlind.blind_select_section and CtxBlind.blind_select_section()
    or CtxBlind.build("BLIND_SELECT")
  local row = tostring(section):match("[^\n]*%(Select%)[^\n]*") or ""
  local target = require("facts.economy_facts").calc_blind_target("bl_small")
  local per = CardUtil.score_per_hand(target, 4)
  check("the blind being chosen states its per-hand figure",
    row:find("per hand", 1, true) ~= nil, row)
  check("and it is the same arithmetic SELECTING_HAND publishes",
    row:find("about " .. tostring(per) .. " per hand over 4 hands", 1, true) ~= nil,
    row .. " :: expected " .. tostring(per))
  check("a row that is not the one being chosen does not claim a hand allowance",
    (tostring(section):match("[^\n]*%(Upcoming%)[^\n]*") or ""):find("per hand", 1, true) == nil,
    tostring(section):match("[^\n]*%(Upcoming%)[^\n]*") or "")

  local boss_row = tostring(section):match("[^\n]*The Hook[^\n]*") or ""
  check("game prose in the state half keeps the punctuation the game wrote",
    boss_row:find("After each hand you play, 2 random cards", 1, true) ~= nil, boss_row)
  check("and no comma survives as a semicolon in it",
    boss_row:find("you play; 2 random", 1, true) == nil, boss_row)
end

do
  local Enforce = require("core.enforce")
  local function correction_for(code, message)
    Enforce.note_rejection("buy_from_shop", table.concat({ code, message }, "\0"))
    return Enforce.take_correction()
  end

  local no_slot = correction_for("NO_SLOT",
    "No slot space to buy Blueprint now: joker slots are 5/5 full -- sell a joker to free one, then buy it.")
  check("a NO_SLOT refusal carries a correction at all",
    type(no_slot) == "string" and no_slot ~= "", tostring(no_slot))
  check("it states that the money did not move, which no refusal message says",
    (no_slot or ""):find("no money moved", 1, true) ~= nil, tostring(no_slot))
  check("and it does not repeat the remedy the message already carries",
    select(2, (no_slot or ""):gsub("sell a joker", "")) == 1, tostring(no_slot))

  local broke = correction_for("INSUFFICIENT_FUNDS", "Can't afford Blueprint ($12): you only have $4.")
  check("an INSUFFICIENT_FUNDS refusal names what to do instead",
    (broke or ""):find("take a cheaper row", 1, true) ~= nil, tostring(broke))

  -- The guard paths (core/dispatcher.lua:409, :859, :900) answer with guard=true and record no
  -- failure, so anything staged for them would go stale and ride a later, unrelated refusal.
  Enforce.note_rejection("play_hand", "TRANSITION_PENDING")
  check("a fingerprint that is not a below-gate refusal stages nothing",
    Enforce.take_correction() == nil)

  check("a code-shaped reason is humanized, not gsub'd into 'NO SLOT'",
    (correction_for("NO_SLOT", "No slot space to buy X now.") or ""):find("NO SLOT", 1, true) == nil)
end

done()
