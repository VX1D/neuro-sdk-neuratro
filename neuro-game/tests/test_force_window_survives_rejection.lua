_G.NEURO_TEST = true
if not love then love = {} end
love.timer = { getTime = function() return 100 end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("force-window-survives-rejection")

local Dispatcher = require("core.dispatcher")
local ForceState = require("core.force_state")
local Registry = require("core.action_registry")
local Enforce = require("core.enforce")

local function env()
  _G.G = {
    NEURO = { dispatcher = Dispatcher, actions = require("core.actions"),
      run_generation = 1, persona = "neuro" },
    FUNCS = {},
    GAME = { dollars = 10, bankrupt_at = 0, round_resets = { ante = 1 },
      current_round = { hands_left = 4, discards_left = 3 } },
    STATES = { SELECTING_HAND = 4 }, STATE = 4, TIMERS = { REAL = 100 },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
  G.NEURO.state = "SELECTING_HAND"
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  require("core.transition_guard").reset()
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  ForceState.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand" })
end

local function bridge()
  local b = { results = {}, unregistered = {} }
  b.send_action_result = function(_, id, ok, msg, reason)
    b.results[#b.results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
  end
  b.send_context = function() return true end
  b.unregister_actions = function(_, names)
    for _, n in ipairs(names or {}) do b.unregistered[#b.unregistered + 1] = n end
  end
  return b
end

do
  env()
  local inflight_before = G.NEURO.force_inflight
  local b = bridge()
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "rej-1", name = "play_hand", data = '{"indices":[1,2,3,4,5,6]}' } }, b)
  local r = b.results[1]
  check("forced-action rejection sends success=false with a durable code",
    r ~= nil and r.ok == false and r.reason == "SCHEMA_INVALID",
    r and (tostring(r.ok) .. "/" .. tostring(r.reason)))
  check("the force window survives rejection with force_inflight intact",
    G.NEURO.force_inflight == inflight_before and inflight_before ~= false,
    tostring(inflight_before) .. " -> " .. tostring(G.NEURO.force_inflight))
  check("the forced action remains registered after rejection",
    Registry.is_registered("play_hand") == true)
  check("rejection does not unregister the one-shot action",
    #b.unregistered == 0, table.concat(b.unregistered, ","))
  check("rejection records a failure for the correction layer",
    G.NEURO.last_failed_action == "play_hand", tostring(G.NEURO.last_failed_action))
end

do
  env()
  local b = bridge()
  G.hand.cards = {}
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "rej-2", name = "play_hand", data = '{"indices":[1]}' } }, b)
  check("a second rejection class leaves the window armed",
    G.NEURO.force_inflight ~= false, tostring(G.NEURO.force_inflight))
  check("a second rejection class still preserves registration",
    Registry.is_registered("play_hand") == true)
end

Registry.reset()
done()
