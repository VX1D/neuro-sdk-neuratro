
local Config = require("core.config")
local Bridge = require("core.bridge")
local ForceState = require("core.force_state")
local json = require("util.neuro_json")
local check, done = require("tests.helpers").harness("force_liveness_wire")

Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("force_liveness_wire")
  .. (tostring({}):match("0x(%x+)") or "0")
local FILES = {
  "neuro_inbox.jsonl",
  "neuro_outbox.jsonl",
  "neuro_session.txt",
  "neuro_action_journal.json",
}

os.execute("mkdir -p '" .. IPC_DIR .. "'")
for _, name in ipairs(FILES) do os.remove(IPC_DIR .. "/" .. name) end

local names = { "play_hand", "discard_hand" }
local defs = {
  { name = "play_hand", description = "Play selected cards", schema = { type = "object" } },
  { name = "discard_hand", description = "Discard selected cards", schema = { type = "object" } },
}

local function name_set(list)
  local set = {}
  for _, name in ipairs(list) do set[name] = true end
  return set
end

local function read_frames(dir, bridge)
  local file = io.open(dir .. "/" .. bridge.outbox_file, "rb")
  if not file then return {} end
  local raw = file:read("*a")
  file:close()
  local frames = {}
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" then frames[#frames + 1] = frame end
  end
  return frames
end

