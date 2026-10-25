require("tests.stubs").setup({ love = "lazy" })

local H = require("tests.helpers")
local check, done = H.harness("mark near without outs")

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

-- Face-down ranks cannot supply public outs: a pair alone is not one card away from Two Pair.
board({ 1, 2, 5 }, nil, { { "5", "Spades" }, { "8", "Hearts" }, { "7", "Clubs" }, { "5", "Hearts" },
  { "6", "Diamonds" }, { "3", "Spades" } })
local s = hand_prose()
local near = s:match("One card away: ([^\n]*)") or ""
check("fixture: the board has a one-card-away entry with outs", near:find("draw-pile cards complete it", 1, true) ~= nil, s)
local bare = {}
for entry in (near:gsub("; (%u)", "\0%1") .. "\0"):gmatch("([^%z]*)%z") do
  if entry:find("keep cards", 1, true) and not entry:find("draw-pile cards complete it", 1, true) then bare[#bare + 1] = entry end
end
check("no one-card-away entry is listed without its outs and odds", #bare == 0, table.concat(bare, " | "))

_G.SMODS = nil
done()
