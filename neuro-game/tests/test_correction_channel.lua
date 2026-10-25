require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("correction-channel")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx
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
  return require("tests.helpers").fake_bridge({ reason = "reason", context = "emitted", register = "count", cooldown = true })
end

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t)
  require("tests.helpers").selecting_hand_env({
    time = t, reset_tx_cache = true,
  })
  retained = {}
end

local function neuro(b)
  G.NEURO = require("tests.helpers").started_bridge({ enabled = true, decision_serial = 1, run_generation = 1,
    persona = "neuro", dispatcher = Dispatcher, actions = Actions, update = function() end,
    register_actions = function() end, force_actions = function() return true end,
    send_context = function(_, msg) retained[#retained + 1] = tostring(msg) return true end })
  require("tests.helpers").stage_registered("SELECTING_HAND", { "buy_from_shop", "leave_shop" })
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
  check("no failure prose is kept back for a later force",
    ForceHelpers.failed_action_warning == nil and G.NEURO.last_failed_correction == nil)
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
      _reservation_epoch = 0, update = function() end,
      register_actions = function() end, force_actions = function() return true end,
      send_context = function(_, msg) retained[#retained + 1] = tostring(msg) return true end }
    TD.apply_mock(scenario.mock())
    require("tests.helpers").in_engine_state("SHOP")
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.GAME.dollars = 0
    G.NEURO.shop_entry_dollars = 12
    G.NEURO.shop_visit_epoch = 1
    require("core.validate").reset_run_state()
    Enforce.reset_run_state()
    TxCache.reset()
    require("tests.helpers").stage_registered("SHOP", { "leave_shop" })

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
    local before = channel_sig(b)
    check("and no later frame writes it -- the retained view is unchanged after "
      .. TICKS .. " orchestrator ticks", settle(b) == before, settle(b))
  end
end

do
  selecting_hand_env(600)
  local b = neuro(bridge())
  local before = settle(b)
  for _ = 1, 8 do
    Dispatcher.route_message({ command = "action",
      data = { id = 42, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  end
  check("invalid non-string ids are dropped without fabricated results",
    #b.results == 0, tostring(#b.results))
  check("a dropped invalid id never spends the retained channel",
    channel_sig(b) == before, channel_sig(b))
  check("and none of the rejected frames surfaces a correction later",
    settle(b) == before, settle(b))
end

done()
