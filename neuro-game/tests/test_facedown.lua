_G.NEURO_TEST = true
_G.G = { GAME = { current_round = {}, blind = nil }, FUNCS = {} }

local CardUtil = require("facts.card_util")
local CtxHand = require("context.ctx_hand")
local HandFacts = require("facts.hand_facts")

local check, done = require("tests.helpers").harness("facedown")

local function card(v, s) return { base = { value = v, suit = s }, config = { center = { key = "c" } } } end

local up = card("King", "Hearts")
local dn = card("Queen", "Spades"); dn.facing = "back"
check("is_face_down: front/nil -> false", CardUtil.is_face_down(up) == false)
check("is_face_down: facing 'back' -> true", CardUtil.is_face_down(dn) == true)

local tok_up = CtxHand.card_token(up, false, false)
local tok_dn = CtxHand.card_token(dn, false, false)
check("card_token visible shows rank", tok_up:find("K", 1, true) ~= nil, tok_up)
check("card_token face-down (compact) = FD", tok_dn == "FD", tok_dn)
check("card_token face-down leaks no rank/suit", not (tok_dn:find("Q") or tok_dn:find("S")), tok_dn)
check("card_token face-down (readable) = hidden", CtxHand.card_token(dn, false, true):find("hidden", 1, true) ~= nil)

G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), dn } }
G.FUNCS.get_poker_hand_info = function(_)
  return "Pair", nil, { Pair = { G.hand.cards[1], G.hand.cards[2] } }, { G.hand.cards[1], G.hand.cards[2] }, nil
end
local s_fd = HandFacts.summary()
check("summary w/ face-down: notes it is hidden", s_fd:find("face-down", 1, true) ~= nil, s_fd)
check("summary w/ face-down: the visible cards are still analysed", s_fd:find("Ready:", 1, true) ~= nil, s_fd)
check("summary w/ face-down: states how many are hidden and how many are visible",
  s_fd:find("1 card(s) face-down (hidden), 2 visible", 1, true) ~= nil, s_fd)
check("summary w/ face-down: states the consequence, not just the count",
  s_fd:find("blind gamble", 1, true) ~= nil, s_fd)

do
  local all_dn = { card("King", "Hearts"), card("Queen", "Spades") }
  for _, c in ipairs(all_dn) do c.facing = "back" end
  local saved = G.hand
  G.hand = { cards = all_dn }
  local s_all = HandFacts.summary()
  check("summary w/ every card face-down: says no analysis is possible at all",
    s_all:find("all 2 cards face-down (hidden), 0 visible", 1, true) ~= nil, s_all)
  G.hand = saved
end
check("has_strong_ready is false when a card is face-down", HandFacts.has_strong_ready() == false)

do
  local saved_info = G.FUNCS.get_poker_hand_info
  local flush = {
    card("2", "Spades"), card("3", "Spades"), card("4", "Spades"),
    card("5", "Spades"), card("6", "Spades"),
  }
  flush[5].facing = "back"
  G.hand = { cards = flush }
  G.FUNCS.get_poker_hand_info = function(list)
    if #list >= 5 then return "Flush", nil, { Flush = list }, list, nil end
    return "High Card", nil, {}, {}, nil
  end
  HandFacts.summary()
  check("strong-ready cache: hidden fifth Spade is not ready", HandFacts.has_strong_ready() == false)
  flush[5].facing = "front"
  check("strong-ready cache: revealing the same card invalidates the cached false",
    HandFacts.has_strong_ready() == true)
  G.FUNCS.get_poker_hand_info = saved_info
end

G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("9", "Clubs") } }
local s_vis = HandFacts.summary()
check("summary all-visible: analysis present", (s_vis:find("Shape:", 1, true) or s_vis:find("Ready:", 1, true)) ~= nil, s_vis)

G.hand = { cards = { card("King", "Hearts"), dn } }
check("any_face_down true with a hidden card", HandFacts.any_face_down() == true)
G.hand = { cards = { card("King", "Hearts"), card("9", "Clubs") } }
check("any_face_down false when all visible", HandFacts.any_face_down() == false)

