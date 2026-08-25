local M = {}
local safe_tostring = require("util.utils").safe_tostring

M.SCOPES = {
  run = true,
}

local fields = {}
local hooks = {}

local function assert_scope(scope)
  assert(M.SCOPES[scope], "unknown lifecycle scope: " .. tostring(scope))
end

function M.register_field(scope, key)
  assert_scope(scope)
  assert(type(key) == "string" and key ~= "", "lifecycle field key required")
  fields[scope] = fields[scope] or {}
  assert(fields[scope][key] == nil, "lifecycle field already registered: " .. scope .. ":" .. key)
  fields[scope][key] = true
end

function M.register_fields(scope, keys)
  for _, key in ipairs(keys or {}) do M.register_field(scope, key) end
end

function M.register_hook(scope, name, reset, priority)
  assert_scope(scope)
  assert(type(name) == "string" and name ~= "", "lifecycle hook name required")
  assert(type(reset) == "function", "lifecycle hook reset must be a function")
  hooks[scope] = hooks[scope] or {}
  assert(hooks[scope][name] == nil, "lifecycle hook already registered: " .. scope .. ":" .. name)
  hooks[scope][name] = { fn = reset, priority = tonumber(priority) or 100 }
end

local function reset_scope(scope, owner, context)
  for key in pairs(fields[scope] or {}) do owner[key] = nil end
  local entries = {}
  for name, entry in pairs(hooks[scope] or {}) do
    entries[#entries + 1] = { name = name, priority = entry.priority }
  end
  table.sort(entries, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.name < b.name
  end)
  local errors = {}
  for _, entry in ipairs(entries) do
    local ok, err = pcall(hooks[scope][entry.name].fn, context or {})
    if not ok then
      errors[#errors + 1] = entry.name .. ": " .. safe_tostring(err)
    end
  end
  if #errors > 0 then
    print("[neuro-game] lifecycle reset hook errors (" .. tostring(scope) .. "): "
      .. table.concat(errors, "; "))
  end
  return errors
end

function M.reset(scope, owner, context)
  assert_scope(scope)
  owner = owner or {}
  local errors = reset_scope(scope, owner, context)
  return owner, errors
end

function M.describe()
  local out = {}
  for scope in pairs(M.SCOPES) do
    local field_names, hook_names = {}, {}
    for key in pairs(fields[scope] or {}) do field_names[#field_names + 1] = key end
    for name in pairs(hooks[scope] or {}) do hook_names[#hook_names + 1] = name end
    table.sort(field_names)
    table.sort(hook_names)
    out[scope] = { fields = field_names, hooks = hook_names }
  end
  return out
end

function M.validate()
  local seen = {}
  local errors = {}
  for scope, entry in pairs(M.describe()) do
    for _, key in ipairs(entry.fields) do
      if seen[key] then
        errors[#errors + 1] = key .. ": registered in both " .. seen[key] .. " and " .. scope
      else
        seen[key] = scope
      end
    end
  end
  return #errors == 0, errors
end

return M
