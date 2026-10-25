require("tests.stubs").setup({ love = "lazy" })

-- The House preserves `wheel_flipped` on unseen discards, so the deck view still counts them as unplayed.
local H = require("tests.helpers")
local EngineCards = require("tests.engine_cards")
local check, done = H.harness("unseen discard")

local CardUtil = require("facts.card_util")
local CtxHand = require("context.ctx_hand")
local HandFacts = require("facts.hand_facts")
local function hand_prose() return require("context.context_readable").structure_prose(HandFacts.structure()) end

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local function card(v, suit) return EngineCards.playing(H.VALN[v] or v, suit) end

local function board(hand, unseen, boss)
  local by = {}
  for _, s in ipairs(SUITS) do for _, v in ipairs(RANKS) do by[v .. s] = card(v, s) end end
  _G.G = {
    GAME = { current_round = { hands_played = 0, discards_used = 1, discards_left = 3, hands_left = 4 },
      hands = {}, blind = boss },
    FUNCS = { get_poker_hand_info = function() return "High Card", nil, {}, {} end },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 9, highlighted_limit = 5 } },
    deck = { cards = {} }, discard = { cards = {} }, playing_cards = {},
  }
  local used = {}
  for _, h in ipairs(hand) do
    local c = by[h[1]]
    used[c] = true
    c.area = G.hand
    if h[2] then c.facing = "back"; c.ability.wheel_flipped = true end
    G.hand.cards[#G.hand.cards + 1] = c
  end
  for _, k in ipairs(unseen) do
    local c = by[k]
    used[c] = true
    c.area, c.facing, c.ability.wheel_flipped = G.discard, "back", true
    G.discard.cards[#G.discard.cards + 1] = c
  end
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = by[v .. s]
      if not used[c] then c.area, c.facing = G.deck, "back"; G.deck.cards[#G.deck.cards + 1] = c end
      G.playing_cards[#G.playing_cards + 1] = c
    end
  end
  return by
end

local function outputs()
  return table.concat({ tostring(CtxHand.deck_cards_section()), tostring(CtxHand.draw_composition_section()),
    tostring(hand_prose()) }, "\n")
end

local HOUSE = { key = "bl_house", name = "The House", disabled = false, in_blind = true }

local VISIBLE = { { "8Clubs" }, { "2Hearts", true }, { "3Hearts", true }, { "4Hearts", true },
  { "5Hearts" }, { "4Clubs" }, { "3Diamonds" }, { "2Spades" }, { "9Hearts", true } }
local UNSEEN_A = { "ASpades", "KSpades", "JSpades", "9Spades", "8Spades" }
local UNSEEN_B = { "QDiamonds", "10Diamonds", "7Diamonds", "6Diamonds", "5Diamonds" }

board(VISIBLE, UNSEEN_A, HOUSE)
local a = outputs()
board(VISIBLE, UNSEEN_B, HOUSE)
local b = outputs()
check("O414->O426: which cards were discarded unseen changes no byte of the hand context", a == b,
  "[" .. a .. "]\nvs\n[" .. b .. "]")
check("the pool is the deck view's unplayed pool: pile, held face-down and discarded unseen",
  a:find("Unplayed pool = the 38 cards in the draw pile plus 4 face-down cards in your hand and 5 face-down"
    .. " cards you discarded unseen, which the game's deck view also counts as unplayed.", 1, true) ~= nil, a)
check("every rank the deck view shows is in the pool tally (13 x4 minus the 5 visible)",
  a:find("Ranks in that pool: A x4, K x4, Q x4, J x4, 10 x4, 9 x4, 8 x3, 7 x4, 6 x4, 5 x3, 4 x3, 3 x3, 2 x3.",
    1, true) ~= nil, a)
check("a pile whose makeup is unknown gets only a range over the public pool, never an exact count",
  a:find("(0 to 8 of the 38 draw-pile cards complete it", 1, true) ~= nil and a:find("low end assumes those cards hold every out", 1, true) ~= nil, a)

do
  local by = board(VISIBLE, UNSEEN_A, HOUSE)
  local n = 0
  for _, c in ipairs(G.playing_cards) do
    if c.area == G.deck or c.ability.wheel_flipped then n = n + 1 end
  end
  local pool = CardUtil.unplayed_pool()
  check("the pool size equals the game's own unplayed predicate", #pool == n, #pool .. " vs " .. n)
  check("a card discarded unseen is not aggregate-public", CardUtil.is_aggregate_public(by.ASpades) == false)
  local seen = by["7Hearts"]
  for i, c in ipairs(G.deck.cards) do if c == seen then table.remove(G.deck.cards, i) end end
  seen.area = G.discard
  G.discard.cards[#G.discard.cards + 1] = seen
  check("a card discarded face up stays aggregate-public", CardUtil.is_aggregate_public(seen) == true)
end

local ALL_UP = { { "8Clubs" }, { "7Hearts" }, { "6Clubs" }, { "5Hearts" }, { "4Clubs" },
  { "QHearts" }, { "3Diamonds" }, { "2Spades" }, { "KHearts" } }
board(ALL_UP, UNSEEN_A, HOUSE)
local c1 = outputs()
board(ALL_UP, UNSEEN_B, HOUSE)
local c2 = outputs()
check("unseen discards alone: the hand context is identical across their identities", c1 == c2,
  "[" .. c1 .. "]\nvs\n[" .. c2 .. "]")
check("unseen discards alone: the odds are a range, and why is explained",
  c1:find("5 card(s) you discarded unseen still count as unplayed", 1, true) ~= nil
    and c1:find("(4 to 9 of the 38 draw-pile cards complete it", 1, true) ~= nil, c1)
board(ALL_UP, {}, HOUSE)
local clean = outputs()
check("control: with nothing unseen the odds come back", clean:find("draw-pile cards complete it", 1, true) ~= nil, clean)

board(VISIBLE, UNSEEN_A, HOUSE)
local s = hand_prose()
check("The House: no claim that fresh draws may come face down, and no anti-discard advice",
  s:find("face-down too", 1, true) == nil and s:find("fresh draws may also", 1, true) == nil
    and s:find("prefer playing", 1, true) == nil, s)
check("The House: later draws are stated face up",
  s:find("Replacements after a play or a discard are drawn face up.", 1, true) ~= nil, s)
check("O426: the Straight keep lists the face-down cards among the others to discard",
  s:find("Straight keep cards 5, 6, 7, 8, the others are 1, 2, 3, 4, 9", 1, true) ~= nil, s)

do
  local Render = require("facts.boss.render")
  for _, key in ipairs({ "bl_house", "bl_wheel", "bl_fish", "bl_mark" }) do
    board(VISIBLE, UNSEEN_A, { key = key, disabled = false, in_blind = true })
    local line = tostring(Render.boss_line("status", key, G.GAME.blind) or "")
    check(key .. ": boss text does not say discarding reveals a card",
      line ~= "" and line:find("played or discarded", 1, true) == nil, line)
  end
end

done()
