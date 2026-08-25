rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }

local H = require("tests.helpers")
local check, done = H.harness("held-ceiling-deck-bound")

local sid = 0
local function card(v, suit, face_down)
  sid = sid + 1
  local id = H.RID[v]
  local c = {
    base = { value = H.VALN[v] or v, suit = suit, id = id, nominal = (id <= 10 and id or 10) },
    sort_id = sid, cost = 1, sell_cost = 1,
    ability = { set = "Default", name = "Base", effect = "" },
    config = { center = { key = "c_base", set = "Default" } },
    facing = face_down and "back" or "front",
  }
  c.is_suit = function(_, s) return s == suit end
  c.get_id = function(self) return self.base.id end
  return c
end

local function baron()
  sid = sid + 1
  return { sort_id = sid, cost = 5, sell_cost = 2, facing = "front",
    ability = { name = "Baron", set = "Joker", extra = 1.5 },
    config = { center = { key = "j_baron", set = "Joker", name = "Baron", rarity = 1,
      loc_txt = { name = "Baron", description = { "Each King held in hand gives X1.5 Mult" } } } },
    is_rarity = function(_, r) return r == "Common" end }
end

local function base_G()
  local g = {
    NEURO = { run_generation = 1 }, STATE = 1,
    STATES = { SELECTING_HAND = 1, SHOP = 2, BLIND_SELECT = 3, ROUND_EVAL = 7, MENU = 20 },
    P_BLINDS = { bl_small = { name = "Small Blind", dollars = 3, mult = 1 },
                 bl_big = { name = "Big Blind", dollars = 4, mult = 1.5 },
                 bl_hook = { name = "The Hook", dollars = 5, mult = 2, boss = true, debuff = {} } },
    P_TAGS = {}, TIMERS = { REAL = 100, TOTAL = 100 },
    SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, playing_cards = {}, FUNCS = {},
    GAME = {
      dollars = 20, bankrupt_at = 0, chips = 0, round = 4, skips = 0, win_ante = 8,
      used_vouchers = {}, modifiers = {}, tags = {}, interest_amount = 1, interest_cap = 25,
      probabilities = { normal = 1 }, starting_params = {}, hands = {},
      blind = { name = "Big Blind", chips = 600, dollars = 4, in_blind = true, boss = false,
                debuff = {}, disabled = false, hands = {}, get_type = function() return "Big" end },
      current_round = { hands_left = 3, discards_left = 2, discards_used = 0,
        most_played_poker_hand = "High Card", reroll_cost = 5, free_rerolls = 0,
        dollars_to_be_earned = "" },
      round_resets = { ante = 3, blind_ante = 3, hands = 4, discards = 3,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Defeated", Big = "Current", Boss = "Upcoming" } },
      round_bonus = { discards = 0, next_hands = 0 },
    },
  }
  _G.G = g
  return g
end

local CtxJokers = require("context.ctx_jokers")
local CtxHand = require("context.ctx_hand")
local Scoring = require("util.scoring")

local DRAW = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A",
               "2", "3", "4", "5", "6", "7", "8" }

local function board(hidden)
  local g = base_G()
  local j = baron()
  j.area = g.jokers
  g.jokers.cards = { j }
  local draw = {}
  for _, v in ipairs(DRAW) do draw[#draw + 1] = card(v, "Spades") end
  g.deck = { cards = draw }
  g.hand.cards = { card("K", "Spades"), card("K", "Hearts"), card(hidden, "Clubs", true),
                   card("4", "Diamonds"), card("7", "Hearts") }
  g.playing_cards = {}
  for _, c in ipairs(draw) do g.playing_cards[#g.playing_cards + 1] = c end
  for _, c in ipairs(g.hand.cards) do g.playing_cards[#g.playing_cards + 1] = c end

  local section = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
  local led = (Scoring.joker_summary(nil) or {}).ledger
  local bound = {}
  for _, s in ipairs((led and led.sources) or {}) do
    bound[#bound + 1] = tostring(s.name) .. " " .. tostring(s.total and s.total.n) .. " -- " .. tostring(s.why)
  end
  return section, table.concat(bound, " ; "), tostring(CtxHand.draw_composition_section and
    CtxHand.draw_composition_section() or "")
end

local sec_k, bound_k, draw_k = board("K")
local sec_2, bound_2, draw_2 = board("2")

check("the joker ledger is byte-identical across the two boards",
  sec_k == sec_2, "[" .. sec_k .. "] vs [" .. sec_2 .. "]")
check("no held-card ceiling figure is printed on either board",
  sec_k:find("more from jokers", 1, true) == nil, sec_k)
check("the roster row survives -- ownership is not the hidden fact",
  sec_k:find("Baron", 1, true) ~= nil, sec_k)

check("the withheld deck-derived bound DOES differ with the hidden card's rank",
  bound_k ~= bound_2 and bound_k ~= "" and bound_2 ~= "",
  "[" .. bound_k .. "] vs [" .. bound_2 .. "]")
check("and it differs by naming the whole-deck match count, hidden card included",
  bound_k:find("4 such cards in your deck", 1, true) ~= nil
    and bound_2:find("3 such cards in your deck", 1, true) ~= nil,
  "[" .. bound_k .. "] vs [" .. bound_2 .. "]")

check("the published composition counts the face-down hand card into the unplayed pool",
  draw_k:find("face-down hand card", 1, true) ~= nil
    and draw_2:find("face-down hand card", 1, true) ~= nil,
  "[" .. draw_k .. "] vs [" .. draw_2 .. "]")

done()
