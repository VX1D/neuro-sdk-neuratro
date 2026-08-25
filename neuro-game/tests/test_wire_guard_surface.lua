G = {}

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
local Bridge = require("core.bridge")
local Protocol = require("core.bridge_protocol")
local Metrics = require("util.metrics")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("wire_guard_surface")
local TmpWork = require("tests.tmp_workdir")

local seq = 0
local function fresh_bridge()
  seq = seq + 1
  local dir = TmpWork.open("wire_guard_" .. seq)
    .. "_" .. (tostring({}):match("0x(%x+)") or "0")
  os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
  local b = Bridge:new({ enabled = true, fs_dir = dir })
  G.NEURO = b
  b:send_startup()
  return b, dir
end

local function frames(b, dir)
  local f = io.open(dir .. "/" .. b.outbox_file, "rb")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  local out = {}
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    out[#out + 1] = (ok and type(frame) == "table") and frame or { command = "UNPARSEABLE" }
  end
  return out
end

local function count(b, dir, command)
  local n = 0
  for _, frame in ipairs(frames(b, dir)) do
    if frame.command == command then n = n + 1 end
  end
  return n
end

local function metric(name)
  return Metrics._counters[name] or 0
end

for _, case in ipairs({
  { label = "no description", def = { name = "cash_out", schema = { type = "object" } } },
  { label = "non-string description", def = { name = "cash_out", description = 7,
    schema = { type = "object" } } },
  { label = "schema that is not an object", def = { name = "cash_out", description = "cash",
    schema = { type = "array", items = {} } } },
  { label = "schema that is not a table", def = { name = "cash_out", description = "cash",
    schema = "object" } },
}) do
  local b, dir = fresh_bridge()
  b:register_actions({ case.def })
  local registers = count(b, dir, "actions/register")
  local before = metric("force_send_unwireable_definition")
  local ok = b:force_actions("ROUND_EVAL", "Choose", { "cash_out" })
  check("A/" .. case.label .. ": the force is refused",
    ok == false, tostring(ok))
  check("A/" .. case.label .. ": no actions/force frame reached the wire",
    count(b, dir, "actions/force") == 0, count(b, dir, "actions/force"))
  check("A/" .. case.label .. ": no force-alias registration was written either",
    count(b, dir, "actions/register") == registers, count(b, dir, "actions/register"))
  check("A/" .. case.label .. ": the refusal is counted",
    metric("force_send_unwireable_definition") == before + 1)
  check("A/" .. case.label .. ": the force window stayed closed", b._force_open == nil)
  os.execute("rm -rf " .. dir)
end

-- A2: the same shapes the SDK does permit still force. SPECIFICATION.md:55 -- an omitted schema and
-- an empty schema are both legal, so the guard must not read them as malformed.
for _, case in ipairs({
  { label = "omitted schema", def = { name = "cash_out", description = "cash" } },
  { label = "empty schema", def = { name = "cash_out", description = "cash", schema = {} } },
  { label = "object schema", def = { name = "cash_out", description = "cash",
    schema = { type = "object", properties = {} } } },
  -- Every key here is on the "probably not supported" list (SPECIFICATION.md:58); the wire copy
  -- strips them, so what Neuro receives is the legal empty schema.
  { label = "schema of stripped keywords only", def = { name = "cash_out", description = "cash",
    schema = { title = "x", description = "y" } } },
}) do
  local b, dir = fresh_bridge()
  b:register_actions({ case.def })
  local ok = b:force_actions("ROUND_EVAL", "Choose", { "cash_out" })
  check("A2/" .. case.label .. ": a legal definition still forces", ok == true, tostring(ok))
  check("A2/" .. case.label .. ": its force frame is on the wire",
    count(b, dir, "actions/force") == 1, count(b, dir, "actions/force"))
  os.execute("rm -rf " .. dir)
end

do
  local b, dir = fresh_bridge()
  b:register_actions({
    { name = "play_hand", description = "play", schema = { type = "object" } },
    { name = "cash_out", description = "cash", schema = { type = "object" } },
  })
  check("no window is open before the first force", b._force_open == nil)
  check("the first force is accepted",
    b:force_actions("S1", "Q1", { "play_hand" }) == true)
  check("send() opened the window when it admitted the frame", b._force_open == true)

  local before = metric("ipc_force_overlap_rejected")
  local dup_before = metric("ipc_duplicate_frame")
  local receipt = { status = "sending" }
  local accepted = b:send(Protocol.force("S2", "Q2", { "cash_out_force_9" }), receipt)
  check("a second, byte-different force is rejected at the transport boundary",
    accepted == false and receipt.status == "rejected", tostring(receipt.status))
  check("it never became a frame",
    count(b, dir, "actions/force") == 1, count(b, dir, "actions/force"))
  check("the overlap is counted as an overlap, not as a duplicate",
    metric("ipc_force_overlap_rejected") == before + 1
      and metric("ipc_duplicate_frame") == dup_before,
    metric("ipc_force_overlap_rejected") .. "/" .. metric("ipc_duplicate_frame"))
  os.execute("rm -rf " .. dir)
end

do
  local b, dir = fresh_bridge()
  b:register_actions({
    { name = "play_hand", description = "play", schema = { type = "object" } },
  })
  b:force_actions("S1", "Q1", { "play_hand" })
  local alias
  for _, frame in ipairs(frames(b, dir)) do
    if frame.command == "actions/force" then alias = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg) b:send_action_result(msg.data.id, true, "done") end)
  b:_deliver_inbox_message({ command = "action", data = { id = "w-1", name = alias, data = "{}" } })
  check("an answered force closes the window", b._force_open == nil)
  check("and the successor force is admitted",
    b:force_actions("S2", "Q2", { "play_hand" }) == true)
  check("both force frames are on the wire",
    count(b, dir, "actions/force") == 2, count(b, dir, "actions/force"))
  os.execute("rm -rf " .. dir)
