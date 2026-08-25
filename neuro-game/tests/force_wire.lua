local M = {}

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")

local Bridge = require("core.bridge")
local Registry = require("core.action_registry")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")
local FP = require("tests.force_payload")

local dir, bridge, delivered, refused = nil, nil, 0, {}

local function outbox_path() return dir .. "/" .. bridge.outbox_file end

local function last_force_frame()
  local fh = io.open(outbox_path(), "rb")
  if not fh then return nil end
  local raw = fh:read("*a"); fh:close()
  local found
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" and frame.command == "actions/force" then found = frame end
  end
  return found
end

local function unalias_fn(active)
  local pairs_list = {}
  for canonical, alias in pairs(active or {}) do
    pairs_list[#pairs_list + 1] = { alias = alias, canonical = canonical }
  end
  table.sort(pairs_list, function(a, b) return #a.alias > #b.alias end)
  return function(text)
    text = tostring(text or "")
    for _, p in ipairs(pairs_list) do
      text = text:gsub((p.alias:gsub("([^%w])", "%%%1")), p.canonical)
    end
    return text
  end
end

local function deliver(state, query, names)
  bridge:retire_force_aliases()
  local ok = bridge:force_actions(state, query, names)
  if not ok then
    refused[#refused + 1] = tostring(state):sub(1, 40)
    return nil
  end
  local frame = last_force_frame()
  if type(frame) ~= "table" or type(frame.data) ~= "table" then
    refused[#refused + 1] = "no actions/force frame reached the outbox"
    return nil
  end
  delivered = delivered + 1
  return {
    state = tostring(frame.data.state or ""),
    query = tostring(frame.data.query or ""),
    action_names = frame.data.action_names or {},
    unalias = unalias_fn(bridge._active_force_wire_by_canonical),
  }
end

function M.attach()
  if bridge then return end
  require("core.actions")
  dir = TmpWork.open("force_wire")
  bridge = Bridge:new({ enabled = true, fs_dir = dir })
  bridge:send_startup()
  bridge:register_actions(Registry.definitions())
  FP.set_sink(deliver)
end

function M.delivered() return delivered end
function M.refusals() return refused end

function M.close() TmpWork.close() end

return M
