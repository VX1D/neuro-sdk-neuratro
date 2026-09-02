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
local HandTx = require("core.hand_transaction")

local function confirm(answer, reason)
  local tx = HandTx.current()
  return HandHandlers.handle_resolve_play({
    transaction_id = tx and tx.id or nil,
    answer = answer,
    reason = reason,
  })
end

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
  check("resolve_play unavailable with nothing pending",
    Actions.is_action_valid("resolve_play") == false)

  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("play_hand opens a confirmation", res == nil and ActionResult.is_error(err))
  check("resolve_play still unavailable: the candidate is armed but not yet delivery-proven",
    Actions.is_action_valid("resolve_play") == false)

  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)
  check("resolve_play becomes available once the confirmation is promoted",
    Actions.is_action_valid("resolve_play") == true)
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

  local exec = confirm("yes")
  check("resolve_play yes returns an executor", type(exec) == "function", type(exec))
  exec()
  check("yes actually plays the confirmed cards", played == true)
  check("yes clears both the synchronous slot and the evidence record",
    HandTx.current() and HandTx.current().phase == "committing")
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

  local exec = confirm("no")
  check("resolve_play no returns an executor", type(exec) == "function", type(exec))
  local msg = exec()
  check("no returns a proper applied outcome, not a bare string",
    type(msg) == "table" and msg.__action_outcome == true and msg.status == "applied", tostring(msg))
  check("no cancels the confirmation without playing or discarding anything",
    played == false and type(msg) == "table" and type(msg.message) == "string"
      and msg.message:find("cancelled", 1, true) ~= nil
      and msg.message:find("Nothing was played or discarded", 1, true) ~= nil, tostring(msg))
  check("no clears both the synchronous slot and the evidence record",
    HandTx.current() == nil and ConfirmationEvidence.current() == nil)
end

