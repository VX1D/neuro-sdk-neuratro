local json = require("util.neuro_json")
local ForceAudit = require("tools.force_wire_audit")

local M = {}

local function read_frames(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, { { kind = "cannot_open", detail = tostring(err) } } end
  local frames, violations, line = {}, {}, 0
  for raw in f:lines() do
    line = line + 1
    if raw:match("%S") then
      local ok, frame = pcall(json.decode, raw)
      if ok and type(frame) == "table" then
        frames[#frames + 1] = frame
      else
        violations[#violations + 1] = { kind = "malformed_jsonl", line = line }
      end
    end
  end
  f:close()
  return frames, violations
end

local function id_key(id)
  return type(id) .. "\0" .. tostring(id)
end

local function terminal_message(message)
  local s = type(message) == "string" and message:lower() or ""
  return s:find("not executed", 1, true) or s:find("nothing happened", 1, true)
    or s:find("expired force", 1, true) or s:find("was withdrawn", 1, true)
    or s:find("shutting down", 1, true) or s:find("stopped responding", 1, true)
end

local WIRE_FIELDS = { command = true, game = true, data = true }
local C2S_COMMANDS = {
  ["startup"] = true,
  ["context"] = true,
  ["actions/register"] = true,
  ["actions/unregister"] = true,
  ["actions/force"] = true,
  ["action/result"] = true,
}
local DATA_FIELDS = {
  ["context"] = { message = true, silent = true },
  ["actions/register"] = { actions = true },
  ["actions/unregister"] = { action_names = true },
  ["actions/force"] = { state = true, query = true, ephemeral_context = true,
    priority = true, action_names = true },
  ["action/result"] = { id = true, success = true, message = true },
}
local ACTION_NAME_PATTERN = "^[a-z0-9]+[a-z0-9_-]*$"

local function scan_frame_conformance(line, frame, violations)
  if type(frame.command) ~= "string" or not C2S_COMMANDS[frame.command] then
    violations[#violations + 1] = { kind = "unknown_command", line = line,
      detail = tostring(frame.command) }
    return
  end

  for field in pairs(frame) do
    if not WIRE_FIELDS[field] then
      violations[#violations + 1] = { kind = "undeclared_wire_field", line = line, detail = field }
    end
  end

  local allowed = DATA_FIELDS[frame.command]
  if allowed then
    if frame.data ~= nil and type(frame.data) ~= "table" then
      violations[#violations + 1] = { kind = "data_not_object", line = line }
    elseif type(frame.data) == "table" then
      for field in pairs(frame.data) do
        if not allowed[field] then
          violations[#violations + 1] = { kind = "undeclared_data_field", line = line,
            detail = field }
        end
      end
    end
  elseif frame.data ~= nil then
    violations[#violations + 1] = { kind = "unexpected_startup_data", line = line }
  end

  local names = {}
  if frame.command == "actions/register" and type(frame.data) == "table" then
    for _, action in ipairs(frame.data.actions or {}) do
      names[#names + 1] = type(action) == "table" and action.name or nil
    end
  elseif frame.command == "actions/force" and type(frame.data) == "table" then
    names = frame.data.action_names or {}
  end
  for _, name in ipairs(names) do
    if type(name) ~= "string" or not name:match(ACTION_NAME_PATTERN)
        or name:find("__", 1, true) then
      violations[#violations + 1] = { kind = "invalid_action_name", line = line,
        detail = tostring(name) }
    end
  end
end

function M.scan(inbox_path, outbox_path)
  local inbound, violations = read_frames(inbox_path)
  if not inbound then return violations end
  local outbound, out_errors = read_frames(outbox_path)
  for _, v in ipairs(out_errors or {}) do violations[#violations + 1] = v end
  if not outbound then return violations end

  local actions, results, terminal_acks = {}, {}, {}
  for line, frame in ipairs(outbound) do
    scan_frame_conformance(line, frame, violations)
  end
  for line, frame in ipairs(inbound) do
    if frame.command == "action" and type(frame.data) == "table" and frame.data.id ~= nil then
      local key = id_key(frame.data.id)
      actions[key] = actions[key] or {
        id = frame.data.id, name = frame.data.name, count = 0, line = line,
      }
      actions[key].count = actions[key].count + 1
    end
  end
  for line, frame in ipairs(outbound) do
    if frame.command == "action/result" and type(frame.data) == "table" and frame.data.id ~= nil then
      local key = id_key(frame.data.id)
      results[key] = results[key] or { id = frame.data.id, count = 0, line = line }
      results[key].count = results[key].count + 1
      if frame.data.success == false and terminal_message(frame.data.message) then
        violations[#violations + 1] = {
          kind = "terminal_result_requests_retry", line = line, id = frame.data.id,
        }
      elseif frame.data.success == true and terminal_message(frame.data.message) then
        violations[#violations + 1] = {
          kind = "ack_without_execution", line = line, id = frame.data.id,
        }
        local action = actions[key]
        local signature = tostring(action and action.name or "?") .. "\0"
          .. tostring(frame.data.message or ""):lower()
        local entry = terminal_acks[signature] or { count = 0, line = line, id = frame.data.id }
        entry.count = entry.count + 1
        entry.line = line
        terminal_acks[signature] = entry
      end
    end
  end
  for key, action in pairs(actions) do
    local count = results[key] and results[key].count or 0
    if count == 0 then
      violations[#violations + 1] = { kind = "missing_result", line = action.line, id = action.id }
    elseif count > 1 then
      violations[#violations + 1] = { kind = "duplicate_result", line = results[key].line, id = action.id }
    end
  end
  for key, result in pairs(results) do
    if not actions[key] then
      violations[#violations + 1] = { kind = "result_without_action", line = result.line, id = result.id }
    end
  end
  for _, entry in pairs(terminal_acks) do
    if entry.count >= 3 then
      violations[#violations + 1] = {
        kind = "semantic_livelock", line = entry.line, id = entry.id, detail = entry.count,
      }
    end
  end
  if outbound[1] and outbound[1].command ~= "startup" then
    violations[#violations + 1] = { kind = "startup_not_first", line = 1 }
  end
  for _, v in ipairs(ForceAudit.scan_frames(outbound, outbox_path, actions)) do
    violations[#violations + 1] = v
  end
  table.sort(violations, function(a, b)
    if (a.line or 0) == (b.line or 0) then return tostring(a.kind) < tostring(b.kind) end
    return (a.line or 0) < (b.line or 0)
  end)
  return violations
end

return M
