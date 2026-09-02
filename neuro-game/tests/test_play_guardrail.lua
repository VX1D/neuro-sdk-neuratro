_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("play-guardrail")

-- The engine sorts G.hand.highlighted by position before resolving (state_events.lua:479), so the play signature must ignore selection order.
do
  local HH = require("handlers.hand_handlers")
  local a, b, c = { sort_id = 7 }, { sort_id = 3 }, { sort_id = 11 }
  local s1 = HH.play_signature({ a, b, c })
  local s2 = HH.play_signature({ c, a, b })
  local s3 = HH.play_signature({ b, c, a })
  check("play signature ignores selection order", s1 == s2 and s2 == s3, s1 .. " / " .. s2 .. " / " .. s3)
  local diff = HH.play_signature({ a, b })
  check("play signature still separates different card sets", diff ~= s1, diff .. " vs " .. s1)
  local missing = HH.play_signature({ a, { } })
  check("play signature tolerates a card with no sort_id", type(missing) == "string" and missing ~= "", tostring(missing))
end

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

local function phi_for(scoring, text)
  text = text or "Flush"
  return function() return text, {}, {}, scoring end
end

local function setup(cards, scoring, text)
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = 3, hands_left = 4 }, hands = {}, blind = {} },
    FUNCS = { get_poker_hand_info = phi_for(scoring, text) },
    NEURO = {},
    play = nil,
  }
end

local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")
local HandTx = require("core.hand_transaction")

local function current_signature()
  local tx = HandTx.current()
  return tx and tx.signature or nil
end

local function resolution_ack(err)
  return ActionResult.is_error(err)
    and ActionResult.normalize(err).reason_code == "POLICY_ACKNOWLEDGED"
end

local function hand8(c7, c8)
  return { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"),
           card("7","Clubs"), card("4","Clubs"), c7, c8 }
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand, { d1, d2 })

  local res1, err1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("all-debuffed play rejected on first attempt", res1 == nil and ActionResult.is_error(err1), tostring(err1))
  local err1_message = ActionResult.normalize(err1).message
  check("rejection explains the zero-score", err1_message:find("debuffed") ~= nil and err1_message:find("base hand value") ~= nil, err1_message)
  check("legality latch recorded (keyed on card identity, not indices)",
    current_signature() == (d1.sort_id .. "," .. d2.sort_id), tostring(current_signature()))

  local res2, err2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("identical repeat does not commit without resolve_play",
    res2 == nil and resolution_ack(err2),
    tostring(err2))
  check("latch remains until explicit resolve_play", HandTx.current() ~= nil,
    tostring(current_signature()))
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand, { d1, d2 })
  local r1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("first all-debuffed play rejected (latch armed)", r1 == nil and HandTx.current() ~= nil)

  local e1, e2 = card("2", "Hearts", true), card("3", "Diamonds", true)
  G.hand.cards[7], G.hand.cards[8] = e1, e2
  G.FUNCS.get_poker_hand_info = phi_for({ e1, e2 })
  local r2, err2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("same indices, redrawn debuffed cards -> guard re-fires, not silently committed",
    r2 == nil and ActionResult.is_error(err2), tostring(r2))
end

