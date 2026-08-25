_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, TIMERS = { REAL = 1000 } }

local Bridge = require("core.bridge")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local check, done = require("tests.helpers").harness("result-delivery-obligation")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("result_delivery")

local function fresh()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  CLOCK.t = 1000
  TxCache.reset()
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b:set_message_handler(function() end)
  b:send_startup()
  return b
end

local function result_frames()
  local out = {}
  local f = io.open(dir .. "/neuro_outbox.jsonl", "r")
  if not f then return out end
  for line in f:lines() do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" and frame.command == "action/result" then out[#out + 1] = frame end
  end
  f:close()
  return out
end

local function owed() return #TxCache.outstanding(CLOCK.t, nil) end

do
  local b = fresh()
  TxCache.open("buf-1", "play_hand", CLOCK.t)
  local real_append = b.append_file
  b.append_file = function() return false, nil end
  local accepted, receipt = b:send_action_result("buf-1", true, "played")
  check("a buffered result is still accepted by the protected FIFO",
    accepted == true and receipt and receipt.status == "buffered",
    receipt and tostring(receipt.status))
  check("a buffered result does not discharge the obligation", owed() == 1, owed())
  check("and nothing is on the wire yet", #result_frames() == 0, #result_frames())

  b.append_file = real_append
  b:_outbox_flush()
  check("the flush is what discharges it", owed() == 0, owed())
  check("exactly one result frame reaches the wire",
    #result_frames() == 1 and result_frames()[1].data.id == "buf-1", #result_frames())
end

do
  local b = fresh()
  TxCache.open("lost-1", "cash_out", CLOCK.t)
  local real_append = b.append_file
  b.append_file = function() return false, nil end
  local _, lost_receipt = b:send_action_result("lost-1", true, "cashed out for 12")
  b._outbox_backlog = nil
  lost_receipt.status = "rejected"
  b.append_file = real_append
  check("a discarded backlog leaves the result owed", owed() == 1, owed())

  local paid = b:answer_owed_results(nil, "swept")
  local frames = result_frames()
  check("the sweep pays it exactly once", paid == 1 and #frames == 1, paid .. "/" .. #frames)
  check("the sweep re-emits the committed verdict, not a new one",
    frames[1] and frames[1].data.message == "cashed out for 12",
    frames[1] and tostring(frames[1].data.message))
  check("and the obligation is then discharged", owed() == 0, owed())
  check("a second sweep does not send a duplicate",
    b:answer_owed_results(nil, "swept") == 0 and #result_frames() == 1, #result_frames())
end

do
  local b = fresh()
  TxCache.open("reemit-1", "cash_out", CLOCK.t)
  b.append_file = function() return false, nil end
  local _, lost = b:send_action_result("reemit-1", true, "cashed out for 12")
  b._outbox_backlog = nil
  lost.status = "rejected" -- what core/bridge.lua discard_frame does to a frame it drops
  check("the sweep re-emits the lost verdict exactly once",
    b:answer_owed_results(nil, "swept") == 1 and #(b._outbox_backlog or {}) == 1,
    #(b._outbox_backlog or {}))
  for _ = 1, 10 do b:answer_owed_results(nil, "swept") end
  check("and further sweeps wait on that frame instead of copying it too",
    #(b._outbox_backlog or {}) == 1, #(b._outbox_backlog or {}))
  b.append_file = nil
  b:_outbox_flush()
  local frames = result_frames()
  check("one action, one result on the wire, and it is the committed verdict",
    #frames == 1 and frames[1].data.message == "cashed out for 12",
    #frames .. "/" .. tostring(frames[1] and frames[1].data.message))
  check("the flush discharges it", owed() == 0, owed())
end

do
  local b = fresh()
  TxCache.open("queued-1", "play_hand", CLOCK.t)
  local real_append = b.append_file
  b.append_file = function() return false, nil end
  b:send_action_result("queued-1", true, "played")
  check("the queued verdict is booked as undelivered",
    owed() == 1 and TxCache.undelivered_verdict("queued-1") ~= nil, owed())

  for _ = 1, 10 do
    CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS + 1
    b:update(0)
  end
  check("ten sweeps past the deadline queue no copy of the frame already on its way",
    #(b._outbox_backlog or {}) == 1, #(b._outbox_backlog or {}))
  check("the sweep reports nothing paid, because nothing was",
    b:answer_owed_results(nil, "swept") == 0)
  check("the obligation stays live -- delivery, not commit, discharges it", owed() == 1, owed())

  b.append_file = real_append
  b:_outbox_flush()
  local frames = result_frames()
  check("the recovered flush puts exactly one result on the wire",
    #frames == 1 and frames[1].data.message == "played", #frames)
  check("and that delivery is what discharges the obligation", owed() == 0, owed())
end

do
  local b = fresh()
  TxCache.open("flood-1", "play_hand", CLOCK.t)
  b.append_file = function() return false, nil end
  b:send_action_result("flood-1", true, "played")
  for _ = 1, 2200 do
    CLOCK.t = CLOCK.t + 1 / 60
    b:update(1 / 60)
  end
  check("2200 sweep frames leave the backlog at the one committed frame",
    #(b._outbox_backlog or {}) == 1, #(b._outbox_backlog or {}))
  check("so the protected outbox never saturates and the inbox keeps being read",
    b:is_transport_saturated() == false and b:_outbox_can_accept_protected(2) == true)
  TxCache.open("flood-2", "cash_out", CLOCK.t)
  local accepted, receipt = b:send_action_result("flood-2", true, "cashed")
  check("and the next action is still answerable",
    accepted == true and receipt and receipt.status == "buffered",
    tostring(receipt and receipt.status))
end

do
  local b = fresh()
  TxCache.open("refused-1", "play_hand", CLOCK.t)
  b.append_file = function() return false, nil end
  local _, lost = b:send_action_result("refused-1", true, "played")
  b._outbox_backlog = nil
  lost.status = "rejected" -- what core/bridge.lua discard_frame does to a frame it drops
  local full = {}
  for i = 1, Bridge.OUTBOX_BACKLOG_HARD do full[i] = { line = "x\n", tier = 2 } end
  b._outbox_backlog = full

  local attempts, real_send = 0, b.send
  b.send = function(self, msg, receipt)
    if msg and msg.command == "action/result" then attempts = attempts + 1 end
    return real_send(self, msg, receipt)
  end
  for _ = 1, 600 do -- ten seconds at 60 fps
    CLOCK.t = CLOCK.t + 1 / 60
    b:update(1 / 60)
  end
  b.send = real_send
  check("ten seconds of refusals cost two re-emission attempts, not six hundred",
    attempts >= 1 and attempts <= 3, attempts)
  check("and the obligation is still owed, because nothing was ever delivered",
    owed() == 1 and #(b._outbox_backlog or {}) == Bridge.OUTBOX_BACKLOG_HARD, owed())
end

do
  local b = fresh()
  TxCache.open("ok-1", "play_hand", CLOCK.t)
  local _, receipt = b:send_action_result("ok-1", true, "played")
  check("a written result is delivered immediately and owes nothing",
    receipt and receipt.status == "written" and owed() == 0 and #result_frames() == 1,
    tostring(receipt and receipt.status) .. "/" .. owed() .. "/" .. #result_frames())
end

TmpWork.close()
done()
