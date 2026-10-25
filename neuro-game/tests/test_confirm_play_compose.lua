require("tests.stubs").setup({ love = "lazy" })

local HandHandlers = require("handlers.hand_handlers")
local play_hand = require("tests.helpers").delivered(HandHandlers.handle_play_hand)
local ActionResult = require("core.action_result")
local PlanGate = require("core.gate")

local check, done = require("tests.helpers").harness("confirm-play-compose")

local card = require("tests.fake_cards").sorted_maker()
local function hand8(c7, c8) return require("tests.fake_cards").hand8(card, c7, c8) end

local function phi(text, poker_hands, scoring)
  return require("tests.engine_hand_info").stub(text, scoring or {}, poker_hands or {})
end

local function setup(cards, phi_fn, opts)
  opts = opts or {}
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = opts.discards or 3, hands_left = opts.hands or 4 },
             hands = require("tests.helpers").game_hands(), blind = {} },
    FUNCS = { get_poker_hand_info = phi_fn },
    NEURO = {},
    play = nil,
  }
end

do
  local STATES = require("tests.engine_cards").states()
  for _, sname in ipairs({ "SELECTING_HAND", "SHOP", "BLIND_SELECT" }) do
    _G.G = { STATES = STATES, STATE = STATES[sname], NEURO = {},
             GAME = { current_round = {} }, jokers = { cards = {} } }
    local rp = require("tests.helpers").review("play_hand")
    local rd = require("tests.helpers").review("discard_hand")
    check("A play_hand not gated by any window in " .. sname,   rp == nil, tostring(rp))
    check("A discard_hand not gated by any window in " .. sname, rd == nil, tostring(rd))
  end
  _G.G = { STATES = STATES, STATE = STATES.SHOP, NEURO = {},
           GAME = { current_round = {} }, jokers = { cards = {} } }
  local rbuy = require("tests.helpers").review("buy_from_shop")
  local required = PlanGate.action_requirements("SHOP", "buy_from_shop").plan
  check("A control: buy_from_shop carries inline plan requirements without a decision bounce",
    rbuy == nil and next(required) ~= nil, tostring(rbuy))
end

do
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", {}, {}), { hands = 1, discards = 0 })
  local res = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("forced_play (1 hand/0 disc/<=1 ready) commits on first send", type(res) == "function", type(res))
  check("no latch armed when confirm bypassed", G.NEURO.play_confirm == nil, tostring(G.NEURO.play_confirm))
end

do
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", { Pair = { 1 }, ["Two Pair"] = { 1 } }, {}), { hands = 1, discards = 0 })
  local res, err = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check(">=2 ready hands: confirm fires despite last hand/no discards",
    res == nil and ActionResult.is_error(err), tostring(err))
  check("transaction opened by the confirm", require("core.gate").proposal() ~= nil,
    tostring(require("core.gate").proposal()))
end

do
  local hand = hand8(card("7","Hearts"), card("4","Hearts"))
  setup(hand, phi("Flush", {}, {}), { hands = 2, discards = 0 })
  local res, err = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("hands_left>1: confirm fires (forced_play requires exactly 1 hand)",
    res == nil and ActionResult.is_error(err), tostring(err))
end

do
  local hand = hand8(card("9","Hearts"), card("9","Diamonds"))
  setup(hand, phi("Pair", {}, {}), { hands = 4, discards = 3 })
  local res1, err1 = play_hand({ indices = { 7, 8 } })
  check("first play with discards left pauses once", res1 == nil and ActionResult.is_error(err1), tostring(err1))
  local tx = require("core.gate").proposal()
  check("the delivered review opens a proposal awaiting its answer", tx ~= nil and tx.phase == "ready",
    tx and tostring(tx.phase) or "nil")
  local res2, err2 = play_hand({ indices = { 6, 7 } })
  check("strict resolution mode blocks a different selection until this proposal is resolved",
    res2 == nil and ActionResult.is_error(err2)
      and ActionResult.normalize(err2).reason_code == "POLICY_ACKNOWLEDGED", tostring(err2))
  local res3, err3 = play_hand({ indices = { 6, 7 } })
  check("resending that exact selection does not commit", res3 == nil and ActionResult.is_error(err3), tostring(err3))
  check("the pending proposal remains open until explicit resolution",
    require("core.gate").proposal() == tx, tostring(require("core.gate").proposal()))
end

do
  local hand = hand8(card("10", "Hearts"), card("10", "Diamonds"))
  setup(hand, require("tests.engine_hand_info").engine(), { hands = 4, discards = 3 })
  local _, err = play_hand({ indices = { 7, 8 } })
  local msg = require("tests.helpers").review_text(err)
  check("the better-Ready note names the hand's option with its positions, not the proposed cards",
    msg:find("1, 2, 3, 4, 7", 1, true) ~= nil, msg)
end

done()
