_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("cross_scope_ceiling")
local Scoring = require("util.scoring")

local function jk(key, name, extra)
  return { sort_id = key, ability = { set = "Joker", name = name, extra = extra }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { "" } } } } }
end

local RANKS = { [2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,
  [10]=true,[11]=true,[12]=true,[13]=true,[14]=true }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local function make_deck()
  local deck = {}
  for _, suit in ipairs(SUITS) do
    for id in pairs(RANKS) do
      local c = { base = { id = id } }
      function c:get_id() return id end
      function c:is_suit(s) return s == suit end
      deck[#deck + 1] = c
    end
  end
  return deck
end

_G.G = {
  GAME = { round = 1, current_round = { ancient_card = { suit = "Spades" } } },
  jokers = { cards = {
    jk("j_baron", "Baron", 1.5),
    jk("j_triboulet", "Triboulet", 2),
    jk("j_ancient", "Ancient Joker", 1.5),
  } },
  hand = { cards = {}, config = { card_limit = 8 } },
  playing_cards = make_deck(),
  FUNCS = { get_poker_hand_info = function() return "High Card", nil, {}, {} end },
}

local s = Scoring.joker_summary()
check("summary produced", s ~= nil and s.ledger ~= nil)

local gated_xmult = s.ledger.gated.xmult
check("aggregate is still an at_most Quantity", gated_xmult.k == "at_most", gated_xmult.k)

local naive = (1.5 ^ 4) * (2 ^ 5) * (1.5 ^ 5)
check("naive product matches the owner's quoted x1230 example",
  math.abs(naive - 1230.1875) < 0.01, naive)

check("tightened aggregate is materially below the naive cross-scope product",
  gated_xmult.n < naive - 1, gated_xmult.n)

check("tightened aggregate matches the exact jointly-achievable bound (364.5)",
  math.abs(gated_xmult.n - 364.5) < 0.01, gated_xmult.n)

_G.G.GAME.current_round.ancient_card = nil
local s2 = Scoring.joker_summary()
local gated2 = s2.ledger.gated.xmult
check("undecidable round suit still yields a positive, non-identity ceiling",
  gated2.k == "at_most" and gated2.n > 1, gated2.n)

_G.G.jokers.cards = { jk("j_baron", "Baron", 1.5) }
local s3 = Scoring.joker_summary()
check("a lone gated row is unaffected by the population budget",
  math.abs(s3.ledger.gated.xmult.n - (1.5 ^ 4)) < 0.0001, s3.ledger.gated.xmult.n)

local function pcard(id, nominal, suit)
  local c = { base = { id = id, nominal = nominal or math.min(id, 10), suit = suit or "Spades" } }
  function c:get_id() return self.base.id end
  function c:is_suit(sx) return sx == self.base.suit end
  function c:is_face() return self.base.id >= 11 and self.base.id <= 13 end
  return c
end

local function fist_board(hand, selection)
  _G.G = {
    GAME = { round = 1, current_round = {} },
    jokers = { cards = { jk("j_raised_fist", "Raised Fist") } },
    hand = { cards = hand, config = { card_limit = 8, highlighted_limit = 5 } },
    playing_cards = make_deck(),
    FUNCS = { get_poker_hand_info = function(sel) return "High Card", nil, {}, sel or {} end },
  }
  local sm = Scoring.joker_summary(selection)
  return sm and sm.ledger and sm.ledger.gated.mult
end

do
  local hand = { pcard(2), pcard(3), pcard(4), pcard(5), pcard(6), pcard(12, 10) }
  local q = fist_board(hand)
  check("RF1 the ceiling is the lowest card left AFTER the best play, not the lowest held now",
    q and q.k == "at_most" and q.n == 20, q and (q.k .. "/" .. tostring(q.n)))
  local staged = fist_board(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] })
  check("RF2 staging the play that reaches it produces the same number",
    staged and staged.n == 20, staged and tostring(staged.n))
  local kept = fist_board(hand, { hand[6] })
  check("RF3 a selection fixes the hand, so its ceiling is that hand's own lowest card",
    kept and kept.n == 4, kept and tostring(kept.n))
end

do
  local hand = { pcard(2), pcard(3), pcard(4), pcard(5), pcard(6), pcard(7), pcard(12, 10) }
  local q = fist_board(hand)
  check("RF4 the ceiling is bounded by how many cards one play may remove",
    q and q.n == 14, q and tostring(q.n))
end

do
  _G.G = {
    GAME = { round = 1, current_round = {} },
    jokers = { cards = { jk("j_bloodstone", "Bloodstone", { Xmult = 1.5 }) } },
    hand = { cards = {}, config = { card_limit = 8 } },
    playing_cards = make_deck(),
    FUNCS = { get_poker_hand_info = function() return "High Card", nil, {}, {} end },
  }
  local q = Scoring.joker_summary().ledger.gated.xmult
  check("RF5 a deck-derived ceiling still names the odds gate it is subject to",
    q and q.why[1] and q.why[1]:find("1 time in 2", 1, true) ~= nil, q and tostring(q.why[1]))
end

done()
