_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
if not love then love = {} end
love.timer = { getTime = function() return CLOCK.t end }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("startup-retry-ledger")
local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")

local dir_seq = 0
local function fresh_bridge()
  dir_seq = dir_seq + 1
  local dir = TmpWork.open("startup_retry_" .. dir_seq)
  os.execute("rm -rf '" .. dir .. "'; mkdir -p '" .. dir .. "'")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  G.NEURO = b
  b:set_message_handler(function() end)
  return b, dir
end

local function feed(dir, line)
  local f = assert(io.open(dir .. "/neuro_inbox.jsonl", "a"))
  f:write(line .. "\n")
  f:close()
end

local function count_results(dir)
  local n = 0
  local f = io.open(dir .. "/neuro_outbox.jsonl", "r")
  if not f then return 0 end
  for line in f:lines() do
    local ok, msg = pcall(json.decode, line)
    if ok and type(msg) == "table" and msg.command == "action/result" then n = n + 1 end
  end
  f:close()
  return n
end

local function break_outbox_truncate(b)
  local real_write = b.write_file
  b.write_file = function(self, file, data)
    if file == self.outbox_file and data == "" then return false end
    return real_write(self, file, data)
  end
end

do
  TxCache.reset()
  local b, dir = fresh_bridge()
  break_outbox_truncate(b)
  check("a startup whose outbox truncate fails reports failure", b:send_startup() == false)

  feed(dir, '{"command":"action","data":{"id":"orphan-1","name":"play_hand","data":"{}"}}')
  b:poll_inbox()
  check("the action delivered while the retry is pending is booked",
    #TxCache.outstanding(0) == 1, #TxCache.outstanding(0))

  b.write_file = nil
  check("the retry succeeds once the disk recovers", b:send_startup() == true)
  check("the retry keeps the obligation booked between the attempts",
    #TxCache.outstanding(0) == 1, #TxCache.outstanding(0))

  CLOCK.t = CLOCK.t + 100
  b:update(0)
  check("SPECIFICATION.md:165-167 -- orphan-1 gets exactly one action/result",
    count_results(dir) == 1, count_results(dir))
end

do
  TxCache.reset()
  local b, dir = fresh_bridge()
  check("setup: first startup completes", b:send_startup() == true)
  feed(dir, '{"command":"action","data":{"id":"dead-1","name":"play_hand","data":"{}"}}')
  b:poll_inbox()
  check("setup: the action is booked", #TxCache.outstanding(0) == 1, #TxCache.outstanding(0))
  check("a new session startup still wipes the previous session's ledger",
    b:send_startup() == true and #TxCache.outstanding(0) == 0, #TxCache.outstanding(0))
end

-- R6: the mechanism, pinned directly -- the destructive session reset runs once per startup
-- sequence, not once per attempt. reset_tx also drops prepared/awaiting jobs without walking
-- abort_prepared, which core/dispatcher.lua:169-171 warns is how the next action gets stuck.
do
  TxCache.reset()
  local real_reset_tx = Dispatcher.reset_tx
  local calls = 0
  Dispatcher.reset_tx = function(...) calls = calls + 1 return real_reset_tx(...) end

  local b = fresh_bridge()
  break_outbox_truncate(b)
  b:send_startup()
  local after_first = calls
  b:send_startup()
  local after_retry = calls
  b.write_file = nil
  b:send_startup()
  local after_success = calls
  Dispatcher.reset_tx = real_reset_tx

  check("the first attempt performs the session reset", after_first == 1, after_first)
  check("a retry does not repeat it", after_retry == 1, after_retry)
  check("the successful retry does not repeat it either", after_success == 1, after_success)
end

do
  TxCache.reset()
  local b, dir = fresh_bridge()
  feed(dir, '{"command":"actions/reregister_all","transport_session":7}')
  local seen = {}
  b:set_message_handler(function(msg) seen[#seen + 1] = msg.command end)
  break_outbox_truncate(b)
  b:send_startup()
  check("setup: the failed attempt delivers nothing", #seen == 0, #seen)
  b.write_file = nil
  b:send_startup()
  check("the retry still delivers the carried session-independent frame",
    #seen == 1 and seen[1] == "actions/reregister_all", table.concat(seen, ","))
end

TmpWork.close()
done()
