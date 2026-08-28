_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("confirm-play-tool")

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
local function phi(text) return function(sel) return text, {}, {}, sel end end
local function phi_ready(text, ready_name)
  return function(sel) return text, {}, { [ready_name] = { true } }, sel end
end

local function setup(cards, phi_fn, opts)
  opts = opts or {}
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
    GAME = { current_round = { discards_left = opts.discards or 3, hands_left = opts.hands or 4 },
             hands = {}, blind = {} },
    FUNCS = { get_poker_hand_info = phi_fn },
    NEURO = { decision_serial = 1, run_generation = 0 },
    play = nil,
  }
end

local HandHandlers = require("handlers.hand_handlers")
local ConfirmationEvidence = require("core.confirmation_evidence")
local ActionResult = require("core.action_result")
local Actions = require("core.actions")

-- Every block except the dedicated always-reason one exercises dominant-alt-only behavior, so pin
-- the flag off rather than depend on its default.
require("core.config").set("NEURO_CONFIRM_REASON_ALWAYS", "off")

local function promote(sig, content, indices, hand_type, text)
  local candidate = assert(ConfirmationEvidence.candidate(sig, content, indices, hand_type))
  local receipt = { status = "written" }
  assert(ConfirmationEvidence.stage(candidate, text, receipt))
  assert(ConfirmationEvidence.step_delivery())
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  check("confirm_play unavailable with nothing pending",
    Actions.is_action_valid("confirm_play") == false)

  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("play_hand opens a confirmation", res == nil and ActionResult.is_error(err))
  check("confirm_play still unavailable: the candidate is armed but not yet delivery-proven",
    Actions.is_action_valid("confirm_play") == false)

  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)
  check("confirm_play becomes available once the confirmation is promoted",
    Actions.is_action_valid("confirm_play") == true)
end

do
  local played = false
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  G.FUNCS.play_cards_from_highlighted = function() played = true end
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local exec = HandHandlers.handle_confirm_play({ answer = "yes" })
  check("confirm_play yes returns an executor", type(exec) == "function", type(exec))
  exec()
  check("yes actually plays the confirmed cards", played == true)
  check("yes clears both the synchronous slot and the evidence record",
    G.NEURO.play_confirm == nil and ConfirmationEvidence.current() == nil)
end

do
  local played = false
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  G.FUNCS.play_cards_from_highlighted = function() played = true end
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local exec = HandHandlers.handle_confirm_play({ answer = "no" })
  check("confirm_play no returns an executor", type(exec) == "function", type(exec))
  local msg = exec()
  check("no returns a proper applied outcome, not a bare string",
    type(msg) == "table" and msg.__action_outcome == true and msg.status == "applied", tostring(msg))
  check("no discards the confirmation without playing anything",
    played == false and type(msg) == "table" and type(msg.message) == "string"
      and msg.message:find("discarded", 1, true) ~= nil, tostring(msg))
  check("no clears both the synchronous slot and the evidence record",
    G.NEURO.play_confirm == nil and ConfirmationEvidence.current() == nil)
end

