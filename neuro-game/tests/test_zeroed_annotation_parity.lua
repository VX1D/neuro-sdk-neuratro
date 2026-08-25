_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("zeroed-annotation-parity")

local A = require("core.actions")
local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")
local HF = require("facts.hand_facts")
local DF = require("facts.debuff_facts")

local MOCK_RESET = { "hand", "jokers", "consumeables", "shop_jokers", "shop_booster", "shop_vouchers",
  "pack_cards", "deck", "STATE", "STATES", "OVERLAY_MENU", "CONTROLLER", "P_BLINDS" }

local function mock_state(desc_match, state)
  require("core.action_receipt").reset("mock_state")
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.FUNCS.get_poker_hand_info = nil
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc:find(desc_match, 1, true) then
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro"
      G.NEURO.state_entry_hints = nil
      return
    end
  end
  error("mock_state: no scenario " .. desc_match)
end

local function card(v, s)
  return { base = { value = v, suit = s }, config = { center = { key = "c" } } }
end

local function board()
  mock_state("Normal", "SELECTING_HAND")
  local h = { card("7", "Hearts"), card("7", "Spades"), card("7", "Clubs"),
    card("K", "Hearts"), card("K", "Diamonds") }
  G.hand = { cards = h, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.GAME.hands = {
    ["Three of a Kind"] = { visible = true, level = 4, chips = 75, mult = 9, played = 0 },
    ["Four of a Kind"] = { visible = true, level = 1, chips = 60, mult = 7, played = 0 },
    ["Full House"] = { visible = true, level = 1, chips = 40, mult = 4, played = 0 },
    ["Two Pair"] = { visible = true, level = 1, chips = 20, mult = 2, played = 0 },
    Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
    ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 0 },
  }
  G.FUNCS.get_poker_hand_info = function(cards)
    local by, order = {}, {}
    for _, c in ipairs(cards) do
      local r = c.base.value
      if not by[r] then by[r] = {}; order[#order + 1] = r end
      table.insert(by[r], c)
    end
    table.sort(order)
    local ph = {}
    for _, k in ipairs({ "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush",
      "Full House", "Four of a Kind", "Straight Flush", "Five of a Kind", "Flush House", "Flush Five" }) do
      ph[k] = {}
    end
    ph["High Card"] = { cards[1] }
    local trips, prs = nil, {}
    for _, r in ipairs(order) do
      if #by[r] >= 3 then trips = by[r] end
      if #by[r] >= 2 then prs[#prs + 1] = { by[r][1], by[r][2] } end
    end
    local text = "High Card"
    if trips then
      text = "Three of a Kind"
      ph["Three of a Kind"] = { { trips[1], trips[2], trips[3] } }
    end
    if #prs >= 2 then
      local tp = {}
      for _, pc in ipairs(prs) do for _, c in ipairs(pc) do tp[#tp + 1] = c end end
      ph["Two Pair"] = { tp }
    end
    if #prs >= 1 then ph["Pair"] = { prs[1] } end
    return text, nil, ph, cards, nil
  end
end

local function mouth_without_method()
  return { name = "The Mouth", key = "bl_mouth", disabled = false, debuff = {}, only_hand = "Flush",
    config = { blind = { key = "bl_mouth", name = "The Mouth" } } }
end

local function mouth_with_method()
  local b = mouth_without_method()
  b.debuff_hand = function(self, _, _, handname)
    return self.only_hand and self.only_hand ~= handname or false
  end
  return b
end

local function lists(summary)
  return tostring(summary:match("Ready:[^\n]-%.") or ""), tostring(summary:match("Close:[^\n]-%.") or "")
end

board()
G.GAME.blind = mouth_without_method()
local s_no = HF.summary()
local ready_no, close_no = lists(s_no)

check("the fixture has both lists", ready_no ~= "" and close_no ~= "", s_no)
check("the Close list warns that these hands score 0",
  close_no:find("zeroed by The Mouth", 1, true) ~= nil, close_no)
check("the Ready list warns too, with no live debuff_hand method on the blind",
  ready_no:find("zeroed by The Mouth", 1, true) ~= nil, ready_no)
check("the biggest Ready entry is the one that carries the warning",
  ready_no:find("Three of a Kind[^;]*zeroed by The Mouth") ~= nil, ready_no)

G.GAME.blind = mouth_without_method()
for _, n in ipairs({ "Three of a Kind", "Two Pair", "Pair", "Four of a Kind", "Full House" }) do
  local cards = { G.hand.cards[1], G.hand.cards[2], G.hand.cards[3] }
  check("both predicates agree on " .. n .. " with no debuff_hand method",
    DF.boss_would_debuff(cards, n) == DF.boss_blocks_handname(n),
    tostring(DF.boss_would_debuff(cards, n)) .. " vs " .. tostring(DF.boss_blocks_handname(n)))
end
check("and the locked type itself is NOT annotated",
  DF.boss_would_debuff({ G.hand.cards[1] }, "Flush") == false,
  tostring(DF.boss_would_debuff({ G.hand.cards[1] }, "Flush")))

board()
G.GAME.blind = mouth_with_method()
local ready_with = (lists(HF.summary()))
check("a blind that does carry the method annotates the same Ready entry",
  ready_with:find("Three of a Kind[^;]*zeroed by The Mouth") ~= nil, ready_with)

board()
G.GAME.blind = { name = "Small Blind", key = "bl_small", disabled = true, debuff = {} }
local plain = HF.summary()
check("with no active boss rule neither list is annotated",
  plain:find("zeroed by", 1, true) == nil, plain)

done()
