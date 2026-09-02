_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")
local PlanGate = require("core.plan_gate")

local check, done = require("tests.helpers").harness("confirm-play-compose")

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
local function hand8(c7, c8)
  return { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"),
           card("7","Clubs"), card("4","Clubs"), c7, c8 }
end

local function phi(text, poker_hands, scoring)
  return function() return text, {}, poker_hands or {}, scoring or {} end
end

local function setup(cards, phi_fn, opts)
  opts = opts or {}
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = opts.discards or 3, hands_left = opts.hands or 4 },
             hands = {}, blind = {} },
    FUNCS = { get_poker_hand_info = phi_fn },
    NEURO = {},
    play = nil,
  }
end

do
  local DW = require("core.decision_window")
  local bridge = { is_transition_cooldown = function() return false end }
  local STATES = { SELECTING_HAND = 1, SHOP = 2, BLIND_SELECT = 3, MENU = 4 }
  for _, sname in ipairs({ "SELECTING_HAND", "SHOP", "BLIND_SELECT" }) do
    _G.G = { STATES = STATES, STATE = STATES[sname], NEURO = {},
             GAME = { current_round = {} }, jokers = { cards = {} } }
    local rp = DW.evaluate("play_hand", bridge)
    local rd = DW.evaluate("discard_hand", bridge)
    check("A play_hand not gated by any window in " .. sname,   rp == false, tostring(rp))
    check("A discard_hand not gated by any window in " .. sname, rd == false, tostring(rd))
  end
  _G.G = { STATES = STATES, STATE = STATES.SHOP, NEURO = {},
           GAME = { current_round = {} }, jokers = { cards = {} } }
  local rbuy = DW.evaluate("buy_from_shop", bridge)
  local required = PlanGate.action_requirements("SHOP", "buy_from_shop").plan
  check("A control: buy_from_shop carries inline plan requirements without a decision bounce",
    rbuy == false and next(required) ~= nil, tostring(rbuy))
end

do -- bypass fires: last hand, no discards, <=1 ready hand (poker_hands empty) -> commit first try
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", {}, {}), { hands = 1, discards = 0 })
  local res = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("forced_play (1 hand/0 disc/<=1 ready) commits on first send", type(res) == "function", type(res))
  check("no latch armed when confirm bypassed", G.NEURO.play_confirm == nil, tostring(G.NEURO.play_confirm))
end

do -- negative: last hand, no discards, but >=2 ready hands -> NOT forced -> confirm still fires
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", { Pair = { 1 }, ["Two Pair"] = { 1 } }, {}), { hands = 1, discards = 0 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check(">=2 ready hands: confirm fires despite last hand/no discards",
    res == nil and ActionResult.is_error(err), tostring(err))
  check("transaction opened by the confirm", require("core.hand_transaction").current() ~= nil,
    tostring(require("core.hand_transaction").current()))
end

do -- negative: more than one hand left -> never forced -> confirm fires
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", {}, {}), { hands = 2, discards = 0 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("hands_left>1: confirm fires (forced_play requires exactly 1 hand)",
    res == nil and ActionResult.is_error(err), tostring(err))
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}, {}), { hands = 4, discards = 3 })
  local res1, err1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("first play with discards left pauses once", res1 == nil and ActionResult.is_error(err1), tostring(err1))
  local msg = ActionResult.normalize(err1).message
  check("the weak guard owns the pause and exposes the explicit yes/no resolution",
    msg:find("Bare Pair", 1, true) ~= nil
      and msg:find("resolve_play", 1, true) ~= nil
      and msg:find("transaction_id", 1, true) ~= nil, msg)
  local tx = require("core.hand_transaction").current()
  check("quality transaction owns the paused selection", tx ~= nil and tx.phase == "publishing",
    tx and tostring(tx.phase) or "nil")
  local res2, err2 = HandHandlers.handle_play_hand({ indices = { 6, 7 } })
  check("strict resolution mode blocks a different selection until this proposal is resolved",
    res2 == nil and ActionResult.is_error(err2)
      and ActionResult.normalize(err2).reason_code == "POLICY_ACKNOWLEDGED", tostring(err2))
  local res3, err3 = HandHandlers.handle_play_hand({ indices = { 6, 7 } })
  check("resending that exact selection does not commit", res3 == nil and ActionResult.is_error(err3), tostring(err3))
  check("the pending proposal remains open until explicit resolution",
    require("core.hand_transaction").current() == tx, tostring(require("core.hand_transaction").current()))
end

do
  local hand = hand8(card("9", "Hearts"), card("9", "Diamonds"))
  setup(hand, function(cards)
    local text = (#cards == 2) and "Pair" or "High Card"
    return text, {}, { Straight = { { cards[1] } } }, cards
  end, { hands = 4, discards = 3 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  local msg = ActionResult.normalize(err).message
  check("stronger-ready wording refers to the whole current hand, not the proposed cards",
    msg:find("Your current hand also contains Ready Straight", 1, true) ~= nil
      and msg:find("These cards can also", 1, true) == nil,
    msg)
end

done()
