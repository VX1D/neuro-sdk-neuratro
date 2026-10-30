require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("sdk-lifecycle-integration")

local Enforce = require("tests.helpers").enforce()
local ActionResult = require("core.action_result")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx
local Orchestrator = require("core.orchestrator")
local ContextCompact = require("context.context_compact")
local TokenLegends = require("facts.token_legends")
local Once = require("util.once")
local Config = require("core.config")

local json = require("util.neuro_json")
local play_card = require("tests.helpers").play_card
local make_joker = require("tests.fake_cards").make_joker

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  require("tests.helpers").in_engine_state("SELECTING_HAND")
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
  G.hand = require("tests.helpers").card_area({ cards = { play_card(1), play_card(2), play_card(3) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } })
  G.jokers = { cards = { make_joker("j_joker", "Joker") }, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = nil
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
  }
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
end

local function force_bridge(over)
  require("core.context_delivery").reset_transport()
  local N = require("tests.helpers").started_bridge(require("tests.helpers").stub_bridge({
    enabled = true, persona = "neuro", run_generation = 1, transport_session = "test-session",
    emitted = {}, reg_log = {}, llm_paused = false, force_actions = "noop", send_action_result = "noop",
  }))
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
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

local function action_envelope(id, name, payload)
  local data = (type(payload) == "table" and next(payload) ~= nil) and json.encode(payload) or "{}"
  return {
    command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = name, data = data },
  }
end

