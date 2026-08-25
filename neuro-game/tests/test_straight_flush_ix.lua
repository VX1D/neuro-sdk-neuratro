_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")

local check, done = require("tests.helpers").harness("straight-flush-ix")

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local function card(v, suit)
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit }, id_ = id, suit_ = suit,
    config = { center = { key = "c_base", set = "Default" } },
    get_id = function(self) return self.id_ end,
    is_suit = function(self, s) return self.suit_ == s end,
  }
end

local SUITS = { "Spades","Hearts","Clubs","Diamonds" }
local function get_flush(h, thr)
  thr = thr or 5
  for _,suit in ipairs(SUITS) do
    local t = {}
    for i=1,#h do if h[i]:is_suit(suit) then t[#t+1]=h[i] end end
    if #t >= thr then return t end
  end
  return nil
end
local function get_straight(h, thr)
  thr = thr or 5
  local IDS = {}
  for i=1,#h do local id=h[i]:get_id(); if id>1 and id<15 then IDS[id]=IDS[id] or {}; table.insert(IDS[id], h[i]) end end
  local t, len, straight = {}, 0, false
  for j=1,14 do
    local rid = (j==1) and 14 or j
    if IDS[rid] then len=len+1; for _,v in ipairs(IDS[rid]) do t[#t+1]=v end
    else len=0; if not straight then t={} end; if straight then break end end
    if len>=thr then straight=true end
  end
  if not straight then return nil end
  return t
end
local function merge(a, b)
  local ret, seen = {}, {}
  for _,grp in ipairs({ a, b }) do for _,v in ipairs(grp) do if not seen[v] then seen[v]=true; ret[#ret+1]=v end end end
  return ret
end
local function merge_flush_first(a, b)
  local ret, seen = {}, {}
  for _,grp in ipairs({ b, a }) do for _,v in ipairs(grp) do if not seen[v] then seen[v]=true; ret[#ret+1]=v end end end
  return ret
end

local function setup(hand, thr, flush_first)
  G.hand = { cards = hand, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Straight Flush"]={level=1,chips=100,mult=8}, Flush={level=1,chips=35,mult=4},
    Straight={level=1,chips=30,mult=4}, Pair={level=1,chips=10,mult=2} } }
  local fl, st = get_flush(hand, thr), get_straight(hand, thr)
  local ph = { Flush = fl and { fl } or {}, Straight = st and { st } or {} }
  if fl and st then
    ph["Straight Flush"] = { (flush_first and merge_flush_first or merge)(st, fl) }
  end
  G.FUNCS = { get_poker_hand_info = function() return nil, nil, ph end }
end

local function sf_ix(hand, thr, flush_first)
  setup(hand, thr, flush_first)
  local s = HF.summary()
  return s:match("Straight Flush(%[[%d,]+%])") or "(absent)", s
end

local function ix(nums) return "[" .. table.concat(nums, ",") .. "]" end

do
  local h = { card("K","Diamonds"), card("9","Clubs"), card("6","Hearts"), card("5","Hearts"),
              card("5","Diamonds"), card("4","Hearts"), card("3","Hearts"), card("2","Hearts") }
  local got, s = sf_ix(h)
  check("A: off-suit dup (5D) dropped, keeps 6H", got == ix({3,4,6,7,8}), got .. " | " .. s:match("Ready:[^.]*"))
end

do
  local h = { card("6","Hearts"), card("5","Diamonds"), card("5","Hearts"),
              card("4","Hearts"), card("3","Hearts"), card("2","Hearts") }
  local got = sf_ix(h)
  check("B: off-suit-first still dropped", got == ix({1,3,4,5,6}), got)
end

do
  local h = { card("A","Spades"), card("3","Hearts"), card("5","Spades"),
              card("4","Spades"), card("3","Spades"), card("2","Spades") }
  local got = sf_ix(h)
  check("C: wheel A-5 keeps 5 spades, drops off-suit 3H", got == ix({1,3,4,5,6}), got)
end

do
  local h = { card("2","Hearts"), card("3","Hearts"), card("4","Hearts"),
              card("5","Hearts"), card("6","Hearts"), card("7","Hearts") }
  local got = sf_ix(h)
  check("D: 6-card SF keeps highest 5", got == ix({2,3,4,5,6}), got)
end

do
  local h = { card("9","Clubs"), card("10","Hearts"), card("J","Hearts"),
              card("Q","Hearts"), card("K","Hearts"), card("A","Hearts") }
  local got = sf_ix(h)
  check("E: clean royal flush", got == ix({2,3,4,5,6}), got)
end

do
  local h = { card("K","Diamonds"), card("9","Clubs"), card("6","Hearts"), card("5","Hearts"),
              card("5","Diamonds"), card("4","Hearts"), card("3","Hearts"), card("2","Hearts") }
  local got = sf_ix(h, 5, true)
  check("F: flush-first merge order also correct", got == ix({3,4,6,7,8}), got)
end

do
  local h = { card("6","Hearts"), card("5","Hearts"), card("5","Diamonds"), card("4","Hearts"),
              card("3","Hearts"), card("3","Spades"), card("2","Hearts") }
  local got = sf_ix(h)
  check("G: two off-suit dups dropped", got == ix({1,2,4,5,7}), got)
end

do
  local h = { card("K","Diamonds"), card("9","Clubs"), card("2","Hearts"), card("3","Hearts"),
              card("4","Hearts"), card("5","Hearts"), card("6","Hearts"), card("K","Hearts") }
  local got = sf_ix(h)
  check("H: off-run suited card (KH) excluded, run kept", got == ix({3,4,5,6,7}), got)
end

do
  local h = { card("K","Hearts"), card("Q","Hearts"), card("9","Hearts"), card("6","Hearts"),
              card("2","Hearts"), card("5","Spades"), card("4","Diamonds"), card("3","Clubs") }
  local got, s = sf_ix(h)
  check("I: disjoint straight+flush -> SF not ready", got == "(absent)", got)
  check("I: Flush and Straight still advertised",
    s:find("Flush%[1,2,3,4,5%]") ~= nil and s:find("Straight%[4,5,6,7,8%]") ~= nil,
    s:match("Ready:[^.]*"))
end

do
  local h = { card("2","Spades"), card("3","Hearts"), card("4","Diamonds"), card("5","Clubs"),
              card("6","Spades"), card("7","Hearts"), card("9","Clubs"), card("K","Diamonds") }
  setup(h)
  local s = HF.summary()
  local got = s:match("Straight(%[[%d,]+%])") or "(absent)"
  check("J: 6-card straight keeps 3-7", got == ix({2,3,4,5,6}), got .. " | " .. (s:match("Ready:[^.]*") or ""))
end

do
  local h = { card("A","Spades"), card("2","Hearts"), card("3","Diamonds"),
              card("4","Clubs"), card("5","Spades"), card("6","Hearts") }
  setup(h)
  local s = HF.summary()
  local got = s:match("Straight(%[[%d,]+%])") or "(absent)"
  check("K: A-6 run keeps the wheel (A-5, 25 chips)", got == ix({1,2,3,4,5}), got)
end

do
  local d5 = card("5","Clubs"); d5.debuff = true
  local h = { card("2","Spades"), card("3","Hearts"), card("4","Diamonds"), d5,
              card("5","Spades"), card("6","Hearts") }
  setup(h)
  local s = HF.summary()
  local got = s:match("Straight(%[[%d,]+%])") or "(absent)"
  check("L: debuffed dup 5C skipped for scoring 5S", got == ix({1,2,3,5,6}), got)
end

do
  local h = { card("9","Spades"), card("9","Hearts"), card("9","Hearts"),
              card("9","Hearts"), card("K","Hearts"), card("K","Hearts") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Flush House"]={level=1,chips=140,mult=14}, ["Full House"]={level=1,chips=40,mult=4} } }
  local all_pairs = { h[5], h[6], h[1], h[2], h[3], h[4] }
  local flush = { h[2], h[3], h[4], h[5], h[6] }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil,
    { ["Flush House"] = { merge(all_pairs, flush) }, ["Full House"] = { all_pairs } } end }
  local s = HF.summary()
  local got = s:match("Flush House(%[[%d,]+%])") or "(absent)"
  check("M: Flush House excludes off-suit 9S", got == ix({2,3,4,5,6}), got)
end

do
  local h = { card("9","Spades"), card("9","Clubs"), card("9","Hearts"), card("K","Hearts"),
              card("K","Spades"), card("2","Hearts"), card("5","Hearts"), card("7","Hearts") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Flush House"]={level=1,chips=140,mult=14}, ["Full House"]={level=1,chips=40,mult=4} } }
  local all_pairs = { h[4], h[5], h[1], h[2], h[3] }
  local flush = { h[3], h[4], h[6], h[7], h[8] }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil,
    { ["Flush House"] = { merge(all_pairs, flush) }, ["Full House"] = { all_pairs } } end }
  local s = HF.summary()
  check("N: unrealizable Flush House dropped", s:find("Flush House") == nil, s:match("Ready:[^.]*"))
  check("N: Full House survives", s:find("Full House%[") ~= nil, s:match("Ready:[^.]*"))
end

do
  local h = { card("9","Spades"), card("9","Hearts"), card("9","Hearts"),
              card("9","Hearts"), card("9","Hearts"), card("9","Hearts") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Flush Five"]={level=1,chips=160,mult=16} } }
  local five = { h[1], h[2], h[3], h[4], h[5], h[6] }
  local flush = { h[2], h[3], h[4], h[5], h[6] }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil,
    { ["Flush Five"] = { merge(five, flush) } } end }
  local s = HF.summary()
  local got = s:match("Flush Five(%[[%d,]+%])") or "(absent)"
  check("O: Flush Five takes the 5 suited 9s", got == ix({2,3,4,5,6}), got)
end

do
  local h = { card("K","Hearts"), card("K","Spades"), card("K","Clubs"), card("4","Diamonds") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Pair"]={level=1,chips=10,mult=2}, ["Three of a Kind"]={level=1,chips=30,mult=3} } }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil,
    { ["Pair"] = { { h[1], h[2], h[3] } }, ["Three of a Kind"] = { { h[1], h[2], h[3] } } } end }
  local s = HF.summary()
  local got = s:match("Pair(%[[%d,]+%])") or "(absent)"
  check("P: Pair lists exactly 2 of the 3 kings", got == ix({1,2}), got)
end

do
  local h = { card("3","Hearts"), card("3","Spades"), card("Q","Clubs"), card("Q","Diamonds"),
              card("K","Hearts"), card("K","Spades") }
  G.hand = { cards = h, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {
    ["Two Pair"]={level=1,chips=20,mult=2} } }
  local all_pairs = { h[5], h[6], h[3], h[4], h[1], h[2] }
  G.FUNCS = { get_poker_hand_info = function() return nil, nil,
    { ["Two Pair"] = { all_pairs } } end }
  local s = HF.summary()
  local got = s:match("Two Pair(%[[%d,]+%])") or "(absent)"
  check("Q: Two Pair = KK+QQ only, threes dropped", got == ix({3,4,5,6}), got)
end

done()
