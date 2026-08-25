_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
if not love then love = {} end
love.timer = { getTime = function() return CLOCK.t end }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("startup-window-wire-order")
local Bridge = require("core.bridge")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")

local dir_seq = 0
local function fresh_bridge()
  dir_seq = dir_seq + 1
  local dir = TmpWork.open("startup_window_" .. dir_seq)
  os.execute("rm -rf '" .. dir .. "'; mkdir -p '" .. dir .. "'")
  TxCache.reset()
  CLOCK.t = 1000
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  G.NEURO = b
  return b, dir
end

local function feed(dir, line)
  local f = assert(io.open(dir .. "/neuro_inbox.jsonl", "a"))
  f:write(line .. "\n")
  f:close()
end

local function frames(dir)
  local out = {}
  local f = io.open(dir .. "/neuro_outbox.jsonl", "r")
  if not f then return out end
  for line in f:lines() do
    local ok, msg = pcall(json.decode, line)
    if ok and type(msg) == "table" then out[#out + 1] = msg end
  end
  f:close()
  return out
end

local function break_outbox_truncate(b)
  local real_write = b.write_file
  b.write_file = function(self, file, data)
    if file == self.outbox_file and data == "" then return false end
    return real_write(self, file, data)
  end
end

do
  local b, dir = fresh_bridge()
  local pre = assert(io.open(dir .. "/neuro_outbox.jsonl", "w"))
  pre:write('{"command":"stale"}\n')
  pre:close()

  b:set_message_handler(function(msg)
    if msg.command == "action" then b:send_action_result(msg.data.id, true, "answered in the window") end
  end)
  break_outbox_truncate(b)
  check("a startup whose outbox truncate fails reports failure and stays pending",
    b:send_startup() == false and b._startup_complete == nil and b._startup_pending == true)

  feed(dir, '{"command":"action","data":{"id":"win-1","name":"play_hand","data":"{}"}}')
  b:poll_inbox()
  check("an action delivered while the retry is pending is still booked",
    #TxCache.outstanding(0) == 1, #TxCache.outstanding(0))
  check("its result is refused rather than written ahead of startup",
    #TxCache.outstanding(0) == 1 and TxCache.get("win-1") == nil,
    TxCache.get("win-1") and "verdict committed" or "owed")

  local ctx_receipt = {}
  b:send_context("hello from inside the window", false, ctx_receipt)
  check("so is every other frame -- the rule is about the wire, not about results",
    ctx_receipt.status == "rejected", tostring(ctx_receipt.status))

  local before = frames(dir)
  check("nothing the mod produced reached the outbox before startup",
    #before == 1 and before[1].command == "stale", #before)

  b.write_file = nil
  check("setup: the retry succeeds once the disk recovers", b:send_startup() == true)
  local after = frames(dir)
  check("startup is the very first message the mod sent",
    after[1] and after[1].command == "startup", after[1] and after[1].command)

  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS + 1
  b:update(0)
  local paid, order = 0, nil
  for i, msg in ipairs(frames(dir)) do
    if msg.command == "action/result" and msg.data and msg.data.id == "win-1" then
      paid = paid + 1
      order = order or i
    end
  end
  check("SPECIFICATION.md:165-167 -- win-1 gets exactly one action/result", paid == 1, paid)
  check("and it follows startup instead of being erased by the retry's truncate",
    order ~= nil and order > 1, tostring(order))
  check("nothing is left owed", #TxCache.outstanding(0) == 0, #TxCache.outstanding(0))
end

do
  local b, dir = fresh_bridge()
  feed(dir, '{"command":"actions/reregister_all","transport_session":7}')
  local carried_receipt
  b:set_message_handler(function(msg)
    if msg.command == "actions/reregister_all" then
      carried_receipt = {}
      b:send_context("re-registered", false, carried_receipt)
    end
  end)
  check("setup: the startup completes and delivers the carried frame",
    b:send_startup() == true and carried_receipt ~= nil)
  check("a frame sent while draining the carried inbox is admitted, not refused",
    carried_receipt and carried_receipt.status == "written", carried_receipt and tostring(carried_receipt.status))
  local out = frames(dir)
  check("and it still follows startup on the wire",
    out[1] and out[1].command == "startup" and #out >= 2, out[1] and out[1].command)
end

do
  local b, dir = fresh_bridge()
  check("setup: a healthy startup completes", b:send_startup() == true
    and b._startup_pending == nil and b._startup_complete == true)
  TxCache.open("normal-1", "play_hand", CLOCK.t)
  local accepted, receipt = b:send_action_result("normal-1", true, "played")
  check("results go straight to the wire after startup",
    accepted == true and receipt.status == "written" and #frames(dir) == 2,
    tostring(receipt and receipt.status) .. "/" .. #frames(dir))
end

TmpWork.close()
done()
