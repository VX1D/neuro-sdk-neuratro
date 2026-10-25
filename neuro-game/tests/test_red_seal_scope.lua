require("tests.stubs").setup({ love = "lazy", localize = true })

local check, done = require("tests.helpers").harness("red-seal-scope")
local Scoring = require("util.scoring")

local function photograph()
  return { sort_id = 1, ability = { set = "Joker", name = "Photograph", extra = 2 }, sell_cost = 3,
    config = { center = { key = "j_photograph", set = "Joker", name = "Photograph",
      loc_txt = { name = "Photograph", description = { "" } } } } }
end

local EngineCards = require("tests.engine_cards")
local function pcard(id, suit, opts)
  opts = opts or {}
  for value, rank in pairs(EngineCards.RANKS) do
    if rank.id == id then
      return EngineCards.playing(value, suit, { facing = opts.down and "back" or "front", seal = opts.seal })
    end
  end
end

local function board(hand, discard)
  local deck = { cards = {} }
  local all = {}
  for i = 2, 9 do deck.cards[#deck.cards + 1] = pcard(i, "Clubs") end
  _G.G = {
    GAME = { round = 1, current_round = {} },
    jokers = { cards = { photograph() } },
    hand = { cards = hand, config = { card_limit = 8 } },
    deck = deck, discard = { cards = discard or {} },
    FUNCS = {},
  }
  for _, c in ipairs(deck.cards) do c.area = G.deck; c.facing = "back"; all[#all + 1] = c end
  for _, c in ipairs(hand) do c.area = G.hand; all[#all + 1] = c end
  for _, c in ipairs(discard or {}) do c.area = G.discard; all[#all + 1] = c end
  G.playing_cards = all
end

local function photo_ceiling()
  local s = Scoring.joker_summary()
  local q = s and s.ledger and s.ledger.gated and s.ledger.gated.xmult
  return q and q.n
end

local function down_hand(red_at)
  local h = {}
  for i = 1, 8 do h[i] = pcard(9 + (i % 5), "Hearts", { down = true, seal = (i == red_at) and "Red" or nil }) end
  return h
end

board(down_hand(nil))
check("face-down hand with no Red Seal in the deck: Photograph stays x2", photo_ceiling() == 2,
  tostring(photo_ceiling()))

board(down_hand(3))
check("a Red Seal that may sit on a face-down held card still counts", photo_ceiling() == 4,
  tostring(photo_ceiling()))

local unseen = pcard(12, "Spades", { down = true, seal = "Red" })
unseen.ability.wheel_flipped = true
local visible = {}
for i = 1, 8 do visible[i] = pcard(2 + i, "Diamonds") end
board(visible, { unseen })
check("a Red Seal on a card discarded unseen still bounds the hand, or the bound would say where it went",
  photo_ceiling() == 4, tostring(photo_ceiling()))

done()
