_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, TIMERS = { REAL = 1000 } }

local Bridge = require("core.bridge")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local check, done = require("tests.helpers").harness("result-ledger")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("result_ledger")
local INBOX = dir .. "/neuro_inbox.jsonl"
local OUTBOX = dir .. "/neuro_outbox.jsonl"

local function fresh(handler)
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  CLOCK.t = 1000
  TxCache.reset()
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b:set_message_handler(handler)
  return b
end

local function append_inbox(lines)
  local f = assert(io.open(INBOX, "a"))
  for _, line in ipairs(lines) do f:write(line, "\n") end
  f:close()
end

local function action_line(id, name)
  return string.format('{"command":"action","data":{"id":%q,"name":%q}}', id, name)
end

local function results()
  local per_id, total = {}, 0
  local f = io.open(OUTBOX, "r")
  if not f then return per_id, total end
  for line in f:lines() do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" and frame.command == "action/result" then
      local id = tostring(frame.data and frame.data.id)
      total = total + 1
      per_id[id] = per_id[id] or { count = 0 }
      per_id[id].count = per_id[id].count + 1
      per_id[id].success = frame.data.success
      per_id[id].message = frame.data.message
    end
  end
  f:close()
  return per_id, total
end

local function settle(b)
  b:poll_inbox()
  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS + 1
  b:update(0)
end

