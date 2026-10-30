local json = require("util.neuro_json")

local SUPPORTED_KEYWORDS = {
  type = true, properties = true, required = true, items = true,
  minItems = true, maxItems = true, minLength = true, maxLength = true,
  uniqueItems = true, minimum = true, maximum = true, enum = true,
  pattern = true,
}

local function dense_array_table(value)
  if type(value) ~= "table" or not json.is_array(value) then return false end
  local max, count = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return false
    end
    count = count + 1
    if key > max then max = key end
  end
  return count == max
end

local function is_object_table(value)
  return json.is_object(value) and not (getmetatable(value) ~= nil and json.is_array(value))
end

local function is_array_table(value)
  if type(value) ~= "table" then return false end
  if getmetatable(value) ~= nil then return json.is_explicit_array(value) end
  local count = 0
  for k in pairs(value) do
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then return false end
    count = count + 1
  end
  return count == #value
end

local function is_integer(value)
  return json.is_safe_number(value)
    and value == math.floor(value)
end
local function array_end(value)
  local max = 0
  for key in pairs(value) do
    if type(key) == "number" and key > max then max = key end
  end
  return max
end


local function utf8_length(value)
  local length = 0
  for i = 1, #value do
    local byte = value:byte(i)
    if byte < 0x80 or byte >= 0xC0 then length = length + 1 end
  end
  return length
end