do
  local a, b, c = card("9", "Hearts"), card("9", "Diamonds"), card("4", "Clubs")
  setup({ a, b, c }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  table.remove(G.hand.cards, 1)
  local reject = HandHandlers.handle_confirm_play({ answer = "yes" })
  check("yes on a confirmation whose card left the hand is refused, not silently committed",
    reject == nil, tostring(reject))
  check("the stale confirmation is torn down rather than left dangling",
    G.NEURO.play_confirm == nil and ConfirmationEvidence.current() == nil)
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  a.base.value, a.base.suit = "King", "Clubs"
  local reject = HandHandlers.handle_confirm_play({ answer = "yes" })
  check("yes on a confirmation whose card mutated in place under a stable sort_id is refused",
    reject == nil, tostring(reject))
end

do
  local a, b, c, d = card("9", "Hearts"), card("9", "Diamonds"), card("4", "Clubs"), card("5", "Clubs")
  setup({ a, b, c, d }, phi("Pair"), { hands = 1 })
  local played_indices
  G.FUNCS.play_cards_from_highlighted = function()
    played_indices = {}
    for _, h in ipairs(G.hand.highlighted or {}) do played_indices[#played_indices + 1] = h end
  end

  local resA, errA = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("selection A opens a confirmation", resA == nil and ActionResult.is_error(errA))
  local sigA, contentA = HandHandlers.play_signature({ a, b }), HandHandlers.play_content({ a, b })
  promote(sigA, contentA, { 1, 2 }, "Pair", ActionResult.normalize(errA).message)
  check("A's confirmation is promoted and delivery-proven",
    ConfirmationEvidence.current() ~= nil)

  local resB, errB = HandHandlers.handle_play_hand({ indices = { 3, 4 } })
  check("switching to selection B re-arms the synchronous slot for B, not A",
    resB == nil and ActionResult.is_error(errB)
      and G.NEURO.play_confirm.signature == HandHandlers.play_signature({ c, d }))
  check("A's stale promoted record is still sitting in ConfirmationEvidence (unstaged B has not promoted yet)",
    ConfirmationEvidence.current() ~= nil
      and ConfirmationEvidence.current().signature == sigA)

  local exec = HandHandlers.handle_confirm_play({ answer = "yes" })
  check("confirm_play refuses rather than committing A while B is the one actually pending",
    exec == nil, tostring(exec))
  check("nothing was played off the stale record", played_indices == nil)
end

do
  local PlanTransaction = require("core.plan_transaction")
  local PlanGate = require("core.plan_gate")
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  G.GAME.blind = { boss = true, name = "Test Boss" }
  G.GAME.round_resets = { ante = 1 }
  G.NEURO.plan = nil

  local tx1 = PlanTransaction.prepare("play_hand", { indices = { 1, 2 },
    plan = { boss_plan = "the held boss plan text" } })
  check("P16: play_hand accepts the inline boss_plan on the confirming send",
    tx1 ~= nil and tx1.plan_values.boss_plan == "the held boss plan text")
  PlanTransaction.hold(tx1)
  check("P16: the boss_plan is held after the send is rejected as a confirmation",
    G.NEURO.held_plan_write ~= nil
      and G.NEURO.held_plan_write.values.boss_plan == "the held boss plan text")

  local tx2 = PlanTransaction.prepare("confirm_play", { answer = "yes" })
  check("P16: confirm_play resumes the held boss_plan with no plan field of its own",
    tx2 ~= nil and tx2.plan_values.boss_plan == "the held boss plan text"
      and type(tx2.plan_commit) == "function")
  tx2.plan_commit()
  PlanGate.complete_requirements(tx2.requirements, tx2.token.shop_visit_epoch)
  check("P16: committing through confirm_play actually writes the plan",
    G.NEURO.plan ~= nil and G.NEURO.plan.boss == "the held boss plan text")
end

local function confirm_play_def()
  for _, def in ipairs(Actions.get_static_actions()) do
    if def.name == "confirm_play" then return def end
  end
end

do
  local a, b, c = card("9", "Hearts"), card("9", "Diamonds"), card("4", "Clubs")
  setup({ a, b, c }, phi_ready("Pair", "Three of a Kind"), { hands = 1, discards = 2 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("a weak pair with a dominant alt still opens a confirmation",
    res == nil and ActionResult.is_error(err))
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local def = confirm_play_def()
  -- No schema minLength: it would reject a short reason as SCHEMA_INVALID before the handler could
  -- answer with the coaching message.
  check("confirm_play schema advertises reason once a dominant alt is pending",
    def ~= nil and def.schema.properties.reason ~= nil
      and def.schema.properties.reason.minLength == nil,
    def and def.schema.required)
  local validate_value = require("util.schema_validate").validate_value
  local all_pass = true
  for _, boiler in ipairs({ "looks good", "good enough", "ok", "do it" }) do
    if validate_value(def.schema.properties.reason, boiler, "reason") ~= true then all_pass = false end
  end
  check("every boilerplate reason reaches the handler instead of being schema-rejected", all_pass)

  -- snapshot_confirmations() holds a shallow reference to G.NEURO.play_confirm, so an in-place
  -- strike would survive a rollback. Capture that reference the way the dispatcher does.
  local pre_call_ref = G.NEURO.play_confirm

  local res1, rej1 = HandHandlers.handle_confirm_play({ answer = "yes", reason = "yes" })
  check("a reason that just restates the answer is rejected the first time",
    res1 == nil and ActionResult.is_error(rej1) and rej1.reason_code == "POLICY_REJECTED",
    tostring(rej1))
  check("the confirmation stays open after the first strike -- nothing was committed",
    G.NEURO.play_confirm ~= nil)
  check("the strike replaces the table rather than mutating the dispatcher's pre-call snapshot",
    G.NEURO.play_confirm ~= pre_call_ref and pre_call_ref.reason_strikes == nil
      and G.NEURO.play_confirm.reason_strikes == 1,
    tostring(pre_call_ref.reason_strikes))

  local exec = HandHandlers.handle_confirm_play({ answer = "yes", reason = "yes" })
  check("the second attempt commits regardless -- friction is bounded to one round trip",
    type(exec) == "function", type(exec))
end

do
  setup({ card("9", "Hearts"), card("9", "Diamonds") }, phi("Pair"), { hands = 1 })
  local def = confirm_play_def()
  check("confirm_play schema stays plain with nothing pending -- the common case is untouched",
    def ~= nil and #def.schema.required == 1 and def.schema.required[1] == "answer"
      and def.schema.properties.reason == nil)
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local def = confirm_play_def()
  check("a weak hand with no dominant alt keeps the plain schema -- no reason required",
    def ~= nil and #def.schema.required == 1)

  local exec = HandHandlers.handle_confirm_play({ answer = "yes" })
  check("plain yes with no reason still commits first try when nothing is dominated",
    type(exec) == "function", type(exec))
end

do
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "on")

  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local def = confirm_play_def()
  check("NEURO_CONFIRM_REASON_ALWAYS advertises reason even with no dominant alt",
    def ~= nil and def.schema.properties.reason ~= nil, def and def.schema.required)
  check("answer stays the only required field, so answer:\"no\" is never schema-rejected",
    def ~= nil and #def.schema.required == 1 and def.schema.required[1] == "answer",
    def and table.concat(def.schema.required, ","))

  local res1, rej1 = HandHandlers.handle_confirm_play({ answer = "yes", reason = "yes" })
  check("a degenerate reason is rejected under the always-reason flag too, with generic wording",
    res1 == nil and ActionResult.is_error(rej1) and rej1.reason_code == "POLICY_REJECTED"
      and rej1.message:find("Say specifically why this is the play", 1, true) ~= nil,
    tostring(rej1))

  local exec2 = HandHandlers.handle_confirm_play({ answer = "yes", reason = "yes" })
  check("bounded retry still applies under the always-reason flag",
    type(exec2) == "function", type(exec2))

  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "off")
  local def2 = confirm_play_def()
  check("turning the flag back off restores the plain schema for the common case",
    def2 ~= nil and #def2.schema.required == 1, def2 and def2.schema.required)
end

do
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "on")

  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  promote(HandHandlers.play_signature({ a, b }), HandHandlers.play_content({ a, b }),
    { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local no_schema = require("core.dispatcher")._test.get_action_schema("confirm_play")
  check("the dispatcher-visible schema does not require reason either",
    no_schema and #no_schema.required == 1 and no_schema.required[1] == "answer",
    no_schema and table.concat(no_schema.required, ","))

  local exec_no = HandHandlers.handle_confirm_play({ answer = "no" })
  check("the handler discards on a bare no without demanding a reason",
    type(exec_no) == "function", type(exec_no))

  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "off")
end

do
  local Staging = require("core.staging")
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 4, discards = 3 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  promote(HandHandlers.play_signature({ a, b }), HandHandlers.play_content({ a, b }),
    { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  Staging.reset_run_state()
  Staging._test.set_validator(function()
    HandHandlers.handle_confirm_play({ answer = "yes", reason = "the pair is the only scoring line" })
    return true
  end)
  local queued = Staging.queue({ command = "action",
    data = { id = "hover-1", name = "confirm_play", data = '{"answer":"yes"}' } },
    { send_action_result = function() end, send_context = function() end })
  Staging._test.set_validator(nil)

  check("a confirmed play is staged", queued == true)
  check("and it carries the confirmation's cards, so the committing send still animates",
    Staging._test.staged_hover_count() == 2, Staging._test.staged_hover_count())
  Staging.reset_run_state()
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  local c, d, e = card("2", "Clubs"), card("3", "Clubs"), card("4", "Clubs")
  setup({ a, b, c, d, e }, phi_ready("Straight", "Three of a Kind"), { hands = 4, discards = 3 })
  local _, strong_err = HandHandlers.handle_play_hand({ indices = { 3, 4, 5 } })
  check("the strong selection opens a confirmation", ActionResult.is_error(strong_err))
  check("but it does not spend the weak budget", G.NEURO.weak_fired_serial == nil,
    tostring(G.NEURO.weak_fired_serial))

  G.FUNCS.get_poker_hand_info = phi_ready("Pair", "Three of a Kind")
  local _, weak_err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("so the weak selection still gets its advice",
    ActionResult.normalize(weak_err).message:find("also ready in your hand right now", 1, true) ~= nil,
    ActionResult.normalize(weak_err).message)
end

done()
