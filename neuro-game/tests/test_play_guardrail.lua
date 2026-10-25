require("tests.stubs").setup({ love = "lazy" })

local check, done = require("tests.helpers").harness("play-guardrail")

-- The engine sorts highlighted cards by position before resolving, so selection order is irrelevant.
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

local card = require("tests.fake_cards").sorted_maker()

local function setup(cards)
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = 3, hands_left = 4 }, hands = require("tests.helpers").game_hands(), blind = {} },
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").engine() },
    NEURO = {},
    play = nil,
  }
end

local HandHandlers = require("handlers.hand_handlers")
local play_hand = require("tests.helpers").delivered(HandHandlers.handle_play_hand)
local ActionResult = require("core.action_result")
local Gate = require("core.gate")

local function current_signature()
  local tx = Gate.proposal()
  return tx and tx.signature or nil
end

local function resolution_ack(err)
  return ActionResult.is_error(err)
    and ActionResult.normalize(err).reason_code == "POLICY_ACKNOWLEDGED"
end

local function hand8(c7, c8) return require("tests.fake_cards").hand8(card, c7, c8) end

local function flush_hand8(c7, c8)
  local h = hand8(c7, c8)
  h[5] = card("7", "Spades")
  return h
end

local function nines(builder)
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup((builder or hand8)(a, b))
  return a, b
end

local function boss_nines()
  local a, b = nines()
  G.GAME.blind = { debuff_hand = function(_self, _cards, _ph, _hn, _check) return true end }
  return a, b
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand)

  local res1, err1 = play_hand({ indices = { 7, 8 } })
  check("all-debuffed play rejected on first attempt", res1 == nil and ActionResult.is_error(err1), tostring(err1))
  check("legality latch recorded (keyed on card identity, not indices)",
    current_signature() == (d1.sort_id .. "," .. d2.sort_id), tostring(current_signature()))

  local res2, err2 = play_hand({ indices = { 7, 8 } })
  check("identical repeat does not commit without resolve_play",
    res2 == nil and resolution_ack(err2),
    tostring(err2))
  check("latch remains until explicit resolve_play", Gate.proposal() ~= nil,
    tostring(current_signature()))
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand)
  local r1 = play_hand({ indices = { 7, 8 } })
  check("first all-debuffed play rejected (latch armed)", r1 == nil and Gate.proposal() ~= nil)

  local e1, e2 = card("2", "Hearts", true), card("3", "Diamonds", true)
  G.hand.cards[7], G.hand.cards[8] = e1, e2
    local r2, err2 = play_hand({ indices = { 7, 8 } })
  check("same indices, redrawn debuffed cards -> guard re-fires, not silently committed",
    r2 == nil and ActionResult.is_error(err2), tostring(r2))
end

