-- Lives in core (not force/) so force_helpers stays a downward-only consumer; re-exported there.
local M = {}

local Lifecycle = require("core.neuro_lifecycle")
local Actions = require("core.actions")

function M.is_forced_action(name)
  if not (G and G.NEURO and G.NEURO.force_inflight and name) then
    return false
  end
  local set = G.NEURO.force_action_set
  if set then
    return not not set[name]
  end
  local list = G.NEURO.force_action_names
  if list then
    for i = 1, #list do
      if list[i] == name then
        return true
      end
    end
  end
  return false
end

-- action_phase and its timestamp must move together; one setter keeps them in sync
function M.set_action_phase(name, at)
  if not (G and G.NEURO) then return end
  G.NEURO.action_phase = name
  G.NEURO.action_phase_at = at or require("util.utils").now()
end

function M.clear_force_state()
  if not (G and G.NEURO) then return end
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_action_names = nil
  G.NEURO.force_action_set = nil
  G.NEURO.force_sent_at = nil
end

function M.snapshot_once_serials()
  if not (G and G.NEURO) then return nil end
  if type(G.NEURO.once_serials) ~= "table" then return nil end
  local snap = {}
  for k, v in pairs(G.NEURO.once_serials) do snap[k] = v end
  return snap
end

function M.restore_once_serials(snap)
  if not (G and G.NEURO) then return end
  G.NEURO.once_serials = snap
end

M.record_failure = Lifecycle.record_failure

function M.correct_optimistic(action, reason, action_id, context_msg)
  if not (G and G.NEURO) then return end
  Lifecycle.record_failure(action, reason)
  if G.NEURO.invalidate_tx then G.NEURO.invalidate_tx(action_id) end
  Lifecycle.mark_force_dirty()
  if context_msg and G.NEURO.send_context then
    pcall(G.NEURO.send_context, G.NEURO, context_msg, true)
  end
end

-- staleness gate: a force built for one state must not reach the bridge after G.STATE moved
function M.force_is_stale(built_state, force)
  local ok_s, State = pcall(require, "core.state")
  if ok_s and State and type(State.get_state_name) == "function" then
    local ok_n, current = pcall(State.get_state_name)
    if ok_n and current and current ~= built_state then return true end
  end
  if built_state == "BLIND_SELECT" and type(force) == "table" and force.blind then
    local now_key = Actions.get_selectable_blind_key and Actions.get_selectable_blind_key() or nil
    if not now_key or string.lower(now_key) ~= tostring(force.blind) then return true end
  end
  return false
end

return M
