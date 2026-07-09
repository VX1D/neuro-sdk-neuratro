local M = {}

M._on = false
M._counters = {}
M._gauges = {}
M._timings = {}
M._starts = {}

local function wall()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function M.set_enabled(b) M._on = not not b end

function M.incr(name, by)
  if not M._on then return end
  M._counters[name] = (M._counters[name] or 0) + (by or 1)
end

function M.set(name, value)
  if not M._on then return end
  M._gauges[name] = value
end

function M.record_timing(label, seconds)
  if not M._on then return end
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
  if not M._on then return end
  M._starts[label] = wall()
end

function M.time_end(label)
  if not M._on then return end
  local s = M._starts[label]
  if not s then return end
  M._starts[label] = nil
  M.record_timing(label, wall() - s)
end

return M
