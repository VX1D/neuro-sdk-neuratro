_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")
local check, done = require("tests.helpers").harness("hand-order-shuffle")

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

local function multi_ready_ph(cards)
  local t1, t2, t3, p1, p2 = cards[1], cards[2], cards[3], cards[4], cards[5]
  return {
    ["Three of a Kind"] = { { t1, t2, t3 } },
    ["Pair"] = { { p1, p2 } },
    ["Two Pair"] = { { t1, t2, p1, p2 } },
    ["Full House"] = { { t1, t2, t3, p1, p2 } },
  }
end

local function setup(cards)
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 3, hands_left = 4 }, hands = {} }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil, multi_ready_ph(cards) end }
end

local HAND_ORDER = {
  ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4,
  ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8,
  ["Straight Flush"] = 9, ["Five of a Kind"] = 10, ["Flush House"] = 11, ["Flush Five"] = 12,
}
local function parse_ready(s)
  local seg = s:match("Ready: (.-)%.")
  if not seg then return {} end
  local names = {}
  for chunk in (seg .. "; "):gmatch("(.-); ") do
    local n = chunk:match("^([%a ]+)")
    if n then names[#names + 1] = n:match("^%s*(.-)%s*$") end
  end
  return names
end

local function multi_ready_hand(trip_rank, pair_rank, filler)
  return { card(trip_rank, "Hearts"), card(trip_rank, "Spades"), card(trip_rank, "Clubs"),
    card(pair_rank, "Hearts"), card(pair_rank, "Diamonds"), card(filler, "Clubs") }
end
local function three_pair_hand() return multi_ready_hand("King", "Queen", "4") end

do
  HF._set_shuffle(function(list) return list end)
  setup(three_pair_hand())
  local s = HF.summary()
  local got = parse_ready(s)
  local expected = {}
  for _, n in ipairs(got) do expected[#expected + 1] = n end
  table.sort(expected, function(a, b) return (HAND_ORDER[a] or 0) > (HAND_ORDER[b] or 0) end)
  check("identity shuffle: selection matches the HAND_ORDER-descending oracle",
    #got == #expected and table.concat(got, "|") == table.concat(expected, "|"), s:match("Ready:[^%.]*"))
  check("identity shuffle: at least 2 Ready hands realized (test is meaningful)", #got >= 2, #got)
end

do
  HF._set_shuffle(nil)
  local saw_non_default_order, saw_3plus = false, false
  local ranks = { "2","3","4","5","6","7","8","9","10","Jack","Queen","King","Ace" }
  for i = 1, 60 do
    local trip = ranks[(i % #ranks) + 1]
    local pair = ranks[((i * 5 + 3) % #ranks) + 1]
    local filler = ranks[((i * 7 + 1) % #ranks) + 1]
    if trip ~= pair and trip ~= filler and pair ~= filler then
      setup(multi_ready_hand(trip, pair, filler))
      local s = HF.summary()
      local got = parse_ready(s)
      if #got >= 3 then
        saw_3plus = true
        local in_default_order = true
        for j = 2, #got do
          if (HAND_ORDER[got[j - 1]] or 0) < (HAND_ORDER[got[j]] or 0) then in_default_order = false end
        end
        if not in_default_order then saw_non_default_order = true end
      end
    end
  end
  check("default shuffle: fixture actually produces 3+-item Ready lists (test is meaningful)", saw_3plus)
  check("default shuffle: at least one 3+-item Ready list is NOT in HAND_ORDER-descending order",
    saw_non_default_order, saw_non_default_order)
end

do
  setup(three_pair_hand())
  local s1 = HF.summary()
  local s2 = HF.summary()
  check("unchanged hand: repeated summary() calls are byte-identical",
    s1:match("Ready:[^%.]*") == s2:match("Ready:[^%.]*"), (s1:match("Ready:[^%.]*") or "") .. " | " .. (s2:match("Ready:[^%.]*") or ""))
end

do
  local calls = 0
  HF._set_shuffle(function(list)
    calls = calls + 1
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    if calls % 2 == 0 then
      local rev = {}
      for i = 1, #out do rev[i] = out[#out - i + 1] end
      out = rev
    end
    return out
  end)
  setup(three_pair_hand())
  local s1 = HF.summary()
  local calls_after_first = calls
  local s2 = HF.summary()
  check("cache hit: identical hand does not re-invoke the shuffle", calls == calls_after_first, calls)

  setup(three_pair_hand())
  HF.summary()
  check("cache invalidation: a changed hand re-invokes the shuffle", calls > calls_after_first, calls)
end

HF._set_shuffle(nil)
done()
