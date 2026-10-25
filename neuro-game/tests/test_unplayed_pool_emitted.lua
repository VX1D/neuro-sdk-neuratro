require("tests.stubs").setup({ love = "lazy", G = "board" })

-- The public unplayed pool includes face-down held cards, so its suit totals must include them.
local H = require("tests.helpers")
local EngineCards = require("tests.engine_cards")
local check, done = H.harness("unplayed pool: emitted text")

local A = require("core.actions")
local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")
local CR = require("context.context_readable")

local sid = 0
local function card(v, suit, area, face_down)
  sid = sid + 1
  local c = EngineCards.playing(H.VALN[v] or v, suit, { sort_id = sid, facing = face_down and "back" or "front" })
  c.area, c.ability.wheel_flipped = area, face_down or nil
  return c
end

local function board(hidden)
  TD.apply_mock(TD.SCENARIOS[1].mock())
  H.in_engine_state("SELECTING_HAND")
  G.NEURO.persona = "neuro"
  G.deck = { cards = {} }
  for _, v in ipairs({ "2", "3", "4", "5", "6" }) do
    G.deck.cards[#G.deck.cards + 1] = card(v, "Spades", G.deck, true)
  end
  G.hand.cards = { card("A", "Hearts", G.hand, hidden), card("K", "Hearts", G.hand, hidden),
    card("3", "Clubs", G.hand, false) }
  G.playing_cards = {}
  for _, c in ipairs(G.deck.cards) do G.playing_cards[#G.playing_cards + 1] = c end
  for _, c in ipairs(G.hand.cards) do G.playing_cards[#G.playing_cards + 1] = c end
  return CR.build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"))
end

do
  local s = board(true)
  check("the pile size is the draw pile alone", s:find("5 cards left in the draw pile.", 1, true) ~= nil, s)
  check("the pool says it holds the pile plus the face-down held cards",
    s:find("Unplayed pool = the 5 cards in the draw pile plus 2 face-down cards in your hand, which the"
      .. " game's deck view also counts as unplayed. Unplayed pool by suit: 2 Hearts, 5 Spades.", 1, true) ~= nil, s)
  check("the held face-down cards are not named in the hand line",
    s:find("Ace of Hearts", 1, true) == nil and s:find("King of Hearts", 1, true) == nil, s)
end

do
  local s = board(false)
  check("with no face-down held card the pool is the pile and says nothing more",
    s:find("Unplayed pool =", 1, true) == nil and s:find("Unplayed pool by suit: 5 Spades.", 1, true) ~= nil, s)
end

done()
