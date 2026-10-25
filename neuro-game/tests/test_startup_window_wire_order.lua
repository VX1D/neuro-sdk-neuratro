_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
if not love then love = {} end
love.timer = { getTime = function() return CLOCK.t end }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("startup-window-wire-order")
local Bridge = require("core.bridge")
local TxCache = require("core.bridge").tx
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

local function frames(dir) return require("tests.helpers").outbox_frames(dir .. "/neuro_outbox.jsonl") end

local function break_outbox_capacity(b)
  b._append = function() return 0 end
  return function() b._append = nil end
end

do
  local b, dir = fresh_bridge()
  local pre = assert(io.open(dir .. "/neuro_outbox.jsonl", "w"))
  pre:write('{"command":"stale"}\n')
  pre:close()

  b:set_message_handler(function(msg)
    if msg.command == "action" then
      b:send_action_result(msg.data.id, true, "answered in the window")
    end
  end)
  local restore_outbox = break_outbox_capacity(b)
  check("a startup the disk refuses is queued ahead of everything else",
    b:send_startup() == true and b._fifo[1] ~= nil and b._fifo[1]:find('"startup"', 1, true) ~= nil)

  feed(dir, '{"command":"action","data":{"id":"win-1","name":"play_hand","data":"{}"}}')
  b:poll_inbox()
  check("no action is read while the startup is still unwritten", #TxCache.outstanding(0) == 0
    and TxCache.get("win-1") == nil, #TxCache.outstanding(0))
  b:send_context("hello from inside the window", false)

  local before = frames(dir)
  check("nothing the mod produced reached the outbox before startup",
    #before == 1 and before[1].command == "stale", #before)

  restore_outbox()
  b:flush_outbox()
  local after = frames(dir)
  check("startup is the very first message the mod sent",
    after[2] and after[2].command == "startup", after[2] and after[2].command)

  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS + 1
  b:update(0)
  local paid, order = 0, nil
  for i, msg in ipairs(frames(dir)) do
    if msg.command == "action/result" and msg.data and msg.data.id == "win-1" then
      paid = paid + 1
      order = order or i
    end
  end
  check("SPECIFICATION.md:166,:169 -- win-1 gets exactly one action/result", paid == 1, paid)
  check("and it follows startup instead of being lost to the failed attempt",
    order ~= nil and order > 1, tostring(order))
  check("nothing is left owed", #TxCache.outstanding(0) == 0, #TxCache.outstanding(0))
end

do
  local b, dir = fresh_bridge()
  feed(dir, '{"command":"neuro-bridge/reregister_all","transport_session":7}')
  local carried_receipt
  b:set_message_handler(function(msg)
    if msg.command == "neuro-bridge/reregister_all" then
      carried_receipt = {}
      b:send_context("re-registered", false, carried_receipt)
    end
  end)
  check("setup: startup completes without dispatching the pre-startup control",
    b:send_startup() ~= false and carried_receipt == nil,
    tostring(carried_receipt ~= nil))
  local out = frames(dir)
  check("a pre-startup reconnect control is consumed before startup",
    #out == 2 and out[1].command == "neuro-bridge/startup_answer"
      and out[1].transport_session == "7" and out[2].command == "startup",
    out[1] and tostring(out[1].command))
end

do
  local b, dir = fresh_bridge()
  check("setup: a healthy startup completes", b:send_startup() ~= false
    and b._startup_complete == true)
  TxCache.open("normal-1", "play_hand", CLOCK.t)
  local accepted = b:send_action_result("normal-1", true, "played")
  check("results go straight to the wire after startup",
    accepted == true and #frames(dir) == 2, tostring(accepted) .. "/" .. #frames(dir))
end

do
  local Protocol = require("core.bridge").wire
  local b, dir = fresh_bridge()
  b.transport_session = 9
  local tag = json.encode(Protocol.startup_answer("Balatro", 9)) .. "\n"
  local limit = b.MAX_OUTBOX_FILE_BYTES - (b.OUTBOX_ROTATION_HEADROOM_BYTES or 0)
  local f = assert(io.open(dir .. "/neuro_outbox.jsonl", "wb"))
  f:seek("set", limit - #tag - 1)
  f:write("\n")
  f:close()
  check("setup: a reconnect startup lands at the rotation boundary",
    b:send_startup({ reconnect = true }) ~= false)
  local rotated = assert(io.open(dir .. "/neuro_outbox.jsonl.1", "rb"))
  rotated:seek("end", -256)
  local rotated_tail = rotated:read("*a")
  rotated:close()
  local out = frames(dir)
  check("an outbox rotation cannot split a startup_answer tag from its startup",
    #out == 2 and out[1].command == "neuro-bridge/startup_answer"
      and out[1].transport_session == "9" and out[2].command == "startup"
      and not rotated_tail:find("startup_answer", 1, true),
    #out .. "/" .. tostring(out[1] and out[1].command))
end

do
  local b, dir = fresh_bridge()
  b:send_startup()
  local Orchestrator = require("core.orchestrator")
  local saved_reset = Orchestrator.reset_run_state
  Orchestrator.reset_run_state = function() b:send_context("emitted during reset", true) end
  require("core.bridge_init").handle_transport_reconnect(11)
  Orchestrator.reset_run_state = saved_reset
  local out = frames(dir)
  local tag, startup, ctx
  for i, msg in ipairs(out) do
    if msg.command == "neuro-bridge/startup_answer" and msg.transport_session == "11" then tag = i end
    if msg.command == "startup" and tag and i == tag + 1 then startup = i end
    if msg.command == "context" and msg.data.message == "emitted during reset" then ctx = i end
  end
  check("a frame produced during the reconnect reset follows the tagged startup",
    tag and startup and ctx and ctx > startup, tostring(tag) .. "/" .. tostring(startup) .. "/" .. tostring(ctx))
end

do
  local b, dir = fresh_bridge()
  b:send_startup()
  local fifo_at_reconnect
  b:set_message_handler(function(msg)
    if msg.command == "neuro-bridge/reregister_all" then
      fifo_at_reconnect = #b._fifo
      b.transport_session = msg.transport_session
      b:send_startup({ reconnect = true })
    end
  end)
  local restore_outbox = break_outbox_capacity(b)
  b:send_context("from the old session", true)
  feed(dir, '{"command":"neuro-bridge/reregister_all","transport_session":12}')
  b:poll_inbox()
  check("a reconnect is not read while an old-session frame is stuck in the FIFO",
    fifo_at_reconnect == nil and #b._fifo == 1, tostring(fifo_at_reconnect))
  restore_outbox()
  CLOCK.t = CLOCK.t + 1
  b:update(0)
  check("it is read once the FIFO drained, with nothing left queued ahead of the startup",
    fifo_at_reconnect == 0, tostring(fifo_at_reconnect))
  local out, old, tag = frames(dir), nil, nil
  for i, msg in ipairs(out) do
    if msg.command == "context" then old = i end
    if msg.command == "neuro-bridge/startup_answer" and msg.transport_session == "12" then tag = i end
  end
  check("the old frame precedes the tagged startup and nothing of the old session follows it",
    old and tag and old < tag and out[tag + 1] and out[tag + 1].command == "startup" and #out == tag + 1,
    tostring(old) .. "/" .. tostring(tag) .. "/" .. #out)
end

TmpWork.close()
done()