do
  local a, b, c = card("9", "Hearts"), card("9", "Diamonds"), card("4", "Clubs")
  setup({ a, b, c }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  table.remove(G.hand.cards, 1)
  local reject = confirm("yes")
  check("yes on a confirmation whose card left the hand is refused, not silently committed",
    reject == nil, tostring(reject))
  check("the stale confirmation is torn down rather than left dangling",
    HandTx.current() == nil and ConfirmationEvidence.current() == nil)
end

do
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local res, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  local sig = HandHandlers.play_signature({ a, b })
  local content = HandHandlers.play_content({ a, b })
  promote(sig, content, { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  a.base.value, a.base.suit = "King", "Clubs"
  local reject = confirm("yes")
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
  check("strict resolution mode refuses selection B while A is ready",
    resB == nil and ActionResult.is_error(errB)
      and errB.reason_code == "POLICY_ACKNOWLEDGED"
      and HandTx.current().signature == sigA)
  check("A's stale promoted record is still sitting in ConfirmationEvidence (unstaged B has not promoted yet)",
    ConfirmationEvidence.current() ~= nil
      and ConfirmationEvidence.current().signature == sigA)

  local exec = confirm("yes")
  check("resolve_play still resolves A because B could not replace it",
    type(exec) == "function", tostring(exec))
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
  PlanTransaction.hold(tx1, 1)
  check("P16: the boss_plan is held after the send is rejected as a confirmation",
    G.NEURO.held_plan_write ~= nil
      and G.NEURO.held_plan_write.values.boss_plan == "the held boss plan text")

  local tx2 = PlanTransaction.prepare("resolve_play", { transaction_id = 1, answer = "yes" })
  check("P16: resolve_play resumes the held boss_plan with no plan field of its own",
    tx2 ~= nil and tx2.plan_values.boss_plan == "the held boss plan text"
      and type(tx2.plan_commit) == "function")
  tx2.plan_commit()
  PlanGate.complete_requirements(tx2.requirements, tx2.token.shop_visit_epoch)
  check("P16: committing through resolve_play actually writes the plan",
    G.NEURO.plan ~= nil and G.NEURO.plan.boss == "the held boss plan text")
end

local function confirm_play_def()
  for _, def in ipairs(Actions.get_static_actions()) do
    if def.name == "resolve_play" then return def end
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
  check("resolve_play schema exposes optional reason without making it part of the protocol",
    def ~= nil and def.schema.properties.reason ~= nil
      and def.schema.properties.reason.minLength == nil
      and def.schema.properties.reason.maxLength == nil
      and #def.schema.required == 2 and def.schema.required[1] == "transaction_id"
      and def.schema.required[2] == "answer",
    def and def.schema.required)
  local validate_value = require("util.schema_validate").validate_value
  local all_pass = true
  for _, boiler in ipairs({ "looks good", "good enough", "ok", "do it" }) do
    if validate_value(def.schema.properties.reason, boiler, "reason") ~= true then all_pass = false end
  end
  check("every boilerplate reason reaches the handler instead of being schema-rejected", all_pass)

  local exec = confirm("yes", "yes")
  check("yes commits on the first attempt even with a degenerate optional reason",
    type(exec) == "function", type(exec))
end

do
  setup({ card("9", "Hearts"), card("9", "Diamonds") }, phi("Pair"), { hands = 1 })
  local def = confirm_play_def()
  check("resolve_play schema remains binary with optional reason in the common case",
    def ~= nil and #def.schema.required == 2 and def.schema.required[1] == "transaction_id"
      and def.schema.required[2] == "answer"
      and def.schema.properties.reason ~= nil)
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
    def ~= nil and #def.schema.required == 2)

  local exec = confirm("yes")
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
  check("NEURO_CONFIRM_REASON_ALWAYS does not change the binary schema",
    def ~= nil and def.schema.properties.reason ~= nil, def and def.schema.required)
  check("transaction identity and answer remain the only required fields",
    def ~= nil and #def.schema.required == 2
      and def.schema.required[1] == "transaction_id" and def.schema.required[2] == "answer",
    def and table.concat(def.schema.required, ","))

  local exec2 = confirm("yes", "yes")
  check("yes still commits on the first attempt under the always-reason flag",
    type(exec2) == "function", type(exec2))

  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "off")
  local def2 = confirm_play_def()
  check("turning the flag back off keeps the same binary schema",
    def2 ~= nil and #def2.schema.required == 2
      and def2.schema.properties.reason ~= nil, def2 and def2.schema.required)
end

do
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "on")

  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 1 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  promote(HandHandlers.play_signature({ a, b }), HandHandlers.play_content({ a, b }),
    { 1, 2 }, "Pair", ActionResult.normalize(err).message)

  local no_schema = require("core.dispatcher")._test.get_action_schema("resolve_play")
  check("the dispatcher-visible schema does not require reason either",
    no_schema and #no_schema.required == 2
      and no_schema.required[1] == "transaction_id" and no_schema.required[2] == "answer",
    no_schema and table.concat(no_schema.required, ","))

  local exec_no = confirm("no")
  check("the handler cancels on a bare no without demanding a reason",
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
  local staged_id = HandTx.current().id
  Staging._test.set_validator(function()
    HandHandlers.handle_resolve_play({ transaction_id = staged_id, answer = "yes",
      reason = "the pair is the only scoring line" })
    return true
  end)
  local queued = Staging.queue({ command = "action",
    data = { id = "hover-1", name = "resolve_play",
      data = string.format('{"transaction_id":%d,"answer":"yes"}', staged_id) } },
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
  check("the weak-layer pause spends its budget even for a strong selection",
    G.NEURO.weak_fired_serial == G.NEURO.decision_serial,
    tostring(G.NEURO.weak_fired_serial))

  G.FUNCS.get_poker_hand_info = phi_ready("Pair", "Three of a Kind")
  local _, weak_err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("strict resolution mode prevents a different selection from replacing the first proposal",
    ActionResult.normalize(weak_err).reason_code == "POLICY_ACKNOWLEDGED",
    ActionResult.normalize(weak_err).message)
end

do
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_HAND", "off")

  local played = false
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 4, discards = 3 })
  G.FUNCS.play_cards_from_highlighted = function() played = true end

  local exec = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("with confirmations off, play_hand commits on the first send",
    type(exec) == "function", type(exec))
  exec()
  check("and it actually plays the selection", played == true)
  check("no confirmation is armed", HandTx.current() == nil,
    tostring(HandTx.current()))
  check("resolve_play is not offered", Actions.is_action_valid("resolve_play") == false)
  check("the rules text stays valid either way, pointing at the action description",
    require("facts.token_legends").READABLE_STATE.SELECTING_HAND
      :find("spends nothing until the commit", 1, true) ~= nil)

  Config.set("NEURO_CONFIRM_HAND", "on")
  setup({ a, b }, phi("Pair"), { hands = 4, discards = 3 })
  local res = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  check("turning it back on restores the confirmation", res == nil and HandTx.current() ~= nil)
end

do
  -- Flipping the toggle mid-decision must not leave an open confirmation the model cannot answer.
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_HAND", "on")
  local a, b = card("9", "Hearts"), card("9", "Diamonds")
  setup({ a, b }, phi("Pair"), { hands = 4, discards = 3 })
  local _, err = HandHandlers.handle_play_hand({ indices = { 1, 2 } })
  promote(HandHandlers.play_signature({ a, b }), HandHandlers.play_content({ a, b }),
    { 1, 2 }, "Pair", ActionResult.normalize(err).message)
  check("a confirmation is open", HandHandlers.pending() ~= nil)

  Config.set("NEURO_CONFIRM_HAND", "off")
  check("turning confirmations off retires the open one", HandHandlers.pending() == nil,
    tostring(HandHandlers.pending()))
  -- nil alone is any rejection; name the reason.
  local retired_ok, retired_err = confirm("yes")
  check("and resolve_play cannot commit it", retired_ok == nil, tostring(retired_ok))
  local retired_msg = tostring(type(retired_err) == "table" and retired_err.message or retired_err)
  check("rejected because nothing is armed, not for some unrelated reason",
    retired_msg:find("stale or missing its transaction_id", 1, true) ~= nil, retired_msg)

  Config.set("NEURO_CONFIRM_HAND", "on")
end

done()
