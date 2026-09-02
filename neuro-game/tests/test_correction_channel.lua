_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("correction-channel")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local TxCache = require("core.tx_cache")
local ForceHelpers = require("force.force_helpers")
local Orchestrator = require("core.orchestrator")
local ContextDelivery = require("core.context_delivery")

local retained = {}

local TICKS = 4

local function ticks(n)
  for _ = 1, (n or TICKS) do pcall(Orchestrator._step_neuro_frame, 0.016) end
end

local function channel_sig(b)
  local rows = {}
  for id, text in pairs(ContextDelivery._delivered() or {}) do
    rows[#rows + 1] = "delivered " .. tostring(id) .. " => " .. tostring(text)
  end
  table.sort(rows)
  return table.concat(rows, "\n")
    .. "\n-- send_context --\n" .. table.concat(retained, "\n")
    .. "\n-- bridge --\n" .. table.concat((b and b.emitted) or {}, "\n")
end

local function settle(b)
  ticks()
  return channel_sig(b)
end

local function bridge()
  local b = { emitted = {}, results = {}, registered = 0 }
  function b:send_context(msg) self.emitted[#self.emitted + 1] = tostring(msg) return true end
  function b:send_action_result(id, ok, message, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason = reason }
  end
  b.register_actions = function() b.registered = b.registered + 1 end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t)
  require("tests.helpers").selecting_hand_env({
    time = t, states = { SELECTING_HAND = 4, SHOP = 5 }, reset_tx_cache = true,
  })
  retained = {}
end

local function neuro(b)
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
    dispatcher = Dispatcher, actions = Actions, update = function() end,
    send_context = function(_, msg) retained[#retained + 1] = tostring(msg) return true end }
  require("tests.helpers").stage_registered("SELECTING_HAND", { "buy_from_shop", "leave_shop" })
  G.NEURO.force_inflight = false
  return b
end

do
  selecting_hand_env(100)
  local b = neuro(bridge())
  local before = settle(b)
  Dispatcher.route_message({ command = "action",
    data = { id = "cc-1", name = "buy_from_shop", data = '{"area":"shop_jokers","index":1}' } }, b)

  local last = b.results[#b.results]
  check("the refusal is answered on the action result",
    last ~= nil and last.id == "cc-1" and last.ok == false, last and tostring(last.reason) or "none")
  check("and nothing at all is spent on the retained context channel",
    channel_sig(b) == before, channel_sig(b))
  check("the correction is stored for the ephemeral force record and names where it works",
    type(G.NEURO.last_failed_correction) == "string"
      and G.NEURO.last_failed_correction:find("works in SHOP", 1, true) ~= nil
      and G.NEURO.last_failed_correction:find("this is SELECTING_HAND", 1, true) ~= nil,
    tostring(G.NEURO.last_failed_correction))
  check("and the next force query carries it",
    ForceHelpers.failed_action_warning():find("works in SHOP", 1, true) ~= nil,
    ForceHelpers.failed_action_warning())
  check("the enforce staging area is drained, so it cannot ride a later refusal",
    Enforce.take_correction() == nil, tostring(Enforce.take_correction()))
  check("and no later frame flushes it either -- the retained view is unchanged after "
    .. TICKS .. " orchestrator ticks", settle(b) == before, settle(b))
end

do
  local shapes = {
    { id = "cc-2a", name = "definitely_not_an_action", data = "{}" },
    { id = "cc-2b", name = "play_hand", data = "{not json" },
    { id = "cc-2c", name = "play_hand", data = '{"indices":"nope"}' },
  }
  for i, msg in ipairs(shapes) do
    selecting_hand_env(200 + i * 10)
    local b = neuro(bridge())
    local before = settle(b)
    Dispatcher.route_message({ command = "action", data = msg }, b)
    check("C2." .. i .. ": " .. msg.name .. " is answered",
      #b.results > 0 and b.results[#b.results].id == msg.id, tostring(#b.results))
    check("C2." .. i .. ": and spends nothing on the retained channel",
      channel_sig(b) == before, channel_sig(b))
    check("C2." .. i .. ": nor on any of the " .. TICKS .. " frames after it",
      settle(b) == before, settle(b))
  end
end

do
  local TD = require("tests.test_deadlock")
  local scenario
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SHOP" and sc.desc:find("leave_shop must survive", 1, true) then scenario = sc end
  end
  check("the shop fixture is present", scenario ~= nil)
  if scenario then
    G.TIMERS.REAL = 500
    retained = {}
    G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
      dispatcher = Dispatcher, actions = Actions, reserved_dollars = 0, shop_reroll_count = 0,
      _decision_windows = {}, _reservation_epoch = 0, update = function() end,
      send_context = function(_, msg) retained[#retained + 1] = tostring(msg) return true end }
    TD.apply_mock(scenario.mock())
    G.STATES = { SHOP = 2 }
    G.STATE = 2
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.GAME.dollars = 0
    G.NEURO.shop_entry_dollars = 12
    G.NEURO.shop_visit_epoch = 1
    require("core.transition_guard").reset()
    Enforce.reset_run_state()
    TxCache.reset()
    require("tests.helpers").stage_registered("SHOP", { "leave_shop" })
    G.NEURO.force_inflight = false

    local b = bridge()
    Dispatcher.route_message({ command = "action",
      data = { id = "cc-3", name = "leave_shop", data = "{}" } }, b)
    local last = b.results[#b.results]
    check("the confirmation is answered on the action result",
      last ~= nil and last.reason == "CONFIRMATION_REQUIRED", last and tostring(last.reason) or "none")
    check("and the blocking sentence never enters retained memory",
      #b.emitted == 0 and #retained == 0,
      table.concat(b.emitted, " | ") .. " || " .. table.concat(retained, " | "))
    check("a confirmation is not a failure, so no failure record is invented for it",
      G.NEURO.last_failed_action == nil, tostring(G.NEURO.last_failed_action))
    check("and its staged correction was drained with the refusal it described",
      Enforce.take_correction() == nil, tostring(Enforce.take_correction()))
    local before = channel_sig(b)
    check("and no later frame writes it -- the retained view is unchanged after "
      .. TICKS .. " orchestrator ticks", settle(b) == before, settle(b))
  end
end

-- C4: SPECIFICATION.md:184 -- success=false retries the whole action force, so a client that keeps
-- rendering the same unusable id would loop forever. The streak must terminate in the spec's
-- success=true form (:188), and every answer must still be addressed to the id Neuro sent.
do
  selecting_hand_env(600)
  local b = neuro(bridge())
  local before = settle(b)
  local echoed_wrong = 0
  for i = 1, 8 do
    Dispatcher.route_message({ command = "action",
      data = { id = 42, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
    local r = b.results[i]
    if not (r and r.id == 42) then echoed_wrong = echoed_wrong + 1 end
  end
  check("every invalid-id send is answered", #b.results == 8, tostring(#b.results))
  check("and the answer is addressed to the id she sent", echoed_wrong == 0, tostring(echoed_wrong))
  check("the first answers are refusals the SDK may retry",
    b.results[1].ok == false and b.results[1].reason == "SCHEMA_INVALID",
    tostring(b.results[1].ok) .. "/" .. tostring(b.results[1].reason))
  local terminal
  for _, r in ipairs(b.results) do if r.ok == true then terminal = r break end end
  check("the retry loop is bounded by a terminal success=true", terminal ~= nil,
    "no acknowledged answer in " .. tostring(#b.results) .. " sends")
  check("which says outright that nothing ran",
    terminal ~= nil and tostring(terminal.message):find("Nothing was executed", 1, true) ~= nil,
    terminal and tostring(terminal.message) or "none")
  check("and still names the id as unusable",
    terminal ~= nil and tostring(terminal.message):find("non-empty string", 1, true) ~= nil,
    terminal and tostring(terminal.message) or "none")
  check("a bounded refusal never spends the retained channel",
    channel_sig(b) == before, channel_sig(b))
  check("and none of the eight corrections surfaces on a later frame",
    settle(b) == before, settle(b))
end

do
  selecting_hand_env(700)
  neuro(bridge())
  G.shop_vouchers = { cards = { { config = { center = { key = "v_grabber" } },
    ability = { set = "Voucher", name = "Grabber" } } }, config = { card_limit = 1 } }
  local FactHints = require("facts.fact_hints")
  FactHints.reset_pending()
  FactHints.voucher_basics_hint()
  local text = require("tests.helpers").drain_hints()
  check("the rule is still stated", type(text) == "string"
    and text:find("permanent, run%-wide upgrade") ~= nil, tostring(text))
  check("it asserts no per-shop voucher count",
    text:find("one is offered per shop", 1, true) == nil
      and text:find("per shop", 1, true) == nil,
    tostring(text))
  check("the clause that is true in every run survives",
    text:find("Rerolling the shop never replaces a voucher", 1, true) ~= nil, tostring(text))
  check("and the live count is left to the shop state that lists the offer",
    text:find("listed with that shop", 1, true) ~= nil, tostring(text))
end

done()
