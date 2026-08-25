
G = { NEURO = { run_generation = 3 } }

local Config = require("core.config")
local Protocol = require("core.bridge_protocol")
local Bridge = require("core.bridge")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("wire_envelope")

Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
Config.set("NEURO_INBOX_TRUNCATE_ON_STARTUP", "off")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("wire_envelope")
  .. (tostring({}):match("0x(%x+)") or "0")

local function fresh_bridge()
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  return Bridge:new({ enabled = true, fs_dir = IPC_DIR })
end

local function outbox_lines(bridge)
  local f = io.open(IPC_DIR .. "/" .. bridge.outbox_file, "rb")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  local out = {}
  for line in raw:gmatch("[^\n]+") do out[#out + 1] = line end
  return out
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function set_of(list)
  local set = {}
  for _, v in ipairs(list) do set[v] = true end
  return set
end

local ENVELOPE = set_of(Protocol.WIRE_FIELDS)

local b = fresh_bridge()
b:send_startup()
b:send_context("hello", true)
b:register_actions({ { name = "play_hand", description = "play", schema = { type = "object" } } })
b:force_actions("SELECTING_HAND", "your move", { "play_hand" }, { priority = "high", ephemeral_context = true })
b:send_action_result("id-1", false, "no", "STALE_GENERATION")
b:unregister_actions({ "play_hand" })

local lines = outbox_lines(b)
check("every C2S command reached the outbox", #lines == 7, #lines)

local seen_commands = {}
for i, line in ipairs(lines) do
  local ok, frame = pcall(json.decode, line)
  check("outbox line " .. i .. " decodes", ok and type(frame) == "table")
  if ok and type(frame) == "table" then
    seen_commands[#seen_commands + 1] = tostring(frame.command)
    local extra = {}
    for _, key in ipairs(sorted_keys(frame)) do
      if not ENVELOPE[key] then extra[#extra + 1] = key end
    end
    check("outbox line " .. i .. " (" .. tostring(frame.command) .. ") carries only command/game/data",
      #extra == 0, table.concat(extra, ","))
    check("outbox line " .. i .. " names the game (SPECIFICATION.md:30)",
      frame.game == "Balatro", tostring(frame.game))

    local allowed = Protocol.DATA_FIELDS[frame.command]
    if allowed and type(frame.data) == "table" then
      local data_extra = {}
      for _, key in ipairs(sorted_keys(frame.data)) do
        if not set_of(allowed)[key] then data_extra[#data_extra + 1] = key end
      end
      check("outbox line " .. i .. " data holds only " .. tostring(frame.command) .. " spec fields",
        #data_extra == 0, table.concat(data_extra, ","))
    end
  end
end

check("the frames include the scoped force registration in SDK send order",
  table.concat(seen_commands, ",") == "startup,context,actions/register,actions/register,actions/force,action/result,actions/unregister",
  table.concat(seen_commands, ","))

do
  local force = json.decode(lines[5])
  check("the force frame keeps every field the SDK reads (SPECIFICATION.md:131-160)",
    force.data.state == "SELECTING_HAND" and force.data.query == "your move"
      and force.data.priority == "high" and force.data.ephemeral_context == true
      and force.data.action_names[1]:match("^play_hand_force_%d+$"), lines[5])
  local result = json.decode(lines[6])
  check("the result frame keeps id/success/message (SPECIFICATION.md:161-189)",
    result.data.id == "id-1" and result.data.success == false and result.data.message == "no",
    lines[6])
  local register = json.decode(lines[3])
  check("the register frame keeps the action definitions",
    register.data.actions[1].name == "play_hand"
      and register.data.actions[1].description == "play", lines[3])
end

local raw = table.concat(lines, "\n")
for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
  check("no outbox line mentions " .. field .. " at all",
    raw:find('"' .. field .. '"', 1, true) == nil)
end

check("the send counter still advances for the local metric", b.seq == 7, b.seq)
check("the session id is still held for the journal and the marker file",
  type(b.session_id) == "number")

do
  local dirty = fresh_bridge()
  dirty:send_startup()
  dirty:send({ command = "context", seq = 9, session_id = "s-9", run_generation = 4,
    reason_code = "ACTION_REJECTED", data = { message = "m", silent = false, note = "leak" } })
  local written = outbox_lines(dirty)[2]
  local frame = written and json.decode(written)
  check("send strips a hand-built frame down to the envelope",
    frame ~= nil and frame.seq == nil and frame.session_id == nil and frame.run_generation == nil
      and frame.reason_code == nil, tostring(written))
  check("send strips data down to the command's spec fields",
    frame and frame.data and frame.data.note == nil and frame.data.message == "m"
      and frame.data.silent == false, tostring(written))
end

do
  -- Same action frame, two transports: the one the Rust bridge writes today (stamped from our own
  -- outbox) and the one a plain jsonl->websocket relay writes (SPECIFICATION.md:214-227, verbatim).
  local function delivered(line)
    local bridge = fresh_bridge()
    local got
    bridge:set_message_handler(function(msg) got = msg end)
    bridge:send_startup()
    local f = io.open(IPC_DIR .. "/" .. bridge.inbox_file, "ab")
    f:write(line .. "\n")
    f:close()
    bridge:poll_inbox()
    return got
  end

  local stamped = delivered('{"command":"action","run_generation":1,"session_id":"s-9","seq":4,'
    .. '"data":{"id":"a-1","name":"play_hand","data":"{}"}}')
  local plain = delivered('{"command":"action","data":{"id":"a-1","name":"play_hand","data":"{}"}}')

  check("a stamped inbound frame reaches the handler", stamped ~= nil)
  check("a spec-exact inbound frame reaches the handler", plain ~= nil)
  for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
    check("the stamped frame loses " .. field .. " before anything downstream sees it",
      stamped and stamped[field] == nil, stamped and tostring(stamped[field]))
  end
  check("both transports hand the dispatcher the same envelope",
    stamped and plain and #sorted_keys(stamped) == #sorted_keys(plain)
      and table.concat(sorted_keys(stamped), ",") == table.concat(sorted_keys(plain), ","),
    stamped and table.concat(sorted_keys(stamped), ","))
  check("the payload itself is untouched",
    stamped and stamped.data and stamped.data.id == "a-1" and stamped.data.name == "play_hand"
      and stamped.data.data == "{}")

  local reconnect = delivered('{"command":"actions/reregister_all","transport_session":2}')
  check("a transport-origin field is not mistaken for a loop and survives",
    reconnect and reconnect.transport_session == 2, reconnect and tostring(reconnect.transport_session))
end

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
