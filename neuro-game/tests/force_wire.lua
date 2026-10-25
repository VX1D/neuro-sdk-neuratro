local M = {}


local Bridge = require("core.bridge")
local Registry = require("core.action_registry")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")
local FP = require("tests.force_payload")

local dir, bridge, delivered, refused = nil, nil, 0, {}

local function outbox_path() return dir .. "/" .. bridge.outbox_file end

local function last_force_frame()
  local fh = io.open(outbox_path(), "rb")
  if not fh then return nil, {} end
  local raw = fh:read("*a"); fh:close()
  local found, parse_errors = nil, {}
  local line_no = 0
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    line_no = line_no + 1
    if line:match("%S") then
      local ok, frame = pcall(json.decode, line)
      if not ok then
        parse_errors[#parse_errors + 1] =
          string.format("line %d: %s", line_no, tostring(frame))
      elseif type(frame) == "table" and frame.command == "actions/force" then
        found = frame
      end
    end
  end
  return found, parse_errors
end

local function parse_error_detail(parse_errors)
  return "malformed JSONL in outbox: " .. table.concat(parse_errors, " | ")
end

local function unalias_fn()
  return function(text) return tostring(text or "") end
end

local function deliver(state, query, names)
  bridge:reset_delivery_memory()
  local ok = bridge:force_actions(state, query, names)
  if not ok then
    refused[#refused + 1] = tostring(state):sub(1, 40)
    return nil
  end
  local frame, parse_errors = last_force_frame()
  if #parse_errors > 0 then
    refused[#refused + 1] = parse_error_detail(parse_errors)
    return nil
  end
  if type(frame) ~= "table" or type(frame.data) ~= "table" then
    refused[#refused + 1] = "no actions/force frame reached the outbox"
    return nil
  end
  delivered = delivered + 1
  return {
    state = tostring(frame.data.state or ""),
    query = tostring(frame.data.query or ""),
    action_names = frame.data.action_names or {},
    unalias = unalias_fn(),
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
