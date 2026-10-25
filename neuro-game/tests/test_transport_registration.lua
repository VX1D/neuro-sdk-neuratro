_G.NEURO_TEST = true

local json = require("util.neuro_json")
local Bridge = require("core.bridge")
local TxCache = require("core.bridge").tx
local TmpWork = require("tests.tmp_workdir")
local check, done = require("tests.helpers").harness("transport-registration")

local dir = TmpWork.open("transport_registration")

local function fresh_bridge()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  TxCache.reset()
  local bridge = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  bridge:send_startup()
  return bridge
end

local function frames(bridge, command)
  return require("tests.helpers").outbox_frames(dir .. "/" .. bridge.outbox_file, { command = command })
end

local function definition(name, description, schema)
  return { name = name, description = description, schema = schema or { type = "object" } }
end

do
  local Registry = require("core.action_registry")
  Registry.register(definition("duplicate", "old"))
  Registry.register(definition("other", "other"))
  Registry.register(definition("duplicate", "latest"))
  local actions = {}
  for _, action in ipairs(Registry.definitions()) do
    if action.name == "duplicate" or action.name == "other" then actions[#actions + 1] = action end
  end
  check("duplicate registration batch emits one definition per name",
    #actions == 2, #actions)
  local latest_by_name, occurrences = {}, {}
  for _, action in ipairs(actions) do
    local name = action.name
    if name then
      occurrences[name] = (occurrences[name] or 0) + 1
      latest_by_name[name] = action.description
    end
  end
  check("duplicate registration batch keeps the latest definition",
    occurrences.duplicate == 1 and latest_by_name.duplicate == "latest"
      and occurrences.other == 1 and latest_by_name.other == "other",
    "duplicate=" .. tostring(latest_by_name.duplicate)
      .. " x" .. tostring(occurrences.duplicate or 0)
      .. ", other=" .. tostring(latest_by_name.other)
      .. " x" .. tostring(occurrences.other or 0))
end

do
  local bridge = fresh_bridge()
  local first = {
    type = "object",
    properties = {
      choice = { type = "string", enum = { "a" } },
      values = { type = "array", items = { type = "string" } },
    },
    required = { "choice" },
  }
  bridge:register_actions({ definition("schema_change", "schema", first) })
  local before = #frames(bridge, "actions/register")

  local second = {
    type = "object",
    properties = {
      choice = { type = "string", enum = { "b" } },
      values = { type = "array", items = { type = "number" } },
    },
    required = { "values" },
  }
  bridge:register_actions({ definition("schema_change", "schema", second) })
  local registers = frames(bridge, "actions/register")
  local wire = registers[#registers].data.actions[1].schema
  check("enum, required, and items mutation emits a replacement",
    #registers == before + 1, #registers)
  check("replacement carries the changed enum and required array",
    wire.properties.choice.enum[1] == "b" and wire.required[1] == "values",
    json.encode(wire))
  check("replacement carries the changed items schema",
    wire.properties.values.items.type == "number", json.encode(wire))
end

do
  local bridge = fresh_bridge()
  TxCache.open("oversized-result", "play_hand", 0)
  local accepted = bridge:send_action_result(
    "oversized-result", true, string.rep("x", Bridge.MAX_OUTBOUND_LINE_BYTES))
  check("oversized result is accepted", accepted == true, tostring(accepted))
  local results = frames(bridge, "action/result")
  local result = results[1]
  check("oversized result reaches outbox as one bounded terminal verdict",
    #results == 1 and result and result.data and type(result.data.message) == "string"
      and #result.data.message < 1024,
    tostring(#results) .. "/" .. tostring(result and result.data and result.data.message
      and #result.data.message))
  check("oversized result obligation is cleared",
    #TxCache.outstanding(0) == 0 and not require("tests.helpers").is_owed("oversized-result"),
    #TxCache.outstanding(0))
end

do
  local bridge = fresh_bridge()
  local receipt = { status = "sending" }
  local sent = bridge:send_context(nil, false, receipt)
  check("malformed generic public frame is rejected before append",
    sent == false and receipt.status == "rejected"
      and #frames(bridge) == 1, tostring(receipt.status))

  local private_receipt = { status = "sending" }
  local private_sent = bridge:send({ command = "neuro-bridge/test" }, private_receipt)
  check("no private control leaves the mod except the startup tag the relay still reads",
    bridge.send_private == nil and private_sent == false and private_receipt.status == "rejected")
end

TmpWork.close()
done()
