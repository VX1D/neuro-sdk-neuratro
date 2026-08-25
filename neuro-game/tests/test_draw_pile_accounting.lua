_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local check, done = H.harness("draw-pile accounting")

local function card(v, suit, flipped)
  local id = H.RID[v]
  return {
    base = { value = H.VALN[v] or v, suit = suit, id = id },
    ability = { set = "Default", name = "Base", effect = "", wheel_flipped = flipped or nil },
    config = { center = { key = "c_base", set = "Default" } },
    facing = "front",
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local function setup(hand, pile)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 2 },
    hand = { cards = hand, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = pile }, jokers = nil, FUNCS = {}, playing_cards = {},
    GAME = { hands = {}, current_round = { discards_left = 2, hands_left = 3 }, blind = {} },
  }
end

local CtxHand = require("context.ctx_hand")

do
  setup({ card("K", "Hearts"), card("9", "Spades") }, { card("2", "Clubs") })
  check("a non-empty pile still states its size",
    (CtxHand.deck_cards_section() or ""):find("1 card", 1, true) ~= nil,
    CtxHand.deck_cards_section())

  setup({ card("K", "Hearts"), card("9", "Spades") }, {})
  local line = CtxHand.deck_cards_section()
  check("an empty pile states its size instead of saying nothing",
    line ~= nil and line:find("0 cards left in the draw pile", 1, true) ~= nil, tostring(line))
  check("an empty pile says what a discard will do, since 'Can discard: yes' still stands",
    line ~= nil and line:find("nothing", 1, true) ~= nil, tostring(line))

  _G.G.deck = nil
  check("no deck object: no size claim is made", CtxHand.deck_cards_section() == nil,
    tostring(CtxHand.deck_cards_section()))
end

do
  local flipped = card("A", "Hearts", true)
  local pile = { card("2", "Clubs"), card("3", "Clubs"), card("4", "Spades") }
  setup({ card("K", "Hearts"), flipped }, pile)
  local comp = CtxHand.draw_composition_section()
  local suits = 0
  for n in comp:gmatch("(%d+) %a+[,%.]") do suits = suits + tonumber(n) end
  check("the by-suit tally really is over the pool, not the pile (3 + 1 flipped)",
    suits == 4, comp)
  check("the caption states the total the tallies are over",
    comp:find("4 cards tallied", 1, true) ~= nil, comp)
  check("the caption still names why that total exceeds the pile",
    comp:find("face-down hand card", 1, true) ~= nil, comp)
  check("the size line keeps reporting the pile itself",
    CtxHand.deck_cards_section():find("3 cards left", 1, true) ~= nil,
    CtxHand.deck_cards_section())

  setup({ card("K", "Hearts") }, pile)
  local clean = CtxHand.draw_composition_section()
  check("with nothing flipped, no reconciliation note is added",
    clean:find("tallied", 1, true) == nil and clean:find("face-down", 1, true) == nil, clean)
end

done()
