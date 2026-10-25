_G.NEURO_TEST = true

G = { TIMERS = { REAL = 100, TOTAL = 50 } }
love = { timer = { getTime = function() return G.TIMERS.REAL end } }

local Bridge = require("core.bridge")
local TmpWork = require("tests.tmp_workdir")
local check, done = require("tests.helpers").harness("game_heartbeat")

local IPC_DIR = TmpWork.open("game_heartbeat")

local function read(name)
  local f = io.open(IPC_DIR .. "/" .. name, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function relay_source()
  local f = assert(io.open("../neuro-bridge-rs/src/liveness.rs", "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local bridge = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
local outbox_before = read(bridge.outbox_file)

bridge:update(0.016)
check("the first update beats", read(bridge.heartbeat_file) == "1\n", read(bridge.heartbeat_file))
G.TIMERS.REAL = G.TIMERS.REAL + 0.5
bridge:update(0.016)
check("no rewrite within the interval", read(bridge.heartbeat_file) == "1\n", read(bridge.heartbeat_file))

local Orchestrator = require("core.orchestrator")
G.SETTINGS = { paused = true }
G.STATE = nil
G.NEURO = bridge
G.TIMERS.REAL = G.TIMERS.REAL + Bridge.HEARTBEAT_INTERVAL_SECS
local frame_ok, frame_err = pcall(Orchestrator.update, 0.016, nil)
check("the love.update frame runs", frame_ok, frame_err)
check("a paused game in a menu still beats", read(bridge.heartbeat_file) == "2\n", read(bridge.heartbeat_file))

local last = read(bridge.heartbeat_file)
for _ = 1, 5 do
  G.TIMERS.REAL = G.TIMERS.REAL + Bridge.HEARTBEAT_INTERVAL_SECS
  bridge:update(0.016)
  check("every interval changes the file", read(bridge.heartbeat_file) ~= last, read(bridge.heartbeat_file))
  last = read(bridge.heartbeat_file)
end

G.TIMERS.REAL = G.TIMERS.REAL - 30
bridge:update(0.016)
check("a clock that went backwards does not silence the beat", read(bridge.heartbeat_file) ~= last,
  read(bridge.heartbeat_file))

check("beating never touches the outbox", read(bridge.outbox_file) == outbox_before,
  tostring(read(bridge.outbox_file)))

os.remove(IPC_DIR .. "/" .. bridge.heartbeat_file)
local disabled = Bridge:new({ enabled = false, fs_dir = IPC_DIR })
G.TIMERS.REAL = G.TIMERS.REAL + 10
disabled:update(0.016)
check("a disabled bridge does not beat", read(disabled.heartbeat_file) == nil)

local rust = relay_source()
check("the relay watches the file the mod writes",
  rust:find('GAME_HEARTBEAT_FILE: &str = "' .. bridge.heartbeat_file .. '"', 1, true) ~= nil)
local stale = tonumber(rust:match("GAME_STALE_AFTER: Duration = Duration::from_secs%((%d+)%)"))
check("the relay waits many beats before calling the game dead",
  stale ~= nil and stale >= 10 * Bridge.HEARTBEAT_INTERVAL_SECS, tostring(stale))

TmpWork.close()
done()
