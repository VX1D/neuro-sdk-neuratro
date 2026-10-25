local M = {}
local Metrics = require("util.metrics")
local json = require("util.neuro_json")
local ActionSchema = require("core.action_schema")

local contracts = {}
local prompt_narrowers = {}
local preflights = {}
local payload_guards = {}
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

local function ordered_field_names(schema)
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

local ARRAY_FIELD_NOUNS = {
  indices = "hand position",
  intents = "joker intent",
  action_names = "action name",
  hand_indices = "hand position",
}

local function same_spec(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same_spec(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function narrows(spec, base, field)
  local base_spec = type(base) == "table" and type(base.properties) == "table" and base.properties[field] or nil
  return not same_spec(spec, base_spec)
end

local function render_schema_count_hint(schema, base)
  local properties = (schema or {}).properties or {}
  for _, field in ipairs(ordered_field_names(schema or {})) do
    local spec = properties[field]
    if type(spec) == "table" and spec.type == "array" and narrows(spec, base, field)
        and (spec.minItems ~= nil or spec.maxItems ~= nil) then
      local singular = ARRAY_FIELD_NOUNS[field] or field:gsub("_", " ")
      return "Select " .. count_noun(spec, singular), field
    end
  end
  return nil
end

local function display_value(value, depth)
  local kind = type(value)
  if kind == "string" then
    if not json.is_valid_utf8(value) then return '"<invalid utf-8>"' end
    return json.encode(value)
  end
  if kind ~= "table" then return tostring(value) end
  depth = depth or 0
  if depth >= 2 then return "object" end
  local parts = {}
  if #value > 0 then
    for _, item in ipairs(value) do parts[#parts + 1] = display_value(item, depth + 1) end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local ak, bk = type(a), type(b)
    if ak ~= bk then return ak < bk end
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. display_value(value[key], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function field_hint(spec, field)
  if type(spec) ~= "table" then return nil end
  if type(spec.enum) == "table" and #spec.enum > 0 then
    local shown = {}
    for i = 1, math.min(#spec.enum, 6) do shown[#shown + 1] = tostring(spec.enum[i]) end
    if #spec.enum > 6 then shown[#shown + 1] = "..." end
    return "one of " .. table.concat(shown, "/")
  end
  if spec.type == "array" then
    local items = type(spec.items) == "table" and spec.items or {}
    local singular = ARRAY_FIELD_NOUNS[field or ""]
      or (field and field:gsub("_", " "):gsub("e?s$", "")) or "entry"
    local noun = count_noun(spec, singular)
    local bound_note = ""
    if items.maximum then bound_note = " 1-" .. tostring(items.maximum) end
    return noun .. bound_note
  end
  if spec.type == "integer" or spec.type == "number" then
    if spec.minimum and spec.maximum then
      return tostring(spec.minimum) .. "-" .. tostring(spec.maximum)
    end
    if spec.maximum then return "at most " .. tostring(spec.maximum) end
    return nil
  end
  if spec.type == "boolean" then return "true/false" end
  return nil
end

local function field_details(bound, selected, schema, base)
  local details, counted = {}, {}
  for _, key in ipairs(selected or {}) do
    local value = bound and bound[key]
    if type(value) == "table" and #value == 0 and next(value) ~= nil then
      local subkeys = {}
      for sub in pairs(value) do subkeys[#subkeys + 1] = tostring(sub) end
      table.sort(subkeys)
      for _, sub in ipairs(subkeys) do
        details[#details + 1] = key .. "." .. sub .. " " .. display_value(value[sub], 1)
      end
    elseif value ~= nil then
      details[#details + 1] = key .. " " .. display_value(value)
    else
      local spec = (schema.properties or {})[key]
      local hint = narrows(spec, base, key) and field_hint(spec, key) or nil
      details[#details + 1] = hint and (key .. " (" .. hint .. ")") or key
      if hint and type(spec) == "table" and spec.type == "array"
        and (spec.minItems ~= nil or spec.maxItems ~= nil) then
        counted[key] = true
      end
    end
  end
  return details, counted
end

local PHRASES = require("core.action_phrases")

local function action_head(name)
  return assert(PHRASES[name], "no prose phrase for action " .. tostring(name))
end
M.phrase = action_head

local function action_context(name, bound, fields, schema)
  schema = schema or (M.get and M.get(name) or {}).schema or {}
  local selected = fields
  if not selected then
    selected = {}
    for _, key in ipairs(ordered_field_names(schema)) do
      if bound and bound[key] ~= nil then selected[#selected + 1] = key end
    end
  end
  if bound and type(bound.name) == "string" then
    local reordered = { "name" }
    for _, key in ipairs(selected) do
      if key ~= "name" then reordered[#reordered + 1] = key end
    end
    if #reordered == #selected then selected = reordered end
  end
  local details, counted = field_details(bound, selected, schema, (contracts[name] or {}).schema)
  local out = action_head(name)
  if #details > 0 then out = out .. " with " .. table.concat(details, ", ") end
  return out, counted
end
function M.register(definition, states)
  if not ActionSchema.valid_definition(definition) then
    Metrics.incr("action_definition_rejected")
    print("[neuro-game] Skipping invalid action definition ("
      .. tostring(type(definition) == "table" and definition.name or definition) .. ")")
    return false
  end
  local existing = contracts[definition.name] or {}
  existing.name = definition.name
  existing.description = definition.description
  existing.schema = definition.schema
  existing.states = states or existing.states or {}
  contracts[definition.name] = existing
  return existing
end


function M.bind_prompt_narrower(name, narrower)
  assert(contracts[name], "cannot bind a prompt narrower for unknown action: " .. tostring(name))
  assert(type(narrower) == "function", "action prompt narrower must be a function")
  prompt_narrowers[name] = narrower
end

local function resolve(name, for_display)
  local contract = contracts[name]
  if not contract then return nil end
  local schema = contract.schema
  local narrower = for_display and prompt_narrowers[name]
  if narrower then
    local ok, narrowed = pcall(narrower, schema)
    if not ok then
      provider_failed("prompt narrower", name, narrowed)
    elseif type(narrowed) == "table" then
      schema = narrowed
    end
  end
  local out = {}
  for key, value in pairs(contract) do out[key] = value end
  out.schema = schema
  return out
end

local function always_available() return true end

local function bound(name, for_display)
  local contract = resolve(name, for_display)
  if not contract then return nil end
  contract.preflight = preflights[name]
  contract.available = availability[name] or always_available
  return contract
end

function M.get(name)
  return bound(name, false)
end

function M.display(name)
  return bound(name, true)
end

function M.definitions()
  local out = {}
  for _, name in ipairs(M.names()) do
    local contract = contracts[name]
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
function M.bind_payload_guard(name, guard)
  assert(contracts[name], "cannot bind payload guard for unknown action: " .. tostring(name))
  assert(type(guard) == "function", "action payload guard must be a function")
  payload_guards[name] = guard
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

local function provider(tbl, name)
  if not tbl[name] then pcall(require, "core.dispatcher") end
  return tbl[name]
end

local function availability_check(name)
  if not contracts[name] then return false, "There is no action named '" .. tostring(name) .. "'." end
  local predicate = provider(availability, name)
  if not predicate then return true end
  local ok, result, reason = pcall(predicate)
  if not ok then
    provider_failed("availability", name, result)
    return false, "The game could not check whether that move is possible right now; choose another."
  end
  if result ~= false then return true end
  return false, reason
end

function M.unavailable_reason(name) return (select(2, availability_check(name))) end
function M.available(name) return (availability_check(name)) end

function M.preflight(name, data)
  local preflight = preflights[name]
  if not preflight then
    return nil, require("core.action_result").error(
      "ACTION_UNAVAILABLE", "No preflight is registered for action '" .. tostring(name) .. "'.")
  end
  data = data or {}
  local guard = payload_guards[name]
  if guard then
    local ok, allowed, rejection = pcall(guard, data)
    if not ok then
      provider_failed("payload guard", name, allowed)
      return nil, require("core.action_result").internal_error()
    end
    if allowed == false then
      return nil, require("core.action_result").normalize(
        rejection or "Action payload is not allowed here.", "ACTION_REJECTED")
    end
  end
  local exec, err, event = preflight(data)
  if exec and type(exec) ~= "function" then
    provider_failed("preflight", name, "returned a " .. type(exec) .. " instead of an execution function")
    return nil, require("core.action_result").internal_error()
  end
  return exec, err, event
end

function M.candidates(name)
  local candidates = provider(candidate_providers, name)
  if not candidates then return {} end
  local ok, result = pcall(candidates)
  if not ok then provider_failed("candidate", name, result) end
  return (ok and type(result) == "table") and result or {}
end

function M.prompt(name, tail)
  local contract = M.display(name)
  if not contract then return nil end
  local schema = contract.schema or {}
  local base = contracts[name].schema
  local properties = schema.properties or {}
  local narrowed = {}
  for _, key in ipairs(ordered_field_names(schema)) do
    if narrows(properties[key], base, key) then narrowed[#narrowed + 1] = key end
  end
  local details, counted = field_details(nil, narrowed, schema, base)
  local prompt = action_head(contract.name)
  if #details > 0 then prompt = prompt .. " with " .. table.concat(details, ", ") end
  local hint, counted_field = render_schema_count_hint(schema, base)
  if hint and not counted[counted_field] then prompt = prompt .. ". " .. hint end
  if type(tail) == "string" and tail ~= "" then
    prompt = prompt .. ". " .. tail:sub(1, 1):upper() .. tail:sub(2)
  end
  return prompt
end

local function contract_schema(name)
  local contract = M.display(name)
  if not contract then return nil end
  local schema = contract.schema or {}
  return schema, schema.properties or {}
end

function M.example(name, bound_values, fields)
  local schema, properties = contract_schema(name)
  if not schema then return nil end
  local required = {}
  for _, key in ipairs(schema.required or {}) do required[key] = true end
  bound_values = bound_values or {}
  local names = fields
  if not names then
    names = {}
    for _, key in ipairs(ordered_field_names(schema)) do
      if required[key] or bound_values[key] ~= nil then names[#names + 1] = key end
    end
  end
  for _, key in ipairs(names) do
    assert(properties[key] ~= nil,
      string.format("field '%s' is not in the %s contract", tostring(key), name))
  end
  return (action_context(name, bound_values, names, schema))
end

function M.render(name, payload)
  local schema, properties = contract_schema(name)
  if not schema then return nil end
  for field in pairs(payload or {}) do
    assert(field:sub(1, 1) == "_" or properties[field] ~= nil,
      string.format("field '%s' is not in the %s contract", tostring(field), name))
  end
  return (action_context(name, payload or {}, nil, schema))
end


M.DYING_GRACE = 10

local function clock()
  return require("util.utils").gate_now("action_dying_grace")
end
M.now = clock

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
