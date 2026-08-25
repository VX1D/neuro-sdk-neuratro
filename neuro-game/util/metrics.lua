local M = {}

M._counters = {}
M._gauges = {}
M._timings = {}
M._starts = {}

local function wall()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local METRICS_FILE = "neuro_metrics.jsonl"
local FLUSH_INTERVAL = 30
local FLUSH_CAP = 2 * 1024 * 1024
local _flush_next_at = 0
local _flush_bytes = nil

local function encode_counters()
  local ok, Json = pcall(require, "util.neuro_json")
  if not (ok and Json and type(Json.encode) == "function") then return nil end
  local ok_enc, body = pcall(Json.encode, { t = wall(), counters = M._counters, gauges = M._gauges })
  if not ok_enc or type(body) ~= "string" then return nil end
  return body .. "\n"
end

function M.flush(force)
  if not (love and love.filesystem and love.filesystem.append) then return false end
  local now = wall()
  local wait = _flush_next_at - now
  if not force and wait > 0 and wait <= FLUSH_INTERVAL then return false end
  _flush_next_at = now + FLUSH_INTERVAL
  if _flush_bytes == nil then
    local info = love.filesystem.getInfo and love.filesystem.getInfo(METRICS_FILE)
    _flush_bytes = (info and info.size) or 0
  end
  if _flush_bytes >= FLUSH_CAP then return false end
  local line = encode_counters()
  if not line then return false end
  _flush_bytes = _flush_bytes + #line
  local ok = pcall(love.filesystem.append, METRICS_FILE, line)
  return ok
end

function M.incr(name, by)
  M._counters[name] = (M._counters[name] or 0) + (by or 1)
end

function M.set(name, value)
  M._gauges[name] = value
end

function M.record_timing(label, seconds)
  local ms = seconds * 1000
  local t = M._timings[label]
  if not t then
    t = { ema = 0, last = 0, max = 0, n = 0 }
    M._timings[label] = t
  end
  t.last = ms
  t.ema = t.ema == 0 and ms or (t.ema * 0.9 + ms * 0.1)
  if ms > t.max then t.max = ms else t.max = t.max * 0.98 + ms * 0.02 end
  t.n = t.n + 1
end

function M.time_begin(label)
  M._starts[label] = wall()
end

function M.time_end(label)
  local s = M._starts[label]
  if not s then return end
  M._starts[label] = nil
  M.record_timing(label, wall() - s)
end

return M
