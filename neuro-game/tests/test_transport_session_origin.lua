_G.NEURO_TEST = true

if not love then love = {} end
love.timer = { getTime = function() return 1000 end }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("transport-session-origin")
local Bridge = require("core.bridge")
local Protocol = require("core.bridge").wire
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
  local msg = over_the_wire(
    '{"command":"neuro-bridge/reregister_all","transport_session":424242}')
  check("the vendor-prefixed reconnect control reaches the handler",
    msg ~= nil and msg.command == "neuro-bridge/reregister_all"
      and msg.transport_session == 424242,
    msg and tostring(msg.command) .. "/" .. tostring(msg.transport_session))
end

do
  local msg = over_the_wire(
    '{"command":"neuro-bridge/abandon","transport_session":9,"data":{"ids":["a-1"]}}')
  check("the vendor-prefixed abandon control keeps its transport stamp",
    msg ~= nil and msg.command == "neuro-bridge/abandon"
      and msg.transport_session == 9,
    msg and tostring(msg.command) .. "/" .. tostring(msg.transport_session))
end

do
  local msg = over_the_wire(
    '{"command":"action","transport_session":11,"data":{"id":"a-1","name":"play_hand"}}')
  check("public action frames do not retain transport bookkeeping",
    msg ~= nil and msg.command == "action" and msg.transport_session == nil,
    msg and tostring(msg.transport_session))
end

do
  local msg = over_the_wire(
    '{"command":"actions/reregister_all","transport_session":5}')
  check("proposed public reconnect control has no private transport semantics",
    msg ~= nil and msg.command == "actions/reregister_all"
      and msg.transport_session == nil,
    msg and tostring(msg.command) .. "/" .. tostring(msg.transport_session))
end

do
  local wire = Protocol.result("x", true)
  check("transport bookkeeping never reaches the SDK wire",
    wire.transport_session == nil, tostring(wire.transport_session))
check("results carry only the public command and data",
  wire.command == "action/result" and wire.data.id == "x" and wire.data.success == true)
local registration = Protocol.register({
  { name = "play_hand", description = "Play the selected hand." },
})
check("registration constructors emit the canonical public command",
  registration.command == "actions/register"
    and registration.data.actions[1].name == "play_hand")
local startup = Protocol.startup("Balatro")
check("startup constructors contain only the game identity",
  startup.command == "startup" and startup.game == "Balatro" and startup.data == nil)
end

TmpWork.close()
done()
