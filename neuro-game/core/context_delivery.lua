local M = {}

local Metrics = require("util.metrics")

local MAX_ATTEMPTS = 12
local TRANSIENT_MEMORY_MAX = 512
local RULE_MEMORY_MAX = 2048
local HINT_RULE_PREFIX = "hint:"

local pending = {}
local delivered = {}
local delivered_text = {}
local transient_order = {}
local transient_count = 0
local rule_order = {}
local rule_count = 0
local transport_epoch = 0
local seq = 0

local function clean_text(value)
  if type(value) ~= "string" then return nil end
  return value:match("%S") and value or nil
end

local function bridge(entry)
  return entry.bridge or (G and G.NEURO)
end

local function identity(kind, key)
  return tostring(kind) .. "\1" .. tostring(key)
end

local function run_coordinate()
  local n = G and G.NEURO
  local generation = n and tonumber(n.run_generation)
  if generation == nil then return nil end
  return "run " .. tostring(generation)
end

function M.stamp(coords)
  local parts = {}
  local run = run_coordinate()
  if run then parts[#parts + 1] = run end
  if type(coords) == "table" then
    for _, coord in ipairs(coords) do
      coord = tostring(coord)
      if coord ~= "" then parts[#parts + 1] = coord end
    end
  end
  if #parts == 0 then return "" end
  return "[" .. table.concat(parts, ", ") .. "] "
end

function M.here(...)
  local gm = G and G.GAME
  local ante = gm and gm.round_resets and gm.round_resets.ante
  local round = gm and gm.round
  local coords = {}
  if ante ~= nil then coords[#coords + 1] = "ante " .. tostring(ante) end
  if round ~= nil then coords[#coords + 1] = "round " .. tostring(round) end
  for i = 1, select("#", ...) do
    local extra = select(i, ...)
    if extra ~= nil then coords[#coords + 1] = tostring(extra) end
  end
  return coords
end

local function forget_text(text)
  local n = (delivered_text[text] or 0) - 1
  delivered_text[text] = (n > 0) and n or nil
end

local function trim(order, count, limit)
  while count > limit do
    local oldest = table.remove(order, 1)
    count = count - 1
    if oldest then
      local text = delivered[oldest]
      delivered[oldest] = nil
      if text ~= nil then forget_text(text) end
    end
  end
  return count
end

local function remember(entry)
  delivered[entry.identity] = entry.text
  delivered_text[entry.text] = (delivered_text[entry.text] or 0) + 1
  if entry.kind == "rule" then
    -- Only hints mint a fresh identity per emission. Glossary and permanent-rule keys are fixed
    -- and must stay remembered; evicting one resends the whole glossary.
    if entry.key:sub(1, #HINT_RULE_PREFIX) == HINT_RULE_PREFIX then
      rule_order[#rule_order + 1] = entry.identity
      rule_count = trim(rule_order, rule_count + 1, RULE_MEMORY_MAX)
    end
    return
  end
  transient_order[#transient_order + 1] = entry.identity
  transient_count = trim(transient_order, transient_count + 1, TRANSIENT_MEMORY_MAX)
end

local function commit(entry, receipt)
  if receipt and receipt.transport_epoch ~= transport_epoch then
    Metrics.incr("context_delivery_stale_receipt")
    pending[entry.identity] = nil
    return false
  end
  remember(entry)
  pending[entry.identity] = nil
  if type(entry.on_written) == "function" then
    local ok, err = pcall(entry.on_written, entry)
    if not ok then
      Metrics.incr("context_delivery_commit_error")
      print("[neuro-game] context delivery commit failed: " .. tostring(err))
    end
  end
  return true
end

local function fail_attempt(entry)
  entry.receipt = nil
  entry.attempts = (entry.attempts or 0) + 1
  if entry.attempts >= MAX_ATTEMPTS then
    pending[entry.identity] = nil
    Metrics.incr("context_delivery_abandoned")
    print("[neuro-game] context delivery abandoned after " .. tostring(entry.attempts)
      .. " attempts for key " .. tostring(entry.key))
  end
  return false
end

local function attempt(entry)
  local b = bridge(entry)
  if not (b and type(b.send_context) == "function") then return false end
  local receipt = { status = "sending", kind = "context_" .. entry.kind,
    context_key = entry.key, transport_epoch = entry.transport_epoch }
  entry.receipt = receipt
  local ok, accepted, queued_not_delivered = pcall(b.send_context, b, entry.text, entry.silent, receipt)
  if not ok or accepted == false or receipt.status == "rejected" then
    return fail_attempt(entry)
  end
  if receipt.status == "written" then
    commit(entry, receipt)
    return true
  end
  if receipt.status == "buffered" or queued_not_delivered == true then
    entry.stalled = 0
    return true
  end
  if accepted then
    Metrics.incr("context_delivery_receiptless_bridge")
    commit(entry, receipt)
    return true
  end
  return fail_attempt(entry)
end

local function enqueue(kind, key, text, opts)
  opts = opts or {}
  key = tostring(key or "")
  text = clean_text(text)
  if key == "" or not text then return false, "empty" end
  local id = identity(kind, key)
  if kind ~= "rule" and delivered_text[text] and delivered[id] == nil then
    Metrics.incr("context_duplicate_text")
    print("[neuro-game] refused unscoped duplicate context for key " .. key)
    return false, "duplicate_text"
  end
  local prior = delivered[id]
  if prior ~= nil then
    if prior ~= text then
      Metrics.incr("context_rule_identity_changed")
      if rawget(_G, "NEURO_TEST") then
        error("context identity changed after delivery: " .. key, 2)
      end
      print("[neuro-game] refused changed retained context for key " .. key)
      return false, "identity_changed"
    end
    return true
  end
  local existing = pending[id]
  if existing then
    if existing.text ~= text then
      Metrics.incr("context_pending_identity_changed")
      if rawget(_G, "NEURO_TEST") then
        error("pending context identity changed: " .. key, 2)
      end
      return false, "identity_changed"
    end
    if existing.receipt and existing.receipt.status == "written" then
      commit(existing, existing.receipt)
      return true
    end
    if existing.receipt and existing.receipt.status == "rejected" then
      existing.receipt = nil
    end
    if existing.receipt ~= nil then return true end
    return attempt(existing)
  end
  seq = seq + 1
  local entry = {
    identity = id,
    kind = kind,
    key = key,
    text = text,
    silent = opts.silent ~= false,
    on_written = opts.on_written,
    bridge = opts.bridge,
    transport_epoch = transport_epoch,
    attempts = 0,
    seq = seq,
  }
  pending[id] = entry
  return attempt(entry)
end

function M.rule(key, text, opts)
  return enqueue("rule", key, text, opts)
end

function M.event(key, text, opts)
  return enqueue("event", key, text, opts)
end

function M.prompt(key, text, opts)
  opts = opts or {}
  opts.silent = false
  return enqueue("prompt", key, text, opts)
end

local function located(kind, prefix, coords, text, opts)
  local body = clean_text(text)
  if not body then return false, "empty" end
  local stamped = M.stamp(coords) .. body
  return enqueue(kind, tostring(prefix) .. "|" .. stamped, stamped, opts)
end

function M.event_at(prefix, coords, text, opts)
  return located("event", prefix, coords, text, opts)
end

function M.prompt_at(prefix, coords, text, opts)
  opts = opts or {}
  opts.silent = false
  return located("prompt", prefix, coords, text, opts)
end

function M.step()
  if next(pending) == nil then return end
  local entries = {}
  for _, entry in pairs(pending) do entries[#entries + 1] = entry end
  table.sort(entries, function(a, b) return a.seq < b.seq end)
  for _, entry in ipairs(entries) do
    if entry.receipt and entry.receipt.status == "written" then
      commit(entry, entry.receipt)
    elseif entry.receipt and entry.receipt.status == "rejected" then
      entry.receipt = nil
      if pending[entry.identity] then attempt(entry) end
    elseif entry.receipt and entry.receipt.status ~= "buffered" then
      entry.stalled = (entry.stalled or 0) + 1
      if entry.stalled >= 3 then
        pending[entry.identity] = nil
        Metrics.incr("context_delivery_stalled")
      end
    elseif not entry.receipt then
      attempt(entry)
    end
  end
end

function M.reset_transport()
  transport_epoch = transport_epoch + 1
  local carried = {}
  for _, entry in pairs(pending) do
    if not (entry.receipt and entry.receipt.status == "written") then
      entry.receipt = nil
      entry.transport_epoch = transport_epoch
      entry.attempts = 0
      carried[entry.identity] = entry
    end
  end
  pending = carried
  delivered = {}
  delivered_text = {}
  transient_order = {}
  transient_count = 0
  rule_order = {}
  rule_count = 0
end

local function delivered_view() return delivered end

if rawget(_G, "NEURO_TEST") then
  M._delivered = delivered_view
end

return M
