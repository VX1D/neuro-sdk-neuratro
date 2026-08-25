_G.NEURO_TEST = true
if not love then love = {} end
love.timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 100 end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("reregister-all-window")

local Dispatcher = require("core.dispatcher")
local ForceState = require("core.force_state")
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
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
end

local function bridge()
  local b = { registered = 0 }
  b.send_action_result = function() end
  b.send_context = function() return true end
  b.register_actions = function() b.registered = b.registered + 1 end
  b.unregister_actions = function() end
  return b
end

local function from_bridge(session)
  return { command = "actions/reregister_all", transport_session = session }
end
local FROM_SERVER = { command = "actions/reregister_all" }

local function arm_and_send()
  local armed = ForceState.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, G.TIMERS.REAL)
  ForceState.mark_sent(G.TIMERS.REAL)
  return armed
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  check("a bridge request receives a registration response", b.registered >= 1, b.registered)
  check("the first request remembers the transport session number",
    G.NEURO.transport_session == 1, tostring(G.NEURO.transport_session))

  check("the window is armed and sent after rebuilding", arm_and_send() == true
    and G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))

  Dispatcher.route_message(from_bridge(1), b)
  check("a repeated stamp means a bridge restart reconnect and dismantles the window",
    G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("a repeated stamp records the reconnect reason",
    G.NEURO.force_last_result == "reconnect", tostring(G.NEURO.force_last_result))
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  local registered_before = b.registered
  Dispatcher.route_message(FROM_SERVER, b)
  check("an unstamped server request does not dismantle a live window",
    G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))
  check("an unstamped server request still receives registration",
    b.registered > registered_before, b.registered)
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  local serial_before = tonumber(G.NEURO.decision_serial) or 0
  Dispatcher.route_message(FROM_SERVER, b)
  Dispatcher.route_message(FROM_SERVER, b)
  Dispatcher.route_message(FROM_SERVER, b)
  check("a series of server requests is idempotent for the force window",
    G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))
  check("a series of server requests does not advance the decision serial",
    (tonumber(G.NEURO.decision_serial) or 0) == serial_before)
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  local serial_before = tonumber(G.NEURO.decision_serial) or 0
  local generation_before = tonumber(G.NEURO.run_generation) or 0
  Dispatcher.route_message(from_bridge(1), b)
  check("reconnect clears force_inflight so the arm loop can ask again",
    G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("reconnect without a run-number change preserves run generation",
    (tonumber(G.NEURO.run_generation) or 0) == generation_before, tostring(G.NEURO.run_generation))
  check("reconnect without a run-number change preserves decision serial",
    (tonumber(G.NEURO.decision_serial) or 0) == serial_before)
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  G.TIMERS.REAL = 200
  Dispatcher.route_message(from_bridge(2), b)
  check("a new transport session dismantles the force window",
    G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("a new session records the reconnect reason",
    G.NEURO.force_last_result == "reconnect", tostring(G.NEURO.force_last_result))
  check("a new session replaces the remembered number",
    G.NEURO.transport_session == 2, tostring(G.NEURO.transport_session))
end

do
  env()
  local b = bridge()
  arm_and_send()
  Dispatcher.route_message(from_bridge(9), b)
  check("a mod with no remembered session treats the first stamp as a new session",
    G.NEURO.force_inflight == false and G.NEURO.transport_session == 9,
    tostring(G.NEURO.force_inflight) .. "/" .. tostring(G.NEURO.transport_session))
end

done()
