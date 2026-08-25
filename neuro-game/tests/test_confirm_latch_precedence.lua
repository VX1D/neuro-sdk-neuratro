_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")

local check, done = require("tests.helpers").harness("confirm-latch-precedence")

local VALN = require("tests.helpers").VALN
local _next_sort_id = 0
local function card(v, suit, debuff)
  _next_sort_id = _next_sort_id + 1
  return {
    base = { value = VALN[v] or v, suit = suit },
    debuff = debuff or nil,
    sort_id = _next_sort_id,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == suit end,
  }
end
local function phi(text, scoring)
  return function() return text, {}, {}, scoring end
end
local function indices_of(list)
  return table.concat(list or {}, ",")
end

local d1, d2 = card("9","Hearts", true), card("9","Diamonds", true)
local hand = { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"),
               card("7","Spades"), card("4","Clubs"), d1, d2 }
local flush = { hand[1], hand[2], hand[3], hand[4], hand[5] }
_G.G = {
  hand = { cards = hand, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
  GAME = { current_round = { discards_left = 0, hands_left = 3 }, hands = {}, blind = {} },
  FUNCS = { get_poker_hand_info = phi("Pair", { d1, d2 }) },
  NEURO = {},
  play = nil,
}

local res1, err1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
check("an all-debuffed selection draws the boss verdict",
  res1 == nil and ActionResult.normalize(err1).boss_verdict == true, tostring(err1))
check("the verdict arms the legality slot and announces it",
  G.NEURO.last_legality_reject == (d1.sort_id .. "," .. d2.sort_id)
    and G.NEURO.last_confirm_armed == "legality", tostring(G.NEURO.last_confirm_armed))

G.FUNCS.get_poker_hand_info = phi("Flush", flush)
local res2, err2 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
local msg2 = ActionResult.normalize(err2).message
check("a different selection meets the general confirmation",
  res2 == nil and msg2:find("Committing Flush", 1, true) ~= nil
    and msg2:find("Any other selection gets its own confirmation first", 1, true) ~= nil, msg2)
check("the boss verdict is still remembered in its own slot",
  G.NEURO.last_legality_reject == (d1.sort_id .. "," .. d2.sort_id)
    and G.NEURO.last_quality_reject ~= nil
    and G.NEURO.last_confirm_armed == "quality", tostring(G.NEURO.last_confirm_armed))
check("the force announces the newest selection",
  indices_of(HandHandlers.pending_confirm_indices()) == "1,2,3,4,5",
  indices_of(HandHandlers.pending_confirm_indices()))

G.FUNCS.get_poker_hand_info = phi("Pair", { d1, d2 })
local res3, err3 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
check("the older slot no longer commits: that selection is confirmed again",
  res3 == nil and ActionResult.is_error(err3), type(res3))
check("the reconfirmed selection is the announced one",
  G.NEURO.last_confirm_armed == "legality"
    and indices_of(HandHandlers.pending_confirm_indices()) == "7,8",
  indices_of(HandHandlers.pending_confirm_indices()))

G.FUNCS.get_poker_hand_info = phi("Flush", flush)
local res4, err4 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
check("the selection that lost the announcement is confirmed again too",
  res4 == nil and ActionResult.is_error(err4), type(res4))
local res5 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
check("the announced selection commits on the identical resend", type(res5) == "function", type(res5))

G.NEURO = {}
G.FUNCS.get_poker_hand_info = phi("Pair", { d1, d2 })
local res6, err6 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
local msg6 = ActionResult.normalize(err6).message
check("a lone boss verdict is the only armed confirmation",
  res6 == nil and ActionResult.normalize(err6).boss_verdict == true
    and G.NEURO.last_confirm_armed == "legality" and G.NEURO.last_quality_reject == nil,
  tostring(G.NEURO.last_confirm_armed))
check("the verdict itself promises that the resend commits",
  msg6:find("Resend the same indices to commit this play", 1, true) ~= nil, msg6)
check("the force announces exactly that selection",
  indices_of(HandHandlers.pending_confirm_indices()) == "7,8",
  indices_of(HandHandlers.pending_confirm_indices()))

G.FUNCS.get_poker_hand_info = phi("Flush", flush)
local res7, err7 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
check("a lone verdict does not license a different selection",
  res7 == nil and ActionResult.is_error(err7), type(res7))

G.NEURO = {}
G.FUNCS.get_poker_hand_info = phi("Pair", { d1, d2 })
HandHandlers.handle_play_hand({ indices = { 7, 8 } })
local res8 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
check("the announced verdict commits on the identical resend", type(res8) == "function", type(res8))
check("committing clears both slots and the announcement",
  G.NEURO.last_legality_reject == nil and G.NEURO.last_quality_reject == nil
    and G.NEURO.last_confirm_armed == nil, tostring(G.NEURO.last_confirm_armed))

done()
