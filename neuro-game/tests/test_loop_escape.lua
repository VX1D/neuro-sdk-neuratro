require("tests.stubs").setup({ love = "timers", G = "timed" })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("loop-escape")

local Enforce = require("tests.helpers").enforce()
local ActionResult = require("core.action_result")
local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local ForceHelpers = require("force.force_helpers")
local Gate = require("core.gate")
local HandHandlers = require("handlers.hand_handlers")

local play_card = require("tests.helpers").play_card

local function open_proposal(indices, rendered)
  return assert(require("tests.helpers").open_proposal(indices, rendered))
end

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
  }
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
end

local function two_jokers()
  G.jokers = { cards = {
    { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
      config = { center = { key = "j_a", set = "Joker" } } },
    { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
      config = { center = { key = "j_b", set = "Joker" } } },
  }, config = { card_limit = 5 } }
end

local function armed_bridge()
  local b = require("tests.helpers").started_bridge(
    require("tests.helpers").stub_bridge({ emitted = {}, register_actions = "noop", is_transition_cooldown = "false" }))
  function b:send_context(msg) self.emitted[#self.emitted + 1] = tostring(msg) end
  return b
end

local function session_neuro(decision_serial, init_complete)
  return require("tests.helpers").started_bridge(require("tests.helpers").stub_bridge({
    enabled = true, decision_serial = decision_serial, transport_session = 1, _bridge_init_complete = init_complete,
    dispatcher = Dispatcher, actions = Actions, send_startup = "true", register_actions = "true" }))
end

local function arm_force()
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
end

do
  selecting_hand_env(100)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local all_passed = true
  for i = 1, 40 do
    arm_force()
    local ok = Enforce.pre_action(b, "play_hand", '{"indices":[' .. i .. ']}')
    if ok ~= true then all_passed = false break end
  end
  check("40 distinct selections never trip the repeat cap", all_passed)
end

do
  selecting_hand_env(200)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local last_ok, last_err, ignored, last_code
  for _ = 1, 31 do
    arm_force()
    last_ok, last_err, ignored, last_code = Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  check("an identical selection past the cap is still refused", last_ok ~= true, tostring(last_err))
  check("the refusal acknowledges instead of retrying the force",
    ActionResult.terminal(last_code, true) == true, tostring(last_code))

  arm_force()
  local ok_fresh = Enforce.pre_action(b, "play_hand", '{"indices":[3,4]}')
  check("a fresh selection passes immediately after the cap (no permanent lock)", ok_fresh == true)
end

local function arm_names(names)
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  local set = {}
  for _, n in ipairs(names) do set[n] = true end
  require("tests.helpers").open_force("SELECTING_HAND", names)
end

local ACTION_NAMES = {}
do
  for _, def in ipairs(require("core.action_registry").definitions()) do
    ACTION_NAMES[#ACTION_NAMES + 1] = def.name
  end
end

local function names_leaked(text)
  local leaked = {}
  for _, n in ipairs(ACTION_NAMES) do
    if tostring(text):find(n, 1, true) then leaked[#leaked + 1] = n end
  end
  return leaked
end

-- A refusal is reported immediately; it does not stage a result for later.
local function refusal_after_cap(force_names)
  local b = armed_bridge()
  local ok, message
  for _ = 1, 31 do
    arm_names(force_names)
    ok, message = Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  return ok, message
end

local function others_named(text)
  local out = {}
  for _, n in ipairs(names_leaked(text)) do
    if n ~= "play_hand" then out[#out + 1] = n end
  end
  return out
end

do
  selecting_hand_env(300)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local ok, refusal = refusal_after_cap({ "play_hand", "discard_hand" })
  check("the repeat refusal carries its reason in its own result", ok ~= true and type(refusal) == "string",
    tostring(refusal))
end

do
  local shapes = {
    { "play_hand", "discard_hand" },
    { "play_hand", "set_joker_order" },
    { "play_hand" },
  }
  for i, shape in ipairs(shapes) do
    selecting_hand_env(320 + i * 20)
    G.NEURO = { enabled = true, decision_serial = 1 }
    local _, refusal = refusal_after_cap(shape)
    check("O1." .. i .. ": a refusal is still produced for force " .. table.concat(shape, "+"),
      type(refusal) == "string", tostring(refusal))
    local leaked = others_named(refusal)
    check("O2." .. i .. ": it names no action but the refused one", #leaked == 0, table.concat(leaked, ", "))
  end

  selecting_hand_env(400)
  G.NEURO = { enabled = true, decision_serial = 1 }
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  require("tests.helpers").open_force("SHOP", { "buy_from_shop" })
  local b_other = armed_bridge()
  local other
  for _ = 1, 31 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    local _, message = Enforce.pre_action(b_other, "play_hand", '{"indices":[1,2]}')
    other = message
  end
  check("a force belonging to another screen still yields a refusal naming only the refused action",
    type(other) == "string" and #others_named(other) == 0, tostring(other))
end

do
  selecting_hand_env(380)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local last_ok
  for _ = 1, 31 do
    arm_names({ "play_hand" })
    last_ok = Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  check("RS1: the cap is latched before the reconnect", last_ok ~= true, tostring(last_ok))
  require("core.neuro_lifecycle").bump_run_generation("transport reconnected")
  arm_names({ "play_hand" })
  local ok_after = Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  check("RS2: the first send after a reconnect is not counted as a repeat",
    ok_after == true, tostring(ok_after))
end

do
  selecting_hand_env(390)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  for _ = 1, 45 do
    arm_names({ "play_hand" })
    Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  local name, count = Enforce.repeat_pressure()
  check("RP1: the pressure view names the capped action", name == "play_hand", tostring(name))
  check("RP2: the count stops at the cap instead of growing with refused sends",
    count == 30, tostring(count))
end

do
  selecting_hand_env(400)
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions }
  local b = require("tests.helpers").stub_bridge({ log = {}, register_actions = "noop", is_transition_cooldown = "false" })
  function b:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, reason = reason }
  end
  function b:send_context(msg) self.log[#self.log + 1] = { kind = "context", msg = tostring(msg) } end

  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  for i = 1, 31 do
    arm_force()
    Dispatcher.handle_message({ command = "action",
      data = { id = "loop-" .. i, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  end
  b.log = {}
  arm_force()
  Dispatcher.handle_message({ command = "action",
    data = { id = "loop-order", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local kinds = {}
  for _, event in ipairs(b.log) do kinds[#kinds + 1] = tostring(event.kind) end
  local trace = table.concat(kinds, " -> ")
  check("the action result is the first frame on the wire", kinds[1] == "result", trace)
  check("and it is the only frame -- no permanent context follows it",
    #b.log == 1, trace)
  check("strict resolution acknowledgements leave no failure record behind",
    G.NEURO.last_failed_action == nil, tostring(G.NEURO.last_failed_action))
end

do
  selecting_hand_env(500)
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions }
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })

  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "indices must have at most 5 item(s)"

  for i = 1, 31 do
    arm_force()
    Dispatcher.handle_message({ command = "action",
      data = { id = "stale-" .. i, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  end
  check("an acknowledged result clears the diagnostic failure record",
    G.NEURO.last_failed_action == nil, tostring(G.NEURO.last_failed_action))
end

do
  local function blocked_over(gen, calls)
    selecting_hand_env(700)
    G.NEURO = { enabled = true, decision_serial = 1 }
    local b = armed_bridge()
    local blocked = 0
    for i = 1, (calls or 60) do
      arm_force()
      if Enforce.pre_action(b, "play_hand", gen(i)) ~= true then blocked = blocked + 1 end
    end
    return blocked
  end

  local spellings = { '{"indices":[1,2]}', '{"indices": [1, 2]}', '{ "indices":[1,2] }' }
  check("whitespace variants of one selection still reach the cap",
    blocked_over(function(i) return spellings[(i % 3) + 1] end) > 0)
  check("a re-worded plan on one selection still reaches the cap",
    blocked_over(function(i)
      return '{"indices":[1,2],"plan":{"hand_plan":"variant ' .. i .. '"}}' end) > 0)
  check("an undeclared field does not split the streak",
    blocked_over(function(i) return '{"indices":[1,2],"zz":' .. i .. '}' end) > 0)
  check("key order does not split the streak",
    blocked_over(function(i)
      return (i % 2 == 0) and '{"indices":[1,2],"plan":{"hand_plan":"x"}}'
        or '{"plan":{"hand_plan":"x"},"indices":[1,2]}' end) > 0)
  check("genuinely different selections never reach the cap",
    blocked_over(function(i) return '{"indices":[' .. ((i % 5) + 1) .. ']}' end) == 0)
  check("junk between identical selections does not break their streak",
    blocked_over(function(i)
      return (i % 2 == 0) and '{"indices":[1,2]}' or 'not json at all' end, 80) > 0)
end

do
  selecting_hand_env(600)
  G.NEURO = session_neuro(1)
  local codes = {}
  local b = armed_bridge()
  b.send_action_result = function(_self, _id, _ok, _msg, reason)
    codes[#codes + 1] = tostring(reason)
    return true, { status = "written" }
  end
  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })

  arm_force()
  Dispatcher.handle_message({ command = "action",
    data = { id = "rc-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("the first selection arms a confirmation",
    codes[1] == "CONFIRMATION_REQUIRED", tostring(codes[1]))
  check("the latch is armed", Gate.proposal() ~= nil)

  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 2 }, b)
  check("reconnect drops the pending confirmation",
    Gate.proposal() == nil, tostring(Gate.proposal()))

  arm_force()
  Dispatcher.handle_message({ command = "action",
    data = { id = "rc-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("the identical resend is confirmed again, not committed",
    codes[#codes] == "CONFIRMATION_REQUIRED", tostring(codes[#codes]))
end

do
  selecting_hand_env(700)
  G.NEURO = { enabled = true, decision_serial = 9 }
  local HH = require("handlers.hand_handlers")
  open_proposal({ 1, 2 }, "Committing Pair A.")
  local first_pend = HH.pending()
  local first = first_pend and first_pend.indices
  check("the armed selection is announced",
    first and table.concat(first, ",") == "1,2", first and table.concat(first, ",") or "nil")

  local _, replace_error = HH.handle_play_hand({ indices = { 3, 4 } })
  local newest_pend = HH.pending()
  local newest = newest_pend and newest_pend.indices
  check("strict resolution prevents a different selection replacing the announcement",
    replace_error and replace_error.reason_code == "POLICY_ACKNOWLEDGED"
      and newest and table.concat(newest, ",") == "1,2",
    newest and table.concat(newest, ",") or "nil")
end

do
  selecting_hand_env(800)
  G.NEURO = session_neuro(3, true)
  open_proposal({ 1, 2 })
  G.NEURO.gates = { sell_joker = { key = "stale" } }
  local b = armed_bridge()
  b.send_action_result = function() end

  check("an unchanged transport_session preserves the play_hand confirmation",
    Gate.proposal() ~= nil, tostring(Gate.proposal()))
  check("it preserves delivered reviews too",
    G.NEURO.gates and G.NEURO.gates.sell_joker ~= nil, tostring(G.NEURO.gates))
end

do
  selecting_hand_env(1100)
  G.NEURO = session_neuro(4)
  G.NEURO.gates = { sell_joker = { key = "reviewed" } }
  open_proposal({ 1, 2 })
  G.NEURO.weak_fired_serial = 4
  require("core.neuro_lifecycle").clear_pending_confirm()
  check("clear_pending_confirm leaves no confirmation state behind",
    G.NEURO.weak_fired_serial == nil and G.NEURO.gates.sell_joker == nil and Gate.proposal() == nil)
end

do
  local SH = require("handlers.shop_handlers")
  _G.G.NEURO = { enabled = true, state = "SHOP", state_enter_serial = 5,
    run_generation = 1, shop_visit_epoch = 1 }
  _G.G.GAME = { dollars = 10, used_vouchers = {} }
  require("tests.helpers").in_engine_state("SHOP")
  _G.G.jokers = { cards = { { sort_id = 77, ability = { set = "Joker", name = "Bull" },
    config = { center = { name = "Bull" } } } }, config = { card_limit = 5 } }
  check("no sell confirmation means no line", SH.pending_sell_card_name() == nil)

  local _, review = SH.handle_sell_card({ area = "jokers", index = 1, name = "Bull" })
  require("core.gate").delivered(review)
  check("an armed sell confirmation names the joker",
    SH.pending_sell_card_name() ~= nil, tostring(SH.pending_sell_card_name()))

  G.NEURO.state_enter_serial = 6
  check("it expires with the shop visit it was armed in",
    SH.pending_sell_card_name() == nil, tostring(SH.pending_sell_card_name()))
end

do
  selecting_hand_env(1200)
  G.NEURO = session_neuro(2)
  local Staging = require("core.staging")
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "discard_hand" })

  arm_force()
  Dispatcher.route_message({ command = "action",
    data = { id = "stale-commit", name = "discard_hand", data = '{"indices":[1]}' } }, b)
  check("the action really is queued in staging", Staging.is_busy() == true,
    tostring(Staging.is_busy()))

  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 2 }, b)
  check("a reconnect cancels it instead of letting it commit later",
    Staging.is_busy() == false, tostring(Staging.is_busy()))
end

do
  selecting_hand_env(1300)
  G.NEURO = { enabled = true, decision_serial = 7 }
  local HH = require("handlers.hand_handlers")
  open_proposal({ 1, 2, 3 }, "Committing three cards.")
  check("the full latched hand is announced",
    #((HH.pending() or {}).indices or {}) == 3)

  table.remove(G.hand.cards, 3)
  check("losing one latched card announces nothing, not a subset the latch would refuse",
    HH.pending() == nil, tostring(HH.pending()))
end

do
  selecting_hand_env(1400)
  G.NEURO = { enabled = true, decision_serial = 7, weak_fired_serial = 7 }
  local HH = require("handlers.hand_handlers")
  open_proposal({ 1, 2 })
  local unchanged, unchanged_err = HH.handle_play_hand({ indices = { 1, 2 } })
  check("an unchanged resend does not commit",
    unchanged == nil and unchanged_err and unchanged_err.reason_code == "POLICY_ACKNOWLEDGED")

  G.hand.cards[1].base.value = "King"
  G.hand.cards[1].base.suit = "Clubs"
  check("a card mutated in place under a stable sort_id is confirmed again, not committed",
    HH.play_review_reason({ G.hand.cards[1], G.hand.cards[2] }, { 1, 2 }) ~= nil)
end

do
  selecting_hand_env(1600)
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions }
  G.NEURO.held_plan_write = { run_generation = 1, values = { money_plan = "hold" }, scopes = {} }
  Dispatcher.reset_run_state()
  check("resetting the dispatcher releases the held plan write",
    G.NEURO.held_plan_write == nil, tostring(G.NEURO.held_plan_write))
end

do
  _G.G = { NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 3, shop_visit_epoch = 1,
      shop_entry_dollars = 14 },
    FUNCS = {}, GAME = { current_round = {}, dollars = 3 },
    STATES = ES, STATE = ES.SHOP, TIMERS = { REAL = 100 } }
  local note = ForceHelpers.pending_gate_note({ "leave_shop", "buy_from_shop" })
  check("an armed window is announced before she bounces off it",
    note ~= "", note)

  require("tests.helpers").review("leave_shop")
  require("core.gate").acknowledge(require("core.gate").snapshot("leave_shop"))
  check("once acknowledged it stops being announced",
    ForceHelpers.pending_gate_note({ "leave_shop" }) == "",
    ForceHelpers.pending_gate_note({ "leave_shop" }))
end

do
  _G.G = { NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 1,
    joker_intents = {} },
    FUNCS = { toggle_shop = function() end },
    GAME = { dollars = 0, current_round = { reroll_cost = 99 }, used_vouchers = {} },
    STATES = ES, STATE = ES.SHOP, TIMERS = { REAL = 100 },
    shop = {}, shop_jokers = { cards = {} }, shop_booster = { cards = {} },
    shop_vouchers = { cards = {} }, consumeables = { cards = {}, config = { card_limit = 2 } },
    jokers = { cards = { { sort_id = 91, ability = { set = "Joker", name = "Bull", eternal = true },
      config = { center = { name = "Bull" } }, cost = 4, sell_cost = 2 } }, config = { card_limit = 5 } },
    hand = { cards = {}, config = { card_limit = 8 } }, deck = { cards = {} } }
  local untagged = require("facts.card_util").untagged_joker_count()
  check("the fixture really is a shop with an untagged joker", untagged > 0, tostring(untagged))
  check("leave_shop stays on offer while a joker is untagged",
    require("core.actions").is_action_valid("leave_shop") == true)
  local ok_r, routed = pcall(require("force.force_router").get_force_for_state, "SHOP")
  check("a force is still produced instead of silence",
    ok_r and routed ~= nil and routed.actions ~= nil, tostring(ok_r) .. " " .. tostring(routed))
  local names = {}
  for _, n in ipairs((routed and routed.actions) or {}) do names[#names + 1] = n end
  check("and it offers the disposable exit first, the reusable tagging tool beside it",
    names[1] == "leave_shop" and table.concat(names, ","):find("record_joker_roles", 1, true) ~= nil,
    table.concat(names, ","))
  local bare, why = Dispatcher.preflight("leave_shop", {})
  check("leaving untagged is refused",
    bare == nil, tostring(why))
  local tagged = Dispatcher.preflight("leave_shop", { intents = { { index = 1, tag = "CORE" } } })
  check("leaving with every untagged joker in `intents` is admitted", type(tagged) == "function", tostring(tagged))
  local partial = Dispatcher.preflight("leave_shop", { intents = { { index = 2, tag = "CORE" } } })
  check("an out-of-range intent is refused before anything runs", partial == nil)
end

do
  local function blocked_over(action, gen, calls)
    selecting_hand_env(1700)
    G.NEURO = { enabled = true, decision_serial = 1 }
    local b = armed_bridge()
    local blocked = 0
    for i = 1, (calls or 60) do
      G.TIMERS.REAL = G.TIMERS.REAL + 100
      require("tests.helpers").open_force("SELECTING_HAND", { action })
      if Enforce.pre_action(b, action, gen(i)) ~= true then blocked = blocked + 1 end
    end
    return blocked
  end

  check("reordered indices are one selection, not two",
    blocked_over("play_hand", function(i)
      return (i % 2 == 0) and '{"indices":[1,2]}' or '{"indices":[2,1]}' end) > 0)
  check("reordered hand_indices are one selection",
    blocked_over("choose_pack_card", function(i)
      return (i % 2 == 0) and '{"area":"consumeables","index":1,"hand_indices":[1,2]}'
        or '{"area":"consumeables","index":1,"hand_indices":[2,1]}' end) > 0)
  check("reordered intents are one tagging",
    blocked_over("record_joker_roles", function(i)
      return (i % 2 == 0) and '{"intents":[{"index":1,"tag":"CORE"},{"index":2,"tag":"HOLD"}]}'
        or '{"intents":[{"index":2,"tag":"HOLD"},{"index":1,"tag":"CORE"}]}' end) > 0)
  check("a repeated unparseable payload is capped like any other repeat",
    blocked_over("play_hand", function() return '{"indices":[1,null,2]}' end) > 0)
  check("a stream of varying malformed payloads is capped too",
    blocked_over("play_hand", function(i) return '{"bad":' .. i end) > 0)
  check("malformed sends do not consume the streak of a real selection",
    blocked_over("play_hand", function(i)
      return (i % 2 == 0) and '{"indices":[1,2]}' or ('{"bad":' .. i) end, 80) > 0)
end

do
  selecting_hand_env(1800)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  Enforce.pre_action(b, "set_joker_order", nil)
  check("the repeat warning stays quiet on the first send",
    ForceHelpers.repeat_pressure_note({ "set_joker_order" }) == "", ForceHelpers.repeat_pressure_note({ "set_joker_order" }))
  for _ = 1, 3 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b, "set_joker_order", nil)
  end
  local note = ForceHelpers.repeat_pressure_note({ "set_joker_order" })
  check("it speaks up once the next identical send would be refused",
    note ~= "", note)
end

do
  selecting_hand_env(1850)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local spoke_at = {}
  for i = 1, 4 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b, "set_joker_order", nil)
    spoke_at[i] = ForceHelpers.repeat_pressure_note({ "set_joker_order" }) ~= ""
  end
  check("silent while another identical send would still be accepted",
    spoke_at[1] == false and spoke_at[2] == false, table.concat({
      tostring(spoke_at[1]), tostring(spoke_at[2]) }, ","))
  check("speaks exactly when the next identical send is refused",
    spoke_at[3] == true, tostring(spoke_at[3]))
end

do
  selecting_hand_env(1900)
  G.NEURO = { enabled = true, decision_serial = 5, dispatcher = Dispatcher, actions = Actions }
  local b = armed_bridge()
  local wire = {}
  b.send_action_result = require("tests.helpers").result_log(wire, { "_", "ok", "_", "reason" })
  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  open_proposal({ 1, 2 }, "Committing Pair.")

  G.NEURO.llm_paused = true
  Dispatcher.route_message({ command = "action",
    data = { id = "paused-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  G.NEURO.llm_paused = nil

  check("the paused answer carries an acknowledging code, which is what keeps it success=true",
    wire[1] and wire[1].ok == true
      and ActionResult.terminal(wire[1].reason, true) == true,
    tostring(wire[1] and wire[1].reason))
  check("a paused action does not advance the decision",
    G.NEURO.decision_serial == 5, tostring(G.NEURO.decision_serial))
  check("the pending confirmation survives the pause",
    require("handlers.hand_handlers").pending() ~= nil)
  check("the paused reply marks its id answered", require("core.bridge").tx.get("paused-1") == true)
  Dispatcher.route_message({ command = "action",
    data = { id = "paused-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("so a redelivery of that id earns no second result", #wire == 1, #wire)
end

do
  local AR = require("core.action_result")
  check("both are declared as real failures (success=false, as in Action.cs:52-60), not merely absent from the table",
    AR.terminal("ACTION_UNREGISTERED", true) == false and AR.terminal("ACTION_UNKNOWN", true) == false)
  check("ActionResult.error accepts them instead of asserting",
    (pcall(ActionResult.error, "ACTION_UNKNOWN", "x")) == true)

  selecting_hand_env(2050)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local _, _, terminal, code = Enforce.pre_action(b, "no_such_action_at_all")
  check("a settled refusal is retried (success=false)",
    code == "ACTION_UNAVAILABLE" and terminal == false, tostring(code) .. "/" .. tostring(terminal))

  local gapped = armed_bridge()
  gapped.is_transition_cooldown = function() return true end
  local _, _, terminal_t, code_t = Enforce.pre_action(gapped, "play_hand", '{"indices":[1,2]}')
  check("and a momentary one outside a force is retried too",
    code_t == "TRANSITION_PENDING" and terminal_t == false, tostring(code_t) .. "/" .. tostring(terminal_t))
end

do
  selecting_hand_env(2000)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local blocked = 0
  for i = 1, 12 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    require("tests.helpers").open_force("SELECTING_HAND", { "set_joker_order" })
    if Enforce.pre_action(b, "set_joker_order", (i % 2 == 0) and nil or "{}") ~= true then
      blocked = blocked + 1
    end
  end
  check("an omitted payload and an empty object are one decision, not two", blocked > 0)
end

do
  selecting_hand_env(2100)
  G.NEURO = { enabled = true, decision_serial = 4, run_generation = 1 }
  open_proposal({ 1 })
  require("core.neuro_lifecycle").reset_run_state()
  check("a new run inherits no confirmation state from the old one",
    Gate.proposal() == nil, tostring(Gate.proposal()))
end

do
  selecting_hand_env(2300)
  G.NEURO = session_neuro(2, true)
  local Staging = require("core.staging")
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.bridge").tx.reset()
  require("tests.helpers").stage_registered(nil, { "discard_hand" })
  require("tests.helpers").open_force("SELECTING_HAND", { "discard_hand" })
  Dispatcher.route_message({ command = "action",
    data = { id = "dup-sess", name = "discard_hand", data = '{"indices":[1]}' } }, b)
  check("the action is queued", Staging.is_busy() == true)
  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 1 }, b)
  check("a duplicate reregister on the same transport keeps the queued action",
    Staging.is_busy() == true, tostring(Staging.is_busy()))
  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 2 }, b)
  check("a real transport change still cancels it",
    Staging.is_busy() == false, tostring(Staging.is_busy()))
end

do
  selecting_hand_env(2600)
  G.NEURO = { enabled = true, decision_serial = 5, once_serials = {}, state_enter_serial = 1 }
  G.GAME.blind = { chips = 300, debuff = {}, config = { blind = {} } }
  local HH = require("handlers.hand_handlers")
  local GOLDEN = "Committing Pair -- Use the currently offered resolve_play action with answer yes or no."
  open_proposal({ 1, 2 }, GOLDEN)

  local pending = require("handlers.hand_handlers").pending()
  check("the confirmation the sentence describes is actually open",
    type(pending) == "table" and table.concat(pending.indices, ",") == "1,2", tostring(pending))
end

done()
