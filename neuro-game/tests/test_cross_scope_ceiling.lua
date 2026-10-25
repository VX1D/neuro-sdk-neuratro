require("tests.stubs").setup({ love = "lazy", localize = true })

local check, done = require("tests.helpers").harness("cross_scope_ceiling")
local Scoring = require("util.scoring")

local jk = require("tests.fake_cards").jk

local RANKS = { [2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,
  [10]=true,[11]=true,[12]=true,[13]=true,[14]=true }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local EngineCards = require("tests.engine_cards")
local VALUE = {}
for value, rank in pairs(EngineCards.RANKS) do VALUE[rank.id] = value end

local function make_deck()
  local deck = {}
  for _, suit in ipairs(SUITS) do
    for id in pairs(RANKS) do
      deck[#deck + 1] = EngineCards.playing(VALUE[id], suit)
    end
  end
  return deck
end

_G.G = {
  GAME = { round = 1, current_round = { ancient_card = { suit = "Spades" } }, probabilities = { normal = 1 } },
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

local function pcard(id, suit) return EngineCards.playing(VALUE[id], suit or "Spades") end

local function fist_board(hand, selection)
  _G.G = {
    GAME = { round = 1, current_round = {}, probabilities = { normal = 1 } },
    jokers = { cards = { jk("j_raised_fist", "Raised Fist") } },
    hand = { cards = hand, config = { card_limit = 8, highlighted_limit = 5 } },
    playing_cards = make_deck(),
    FUNCS = { get_poker_hand_info = function(sel) return "High Card", nil, {}, sel or {} end },
  }
  local sm = Scoring.joker_summary(selection)
  return sm and sm.ledger and sm.ledger.gated.mult
end

do
  local hand = { pcard(2), pcard(3), pcard(4), pcard(5), pcard(6), pcard(12) }
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
  local hand = { pcard(2), pcard(3), pcard(4), pcard(5), pcard(6), pcard(7), pcard(12) }
  local q = fist_board(hand)
  check("RF4 the ceiling is bounded by how many cards one play may remove",
    q and q.n == 14, q and tostring(q.n))
end

do
  _G.G = {
    GAME = { round = 1, current_round = {}, probabilities = { normal = 1 } },
    jokers = { cards = { jk("j_bloodstone", "Bloodstone", { Xmult = 1.5, odds = 2 }) } },
    hand = { cards = {}, config = { card_limit = 8 } },
    playing_cards = make_deck(),
    FUNCS = { get_poker_hand_info = function() return "High Card", nil, {}, {} end },
  }
  local q = Scoring.joker_summary().ledger.gated.xmult
  check("RF5 a deck-derived ceiling still names the odds gate it is subject to",
    q and q.why[1] and q.why[1]:find("1 time in 2", 1, true) ~= nil, q and tostring(q.why[1]))
end

do
  local function hidden_card()
    local c = { facing = "back", ability = {}, base = {} }
    local function probe() error("a face-down card was read") end
    c.get_id, c.is_suit, c.is_face = probe, probe, probe
    return c
  end
  local function tri_board(fifth)
    local hand = { pcard(13), pcard(13, "Hearts"), pcard(7), pcard(5), fifth, pcard(3) }
    _G.G = {
      GAME = { round = 1, current_round = {}, probabilities = { normal = 1 } },
      jokers = { cards = { jk("j_triboulet", "Triboulet", 2) } },
      hand = { cards = hand, config = { card_limit = 8, highlighted_limit = 5 } },
      playing_cards = make_deck(),
      FUNCS = { get_poker_hand_info = function(sel) return "Pair", nil, {}, { sel[1], sel[2] } end },
    }
    local sm = Scoring.joker_summary({ hand[1], hand[2], hand[3], hand[4], hand[5] })
    return sm and sm.ledger
  end
  local open = tri_board(pcard(4))
  check("HC1 an all-public selection pays exactly its two Kings",
    open and open.gated.xmult.k == "known" and open.gated.xmult.n == 4,
    open and (open.gated.xmult.k .. "/" .. tostring(open.gated.xmult.n)))
  local ok, led = pcall(tri_board, hidden_card())
  check("HC2 the face-down card is never read", ok, tostring(led))
  local q = ok and led and led.gated.xmult
  check("HC3 the ceiling counts it as a possible King that a Red Seal scores twice (x2^4)",
    q and q.k == "at_most" and q.n == 16, q and (q.k .. "/" .. tostring(q.n)))
  local row = ok and led and led.sources[1]
  check("HC4 Triboulet's own line carries the same bound",
    row and row.total.n == 16, row and tostring(row.total.n))
end

done()
