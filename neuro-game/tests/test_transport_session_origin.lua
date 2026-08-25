_G.NEURO_TEST = true

if not love then love = {} end
love.timer = { getTime = function() return 1000 end }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("transport-session-origin")
local Bridge = require("core.bridge")
local Protocol = require("core.bridge_protocol")
local TmpWork = require("tests.tmp_workdir")

local dir_seq = 0
local function fresh_bridge()
  dir_seq = dir_seq + 1
  local dir = TmpWork.open("session_origin_" .. dir_seq)
  os.execute("rm -rf '" .. dir .. "'; mkdir -p '" .. dir .. "'")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  G.NEURO = b
  local seen = {}
  b:set_message_handler(function(msg) seen[#seen + 1] = msg end)
  return b, dir, seen
end

local function over_the_wire(line)
  local b, dir, seen = fresh_bridge()
  local f = assert(io.open(dir .. "/neuro_inbox.jsonl", "a"))
  f:write(line .. "\n")
  f:close()
  b:poll_inbox()
  return seen[1]
end

do
  check("the bridge-control prefix is the transport's own namespace",
    Protocol.CONTROL_PREFIX == "neuro-bridge/")
  check("is_transport_control accepts the transport's namespace",
    Protocol.is_transport_control("neuro-bridge/abandon") == true)
  check("is_transport_control rejects the spec namespace",
    Protocol.is_transport_control("actions/reregister_all") == false
      and Protocol.is_transport_control("action") == false)
  check("is_transport_control survives a non-string command",
    Protocol.is_transport_control(nil) == false and Protocol.is_transport_control(7) == false)
end

do
  local msg = over_the_wire('{"command":"actions/reregister_all","transport_session":424242}')
  check("a spec-namespace stamp reaches the dispatcher marked unattributable",
    msg ~= nil and msg.transport_session == 424242 and msg.transport_session_unattributed == true,
    msg and tostring(msg.transport_session_unattributed))
end

do
  local msg = over_the_wire('{"command":"neuro-bridge/abandon","transport_session":9,"data":{"ids":["a-1"]}}')
  check("a stamp in the transport's own namespace is not marked",
    msg ~= nil and msg.transport_session == 9 and msg.transport_session_unattributed == nil,
    msg and tostring(msg.transport_session_unattributed))
end

do
  local msg = over_the_wire(
    '{"command":"actions/reregister_all","transport_session":5,"transport_session_unattributed":false}')
  check("the wire cannot vouch for itself",
    msg ~= nil and msg.transport_session_unattributed == true,
    msg and tostring(msg.transport_session_unattributed))
  local listed = false
  for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
    if field == "transport_session_unattributed" then listed = true end
  end
  check("the attribution field is mod-local and never goes to the wire", listed)
  local wire = Protocol.sanitize_for_wire({
    command = "action/result", game = "Balatro", transport_session_unattributed = true,
    data = { id = "x", success = true },
  })
  check("sanitize_for_wire drops it outbound", wire.transport_session_unattributed == nil)
end

do
  local msg = over_the_wire('{"command":"actions/reregister_all"}')
  check("the bare frame PROPOSALS.md defines carries no attribution either way",
    msg ~= nil and msg.transport_session == nil and msg.transport_session_unattributed == nil)
end

do
  local msg = over_the_wire('{"command":"action","transport_session":11,"data":{"id":"a-1","name":"play_hand"}}')
  check("the mark is not special-cased to reregister_all",
    msg ~= nil and msg.transport_session_unattributed == true,
    msg and tostring(msg.transport_session_unattributed))
end

TmpWork.close()
done()
