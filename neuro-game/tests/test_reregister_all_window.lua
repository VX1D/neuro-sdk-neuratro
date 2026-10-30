local ES = require("tests.engine_cards").states()
_G.NEURO_TEST = true
if not love then love = {} end
love.timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 100 end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("reregister-all-window")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()

local function env()
  _G.G = {
    NEURO = { dispatcher = Dispatcher, actions = require("core.actions"),
      run_generation = 1, persona = "neuro" },
    FUNCS = {},
    GAME = { dollars = 10, bankrupt_at = 0, round_resets = { ante = 1 },
      current_round = { hands_left = 4, discards_left = 3 } },
    STATES = ES, STATE = ES.SELECTING_HAND, TIMERS = { REAL = 100 },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
  G.NEURO.state = "SELECTING_HAND"
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  G.NEURO.force_window = nil
end

local function bridge()
  local b = { registered = 0, startups = 0 }
  for key, value in pairs(G.NEURO or {}) do b[key] = value end
  b.send_startup = function()
    b.startups = b.startups + 1
    return true
  end
  b.send_action_result = function() end
  b.send_context = function() return true end
  b.register_actions = function() b.registered = b.registered + 1 end
  G.NEURO = require("tests.helpers").started_bridge(b)
  return b
end

local function from_bridge(session)
  return { command = "neuro-bridge/reregister_all", transport_session = session }
end
local FROM_SERVER = { command = "neuro-bridge/reregister_all" }

local Window = require("core.window")
local function live() return Window.current() ~= nil end

local function arm_and_send()
  local armed = require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  return armed
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  check("a bridge request starts a fresh SDK session", b.startups >= 1, b.startups)
  check("the first request remembers the transport session number",
    tostring(G.NEURO.transport_session) == "1", tostring(G.NEURO.transport_session))

  check("the window is armed and sent after rebuilding", arm_and_send() ~= nil and live())

  Dispatcher.route_message(from_bridge(1), b)
  check("a duplicate stamp leaves the existing result state alone",
    Window.current() ~= nil and Window.current().phase == "forced",
    tostring(G.NEURO.force_window and G.NEURO.force_window.phase))
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  local starts_before = b.startups
  Dispatcher.route_message(FROM_SERVER, b)
  check("an unstamped server request does not dismantle a live window",
    live())
  check("an unstamped server request does not start a new SDK session",
    b.startups == starts_before, b.startups)
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
    live())
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
  check("a duplicate stamp leaves the force window untouched",
    live())
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
  local ended = G.NEURO.force_window
  check("a new transport session dismantles the force window", not live())
  check("a new session records the reconnect reason",
    ended and ended.ended_by == "reset", tostring(ended and ended.ended_by))
  check("a new session replaces the remembered number",
    tostring(G.NEURO.transport_session) == "2", tostring(G.NEURO.transport_session))
end

do
  env()
  local b = bridge()
  arm_and_send()
  Dispatcher.route_message(from_bridge(9), b)
  check("a mod with no remembered session treats the first stamp as a new session",
    not live() and tostring(G.NEURO.transport_session) == "9", tostring(G.NEURO.transport_session))
end

do
  env()
  local b = bridge()
  Dispatcher.route_message(from_bridge(1), b)
  arm_and_send()
  G.jokers.cards = { { ability = { set = "Joker" } }, { ability = { set = "Joker" } } }
  b.register_actions = function() return false end
  Dispatcher.route_message(from_bridge(2), b)
  local ended = G.NEURO.force_window
  check("a new session whose catalogue fails to register still ends the old window at once",
    not live() and ended and ended.ended_by == "reset", tostring(ended and ended.phase))
  check("and keeps the catalogue owed for the next frame", G.NEURO._reconnect_pending == "2",
    tostring(G.NEURO._reconnect_pending))
  b.register_actions = function() return true end
  require("core.bridge_init").retry_pending_reconnect()
  check("which a later retry pays", G.NEURO._reconnect_pending == nil and G.NEURO._bridge_init_complete == true)
end

done()
