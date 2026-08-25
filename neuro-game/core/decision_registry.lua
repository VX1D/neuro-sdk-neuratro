local M = {}

local definitions = {}
local order = {}

M.SCOPE_KINDS = {
  setup_visit = true,
  economy_epoch = true,
  shop_revision = true,
  shop_visit = true,
  joker_roster = true,
  blind = true,
  boss = true,
  pack_opening = true,
}

function M.register(definition)
  assert(type(definition) == "table", "decision window definition must be a table")
  assert(type(definition.id) == "string" and definition.id ~= "", "decision window id is required")
  assert(definition.policy == "soft" or definition.policy == "hard", "decision window policy must be soft or hard")
  assert(type(definition.reject_prose) == "string" or type(definition.reject_prose) == "function", "decision window reject_prose is required")
  assert(type(definition.acknowledged_by) == "table", "decision window acknowledged_by is required")
  assert(type(definition.blocks) == "table", "decision window blocks is required")
  assert(type(definition.scope) == "table", "decision window scope is required")
  assert(M.SCOPE_KINDS[definition.scope.kind], "unknown decision window scope kind: " .. tostring(definition.scope.kind))
  assert(type(definition.scope.key) == "function", "decision window scope key is required")
  assert(not definitions[definition.id], "duplicate decision window id: " .. definition.id)
  definitions[definition.id] = definition
  order[#order + 1] = definition
  return definition
end

function M.get(id) return definitions[id] end
function M.ordered() return order end
function M.scope_key(definition)
  local value = definition.scope.key()
  if value == nil or value == "" then return "<unavailable:" .. definition.scope.kind .. ">" end
  return tostring(value)
end

function M.validate()
  local errors = {}
  for _, definition in ipairs(order) do
    local ok, value = pcall(M.scope_key, definition)
    if not ok then
      errors[#errors + 1] = definition.id .. ": scope key failed: " .. tostring(value)
    elseif type(value) ~= "string" or value == "" then
      errors[#errors + 1] = definition.id .. ": empty scope key"
    end
    if definition.policy == "hard" and type(definition.unresolved) ~= "function" then
      errors[#errors + 1] = definition.id .. ": hard window needs an unresolved() progress measure"
    end
    if #definition.blocks == 0 then errors[#errors + 1] = definition.id .. ": blocks no actions" end
    if #definition.acknowledged_by == 0 then errors[#errors + 1] = definition.id .. ": no acknowledgement actions" end
  end
  return #errors == 0, errors
end

return M
