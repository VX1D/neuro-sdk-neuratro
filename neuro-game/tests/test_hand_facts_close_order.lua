_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")
local check, done = require("tests.helpers").harness("hand-facts-close-order")

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local function card(v, suit)
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit },
    config = { center = { key = "c_base", set = "Default" } },
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local HAND_ORDER = {
  ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4,
  ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8,
  ["Straight Flush"] = 9, ["Five of a Kind"] = 10, ["Flush House"] = 11, ["Flush Five"] = 12,
}

local function names_of(seg)
  local names = {}
  if not seg then return names end
  for chunk in (seg .. "; "):gmatch("(.-); ") do
    local n = chunk:match("^near ([%a ]+)") or chunk:match("^([%a ]+)")
    if n then names[#names + 1] = (n:gsub("%s*keep$", "")):match("^%s*(.-)%s*$") end
  end
  return names
end
local function close_names(s) return names_of(s:match("Close: (.-)%.%s")) end
local function ready_names(s) return names_of(s:match("Ready: (.-)%.")) end
local function descending(list)
  for i = 2, #list do
    if (HAND_ORDER[list[i - 1]] or 0) < (HAND_ORDER[list[i]] or 0) then return false end
  end
  return true
end

local function setup()
  local h = { card("K","Hearts"), card("K","Diamonds"), card("3","Spades"), card("7","Clubs"),
              card("9","Hearts"), card("2","Diamonds"), card("5","Spades"), card("8","Clubs") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 3, hands_left = 4 }, hands = {}, blind = {} }
  G.NEURO = { run_generation = 1 }
  G.FUNCS = { get_poker_hand_info = function(cards)
    return nil, nil, { ["Pair"] = { { cards[1], cards[2] } },
                       ["High Card"] = { { cards[1] } } }
  end }
  return h
end

local function reversing(list)
  local out = {}
  for i = 1, #list do out[i] = list[#list - i + 1] end
  return out
end

do
  HF._set_shuffle(reversing)
  setup()
  local s = HF.summary()
  local close = close_names(s)
  check("fixture actually produces a multi-entry Close list (test is meaningful)",
    #close >= 3, table.concat(close, "|"))
  check("Close is HAND_ORDER-descending: the tie-shuffle does not reach it",
    descending(close), table.concat(close, "|"))
  HF._set_shuffle(nil)
end

do
  local seen_shuffled = false
  HF._set_shuffle(reversing)
  local ranks = { "2","3","4","5","6","7","8","9","10","Jack","Queen","King","Ace" }
  for i = 1, 20 do
    local t, p = ranks[(i % #ranks) + 1], ranks[((i * 5 + 3) % #ranks) + 1]
    if t ~= p then
      local h = { card(t,"Hearts"), card(t,"Spades"), card(t,"Clubs"),
                  card(p,"Hearts"), card(p,"Diamonds"), card("4","Clubs") }
      G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
      G.GAME = { current_round = { discards_left = 3, hands_left = 4 }, hands = {}, blind = {} }
      G.NEURO = { run_generation = 1 }
      G.FUNCS = { get_poker_hand_info = function(cards)
        return nil, nil, { ["Three of a Kind"] = { { cards[1], cards[2], cards[3] } },
                           ["Pair"] = { { cards[4], cards[5] } },
                           ["Two Pair"] = { { cards[1], cards[2], cards[4], cards[5] } },
                           ["Full House"] = { { cards[1], cards[2], cards[3], cards[4], cards[5] } } }
      end }
      local r = ready_names(HF.summary())
      if #r >= 3 and not descending(r) then seen_shuffled = true end
    end
  end
  HF._set_shuffle(nil)
  check("Ready keeps the deliberate tie-shuffle", seen_shuffled, seen_shuffled)
end

do
  setup()
  local a = HF.summary()
  local b = HF.summary()
  check("unchanged board: repeated summary() calls are byte-identical", a == b, a .. "\n" .. b)
end

done()
