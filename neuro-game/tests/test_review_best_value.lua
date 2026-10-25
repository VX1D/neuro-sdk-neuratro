require("tests.stubs").setup({ love = "lazy", localize = true })

local check, done = require("tests.helpers").harness("review-best-value")
local dump = os.getenv("BALATRO_DUMP")
local Engine = require("tests.engine_scorer")
if not (dump and dump ~= "" and Engine.load(dump)) then
  require("tests.skip_ledger").bail("review-best-value", 4, "BALATRO_DUMP unset or game/smods source unreadable")
end
local engine_localize = _G.localize
SMODS.reset_card = SMODS.reset_card or function(card, args)
  local t = args.ref_table or card.ability.extra
  t[args.ref_value] = args.reset_value or 0
end

local V = require("tests.fixtures.vanilla_jokers")
local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")

local HAND = { { 13, "Hearts" }, { 10, "Clubs" }, { 9, "Clubs" }, { 7, "Hearts" }, { 5, "Spades" },
  { 3, "Hearts" }, { 2, "Diamonds" } }
local JOKERS = { { "j_mystic_summit" }, { "j_ride_the_bus", mult = 3 }, { "j_wrathful_joker" }, { "j_clever" },
  { "j_walkie_talkie" }, { "j_cavendish" } }
local LEVELS = { ["High Card"] = { 5, 1, 1 }, Pair = { 10, 2, 1 }, ["Two Pair"] = { 80, 5, 4 },
  ["Three of a Kind"] = { 70, 7, 3 }, Straight = { 30, 4, 1 }, Flush = { 35, 4, 1 }, ["Full House"] = { 40, 4, 1 },
  ["Four of a Kind"] = { 60, 7, 1 }, ["Straight Flush"] = { 100, 8, 1 }, ["Five of a Kind"] = { 120, 12, 1 },
  ["Flush House"] = { 140, 14, 1 }, ["Flush Five"] = { 160, 16, 1 } }

local function setup()
  local hands = {}
  for name, v in pairs(LEVELS) do
    hands[name] = { chips = v[1], mult = v[2], level = v[3], visible = true, played = 0, played_this_round = 0 }
  end
  _G.G = _G.G or {}
  G.GAME = {
    current_round = { hands_left = 2, discards_left = 0, discards_used = 3, hands_played = 1 },
    hands = hands, probabilities = { normal = 1 }, dollars = 24, dollar_buffer = 0, round_resets = { ante = 5 },
    hands_played = 20, starting_deck_size = 52, consumeable_usage_total = { tarot = 0 }, blind = {}, modifiers = {},
  }
  local cards = {}
  for i, s in ipairs(HAND) do cards[i] = Engine.card(s[1], s[2]) end
  G.hand = { cards = cards, highlighted = {}, config = { card_limit = 7, highlighted_limit = 5 } }
  for _, c in ipairs(cards) do c.area = G.hand end
  local jokers = {}
  for i, spec in ipairs(JOKERS) do
    local j = Engine.joker(V.card(spec[1], 900 + i))
    j.facing = "front"
    if spec.mult then j.ability.mult = spec.mult end
    jokers[i] = j
  end
  G.jokers = { cards = jokers, config = { card_limit = 6 } }
  G.deck = { cards = {}, config = { card_limit = 52 } }
  G.playing_cards, G.discard, G.play = {}, { cards = {} }, nil
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.NEURO = { once_serials = {}, session_once_serials = {} }
  G.FUNCS.get_poker_hand_info = Engine.get_poker_hand_info
  _G.localize = engine_localize
  require("core.gate").reset()
  return cards
end

local function engine_total(i)
  local cards = setup()
  local mult, _, _, chips = Engine.score({ cards[i] })
  return chips * mult
end

local king, ten, five = engine_total(1), engine_total(2), engine_total(5)
check("the engine: the 10 of Clubs (1800) outscores the King (720), which outscores the 5 of Spades (690)",
  ten == 1800 and king == 720 and five == 690, ten .. " / " .. king .. " / " .. five)

setup()
local _, err = HandHandlers.handle_play_hand({ indices = { 5 } })
local msg = require("tests.helpers").review_text(err)
check("the review names the High Card that scores most, the 10 of Clubs",
  msg:find("Ready High Card (cards 2) would score more than these cards", 1, true) ~= nil, msg)
check("the review does not point at the King, which scores less than the 10",
  msg:find("High Card (cards 1)", 1, true) == nil, msg)

setup()
local ten_play = HandHandlers.handle_play_hand({ indices = { 2 } })
check("playing the best High Card with no discard left commits without a review",
  type(ten_play) == "function", tostring(ten_play))

done()
