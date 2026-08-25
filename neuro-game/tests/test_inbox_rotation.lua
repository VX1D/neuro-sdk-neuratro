local clock = 0
love = { timer = { getTime = function() return clock end } }
_G.G = { NEURO = {}, TIMERS = { REAL = 0 } }

local Bridge = require("core.bridge")
local check, done = require("tests.helpers").harness("inbox-rotation")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("ibx")

local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
local seen = {}
b:set_message_handler(function(msg) seen[#seen + 1] = msg.command end)

local function append(line)
  local f = io.open(dir .. "/neuro_inbox.jsonl", "a")
  f:write(line .. "\n"); f:close()
end

append('{"command":"actions/reregister_all"}')
b:poll_inbox()
local after_first = #seen
check("first line handled once", after_first == 1, after_first)

append('{"command":"action","data":{"id":"x1","name":"help","data":"{}"}}')
b:poll_inbox()
check("a prefix growing past 64B is not treated as a rotation (reregister_all handled only once)",
  seen[1] == "actions/reregister_all" and #seen == 2, table.concat(seen, ","))

local f = io.open(dir .. "/neuro_inbox.jsonl", "w")
f:write('{"command":"context","data":{"message":"new file","silent":true}}\n'); f:close()
b:poll_inbox()
check("a real rotation (diverging prefix) is detected and the file is read from zero",
  seen[#seen] == "context", table.concat(seen, ","))

local function fresh_bridge()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  local nb = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  local tags = {}
  nb:set_message_handler(function(msg) tags[#tags + 1] = msg.data and msg.data.tag end)
  return nb, tags
end

local function overwrite(text)
  local fh = io.open(dir .. "/neuro_inbox.jsonl", "wb")
  fh:write(text); fh:close()
end

local function tagged(tag, pad)
  return '{"command":"context","data":{"tag":"' .. tag .. '","pad":"' .. string.rep("x", pad or 0) .. '"}}\n'
end

do
  local nb, tags = fresh_bridge()
  overwrite(tagged("AAAA"))
  nb:poll_inbox()
  local before = #tags
  overwrite(tagged("BBBB"))
  check("a rotation to a file of the same byte size is still a rotation",
    before == 1 and (function() nb:poll_inbox() return tags[2] == "BBBB" end)(),
    table.concat(tags, ","))
end

do
  local nb, tags = fresh_bridge()
  overwrite(tagged("OLD1") .. tagged("OLD2", 40) .. tagged("OLD3", 40))
  nb:poll_inbox()
  local before = #tags
  overwrite(tagged("OLD1") .. tagged("NEW1"))
  nb:poll_inbox()
  local saw_new = false
  for _, t in ipairs(tags) do if t == "NEW1" then saw_new = true end end
  check("a truncation that keeps the leading bytes does not swallow what replaced them",
    before == 3 and saw_new, table.concat(tags, ","))
end

do
  local nb, tags = fresh_bridge()
  nb._transport_saturated = true
  overwrite(tagged("ANS1") .. tagged("ANS2"))
  nb:poll_inbox()
  check("a saturated outbox leaves inbound obligations unread",
    #tags == 0, table.concat(tags, ","))
  overwrite(tagged("ANS1") .. tagged("ANS2") .. tagged("ANS3"))
  clock = clock + 1
  nb:update(1)
  check("update does not accept more obligations while saturation remains",
    #tags == 0, table.concat(tags, ","))
  check("not reading the inbox does not clear the send-side backpressure",
    nb:is_transport_saturated() == true)
  nb._transport_saturated = nil
  nb:poll_inbox()
  check("polling resumes from the unread prefix after transport recovery",
    #tags == 3 and tags[3] == "ANS3", table.concat(tags, ","))
end

TmpWork.close()
done()
