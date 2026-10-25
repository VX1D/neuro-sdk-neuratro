local function get_store(epoch)
  if not (G and G.NEURO) then return nil end
  local field = epoch == "session" and "session_once_serials" or "once_serials"
  if type(G.NEURO[field]) ~= "table" then G.NEURO[field] = {} end
  return G.NEURO[field]
end

local function normalize_epoch(epoch)
  if epoch == nil then return "\0nil" end
  return epoch
end

local journal = nil
-- A stale receipt callback must not resolve the next turn’s journal.
local journal_token = 0
local next_token = 0

local function unwind(entries)
  if not entries then return 0 end
  for i = #entries, 1, -1 do
    local e = entries[i]
    local seen = get_store(e.epoch)
    if seen then seen[e.key] = e.prev end
  end
  return #entries
end

local function owns(token)
  return token == nil or token == journal_token
end

local function rollback_journal(token)
  if not owns(token) then return 0 end
  local entries = journal
  journal = nil
  return unwind(entries)
end

local function begin_journal()
  if journal then unwind(journal) end
  journal = {}
  next_token = next_token + 1
  journal_token = next_token
  return journal_token
end

local function commit_journal(token)
  if not owns(token) then return false end
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
