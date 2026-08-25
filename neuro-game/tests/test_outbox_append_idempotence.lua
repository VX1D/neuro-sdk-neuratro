_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

math.randomseed(20260722)

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
local Bridge = require("core.bridge")
local Protocol = require("core.bridge_protocol")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("outbox-append-idempotence")

local real_open = io.open
local pending_fault = nil

local function fault(fraction)
  pending_fault = fraction
end

io.open = function(path, mode)
  local f = real_open(path, mode)
  if f and pending_fault and tostring(mode):find("a") then
    local fraction = pending_fault
    pending_fault = nil
    local wrapped = {}
    function wrapped:write(data)
      local keep = math.floor(#data * fraction)
      if keep > 0 then f:write(data:sub(1, keep)) end
      f:flush()
      return nil
    end
    function wrapped:flush() return nil end
    function wrapped:close() return f:close() end
    return wrapped
  end
  return f
end

local TmpWork = require("tests.tmp_workdir")
local WORK = TmpWork.open("neuro_append_idem")
local bridge_n = 0

local function new_bridge()
  bridge_n = bridge_n + 1
  local dir = WORK .. "/b" .. bridge_n
  os.execute("mkdir -p " .. dir)
  local bridge = Bridge:new({ enabled = true, fs_dir = dir })
  G = { NEURO = bridge, TIMERS = { REAL = 100 } }
  bridge.run_generation = 1
  bridge.state = "SELECTING_HAND"
  bridge:send_startup()
  bridge._registered_set = { play_hand = true, discard_hand = true }
  return bridge, dir
end

local function frames(bridge, dir)
  local f = real_open(dir .. "/" .. bridge.outbox_file, "rb")
  if not f then return {}, {} end
  local raw = f:read("*a")
  f:close()
  local lines, decoded = {}, {}
  for line in raw:gmatch("[^\n]+") do
    lines[#lines + 1] = line
    local ok, frame = pcall(json.decode, line)
    decoded[#decoded + 1] = ok and frame or { command = "UNPARSEABLE" }
  end
  return lines, decoded
end

local function count(decoded, command)
  local n = 0
  for _, f in ipairs(decoded) do if f.command == command then n = n + 1 end end
  return n
end

local function adjacent_duplicates(lines)
  local n = 0
  for i = 2, #lines do if lines[i] == lines[i - 1] then n = n + 1 end end
  return n
end

do
  local bridge, dir = new_bridge()
  fault(1.0)
  bridge:send(Protocol.force("SELECTING_HAND", "Q", { "play_hand", "discard_hand" }))
  bridge:send_action_result("abc", true)
  local lines, decoded = frames(bridge, dir)
  check("the force reached the wire exactly once", count(decoded, "actions/force") == 1,
    count(decoded, "actions/force") .. " force frames")
  check("no frame is byte-identical to the one before it", adjacent_duplicates(lines) == 0,
    adjacent_duplicates(lines) .. " adjacent duplicates")
  check("the frame that followed it is still there", count(decoded, "action/result") == 1)
  os.execute("rm -rf '" .. dir .. "'")
end

do
  local bridge, dir = new_bridge()
  fault(0.4)
  bridge:send(Protocol.force("SELECTING_HAND", "Q", { "play_hand", "discard_hand" }))
  bridge:send_action_result("abc", true)
  local lines, decoded = frames(bridge, dir)
  check("the torn line was completed, not restarted",
    count(decoded, "actions/force") == 1 and count(decoded, "UNPARSEABLE") == 0,
    count(decoded, "actions/force") .. " force, " .. count(decoded, "UNPARSEABLE") .. " unparseable")
  check("and the frame after it still followed", count(decoded, "action/result") == 1)
  os.execute("rm -rf '" .. dir .. "'")
end

do
  local bridge, dir = new_bridge()
  fault(0.0)
  bridge:send(Protocol.force("SELECTING_HAND", "Q", { "play_hand", "discard_hand" }))
  local _, mid = frames(bridge, dir)
  check("nothing was written while the disk refused it", count(mid, "actions/force") == 0)
  bridge:send_action_result("abc", true)
  local lines, decoded = frames(bridge, dir)
  check("the buffered force was replayed once the disk came back",
    count(decoded, "actions/force") == 1, count(decoded, "actions/force") .. " force frames")
  check("and only once", adjacent_duplicates(lines) == 0)
  os.execute("rm -rf '" .. dir .. "'")
end

do
  local Metrics = require("util.metrics")
  local bridge, dir = new_bridge()
  local before = Metrics._counters["ipc_duplicate_frame"] or 0
  bridge:send(Protocol.force("SELECTING_HAND", "Q", { "play_hand", "discard_hand" }))
  check("a single force raises nothing",
    (Metrics._counters["ipc_duplicate_frame"] or 0) == before)
  local receipt = { status = "sending" }
  local accepted = bridge:send(
    Protocol.force("SELECTING_HAND", "Q", { "play_hand", "discard_hand" }), receipt)
  local _, decoded = frames(bridge, dir)
  check("the same frame is counted, rejected, and absent from the wire",
    accepted == false
      and (Metrics._counters["ipc_duplicate_frame"] or 0) == before + 1
      and count(decoded, "actions/force") == 1,
    tostring(Metrics._counters["ipc_duplicate_frame"]))
  os.execute("rm -rf '" .. dir .. "'")
end

do
  local bridge, dir = new_bridge()
  fault(0.4)
  bridge:send(Protocol.context(string.rep("torn-context-", 20), true))
  for i = 1, 400 do
    local message = Protocol.context("droppable-" .. tostring(i), true)
    bridge:_outbox_push(json.encode(message) .. "\n", message)
  end
  bridge:send_action_result("after-pressure", true)
  local _, decoded = frames(bridge, dir)
  check("backlog pressure cannot evict a torn frame remainder",
    count(decoded, "UNPARSEABLE") == 0, count(decoded, "UNPARSEABLE"))
  check("a protected result still follows the repaired JSONL frame",
    count(decoded, "action/result") == 1)
  os.execute("rm -rf '" .. dir .. "'")
end

io.open = real_open
TmpWork.close()
done()