end

do
  local b, dir = fresh_bridge()
  local first = { status = "sending" }
  check("a force written straight at the transport is admitted",
    b:send(Protocol.force("S1", "Q1", { "play_hand_force_1" }), first) == true
      and first.status == "written", tostring(first.status))
  check("the frame itself opened the window", b._force_open == true)
  local second = { status = "sending" }
  check("so its byte-different successor is refused by the same boundary",
    b:send(Protocol.force("S2", "Q2", { "cash_out_force_2" }), second) == false
      and second.status == "rejected", tostring(second.status))
  check("and only the first force is on the wire",
    count(b, dir, "actions/force") == 1, count(b, dir, "actions/force"))
  os.execute("rm -rf " .. dir)
end

do
  local b, dir = fresh_bridge()
  b:register_actions({
    { name = "play_hand", description = "play", schema = { type = "object" } },
  })
  b.enabled = false
  local receipt = { status = "sending" }
  check("a disabled bridge writes no force",
    b:send(Protocol.force("S", "Q", { "play_hand" }), receipt) == false
      and receipt.status == "rejected")
  check("and opens no window", b._force_open == nil)
  os.execute("rm -rf " .. dir)
end

do
  local TxCache = require("core.tx_cache")
  local b, dir = fresh_bridge()
  TxCache.reset()
  TxCache.open("owed-1", "play_hand", 0)
  check("the action is owed before the sweep",
    #TxCache.outstanding(0) == 1, #TxCache.outstanding(0))
  check("the sweep reports one payment",
    b:answer_owed_results(nil, "swept") == 1)
  check("nothing is owed afterwards",
    #TxCache.outstanding(0) == 0, #TxCache.outstanding(0))
  local settled = TxCache.get("owed-1")
  check("the verdict was committed by send_action_result itself",
    settled ~= nil and settled.ok == true and settled.message == "swept",
    settled and tostring(settled.message))
  check("and the id can never be answered a second time", TxCache.claim("owed-1") == false)
  check("exactly one action/result frame reached the wire",
    count(b, dir, "action/result") == 1, count(b, dir, "action/result"))
  TxCache.reset()
  os.execute("rm -rf " .. dir)
end

TmpWork.close()
done()
