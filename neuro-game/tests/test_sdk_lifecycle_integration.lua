_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("sdk-lifecycle-integration")

local Enforce = require("core.enforce")
local ActionResult = require("core.action_result")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Orchestrator = require("core.orchestrator")
local ContextCompact = require("context.context_compact")
local TokenLegends = require("facts.token_legends")
local Once = require("util.once")

local play_card = require("tests.helpers").play_card

local function make_joker(key, name, desc)
  return {
    cost = 4, sell_cost = 2, debuff = false,
    ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = key, name = name, set = "Joker",
      loc_txt = { name = name, description = desc or "+4 Mult" } } },
  }
end

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = { make_joker("j_joker", "Joker") }, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.playbook_extra = nil
  G.shop_jokers = nil
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
  }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  ContextCompact.invalidate_cache()
end

local function force_bridge(over)
  require("core.context_delivery").reset_transport()
  local N = { enabled = true, persona = "neuro", emitted = {}, reg_log = {}, unreg_log = {},
    llm_paused = false }
  function N:send_context(msg, _silent, receipt)
    if self.llm_paused then if receipt then receipt.status = "rejected" end return false end
    self.emitted[#self.emitted + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  function N:register_actions(defs)
    local names = {}
    for i, d in ipairs(defs or {}) do names[i] = d.name end
    self.reg_log[#self.reg_log + 1] = names
  end
  function N:unregister_actions(names)
    local copy = {}
    for i, v in ipairs(names or {}) do copy[i] = v end
    self.unreg_log[#self.unreg_log + 1] = copy
  end
  function N:force_actions() end
  function N:send_action_result() end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

do
  selecting_hand_env(500)
  G.NEURO = force_bridge({})
  require("core.force_state").arm("SELECTING_HAND", { "discard_hand" },
    { discard_hand = true }, 1)
  local b = { send_context = function() end }
  local last_ok, last_err, last_code
  for i = 1, 31 do
    G.NEURO.force_inflight = true
    last_ok, last_err, _, last_code = Enforce.pre_action(b, "discard_hand")
    if i <= 30 then
      check("A: forced repeat " .. i .. " passes the gate", last_ok == true, last_err)
    end
  end
  check("A: forced repeat over the limit is refused by the gate", last_ok ~= true)
  check("A: refusal carries an acknowledging reason code (wire success=true, no force retry)",
    ActionResult.acknowledges(last_code) == true, tostring(last_code))
  check("A: acknowledgement says nothing happened",
    tostring(last_err):find("Nothing happened", 1, true) ~= nil, tostring(last_err))
end

do
  selecting_hand_env(600)
  G.NEURO = force_bridge()
  local b = { send_context = function() end }
  local last_ok, last_code
  for _i = 1, 31 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    local ok, _a, _b, code = Enforce.pre_action(b, "discard_hand")
    last_ok, last_code = ok, code
  end
  check("A: unforced repeat over the limit still hard-rejects", last_ok ~= true)
  check("A: unforced refusal keeps POLICY_REJECTED (success=false is safe outside a force)",
    last_code == "POLICY_REJECTED", tostring(last_code))
end

do
  selecting_hand_env(700)
  G.NEURO = force_bridge()
  local contexts = {}
  local b = {}
  function b:send_context(msg, _silent) contexts[#contexts + 1] = tostring(msg) end
  Enforce.on_error(b)
  Enforce.post_action(b, false)
  check("on_error/post_action(false) send no board dump to retained context",
    #contexts == 0, tostring(contexts[1]))
end

do
  selecting_hand_env(800)
  local N = force_bridge({ stable_refresh_due = true })
  G.NEURO = N
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  local rules_first = 0
  for _, m in ipairs(N.emitted) do
    if m:find("RULES.", 1, true) == 1 then rules_first = rules_first + 1 end
  end
  check("first stable emission carries the rules head", rules_first == 1, tostring(#N.emitted))
  check("first stable emission excludes the variable tail", #N.emitted == 1)

  local before = #N.emitted
  G.jokers.cards[#G.jokers.cards + 1] = make_joker("j_greedy_joker", "Greedy Joker",
    "Played Diamond cards give +3 Mult when scored")
  ContextCompact.invalidate_cache()
  N.stable_refresh_due = true
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("roster change emits no retained tail", #N.emitted == before)
  local rules_again = false
  for i = before + 1, #N.emitted do
    if N.emitted[i]:find("RULES.", 1, true) == 1 then rules_again = true end
  end
  check("roster change does NOT re-emit the rules head", rules_again == false)
end

do
  selecting_hand_env(900)
  local N = force_bridge({ stable_refresh_due = true, llm_paused = true })
  G.NEURO = N
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("paused bridge emits nothing", #N.emitted == 0)
  N.llm_paused = false
  N.stable_refresh_due = true
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  local got_rules = false
  for _, m in ipairs(N.emitted) do
    if m:find("RULES.", 1, true) == 1 then got_rules = true end
  end
  check("gate not consumed while paused -- rules delivered after unpause", got_rules == true)
end

do
  Enforce.reset_run_state()
  local acknowledged = false
  for _ = 1, 4 do acknowledged = Enforce.note_rejection("play_hand", "same-decision") end
  check("A: an unchanged rejection scope eventually becomes a terminal acknowledgement",
    acknowledged == true)
  check("A: real decision progress resets the rejection acknowledgement streak",
    Enforce.note_rejection("play_hand", "next-decision") == false)
end

do
  selecting_hand_env(1000)
  local N = force_bridge()
  G.NEURO = N
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  local first = #N.emitted
  check("first glossary emission delivers the common legend",
    first > 0 and N.emitted[1] == TokenLegends.READABLE_COMMON)
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("the same ante does not re-emit glossaries", #N.emitted == first, tostring(#N.emitted))
  G.GAME.round_resets.ante = 2
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("a new ante stays silent under session epoch", #N.emitted == first, tostring(#N.emitted))
end

do
  selecting_hand_env(1100)
  local N = force_bridge({ llm_paused = true })
  G.NEURO = N
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("paused bridge emits no glossary", #N.emitted == 0)
  N.llm_paused = false
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("glossary gate not consumed while paused", #N.emitted > 0)
end
do
  G.NEURO.once_serials = {}
  check("peek does not consume an unsent glossary gate",
    Once.peek("gloss:test", "session") and Once.peek("gloss:test", "session"))
  Once.book("gloss:test", "session")
  check("book consumes the glossary gate only after delivery",
    not Once.peek("gloss:test", "session"))
  check("a new epoch reopens the glossary gate",
    Once.peek("gloss:test", "next-session"))
end

do
  selecting_hand_env(1200)
  G.NEURO = force_bridge()
  local PlanHandlers = require("handlers.plan_handlers")
  local exec1 = PlanHandlers.prepare_plan({ hand_plan = "play pairs early" })
  check("first plan write accepted", type(exec1) == "function")
  check("it puts no plan wording on the retained channel", exec1() == nil)
  check("the plan itself is held in state, scoped",
    G.NEURO.plan.hand == "play pairs early" and G.NEURO.plan.hand_scope ~= nil,
    tostring(G.NEURO.plan.hand) .. " @ " .. tostring(G.NEURO.plan.hand_scope))
  local exec2 = PlanHandlers.prepare_plan({ hand_plan = "play pairs aggressively" })
  check("rewriting the slot is equally silent", exec2() == nil)
  check("and the rewrite superseded the old wording in state",
    G.NEURO.plan.hand == "play pairs aggressively", tostring(G.NEURO.plan.hand))
  G.GAME.round_resets.ante = 3
  G.GAME.blind_on_deck = "Boss"
  G.GAME.round_resets.blind_on_deck = "Boss"
  local exec3 = PlanHandlers.prepare_plan({ hand_plan = "save discards for the boss" })
  check("a new plan scope is silent too", exec3() == nil)
  check("the new scope is the one recorded",
    G.NEURO.plan.hand_scope == require("core.plan_gate").current_blind_scope(),
    tostring(G.NEURO.plan.hand_scope))
end

do
  selecting_hand_env(1300)
  local N = force_bridge()
  G.NEURO = N
  Orchestrator.register_valid_actions("HAND_PLAYED")
  check("transient state sends no register frame", #N.reg_log == 0)
  Orchestrator.register_valid_actions("DRAW_TO_HAND")
  Orchestrator.register_valid_actions("NEW_ROUND")
  Orchestrator.register_valid_actions("PLAY_TAROT")
  check("no transient state sends a register frame", #N.reg_log == 0)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local has_play = false
  for _, n in ipairs(N.reg_log[1] or {}) do
    if n == "play_hand" then has_play = true end
  end
  check("a real state still registers its action set",
    #N.reg_log == 1 and has_play)
  check("state_has_actions covers pack states",
    Actions.state_has_actions("TAROT_PACK") == true
      and Actions.state_has_actions("HAND_PLAYED") == false)
end

local Bridge = require("core.bridge")

local function wire_bridge(registered)
  local b = setmetatable({ log = {}, enabled = true,
    _registered_set = {}, _registered_sigs = {} }, { __index = Bridge })
  for _, n in ipairs(registered or {}) do
    b._registered_set[n] = true
    b._registered_sigs[n] = "sig"
  end
  function b:send(msg, receipt)
    if msg.command == "actions/unregister" then
      self.log[#self.log + 1] = { kind = "unregister", names = msg.data.action_names }
    end
    if receipt then
      receipt.status = "written"
      receipt.written_at = G.TIMERS.REAL
    end
    return true
  end
  function b:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, msg = msg, reason = reason }
    return true
  end
  function b:send_context() return true end
  function b:register_actions() end
  function b:write_file() return true end
  b:set_desired_action_names(function()
    local want = {}
    local state_name = require("core.state").get_state_name()
    for _, n in ipairs(Actions.get_valid_actions_for_state(state_name)) do want[n] = true end
    return want
  end)
  return b
end

do
  selecting_hand_env(1400)
  G.NEURO = force_bridge({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
    weak_fired_serial = 5,
  })
  G.NEURO.play_confirm = {
    signature = "1,2",
    content = require("handlers.hand_handlers").play_content({ G.hand.cards[1], G.hand.cards[2] }),
    indices = { 1, 2 }, decision_serial = 5, run_generation = 0,
  }
  require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  require("core.tx_cache").reset()
  local played = false
  local b = wire_bridge({ "play_hand", "discard_hand" })
  G.FUNCS.play_cards_from_highlighted = function()
    played = true
    b.log[#b.log + 1] = { kind = "execution" }
    local selected = {}
    for _, card in ipairs(G.hand.highlighted or {}) do selected[card] = true end
    local kept = {}
    for _, card in ipairs(G.hand.cards or {}) do
      if not selected[card] then kept[#kept + 1] = card end
    end
    G.hand.cards = kept
    G.hand.highlighted = {}
    G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
  end
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  check("play committed", played == true)
  check("shared event log proves unregister -> result -> execution",
    b.log[1] and b.log[1].kind == "unregister" and b.log[1].names[1] == "play_hand"
      and b.log[2] and b.log[2].kind == "result"
      and b.log[2].ok == true and b.log[2].id == "disp-1"
      and b.log[3] and b.log[3].kind == "execution",
    table.concat((function()
      local kinds = {}
      for _, event in ipairs(b.log) do kinds[#kinds + 1] = tostring(event.kind) end
      return kinds
    end)(), " -> "))
  check("success result closes the force after the unregister",
    G.NEURO.force_inflight == false)
end

do
  selecting_hand_env(1500)
  G.NEURO = force_bridge({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 7,
  })
  require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  require("core.tx_cache").reset()
  local b = wire_bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  local unregs = 0
  for _, e in ipairs(b.log) do if e.kind == "unregister" then unregs = unregs + 1 end end
  check("confirmation round-trip does NOT unregister (force stays valid for the resend)",
    unregs == 0, tostring(unregs))
  check("confirmation result present",
    b.log[1] and b.log[1].kind == "result" and b.log[1].reason == "CONFIRMATION_REQUIRED")
end

do
  selecting_hand_env(1600)
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions })
  require("core.tx_cache").reset()
  local b = wire_bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-3", name = "play_hand", data = { indices = { 99 } } } }, b)
  local unregs = 0
  for _, e in ipairs(b.log) do if e.kind == "unregister" then unregs = unregs + 1 end end
  check("rejected disposable action sends no unregister", unregs == 0)
  check("rejection result still delivered",
    b.log[#b.log] and b.log[#b.log].kind == "result" and b.log[#b.log].ok == false)
end

do
  G.TIMERS.REAL = 1700
  require("core.action_receipt").reset("test_env")
  G.STATES = { ROUND_EVAL = 8, SHOP = 9 }
  G.STATE = 8
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.round_eval = true
  G.GAME = {
    dollars = 10, used_vouchers = {},
    current_round = { hands_left = 1, discards_left = 1 },
    round_resets = { ante = 1 },
    hands = {},
    modifiers = {},
  }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {} }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions })
  require("core.tx_cache").reset()
  local cashed = false
  G.FUNCS.cash_out = function()
    cashed = true
    G.round_eval = nil
    G.STATE = G.STATES.SHOP
    G.NEURO.state = "SHOP"
  end
  local b = wire_bridge({ "cash_out" })
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-4", name = "cash_out", data = {} } }, b)
  check("cash_out executes", cashed == true)
  check("cash_out unregisters before its success result",
    b.log[1] and b.log[1].kind == "unregister" and b.log[1].names[1] == "cash_out"
      and b.log[2] and b.log[2].kind == "result" and b.log[2].ok == true)

  G.STATE, G.STATE_COMPLETE, G.round_eval = G.STATES.ROUND_EVAL, true, true
  require("core.action_receipt").reset("buffered_result_case")
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.tx_cache").reset()
  cashed = false
  local receipt = { status = "buffered" }
  local buffered = wire_bridge({ "cash_out" })
  function buffered:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, msg = msg, reason = reason }
    return true, receipt
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-buffered", name = "cash_out", data = {} } }, buffered)
  check("a merely buffered result does not execute the action", cashed == false)
  local waiting_before_write = Dispatcher._test.awaiting_result_write_count()
  receipt.status = "written"
  Dispatcher.update_receipts(1701)
  check("the action executes after its result is physically written", cashed == true,
    "waiting=" .. tostring(waiting_before_write) .. "->"
      .. tostring(Dispatcher._test.awaiting_result_write_count()) .. " receipt=" .. tostring(receipt.status)
      .. " last=" .. tostring(buffered.log[#buffered.log] and buffered.log[#buffered.log].kind)
      .. "/" .. tostring(buffered.log[#buffered.log] and buffered.log[#buffered.log].ok)
      .. "/" .. tostring(buffered.log[#buffered.log] and buffered.log[#buffered.log].reason))

  G.STATE, G.STATE_COMPLETE, G.round_eval = G.STATES.ROUND_EVAL, true, true
  Dispatcher.reset_run_state()
  require("core.action_receipt").reset("buffered_result_abandon_case")
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.tx_cache").reset()
  cashed = false
  local abandoned_receipt = { status = "buffered" }
  local abandoned_buffered = wire_bridge({ "cash_out" })
  function abandoned_buffered:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, msg = msg, reason = reason }
    return true, abandoned_receipt
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-abandoned", name = "cash_out", data = {} } }, abandoned_buffered)
  check("buffered action is waiting before transport abandonment",
    Dispatcher._test.awaiting_result_write_count() == 1 and cashed == false)
  Dispatcher.handle_message({ command = "neuro-bridge/abandon",
    data = { ids = { "disp-abandoned" } } }, abandoned_buffered)
  check("protocol abandon finds a job after it left the prepared map",
    Dispatcher._test.awaiting_result_write_count() == 0)
  check("abandon removes the durable-write waiter",
    Dispatcher._test.awaiting_result_write_count() == 0)
  abandoned_receipt.status = "written"
  Dispatcher.update_receipts(1702)
  check("a later buffered write cannot execute an abandoned action", cashed == false)

  G.STATE, G.STATE_COMPLETE, G.round_eval = G.STATES.ROUND_EVAL, true, true
  require("core.action_receipt").reset("buffered_unregister_case")
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.tx_cache").reset()
  cashed = false
  local unregister_receipt = { status = "buffered" }
  local withdrawal_buffered = wire_bridge({ "cash_out" })
  function withdrawal_buffered:send(msg, out_receipt)
    if msg.command == "actions/unregister" then
      self.log[#self.log + 1] = { kind = "unregister", names = msg.data.action_names }
      unregister_receipt = out_receipt
      unregister_receipt.status = "buffered"
      return false
    end
    return true
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-unregister-buffered", name = "cash_out", data = {} } }, withdrawal_buffered)
  check("buffered disposable unregister sends neither result nor mutation",
    cashed == false and #withdrawal_buffered.log == 1
      and withdrawal_buffered.log[1].kind == "unregister"
      and Dispatcher._test.awaiting_disposable_write_count() == 1)
  unregister_receipt.status = "written"
  unregister_receipt.written_at = 1702
  Dispatcher.update_receipts(1702)
  check("durable unregister releases result then execution in order",
    cashed == true
      and withdrawal_buffered.log[2] and withdrawal_buffered.log[2].kind == "result"
      and #withdrawal_buffered.log == 2
      and Dispatcher._test.awaiting_disposable_write_count() == 0)
end

do
  G.TIMERS.REAL = 1800
  require("core.action_receipt").reset("test_env")
  G.STATES = { ROUND_EVAL = 8, SHOP = 9 }
  G.STATE, G.STATE_COMPLETE, G.round_eval = 8, true, true
  G.GAME = {
    dollars = 10, used_vouchers = {}, hands = {}, modifiers = {},
    current_round = { hands_left = 1, discards_left = 1 },
    round_resets = { ante = 1 },
  }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {} }
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.tx_cache").reset()
  local executed, sends = false, 0
  G.FUNCS.cash_out = function() executed = true end
  local b = wire_bridge({ "cash_out" })
  local real_result = b.send_action_result
  function b:send_action_result(...)
    sends = sends + 1
    if sends == 1 then error("result serializer exploded") end
    return real_result(self, ...)
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-send-fault", name = "cash_out", data = {} } }, b)
  check("a result-send throw aborts instead of executing an unacknowledged action",
    executed == false)
  check("a result-send throw releases the disposable lock and pays the fallback result",
    G.NEURO.consumed_actions == nil
      and b.log[#b.log] and b.log[#b.log].kind == "result" and b.log[#b.log].ok == false,
    "lock=" .. tostring(G.NEURO.consumed_actions) .. " sends=" .. tostring(sends)
      .. " last=" .. tostring(b.log[#b.log] and b.log[#b.log].kind)
      .. "/" .. tostring(b.log[#b.log] and b.log[#b.log].ok))
end

done()
