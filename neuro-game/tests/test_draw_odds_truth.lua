_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local H = require("tests.helpers")
local check, done = H.harness("draw-odds truth")
local HF = require("facts.hand_facts")

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
local SUITS = { "Hearts", "Spades", "Diamonds", "Clubs" }

local function card(v, suit)
  local id = H.RID[v]
  return {
    base = { value = H.VALN[v] or v, suit = suit, id = id },
    ability = { set = "Default", name = "Base", effect = "" },
    config = { center = { key = "c_base", set = "Default" } },
    facing = "front",
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local function deck_minus(hand)
  local used = {}
  for _, c in ipairs(hand) do used[tostring(c.base.value) .. c.base.suit] = true end
  local out = {}
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = card(v, s)
      if not used[tostring(c.base.value) .. s] then out[#out + 1] = c end
    end
  end
  return out
end

local function setup(hand, opts)
  opts = opts or {}
  G.hand = { cards = hand,
    config = { highlighted_limit = 5, card_limit = opts.card_limit or 8 }, highlighted = {} }
  G.deck = { cards = opts.deck or deck_minus(hand) }
  G.jokers = nil
  G.GAME = {
    current_round = { discards_left = 3, hands_left = 4, discards_used = 0, hands_played = 0 },
    hands = {},
    blind = opts.blind or {},
  }
  G.FUNCS = {}
end

local function pct(n, m, k)
  if k < 1 or n < 1 or m < 1 then return 0 end
  if k >= m or n >= m then return 100 end
  local miss = 1.0
  for i = 0, k - 1 do miss = miss * (m - n - i) / (m - i) end
  return math.floor((1 - miss) * 100 + 0.5)
end

local function flush_draw(s)
  local n, m, p = s:match("Flush: %d+ %a+ keep[^%(]*%(draw (%d+)/(%d+)=(%d+)%%%)")
  if not n then return "<no flush draw note>" end
  return n .. "/" .. m .. "=" .. p .. "%"
end
local function straight_draw(s)
  local keep, n, m, p = s:match("Straight keep([^%(]*)%(draw (%d+)/(%d+)=(%d+)%%%)")
  if not keep then return "<no straight draw note>" end
  return keep .. n .. "/" .. m .. "=" .. p .. "%"
end

local HEARTS4 = { "K", "9", "7", "3" }
local function four_heart_hand()
  local h = {}
  for _, v in ipairs(HEARTS4) do h[#h + 1] = card(v, "Hearts") end
  h[#h + 1] = card("2", "Spades"); h[#h + 1] = card("4", "Clubs")
  h[#h + 1] = card("6", "Diamonds"); h[#h + 1] = card("8", "Spades")
  return h
end

do
  local hand = four_heart_hand()
  setup(hand, { card_limit = 8 })
  local plain = HF.summary()
  check("no boss: an 8-of-8 hand discarding 4 draws 4",
    flush_draw(plain) == "9/44=" .. pct(9, 44, 4) .. "%",
    flush_draw(plain) .. " (expected 9/44=" .. pct(9, 44, 4) .. "%)")

  setup(four_heart_hand(), { card_limit = 8,
    blind = { name = "The Serpent", key = "bl_serpent", in_blind = true, disabled = false, debuff = {} } })
  local serpent = HF.summary()
  check("The Serpent: the same discard draws 3, not 4",
    flush_draw(serpent) == "9/44=" .. pct(9, 44, 3) .. "%",
    flush_draw(serpent) .. " (expected 9/44=" .. pct(9, 44, 3) .. "%)")

  setup(four_heart_hand(), { card_limit = 8,
    blind = { name = "The Serpent", key = "bl_serpent", in_blind = true, disabled = true, debuff = {} } })
  check("a disabled Serpent does not cap the draw (blind.lua:560 self.disabled)",
    flush_draw(HF.summary()) == "9/44=" .. pct(9, 44, 4) .. "%", flush_draw(HF.summary()))

  setup(four_heart_hand(), { card_limit = 8, deck = { card("2", "Hearts"), card("5", "Hearts") },
    blind = { name = "The Serpent", key = "bl_serpent", in_blind = true, disabled = false, debuff = {} } })
  check("The Serpent with 2 cards left draws min(#deck,3)=2",
    flush_draw(HF.summary()) == "2/2=100%", flush_draw(HF.summary()))

  local short_hand = {}
  for _, v in ipairs(HEARTS4) do short_hand[#short_hand + 1] = card(v, "Hearts") end
  short_hand[#short_hand + 1] = card("2", "Spades")
  setup(short_hand, { card_limit = 5,
    blind = { name = "The Serpent", key = "bl_serpent", in_blind = true, disabled = false, debuff = {} } })
  check("The Serpent: discarding 1 still draws 3 rather than capping the normal refill at 1",
    flush_draw(HF.summary()) == "9/47=" .. pct(9, 47, 3) .. "%",
    flush_draw(HF.summary()) .. " (expected 9/47=" .. pct(9, 47, 3) .. "%)")
end

do
  local hand = {}
  for _, v in ipairs(HEARTS4) do hand[#hand + 1] = card(v, "Hearts") end
  hand[#hand + 1] = card("2", "Spades"); hand[#hand + 1] = card("4", "Clubs")
  setup(hand, { card_limit = 8 })
  check("hand under its limit: discarding 2 draws 4",
    flush_draw(HF.summary()) == "9/46=" .. pct(9, 46, 4) .. "%",
    flush_draw(HF.summary()) .. " (expected 9/46=" .. pct(9, 46, 4) .. "%)")

  local hand2 = {}
  for _, v in ipairs(HEARTS4) do hand2[#hand2 + 1] = card(v, "Hearts") end
  hand2[#hand2 + 1] = card("2", "Spades"); hand2[#hand2 + 1] = card("4", "Clubs")
  setup(hand2, { card_limit = 10 })
  check("a raised hand-size cap raises the draw with it: discarding 2 draws 6",
    flush_draw(HF.summary()) == "9/46=" .. pct(9, 46, 6) .. "%",
    flush_draw(HF.summary()) .. " (expected 9/46=" .. pct(9, 46, 6) .. "%)")
end

do
  local hand = { card("2", "Hearts"), card("3", "Spades"), card("4", "Diamonds"), card("5", "Clubs"),
                 card("10", "Spades"), card("J", "Diamonds"), card("Q", "Clubs"), card("K", "Hearts") }
  setup(hand, { card_limit = 8 })
  local s = HF.summary()
  check("2345 + 10JQK: outs are counted over the kept window only",
    straight_draw(s) == "[1,2,3,4]/other[5,6,7,8]8/44=" .. pct(8, 44, 4) .. "%",
    straight_draw(s))

  local hand2 = { card("9", "Hearts"), card("10", "Spades"), card("J", "Diamonds"), card("K", "Clubs"),
                  card("3", "Spades"), card("5", "Diamonds"), card("7", "Clubs"), card("2", "Hearts") }
  setup(hand2, { card_limit = 8 })
  local s2 = HF.summary()
  check("7,9,10,J keep-list: the Queen is not an out for it",
    straight_draw(s2) == "[1,2,3,7]/other[4,5,6,8]4/44=" .. pct(4, 44, 4) .. "%",
    straight_draw(s2))
end

do
  local hand = {}
  for _, v in ipairs(HEARTS4) do hand[#hand + 1] = card(v, "Hearts") end
  setup(hand, { card_limit = 8 })
  local s = HF.summary()
  check("nothing to discard: no draw percentage is published",
    s:find("=0%%%)") == nil and s:find("(draw ", 1, true) == nil, s)
  check("nothing to discard: the near-flush shape is still reported",
    s:find("Flush: 4 Hearts keep[1,2,3,4]", 1, true) ~= nil, s)
end

done()
