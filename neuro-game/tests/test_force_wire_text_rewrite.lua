G = {}

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
local Bridge = require("core.bridge")
local json = require("util.neuro_json")

local check, done = require("tests.helpers").harness("force_wire_text_rewrite")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("force_wire_text")
  .. (tostring({}):match("0x(%x+)") or "0")
os.execute("rm -rf " .. IPC_DIR .. " && mkdir -p " .. IPC_DIR)

local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
b:send_startup()

b:register_actions({
  { name = "play_hand", schema = { type = "object" },
    description = "Play your highlighted cards. Use play_hand before cash_out." },
  { name = "cash_out", schema = { type = "object" },
    description = "Ends the round early. Consider play_hand first, then cash_out when ready. "
      .. "If you already used cash_out, don't call cash_out again this turn." },
})

local state = "Hand contains 5 cards. play_hand is available. play_hand was used last turn too."
local query = "Decide between play_hand and cash_out. If in doubt, call cash_out."

local ok, receipt = b:force_actions(state, query, { "play_hand", "cash_out" })
check("fixture: force accepted", ok == true, tostring(receipt and receipt.status))

local active = b._active_force_wire_by_canonical
check("fixture: both canonical names got aliases", type(active) == "table"
  and type(active.play_hand) == "string" and type(active.cash_out) == "string",
  json.encode(active))

local function canonical_survives(text, canonical)
  if type(text) ~= "string" then return false end
  return text:find("%f[%w_]" .. canonical .. "%f[^%w_]") ~= nil
end

local function alias_present(text, alias)
  if type(text) ~= "string" then return false end
  return text:find(alias, 1, true) ~= nil
end

local f = assert(io.open(IPC_DIR .. "/" .. b.outbox_file, "rb"))
local raw = f:read("*a")
f:close()

local register_frame, force_frame
for line in raw:gmatch("[^\n]+") do
  local dok, frame = pcall(json.decode, line)
  if dok and type(frame) == "table" then
    if frame.command == "actions/register" then register_frame = frame end
    if frame.command == "actions/force" then force_frame = frame end
  end
end

check("fixture: an alias register frame was sent", type(register_frame) == "table")
check("fixture: a force frame was sent", type(force_frame) == "table")

local alias_descriptions = {}
if register_frame then
  for _, a in ipairs(register_frame.data.actions or {}) do
    alias_descriptions[a.name] = a.description
  end
end

for canonical, alias in pairs(active) do
  local desc = alias_descriptions[alias]
  check("forced definition " .. tostring(alias) .. " has a description on the wire",
    type(desc) == "string", tostring(desc))
  check("canonical name '" .. canonical .. "' does not survive in " .. tostring(alias)
    .. "'s description", not canonical_survives(desc, canonical), tostring(desc))
end

check("canonical 'play_hand' does not survive in the force state",
  not canonical_survives(force_frame and force_frame.data.state, "play_hand"),
  tostring(force_frame and force_frame.data.state))
check("canonical 'cash_out' does not survive in the force state",
  not canonical_survives(force_frame and force_frame.data.state, "cash_out"),
  tostring(force_frame and force_frame.data.state))
check("canonical 'play_hand' does not survive in the force query",
  not canonical_survives(force_frame and force_frame.data.query, "play_hand"),
  tostring(force_frame and force_frame.data.query))
check("canonical 'cash_out' does not survive in the force query",
  not canonical_survives(force_frame and force_frame.data.query, "cash_out"),
  tostring(force_frame and force_frame.data.query))

local wire_names = {}
for _, n in ipairs(force_frame and force_frame.data.action_names or {}) do wire_names[n] = true end
for canonical, alias in pairs(active) do
  check("wire action_names contains the alias for " .. canonical, wire_names[alias] == true,
    json.encode(force_frame and force_frame.data.action_names))
  check("the alias for " .. canonical .. " actually appears where the canonical name used to be "
    .. "(state or query)",
    alias_present(force_frame and force_frame.data.state, alias)
      or alias_present(force_frame and force_frame.data.query, alias),
    alias)
end

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
