require("tests.stubs").setup({ love = "lazy" })

local Bridge = require("core.bridge")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")

local check, done = require("tests.helpers").harness("outbox-fifo")

local real_open = io.open
local refuse_appends, tear_next = false, nil
io.open = function(path, mode)
  local f = real_open(path, mode)
  if f and tostring(mode):find("a") and (refuse_appends or tear_next) then
    local frac = tear_next
    tear_next = nil
    local w = {}
    function w:write(data)
      if frac then
        f:write(data:sub(1, math.floor(#data * frac)))
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

local function fresh(label)
  local dir = TmpWork.open("outbox_fifo_" .. label)
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  G = { NEURO = b, TIMERS = { REAL = 100 } }
  return b, dir
end

local function read_lines(path)
  local f = real_open(path, "rb")
  if not f then return {}, 0 end
  local raw = f:read("*a")
  f:close()
  local frames, bad = {}, 0
  for line in raw:gmatch("[^\n]+") do
    local ok, msg = pcall(json.decode, line)
    if ok and type(msg) == "table" then frames[#frames + 1] = msg else bad = bad + 1 end
  end
  return frames, bad
end

local function context(b, text)
  local receipt = {}
  b:send_context(text, true, receipt)
  return receipt
end

do
  local b, dir = fresh("torn")
  b:send_startup()
  tear_next = 0.4
  local torn = context(b, "TORN-IN-THE-MIDDLE")
  check("a torn frame is settled at send time", torn.status == "written", torn.status)
  check("its unwritten remainder stays queued", b:is_transport_saturated())
  refuse_appends = true
  for i = 1, 300 do context(b, "queued-" .. i) end
  check("frames behind a stalled disk are queued, none dropped", #b._fifo == 301, #b._fifo)
  refuse_appends = false
  b:update(0)
  check("the next update drains the queue", not b:is_transport_saturated(), #b._fifo)
  local frames, bad = read_lines(dir .. "/neuro_outbox.jsonl")
  check("the torn line was completed, not restarted, so every line parses", bad == 0, bad)
  local ordered = #frames == 302 and frames[2].data.message == "TORN-IN-THE-MIDDLE"
  for i = 1, 300 do
    ordered = ordered and frames[i + 2].data.message == "queued-" .. i
  end
  check("every frame reached the file once and in send order", ordered, #frames)
end

do
  local b, dir = fresh("inbox_hold")
  local seen = {}
  b:set_message_handler(function(msg) seen[#seen + 1] = msg.command end)
  b:send_startup()
  refuse_appends = true
  context(b, "held")
  local f = real_open(dir .. "/neuro_inbox.jsonl", "ab")
  f:write('{"command":"context","data":{"message":"in","silent":true}}\n')
  f:close()
  b:poll_inbox()
  check("the inbox is not read while the outbox holds unwritten frames", #seen == 0, #seen)
  refuse_appends = false
  b:flush_outbox()
  b:poll_inbox()
  check("it is read once the queue has drained", #seen == 1, #seen)
end

do
  local dir = TmpWork.open("outbox_fifo_tail")
  local f = real_open(dir .. "/neuro_outbox.jsonl", "wb")
  f:write('{"command":"context","data":{"message":"cut')
  f:close()
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  G = { NEURO = b, TIMERS = { REAL = 100 } }
  b:send_startup()
  local frames, bad = read_lines(dir .. "/neuro_outbox.jsonl")
  check("a line torn by an earlier process is closed before startup",
    bad == 1 and frames[1] and frames[1].command == "startup", bad)
end

do
  local b, dir = fresh("rotate")
  b.MAX_OUTBOX_FILE_BYTES = 400
  b:send_startup()
  for i = 1, 3 do context(b, string.rep("r", 100) .. i) end
  local rotated = read_lines(dir .. "/neuro_outbox.jsonl.1")
  local live = read_lines(dir .. "/neuro_outbox.jsonl")
  check("a full outbox is rotated whole to <outbox>.1", #rotated == 3 and #live == 1,
    #rotated .. "/" .. #live)
end

do
  local dir = TmpWork.open("outbox_fifo_torn_full")
  local f = real_open(dir .. "/neuro_outbox.jsonl", "wb")
  f:write(string.rep("x", 400))
  f:close()
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  G = { NEURO = b, TIMERS = { REAL = 100 } }
  b.MAX_OUTBOX_FILE_BYTES = 400
  b:send_startup()
  local rotated = real_open(dir .. "/neuro_outbox.jsonl.1", "rb")
  local tail = rotated and rotated:read("*a") or ""
  if rotated then rotated:close() end
  local live = read_lines(dir .. "/neuro_outbox.jsonl")
  check("a torn line is finished in its own file before that file is rotated",
    #tail == 401 and tail:sub(-1) == "\n" and live[1] and live[1].command == "startup", #tail)
end

io.open = real_open
TmpWork.close()
done()
