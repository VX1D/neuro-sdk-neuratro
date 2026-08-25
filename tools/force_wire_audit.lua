local json = require("util.neuro_json")

local M = {}

local function id_key(id)
  return type(id) .. "\0" .. tostring(id)
end

local function names(data)
  local out = {}
  for _, name in ipairs((type(data) == "table" and data.action_names) or {}) do
    if type(name) == "string" then out[name] = true end
  end
  return out
end

local function list(set)
  local out = {}
  for name in pairs(set or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function identifier_occurs(text, name)
  if type(text) ~= "string" or type(name) ~= "string" or name == "" then return false end
  local escaped = name:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  return (" " .. text .. " "):find("[^%w_]" .. escaped .. "[^%w_]") ~= nil
end

function M.scan_frames(frames, source, known_actions)
  local active, registered, registry_known = nil, {}, false
  local definitions, catalog = {}, {}
  local actions = {}
  for key, action in pairs(known_actions or {}) do actions[key] = action end
  local violations = {}
  for line, frame in ipairs(frames or {}) do
    local command = type(frame) == "table" and frame.command or nil
    local data = type(frame) == "table" and frame.data or nil
    if command == "startup" then
      active, registered, registry_known = nil, {}, false
      definitions, catalog = {}, {}
    elseif command == "actions/register" then
      registry_known = true
      for _, def in ipairs((type(data) == "table" and data.actions) or {}) do
        if type(def) == "table" and type(def.name) == "string" then
          registered[def.name] = true
          definitions[def.name] = def
          catalog[def.name] = true
        end
      end
    elseif command == "actions/unregister" then
      local removed = names(data)
      for name in pairs(removed) do registered[name] = nil end
      if active then
        for name in pairs(removed) do active.remaining[name] = nil end
        if next(active.remaining) == nil then active = nil end
      end
    elseif command == "action" then
      if type(data) == "table" and data.id ~= nil and type(data.name) == "string" then
        actions[id_key(data.id)] = { id = data.id, name = data.name, line = line }
      end
    elseif command == "action/result" then
      -- SPECIFICATION.md:165-167 ties a result to the exact inbound action id. A successful result
      -- for an unrelated/non-force action does not close the outstanding force.
      local action = type(data) == "table" and actions[id_key(data.id)] or nil
      if active and type(data) == "table" and data.success == true
          and action and active.remaining[action.name] then
        active = nil
      end
    elseif command == "actions/force" then
      local offered = names(data)
      if active then
        violations[#violations + 1] = {
          source = source, line = line, previous_line = active.line,
          kind = "overlapping_force", names = list(offered),
        }
      end
      if registry_known then
        local missing = {}
        for name in pairs(offered) do if not registered[name] then missing[name] = true end end
        if next(missing) then
          violations[#violations + 1] = {
            source = source, line = line, kind = "forced_action_not_registered",
            names = list(missing),
          }
        end
      end
      local texts = {
        query = type(data) == "table" and data.query or nil,
        state = type(data) == "table" and data.state or nil,
      }
      for name in pairs(offered) do
        local def = definitions[name]
        if def then texts["description:" .. name] = def.description end
      end
      for field, value in pairs(texts) do
        local foreign = {}
        for name in pairs(catalog) do
          if not offered[name] and identifier_occurs(value, name) then foreign[name] = true end
        end
        if next(foreign) then
          violations[#violations + 1] = {
            source = source, line = line, kind = "force_text_nonoffered_action",
            field = field, names = list(foreign),
          }
        end
      end
      active = { line = line, remaining = offered }
    end
  end
  return violations
end

function M.scan_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local frames, malformed = {}, {}
  local line_no = 0
  for raw in f:lines() do
    line_no = line_no + 1
    if raw:match("%S") then
      local ok, frame = pcall(json.decode, raw)
      if ok and type(frame) == "table" then
        frames[#frames + 1] = frame
      else
        malformed[#malformed + 1] = line_no
      end
    end
  end
  f:close()
  local violations = M.scan_frames(frames, path)
  return violations, malformed
end

return M
