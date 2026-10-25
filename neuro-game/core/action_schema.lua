local json = require("util.neuro_json")
local SchemaValidate = require("util.schema_validate")
local Metrics = require("util.metrics")
local M = {}
local MAX_SCHEMA_DEPTH = 256

local dense_array = SchemaValidate.dense_array_table

local VALID_TYPES = { object = true, array = true, string = true, integer = true, number = true,
  boolean = true }

local SUPPORTED_KEYWORDS = SchemaValidate.SUPPORTED_KEYWORDS

local function project_schema(value)
  if type(value) ~= "table" or not json.is_object(value) then return value end
  local out = {}
  for child_key, child in pairs(value) do
    if type(child_key) ~= "string" or not SUPPORTED_KEYWORDS[child_key] then
      Metrics.incr("action_schema_unsupported_keyword_stripped")
    elseif child_key == "properties" and type(child) == "table" and json.is_object(child) then
      local properties = {}
      for name, property in pairs(child) do
        properties[name] = project_schema(property)
      end
      out[child_key] = json.object(properties)
    elseif child_key == "items" then
      out[child_key] = project_schema(child)
    else
      out[child_key] = child
    end
  end
  return json.object(out)
end

function M.copy_schema_for_json(value, key)
  local copied = json.normalize_schema(value, key or "schema")
  if type(copied) ~= "table" then return copied end
  return project_schema(copied)
end

local finite_number = json.is_safe_number

local function nonnegative_integer(value)
  return (type(value) == "number" and value == math.floor(value)
      and value >= 0 and finite_number(value))
end

local function valid_schema_inner(schema, root, depth)
  if depth > MAX_SCHEMA_DEPTH then return false end
  if json.is_null(schema) or type(schema) ~= "table" or not json.is_object(schema) then
    return false
  end
  local kind = schema.type
  if kind ~= nil then
    if VALID_TYPES[kind] ~= true then return false end
    if root and kind ~= "object" then return false end
  elseif root and next(schema) ~= nil then
    return false
  end
  if next(schema) == nil then return true end

  local properties = schema.properties
  if properties ~= nil then
    if type(properties) ~= "table" or not json.is_object(properties) then return false end
    for _, property in pairs(properties) do
      if not valid_schema_inner(property, false, depth + 1) then return false end
    end
  end

  local required = schema.required
  if required ~= nil then
    if type(required) ~= "table" or not dense_array(required) then return false end
    for i = 1, #required do
      if type(required[i]) ~= "string" then return false end
      if properties == nil or properties[required[i]] == nil then return false end
    end
  end

  local items = schema.items
  if items ~= nil and ((type(items) == "table" and json.is_array(items))
      or not valid_schema_inner(items, false, depth + 1)) then
    return false
  end

  for _, key in ipairs({ "minItems", "maxItems", "minLength", "maxLength" }) do
    if schema[key] ~= nil and not nonnegative_integer(schema[key]) then return false end
  end
  if schema.uniqueItems ~= nil and type(schema.uniqueItems) ~= "boolean" then return false end
  if schema.minimum ~= nil and not finite_number(schema.minimum) then return false end
  if schema.maximum ~= nil and not finite_number(schema.maximum) then return false end
  if schema.enum ~= nil then
    if type(schema.enum) ~= "table" or not dense_array(schema.enum) or #schema.enum == 0 then
      return false
    end
  end
  if schema.pattern ~= nil then
    if type(schema.pattern) ~= "string" or not SchemaValidate.pattern_supported(schema.pattern) then
      return false
    end
  end
  return true
end

function M.valid_schema(schema, root)
  if not json.is_json_value(schema) then return false end
  local normalized, within_depth = json.normalize_schema(schema, "schema")
  return within_depth and valid_schema_inner(normalized, root == true, 0)
end
function M.valid_action_name(name)
  return type(name) == "string" and name ~= "" and json.is_valid_utf8(name)
end

function M.valid_definition(definition)
  if type(definition) ~= "table"
      or not M.valid_action_name(definition.name)
      or not definition.name:match("^[a-z0-9_-]+$")
      or type(definition.description) ~= "string"
      or not json.is_valid_utf8(definition.description) then
    return false
  end
  return definition.schema == nil or M.valid_schema(definition.schema, true)
end

return M
