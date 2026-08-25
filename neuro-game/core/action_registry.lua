local M = {}
local Metrics = require("util.metrics")

local contracts = {}
local narrowers = {}
local preflights = {}
local availability = {}
local candidate_providers = {}
local provider_errors = {}

local function provider_failed(kind, name, err)
  local key = tostring(kind) .. ":" .. tostring(name)
  Metrics.incr("action_registry_provider_error")
  if provider_errors[key] then return end
  provider_errors[key] = true
  print("[neuro-game] action_registry: " .. tostring(kind) .. " provider for '"
    .. tostring(name) .. "' failed: " .. tostring(err))
end

local function sorted_keys(t)
  local out = {}
  for key in pairs(t or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local DEFAULT_FAILURE_CODES = sorted_keys(require("core.action_result").CODES)
M.DEFAULT_FAILURE_CODES = DEFAULT_FAILURE_CODES

local SCALAR_NOUN = { integer = "int", number = "number", string = "text", boolean = "true|false" }

local function value_range(spec)
  if spec.minimum ~= nil and spec.maximum ~= nil then
    return " " .. tostring(spec.minimum) .. "-" .. tostring(spec.maximum)
  end
  if spec.minimum ~= nil then return " " .. tostring(spec.minimum) .. "+" end
  if spec.maximum ~= nil then return " up to " .. tostring(spec.maximum) end
  return ""
end

local function count_phrase(spec, noun, unique)
  local lo, hi = spec.minItems, spec.maxItems
  local many = (unique and " different " or " ") .. (noun or "values")
  if lo and hi and lo == 1 and hi == 1 then
    return "pick 1 " .. ((noun or "value"):gsub("s$", ""))
  end
  if lo and hi and lo == hi then return "pick exactly " .. tostring(lo) .. many end
  if lo and hi then return "pick " .. tostring(lo) .. " to " .. tostring(hi) .. many end
  if lo then return "pick " .. tostring(lo) .. " or more" .. many end
  if hi then return "pick up to " .. tostring(hi) .. many end
  return "pick one or more" .. many
end

local function count_noun(spec, singular)
  local lo, hi = spec.minItems, spec.maxItems
  local plural = singular .. "s"
  local function amount(count) return tostring(count) .. " " .. (count == 1 and singular or plural) end
  if lo and hi and lo == hi then
    return (lo == 1) and amount(1) or ("exactly " .. amount(lo))
  end
  if lo and hi then return tostring(lo) .. "-" .. tostring(hi) .. " " .. plural end
  if lo then return "at least " .. amount(lo) end
  if hi then return "up to " .. amount(hi) end
  return "any number of " .. plural
end

local function render_description(description, schema)
  if type(description) ~= "string" or not description:find("{count:", 1, true) then
    return description
  end
  local properties = (schema or {}).properties or {}
  return (description:gsub("{count:([%w_]+):([^}]+)}", function(field, singular)
    return count_noun(properties[field] or {}, singular)
  end))
end

local ordered_field_names, object_hint

local function value_hint(spec, optional, noun, depth)
  spec = spec or {}
  local opt = optional and ", optional" or ""
  if spec.enum then
    local choices = {}
    for _, v in ipairs(spec.enum) do choices[#choices + 1] = '"' .. tostring(v) .. '"' end
    return "<" .. table.concat(choices, "|") .. opt .. ">"
  end
  if spec.type == "array" then
    local items = spec.items or {}
    if items.type == "object" and items.properties and depth < 2 then
      return "[" .. object_hint(items, depth + 1) .. "]" .. (optional and " (optional)" or "")
    end
    return "[<" .. count_phrase(spec, noun, spec.uniqueItems) .. opt .. ">]"
  end
  if spec.type == "object" then return "<object" .. opt .. ">" end
  local base = SCALAR_NOUN[spec.type] or "value"
  if spec.type == "integer" or spec.type == "number" then base = base .. value_range(spec) end
  return "<" .. base .. opt .. ">"
end

function object_hint(schema, depth, hints)
  local properties = schema.properties or {}
  local required = {}
  for _, name in ipairs(schema.required or {}) do required[name] = true end
  local fields = {}
  for _, name in ipairs(ordered_field_names(schema)) do
    fields[#fields + 1] = '"' .. name .. '":'
      .. value_hint(properties[name], not required[name], (hints or {})[name], depth)
  end
  return "{" .. table.concat(fields, ",") .. "}"
end

function ordered_field_names(schema)
  local properties = schema.properties or {}
  local out, seen = {}, {}
  for _, name in ipairs(schema.required or {}) do
    if properties[name] ~= nil and not seen[name] then out[#out + 1] = name; seen[name] = true end
  end
  for _, name in ipairs(sorted_keys(properties)) do
    if not seen[name] then out[#out + 1] = name end
  end
  return out
end

local function default_prompt(contract)
  return contract.name .. "|" .. object_hint(contract.schema or {}, 0, contract.arg_hints)
end

function M.register(definition, states)
  assert(type(definition) == "table" and type(definition.name) == "string",
    "action definition requires a name")
  local existing = contracts[definition.name] or {}
  existing.name = definition.name
  existing.description = definition.description
  existing.schema = definition.schema
  existing.arg_hints = definition.arg_hints or existing.arg_hints
  existing.states = states or existing.states or {}
  existing.failure_codes = definition.failure_codes or existing.failure_codes or DEFAULT_FAILURE_CODES
  existing.idempotency = definition.idempotency or existing.idempotency or "session_scoped_action_id"
  contracts[definition.name] = existing
  return existing
end

function M.bind_schema_narrower(name, narrower)
  assert(contracts[name], "cannot bind a schema narrower for unknown action: " .. tostring(name))
  assert(type(narrower) == "function", "action schema narrower must be a function")
  narrowers[name] = narrower
end

local function resolve(name)
  local contract = contracts[name]
  if not contract then return nil end
  local schema = contract.schema
  local narrower = narrowers[name]
  if narrower then
    local ok, narrowed = pcall(narrower, schema)
    if not ok then
      provider_failed("schema narrower", name, narrowed)
    elseif type(narrowed) == "table" then
      schema = narrowed
    end
  end
  local description = render_description(contract.description, schema)
  if schema == contract.schema and description == contract.description then return contract end
  local out = {}
  for key, value in pairs(contract) do out[key] = value end
  out.schema = schema
  out.description = description
  return out
end

function M.get(name)
  local contract = resolve(name)
  if not contract then return nil end
  contract.preflight = preflights[name]
  contract.available = availability[name] or function() return true end
  return contract
end

function M.all()
  local out = {}
  for _, name in ipairs(sorted_keys(contracts)) do out[#out + 1] = M.get(name) end
  return out
end

function M.definitions()
  local out = {}
  for _, name in ipairs(M.names()) do
    local contract = resolve(name)
    out[#out + 1] = {
      name = contract.name,
      description = contract.description,
      schema = contract.schema,
    }
  end
  return out
end
function M.names()
  return sorted_keys(contracts)
end

function M.bind_preflight(name, preflight)
  assert(contracts[name], "cannot bind preflight for unknown action: " .. tostring(name))
  assert(type(preflight) == "function", "action preflight must be a function")
  preflights[name] = preflight
end

function M.bind_availability(name, predicate)
  assert(type(name) == "string" and type(predicate) == "function",
    "action availability requires a name and predicate")
  if availability[name] ~= nil then
    print("[neuro-game] action_registry: overwriting availability for '" .. name .. "'")
  end
  availability[name] = predicate
end

function M.bind_candidates(name, provider)
  assert(contracts[name], "cannot bind candidates for unknown action: " .. tostring(name))
  assert(type(provider) == "function", "action candidate provider must be a function")
  candidate_providers[name] = provider
end

function M.available(name)
  if not contracts[name] then return false end
  local predicate = availability[name]
  if not predicate then
    pcall(require, "core.dispatcher")
    predicate = availability[name]
  end
  if not predicate then return true end
  local ok, result = pcall(predicate)
  if not ok then provider_failed("availability", name, result) end
  return ok and result ~= false
end

function M.preflight(name, data)
  local preflight = preflights[name]
  if not preflight then
    return nil, require("core.action_result").error(
      "ACTION_UNAVAILABLE", "No preflight is registered for action '" .. tostring(name) .. "'.")
  end
  return preflight(data or {})
end

function M.candidates(name)
  local provider = candidate_providers[name]
  if not provider then
    pcall(require, "core.dispatcher")
    provider = candidate_providers[name]
  end
  if not provider then return {} end
  local ok, result = pcall(provider)
  if not ok then provider_failed("candidate", name, result) end
  return (ok and type(result) == "table") and result or {}
end

function M.prompt(name)
  local contract = M.get(name)
  if not contract then return nil end
  return default_prompt(contract)
end

function M.example(name, bound, fields)
  local contract = M.get(name)
  if not contract then return nil end
  local schema = contract.schema or {}
  local properties = schema.properties or {}
  local hints = contract.arg_hints or {}
  local required = {}
  for _, key in ipairs(schema.required or {}) do required[key] = true end
  bound = bound or {}
  local names = fields
  if not names then
    names = {}
    for _, key in ipairs(ordered_field_names(schema)) do
      if required[key] or bound[key] ~= nil then names[#names + 1] = key end
    end
  end
  local out = {}
  for _, key in ipairs(names) do
    assert(properties[key] ~= nil,
      string.format("field '%s' is not in the %s contract", tostring(key), name))
    local rendered
    if bound[key] ~= nil then
      rendered = M.encode_ordered(bound[key], properties[key])
    else
      rendered = value_hint(properties[key], false, hints[key], 0)
    end
    out[#out + 1] = '"' .. key .. '":' .. rendered
  end
  return name .. "|{" .. table.concat(out, ",") .. "}"
end

function M.render(name, payload)
  local contract = M.get(name)
  if not contract then return nil end
  local schema = contract.schema or {}
  local properties = schema.properties or {}
  local fields = {}
  for field, value in pairs(payload or {}) do
    assert(field:sub(1, 1) == "_" or properties[field] ~= nil,
      string.format("field '%s' is not in the %s contract", tostring(field), name))
    fields[field] = value
  end
  return name .. "|" .. M.encode_ordered(fields, schema)
end

function M.encode_ordered(value, schema)
  local NeuroJson = require("util.neuro_json")
  if type(value) ~= "table" then return NeuroJson.encode(value) end
  if NeuroJson.is_array(value) or (#value > 0 and not NeuroJson.is_object(value)) then
    local out = {}
    for i = 1, #value do out[#out + 1] = M.encode_ordered(value[i], (schema or {}).items) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  schema = schema or {}
  local properties = schema.properties or {}
  local order, seen = {}, {}
  for _, key in ipairs(ordered_field_names(schema)) do
    if value[key] ~= nil then order[#order + 1] = key; seen[key] = true end
  end
  for _, key in ipairs(sorted_keys(value)) do
    if not seen[key] then order[#order + 1] = key end
  end
  local out = {}
  for _, key in ipairs(order) do
    out[#out + 1] = NeuroJson.encode(tostring(key)) .. ":" .. M.encode_ordered(value[key], properties[key])
  end
  return "{" .. table.concat(out, ",") .. "}"
end

function M.validate(opts)
  opts = opts or {}
  local errors = {}
  for _, contract in ipairs(M.all()) do
    if type(contract.description) ~= "string" or contract.description == "" then
      errors[#errors + 1] = contract.name .. ": missing description"
    end
    if type(contract.schema) ~= "table" or contract.schema.type ~= "object" then
      errors[#errors + 1] = contract.name .. ": missing object schema"
    end
    if type(contract.states) ~= "table" or next(contract.states) == nil then
      errors[#errors + 1] = contract.name .. ": no states"
    end
    if type(contract.failure_codes) ~= "table" or #contract.failure_codes == 0 then
      errors[#errors + 1] = contract.name .. ": no failure code contract"
    else
      local codes = require("core.action_result").CODES
      for _, code in ipairs(contract.failure_codes) do
        if not codes[code] then errors[#errors + 1] = contract.name .. ": unknown failure code " .. tostring(code) end
      end
    end
    if contract.idempotency ~= "session_scoped_action_id" then
      errors[#errors + 1] = contract.name .. ": invalid idempotency contract"
    end
    if type(M.prompt(contract.name)) ~= "string" then
      errors[#errors + 1] = contract.name .. ": no prompt"
    end
    if opts.require_preflights and not preflights[contract.name] then
      errors[#errors + 1] = contract.name .. ": no preflight"
    end
  end
  return #errors == 0, errors
end

M.DYING_GRACE = 10

local function clock()
  return require("util.utils").gate_now("action_dying_grace")
end

function M.now()
  return clock()
end

local live_registered = {}
local dying = {}
local withdrawn = {}

local function name_list(names)
  if type(names) == "string" then return { names } end
  if type(names) ~= "table" then return {} end
  return names
end

function M.prune(now)
  local t = tonumber(now) or clock()
  for name, at in pairs(dying) do
    if (t - at) >= M.DYING_GRACE then dying[name] = nil end
  end
end

function M.note_registered(names)
  for _, name in ipairs(name_list(names)) do
    if type(name) == "string" and name ~= "" then
      live_registered[name] = true
      dying[name] = nil
      withdrawn[name] = nil
    end
  end
end

function M.note_unregistered(names, now)
  local stamp = tonumber(now) or clock()
  for _, name in ipairs(name_list(names)) do
    if type(name) == "string" and name ~= "" then
      live_registered[name] = nil
      dying[name] = stamp
      withdrawn[name] = true
    end
  end
  M.prune(stamp)
end

function M.is_registered(name)
  return type(name) == "string" and live_registered[name] == true
end

function M.is_withdrawn(name)
  return type(name) == "string" and withdrawn[name] == true
end

function M.is_recently_unregistered(name, now)
  if type(name) ~= "string" then return false end
  local at = dying[name]
  if at == nil then return false end
  local t = tonumber(now) or clock()
  if (t - at) >= M.DYING_GRACE then
    dying[name] = nil
    return false
  end
  return true
end

function M.reset()
  live_registered = {}
  dying = {}
  withdrawn = {}
end

function M.snapshot()
  local registered, expiring, gone = {}, {}, {}
  for name in pairs(live_registered) do registered[name] = true end
  for name, at in pairs(dying) do expiring[name] = at end
  for name in pairs(withdrawn) do gone[name] = true end
  return { registered = registered, dying = expiring, withdrawn = gone }
end

return M
