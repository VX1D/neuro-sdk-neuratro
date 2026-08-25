_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")

local check, done = require("tests.helpers").harness("forced-play-weak-pause")

local VALN = require("tests.helpers").VALN
local _next_sort_id = 0
local function card(v, suit)
  _next_sort_id = _next_sort_id + 1
  return {
    base = { value = VALN[v] or v, suit = suit },
    sort_id = _next_sort_id,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == suit end,
  }
end
local function hand8(c7, c8)
  return { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"),
           card("7","Clubs"), card("4","Clubs"), c7, c8 }
end
local function phi(text, poker_hands)
  return function() return text, {}, poker_hands or {}, {} end
end
local function setup(cards, phi_fn, opts)
  opts = opts or {}
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = opts.discards or 0, hands_left = opts.hands or 1 },
             hands = opts.hand_levels or {}, blind = {} },
    FUNCS = { get_poker_hand_info = phi_fn },
    NEURO = {},
    play = nil,
  }
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}), { hands = 1, discards = 0,
    hand_levels = { Pair = { level = 5, chips = 30, mult = 3 } } })

  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("bare Pair on the last hand with no discards is not committed unseen",
    res == nil and ActionResult.is_error(err), tostring(res))
  local norm = ActionResult.normalize(err)
  check("the pause is a confirmation, not a failure",
    norm.reason_code == "CONFIRMATION_REQUIRED", tostring(norm.reason_code))
  local expected = "Selection [7,8] = Pair (lvl 5, 30 chips x 3 mult).\n"
    .. "This is a bare Pair -- one of the three lowest-ranking hand types. Send this same selection again to commit it, or send a different final selection. It commits if it passes the debuff and blind safety guards; there is no second weak/general confirmation."
  check("the message is exactly the zero-discard weak pause text", norm.message == expected, norm.message)
  check("the weak layer fired and armed the quality latch",
    G.NEURO.last_quality_reject ~= nil and G.NEURO.last_legality_reject == nil
      and tonumber(G.NEURO.weak_fired_serial) == 0, tostring(G.NEURO.last_quality_reject))

  local res2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("resending the same selection commits it", type(res2) == "function", type(res2))
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}), { hands = 1, discards = 0 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  local expected = "Selection [7,8] = Pair.\n"
    .. "This is a bare Pair -- one of the three lowest-ranking hand types. Send this same selection again to commit it, or send a different final selection. It commits if it passes the debuff and blind safety guards; there is no second weak/general confirmation."
  check("the pause carries the engine verdict with no hand-level entry available",
    ActionResult.normalize(err).message == expected, ActionResult.normalize(err).message)
end

do
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", {}), { hands = 1, discards = 0 })
  local res = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("a non-weak hand still commits on the first send", type(res) == "function", type(res))
  check("no latch armed for the non-weak commit",
    G.NEURO.last_quality_reject == nil and G.NEURO.last_legality_reject == nil,
    tostring(G.NEURO.last_quality_reject))
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", { Pair = { 1 }, ["Two Pair"] = { 1 } }), { hands = 1, discards = 0 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  local msg = ActionResult.normalize(err).message
  check("with two ready hands the general confirmation still owns the pause",
    res == nil and msg:find("Committing Pair", 1, true) ~= nil
      and msg:find("lowest-ranking", 1, true) == nil, msg)
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}), { hands = 2, discards = 0 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  local msg = ActionResult.normalize(err).message
  check("with a hand in reserve the general confirmation still owns the pause",
    res == nil and msg:find("Committing Pair", 1, true) ~= nil
      and msg:find("Send the same indices again", 1, true) ~= nil
      and msg:find("Send this same selection again", 1, true) == nil, msg)
  check("Z10b and it names the weakness instead of committing a bare hand in silence",
    msg:find("lowest%-ranking") ~= nil and msg:find("no discards left", 1, true) ~= nil, msg)
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}), { hands = 1, discards = 0 })
  local res1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("the weak pause fires first", res1 == nil)
  local res2 = HandHandlers.handle_play_hand({ indices = { 5, 6 } })
  check("a different final selection commits without a second confirmation",
    type(res2) == "function", type(res2))
end

do
  local DebuffFacts = require("facts.debuff_facts")
  local real_active, real_halve = DebuffFacts.flint_active, DebuffFacts.flint_halve
  DebuffFacts.flint_active = function() return true end

  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}), { hands = 1, discards = 0,
    hand_levels = { Pair = { level = 5, chips = 30, mult = 3 } } })
  local _, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  local msg = ActionResult.normalize(err).message or ""

  local ch, mu = real_halve(30, 3)
  check("under The Flint the verdict quotes the halved base, not the raw table",
    msg:find("(lvl 5, " .. ch .. " chips x " .. mu .. " mult)", 1, true) ~= nil, msg)
  check("and it never quotes the unhalved pair the legend told the reader to trust",
    msg:find("30 chips x 3 mult", 1, true) == nil, msg)

  DebuffFacts.flint_active, DebuffFacts.flint_halve = real_active, real_halve
end

done()
