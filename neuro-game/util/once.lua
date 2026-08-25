local function get_store(epoch)
  if not (G and G.NEURO) then return nil end
  if epoch == "session" then
    if type(G.NEURO.session_once_serials) ~= "table" then
      G.NEURO.session_once_serials = {}
    end
    return G.NEURO.session_once_serials
  end
  if type(G.NEURO.once_serials) ~= "table" then
    G.NEURO.once_serials = {}
  end
  return G.NEURO.once_serials
end

local function normalize_epoch(epoch)
  if epoch == nil then return "\0nil" end
  return epoch
end

local journal = nil

local function rollback_journal()
  local entries = journal
  journal = nil
  if not entries then return 0 end
  for i = #entries, 1, -1 do
    local e = entries[i]
    local seen = get_store(e.epoch)
    if seen then seen[e.key] = e.prev end
  end
  return #entries
end

local function begin_journal()
  rollback_journal()
  journal = {}
end

local function commit_journal()
  journal = nil
  return true
end

local function once_until(key, epoch)
  local seen = get_store(epoch)
  if not seen then return false end
  key = tostring(key)
  local norm = normalize_epoch(epoch)
  if seen[key] == norm then return false end
  if journal then
    journal[#journal + 1] = { key = key, epoch = epoch, prev = seen[key] }
  end
  seen[key] = norm
  return true
end

local function peek(key, epoch)
  local seen = get_store(epoch)
  if not seen then return false end
  return seen[tostring(key)] ~= normalize_epoch(epoch)
end

local function book(key, epoch)
  local seen = get_store(epoch)
  if not seen then return end
  seen[tostring(key)] = normalize_epoch(epoch)
end

return {
  once_until = once_until,
  peek = peek,
  book = book,
  begin_journal = begin_journal,
  commit_journal = commit_journal,
  rollback_journal = rollback_journal,
}
