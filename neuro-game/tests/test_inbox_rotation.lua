love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, TIMERS = { REAL = 0 } }

local Bridge = require("core.bridge")
local check, done = require("tests.helpers").harness("inbox-rotation")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("ibx")
local inbox = dir .. "/neuro_inbox.jsonl"

local function write(path, text, mode)
  local f = io.open(path, mode or "ab")
  f:write(text)
  f:close()
end

local function tagged(tag)
  return '{"command":"context","data":{"tag":"' .. tag .. '"}}\n'
end

local function fresh()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  G.NEURO = b
  local tags = {}
  b:set_message_handler(function(msg) tags[#tags + 1] = msg.data and msg.data.tag or msg.command end)
  return b, tags
end

do
  local b, tags = fresh()
  write(inbox, tagged("a"))
  b:poll_inbox()
  write(inbox, tagged("b"))
  b:poll_inbox()
  b:poll_inbox()
  check("a growing file is read once, line by line", table.concat(tags, ",") == "a,b",
    table.concat(tags, ","))
  write(inbox, tagged("c"), "wb")
  b:poll_inbox()
  check("a file that no longer continues the cursor is read from zero",
    table.concat(tags, ",") == "a,b,c", table.concat(tags, ","))
end

do
  local b, tags = fresh()
  write(inbox, tagged("same1"))
  b:poll_inbox()
  write(inbox, tagged("same2"), "wb")
  b:poll_inbox()
  check("a rotation to a file of the same byte size is still a rotation",
    table.concat(tags, ",") == "same1,same2", table.concat(tags, ","))
end

do
  local b, tags = fresh()
  write(inbox, tagged("old1"))
  b:poll_inbox()
  write(inbox, tagged("old2"))
  os.rename(inbox, inbox .. ".1")
  write(inbox, tagged("new1"))
  b:poll_inbox()
  check("a record appended just before the rename is delivered before the new file",
    table.concat(tags, ",") == "old1,old2,new1", table.concat(tags, ","))
  write(inbox, tagged("new2"))
  b:poll_inbox()
  check("after the drain the new file is followed like any other",
    table.concat(tags, ",") == "old1,old2,new1,new2", table.concat(tags, ","))
end

do
  local b, tags = fresh()
  write(inbox, tagged("r1"))
  b:poll_inbox()
  write(inbox, tagged("r2") .. tagged("r3"))
  os.rename(inbox, inbox .. ".1")
  write(inbox, tagged("n1"))
  b:set_message_handler(function(msg)
    tags[#tags + 1] = msg.data.tag
    if msg.data.tag == "r2" then b._fifo[#b._fifo + 1] = "held\n" end
  end)
  b._append = function() return 0 end
  b:poll_inbox()
  check("a pending outbox stops the drain mid-file", table.concat(tags, ",") == "r1,r2",
    table.concat(tags, ","))
  b._append = nil
  b:flush_outbox()
  b:poll_inbox()
  check("the drain resumes from its cursor and then follows the new file",
    table.concat(tags, ",") == "r1,r2,r3,n1", table.concat(tags, ","))
end

do
  local b, tags = fresh()
  write(inbox, tagged("mine"))
  b:poll_inbox()
  write(inbox .. ".1", tagged("stranger") .. tagged("stranger2"), "wb")
  write(inbox, tagged("fresh"), "wb")
  b:poll_inbox()
  check("a rotated file that does not continue our cursor is never replayed",
    table.concat(tags, ",") == "mine,fresh", table.concat(tags, ","))
end

do
  local b, tags = fresh()
  write(inbox, tagged("stale") .. '{"command":"neuro-bridge/reregister_all","transport_session":7}\n'
    .. '{"command":"context","data":{"tag":"half')
  b:send_startup()
  b:poll_inbox()
  check("startup skips what the relay wrote before the game started", #tags == 0,
    table.concat(tags, ","))
  check("while keeping the session it last named", b.transport_session == "7",
    tostring(b.transport_session))
  write(inbox, '"}}\n' .. tagged("after"))
  b:poll_inbox()
  check("an unterminated record resumes when the relay finishes it",
    table.concat(tags, ",") == "half,after", table.concat(tags, ","))
end

TmpWork.close()
done()