local function force_indexes(frames)
  local forces = {}
  for i, frame in ipairs(frames) do
    if frame.command == "actions/force" then forces[#forces + 1] = i end
  end
  return forces
end

local bridge = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
G = {
  TIMERS = { REAL = 100 },
  NEURO = bridge,
}
bridge.enabled = true
bridge.run_generation = 1
bridge.decision_serial = 1
bridge.state = "SELECTING_HAND"
bridge:send_startup()

bridge:set_desired_action_names(function()
  error("synthetic desired-set rebuild failure")
end)

bridge:register_actions(defs)
check("first force arms", ForceState.arm("SELECTING_HAND", names, name_set(names), G.TIMERS.REAL))
check("first force is marked sent", ForceState.mark_sent(G.TIMERS.REAL))
bridge:force_actions("SELECTING_HAND", "Choose play or discard", names)

bridge._registered_set = {}
bridge._registered_sigs = {}
G.TIMERS.REAL = G.TIMERS.REAL + ForceState.FORCE_LIVENESS_TIMEOUT
check("watchdog closes the unanswered force", ForceState.liveness_timeout(G.TIMERS.REAL))

check("watchdog leaves the withdrawal durable and settling",
  ForceState.cancel_pending(G.TIMERS.REAL) ~= nil
  and ForceState.cancel_pending(G.TIMERS.REAL).phase == "settling")

G.TIMERS.REAL = G.TIMERS.REAL + ForceState.CANCEL_SETTLE
check("written cancellation retires after its settle floor",
  ForceState.cancel_pending(G.TIMERS.REAL) == nil)
bridge:register_actions(defs)
bridge.decision_serial = 2
check("replacement force arms after cancellation settled",
  ForceState.arm("SELECTING_HAND", names, name_set(names), G.TIMERS.REAL))
check("replacement force is marked sent", ForceState.mark_sent(G.TIMERS.REAL))
check("replacement force reaches the wire after settling",
  bridge:force_actions("SELECTING_HAND", "Choose play or discard", names) ~= false)

local frames = read_frames(IPC_DIR, bridge)
local forces = force_indexes(frames)
check("wire contains exactly the original and replacement force", #forces == 2, #forces)

local withdrawn, restored = {}, {}
local replacement_names = {}
local original_names = {}
if #forces == 2 then
  for _, name in ipairs(frames[forces[1]].data.action_names or {}) do original_names[name] = true end
  for _, name in ipairs(frames[forces[2]].data.action_names or {}) do replacement_names[name] = true end
  for i = forces[1] + 1, forces[2] - 1 do
    local frame = frames[i]
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do withdrawn[name] = true end
    elseif frame.command == "actions/register" then
      for _, def in ipairs(frame.data.actions or {}) do restored[def.name] = true end
    end
  end
end

for _, name in ipairs(names) do
  local old_alias, new_alias = nil, nil
  for wire_name in pairs(original_names) do
    if wire_name:match("^" .. name .. "_force_%d+$") then old_alias = wire_name end
  end
  for wire_name in pairs(replacement_names) do
    if wire_name:match("^" .. name .. "_force_%d+$") then new_alias = wire_name end
  end
  check("expired force withdraws its scoped " .. name .. " identifier before replacement",
    old_alias ~= nil and withdrawn[old_alias] == true, tostring(old_alias))
  check("replacement registers a fresh scoped " .. name .. " identifier before asking",
    new_alias ~= nil and new_alias ~= old_alias and restored[new_alias] == true, tostring(new_alias))
end

do
  local invalid
  for wire_name in pairs(replacement_names) do
    if not wire_name:match("^[a-z0-9]+[a-z0-9_-]*_force_%d+$")
      or wire_name:find("__", 1, true) then invalid = wire_name break end
  end
  check("replacement identifiers follow the SDK lowercase underscore naming recommendation",
    invalid == nil, tostring(invalid))
end

do
  local handled = {}
  bridge:set_message_handler(function(msg)
    handled[#handled + 1] = msg.data.name
    bridge:send_action_result(msg.data.id, true, "handled current offer")
  end)
  local live_wire_name
  for wire_name in pairs(replacement_names) do
    if wire_name:match("^play_hand_force_%d+$") then live_wire_name = wire_name end
  end
  bridge:_deliver_inbox_message({ command = "action",
    data = { id = "current-force", name = live_wire_name, data = "{}" } })
  check("an answer carrying the current scoped name maps to the canonical game handler",
    handled[1] == "play_hand", tostring(handled[1]))
end

local BUFFERED_DIR = TmpWork.open("force_liveness_wire_buffered")
os.execute("mkdir -p '" .. BUFFERED_DIR .. "'")
for _, name in ipairs(FILES) do os.remove(BUFFERED_DIR .. "/" .. name) end

local buffered = Bridge:new({ enabled = true, fs_dir = BUFFERED_DIR })
G = { TIMERS = { REAL = 500 }, NEURO = buffered }
buffered.enabled = true
buffered.run_generation = 1
buffered.decision_serial = 20
buffered.state = "SELECTING_HAND"
buffered:send_startup()
buffered:set_desired_action_names(function()
  local desired = {}
  for _, def in ipairs(defs) do
    desired[def.name] = true
  end
  return desired
end)
buffered:register_actions(defs)
check("buffered fixture arms original", ForceState.arm(
  "SELECTING_HAND", names, name_set(names), G.TIMERS.REAL))
check("buffered fixture marks original sent", ForceState.mark_sent(G.TIMERS.REAL))
buffered:force_actions("SELECTING_HAND", "Choose play or discard", names)

local real_append = buffered.append_file
local append_blocked = true
function buffered:append_file(file, data)
  if append_blocked then return false, data end
  return real_append(self, file, data)
end

G.TIMERS.REAL = G.TIMERS.REAL + ForceState.FORCE_LIVENESS_TIMEOUT
check("buffered watchdog enters durable cancellation", not ForceState.liveness_timeout(G.TIMERS.REAL)
  and ForceState.window().phase == require("core.force_window").CANCELLING)
G.TIMERS.REAL = G.TIMERS.REAL + ForceState.CANCEL_SETTLE
buffered:register_actions(defs)
buffered.decision_serial = 21
local queued_arm = ForceState.arm("SELECTING_HAND", names, name_set(names), G.TIMERS.REAL)
if queued_arm then
  ForceState.mark_sent(G.TIMERS.REAL)
  buffered:force_actions("SELECTING_HAND", "Choose play or discard", names)
end

local before_flush = read_frames(BUFFERED_DIR, buffered)
check("replacement cannot reach disk while its cancellation is buffered",
  #force_indexes(before_flush) == 1, #force_indexes(before_flush))

append_blocked = false
buffered:_outbox_flush()
ForceState.cancel_pending(G.TIMERS.REAL)
G.TIMERS.REAL = G.TIMERS.REAL + ForceState.CANCEL_SETTLE
ForceState.cancel_pending(G.TIMERS.REAL)
if not queued_arm then
  buffered:register_actions(defs)
  check("replacement arms after cancellation flush", ForceState.arm(
    "SELECTING_HAND", names, name_set(names), G.TIMERS.REAL))
  check("replacement marks sent after cancellation flush", ForceState.mark_sent(G.TIMERS.REAL))
  check("replacement force reaches the wire after cancellation flush",
    buffered:force_actions("SELECTING_HAND", "Choose play or discard", names) ~= false)
end

local after_flush = read_frames(BUFFERED_DIR, buffered)
local flushed_forces = force_indexes(after_flush)
local unregister_between = false
if #flushed_forces == 2 then
  for i = flushed_forces[1] + 1, flushed_forces[2] - 1 do
    if after_flush[i].command == "actions/unregister" then
      unregister_between = true
      break
    end
  end
end
check("buffer flush preserves unregister before replacement force",
  #flushed_forces == 2 and unregister_between, #flushed_forces)

G = { TIMERS = { REAL = 900 }, NEURO = { enabled = true } }
G.NEURO.cancel_force_actions = function()
  return { status = "written", written_at = G.TIMERS.REAL }
end
G.NEURO.complete_force_cancellation = function() return false end
check("commit-rejection fixture arms", ForceState.arm(
  "SELECTING_HAND", names, name_set(names), G.TIMERS.REAL))
check("commit-rejection fixture marks sent", ForceState.mark_sent(G.TIMERS.REAL))
check("rejected cancellation bookkeeping blocks completion",
  ForceState.invalidate("liveness_timeout", G.TIMERS.REAL) == false)
check("rejected cancellation bookkeeping keeps the window cancelling",
  ForceState.window().phase == require("core.force_window").CANCELLING
    and G.NEURO.force_cancel_pending ~= nil)

for _, name in ipairs(FILES) do os.remove(BUFFERED_DIR .. "/" .. name) end
os.execute("rmdir '" .. BUFFERED_DIR .. "'")

for _, name in ipairs(FILES) do os.remove(IPC_DIR .. "/" .. name) end
os.execute("rmdir '" .. IPC_DIR .. "'")

TmpWork.close()
done()
