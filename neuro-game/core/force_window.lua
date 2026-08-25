local M = {}

local BUILDING, REGISTERED, FORCED = "building", "registered", "forced"
local ACKNOWLEDGED, CANCELLING, ENDED = "acknowledged", "cancelling", "ended"

M.BUILDING, M.REGISTERED, M.FORCED = BUILDING, REGISTERED, FORCED
M.ACKNOWLEDGED, M.CANCELLING, M.ENDED = ACKNOWLEDGED, CANCELLING, ENDED

function M.key_for(state_name, decision_serial)
  return tostring(state_name or "") .. "#" .. tostring(decision_serial or 0)
end

function M.build(state_name, decision_serial)
  return {
    key = M.key_for(state_name, decision_serial),
    state = state_name,
    phase = BUILDING,
    names = nil,
    set = nil,
    payload = nil,
  }
end

function M.register(window, names, set, payload)
  if type(window) ~= "table" or window.phase ~= BUILDING then return false end
  if type(names) ~= "table" or #names == 0 then return false end
  if type(set) ~= "table" then
    set = {}
    for i = 1, #names do set[names[i]] = true end
  end
  window.names, window.set = names, set
  window.payload = payload
  window.phase = REGISTERED
  return true
end

function M.mark_forced(window)
  if type(window) ~= "table" or window.phase ~= REGISTERED then return false end
  window.phase = FORCED
  return true
end

-- Answer acknowledged (SPECIFICATION.md:184: won't be retried), but the decision itself is still
-- open -- actions stay registered; only the asking ends here.
function M.mark_acknowledged(window)
  if type(window) ~= "table" then return false end
  if window.phase == ACKNOWLEDGED then return true end
  if window.phase ~= FORCED then return false end
  window.phase = ACKNOWLEDGED
  return true
end

function M.mark_cancelling(window)
  if type(window) ~= "table" then return false end
  if window.phase == CANCELLING then return true end
  if window.phase ~= FORCED and window.phase ~= ACKNOWLEDGED then return false end
  window.phase = CANCELLING
  return true
end

function M.owns(window, name)
  return not not (type(window) == "table" and window.set and name and window.set[name])
end

function M.is_open(window)
  if type(window) ~= "table" then return false end
  return window.phase == REGISTERED or window.phase == FORCED or window.phase == ACKNOWLEDGED
    or window.phase == CANCELLING
end

function M.finish(window)
  if type(window) ~= "table" or window.phase == ENDED then return false end
  window.phase = ENDED
  return true
end

return M
