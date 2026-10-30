require("tests.stubs").setup({ love = "timers" })
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 }, STATES = require("tests.engine_cards").states() }

local check, done = require("tests.helpers").harness("catalogue-mirror")
local Protocol = require("core.bridge").wire
local Bridge = require("core.bridge")
local TmpWork = require("tests.tmp_workdir")

local dir = TmpWork.open("catalogue_mirror")
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")

local function frames() return require("tests.helpers").outbox_frames(dir .. "/neuro_outbox.jsonl") end

local function count(command)
  local n = 0
  for _, frame in ipairs(frames()) do
    if frame.command == command then n = n + 1 end
  end
  return n
end

local b = Bridge:new({ enabled = true, fs_dir = dir })
G.NEURO = b
b.run_generation = 1
b:send_startup()
b._bridge_init_complete = true
local Orch = require("core.orchestrator")
local registered = require("core.window").register_catalogue({ "play_hand" })
check("setup: the offer registers play_hand",
  registered == true and b._registered_sigs.play_hand ~= nil)

local withdrawal = b:withdraw_actions({ "play_hand" })
check("setup: the disposable unregister reached the wire",
  withdrawal == true and count("actions/unregister") == 1)
check("an unregister that reached the wire leaves play_hand off the local mirror",
  b._registered_sigs.play_hand == nil)
local registers_before = count("actions/register")
require("core.window").register_catalogue({ "play_hand" })
check("the rollback re-registers the withdrawn action instead of trusting a stale mirror",
  count("actions/register") == registers_before + 1 and b._registered_sigs.play_hand ~= nil)
local last = frames()[#frames()]
check("the re-registration carries play_hand",
  last.command == "actions/register" and last.data.actions[1] ~= nil
    and (function()
      for _, action in ipairs(last.data.actions) do
        if action.name == "play_hand" then return true end
      end
      return false
    end)())

local unregisters_before = count("actions/unregister")
local receipt = {}
check("a catalogue frame cannot bypass the mirror through send",
  b:send(Protocol.unregister({ "play_hand" }), receipt) == false
    and receipt.status == "rejected"
    and count("actions/unregister") == unregisters_before
    and b._registered_sigs.play_hand ~= nil)
receipt = {}
check("a register frame cannot bypass the mirror through send",
  b:send(Protocol.register({ { name = "ghost", description = "d" } }), receipt) == false
    and receipt.status == "rejected" and b._registered_sigs.ghost == nil)

os.execute("rm -rf '" .. dir .. "'")
TmpWork.close()
done()
