_G.NEURO_TEST = true

local clock = 1000
if not love then love = {} end
love.timer = {
  getTime = function() return clock end,
  getFPS = function() return 60 end,
  getAverageDelta = function() return 0.01 end,
}
local fs_lines = {}
love.filesystem = {
  getInfo = function() return nil end,
  append = function(_, data) fs_lines[#fs_lines + 1] = data; return true end,
}

local check, done = require("tests.helpers").harness("metrics")

local Metrics = require("util.metrics")

check("incr records without any prior enable call",
  (function()
    Metrics.incr("default_on_probe")
    return Metrics._counters["default_on_probe"] == 1
  end)())

check("incr keeps accumulating on repeated calls",
  (function()
    Metrics.incr("default_on_probe", 4)
    return Metrics._counters["default_on_probe"] == 5
  end)())

check("set records a gauge without any prior enable call",
  (function()
    Metrics.set("default_on_gauge", 7)
    return Metrics._gauges["default_on_gauge"] == 7
  end)())

check("time_begin/time_end record a timing without any prior enable call",
  (function()
    Metrics.time_begin("default_on_timer")
    clock = clock + 0.5
    Metrics.time_end("default_on_timer")
    local t = Metrics._timings["default_on_timer"]
    return t ~= nil and t.n == 1 and t.last > 0
  end)())

check("record_timing works standalone without any prior enable call",
  (function()
    Metrics.record_timing("default_on_direct", 0.25)
    local t = Metrics._timings["default_on_direct"]
    return t ~= nil and t.last == 250
  end)())

local Config = require("core.config")
local Json = require("util.neuro_json")
local DS = require("render.debug_stats")

-- One append can carry several batched records, so split before decoding.
local function decoded_records(from)
  local out = {}
  for i = (from or 1), #fs_lines do
    for chunk in tostring(fs_lines[i]):gmatch("[^\n]+") do
      local ok, decoded = pcall(Json.decode, chunk)
      if ok and type(decoded) == "table" then out[#out + 1] = decoded end
    end
  end
  return out
end

local function counter_lines()
  local out = {}
  for _, decoded in ipairs(decoded_records()) do
    if type(decoded.counters) == "table" then out[#out + 1] = decoded end
  end
  return out
end

Config.set("NEURO_PERF_LOG", "off")
Metrics.incr("dispatch_drop_test_probe", 3)
DS.sample(0.016)
check("the perf overlay writes no counters of its own -- one owner, one sink",
  #counter_lines() == 0, tostring(#counter_lines()))

check("flush persists the counters with the overlay OFF", Metrics.flush(true) == true)
local snap = counter_lines()
check("the snapshot carries the live counter values",
  #snap == 1 and snap[1].counters.dispatch_drop_test_probe == 3,
  "lines=" .. tostring(#snap))

Metrics.incr("dispatch_drop_test_probe", 1)
check("an immediate unforced flush is throttled away", Metrics.flush() == false)
check("and wrote nothing", #counter_lines() == 1, tostring(#counter_lines()))

check("a forced flush always writes -- shutdown has no later chance",
  Metrics.flush(true) == true and #counter_lines() == 2, tostring(#counter_lines()))

Config.set("NEURO_PERF_LOG", "on")
local before = #fs_lines
DS.sample(0.016)
local saw_perf_line = false
for _, decoded in ipairs(decoded_records(before + 1)) do
  if decoded.fps then saw_perf_line = true end
end
check("debug_stats still writes the frame-timing perf line when NEURO_PERF_LOG is on", saw_perf_line)

done()
