_G.NEURO_TEST = true

local Config = require("core.config")
local Bridge = require("core.bridge")
local ForceState = require("core.force_state")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("force_supersede_wire")

Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("force_supersede_wire")
local FILES = {
  "neuro_inbox.jsonl",
  "neuro_outbox.jsonl",
  "neuro_session.txt",
  "neuro_action_journal.json",
}

os.execute("mkdir -p " .. IPC_DIR)
for _, name in ipairs(FILES) do os.remove(IPC_DIR .. "/" .. name) end

local function definition(name)
  return {
    name = name,
    description = name,
    schema = { type = "object" },
  }
end

local function definitions(names)
  local out = {}
  for _, name in ipairs(names) do out[#out + 1] = definition(name) end
  return out
end

local function as_set(names)
  local out = {}
  for _, name in ipairs(names) do out[name] = true end
  return out
end

local function read_frames(bridge)
  local file = io.open(IPC_DIR .. "/" .. bridge.outbox_file, "rb")
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

local old_names = { "select_blind", "sell_card", "record_plan" }
local new_names = { "sell_card", "reroll_shop", "leave_shop", "record_plan", "record_joker_roles" }
local shared = { sell_card = true, record_plan = true }

local bridge = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
G = { NEURO = bridge, TIMERS = { REAL = 100 } }
bridge.run_generation = 1
bridge.decision_serial = 10
bridge.state = "BLIND_SELECT"
bridge:send_startup()

local function reregister(names)
  local defs = definitions(names)
  if #defs > 0 then bridge:register_actions(defs) end
end

reregister(old_names)
check("first window arms", ForceState.arm("BLIND_SELECT", old_names, as_set(old_names), 1))
check("first window reaches the wire", ForceState.mark_sent(G.TIMERS.REAL))
bridge:force_actions("BLIND_SELECT", "Choose a blind", old_names)

bridge.state = "SHOP"
bridge.decision_serial = 11
ForceState.supersede(G.TIMERS.REAL)
check("old window ended", not ForceState._test.is_inflight())

reregister(new_names)
local during_quarantine = #read_frames(bridge)

G.TIMERS.REAL = G.TIMERS.REAL + ForceState.CANCEL_SETTLE
ForceState.cancel_pending(G.TIMERS.REAL)
reregister(new_names)
check("second window arms", ForceState.arm("SHOP", new_names, as_set(new_names), 2))
check("second window reaches the wire", ForceState.mark_sent(G.TIMERS.REAL))
bridge:force_actions("SHOP", "Choose a shop action", new_names)

local frames = read_frames(bridge)
local force_indexes = {}
for index, frame in ipairs(frames) do
  if frame.command == "actions/force" then force_indexes[#force_indexes + 1] = index end
end
check("exactly two force frames", #force_indexes == 2, #force_indexes)

local cancelled = {}
local first_force_names = {}
if #force_indexes == 2 then
  for _, name in ipairs(frames[force_indexes[1]].data.action_names or {}) do
    first_force_names[name] = true
  end
  for index = force_indexes[1] + 1, force_indexes[2] - 1 do
    local frame = frames[index]
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do cancelled[name] = true end
    end
  end
end

for _, name in ipairs(old_names) do
  local old_alias
  for wire_name in pairs(first_force_names) do
    if wire_name:match("^" .. name .. "_force_%d+$") then old_alias = wire_name end
  end
  check("old force cancelled before second: " .. name,
    old_alias ~= nil and cancelled[old_alias] == true, tostring(old_alias))
end

local function register_names(frame)
  local names = {}
  for _, action in ipairs(frame.data.actions or {}) do names[action.name] = true end
  return names
end

local unregister_index = nil
local reregistered_at = nil
if #force_indexes == 2 then
  for index = force_indexes[1] + 1, force_indexes[2] - 1 do
    local frame = frames[index]
    if frame.command == "actions/unregister" then
      local withdrawn = {}
      for _, name in ipairs(frame.data.action_names or {}) do withdrawn[name] = true end
      local hits_shared = false
      for name in pairs(shared) do
        for wire_name in pairs(withdrawn) do
          if wire_name:match("^" .. name .. "_force_%d+$") then hits_shared = true end
        end
      end
      if hits_shared and not unregister_index then unregister_index = index end
    elseif frame.command == "actions/register" then
      local names = register_names(frame)
      for name in pairs(shared) do
        for wire_name in pairs(names) do
          if wire_name:match("^" .. name .. "_force_%d+$") then
            reregistered_at = reregistered_at or index
          end
        end
      end
    end
  end
end
check("withdrawal frame precedes the shared names' re-registration",
  unregister_index ~= nil and reregistered_at ~= nil and unregister_index < reregistered_at,
  tostring(unregister_index) .. " < " .. tostring(reregistered_at))

local second_force_names = {}
if #force_indexes == 2 then
  for _, name in ipairs(frames[force_indexes[2]].data.action_names or {}) do
    second_force_names[name] = true
  end
end

local invalid = nil
for wire_name in pairs(second_force_names) do
  if not wire_name:match("^[a-z0-9]+[a-z0-9_-]*_force_%d+$")
      or wire_name:find("__", 1, true) then invalid = wire_name break end
end
check("second force offers valid SDK-shaped scoped identifiers",
  invalid == nil, tostring(invalid))

local shared_offered = true
for name in pairs(shared) do
  local found = false
  for wire_name in pairs(second_force_names) do
    if wire_name:match("^" .. name .. "_force_%d+$") then found = true end
  end
  if not found then shared_offered = false end
end
check("shared names are back on the client by the time the second force offers them",
  #force_indexes == 2 and shared_offered, tostring(shared_offered))

os.execute("rm -rf '" .. IPC_DIR .. "'")

TmpWork.close()
done()
