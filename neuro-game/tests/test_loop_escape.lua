_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("loop-escape")

local Enforce = require("core.enforce")
local ActionResult = require("core.action_result")
local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local FS = require("core.force_state")
local ForceHelpers = require("force.force_helpers")

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
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
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
  }
  require("core.transition_guard").reset()
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
  local b = { emitted = {} }
  function b:send_context(msg) self.emitted[#self.emitted + 1] = tostring(msg) end
  b.register_actions = function() end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

local function arm_force()
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.NEURO.force_inflight = false
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
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
  local last_ok, last_err, last_code
  for _ = 1, 31 do
    arm_force()
    last_ok, last_err, _, last_code = Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  check("an identical selection past the cap is still refused", last_ok ~= true, tostring(last_err))
  check("the refusal acknowledges instead of retrying the force",
    ActionResult.acknowledges(last_code) == true, tostring(last_code))

  arm_force()
  local ok_fresh = Enforce.pre_action(b, "play_hand", '{"indices":[3,4]}')
  check("a fresh selection passes immediately after the cap (no permanent lock)", ok_fresh == true)
end

local function arm_names(names)
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.NEURO.force_inflight = false
  local set = {}
  for _, n in ipairs(names) do set[n] = true end
  FS.arm("SELECTING_HAND", names, set, 1)
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

local function correction_after_cap(force_names)
  local b = armed_bridge()
  for _ = 1, 31 do
    arm_names(force_names)
    Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  end
  return Enforce.take_correction()
end

do
  selecting_hand_env(300)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local correction = correction_after_cap({ "play_hand", "discard_hand" })
  check("the repeat refusal stages a correction", type(correction) == "string", tostring(correction))
  check("the correction names the past event",
    tostring(correction):find("wasn't applied", 1, true) ~= nil, tostring(correction))
  check("it does not restate what is callable on the retained channel",
    tostring(correction):find("Actions you can take now", 1, true) == nil, tostring(correction))
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
    local correction = correction_after_cap(shape)
    check("O1." .. i .. ": a correction is still produced for force " .. table.concat(shape, "+"),
      type(correction) == "string", tostring(correction))
    local leaked = names_leaked(correction)
    check("O2." .. i .. ": it names no action at all", #leaked == 0, table.concat(leaked, ", "))
  end

  selecting_hand_env(400)
  G.NEURO = { enabled = true, decision_serial = 1 }
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.NEURO.force_inflight = false
  FS.arm("SHOP", { "buy_from_shop" }, { buy_from_shop = true }, 1)
  local b_other = armed_bridge()
  for _ = 1, 31 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b_other, "play_hand", '{"indices":[1,2]}')
  end
  local other = Enforce.take_correction()
  check("a force belonging to another screen still yields only the past-event sentence",
    type(other) == "string" and #names_leaked(other) == 0, tostring(other))
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
  FS.reconnect()
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
  local b = { log = {} }
  function b:send_action_result(id, ok, msg, reason)
    self.log[#self.log + 1] = { kind = "result", id = id, ok = ok, reason = reason }
  end
  function b:send_context(msg) self.log[#self.log + 1] = { kind = "context", msg = tostring(msg) } end
  b.register_actions = function() end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end

  require("core.tx_cache").reset()
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
  local correction = G.NEURO.last_failed_correction
  check("the correction is on the ephemeral force channel instead",
    type(correction) == "string" and correction ~= ""
      and ForceHelpers.failed_action_warning():find(correction, 1, true) ~= nil,
    tostring(correction) .. " || " .. ForceHelpers.failed_action_warning())
end

do
  selecting_hand_env(500)
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions }
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })

  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "indices must have at most 5 item(s)"
  G.NEURO.last_failed_at = 1
  check("the warning is present before the acknowledged answer",
    ForceHelpers.failed_action_warning():find("Previous action rejected", 1, true) ~= nil)

  for i = 1, 31 do
    arm_force()
    Dispatcher.handle_message({ command = "action",
      data = { id = "stale-" .. i, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  end
  check("an acknowledged result expires the stale rejection warning",
    G.NEURO.last_failed_action == nil, tostring(G.NEURO.last_failed_action))
  check("the force query stops carrying it", ForceHelpers.failed_action_warning() == "",
    ForceHelpers.failed_action_warning())
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
  G.NEURO = { enabled = true, decision_serial = 1, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local codes = {}
  local b = armed_bridge()
  b.send_action_result = function(_self, _id, _ok, _msg, reason)
    codes[#codes + 1] = tostring(reason)
  end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })

  arm_force()
  Dispatcher.handle_message({ command = "action",
    data = { id = "rc-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("the first selection arms a confirmation",
    codes[1] == "CONFIRMATION_REQUIRED", tostring(codes[1]))
  check("the latch is armed", G.NEURO.play_confirm ~= nil)

  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 2 }, b)
  check("reconnect drops the pending confirmation",
    G.NEURO.play_confirm == nil, tostring(G.NEURO.play_confirm))

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
  G.NEURO.play_confirm = { signature = "1,2", content = "c12", indices = { 1, 2 },
    decision_serial = 9, run_generation = 0 }
  local first_pend = HH.pending()
  local first = first_pend and first_pend.indices
  check("the armed selection is announced",
    first and table.concat(first, ",") == "1,2", first and table.concat(first, ",") or "nil")

  G.NEURO.play_confirm = { signature = "3,4", content = "c34", indices = { 3, 4 },
    decision_serial = 9, run_generation = 0 }
  local newest_pend = HH.pending()
  local newest = newest_pend and newest_pend.indices
  check("arming a different selection replaces the announcement outright -- one slot, not two",
    newest and table.concat(newest, ",") == "3,4", newest and table.concat(newest, ",") or "nil")
end

do
  selecting_hand_env(800)
  G.NEURO = { enabled = true, decision_serial = 3, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  G.NEURO.play_confirm = { signature = "1,2", content = "c12", indices = { 1, 2 },
    decision_serial = 3, run_generation = 0 }
  G.NEURO.last_sell_reject = "sell:0:7"
  local b = armed_bridge()
  b.send_action_result = function() end

  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 1 }, b)
  check("an unchanged transport_session still drops the play_hand confirmation",
    G.NEURO.play_confirm == nil, tostring(G.NEURO.play_confirm))
  check("it drops the pending sell confirmation too",
    G.NEURO.last_sell_reject == nil, tostring(G.NEURO.last_sell_reject))
end

do
  selecting_hand_env(900)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  Enforce.pre_action(b, "play_hand", '{"indices":[1,2]}')
  Enforce.take_correction()
  G.TIMERS.REAL = G.TIMERS.REAL + 0.05
  Enforce.pre_action(b, "discard_hand", '{"indices":[3]}')
  local correction = Enforce.take_correction()
  check("a global-gap refusal is reported",
    type(correction) == "string" and correction:find("slow down", 1, true) ~= nil,
    tostring(correction))
  check("it does not advertise actions that are equally gapped",
    tostring(correction):find("Actions you can take now", 1, true) == nil, tostring(correction))
end

do
  selecting_hand_env(1000)
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions }
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  arm_force()
  G.NEURO.last_failed_action = "play_hand"
  G.NEURO.last_failed_reason = "indices must have at most 5 item(s)"
  G.NEURO.last_failed_at = G.TIMERS.REAL
  Dispatcher.handle_message({ command = "action",
    data = { id = "fresh-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("a failure younger than defer_window survives the next answer",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
end

do
  selecting_hand_env(1100)
  G.NEURO = { enabled = true, decision_serial = 4, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  G.NEURO.last_sell_reject = "x"
  G.NEURO.play_confirm = "x"
  G.NEURO.weak_fired_serial = 4
  require("core.neuro_lifecycle").clear_pending_confirm()
  local leftover = {}
  for _, field in ipairs({ "play_confirm", "weak_fired_serial", "last_sell_reject" }) do
    if G.NEURO[field] ~= nil then leftover[#leftover + 1] = field end
  end
  check("clear_pending_confirm leaves no confirmation field behind",
    #leftover == 0, table.concat(leftover, ", "))
end

do
  local SH = require("handlers.shop_handlers")
  _G.G.NEURO = { enabled = true, state_enter_serial = 5 }
  _G.G.jokers = { cards = { { sort_id = 77, ability = { set = "Joker", name = "Bull" },
    config = { center = { name = "Bull" } } } }, config = { card_limit = 5 } }
  check("no sell confirmation means no line", SH.pending_sell_card_name() == nil)

  G.NEURO.last_sell_reject = "sell:5:77"
  check("an armed sell confirmation names the joker",
    SH.pending_sell_card_name() ~= nil, tostring(SH.pending_sell_card_name()))

  G.NEURO.state_enter_serial = 6
  check("it expires with the shop visit it was armed in",
    SH.pending_sell_card_name() == nil, tostring(SH.pending_sell_card_name()))
end

do
  selecting_hand_env(1200)
  G.NEURO = { enabled = true, decision_serial = 2, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local Staging = require("core.staging")
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "discard_hand" })

  arm_force()
  Staging.queue({ command = "action",
    data = { id = "stale-commit", name = "discard_hand", data = '{"indices":[1]}' } }, b)
  check("the action really is queued in staging", Staging.is_busy() == true,
    tostring(Staging.is_busy()))

  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 2 }, b)
  check("a reconnect cancels it instead of letting it commit later",
    Staging.is_busy() == false, tostring(Staging.is_busy()))
end

do
  selecting_hand_env(1300)
  G.NEURO = { enabled = true, decision_serial = 7 }
  local HH = require("handlers.hand_handlers")
  local sel = { G.hand.cards[1], G.hand.cards[2], G.hand.cards[3] }
  G.NEURO.play_confirm = { signature = HH.play_signature(sel), content = HH.play_content(sel),
    indices = { 1, 2, 3 }, decision_serial = 7, run_generation = 0 }
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
  local sel = { G.hand.cards[1], G.hand.cards[2] }
  G.NEURO.play_confirm = { signature = HH.play_signature(sel), content = HH.play_content(sel),
    indices = { 1, 2 }, decision_serial = 7, run_generation = 0 }
  check("an unchanged resend still commits",
    HH.play_confirm_reject(sel, { 1, 2 }) == nil)

  G.hand.cards[1].base.value = "King"
  G.hand.cards[1].base.suit = "Clubs"
  check("a card mutated in place under a stable sort_id is confirmed again, not committed",
    HH.play_confirm_reject({ G.hand.cards[1], G.hand.cards[2] }, { 1, 2 }) ~= nil)
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
  _G.G = { NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 3,
    _decision_windows = {} }, FUNCS = {}, GAME = { current_round = {} },
    STATES = { BUFFOON_PACK = 9 }, STATE = 9, TIMERS = { REAL = 100 } }
  local DW = require("core.decision_window")
  DW.reset_field("pack_review")
  local note = ForceHelpers.pending_gate_note({ "use_card", "skip_booster" })
  check("an armed window is announced before she bounces off it",
    note:find("use_card", 1, true) ~= nil and note:find("confirmation", 1, true) ~= nil, note)

  DW.evaluate("use_card", nil)
  DW.acknowledge("use_card")
  check("once acknowledged it stops being announced",
    ForceHelpers.pending_gate_note({ "use_card" }) == "",
    ForceHelpers.pending_gate_note({ "use_card" }))
end

do
  _G.G = { NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 1,
    _decision_windows = {}, joker_intents = {} },
    FUNCS = { toggle_shop = function() end },
    GAME = { dollars = 0, current_round = { reroll_cost = 99 }, used_vouchers = {} },
    STATES = { SHOP = 5 }, STATE = 5, TIMERS = { REAL = 100 },
    shop = {}, shop_jokers = { cards = {} }, shop_booster = { cards = {} },
    shop_vouchers = { cards = {} }, consumeables = { cards = {}, config = { card_limit = 2 } },
    jokers = { cards = { { sort_id = 91, ability = { set = "Joker", name = "Bull", eternal = true },
      config = { center = { name = "Bull" } }, cost = 4, sell_cost = 2 } }, config = { card_limit = 5 } },
    hand = { cards = {}, config = { card_limit = 8 } }, deck = { cards = {} } }
  local untagged = require("facts.card_util").untagged_joker_count()
  check("the fixture really is a shop with an untagged joker", untagged > 0, tostring(untagged))
  check("toggle_shop is withheld until tagging is done",
    require("core.actions").is_action_valid("toggle_shop") == false)
  local ok_r, routed = pcall(require("force.force_router").get_force_for_state, "SHOP")
  check("a force is still produced instead of silence",
    ok_r and routed ~= nil and routed.actions ~= nil, tostring(ok_r) .. " " .. tostring(routed))
  local names = {}
  for _, n in ipairs((routed and routed.actions) or {}) do names[#names + 1] = n end
  check("and it offers the action that actually unblocks the shop",
    table.concat(names, ","):find("set_joker_intents", 1, true) ~= nil, table.concat(names, ","))
end

do
  local function blocked_over(action, gen, calls)
    selecting_hand_env(1700)
    G.NEURO = { enabled = true, decision_serial = 1 }
    local b = armed_bridge()
    local blocked = 0
    for i = 1, (calls or 60) do
      G.TIMERS.REAL = G.TIMERS.REAL + 100
      G.NEURO.force_inflight = false
      FS.arm("SELECTING_HAND", { action }, { [action] = true }, 1)
      if Enforce.pre_action(b, action, gen(i)) ~= true then blocked = blocked + 1 end
    end
    return blocked
  end

  check("reordered indices are one selection, not two",
    blocked_over("play_hand", function(i)
      return (i % 2 == 0) and '{"indices":[1,2]}' or '{"indices":[2,1]}' end) > 0)
  check("reordered hand_indices are one selection",
    blocked_over("use_card", function(i)
      return (i % 2 == 0) and '{"area":"consumeables","index":1,"hand_indices":[1,2]}'
        or '{"area":"consumeables","index":1,"hand_indices":[2,1]}' end) > 0)
  check("reordered intents are one tagging",
    blocked_over("set_joker_intents", function(i)
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
    ForceHelpers.repeat_pressure_note() == "", ForceHelpers.repeat_pressure_note())
  for _ = 1, 3 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b, "set_joker_order", nil)
  end
  local note = ForceHelpers.repeat_pressure_note()
  check("it speaks up once the next identical send would be refused",
    note ~= "" and note:find("set_joker_order", 1, true) ~= nil, note)
  check("and it never quotes an ordinal it recomputes from live state",
    note:find("th identical", 1, true) == nil, note)
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
    spoke_at[i] = ForceHelpers.repeat_pressure_note() ~= ""
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
  b.send_action_result = function(_self, _id, ok, _msg, reason)
    wire[#wire + 1] = { ok = ok, reason = reason }
  end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  G.NEURO.force_inflight = false
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  G.NEURO.play_confirm = { signature = "1,2", content = require("handlers.hand_handlers").play_content(
    { G.hand.cards[1], G.hand.cards[2] }), indices = { 1, 2 }, decision_serial = 5, run_generation = 0 }

  G.NEURO.llm_paused = true
  Dispatcher.route_message({ command = "action",
    data = { id = "paused-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  G.NEURO.llm_paused = nil

  check("the paused answer carries an acknowledging code, which is what keeps it success=true",
    wire[1] and wire[1].ok == true
      and ActionResult.acknowledges(wire[1].reason) == true,
    tostring(wire[1] and wire[1].reason))
  check("a paused action does not advance the decision",
    G.NEURO.decision_serial == 5, tostring(G.NEURO.decision_serial))
  check("the pending confirmation survives the pause",
    require("handlers.hand_handlers").pending() ~= nil)
  local cached = require("core.tx_cache").get("paused-1")
  check("the paused reply is retained so a redelivery replays it",
    cached ~= nil and tostring(cached.message or cached.msg or ""):find("Paused", 1, true) ~= nil,
    tostring(cached and (cached.message or cached.msg)))
end

do
  local CODES = require("core.action_result").CODES
  check("ACTION_UNREGISTERED is declared", CODES.ACTION_UNREGISTERED ~= nil)
  check("ACTION_UNKNOWN is declared", CODES.ACTION_UNKNOWN ~= nil)
  check("both are declared as real failures, not merely absent from the table",
    CODES.ACTION_UNREGISTERED.acknowledge == true
      and CODES.ACTION_UNKNOWN.acknowledge == nil
      and CODES.ACTION_UNREGISTERED.transient == false)
  check("ActionResult.error accepts them instead of asserting",
    (pcall(ActionResult.error, "ACTION_UNKNOWN", "x")) == true)
end

do
  local AR = require("core.action_result")
  check("with no per-send opinion the class answers",
    AR.is_transient("TRANSITION_PENDING") == true
      and AR.is_transient("POLICY_REJECTED") == false)
  check("a per-send value overrides the class in both directions",
    AR.is_transient("TRANSITION_PENDING", { transient = false }) == false
      and AR.is_transient("POLICY_REJECTED", { transient = true }) == true)
  check("opts without the field falls back to the class",
    AR.is_transient("TRANSITION_PENDING", { acknowledged = true }) == true)
  check("an unknown or absent code is not transient",
    AR.is_transient(nil) == false and AR.is_transient("no_such_code") == false)

  selecting_hand_env(2050)
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local _, _, transient, code = Enforce.pre_action(b, "no_such_action_at_all")
  check("a settled refusal reports the flag its own code declares",
    code == "ACTION_UNAVAILABLE" and transient == AR.is_transient(code) and transient == false,
    tostring(code) .. "/" .. tostring(transient))

  local gapped = armed_bridge()
  gapped.is_transition_cooldown = function() return true end
  local _, _, transient_t, code_t = Enforce.pre_action(gapped, "play_hand", '{"indices":[1,2]}')
  check("and a momentary one reports the flag its own code declares",
    code_t == "TRANSITION_PENDING" and transient_t == AR.is_transient(code_t) and transient_t == true,
    tostring(code_t) .. "/" .. tostring(transient_t))
end

do
  selecting_hand_env(2000)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local blocked = 0
  for i = 1, 12 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    G.NEURO.force_inflight = false
    FS.arm("SELECTING_HAND", { "set_joker_order" }, { set_joker_order = true }, 1)
    if Enforce.pre_action(b, "set_joker_order", (i % 2 == 0) and nil or "{}") ~= true then
      blocked = blocked + 1
    end
  end
  check("an omitted payload and an empty object are one decision, not two", blocked > 0)
end

do
  selecting_hand_env(2100)
  G.NEURO = { enabled = true, decision_serial = 4, run_generation = 1 }
  G.NEURO.play_confirm = { signature = "old", content = "old", indices = { 1 } }
  require("core.neuro_lifecycle").reset_run_state()
  local leftover = {}
  for _, f in ipairs({ "play_confirm" }) do
    if G.NEURO[f] ~= nil then leftover[#leftover + 1] = f end
  end
  check("a new run inherits no confirmation state from the old one",
    #leftover == 0, table.concat(leftover, ", "))
end

do
  selecting_hand_env(2200)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  for _ = 1, 5 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b, "set_joker_order", nil)
  end
  check("a refusal really did stage a correction", Enforce.take_correction() ~= nil)
  for _ = 1, 5 do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    Enforce.pre_action(b, "set_joker_order", nil)
  end
  Enforce.reset_run_state()
  check("a staged correction does not survive into the next run",
    Enforce.take_correction() == nil, tostring(Enforce.take_correction()))
end

do
  selecting_hand_env(2300)
  G.NEURO = { enabled = true, decision_serial = 2, transport_session = 1,
    dispatcher = Dispatcher, actions = Actions }
  local Staging = require("core.staging")
  local b = armed_bridge()
  b.send_action_result = function() end
  require("core.tx_cache").reset()
  require("tests.helpers").stage_registered(nil, { "discard_hand" })
  G.NEURO.force_inflight = false
  FS.arm("SELECTING_HAND", { "discard_hand" }, { discard_hand = true }, 1)
  Staging.queue({ command = "action",
    data = { id = "dup-sess", name = "discard_hand", data = '{"indices":[1]}' } }, b)
  check("the action is queued", Staging.is_busy() == true)
  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 1 }, b)
  check("a duplicate reregister on the same transport keeps the queued action",
    Staging.is_busy() == true, tostring(Staging.is_busy()))
  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 2 }, b)
  check("a real transport change still cancels it",
    Staging.is_busy() == false, tostring(Staging.is_busy()))
end

do
  selecting_hand_env(2400)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  local b = armed_bridge()
  local function send(payload)
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    return Enforce.pre_action(b, "set_joker_order", payload) == true
  end

  local allowed = 0
  while allowed < 50 and send("not json at all") do allowed = allowed + 1 end
  check("a run of malformed sends is capped", allowed > 0 and allowed < 50, tostring(allowed))

  selecting_hand_env(2500)
  two_jokers()
  G.NEURO = { enabled = true, decision_serial = 1 }
  b = armed_bridge()
  local pre = true
  for _ = 1, allowed do pre = pre and send("not json at all") end
  check("the same run is accepted up to the cap", pre == true)
  check("a payload that parses is accepted after that run", send(nil) == true)

  local post = true
  for _ = 1, allowed do post = post and send("not json at all") end
  check("the junk counter restarts from zero after a payload that parsed", post == true)
  check("and the cap still fires on the restarted run", send("not json at all") == false)

  local function refuse_msg()
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    local _, msg = Enforce.pre_action(b, "set_joker_order", "not json at all")
    return tonumber((tostring(msg):match("repeated (%d+) times")))
  end
  local first = refuse_msg()
  for _ = 1, 20 do refuse_msg() end
  local later = refuse_msg()
  check("the refused junk count the message quotes stops at the cap",
    first == allowed and later == allowed,
    tostring(allowed) .. ": " .. tostring(first) .. " -> " .. tostring(later))
end

do
  selecting_hand_env(2600)
  G.NEURO = { enabled = true, decision_serial = 5, once_serials = {}, state_enter_serial = 1 }
  G.GAME.blind = { chips = 300, debuff = {}, config = { blind = {} } }
  G.NEURO.play_confirm = { signature = "1,2", content = require("handlers.hand_handlers").play_content(
    { G.hand.cards[1], G.hand.cards[2] }), indices = { 1, 2 }, decision_serial = 5, run_generation = 0 }

  local pending = require("handlers.hand_handlers").pending()
  check("the confirmation the sentence describes is actually open",
    type(pending) == "table" and table.concat(pending.indices, ",") == "1,2", tostring(pending))

  local q = (require("force.force_selecting_hand").build() or {}).query or ""
  local GOLDEN = "A play_hand confirmation is open for indices [1,2];"
    .. " any other selection gets its own confirmation first. "
  check("the force states the open confirmation verbatim", q:find(GOLDEN, 1, true) ~= nil, q)

  G.NEURO.play_confirm = nil
  local q2 = (require("force.force_selecting_hand").build() or {}).query or ""
  check("the force really was rebuilt after the latch was cleared",
    q2:find("State: SELECTING_HAND.", 1, true) ~= nil, q2)
  check("and says nothing about an open confirmation when none is",
    q2:find("A play_hand confirmation is open", 1, true) == nil, q2)
end

done()
