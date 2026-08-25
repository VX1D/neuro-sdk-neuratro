local TxCache = {}

local TX_CACHE_MAX = 4096
TxCache.CAP = TX_CACHE_MAX
local entries = {}
local order = {}
local order_pos = 1
local owed = {}

local function slot_of(action_id)
  if action_id == nil then return nil end
  return type(action_id) .. "\0" .. tostring(action_id)
end

local function intern(slot, action_id)
  local entry = entries[slot]
  if entry then return entry end
  entry = owed[slot] or { slot = slot, key = action_id, answered = false }
  local evicted = order[order_pos]
  if evicted and entries[evicted.slot] == evicted then
    entries[evicted.slot] = nil
  end
  entries[slot] = entry
  order[order_pos] = entry
  order_pos = (order_pos % TX_CACHE_MAX) + 1
  return entry
end

local function mark_answered(entry)
  entry.answered = true
  entry.claimed = nil
  owed[entry.slot] = nil
end

local function session_slot(session)
  return session == nil and "\0no_transport_session" or (type(session) .. "\0" .. tostring(session))
end

function TxCache.get(action_id)
  local slot = slot_of(action_id)
  if not slot then return nil end
  local entry = entries[slot]
  if entry and entry.stored then return entry end
  return nil
end

function TxCache.store(action_id, ok, message, name, reason_code)
  local slot = slot_of(action_id)
  if not slot then return end
  local entry = intern(slot, action_id)
  entry.stored = true
  entry.ok, entry.message, entry.reason_code = not not ok, message, reason_code
  entry.name = name or entry.name
  mark_answered(entry)
end

function TxCache.open(action_id, name, at)
  local slot = slot_of(action_id)
  if not slot then return false end
  local entry = intern(slot, action_id)
  if entry.answered or entry.claimed then return false end
  if owed[slot] == nil then
    owed[slot] = entry
    entry.name = entry.name or name
    entry.opened_at = tonumber(at) or 0
  end
  return true
end

function TxCache.claim(action_id)
  local slot = slot_of(action_id)
  if not slot then return true end
  local entry = intern(slot, action_id)
  if entry.answered or entry.claimed then return false end
  entry.claimed = true
  return true
end

function TxCache.release_claim(action_id)
  local slot = slot_of(action_id)
  if not slot then return false end
  local entry = entries[slot]
  if not entry or entry.stored or not entry.claimed then return false end
  entry.claimed = nil
  return true
end

function TxCache.settle(action_id, attempt)
  if not TxCache.claim(action_id) then return nil end
  local ok, verdict, extra = pcall(attempt)
  if not ok then
    TxCache.release_claim(action_id)
    error(verdict, 0)
  end
  if type(verdict) ~= "table" then
    TxCache.release_claim(action_id)
    return false, extra
  end
  TxCache.store(action_id, verdict.ok, verdict.message, verdict.name, verdict.reason_code)
  return true, extra
end

function TxCache.hold_undelivered(action_id, receipt, at)
  local slot = slot_of(action_id)
  if not slot then return false end
  local entry = entries[slot]
  if not entry or entry.delivered then return false end
  entry.undelivered = true
  entry.pending_frame = receipt
  entry.opened_at = tonumber(at) or entry.opened_at or 0
  owed[slot] = entry
  return true
end

function TxCache.mark_delivered(action_id)
  local slot = slot_of(action_id)
  if not slot then return false end
  local entry = entries[slot] or owed[slot]
  if not entry then return false end
  entry.delivered = true
  entry.undelivered = nil
  entry.pending_frame = nil
  owed[slot] = nil
  return true
end

function TxCache.pending_frame_state(action_id)
  local slot = slot_of(action_id)
  local entry = slot and entries[slot]
  local receipt = entry and entry.pending_frame
  if not receipt then return "gone" end
  if receipt.status == "written" then return "delivered" end
  if receipt.status == "rejected" then return "gone" end
  return "queued"
end

function TxCache.undelivered_verdict(action_id)
  local entry = TxCache.get(action_id)
  if entry and entry.undelivered then return entry end
  return nil
end

function TxCache.note_result_session(action_id, session)
  local slot = slot_of(action_id)
  if not slot then return false end
  local entry = intern(slot, action_id)
  entry.result_transport_session = session_slot(session)
  return true
end

function TxCache.replay_due(action_id, session)
  local entry = TxCache.get(action_id)
  return entry ~= nil and entry.result_transport_session ~= session_slot(session)
end

function TxCache.outstanding(now, deadline)
  local out = {}
  local cutoff = tonumber(deadline)
  local at = tonumber(now) or 0
  for _, entry in pairs(owed) do
    if cutoff == nil or (at - (entry.opened_at or 0)) >= cutoff then
      out[#out + 1] = entry
    end
  end
  table.sort(out, function(a, b)
    if (a.opened_at or 0) == (b.opened_at or 0) then return a.slot < b.slot end
    return (a.opened_at or 0) < (b.opened_at or 0)
  end)
  return out
end

function TxCache.invalidate(action_id)
  local slot = slot_of(action_id)
  if not slot then return end
  local entry = entries[slot]
  if not entry then return end
  entry.stored = nil
  entry.ok, entry.message, entry.name, entry.reason_code = nil, nil, nil, nil
end

function TxCache.reset()
  for k in pairs(entries) do entries[k] = nil end
  for k in pairs(owed) do owed[k] = nil end
  for i = 1, TX_CACHE_MAX do order[i] = nil end
  order_pos = 1
end

return TxCache