do
  selecting_hand_env(500)
  G.NEURO = force_bridge({})
  require("tests.helpers").open_force("SELECTING_HAND", { "discard_hand" })
  local b = { send_context = function() end }
  local last_ok, last_err, last_terminal
  for i = 1, 31 do
    last_ok, last_err, last_terminal = Enforce.pre_action(b, "discard_hand")
    if i <= 30 then
      check("A: forced repeat " .. i .. " passes the gate", last_ok == true, last_err)
    end
  end
  check("A: forced repeat over the limit is refused by the gate", last_ok ~= true)
  check("A: the refusal is terminal (wire success=true, no force retry)", last_terminal == true)
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
  selecting_hand_env(800)
  local N = force_bridge({ stable_refresh_due = true })
  G.NEURO = N
  require("core.window").emit_rules("SELECTING_HAND")
  local rules_first = 0
  for _, m in ipairs(N.emitted) do
    if m:find("RULES.", 1, true) == 1 then rules_first = rules_first + 1 end
  end
  check("first stable emission carries the rules head", rules_first == 1, tostring(#N.emitted))
  check("first stable emission is limited to retained stable frames",
    #N.emitted >= 1, tostring(#N.emitted))
  local before = #N.emitted
  G.jokers.cards[#G.jokers.cards + 1] = make_joker("j_greedy_joker", "Greedy Joker",
    "Played Diamond cards give +3 Mult when scored")
  N.stable_refresh_due = true
  require("core.window").emit_rules("SELECTING_HAND")
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
  require("core.window").emit_rules("SELECTING_HAND")
  check("paused bridge emits nothing", #N.emitted == 0)
  N.llm_paused = false
  N.stable_refresh_due = true
  require("core.window").emit_rules("SELECTING_HAND")
  local got_rules = false
  for _, m in ipairs(N.emitted) do
    if m:find("RULES.", 1, true) == 1 then got_rules = true end
  end
  check("gate not consumed while paused -- rules delivered after unpause", got_rules == true)
end

do
  selecting_hand_env(1000)
  local N = force_bridge()
  G.NEURO = N
  local stages, stage = G.STAGES, G.STAGE
  G.STAGES = { RUN = 2 }; G.STAGE = 2
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  local first = #N.emitted
  check("first glossary emission delivers the common legend",
    first > 0 and N.emitted[1] == TokenLegends.READABLE_COMMON)
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("the same ante does not re-emit glossaries", #N.emitted == first, tostring(#N.emitted))
  G.GAME.round_resets.ante = 2
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("a new ante repeats the glossaries", #N.emitted > first, tostring(#N.emitted))
  G.STAGES, G.STAGE = stages, stage
end

do
  selecting_hand_env(1100)
  local N = force_bridge({ llm_paused = true })
  G.NEURO = N
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("paused bridge emits no glossary", #N.emitted == 0)
  N.llm_paused = false
  require("core.window")._test.emit_glossary("SELECTING_HAND")
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
    G.NEURO.plan.hand_scope == require("core.gate").current_blind_scope(),
    tostring(G.NEURO.plan.hand_scope))
end

do
  selecting_hand_env(1300)
  local N = force_bridge()
  G.NEURO = N
  require("core.window").register_catalogue()
  check("first transient state registers the canonical action catalogue", #N.reg_log == 1)
  require("core.window").register_catalogue()
  require("core.window").register_catalogue()
  require("core.window").register_catalogue()
  check("transient state changes do not re-register the canonical catalogue", #N.reg_log == 1)
  require("core.window").register_catalogue()
  local has_play = false
  for _, n in ipairs(N.reg_log[1] or {}) do
    if n == "play_hand" then has_play = true end
  end
  check("a real state keeps the canonical action set without re-registering",
    #N.reg_log == 1 and has_play)

  local previous_pack_cards, previous_booster_pack = G.pack_cards, G.booster_pack
  local pack = { cards = { play_card(1) } }
  G.pack_cards, G.booster_pack = pack, pack
  local pack_actions = Actions.get_valid_actions_for_state("SMODS_BOOSTER_OPENED")
  local transient_actions = Actions.get_valid_actions_for_state("HAND_PLAYED")
  local has_pack_choice = false
  for _, name in ipairs(pack_actions) do
    if name == "choose_pack_card" then has_pack_choice = true end
  end
  G.pack_cards, G.booster_pack = previous_pack_cards, previous_booster_pack
  check("the canonical action list covers pack-state availability",
    has_pack_choice, table.concat(pack_actions, ","))
  check("the canonical action list leaves transient states unavailable",
    #transient_actions == 0, table.concat(transient_actions, ","))
end

local Bridge = require("core.bridge")

local function wire_bridge(registered)
  local b = setmetatable({ log = {}, enabled = true,
    _registered_sigs = {} }, { __index = Bridge })
  for _, n in ipairs(registered or {}) do
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
    return true, { status = "written", written_at = G.TIMERS.REAL }
  end
  local H = require("tests.helpers")
  b.send_context, b.register_actions, b.write_file = H.yes, H.noop, H.yes
  return b
end

do
  selecting_hand_env(1400)
  Config.set("NEURO_CONFIRM_HAND", "off")
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
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  require("core.bridge").tx.reset()
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
  Dispatcher.handle_message(action_envelope("disp-1", "play_hand", { indices = { 1, 2 } }), b)
  check("play committed", played == true)
  check("shared event log proves unregister -> admission result -> execution",
    b.log[1] and b.log[1].kind == "unregister" and b.log[1].names[1] == "play_hand"
      and b.log[2] and b.log[2].kind == "result"
      and b.log[2].ok == true and b.log[2].id == "disp-1"
      and b.log[3] and b.log[3].kind == "execution",
    table.concat((function()
      local kinds = {}
      for _, event in ipairs(b.log) do kinds[#kinds + 1] = tostring(event.kind) end
      return kinds
    end)(), " -> "))
  check("the admission result answers the force", require("core.window").current() == nil)
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  selecting_hand_env(1500)
  G.NEURO = force_bridge({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 7,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  require("core.bridge").tx.reset()
  local b = wire_bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message(action_envelope("disp-2", "play_hand", { indices = { 1, 2 } }), b)
  local unregs = 0
  for _, e in ipairs(b.log) do if e.kind == "unregister" then unregs = unregs + 1 end end
  check("guarded proposal keeps the canonical action surface registered",
    unregs == 0, tostring(unregs))
  local confirmation_result
  for _, event in ipairs(b.log) do
    if event.kind == "result" then confirmation_result = event break end
  end
  check("confirmation result follows the withdrawal",
    confirmation_result and confirmation_result.reason == "CONFIRMATION_REQUIRED")
end

do
  selecting_hand_env(1600)
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions })
  require("core.bridge").tx.reset()
  local b = wire_bridge()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message(action_envelope("disp-3", "play_hand", { indices = { 99 } }), b)
  local unregs = 0
  for _, e in ipairs(b.log) do if e.kind == "unregister" then unregs = unregs + 1 end end
  check("rejected disposable action sends no unregister", unregs == 0)
  check("rejection result still delivered",
    b.log[#b.log] and b.log[#b.log].kind == "result" and b.log[#b.log].ok == false)
end

do
  G.TIMERS.REAL = 1700
  require("tests.helpers").in_engine_state("ROUND_EVAL")
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.round_eval = true
  require("tests.helpers").cash_out_ready(G)
  G.GAME = {
    dollars = 10, used_vouchers = {},
    current_round = { hands_left = 1, discards_left = 1 },
    round_resets = { ante = 1 },
    hands = {},
    modifiers = {},
  }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = require("tests.helpers").card_area({ cards = {}, highlighted = {} })
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions })
  require("core.bridge").tx.reset()
  local cash_out_calls = 0
  local cashed
  G.FUNCS.cash_out = function()
    cash_out_calls = cash_out_calls + 1
    cashed = true
    G.round_eval = nil
    G.STATE = G.STATES.SHOP
    G.NEURO.state = "SHOP"
  end
  local b = wire_bridge({ "cash_out" })
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message(action_envelope("disp-4", "cash_out", {}), b)
  check("cash_out executes", cashed == true)
  check("cash_out unregisters before its success result",
    b.log[1] and b.log[1].kind == "unregister" and b.log[1].names[1] == "cash_out"
      and b.log[2] and b.log[2].kind == "result" and b.log[2].ok == true)

  G.STATE, G.STATE_COMPLETE, G.round_eval = G.STATES.ROUND_EVAL, true, true
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.bridge").tx.reset()
  cashed = false
  cash_out_calls = 0
  local refusing = wire_bridge({ "cash_out" })
  function refusing:send(msg)
    if msg.command == "actions/unregister" then
      self.log[#self.log + 1] = { kind = "unregister", names = msg.data.action_names }
      return false
    end
    return true
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  Dispatcher.handle_message(action_envelope("disp-unregister-refused", "cash_out", {}), refusing)
  check("a disposable action whose unregister the transport refuses is not executed (README.md:23-25)",
    cashed == false and #refusing.log == 2
      and refusing.log[1].kind == "unregister"
      and refusing.log[2].kind == "result" and refusing.log[2].ok == false)
end

do
  G.TIMERS.REAL = 1800
  require("tests.helpers").in_engine_state("ROUND_EVAL")
  G.STATE_COMPLETE, G.round_eval = true, true
  G.GAME = {
    dollars = 10, used_vouchers = {}, hands = {}, modifiers = {},
    current_round = { hands_left = 1, discards_left = 1 },
    round_resets = { ante = 1 },
  }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = require("tests.helpers").card_area({ cards = {}, highlighted = {} })
  Enforce.reset_run_state()
  G.NEURO = force_bridge({ dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL" })
  require("core.bridge").tx.reset()
  local executed, sends = false, 0
  G.FUNCS.cash_out = function() executed = true end
  local b = wire_bridge({ "cash_out" })
  local real_result = b.send_action_result
  function b:send_action_result(...)
    sends = sends + 1
    if sends == 1 then error("result serializer exploded") end
    return real_result(self, ...)
  end
  Dispatcher.handle_message(action_envelope("disp-send-fault", "cash_out", {}), b)
  check("a result-send throw aborts instead of executing an unacknowledged action",
    executed == false)
  check("a result-send throw pays the fallback result",
    b.log[#b.log] and b.log[#b.log].kind == "result" and b.log[#b.log].ok == false,
    "sends=" .. tostring(sends)
      .. " last=" .. tostring(b.log[#b.log] and b.log[#b.log].kind)
      .. "/" .. tostring(b.log[#b.log] and b.log[#b.log].ok))
end
do
  G.TIMERS.REAL = 1900
  require("core.bridge").tx.reset()
  local executed = false
  G.FUNCS.cash_out = function() executed = true end
  local b = wire_bridge({ "cash_out" })
  local first = true
  function b:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, msg = msg, reason = reason }
    if first then
      first = false
      require("core.bridge").tx.store(id, ok, msg, "cash_out", reason)
      return false, { status = "rejected" }
    end
    return true, { status = "written", written_at = G.TIMERS.REAL }
  end
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  require("core.bridge").tx.open("disp-result-rejected", "cash_out", 1900)
  Dispatcher.handle_message(action_envelope("disp-result-rejected", "cash_out", {}), b)
  check("a rejected admission frame aborts before mutation even with a cached verdict",
    executed == false, tostring(executed))
end

done()