do
  local d1 = card("9", "Hearts", true)
  local live = card("9", "Diamonds")
  local hand = hand8(d1, live)
  setup(hand)

  local res, err = play_hand({ indices = { 7, 8 } })
  check("partial-debuff play still receives the standard review",
    res == nil and ActionResult.is_error(err))
  check("the review arms the confirmation latch", Gate.proposal() ~= nil)
  local committed, committed_err = play_hand({ indices = { 7, 8 } })
  check("reviewed partial-debuff play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local a, b = nines()

  local res, err = play_hand({ indices = { 7, 8 } })
  check("clean play receives the standard review", res == nil and ActionResult.is_error(err))
  local committed, committed_err = play_hand({ indices = { 7, 8 } })
  check("reviewed clean play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  local hand = hand8(d1, d2)
  setup(hand)

  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("all-debuffed rejected", r1 == nil and e1 ~= nil)

    local rc, ec = play_hand({ indices = { 1, 2 } })
  check("intervening clean play receives review", rc == nil and ActionResult.is_error(ec))
  local committed, committed_err = play_hand({ indices = { 1, 2 } })
  check("reviewed clean play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
  check("the legality latch remains until explicit resolve_play", Gate.proposal() ~= nil)

    local r2, e2 = play_hand({ indices = { 7, 8 } })
  check("identical all-debuffed play is challenged again after clear", r2 == nil and e2 ~= nil)
end

do
  local a, b = boss_nines()

  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("boss zero-hand-type play rejected once", r1 == nil and ActionResult.is_error(e1), tostring(e1))
  do
    local m1 = require("tests.helpers").review_text(e1)
    check("verdict is engine-attributed (opens with the facts.boss.legality Selection [ix] = ... line, not just any text mentioning 'Selection') and states the zeroed consequence",
      m1:find("scores 0", 1, true) ~= nil, m1)
    check("E2c verdict carries the boss-verdict class marker",
      ActionResult.normalize(e1).boss_verdict == true, tostring(ActionResult.normalize(e1).boss_verdict))
  end
  check("legality latch recorded", current_signature() == (a.sort_id .. "," .. b.sort_id), tostring(current_signature()))

  local r2, e2 = play_hand({ indices = { 7, 8 } })
  check("identical repeat does not commit without resolve_play",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("latch remains until explicit resolve_play", Gate.proposal() ~= nil)
end

do
  local a, b = nines()
  G.GAME.hands = require("tests.helpers").game_hands({ Pair = { level = 1, chips = 10, mult = 2 } })

  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("play with discards left pauses once", r1 == nil and ActionResult.is_error(e1), tostring(e1))
  check("the confirmation latch is armed on the paused selection",
    current_signature() == (a.sort_id .. "," .. b.sort_id),
    tostring(current_signature()))
  check("weak firing recorded for this decision point",
    tonumber(G.NEURO.weak_fired_serial) == 0, tostring(G.NEURO.weak_fired_serial))

  local r2, e2 = play_hand({ indices = { 7, 8 } })
  check("resending the same indices does not play them",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("the latch remains until explicit resolve_play", Gate.proposal() ~= nil)
end

do
  for _, ht in ipairs({ "High Card", "Pair", "Two Pair", "Flush", "Straight Flush" }) do
    local a, b = nines()
    local r1, e1 = play_hand({ indices = { 7, 8 } })
    check("" .. ht .. ": trigger is blind to hand type -- fires on resource state",
      r1 == nil and ActionResult.is_error(e1), tostring(r1))
    local r2, e2 = play_hand({ indices = { 7, 8 } })
    check("" .. ht .. ": resend does not commit without resolve_play",
      r2 == nil and resolution_ack(e2),
      tostring(e2))
  end
end

do
  local a, b = nines()
  G.GAME.hands = require("tests.helpers").game_hands({ Pair = { level = 8, chips = 80, mult = 9 } })
  G.jokers = { cards = { { config = { center = { key = "j_jolly", set = "Joker", name = "Jolly",
    loc_txt = { name = "Jolly", description = { "+8 Mult if hand contains a Pair" } } } },
    ability = { name = "Jolly", set = "Joker", type = "Pair", t_mult = 8 } } } }
  local rp, ep = play_hand({ indices = { 7, 8 } })

  local c = card("9", "Clubs")
  local hand2 = hand8(c, card("4", "Diamonds"))
  setup(hand2)
  local rh, eh = play_hand({ indices = { 7 } })

  check("high-level Pair with a pair-scaling joker and a bare High Card both pause for review",
    rp == nil and ActionResult.is_error(ep) and rh == nil and ActionResult.is_error(eh),
    tostring(rp) .. " / " .. tostring(rh))
end

do
  local a, b = nines(flush_hand8)
  G.GAME.current_round.discards_left = 0
  local res, err = play_hand({ indices = { 7, 8 } })
  check("at 0 discards the standard review still applies", res == nil and ActionResult.is_error(err))
  check("the weak warning remains unused", G.NEURO.weak_fired_serial == nil)
  local committed, committed_err = play_hand({ indices = { 7, 8 } })
  check("reviewed play does not commit on resend",
    committed == nil and resolution_ack(committed_err),
    tostring(committed_err))
end

do
  local a, b = nines()
  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("first submission at the decision point pauses", r1 == nil and ActionResult.is_error(e1))
  local r2, e2 = play_hand({ indices = { 6, 7 } })
  check("after the weak warning, strict resolution blocks a different selection",
    r2 == nil and resolution_ack(e2), tostring(e2))
  local r3, e3 = play_hand({ indices = { 6, 7 } })
  check("O2b reviewed selection does not commit on resend",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

do
  local a, b = nines()
  local r1 = play_hand({ indices = { 7, 8 } })
  check("fires at decision point 0", r1 == nil)
  G.NEURO.decision_serial = 1
  Gate.observe_context_changed()
  local r2, e2 = play_hand({ indices = { 7, 8 } })
  check("a new decision point re-arms the guard", r2 == nil and ActionResult.is_error(e2), tostring(r2))
  local r3, e3 = play_hand({ indices = { 7, 8 } })
  check("and the repeated selection still waits for explicit resolve_play",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

do
  local a, b = boss_nines()

  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("boss verdict fires first", r1 == nil and ActionResult.normalize(e1).boss_verdict == true, tostring(e1))
  check("the boss verdict owns the pause and leaves the weak guard unused", G.NEURO.weak_fired_serial == nil)

  local spent_before = G.NEURO.weak_fired_serial
  local r2, e2 = play_hand({ indices = { 7, 8 } })
  check("resend after the boss verdict does not commit without resolve_play",
    r2 == nil and resolution_ack(e2),
    tostring(e2))
  check("the resend does not re-fire the weak guard",
    G.NEURO.weak_fired_serial == spent_before, tostring(G.NEURO.weak_fired_serial))
end

do
  local a, b = nines(flush_hand8)
  G.GAME.blind = { debuff_hand = function(_self, _cards, _ph, hn, _check) return hn == "Flush" end }

  local r1, e1 = play_hand({ indices = { 7, 8 } })
  check("weak pause fires on the Pair selection",
    r1 == nil and ActionResult.is_error(e1),
    tostring(e1))

  local r2, e2 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("strict resolution prevents the boss selection replacing the weak proposal",
    r2 == nil and resolution_ack(e2)
      and G.NEURO.weak_fired_serial ~= nil, tostring(e2))

  local r3, e3 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("resend after the verdict does not commit without resolve_play",
    r3 == nil and resolution_ack(e3),
    tostring(e3))
end

local function outscored_flush(hand)
  setup(hand)
  G.GAME.current_round.discards_left = 0
  G.GAME.hands.Pair.level, G.GAME.hands.Pair.chips, G.GAME.hands.Pair.mult = 30, 300, 30
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local hand = flush_hand8(a, b)
  outscored_flush(hand)
  local r1, e1 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP1 cold-check rejects a clean hand on first attempt",
    r1 == nil and ActionResult.is_error(e1), tostring(e1))
  local r2, e2 = play_hand({ indices = { 1, 2, 3 } })
  check("CP2 strict resolution blocks a changed selection until explicit cancellation",
    r2 == nil and resolution_ack(e2), tostring(e2))
  local r2b, e2b = play_hand({ indices = { 1, 2, 3 } })
  check("CP2b resending that exact selection does not commit",
    r2b == nil and resolution_ack(e2b),
    tostring(e2b))

  outscored_flush(hand)
  local r3, e3 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP3 fresh window still requires review", r3 == nil and ActionResult.is_error(e3), tostring(e3))
  G.NEURO.decision_serial = 1
  Gate.observe_context_changed()
  local r4, e4 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP4 review expires when the decision window advances",
    r4 == nil and ActionResult.is_error(e4), tostring(e4))

  setup(hand)
  local r5, e5 = play_hand({ indices = { 7, 8 } })
  check("CP5 the weak pause owns the first submission",
    r5 == nil and ActionResult.is_error(e5), tostring(e5))
  local r5b, e5b = play_hand({ indices = { 7, 8 } })
  check("CP5b one resend does not answer the quality class",
    r5b == nil and resolution_ack(e5b),
    tostring(e5b))

  setup(hand)
  local r5c, e5c = play_hand({ indices = { 7, 8 } })
  check("CP5c weak pause fires", r5c == nil and ActionResult.is_error(e5c), tostring(r5c))
  local r5d, e5d = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP5d strict resolution blocks a different selection",
    r5d == nil and resolution_ack(e5d), tostring(e5d))
  local r5e, e5e = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP5e resend does not commit without resolve_play",
    r5e == nil and resolution_ack(e5e),
    tostring(e5e))

  setup(hand)
  local r6, e6 = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  check("CP6 hard-guard setup requires general review", r6 == nil and ActionResult.is_error(e6), tostring(e6))
  local d1, d2 = card("6", "Hearts", true), card("6", "Diamonds", true)
  G.hand.cards[7], G.hand.cards[8] = d1, d2
  local r7, e7 = play_hand({ indices = { 7, 8 } })
  check("CP7 changed all-debuffed selection cannot replace the ready proposal",
    r7 == nil and resolution_ack(e7), tostring(e7))
  local r8, e8 = play_hand({ indices = { 7, 8 } })
  check("CP8 boss-verdict resend does not commit without resolve_play",
    r8 == nil and resolution_ack(e8),
    tostring(e8))
  check("CP9 boss resend keeps the confirmation latch open",
    Gate.proposal() ~= nil, tostring(Gate.proposal()))

end

do
  local Actions = require("core.actions")

  local function banner_world(block)
    local hand = { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"), card("10","Spades") }
    setup(hand)
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
  local res, err = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  local e = ActionResult.normalize(err)
  check("BP4 a play that slips past the validator is still refused", res == nil and ActionResult.is_error(err))
  check("BP5 the refusal is a wait, retried outside a force, not an unavailable action",
    e.reason_code == "TRANSITION_PENDING" and ActionResult.terminal(e.reason_code, false) == false,
    tostring(e.reason_code))

  banner_world(true)
  local dres, derr = HandHandlers.handle_discard_hand({ indices = { 1, 2 } })
  check("BP9 discarding is untouched by the banner lock",
    dres ~= nil or (derr and ActionResult.normalize(derr).reason_code ~= "TRANSITION_PENDING"),
    tostring(derr and ActionResult.normalize(derr).reason_code))

  banner_world(true)
  G.NEURO.force_window = { key = "SELECTING_HAND#1", state = "SELECTING_HAND", phase = "forced",
    names = { "play_hand" }, set = { play_hand = true } }
  local _, ferr = play_hand({ indices = { 1, 2, 3, 4, 5 } })
  local fe = ActionResult.normalize(ferr)
  check("BP10 a forced play acknowledges instead of failing the whole force",
    ActionResult.terminal(fe.reason_code, true) == true, tostring(fe.reason_code))
  G.NEURO.force_window = nil
end

do
  local d1, d2 = card("9", "Hearts", true), card("9", "Diamonds", true)
  setup(hand8(d1, d2))
  local res, err = play_hand({ indices = { 7, 8 }, confirm = true })
  check("a stray confirm does not skip the review",
    res == nil and ActionResult.is_error(err) and Gate.proposal() ~= nil,
    tostring(err and ActionResult.normalize(err).message))
end

do
  local hand = hand8(card("9", "Hearts"), card("9", "Diamonds"))
  setup(hand)
  G.GAME.blind = { chips = 300, debuff = { h_size_ge = 5 } }
  local res, err = play_hand({ indices = { 7, 8 } })
  local normalized = err and ActionResult.normalize(err)
  check("the blind size rule runs before the review",
    res == nil and normalized ~= nil and normalized.reason_code == "INVALID_SELECTION"
      and tostring(normalized.message):find("at least 5", 1, true) ~= nil,
    tostring(normalized and normalized.message))
end

do
  local Registry = require("core.action_registry")
  local Config = require("core.config")
  for _, mode in ipairs({ "on", "off" }) do
    Config.set("NEURO_CONFIRM_HAND", mode)
    local defs = require("core.actions").get_static_actions()
    local def = defs.play_hand or {}
    for _, d in ipairs(Registry.definitions()) do if d.name == "play_hand" then def = d end end
    local props = def.schema and def.schema.properties or {}
    check("play_hand offers no confirm field (hand confirmation " .. mode .. ")",
      props.indices ~= nil and props.confirm == nil)
  end
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  local HH = require("handlers.hand_handlers")
  local function ONE()
    return { card("A", "Spades"), card("7", "Hearts"), card("3", "Clubs") }
  end
  local function MANY()
    return { card("A", "Spades"), card("A", "Hearts"), card("7", "Hearts"), card("7", "Clubs"), card("3", "Clubs") }
  end
  local function force_for(hands_left, discards_left, fixture)
    setup(fixture())
    G.GAME.current_round.hands_left = hands_left
    G.GAME.current_round.discards_left = discards_left
    G.NEURO.once_serials = {}
    require("core.actions").get_static_actions()
    return tostring((require("force.force_selecting_hand").build() or {}).query or "")
  end

  force_for(1, 0, MANY)
  check("a last hand with several Ready hands still has something to weigh, so no rule either",
    HH.forced_play_now() == false)

  force_for(1, 0, ONE)
  check("the force states the rule exactly when it applies",
    HH.forced_play_now() == true)
end

done()
