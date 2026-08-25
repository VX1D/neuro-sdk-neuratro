local M = {}

local Orchestrator = require("core.orchestrator")
local ForceState = require("core.force_state")
local Lifecycle = require("core.neuro_lifecycle")
local Dispatcher = require("core.dispatcher")

local clock = 1000
local TICK = 0.02
local BUDGET = 3000  -- 60 s of ticks; a re-ask arms in ~7, a fresh pack state in ~235

local capture, last_error = nil, nil
local captures = 0

local sink = nil
function M.set_sink(fn) sink = fn end

local function bridge_installed()
  return G and G.NEURO and G.NEURO._fp_capture == true
end

local function install_bridge()
  local N = G.NEURO
  N._fp_capture = true
  N.enabled = true
  N.persona = N.persona or "neuro"
  N.dispatcher = N.dispatcher or Dispatcher
  N.actions = N.actions or require("core.actions")
  N.update = function() end
  N.send_action_result = function() end
  function N:send_context(_msg, _silent) return true end
  function N:register_actions() return true end
  function N:unregister_actions() return true end
  function N:force_actions(context, query, actions, _opts)
    local state = tostring(context or "")
    local q = tostring(query or "")
    capture = { state = state, query = q, actions = actions or {}, message = state .. "\n" .. q }
    captures = captures + 1
    if sink then capture.wire = sink(state, q, capture.actions) end
    return true
  end
end

local function ensure_state(state_name)
  G.STATES = G.STATES or {}
  if G.STATES[state_name] == nil then
    local max = 0
    for _, v in pairs(G.STATES) do if type(v) == "number" and v > max then max = v end end
    G.STATES[state_name] = max + 1
  end
  G.STATE = G.STATES[state_name]
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
  require("core.transition_guard").reset()

  capture, last_error = nil, nil
  ForceState.clear_force_state()
  Lifecycle.mark_force_dirty()
  for _ = 1, BUDGET do
    tick()
    if capture then break end
  end
  if capture then return capture, capture end
  if type(Dispatcher.get_force_for_state(state_name)) ~= "table" then return nil end
  error(string.format("force_payload: %s offers a force but the orchestrator sent nothing in %d ticks%s",
    tostring(state_name), BUDGET, last_error and ("; last update error: " .. last_error) or ""), 2)
end

local SOURCE = "core/orchestrator.lua"

function M.drift()
  local fh = io.open(SOURCE, "r")
  if not fh then return SOURCE .. " unreadable" end
  local src = fh:read("*a"); fh:close()
  if not src:find("G%.NEURO%.force_actions, G%.NEURO, p%.context, p%.query, p%.actions") then
    return SOURCE .. " no longer hands (context, query, actions) to G.NEURO.force_actions"
  end
  return nil
end

function M.captures() return captures end

return M