local dn2 = card("Ace", "Diamonds"); dn2.facing = "back"
G.hand = { cards = { dn, dn2 } }
local s_all = HandFacts.summary()
check("all-hidden: 0 visible noted", s_all:find("0 visible", 1, true) ~= nil, s_all)
check("all-hidden: neutral 'Your call'", s_all:find("Your call", 1, true) ~= nil, s_all)
check("all-hidden: no play-over-discard nudge", s_all:find("prefer playing", 1, true) == nil, s_all)

G.hand = { cards = { card("King", "Hearts"), dn } }
check("partial face-down keeps prefer-playing guidance", HandFacts.summary():find("prefer playing", 1, true) ~= nil)

do
  G.GAME.blind = { key = "bl_fish", disabled = false, in_blind = true }
  G.GAME.current_round.hands_left = 3
  G.hand = { cards = { card("King", "Hearts"), dn } }
  local fish = HandFacts.summary()
  check("The Fish says discard replacements are face-up",
    fish:find("discarding hidden cards draws face-up replacements", 1, true) ~= nil, fish)
  check("The Fish does not retain the generic anti-discard advice",
    fish:find("fresh draws may also come face-down", 1, true) == nil
      and fish:find("prefer playing", 1, true) == nil, fish)
  G.GAME.blind = nil
end

do
  HandFacts._set_shuffle(function(l) return l end)
  G.GAME.current_round.discards_left = 2
  G.deck = { cards = {
    card("Ace", "Hearts"), card("3", "Hearts"), card("4", "Spades"), card("6", "Clubs"),
    card("8", "Diamonds"), card("10", "Hearts"), card("Jack", "Spades"), card("2", "Hearts"),
  } }
  G.FUNCS.get_poker_hand_info = function(list)
    local by_rank, ranks, by_suit, suits = {}, {}, {}, {}
    for _, c in ipairs(list or {}) do
      local v, u = c.base.value, c.base.suit
      if not by_rank[v] then by_rank[v] = {}; ranks[#ranks + 1] = v end
      by_rank[v][#by_rank[v] + 1] = c
      if not by_suit[u] then by_suit[u] = {}; suits[#suits + 1] = u end
      by_suit[u][#by_suit[u] + 1] = c
    end
    local function hit(name, set)
      return name, nil, { [name] = set }, set, nil
    end
    for _, v in ipairs(ranks) do
      local set = by_rank[v]
      if #set >= 3 then return hit("Three of a Kind", { set[1], set[2], set[3] }) end
    end
    for _, u in ipairs(suits) do
      local set = by_suit[u]
      if #set >= 5 then return hit("Flush", { set[1], set[2], set[3], set[4], set[5] }) end
    end
    for _, v in ipairs(ranks) do
      local set = by_rank[v]
      if #set >= 2 then return hit("Pair", { set[1], set[2] }) end
    end
    return "High Card", nil, {}, {}, nil
  end
  local function hand_with(hidden)
    hidden.facing = "back"
    return {
      cards = { card("9", "Hearts"), card("10", "Hearts"), hidden,
        card("Jack", "Hearts"), card("Queen", "Hearts"), card("9", "Spades") },
      config = { highlighted_limit = 5 },
    }
  end

  G.hand = hand_with(card("4", "Diamonds"))
  local base = HandFacts.summary()
  check("no-leak baseline: Ready and Close are computed from the visible cards",
    base:find("Ready:", 1, true) ~= nil and base:find("Close: near Flush", 1, true) ~= nil
      and base:find("Straight", 1, true) ~= nil, base)
  check("no-leak baseline: positions stay hand positions, hidden slot excluded",
    base:find("Flush: 4 Hearts keep[1,2,4,5]/other[6]", 1, true) ~= nil
      and base:find("Straight keep[1,2,4,5]/other[6]", 1, true) ~= nil
      and base:find("Ready: Pair[1,6]", 1, true) ~= nil, base)

  for _, sub in ipairs({
    { "King", "Hearts" }, { "8", "Spades" }, { "9", "Diamonds" },
    { "Jack", "Diamonds" }, { "2", "Clubs" }, { "Queen", "Hearts" },
  }) do
    G.hand = hand_with(card(sub[1], sub[2]))
    check(string.format("hidden %s of %s changes no byte of the summary", sub[1], sub[2]),
      HandFacts.summary() == base, HandFacts.summary())
  end
  HandFacts._set_shuffle(nil)
end

done()