do
  TxCache.reset()
  check("open books an obligation without inventing a verdict",
    TxCache.open("led-1", "play_hand", 10) == true and TxCache.get("led-1") == nil
      and #TxCache.outstanding(0) == 1)
  check("claim succeeds exactly once", TxCache.claim("led-1") == true and TxCache.claim("led-1") == false)
  check("a bare claim cannot burn the outstanding obligation",
    #TxCache.outstanding(0) == 1 and TxCache.get("led-1") == nil and TxCache.claim("led-1") == false)
  check("reopening a claimed id is refused without erasing its obligation",
    TxCache.open("led-1", "play_hand", 20) == false and #TxCache.outstanding(0) == 1)
  check("releasing an uncommitted claim makes the same obligation sendable again",
    TxCache.release_claim("led-1") == true and TxCache.claim("led-1") == true)

  TxCache.reset()
  TxCache.open("led-2", "cash_out", 10)
  TxCache.store("led-2", true, "done", "cash_out", nil)
  check("store answers the obligation and records the replayable verdict",
    #TxCache.outstanding(0) == 0 and TxCache.get("led-2") ~= nil and TxCache.get("led-2").ok == true)
  check("an id answered by store cannot be claimed again", TxCache.claim("led-2") == false)
  TxCache.invalidate("led-2")
  check("invalidate drops the verdict without reopening the right to answer",
    TxCache.get("led-2") == nil and TxCache.claim("led-2") == false and #TxCache.outstanding(0) == 0)

  TxCache.reset()
  check("an id nobody opened is locked by a claim until it is released or committed",
    TxCache.claim("led-3") == true and TxCache.claim("led-3") == false
      and TxCache.release_claim("led-3") == true and TxCache.claim("led-3") == true)
  check("a nil id is never tracked and never blocks", TxCache.claim(nil) == true
    and TxCache.claim(nil) == true and TxCache.open(nil) == false)
  TxCache.reset()
end

do
  local b = fresh(function() end)
  TxCache.open("send-throw", "play_hand", CLOCK.t)
  local original_send = b.send
  b.send = function() error("serializer exploded") end
  local ok = pcall(b.send_action_result, b, "send-throw", true, "ok")
  check("a thrown result send returns its claim to the obligation ledger",
    not ok and #TxCache.outstanding(CLOCK.t) == 1)
  b.send = original_send
  b:answer_owed_results(nil, "recovered")
  local per_id = results()
  check("the returned result claim is payable exactly once after recovery",
    per_id["send-throw"] and per_id["send-throw"].count == 1
      and per_id["send-throw"].message == "recovered")
end

do
  local b = fresh(function() end)
  TxCache.open("send-disabled", "play_hand", CLOCK.t)
  b.enabled = false
  local accepted = b:send_action_result("send-disabled", true, "must not disappear")
  check("a disabled result send is rejected and leaves the obligation outstanding",
    accepted == false and #TxCache.outstanding(CLOCK.t) == 1)
  b.enabled = true
  b:answer_owed_results(nil, "recovered after enable")
  local per_id = results()
  check("the rejected result is payable exactly once after enable",
    per_id["send-disabled"] and per_id["send-disabled"].count == 1
      and per_id["send-disabled"].success == true)
end

do
  local b = fresh(function() end)
  G.NEURO.transport_session = 10
  TxCache.open("session-replay", "cash_out", CLOCK.t)
  b:send_action_result("session-replay", true, "settled")
  TxCache.store("session-replay", true, "settled", "cash_out")
  local before = select(2, results())
  check("cached result is not replayed twice within one transport session",
    b:replay_action_result("session-replay", true, "settled") == false
      and select(2, results()) == before)
  G.NEURO.transport_session = 11
  b:reset_delivery_memory() -- production does this while handling actions/reregister_all
  b:replay_action_result("session-replay", true, "settled")
  local per_id, after = results()
  check("cached result is replayed once to a newly connected transport session",
    after == before + 1 and per_id["session-replay"].count == 2)
  check("the reconnect replay remains deduplicated inside the new session",
    b:replay_action_result("session-replay", true, "settled") == false
      and select(2, results()) == after)
  G.NEURO.transport_session = nil
end

do
  local b = fresh(function() end)
  TxCache.store("replay-disabled", true, "old verdict", "cash_out")
  G.NEURO.transport_session = 21
  b.enabled = false
  check("a rejected reconnect replay does not consume the new session's replay slot",
    b:replay_action_result("replay-disabled", true, "old verdict") == false)
  b.enabled = true
  check("the same reconnect replay is delivered after the bridge recovers",
    b:replay_action_result("replay-disabled", true, "old verdict") == true)
  local per_id = results()
  check("the recovered reconnect replay reaches the wire exactly once",
    per_id["replay-disabled"] and per_id["replay-disabled"].count == 1)
  G.NEURO.transport_session = nil
end

do
  local b = fresh(function() end)
  local original_send = b.send
  b.send = function() error("register serializer exploded") end
  local ok_register = pcall(b.register_actions, b, {
    { name = "retry_action", description = "retry", schema = { type = "object" } },
  })
  check("a thrown register send does not advance the local catalogue shadow",
    not ok_register and not (b._registered_set and b._registered_set.retry_action)
      and b._last_register_key == nil)
  b.send = original_send
  local retry_ok = pcall(b.register_actions, b, {
    { name = "retry_action", description = "retry", schema = { type = "object" } },
  })
  check("a register whose first send threw is retried after transport recovery",
    retry_ok and b._registered_set and b._registered_set.retry_action == true)
end

local HANDLERS = {
  {
    name = "handler answers once",
    fn = function(b) return function(msg) b:send_action_result(msg.data.id, true, "ok") end end,
    expect_success = true,
  },
  {
    name = "handler answers twice",
    fn = function(b)
      return function(msg)
        b:send_action_result(msg.data.id, true, "first")
        b:send_action_result(msg.data.id, false, "second")
      end
    end,
    expect_success = true,
    expect_message = "first",
  },
  {
    name = "handler never answers",
    fn = function() return function() end end,
    expect_success = true,
  },
  {
    name = "handler throws before answering",
    fn = function() return function() error("boom before") end end,
    expect_success = true,
  },
  {
    name = "handler throws after answering",
    fn = function(b)
      return function(msg)
        b:send_action_result(msg.data.id, true, "ok")
        error("boom after")
      end
    end,
    expect_success = true,
  },
  {
    name = "handler answers the wrong id",
    fn = function(b) return function() b:send_action_result("foreign-id", true, "ok") end end,
    expect_success = true,
    foreign = "foreign-id",
  },
}

for _, case in ipairs(HANDLERS) do
  local b
  b = fresh(function(msg) return nil end)
  b:set_message_handler(case.fn(b))
  append_inbox({ action_line("case-1", "play_hand") })
  settle(b)
  local per_id, total = results()
  local entry = per_id["case-1"]
  check(case.name .. ": exactly one action/result for the delivered id",
    entry ~= nil and entry.count == 1, entry and entry.count or "none")
  if entry then
    check(case.name .. ": the surviving result reports the expected verdict",
      entry.success == case.expect_success, tostring(entry.success))
    if case.expect_message then
      check(case.name .. ": the first result is the one that survives",
        entry.message == case.expect_message, tostring(entry.message))
    end
  end
  if case.foreign then
    local foreign = per_id[case.foreign]
    check(case.name .. ": the foreign id is answered exactly once and does not discharge the delivered one",
      foreign ~= nil and foreign.count == 1 and total == 2, total)
  else
    check(case.name .. ": no result is emitted for any id that was never delivered", total == 1, total)
  end
end

do
  local b
  b = fresh(function() end)
  b:set_message_handler(function(msg) b:send_action_result(msg.data.id, true, "ok") end)
  append_inbox({ action_line("redelivered", "cash_out"), action_line("redelivered", "cash_out") })
  settle(b)
  local per_id, total = results()
  check("a redelivered id is answered exactly once", total == 1 and per_id["redelivered"].count == 1, total)
end

do
  local b = fresh(function() error("handler must not decide whether the obligation exists") end)
  append_inbox({ action_line("pre-booked", "play_hand") })
  b:poll_inbox()
  check("delivery books the obligation before the handler runs", #TxCache.outstanding(0) == 1,
    #TxCache.outstanding(0))
  local per_id = results()
  check("the deadline has not passed yet, so nothing is paid early", per_id["pre-booked"] == nil)
  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS + 1
  b:update(0)
  per_id = results()
  check("the sweep pays it once the deadline passes",
    per_id["pre-booked"] ~= nil and per_id["pre-booked"].count == 1)
  b:update(0)
  b:update(0)
  per_id = results()
  check("repeated sweeps do not pay the same id twice",
    per_id["pre-booked"] ~= nil and per_id["pre-booked"].count == 1,
    per_id["pre-booked"] and per_id["pre-booked"].count)
end

-- An action with no addressable id cannot be answered: SPECIFICATION.md:222 makes id a string, and a
-- result carrying no id addresses nothing.
do
  local b = fresh(function() end)
  append_inbox({ '{"command":"action","data":{"name":"play_hand"}}',
    '{"command":"context","data":{"message":"hi"}}',
    '{"command":"actions/reregister_all"}' })
  settle(b)
  local _, total = results()
  check("a frame with no action id and non-action frames owe nothing", total == 0, total)
end

do
  package.loaded["core.bridge_init"] = nil
  local BridgeInit = require("core.bridge_init")
  local Paths = require("core.mod_paths")
  local saved_read_ipc_dir = Paths.read_ipc_dir
  Paths.read_ipc_dir = function() return nil end
  local saved_love, saved_neuro = _G.love, G.NEURO
  local original_quit_called = false
  local b = fresh(function() end)
  _G.love = { quit = function() original_quit_called = true end,
    timer = { getTime = function() return CLOCK.t end } }
  G.NEURO = b

  append_inbox({ action_line("quit-1", "play_hand"), action_line("quit-2", "cash_out") })
  b:poll_inbox()
  check("shutdown fixture: two actions are outstanding before quit", #TxCache.outstanding(0) == 2,
    #TxCache.outstanding(0))

  BridgeInit.hook_love_quit()
  _G.love.quit()

  local per_id, total = results()
  check("quit answers every outstanding action exactly once",
    total == 2 and per_id["quit-1"] and per_id["quit-1"].count == 1
      and per_id["quit-2"] and per_id["quit-2"].count == 1, total)
  check("the shutdown result acknowledges without retrying the dead force",
    per_id["quit-1"] and per_id["quit-1"].success == true
      and per_id["quit-1"].message == Bridge.OWED_SHUTDOWN_MESSAGE,
    per_id["quit-1"] and tostring(per_id["quit-1"].message))
  check("quit still calls through to the original love.quit", original_quit_called == true)
  check("quit leaves nothing owed", #TxCache.outstanding(0) == 0, #TxCache.outstanding(0))

  local flushed = fresh(function() end)
  G.NEURO = flushed
  flushed:send_action_result("backlogged", true, "buffered")
  flushed._outbox_backlog = { { line = '{"command":"action/result","data":{"id":"backlogged-2","success":true}}\n',
    tier = 2 } }
  package.loaded["core.bridge_init"] = nil
  local BridgeInit2 = require("core.bridge_init")
  BridgeInit2.hook_love_quit()
  _G.love.quit()
  local per_id2 = results()
  check("quit flushes results still sitting in the outbox backlog",
    per_id2["backlogged-2"] ~= nil and per_id2["backlogged-2"].count == 1)

  G.NEURO, _G.love = saved_neuro, saved_love
  Paths.read_ipc_dir = saved_read_ipc_dir
  package.loaded["core.bridge_init"] = nil
end

local function archive_frames()
  local frames, ids = {}, {}
  local f = assert(io.open("tests/fixtures/s2c_archive.jsonl", "r"))
  for line in f:lines() do
    if line ~= "" then
      frames[#frames + 1] = line
      local ok, frame = pcall(json.decode, line)
      if ok and type(frame) == "table" and frame.command == "action"
        and type(frame.data) == "table" and type(frame.data.id) == "string" and frame.data.id ~= "" then
        ids[#ids + 1] = frame.data.id
      end
    end
  end
  f:close()
  return frames, ids
end

local ORPHANS = { "ec3322c7caa041339161de03d852c8af", "1cf1ca49f8c449958c5993dc2cb5f7f3",
  "35c4cd08a4234ad98e5d391f1eecdb63" }

do
  local frames, ids = archive_frames()
  check("archive fixture carries the real corpus", #frames == 596 and #ids == 585, #frames .. "/" .. #ids)

  for _, mode in ipairs({ "silent", "answering" }) do
    local b
    b = fresh(function() end)
    if mode == "answering" then
      b:set_message_handler(function(msg)
        if msg.command == "action" and msg.data and type(msg.data.id) == "string" then
          b:send_action_result(msg.data.id, true, nil)
        end
      end)
    end
    append_inbox(frames)
    settle(b)
    local per_id, total = results()
    local missing, doubled = 0, 0
    for _, id in ipairs(ids) do
      local entry = per_id[id]
      if not entry then missing = missing + 1
      elseif entry.count ~= 1 then doubled = doubled + 1 end
    end
    check("archive/" .. mode .. ": every real action is answered exactly once",
      missing == 0 and doubled == 0 and total == #ids,
      string.format("missing=%d doubled=%d total=%d", missing, doubled, total))
    for _, id in ipairs(ORPHANS) do
      check("archive/" .. mode .. ": the archived orphan " .. id:sub(1, 8) .. " is answered by the mod",
        per_id[id] ~= nil and per_id[id].count == 1)
    end
  end
end

do
  local f = io.open("../neuro-bridge-rs/src/main.rs", "r")
  check("the bridge source is readable for the deadline-ordering check", f ~= nil)
  if f then
    local src = f:read("*a")
    f:close()
    local secs = tonumber(src:match("DEFAULT_ORPHAN_TIMEOUT_SECS:%s*u64%s*=%s*(%d+)"))
    check("the bridge still declares an orphan timeout", secs ~= nil, tostring(secs))
    check("the mod's result deadline fires strictly before the transport's",
      secs ~= nil and Bridge.RESULT_DEADLINE_SECS < secs,
      Bridge.RESULT_DEADLINE_SECS .. " vs " .. tostring(secs))
  end
end

TmpWork.close()
done()
