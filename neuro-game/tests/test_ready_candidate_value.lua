_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("ready-candidate-value")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local TD = require("tests.test_deadlock")
local HF = require("facts.hand_facts")
local CardUtil = require("facts.card_util")
local Registry = require("core.action_registry")
require("core.actions")

local DISCARD_CAP = Registry.get("discard_hand").schema.properties.indices.maxItems
check("the discard cap is readable from the contract", (DISCARD_CAP or 0) > 0, tostring(DISCARD_CAP))

local ready_boards, others_lists = 0, 0
for _, board in ipairs(LB.BOARDS) do
  if board.state == "SELECTING_HAND" then
    LB.load(board.state, board.desc)
    local first = FP.build(board.state)
    local q = (first and first.query) or ""
    if q:find("Ready to play now:", 1, true) then ready_boards = ready_boards + 1 end

    for list in q:gmatch("the others are ([%d, ]+)") do
      others_lists = others_lists + 1
      local n = 0
      for _ in list:gmatch("%d+") do n = n + 1 end
      check("" .. board.desc:sub(1, 22) .. ": the named discard fits discard_hand",
        n <= DISCARD_CAP, n .. " positions named, cap " .. DISCARD_CAP .. ": " .. list)
    end
  end
end
check("the live corpus renders a Ready section for SELECTING_HAND", ready_boards >= 2,
  "boards with a Ready section: " .. ready_boards)
check("the sweep actually found odds sentences to check", others_lists > 0, tostring(others_lists))

local function suit_card(rank, suit, i) return LB.pcard(rank, suit, 100 + i) end

local function board(hand, jokers)
  _G.G.NEURO = { run_generation = 1, once_serials = {}, session_once_serials = {} }
  _G.G.hand = { cards = hand, highlighted = {},
    config = { card_limit = 8, highlighted_limit = 5 } }
  _G.G.jokers = { cards = jokers or {}, config = { card_limit = 5 } }
  _G.G.consumeables = { cards = {}, config = { card_limit = 2 } }
  _G.G.deck = { cards = {} }
  _G.G.playing_cards = _G.G.deck.cards
  _G.G.GAME = { current_round = { hands_left = 3, discards_left = 2 }, chips = 0,
    hands = {}, probabilities = { normal = 1 }, dollars = 10 }
  for _, n in ipairs({ "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush",
      "Full House", "Four of a Kind", "Straight Flush", "Five of a Kind" }) do
    _G.G.GAME.hands[n] = { visible = true, level = 1, chips = 10, mult = 2, played = 0 }
  end
  _G.G.FUNCS = { get_poker_hand_info = TD.get_poker_hand_info }
  HF._set_shuffle(function(list) return list end)
end

local FACE_HOUSE = {
  suit_card("K", "Hearts", 1), suit_card("K", "Spades", 2), suit_card("K", "Diamonds", 3),
  suit_card("Q", "Hearts", 4), suit_card("Q", "Spades", 5),
}
board(FACE_HOUSE, { LB.joker("j_scary_face", 900) })
local summary = HF.summary()
local ready_seg = summary:match("Ready: ([^%.]*)") or ""
check("the measured board really is multi-candidate",
  select(2, ready_seg:gsub(";", "")) >= 2, ready_seg)

local function value_of(name)
  local entry = ready_seg:match(name:gsub("%s", "%%s") .. "%[[%d,]+%][^;]*")
  return entry and entry:match("%(J[%dJ,]+ ([^%)]+)%)") or nil
end
local house, trips = value_of("Full House"), value_of("Three of a Kind")
check("Full House states its own joker contribution", house ~= nil, ready_seg)
check("Three of a Kind states its own joker contribution", trips ~= nil, ready_seg)
check("the two candidates are priced differently", house ~= trips,
  tostring(house) .. " vs " .. tostring(trips) .. " :: " .. ready_seg)
check("the number is the engine's, not a roster ceiling",
  house == "+150c" and trips == "+90c", tostring(house) .. " / " .. tostring(trips))

do
  local stripped = ready_seg:gsub("%(J[%dJ,]+ [^%)]*%)", "")
  local function priced(name)
    local entry = stripped:match(name:gsub("%s", "%%s") .. "%[[%d,]+%][^;]*")
    return entry and table.concat({ entry:match("(%b())") or "" }) or nil
  end
  local a, b = priced("Full House"), priced("Three of a Kind")
  check("without the per-candidate note the entries carry the same numbers", a ~= nil and a == b,
    tostring(a) .. " vs " .. tostring(b))
end

do
  local hand = {
    suit_card("K", "Hearts", 11), suit_card("K", "Spades", 12), suit_card("2", "Clubs", 13),
    suit_card("7", "Diamonds", 14), suit_card("9", "Hearts", 15), suit_card("3", "Spades", 16),
    suit_card("4", "Clubs", 17), suit_card("5", "Diamonds", 18),
  }
  board(hand, {})
  _G.G.deck = { cards = { suit_card("K", "Clubs", 19), suit_card("8", "Hearts", 20) } }
  _G.G.playing_cards = _G.G.deck.cards
  local s = HF.summary()
  local cap = CardUtil.highlight_limit()
  local seen = 0
  for list in s:gmatch("/other%[([%d,]+)%]") do
    seen = seen + 1
    local n = 1
    for _ in list:gmatch(",") do n = n + 1 end
    check("the compact other-list is a discard the schema accepts", n <= cap,
      n .. " > " .. cap .. " in " .. list)
  end
  check("the oversized case was actually reached", seen > 0 and s:find("discard at most", 1, true) ~= nil,
    s:match("Close:[^%.]*") or s)
  local capped = s:match("Three of a Kind keep%[1,2%]/other%[([%d,]+)%]")
  check("the capped list drops the highest-ranked other, not an arbitrary tail",
    capped == "3,4,6,7,8", tostring(capped) .. " :: " .. (s:match("Close:[^%.]*") or ""))
end

HF._set_shuffle(nil)
done()
