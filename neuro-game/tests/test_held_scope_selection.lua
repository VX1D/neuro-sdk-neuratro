_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("held-scope-selection")

local function pc(id, suit)
  local c = { base = { id = id, suit = suit, nominal = id }, ability = {}, playing_card = true }
  function c:get_id() return id end
  function c:is_suit(s) return s == suit end
  function c:is_face() return id >= 11 and id <= 13 end
  return c
end

local function joker(key, name)
  return { sort_id = key, ability = { set = "Joker", name = name, extra = 1.5 }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { "" } } } } }
end

local HAND = { pc(13, "Spades"), pc(13, "Hearts"), pc(13, "Clubs"), pc(5, "Spades"),
               pc(6, "Spades"), pc(7, "Spades"), pc(8, "Diamonds"), pc(9, "Clubs") }

local function world(jokers)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1 },
    GAME = { round = 1, dollars = 5, round_resets = { ante = 1 }, probabilities = { normal = 1 },
      hands = {}, current_round = { discards_left = 2, hands_left = 3 } },
    NEURO = { once_serials = {}, jokers_sold_run = 0, joker_intents = {}, joker_bought_cost = {} },
    hand = { cards = HAND, config = { card_limit = 8 }, highlighted = {} },
    deck = { cards = {} }, playing_cards = HAND,
    jokers = { cards = jokers, config = { card_limit = 5 } },
    FUNCS = { get_poker_hand_info = function(sel)
      return "Three of a Kind", nil, {}, { sel[1], sel[2], sel[3] } end },
  }
end

package.loaded["util.scoring"] = nil
local Scoring = require("util.scoring")

-- Baron (card.lua:3666, context.other_card:get_id() == 13 under context.cardarea == G.hand) pays
-- x1.5 per King still held. Three Kings held and NONE played: x1.5^3 = 3.375.
do
  world({ joker("j_baron", "Baron") })
  local s = Scoring.joker_summary()
  local q = s.ledger.gated.xmult
  check("no selection: Baron over three held Kings is at most x3.375, not a certainty",
    q.k == "at_most" and math.abs(q.n - 3.375) < 1e-9, q.k .. " " .. tostring(q.n))
end

do
  world({ joker("j_baron", "Baron") })
  local selection = { HAND[1], HAND[2], HAND[3] }
  local s = Scoring.joker_summary(selection)
  local q = s.ledger.gated.xmult
  check("selection = the three Kings: Baron pays x1, not x3.375",
    q.n == nil or math.abs(q.n - 1) < 1e-9, q.k .. " " .. tostring(q.n))
  check("the inflated figure is not smuggled through ledger.sources either",
    (function()
      for _, src in ipairs(s.ledger.sources) do
        if src.kind == "xmult" and src.total.n and src.total.n > 1 then return false end
      end
      return true
    end)(), "sources still price the played Kings")
end

do
  world({ joker("j_baron", "Baron") })
  local s = Scoring.joker_summary({ HAND[1] })
  local q = s.ledger.gated.xmult
  check("selection = one King: Baron pays x2.25 over the two Kings still held",
    q.k == "known" and math.abs(q.n - 2.25) < 1e-9, q.k .. " " .. tostring(q.n))
end

-- Shoot the Moon (card.lua:3651) is the same scope over Queens; with no Queen in hand it must stay
-- at the identity whether or not a selection is open.
do
  world({ joker("j_shoot_the_moon", "Shoot the Moon") })
  local s = Scoring.joker_summary({ HAND[1], HAND[2], HAND[3] })
  local q = s.ledger.gated.mult
  check("Shoot the Moon with no Queen held stays at +0 Mult",
    q.n == nil or q.n == 0, q.k .. " " .. tostring(q.n))
end

-- The RATE twin of the same bug: Raised Fist (card.lua:3699-3712) walks G.hand itself to elect the
-- lowest held card, so it must walk the post-move hand too -- a card in G.play cannot be elected.
do
  local RF = { sort_id = "j_raised_fist", ability = { set = "Joker", name = "Raised Fist" }, sell_cost = 3,
    config = { center = { key = "j_raised_fist", set = "Joker", name = "Raised Fist",
      loc_txt = { name = "Raised Fist", description = { "" } } } } }
  local function fist_mult(selection)
    world({ RF })
    local s = Scoring.joker_summary(selection)
    return s and s.ledger.gated.mult and s.ledger.gated.mult.n or nil
  end
  check("no selection: the ceiling is the King the best play would leave, not the 5 held now",
    fist_mult(nil) == 26, tostring(fist_mult(nil)))
  check("selection = the 5: the elected card is the 6 still held, so +12 not +10",
    fist_mult({ HAND[4] }) == 12, tostring(fist_mult({ HAND[4] })))
  check("selection = 5,6,7: the elected card is the 8 still held, so +16",
    fist_mult({ HAND[4], HAND[5], HAND[6] }) == 16, tostring(fist_mult({ HAND[4], HAND[5], HAND[6] })))
  check("playing every non-King leaves a King as the lowest held card, so +26",
    fist_mult({ HAND[4], HAND[5], HAND[6], HAND[7], HAND[8] }) == 26,
    tostring(fist_mult({ HAND[4], HAND[5], HAND[6], HAND[7], HAND[8] })))
end

do
  local CtxHelpers = require("context.ctx_helpers")
  world({ joker("j_baron", "Baron") })
  local s = Scoring.joker_summary({ HAND[1], HAND[2], HAND[3] })
  local clause = CtxHelpers.quantity_clause("xmult", s.ledger.gated.xmult)
  check("the confirmation clause states no xMult for a hand that empties its Kings",
    clause == nil or clause:find("3.38", 1, true) == nil, tostring(clause))
end

done()
