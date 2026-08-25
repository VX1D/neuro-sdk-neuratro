_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("rules-core-gate")
local H = require("tests.helpers")
local FactHints = require("facts.fact_hints")
local Actions = require("core.actions")
local FSH = require("force.force_selecting_hand")

local function blind(minimum, disabled)
  return { key = "bl_psychic", name = "The Psychic", boss = true, disabled = disabled == true,
    debuff = { h_size_ge = minimum }, hands = {}, only_hand = false }
end

local function fixture(b)
  local cards = {}
  for i, rank in ipairs({ "A", "K", "Q", "J", "9", "8", "7", "6" }) do
    local suit = ({ "Spades", "Hearts", "Clubs", "Diamonds" })[((i - 1) % 4) + 1]
    cards[i] = { base = { value = H.VALN[rank] or rank, suit = suit }, sort_id = i,
      config = { center = { key = "c_base", set = "Default" } },
      is_suit = function(_, s) return s == suit end }
  end
  return { hand = { cards = cards, config = { highlighted_limit = 5 }, highlighted = {} },
    GAME = { blind = b, hands = {}, probabilities = { normal = 1 }, starting_params = {},
      round = 1, dollars = 4, current_round = { hands_left = 3, discards_left = 2,
        discards_used = 0, most_played_poker_hand = "High Card" } },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = { once_serials = {}, decision_serial = 1, state_enter_serial = 1 },
    jokers = { cards = {} }, consumeables = { cards = {} }, playing_cards = cards,
    deck = { cards = {} }, play = nil }
end

local real_valid = Actions.is_action_valid
Actions.is_action_valid = function(name)
  if name == "play_hand" or name == "discard_hand" then return real_valid(name) end
  return false
end

local function build()
  FactHints.reset_pending()
  local f = assert(FSH.build())
  return f.query or "", H.drain_hints()
end

_G.G = fixture(blind(5))
local q1, retained1 = build()
check("rules are inline in the ephemeral force", q1:find("Rules: 1)", 1, true) ~= nil, q1)
check("current boss minimum is inline", q1:find("select at least 5 cards", 1, true) ~= nil, q1)
check("no current rule enters retained hint context", retained1 == "", retained1)

local q2 = build()
check("re-ask is self-contained", q2:find("Rules: 1)", 1, true) ~= nil)
check("re-ask repeats the exact current minimum", q2:find("select at least 5 cards", 1, true) ~= nil)

G.GAME.blind = blind(4)
local q4 = build()
check("a changed boss is reflected immediately", q4:find("select at least 4 cards", 1, true) ~= nil)
check("changed force carries no stale old minimum", q4:find("select at least 5 cards", 1, true) == nil)

G.GAME.current_round.discards_left = 0
G.GAME.current_round.discards_used = 2
local q0 = build()
check("exhausted discards remove discard advice from the rebuilt block",
  q0:find("a discard toward", 1, true) == nil, q0)
check("no retained correction is minted", not q0:find("Correction to the rules above", 1, true))

G.GAME.round = nil
local qnil = build()
check("missing cadence clock cannot suppress current rules", qnil:find("Rules: 1)", 1, true) ~= nil)

G.GAME.blind.disabled = true
G.GAME.current_round.discards_left = 3
local qdisabled = build()
check("disabling the boss removes its minimum immediately",
  qdisabled:find("select at least 4 cards", 1, true) == nil, qdisabled)
check("restored discards restore current discard advice",
  qdisabled:find("a discard toward", 1, true) ~= nil, qdisabled)

G.NEURO.plan = { hand = "chase flush", build = "no xMult yet" }
local qp = build()
check("model hand plan remains visible", qp:find("chase flush", 1, true) ~= nil, qp)
check("model build plan remains visible", qp:find("no xMult yet", 1, true) ~= nil, qp)
check("no scope stamp is added to current rule prose", qp:find("[ante", 1, true) == nil, qp)

Actions.is_action_valid = real_valid
done()
