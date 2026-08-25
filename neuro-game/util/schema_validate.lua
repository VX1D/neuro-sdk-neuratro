local json = require("util.neuro_json")

local function is_object_table(value)
  if type(value) ~= "table" then
    return false
  end
  if json.is_array(value) then
    return false
  end
  if json.is_object(value) then
    return true
  end
  for k, _ in pairs(value) do
    if type(k) ~= "string" then
      return false
    end
  end
  return true
end

local function is_array_table(value)
  if type(value) ~= "table" then
    return false
  end
  if json.is_object(value) then
    return false
  end
  if json.is_array(value) then
    return true
  end
  local count, max = 0, 0
  for k, _ in pairs(value) do
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
      return false
    end
    count = count + 1
    if k > max then max = k end
  end
  return count == max
end

local function is_integer(value)
  return type(value) == "number" and value == math.floor(value)
    and value ~= math.huge and value ~= -math.huge
end

local function utf8_length(value)
  local length = 0
  for i = 1, #value do
    local byte = value:byte(i)
    if byte < 0x80 or byte >= 0xC0 then length = length + 1 end
  end
  return length
end

local function enum_contains(enum, value)
  if not enum then
    return true
  end
  for i = 1, #enum do
    if enum[i] == value then
      return true
    end
  end
  return false
end

local function validate_value(schema, value, label)
  if not schema then
    return true
  end
  local t = schema.type
  if not t and (schema.required or schema.properties) then t = "object" end
  if t == "object" then
    if not is_object_table(value) then
      return false, label .. " must be an object."
    end
    local required = schema.required or {}
    local missing = {}
    for i = 1, #required do
      local key = required[i]
      if value[key] == nil then
        missing[#missing + 1] = key
      end
    end
    if #missing > 0 then
      local word = (#missing > 1) and "parameters" or "parameter"
      return false, "Missing required " .. word .. ": " .. table.concat(missing, ", ")
    end
    local props = schema.properties or {}
    for key, prop in pairs(props) do
      if value[key] ~= nil then
        local ok, err = validate_value(prop, value[key], key)
        if not ok then
          return false, err
        end
      end
    end
  elseif t == "array" then
    if not is_array_table(value) then
      return false, label .. " must be an array."
    end
    if schema.items then
      for i = 1, #value do
        local ok, err = validate_value(schema.items, value[i], label .. "[" .. i .. "]")
        if not ok then
          return false, err
        end
      end
    end
    if schema.minItems and #value < schema.minItems then
      return false, label .. " must have at least " .. tostring(schema.minItems) .. " item(s)."
    end
    if schema.maxItems and #value > schema.maxItems then
      return false, label .. " must have at most " .. tostring(schema.maxItems) .. " item(s)."
    end
    if schema.uniqueItems then
      local item_schema = schema.items
      local item_type = type(item_schema) == "table" and item_schema.type or nil
      local item_is_non_scalar = item_type == "object" or item_type == "array"
        or (not item_type and type(item_schema) == "table"
          and (item_schema.required or item_schema.properties))
      if item_is_non_scalar then
        return false, label .. " uses uniqueItems with non-scalar items; this schema is unsupported."
      end
      local seen = {}
      for i = 1, #value do
        local v = value[i]
        if type(v) ~= "table" then
          if seen[v] then return false, label .. " items must be unique (duplicate: " .. tostring(v) .. ")." end
          seen[v] = true
        else
          return false, label .. " uses uniqueItems with non-scalar items; this schema is unsupported."
        end
      end
    end
  elseif t == "string" then
    if type(value) ~= "string" then
      return false, label .. " must be a string."
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
    if type(value) ~= "number" then
      return false, label .. " must be a number."
    end
  elseif t == "boolean" then
    if type(value) ~= "boolean" then
      return false, label .. " must be a boolean."
    end
  end
  if schema.enum and not enum_contains(schema.enum, value) then
    local opts = {}
    for _, ev in ipairs(schema.enum) do opts[#opts + 1] = tostring(ev) end
    return false, label .. " must be one of: " .. table.concat(opts, ", ")
  end
  if schema.minimum ~= nil and type(value) == "number" and value < schema.minimum then
    return false, label .. " must be >= " .. tostring(schema.minimum)
  end
  if schema.maximum ~= nil and type(value) == "number" and value > schema.maximum then
    return false, label .. " must be <= " .. tostring(schema.maximum)
  end
  return true
end

return { validate_value = validate_value, is_object_table = is_object_table }