do
  local d1 = card("9", "Hearts", true)
  local live = card("9", "Diamonds")
  local hand = hand8(d1, live)
  setup(hand, { d1, live })

  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("partial-debuff play still receives the standard review",
    res == nil and ActionResult.is_error(err))
  check("the review arms the confirmation latch", HandTx.current() ~= nil)
  local committed, committed_err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("reviewed partial-debuff play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b })

  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("clean play receives the standard review", res == nil and ActionResult.is_error(err))
  local committed, committed_err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("reviewed clean play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand, { d1, d2 })

  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("all-debuffed rejected", r1 == nil and e1 ~= nil)

  G.FUNCS.get_poker_hand_info = phi_for({ hand[1], hand[2] })
  local rc, ec = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("intervening clean play receives review", rc == nil and ActionResult.is_error(ec))
  local committed, committed_err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("reviewed clean play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
  check("the legality latch remains until explicit resolve_play", HandTx.current() ~= nil)

  G.FUNCS.get_poker_hand_info = phi_for({ d1, d2 })
  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("identical all-debuffed play is challenged again after clear", r2 == nil and e2 ~= nil)
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b })
  G.GAME.blind = { debuff_hand = function(_self, _cards, _ph, _hn, _check) return true end }

  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("boss zero-hand-type play rejected once", r1 == nil and ActionResult.is_error(e1), tostring(e1))
  do
    local m1 = ActionResult.normalize(e1).message
    check("verdict is engine-attributed (opens with the facts.boss.legality Selection [ix] = ... line, not just any text mentioning 'Selection') and states the zeroed consequence",
      m1:match("^Selection %[") ~= nil and m1:find("scores 0", 1, true) ~= nil
        and m1:find("Call resolve_play with", 1, true) ~= nil, m1)
    check("E2b verdict names no alternative action",
      m1:find("Choose one action now", 1, true) == nil and m1:find("Discard toward one first", 1, true) == nil, m1)
    check("E2c verdict carries the boss-verdict class marker",
      ActionResult.normalize(e1).boss_verdict == true, tostring(ActionResult.normalize(e1).boss_verdict))
  end
  check("legality latch recorded", current_signature() == (a.sort_id .. "," .. b.sort_id), tostring(current_signature()))

  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("identical repeat does not commit without resolve_play",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("latch remains until explicit resolve_play", HandTx.current() ~= nil)
end

do
  local HH = HandHandlers
  local with_discards = "Answer \"yes\" to commit these exact cards. Answer \"no\" only with a concrete next move; no plays nothing, discards nothing, and draws nothing. After no, use discard_hand to redraw or play_hand for a specific Ready alternative; that next play commits immediately. For yes, omit reason. For no, optional reason should name the next action and exact indices."
  local golden = {
    { args = { { 3, 5 }, "Pair", 8, 80, 9, 2, 3 },
      text = "Selection [3,5] = Pair (lvl 8, 80 chips x 9 mult).\n"
        .. "Bare Pair is one of the three lowest-ranking hand types. Discards are a separate pool that costs no hand-slot. Available discards: 3. Check the one-card-away odds for a concrete upgrade before declining to redraw. Review required: call resolve_play with its transaction_id. " .. with_discards },
    { args = { { 1 }, "High Card", 1, 5, 1, 4, 1 },
      text = "Selection [1] = High Card (lvl 1, 5 chips x 1 mult).\n"
        .. "Bare High Card is one of the three lowest-ranking hand types. Discards are a separate pool that costs no hand-slot. Available discards: 1. Check the one-card-away odds for a concrete upgrade before declining to redraw. Review required: call resolve_play with its transaction_id. " .. with_discards },
    { args = { { 1, 2, 3, 4, 5 }, "Flush", 2, 50, 6, 1, 2 },
      text = "Selection [1,2,3,4,5] = Flush (lvl 2, 50 chips x 6 mult).\n"
        .. "Playing spends 1 of 1 hands; discarding spends 1 of 2 discards.\n"
        .. "Review required: call resolve_play with its transaction_id. " .. with_discards },
    { args = { { 7, 8 }, "Pair", nil, nil, nil, 4, 3 },
      text = "Selection [7,8] = Pair.\n"
        .. "Bare Pair is one of the three lowest-ranking hand types. Discards are a separate pool that costs no hand-slot. Available discards: 3. Check the one-card-away odds for a concrete upgrade before declining to redraw. Review required: call resolve_play with its transaction_id. " .. with_discards },
    { args = { { 3, 5, 6, 7 }, "Two Pair", 3, 40, 4, 2, 2 },
      text = "Selection [3,5,6,7] = Two Pair (lvl 3, 40 chips x 4 mult).\n"
        .. "Bare Two Pair is one of the three lowest-ranking hand types. Discards are a separate pool that costs no hand-slot. Available discards: 2. Check the one-card-away odds for a concrete upgrade before declining to redraw. Review required: call resolve_play with its transaction_id. " .. with_discards },
  }
  for i, g in ipairs(golden) do
    local got = HH.weak_pause_text(g.args[1], g.args[2], g.args[3], g.args[4], g.args[5], g.args[6], g.args[7])
    check("W-GOLD" .. i .. " weak_pause_text is exactly the golden string", got == g.text, got)
  end
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  G.GAME.hands = { Pair = { level = 8, chips = 80, mult = 9 } }

  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("play with discards left pauses once", r1 == nil and ActionResult.is_error(e1), tostring(e1))
  local msg = ActionResult.normalize(e1).message
  local expected = "Selection [7,8] = Pair (lvl 8, 80 chips x 9 mult).\n"
    .. "Bare Pair is one of the three lowest-ranking hand types. Discards are a separate pool that costs no hand-slot. Available discards: 3. Check the one-card-away odds for a concrete upgrade before declining to redraw. Review required: call resolve_play with its transaction_id. Answer \"yes\" to commit these exact cards. Answer \"no\" only with a concrete next move; no plays nothing, discards nothing, and draws nothing. After no, use discard_hand to redraw or play_hand for a specific Ready alternative; that next play commits immediately. For yes, omit reason. For no, optional reason should name the next action and exact indices."
  check("handler message preserves the 1.1.0 weak-guard precedence", msg == expected, msg)
  check("the confirmation latch is armed on the paused selection",
    current_signature() == (a.sort_id .. "," .. b.sort_id),
    tostring(current_signature()))
  check("weak firing recorded for this decision point",
    tonumber(G.NEURO.weak_fired_serial) == 0, tostring(G.NEURO.weak_fired_serial))

  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("resending the same indices does not play them",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("the latch remains until explicit resolve_play", HandTx.current() ~= nil)
end

do
  for _, ht in ipairs({ "High Card", "Pair", "Two Pair", "Flush", "Straight Flush" }) do
    local a, b = card("9", "Hearts"), card("9", "Diamonds")
    local hand = hand8(a, b)
    setup(hand, { a, b }, ht)
    local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
    check("" .. ht .. ": trigger is blind to hand type -- fires on resource state",
      r1 == nil and ActionResult.is_error(e1), tostring(r1))
    local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
    check("" .. ht .. ": resend does not commit without resolve_play",
      r2 == nil and resolution_ack(e2),
      tostring(e2))
  end
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  G.GAME.hands = { Pair = { level = 8, chips = 80, mult = 9 } }
  G.jokers = { cards = { { config = { center = { key = "j_jolly", set = "Joker", name = "Jolly",
    loc_txt = { name = "Jolly", description = { "+8 Mult if hand contains a Pair" } } } },
    ability = { name = "Jolly", set = "Joker", type = "Pair", t_mult = 8 } } } }
  local rp, ep = HandHandlers.handle_play_hand({ indices = { 7, 8 } })

  local c = card("9", "Clubs")
  local hand2 = hand8(c, card("4", "Diamonds"))
  setup(hand2, { c }, "High Card")
  local rh, eh = HandHandlers.handle_play_hand({ indices = { 7 } })

  check("high-level Pair with a pair-scaling joker and a bare High Card behave identically",
    rp == nil and ActionResult.is_error(ep) and rh == nil and ActionResult.is_error(eh),
    tostring(rp) .. " / " .. tostring(rh))
  local mp = ActionResult.normalize(ep).message
  local mh = ActionResult.normalize(eh).message
  check("both messages share the bare-hand framing and explicit yes/no mandate",
    mp:find("one of the three lowest-ranking hand types.", 1, true) ~= nil
      and mh:find("one of the three lowest-ranking hand types.", 1, true) ~= nil
      and mp:find("Review required", 1, true) ~= nil
      and mh:find("Review required", 1, true) ~= nil,
    mp .. " || " .. mh)
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  G.GAME.current_round.discards_left = 0
  local res, err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("at 0 discards the standard review still applies", res == nil and ActionResult.is_error(err))
  check("the weak warning remains unused", G.NEURO.weak_fired_serial == nil)
  local committed, committed_err = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("reviewed play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("first submission at the decision point pauses", r1 == nil and ActionResult.is_error(e1))
  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 6, 7 } })
  check("after the weak warning, strict resolution blocks a different selection",
    r2 == nil and resolution_ack(e2), tostring(e2))
  local r3, e3 = HandHandlers.handle_play_hand({ indices = { 6, 7 } })
  check("O2b reviewed selection does not commit on resend",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  local r1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("fires at decision point 0", r1 == nil)
  G.NEURO.decision_serial = 1
  HandTx.observe_context_changed()
  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("a new decision point re-arms the guard", r2 == nil and ActionResult.is_error(e2), tostring(r2))
  local r3, e3 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("and the repeated selection still waits for explicit resolve_play",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  G.GAME.blind = { debuff_hand = function(_self, _cards, _ph, _hn, _check) return true end }

  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("boss verdict fires first", r1 == nil and ActionResult.normalize(e1).boss_verdict == true, tostring(e1))
  check("the boss verdict owns the pause and leaves the weak guard unused", G.NEURO.weak_fired_serial == nil)

  local spent_before = G.NEURO.weak_fired_serial
  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("resend after the boss verdict does not commit without resolve_play",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("the resend does not re-fire the weak guard",
    G.NEURO.weak_fired_serial == spent_before, tostring(G.NEURO.weak_fired_serial))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { a, b }, "Pair")
  G.FUNCS.get_poker_hand_info = function(cards)
    local text = #cards == 2 and "Pair" or "Flush"
    return text, {}, {}, cards
  end
  G.GAME.blind = { debuff_hand = function(_self, _cards, _ph, hn, _check) return hn == "Flush" end }

  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("weak pause fires on the Pair selection",
    r1 == nil and ActionResult.normalize(e1).message:find("one of the three lowest-ranking hand types", 1, true) ~= nil,
    tostring(e1))

  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("strict resolution prevents the boss selection replacing the weak proposal",
    r2 == nil and resolution_ack(e2)
      and G.NEURO.weak_fired_serial ~= nil, tostring(e2))

  local r3, e3 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("resend after the verdict does not commit without resolve_play",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = hand8(a, b)
  setup(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] }, "Flush")
  G.GAME.current_round.discards_left = 0
  local r1, e1 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  local cp_msg = ActionResult.normalize(e1).message
  check("CP1 cold-check rejects a clean hand on first attempt",
    r1 == nil and ActionResult.is_error(e1)
      and cp_msg:find("Call resolve_play with", 1, true) ~= nil, tostring(e1))
  check("CP1b confirm names the committed hand and a resource fact (agnostic)",
    cp_msg:find("Committing Flush", 1, true) ~= nil and cp_msg:find("discard(s) left", 1, true) ~= nil, cp_msg)
  check("CP1c confirm text gives the explicit confirmation action, not a re-review",
    cp_msg:find("Call resolve_play with", 1, true) ~= nil
      and cp_msg:find("Review this choice", 1, true) == nil
      and cp_msg:find("commits without another", 1, true) == nil, cp_msg)
  local r2, e2 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3 } })
  check("CP2 strict resolution blocks a changed selection until explicit cancellation",
    r2 == nil and resolution_ack(e2), tostring(e2))
  local r2b, e2b = HandHandlers.handle_play_hand({ indices = { 1, 2, 3 } })
  check("CP2b resending that exact selection does not commit",
    r2b == nil and resolution_ack(e2b),
    tostring(e2b))

  setup(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] }, "Flush")
  G.GAME.current_round.discards_left = 0
  local r3, e3 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP3 fresh window still requires review", r3 == nil and ActionResult.is_error(e3), tostring(e3))
  G.NEURO.decision_serial = 1
  HandTx.observe_context_changed()
  local r4, e4 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP4 review expires when the decision window advances",
    r4 == nil and ActionResult.is_error(e4)
      and ActionResult.normalize(e4).message:find("Committing Flush", 1, true) ~= nil, tostring(e4))

  setup(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] }, "Flush")
  G.FUNCS.get_poker_hand_info = function(cards)
    local text = #cards == 2 and "Pair" or "Flush"
    return text, {}, {}, cards
  end
  local r5, e5 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("CP5 the weak pause owns the first submission",
    r5 == nil and ActionResult.is_error(e5)
      and ActionResult.normalize(e5).message:find("one of the three lowest-ranking hand types", 1, true) ~= nil
      and ActionResult.normalize(e5).message:find("Committing", 1, true) == nil
      and ActionResult.normalize(e5).message:find("Answer \"yes\"", 1, true) ~= nil, tostring(e5))
  local r5b, e5b = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("CP5b one resend does not answer the quality class",
    r5b == nil and resolution_ack(e5b),
    tostring(e5b))

  setup(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] }, "Flush")
  G.FUNCS.get_poker_hand_info = function(cards)
    local text = #cards == 2 and "Pair" or "Flush"
    return text, {}, {}, cards
  end
  local r5c, e5c = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("CP5c weak pause fires", r5c == nil and ActionResult.is_error(e5c), tostring(r5c))
  local r5d, e5d = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP5d strict resolution blocks a different selection",
    r5d == nil and resolution_ack(e5d), tostring(e5d))
  local r5e, e5e = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP5e resend does not commit without resolve_play",
    r5e == nil and resolution_ack(e5e),
    tostring(e5e))

  setup(hand, { hand[1], hand[2], hand[3], hand[4], hand[5] }, "Flush")
  local r6, e6 = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP6 hard-guard setup requires general review", r6 == nil and ActionResult.is_error(e6), tostring(e6))
  local d1, d2 = card("6", "Hearts", true), card("6", "Diamonds", true)
  G.hand.cards[7], G.hand.cards[8] = d1, d2
  G.FUNCS.get_poker_hand_info = function(cards)
    local text = #cards == 2 and "Pair" or "Flush"
    return text, {}, {}, cards
  end
  local r7, e7 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("CP7 changed all-debuffed selection cannot replace the ready proposal",
    r7 == nil and resolution_ack(e7), tostring(e7))
  local r8, e8 = HandHandlers.handle_play_hand({ indices = { 7, 8 } })
  check("CP8 boss-verdict resend does not commit without resolve_play",
    r8 == nil and resolution_ack(e8),
    tostring(e8))
  check("CP9 boss resend keeps the confirmation latch open",
    HandTx.current() ~= nil, tostring(HandTx.current()))

