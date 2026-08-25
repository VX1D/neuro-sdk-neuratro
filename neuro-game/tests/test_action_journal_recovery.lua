_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = nil, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 },
  STATES = { MENU = 11 }, STATE = 11 }

local check, done = require("tests.helpers").harness("action-journal-recovery")
local json = require("util.neuro_json")

local TmpWork = require("tests.tmp_workdir")
local IPC = TmpWork.open("journal_recovery")
local Paths = require("core.mod_paths")
Paths.read_ipc_dir = function() return IPC end
Paths.write_ipc_marker = function() end
local BridgeInit = require("core.bridge_init")

local function boot_with_journal(raw)
  os.execute("rm -rf " .. IPC .. " && mkdir -p " .. IPC)
  if raw then
    local f = io.open(IPC .. "/neuro_action_journal.json", "wb")
    f:write(raw)
    f:close()
  end
  G.NEURO = nil
  BridgeInit.run({})
  local frames = {}
  local fh = io.open(IPC .. "/neuro_outbox.jsonl", "rb")
  if fh then
    local data = fh:read("*a")
    fh:close()
    for line in data:gmatch("[^\n]+") do
      local ok, msg = pcall(json.decode, line)
      if ok and type(msg) == "table" then frames[#frames + 1] = msg end
    end
  end
  return frames
end

local function index_of(frames, command)
  for i, m in ipairs(frames) do
    if m.command == command then return i, m end
  end
end

local function survives_wire_sanitizer(frame)
  local d = frame and frame.data
  return type(frame.game) == "string" and frame.game ~= ""
    and type(d) == "table"
    and type(d.id) == "string" and d.id ~= ""
    and type(d.success) == "boolean"
    and (d.message == nil or type(d.message) == "string")
end

do
  local frames = boot_with_journal(
    '{"id":"7db23060c43041c4a9aebc1619464e3c","name":"play_hand","phase":"prepared","run_generation":2}')
  local startup_i = index_of(frames, "startup")
  local result_i, result = index_of(frames, "action/result")
  local context_i = index_of(frames, "context")

  check("an interrupted action answered before the restart is not left without a result",
    result ~= nil, "frames=" .. #frames)
  check("the result carries the interrupted action's id",
    result and result.data and result.data.id == "7db23060c43041c4a9aebc1619464e3c",
    result and result.data and tostring(result.data.id))
  check("the result is success=true so no force is retried into a run that no longer exists",
    result and result.data and result.data.success == true,
    result and result.data and tostring(result.data.success))
  check("the result explains that the action never ran",
    result and result.data and type(result.data.message) == "string"
      and result.data.message:find("not executed", 1, true) ~= nil,
    result and result.data and tostring(result.data.message))
  check("the result survives the bridge wire sanitizer",
    result ~= nil and survives_wire_sanitizer(result))
  check("startup stays the first frame of the session",
    startup_i == 1, tostring(startup_i))
  check("the result follows startup and precedes the recovery context",
    startup_i and result_i and context_i and startup_i < result_i and result_i < context_i,
    tostring(startup_i) .. "/" .. tostring(result_i) .. "/" .. tostring(context_i))
  check("the recovery still re-arms the force", G.NEURO.force_dirty == true)
  check("the recovered entry is still published to the mod",
    type(G.NEURO.recovered_action_journal) == "table"
      and G.NEURO.recovered_action_journal.name == "play_hand")
end

do
  local frames = boot_with_journal(
    '{"id":"aaa","name":"play_hand","phase":"acknowledged","run_generation":2}')
  check("an action already acknowledged before the crash is not answered twice",
    index_of(frames, "action/result") == nil)
  check("an already acknowledged action still gets the recovery context",
    index_of(frames, "context") ~= nil)
end

do
  local frames = boot_with_journal(
    '{"id":"bbb","name":"play_hand","phase":"executing","run_generation":2}')
  check("an action whose result was already sent while executing is not answered twice",
    index_of(frames, "action/result") == nil)
end

do
  local frames = boot_with_journal(
    '{"id":"verify","name":"buy_from_shop","phase":"verifying","run_generation":2}')
  local _, context = index_of(frames, "context")
  check("a verifying action is never answered twice", index_of(frames, "action/result") == nil)
  check("verifying recovery reports unknown outcome rather than non-execution",
    context and context.data and context.data.message:find("outcome is unknown", 1, true) ~= nil,
    context and context.data and context.data.message)
end

do
  local frames = boot_with_journal(
    '{"id":"ccc","name":"cash_out","phase":"completed","run_generation":2}')
  check("a completed action produces no recovery traffic at all",
    index_of(frames, "action/result") == nil and index_of(frames, "context") == nil)
end

do
  local frames = boot_with_journal(nil)
  check("a clean shutdown produces no recovery traffic",
    index_of(frames, "action/result") == nil and index_of(frames, "context") == nil)
end

do
  G.NEURO = nil
  local sent = {}
  local bridge = {
    send_action_result = function(_, id, ok, message) sent[#sent + 1] = { id, ok, message } end,
    send_context = function() end,
  }
  BridgeInit._recover_interrupted_action(bridge, { name = "play_hand", phase = "prepared" })
  check("an entry with no id sends nothing: the bridge would drop that frame anyway",
    #sent == 0, tostring(#sent))
  BridgeInit._recover_interrupted_action(bridge, { id = 4021, name = "play_hand", phase = "prepared" })
  check("a non-string id is normalized to a string for the wire",
    #sent == 1 and sent[1][1] == "4021", tostring(sent[1] and sent[1][1]))
end

os.execute("rm -rf " .. IPC)

TmpWork.close()
done()
