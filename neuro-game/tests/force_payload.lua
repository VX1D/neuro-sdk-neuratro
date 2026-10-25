local M = {}

local Orchestrator = require("core.orchestrator")
local Window = require("core.window")
local Dispatcher = require("core.dispatcher")

local clock = 1000
local TICK = 0.02
local BUDGET = 3000

local capture, last_error = nil, nil
local captures = 0

local sink = nil
function M.set_sink(fn) sink = fn end

local function bridge_installed()
  return G and G.NEURO and G.NEURO._fp_capture == true
end

local function install_bridge()
  local N = require("tests.helpers").started_bridge(G.NEURO)
  N._fp_capture = true
  N.enabled = true
  N.persona = N.persona or "neuro"
  N.dispatcher = N.dispatcher or Dispatcher
  N.actions = N.actions or require("core.actions")
  N.update = function() end
  N.send_action_result = function() end
  function N:send_context(_msg, _silent) return true end
  function N:register_actions() return true end
  function N:force_actions(context, query, actions, opts)
    local state = tostring(context or "")
    local q = tostring(query or "")
    capture = { state = state, query = q, actions = actions or {}, message = state .. "\n" .. q,
      opts = type(opts) == "table" and opts or nil }
    captures = captures + 1
    if sink then capture.wire = sink(state, q, capture.actions) end
    return true
  end
end

local function ensure_state(state_name)
  if require("core.state").get_state_name() ~= state_name then
    require("tests.helpers").in_engine_state(state_name)
  end
end

local function tick()
  clock = clock + TICK
  G.TIMERS.REAL = clock
  G.TIMERS.TOTAL = clock
  local ok, err = pcall(Orchestrator.update, TICK)
  if not ok then last_error = tostring(err) end
end

function M.build(state_name)
  G.TIMERS = G.TIMERS or {}
  if type(G.TIMERS.REAL) ~= "number" or G.TIMERS.REAL < clock then G.TIMERS.REAL = clock end
  if not bridge_installed() then install_bridge() end
  ensure_state(state_name)
  require("core.validate").reset_run_state()

  capture, last_error = nil, nil
  Window.reset()
  for _ = 1, BUDGET do
    tick()
    if capture then break end
  end
  if capture then return capture, capture end
  if type(require("force.force_router").get_force_for_state(state_name)) ~= "table" then return nil end
  error(string.format("force_payload: %s offers a force but the orchestrator sent nothing in %d ticks%s",
    tostring(state_name), BUDGET, last_error and ("; last update error: " .. last_error) or ""), 2)
end

function M.next()
  clock = math.max(clock, tonumber(G.TIMERS.REAL) or clock)
  capture, last_error = nil, nil
  for _ = 1, BUDGET do
    tick()
    if capture then return capture end
  end
  return nil
end

local SOURCE = "core/window.lua"

function M.drift()
  local fh = io.open(SOURCE, "r")
  if not fh then return SOURCE .. " unreadable" end
  local src = fh:read("*a"); fh:close()
  if not src:find("n%.force_actions, n, Utils%.trim_line_ends%(context%), Utils%.trim_line_ends%(force%.query%),%s+force%.actions") then
    return SOURCE .. " no longer hands (context, query, actions) to G.NEURO.force_actions"
  end
  return nil
end

function M.captures() return captures end

return M
