local M = {}

local Metrics = require("util.metrics")

local MAX_ATTEMPTS = 12
local MEMORY_MAX = { transient = 512, hint = 2048, rule = 512 }
local PENDING_MEMORY_MAX = 512
local HINT_RULE_PREFIX = "hint:"
local ESSENTIAL_GUIDE_KEY = "permanent_rule:action_semantics:v1"

local pending = {}
local pending_count = 0
local delivered = {}
local orders = { transient = {}, hint = {}, rule = {} }
local seq = 0

local function is_essential_guide(kind, key)
  return kind == "rule" and key == ESSENTIAL_GUIDE_KEY
end

local function clean_text(value)
  if type(value) ~= "string" then return nil end
  value = require("util.utils").trim_line_ends(value)
  return value:match("%S") and value or nil
end

local function bridge(entry)
  return entry.bridge or (G and G.NEURO)
end
local function startup_admitted(b)
  if type(b) ~= "table" or type(b.send_startup) ~= "function" then return true end
  return b._startup_complete == true and b._bridge_init_complete == true
end

local function identity(kind, key, occurrence)
  local id = tostring(kind) .. "\1" .. tostring(key)
  if occurrence ~= nil then id = id .. "\1" .. tostring(occurrence) end
  return id
end

local function live_game()
  if not (G and G.STAGES and G.STAGE ~= nil and G.STAGE == G.STAGES.RUN) then return nil end
  return type(G.GAME) == "table" and G.GAME or nil
end

local run_ordinals, runs_seen = setmetatable({}, { __mode = "k" }), 0
local function run_coordinate()
  local game = live_game()
  if not game then return nil end
  local seed = type(game.pseudorandom) == "table" and game.pseudorandom.seed
  local key = type(seed) == "string" and seed ~= "" and ("seed:" .. seed) or game
  if not run_ordinals[key] then runs_seen = runs_seen + 1; run_ordinals[key] = runs_seen end
  return "run " .. tostring(run_ordinals[key])
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
  local gm = live_game()
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

local function remember(entry)
  delivered[entry.identity] = entry.text
  local class = "transient"
  if entry.kind == "rule" then
    if entry.key:sub(1, #HINT_RULE_PREFIX) == HINT_RULE_PREFIX then
      class = "hint"
    elseif entry.essential then
      return
    else
      class = "rule"
    end
  end
  local order = orders[class]
  order[#order + 1] = entry.identity
  while #order > MEMORY_MAX[class] do delivered[table.remove(order, 1)] = nil end
end

local function remove_pending(entry)
  if pending[entry.identity] ~= entry then return false end
  pending[entry.identity] = nil
  pending_count = pending_count - 1
  return true
end

local enqueue

local guide_retry_pending = true

local function revive_essential_guide(entry)
  if not entry.essential or not guide_retry_pending then return end
  guide_retry_pending = false
  Metrics.incr("context_delivery_guide_reenqueued")
  enqueue(entry.kind, entry.key, entry.text, { silent = entry.silent, on_written = entry.on_written,
    bridge = entry.bridge, occurrence = entry.occurrence })
end

local function evict_pending_overflow()
  while pending_count > PENDING_MEMORY_MAX do
    local victim
    for _, candidate in pairs(pending) do
      if not candidate.essential and (not victim or candidate.seq < victim.seq) then victim = candidate end
    end
    if not victim then break end
    remove_pending(victim)
    Metrics.incr("context_delivery_pending_evicted")
  end
end

local function commit(entry)
  remember(entry)
  remove_pending(entry)
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
  entry.attempts = (entry.attempts or 0) + 1
  if entry.attempts >= MAX_ATTEMPTS then
    remove_pending(entry)
    Metrics.incr("context_delivery_abandoned")
    print("[neuro-game] context delivery abandoned after " .. tostring(entry.attempts)
      .. " attempts for key " .. tostring(entry.key))
    revive_essential_guide(entry)
  end
  return false
end

local function attempt(entry)
  local b = bridge(entry)
  if not (b and type(b.send_context) == "function") then return false end
  if not startup_admitted(b) then return false end
  local receipt = { status = "sending", kind = "context_" .. entry.kind, context_key = entry.key }
  local ok, accepted = pcall(b.send_context, b, entry.text, entry.silent, receipt)
  if not ok or accepted == false or receipt.status == "rejected" then
    return fail_attempt(entry)
  end
  return commit(entry)
end

enqueue = function(kind, key, text, opts)
  opts = opts or {}
  key = tostring(key or "")
  text = clean_text(text)
  if key == "" or not text then return false, "empty" end
  if kind ~= "rule" and opts.occurrence == nil then
    Metrics.incr("context_missing_occurrence")
    if rawget(_G, "NEURO_TEST") then
      error("context " .. kind .. " without an occurrence: " .. key, 2)
    end
    print("[neuro-game] refused context " .. kind .. " without an occurrence for key " .. key)
    return false, "missing_occurrence"
  end
  local id = identity(kind, key, opts.occurrence)
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
    return attempt(existing)
  end
  seq = seq + 1
  local entry = {
    identity = id,
    kind = kind,
    key = key,
    occurrence = opts.occurrence,
    text = text,
    essential = is_essential_guide(kind, key),
    silent = opts.silent ~= false,
    on_written = opts.on_written,
    bridge = opts.bridge,
    attempts = 0,
    seq = seq,
  }
  pending[id] = entry
  pending_count = pending_count + 1
  evict_pending_overflow()
  if pending[id] ~= entry then return false, "pending_full" end
  return attempt(entry)
end

function M.rule(key, text, opts)
  return enqueue("rule", key, text, opts)
end

function M.event(key, text, opts)
  return enqueue("event", key, text, opts)
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

function M.essential_ready()
  return delivered[identity("rule", ESSENTIAL_GUIDE_KEY)] ~= nil
end

function M.step()
  if next(pending) == nil then return end
  local entries = {}
  for _, entry in pairs(pending) do entries[#entries + 1] = entry end
  table.sort(entries, function(a, b) return a.seq < b.seq end)
  for _, entry in ipairs(entries) do
    if pending[entry.identity] == entry then attempt(entry) end
  end
end

local function open_transport_epoch()
  for _, entry in pairs(pending) do entry.attempts = 0 end
  guide_retry_pending = true
end

M.reconnect_transport = open_transport_epoch

function M.reset_transport()
  open_transport_epoch()
  delivered = {}
  orders = { transient = {}, hint = {}, rule = {} }
end
if rawget(_G, "NEURO_TEST") then
  M._delivered = function() return delivered end
end

return M