local function json_equal(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  if json.is_null(a) or json.is_null(b) then
    return json.is_null(a) and json.is_null(b)
  end
  local function shape(value)
    if json.is_explicit_array(value) then return "array" end
    if type(value) ~= "table" or json.is_null(value) then return nil end
    if getmetatable(value) ~= nil then return "object" end
    if json.is_array(value) and next(value) ~= nil then return "array" end
    return "object"
  end
  local a_shape, b_shape = shape(a), shape(b)
  if a_shape ~= b_shape then return false end
  if a_shape == "array" then
    local a_end, b_end = array_end(a), array_end(b)
    if a_end ~= b_end then return false end
    for i = 1, a_end do
      local av, bv = a[i], b[i]
      if av == nil then av = json.null end
      if bv == nil then bv = json.null end
      if not json_equal(av, bv) then return false end
    end
    return true
  end
  for key, value in pairs(a) do
    if not json_equal(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

local function enum_contains(enum, value)
  if not enum then
    return true
  end
  for i = 1, #enum do
    if json_equal(enum[i], value) then
      return true
    end
  end
  return false
end

-- Only anchored character-class patterns using * or + are supported at registration.
local function pattern_class(pattern)
  return type(pattern) == "string" and pattern:match("^%^%[([%w_%-]+)%][%*%+]%$$") or nil
end

local function pattern_rule(pattern)
  local class = pattern_class(pattern)
  if not class then return "must match the pattern " .. tostring(pattern) .. "." end
  local parts, i = {}, 1
  while i <= #class do
    local a, dash, b = class:sub(i, i), class:sub(i + 1, i + 1), class:sub(i + 2, i + 2)
    if dash == "-" and b ~= "" then
      parts[#parts + 1] = a .. "-" .. b
      i = i + 3
    else
      parts[#parts + 1] = "'" .. a .. "'"
      i = i + 1
    end
  end
  return "may contain only the characters " .. table.concat(parts, ", ") .. "."
end

local function pattern_supported(pattern)
  return pattern_class(pattern) ~= nil
end

local function matches_pattern(value, pattern)
  -- Unsupported patterns fail open because no retry could satisfy them.
  return not pattern_supported(pattern) or value:find(pattern) ~= nil
end


local function permits_null(schema)
  if type(schema) ~= "table" or type(schema.enum) ~= "table" then return false end
  for i = 1, #schema.enum do
    if json.is_null(schema.enum[i]) then return true end
  end
  return false
end

local function required_path(spec, path)
  local inner = type(spec) == "table" and spec.required or nil
  if type(inner) ~= "table" or #inner == 0 then return path end
  local parts = {}
  for i = 1, #inner do parts[i] = path .. "." .. inner[i] end
  return path .. " (with " .. table.concat(parts, ", ") .. ")"
end

local function walk(schema, value, label, nested)
  if schema == nil then
    return true
  end
  schema = json.normalize_schema(schema, "schema")
  local t = schema.type
  if t == nil and (schema.required or schema.properties) then t = "object" end
  if t == "object" then
    if not is_object_table(value) then
      return false, label .. " must be an object."
    end
    local required = schema.required or {}
    local props = schema.properties or {}
    local missing = {}
    for i = 1, #required do
      local key = required[i]
      if value[key] == nil
          or (json.is_null(value[key]) and not permits_null(props[key])) then
        missing[#missing + 1] = required_path(props[key], nested and (label .. "." .. key) or key)
      end
    end
    if #missing > 0 then
      local word = (#missing > 1) and "parameters" or "parameter"
      return false, "Missing required " .. word .. ": " .. table.concat(missing, ", ") .. "."
    end
    -- Unknown properties pass because clients cannot infer an unadvertised additionalProperties rule.
    for key, prop in pairs(props) do
      if value[key] ~= nil
          and not (json.is_null(value[key]) and not permits_null(prop)) then
        local ok, err = walk(prop, value[key], nested and (label .. "." .. key) or key, true)
        if not ok then
          return false, err
        end
      end
    end
  elseif t == "array" then
    if not is_array_table(value) then
      return false, label .. " must be an array."
    end
    local value_end = array_end(value)
    if schema.items ~= nil then
      for i = 1, value_end do
        local item = value[i]
        if item == nil then item = json.null end
        local ok, err = walk(schema.items, item, label .. "[" .. i .. "]", true)
        if not ok then return false, err end
      end
    end
    if schema.minItems and value_end < schema.minItems then
      return false, label .. " must have at least " .. tostring(schema.minItems) .. " item(s)."
    end
    if schema.maxItems and value_end > schema.maxItems then
      return false, label .. " must have at most " .. tostring(schema.maxItems) .. " item(s)."
    end
    if schema.uniqueItems then
      for i = 1, value_end do
        for j = 1, i - 1 do
          local a, b = value[i], value[j]
          if a == nil then a = json.null end
          if b == nil then b = json.null end
          if json_equal(a, b) then
            return false, label .. " items must be unique (duplicate at index " .. j .. ")."
          end
        end
      end
    end
  elseif t == "string" then
    if type(value) ~= "string" then
      return false, label .. " must be text (a string)."
    end
    if not json.is_valid_utf8(value) then
      return false, label .. " must be valid UTF-8 text."
    end
    if schema.pattern ~= nil then
      if type(schema.pattern) ~= "string" or not matches_pattern(value, schema.pattern) then
        return false, label .. " " .. pattern_rule(schema.pattern)
      end
    end
    local length = (schema.minLength or schema.maxLength) and utf8_length(value)
    if schema.minLength and length < schema.minLength then
      return false, label .. " must be at least " .. tostring(schema.minLength) .. " character(s)."
    end
    if schema.maxLength and length > schema.maxLength then
      return false, label .. " must be at most " .. tostring(schema.maxLength) .. " character(s)."
    end
  elseif t == "integer" then
    if not is_integer(value) then
      return false, label .. " must be an integer."
    end
  elseif t == "number" then
    if not json.is_safe_number(value) then
      return false, label .. " must be a finite safe number."
    end
  elseif t == "boolean" then
    if type(value) ~= "boolean" then
      return false, label .. " must be a boolean."
    end
  end
  if schema.enum and not enum_contains(schema.enum, value) then
    local opts = {}
    for _, ev in ipairs(schema.enum) do opts[#opts + 1] = tostring(ev) end
    return false, label .. " must be one of: " .. table.concat(opts, ", ") .. "."
  end
  if schema.minimum ~= nil and type(value) == "number" and value < schema.minimum then
    return false, label .. " must be >= " .. tostring(schema.minimum) .. "."
  end
  if schema.maximum ~= nil and type(value) == "number" and value > schema.maximum then
    return false, label .. " must be <= " .. tostring(schema.maximum) .. "."
  end
  return true
end

local function validate_value(schema, value, label)
  return walk(schema, value, label, false)
end

local PLURAL = { integer = "integers", number = "numbers", string = "strings", boolean = "booleans", object = "objects" }

local function value_phrase(prop)
  if type(prop) ~= "table" then return "any value" end
  if type(prop.enum) == "table" then
    local opts = {}
    for _, v in ipairs(prop.enum) do opts[#opts + 1] = tostring(v) end
    return "one of: " .. table.concat(opts, ", ")
  end
  if prop.type == "array" then
    local item = type(prop.items) == "table" and PLURAL[prop.items.type]
    return item and ("array of " .. item) or "array"
  end
  return prop.type == "string" and "text" or tostring(prop.type or "any value")
end

local function payload_shape(schema)
  schema = type(schema) == "table" and schema or {}
  local props, parts = schema.properties or {}, {}
  for _, key in ipairs(schema.required or {}) do
    parts[#parts + 1] = tostring(key) .. " (" .. value_phrase(props[key]) .. ")"
  end
  if #parts == 0 then return "A valid payload is one JSON object, e.g. {}." end
  local list = #parts == 1 and parts[1]
    or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
  return "A valid payload is one JSON object with " .. list .. "."
end

return {
  validate_value = validate_value,
  payload_shape = payload_shape,
  permits_null = permits_null,
  is_object_table = is_object_table,
  dense_array_table = dense_array_table,
  pattern_supported = pattern_supported,
  SUPPORTED_KEYWORDS = SUPPORTED_KEYWORDS,
}
