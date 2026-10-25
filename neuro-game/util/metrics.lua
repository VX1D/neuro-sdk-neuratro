local M = {}

M._counters = {}
M._gauges = {}
M._timings = {}
M._starts = {}

local function wall()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
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
    t = { ema = 0, last = 0, max = 0 }
    M._timings[label] = t
  end
  t.last = ms
  t.ema = t.ema == 0 and ms or (t.ema * 0.9 + ms * 0.1)
  if ms > t.max then t.max = ms else t.max = t.max * 0.98 + ms * 0.02 end
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
