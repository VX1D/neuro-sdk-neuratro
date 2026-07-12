local TxCache = {}

local TX_CACHE_MAX = 256
local settled = {}
local order = {}

local function key(action_id)
  if action_id == nil then return nil end
  return tostring(action_id)
end
TxCache.key = key

function TxCache.get(action_id)
  local k = key(action_id)
  if not k then return nil end
  return settled[k]
end

function TxCache.store(action_id, ok, message, name)
  local k = key(action_id)
  if not k then return end
  if not settled[k] then
    order[#order + 1] = k
  end
  settled[k] = { ok = not not ok, message = message, name = name }
  while #order > TX_CACHE_MAX do
    local drop = table.remove(order, 1)
    settled[drop] = nil
  end
end

function TxCache.invalidate(action_id)
  local k = key(action_id)
  if not k or settled[k] == nil then return end
  settled[k] = nil
  for i = #order, 1, -1 do
    if order[i] == k then table.remove(order, i); break end
  end
end

function TxCache.reset()
  for k in pairs(settled) do settled[k] = nil end
  for i = #order, 1, -1 do order[i] = nil end
end

return TxCache