end

do
  local Actions = require("core.actions")

  local function banner_world(block)
    local hand = { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"), card("10","Spades") }
    setup(hand, hand, "Straight Flush")
    G.GAME.blind = { name = "The Wall", boss = true, block_play = block or nil }
    return hand
  end

  banner_world(true)
  check("BP1 play_hand is not offered while the boss banner is still animating",
    Actions.is_action_valid("play_hand") == false)
  check("BP2 discard_hand stays offered -- the banner lock only blocks playing",
    Actions.is_action_valid("discard_hand") == true)

  banner_world(false)
  check("BP3 play_hand returns the moment the banner lock clears",
    Actions.is_action_valid("play_hand") == true)

  banner_world(true)
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  local e = ActionResult.normalize(err)
  check("BP4 a play that slips past the validator is still refused", res == nil and ActionResult.is_error(err))
  check("BP5 the refusal is classed transient, not as an unavailable action",
    e.reason_code == "TRANSITION_PENDING" and e.transient == true,
    tostring(e.reason_code) .. "/" .. tostring(e.transient))
  check("BP6 the refusal never claims the blind blocks playing hands",
    e.message:lower():find("blocks playing", 1, true) == nil, e.message)
  check("BP7 the refusal reuses the existing busy vocabulary",
    e.message:find("still resolving on screen", 1, true) ~= nil
      and e.message:find("Wait a moment, then choose again", 1, true) ~= nil, e.message)
  check("BP8 the refusal says nothing was applied", e.message:find("nothing was applied", 1, true) ~= nil, e.message)

  banner_world(true)
  local dres, derr = HandHandlers.handle_discard_hand({ indices = { 1, 2 } })
  check("BP9 discarding is untouched by the banner lock",
    dres ~= nil or (derr and ActionResult.normalize(derr).message:find("still resolving on screen", 1, true) == nil),
    tostring(derr and ActionResult.normalize(derr).message))

  banner_world(true)
  G.NEURO.force_window = { key = "SELECTING_HAND#1", state = "SELECTING_HAND", phase = "forced",
    names = { "play_hand" }, set = { play_hand = true } }
  local _, ferr = HandHandlers.handle_play_hand({ indices = { 1, 2, 3, 4, 5 } })
  local fe = ActionResult.normalize(ferr)
  check("BP10 a forced play acknowledges instead of failing the whole force",
    fe.reason_code == "TRANSITION_ACKNOWLEDGED", tostring(fe.reason_code))
  G.NEURO.force_window = nil
end

done()
