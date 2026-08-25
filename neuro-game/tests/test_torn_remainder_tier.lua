_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
local Bridge = require("core.bridge")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("torn_remainder_tier")

local OUTBOX_TIER_PROTECTED = 2
local OUTBOX_BACKLOG_MAX = 256  -- must exceed this with protected frames to force an eviction pass

local real_open = io.open
local fail_appends = false
local tear_next = nil  -- fraction of the next append that lands before the handle reports failure

io.open = function(path, mode)
  local f = real_open(path, mode)
  if f and tostring(mode):find("a") and (fail_appends or tear_next) then
    local frac = tear_next
    tear_next = nil
    local w = {}
    function w:write(data)
      if frac then
        local keep = math.floor(#data * frac)
        if keep > 0 then f:write(data:sub(1, keep)) end
        f:flush()
      end
      return nil
    end
    function w:flush() return nil end
    function w:close() return f:close() end
    return w
  end
  return f
end

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("torn_remainder")
  .. (tostring({}):match("0x(%x+)") or "0")
os.execute("mkdir -p " .. dir .. " && rm -f " .. dir .. "/*")

local b = Bridge:new({ enabled = true, fs_dir = dir })
G = { NEURO = b, TIMERS = { REAL = 100 } }
b:send_startup()
b._registered_set = { play_hand = true }
b._canonical_defs = { play_hand = { name = "play_hand", description = "d", schema = { type = "object" } } }

fail_appends = false
tear_next = 0.5
b:send_context("SILENT-FACTS-THAT-WILL-TEAR-IN-HALF", true)

local backlog = b._outbox_backlog or {}
check("fixture: exactly one entry was buffered by the tear", #backlog == 1, #backlog)
check("the torn remainder's tier is PROTECTED, not the silent-context tier it started as",
  backlog[1] and backlog[1].tier == OUTBOX_TIER_PROTECTED, tostring(backlog[1] and backlog[1].tier))

fail_appends = true
local pad_count = OUTBOX_BACKLOG_MAX + 44
for i = 1, pad_count do
  local r = { status = "sending" }
  b:send({ command = "action/result", data = { id = "pad-" .. i, success = true, message = "x" } }, r)
end
check("no frame was dropped: the torn remainder survives the eviction pass",
  #(b._outbox_backlog or {}) == pad_count + 1, #(b._outbox_backlog or {}))

fail_appends = false
b:_outbox_flush()
check("the backlog is fully flushed", #(b._outbox_backlog or {}) == 0, #(b._outbox_backlog or {}))

local raw = real_open(dir .. "/" .. b.outbox_file, "rb"):read("*a")
local good, bad, first_bad = 0, 0, nil
for line in raw:gmatch("[^\n]+") do
  local ok = pcall(json.decode, line)
  if ok then good = good + 1 else bad = bad + 1; first_bad = first_bad or line:sub(1, 140) end
end
check("no corrupt (unparseable) lines reached the outbox", bad == 0, tostring(first_bad))
local expected_lines = 2 + pad_count
check("every frame that was ever sent made it to disk intact, none dropped",
  good == expected_lines, good .. " (expected " .. expected_lines .. ")")

io.open = real_open
os.execute("rm -rf " .. dir)
TmpWork.close()
done()
