require("tests.stubs").setup({ love = "lazy" })

-- The blind flips each replacement with 1-in-7 probability, so replacements are usually face up.
local H = require("tests.helpers")
local check, done = H.harness("wheel discard")

local HandFacts = require("facts.hand_facts")
local function hand_prose() return require("context.context_readable").structure_prose(HandFacts.structure()) end
local Force = require("force.force_selecting_hand")

local function card(v, suit)
  return require("tests.engine_cards").playing(H.VALN[v] or v, suit)
end

local POOL = {
  { "A", "Spades" }, { "A", "Hearts" }, { "A", "Clubs" }, { "K", "Spades" }, { "K", "Hearts" }, { "K", "Clubs" },
  { "Q", "Spades" }, { "Q", "Clubs" }, { "J", "Hearts" }, { "J", "Clubs" }, { "10", "Spades" },
  { "10", "Hearts" }, { "10", "Clubs" }, { "9", "Hearts" }, { "7", "Spades" }, { "7", "Hearts" },
  { "6", "Clubs" }, { "6", "Spades" }, { "5", "Clubs" }, { "5", "Hearts" }, { "4", "Spades" },
  { "4", "Hearts" }, { "4", "Clubs" }, { "3", "Clubs" }, { "3", "Spades" }, { "2", "Clubs" },
}
local VISIBLE = { { "Q", "Diamonds" }, { "9", "Clubs" }, { "8", "Hearts" }, { "7", "Clubs" },
  { "5", "Diamonds" }, { "2", "Diamonds" } }

local function board(hidden, normal)
  local pool = {}
  for i, p in ipairs(POOL) do pool[i] = card(p[1], p[2]) end
  local vis = {}
  for i, p in ipairs(VISIBLE) do vis[i] = card(p[1], p[2]) end
  require("tests.engine_cards").install_smods({ four_fingers = function() return 4 end })
  _G.G = {
    GAME = {
      blind = { key = "bl_wheel", name = "The Wheel", boss = true, disabled = false, in_blind = true,
        debuff = {}, hands = {}, only_hand = false, chips = 14586 },
      round = 1, chips = 7172, dollars = 10, hands = {}, probabilities = { normal = normal or 1 },
      starting_params = {},
      current_round = { hands_left = 2, discards_left = 1, discards_used = 2, hands_played = 1,
        most_played_poker_hand = "Straight" },
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = {},
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, discard = { cards = {} }, play = nil,
    jokers = { cards = {} }, consumeables = { cards = {} }, playing_cards = {},
  }
  local held = { [hidden[1]] = 1, [hidden[2]] = 6 }
  local order = { false, vis[1], vis[2], vis[3], vis[4], false, vis[5], vis[6] }
  for idx, pos in pairs(held) do
    local c = pool[idx]
    c.facing, c.ability.wheel_flipped = "back", true
    order[pos] = c
  end
  for _, c in ipairs(order) do c.area = G.hand; G.hand.cards[#G.hand.cards + 1] = c end
  local un = pool[hidden[3]]
  un.area, un.facing, un.ability.wheel_flipped = G.discard, "back", true
  G.discard.cards[1] = un
  for i, c in ipairs(pool) do
    if not held[i] and i ~= hidden[3] then c.area, c.facing = G.deck, "back"; G.deck.cards[#G.deck.cards + 1] = c end
    G.playing_cards[#G.playing_cards + 1] = c
  end
  for _, c in ipairs(vis) do G.playing_cards[#G.playing_cards + 1] = c end
end

board({ 1, 4, 21 })
local s = hand_prose()
check("L1271: the face-down draw rule states the game's 1 in 7",
  s:find("each with a 1 in 7 chance of arriving face down", 1, true) ~= nil, s)
check("L1271: no false blind-gamble premise, no anti-discard nudge",
  s:find("is a blind gamble:", 1, true) == nil and s:find("prefer playing", 1, true) == nil, s)
check("L1271: the Straight draw keeps its odds, as a range over the concealed cards, face-down draws a miss",
  s:find("Straight keep cards 3, 4, 5", 1, true) ~= nil and s:find("(2 to 5 of the 23 draw-pile cards complete it", 1, true) ~= nil
    and s:find("count a face-down draw as a miss", 1, true) ~= nil, s)

board({ 11, 12, 17 })
local s2 = hand_prose()
check("which pool cards are concealed changes no byte of the hand prose", s2 == s, "[" .. s .. "]\nvs\n[" .. s2 .. "]")

board({ 1, 4, 21 })
local force = Force.build()
local q = type(force) == "table" and tostring(force.query) or ""
local st = require("tests.helpers").force_frame("SELECTING_HAND", force)
check("L1271 force: the query points a discard at the one-card-away odds",
  q:find("the one-card-away odds above show which stronger hands a discard can reach", 1, true) ~= nil, q)
check("L1271 force: the Wheel's 1 in 7 is stated", (q .. st):find("1 in 7", 1, true) ~= nil, q .. st)
check("L1271 force: the query says to decide from the visible cards, with no anti-discard nudge",
  q:find("Decide from the visible cards.", 1, true) ~= nil and q:find("prefer playing", 1, true) == nil, q)

board({ 1, 4, 21 }, 4)
local blind = hand_prose()
check("4 in 7 (most draws face down): the blind-gamble fact and withheld odds return",
  blind:find("each with a 4 in 7 chance", 1, true) ~= nil and blind:find("Discarding here is a blind gamble:", 1, true) ~= nil
    and blind:find("draw-pile cards complete it", 1, true) == nil, blind)
local f4 = Force.build()
check("4 in 7: the prefer-playing guidance rides the query, not the state",
  tostring(f4 and f4.query):find("Decide from the visible cards, and prefer playing your best hand from what you can see over burning discards.", 1, true) ~= nil
    and blind:find("prefer playing", 1, true) == nil, tostring(f4 and f4.query))
check("4 in 7: the query no longer points a discard at the odds",
  tostring(f4 and f4.query):find("the one-card-away odds above show which stronger hands a discard can reach", 1, true) == nil,
  tostring(f4 and f4.query))

_G.SMODS = nil
done()
