G = {}

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
local Bridge = require("core.bridge")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("force_overlap_guard")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("force_overlap")
  .. (tostring({}):match("0x(%x+)") or "0")
os.execute("rm -rf " .. IPC_DIR .. " && mkdir -p " .. IPC_DIR)

local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
b:send_startup()
b:register_actions({
  { name = "play_hand", description = "play", schema = { type = "object" } },
  { name = "cash_out", description = "cash", schema = { type = "object" } },
})

local function force_frame_count()
  local f = io.open(IPC_DIR .. "/" .. b.outbox_file, "rb")
  if not f then return 0 end
  local raw = f:read("*a")
  f:close()
  local n = 0
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" and frame.command == "actions/force" then n = n + 1 end
  end
  return n
end

local ok1, receipt1 = b:force_actions("S1", "Q1", { "play_hand" })
check("first force is accepted", ok1 == true, tostring(receipt1 and receipt1.status))
check("fixture: the bridge now holds an open force", b._force_open == true)
check("exactly one force frame is on the wire so far", force_frame_count() == 1, force_frame_count())

-- The first force is still unanswered; SPECIFICATION.md forbids a second in-flight force.
local ok2 = b:force_actions("S2", "Q2", { "cash_out" })
check("a second, overlapping force is rejected", ok2 == false, tostring(ok2))
check("the overlapping call put no second actions/force frame on the wire",
  force_frame_count() == 1, force_frame_count())
check("the SDK is still holding only the first offer",
  b._active_force_wire_by_canonical ~= nil
    and b._active_force_wire_by_canonical.play_hand ~= nil
    and b._active_force_wire_by_canonical.cash_out == nil)

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
