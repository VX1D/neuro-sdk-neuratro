require("tests.stubs").setup({ love = "lazy" })

local H = require("tests.helpers")
local check, done = H.harness("mark draw range")

local HandFacts = require("facts.hand_facts")
local function hand_prose() return require("context.context_readable").structure_prose(HandFacts.structure()) end

local function card(v, suit)
  return require("tests.engine_cards").playing(H.VALN[v] or v, suit)
end

local POOL = {
  { "K", "Spades" }, { "K", "Hearts" }, { "Q", "Clubs" }, { "Q", "Spades" }, { "J", "Hearts" }, { "J", "Clubs" },
  { "A", "Spades" }, { "A", "Hearts" }, { "10", "Spades" }, { "10", "Hearts" }, { "9", "Hearts" },
  { "6", "Clubs" }, { "6", "Spades" }, { "4", "Spades" }, { "4", "Hearts" }, { "4", "Clubs" }, { "3", "Clubs" },
  { "3", "Hearts" }, { "2", "Clubs" }, { "2", "Hearts" }, { "A", "Clubs" }, { "10", "Clubs" }, { "9", "Spades" },
  { "K", "Clubs" },
}
local VISIBLE = { { "9", "Clubs" }, { "8", "Hearts" }, { "7", "Clubs" }, { "5", "Diamonds" }, { "2", "Diamonds" },
  { "3", "Spades" } }

local function board(hidden, flipped_modifier, visible)
  local pool = {}
  for i, p in ipairs(POOL) do pool[i] = card(p[1], p[2]) end
  local vis = {}
  for i, p in ipairs(visible or VISIBLE) do vis[i] = card(p[1], p[2]) end
  require("tests.engine_cards").install_smods({})
  _G.G = {
    GAME = {
      blind = { key = "bl_mark", name = "The Mark", boss = true, disabled = false, in_blind = true,
        debuff = {}, hands = {}, only_hand = false, chips = 14586 },
      round = 1, chips = 7172, dollars = 10, hands = {}, probabilities = { normal = 1 },
      starting_params = {}, modifiers = { flipped_cards = flipped_modifier },
      current_round = { hands_left = 2, discards_left = 1, discards_used = 2, hands_played = 1 },
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
    c.facing = "back"
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

board({ 1, 2, 5 })
local s = hand_prose()
check("The Mark: the Straight's outs are exact, since a concealed card is a face card and never an out",
  s:find("Straight keep cards 2, 3, 4, 5", 1, true) ~= nil and s:find("(2 of the 21 draw-pile cards complete it", 1, true) ~= nil, s)
check("The Mark: no range whose low end assumes the concealed cards hold outs",
  s:find("(0 to ", 1, true) == nil and s:find("(1 to ", 1, true) == nil
    and s:find("range whose low end", 1, true) == nil and s:find("no hidden card hides a counted out", 1, true) ~= nil, s)
check("The Mark: a Straight on 5-9 needs a 6, which no face card is, so no face-down floor is claimed",
  s:find("face cards, dealt face down", 1, true) == nil and s:find("odds are exact", 1, true) == nil, s)

board({ 3, 24, 6 })
local s2 = hand_prose()
check("which face cards are concealed changes no byte of the hand prose", s2 == s, "[" .. s .. "]\nvs\n[" .. s2 .. "]")

board({ 1, 2, 5 }, 10)
local ranged = hand_prose()
check("flipped_cards on top of The Mark: a non-face card can be concealed, so the odds stay a range",
  ranged:find("(0 to 2 of the 21 draw-pile cards complete it", 1, true) ~= nil and ranged:find("range whose low end", 1, true) ~= nil, ranged)

board({ 1, 2, 5 }, nil, { { "9", "Clubs" }, { "8", "Clubs" }, { "7", "Clubs" }, { "5", "Clubs" },
  { "2", "Diamonds" }, { "3", "Spades" } })
local flush = hand_prose()
check("The Mark: a Flush draw flags the Club faces that would complete it face down",
  flush:find("Flush: 4 Clubs keep cards ", 1, true) ~= nil
    and flush:find("(6 of the 21 draw-pile cards complete it", 1, true) ~= nil, flush)
local prose = require("context.context_readable").structure_prose(HandFacts.structure())
check("and the readable board says the real chance is higher, not that the odds are exact",
  prose:find("up to 3 face cards, dealt face down, would complete it too, so the real chance is higher", 1, true) ~= nil
    and prose:find("odds are exact", 1, true) == nil, prose)
board({ 3, 24, 6 }, nil, { { "9", "Clubs" }, { "8", "Clubs" }, { "7", "Clubs" }, { "5", "Clubs" },
  { "2", "Diamonds" }, { "3", "Spades" } })
check("which Club face is concealed changes no byte of that either", hand_prose() == flush)

_G.SMODS = nil
done()
