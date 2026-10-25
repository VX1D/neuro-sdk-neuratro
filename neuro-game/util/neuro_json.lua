local json = {}

local encode

local MAX_DEPTH = 256
local ARRAY_MT = {}
local OBJECT_MT = {}
local NULL_MT = {}
local JSON_NULL = setmetatable({}, NULL_MT)

local function table_kind(value)
  local mt = getmetatable(value)
  if mt == ARRAY_MT then return "array" end
  if mt == OBJECT_MT then return "object" end
  if mt == NULL_MT then return "null" end
  return nil
end

local escape_char_map = {
  ['\\'] = '\\\\',
  ['"'] = '\\"',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local MAX_SAFE_INTEGER = 9007199254740991

local function utf8_sequence_length(s, i)
  local b = s:byte(i)
  if not b then return nil end
  if b < 0x80 then return 1 end
  local len, lo, hi
  if b >= 0xC2 and b <= 0xDF then len, lo, hi = 2, 0x80, 0xBF
  elseif b == 0xE0 then len, lo, hi = 3, 0xA0, 0xBF
  elseif (b >= 0xE1 and b <= 0xEC) or (b >= 0xEE and b <= 0xEF) then
    len, lo, hi = 3, 0x80, 0xBF
  elseif b == 0xED then len, lo, hi = 3, 0x80, 0x9F
  elseif b == 0xF0 then len, lo, hi = 4, 0x90, 0xBF
  elseif b >= 0xF1 and b <= 0xF3 then len, lo, hi = 4, 0x80, 0xBF
  elseif b == 0xF4 then len, lo, hi = 4, 0x80, 0x8F
  else return nil end
  if i + len - 1 > #s then return nil end
  local first = s:byte(i + 1)
  if first < lo or first > hi then return nil end
  for j = i + 2, i + len - 1 do
    local continuation = s:byte(j)
    if continuation < 0x80 or continuation > 0xBF then return nil end
  end
  return len
end

local function valid_utf8(s)
  local i = 1
  while i <= #s do
    local len = utf8_sequence_length(s, i)
    if not len then return false end
    i = i + len
  end
  return true
end

local REPLACEMENT_CHARACTER = "\239\191\189"
local function scrub_utf8(s)
  if valid_utf8(s) then return s end
  local out, i = {}, 1
  while i <= #s do
    local len = utf8_sequence_length(s, i)
    if len then
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    else
      out[#out + 1] = REPLACEMENT_CHARACTER
      i = i + 1
    end
  end
  return table.concat(out)
end

local function encode_string(val)
  val = scrub_utf8(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', function(c)
    return escape_char_map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function safe_number(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and (value ~= math.floor(value) or math.abs(value) <= MAX_SAFE_INTEGER)
end



local function is_array(t)
  local kind = table_kind(t)
  if kind == "object" or kind == "null" then
    return false
  end
  local max = 0
  local count = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
      if kind ~= "array" then
        return false
      end
    else
      if k > max then
        max = k
      end
      count = count + 1
    end
  end
  if kind == "array" then
    return true, max
  end
  if count == 0 then
    return true, 0
  end
  if max ~= count then
    return false
  end
  return true, max
end

local function is_object(t)
  local kind = table_kind(t)
  if kind == "array" or kind == "null" then
    return false
  end
  for k in pairs(t) do
    if type(k) ~= "string" or not valid_utf8(k) then
      return false
    end
  end
  return true
end
local ARRAY_SCHEMA_KEYS = { required = true, enum = true, type = true }
local function normalize_schema_inner(value, key, depth, seen)
  if json.is_null(value) or type(value) ~= "table" then return value, true end
  if depth >= MAX_DEPTH or seen[value] then return value, false end
  seen[value] = true
  local out, within_depth = {}, true
  for child_key, child in pairs(value) do
    local copied, child_ok =
      normalize_schema_inner(child, child_key, depth + 1, seen)
    out[child_key] = copied
    within_depth = within_depth and child_ok
  end
  seen[value] = nil
  local explicit = table_kind(value) == "array"
  local array_like = explicit or (table_kind(value) == nil and is_array(out))
  if array_like and (next(out) ~= nil or explicit or ARRAY_SCHEMA_KEYS[key]) then
    return json.array(out), within_depth
  end
  return json.object(out), within_depth
end

local function is_json_value(value, seen, depth)
  local t = type(value)
  if t == "nil" then return true end
  if t == "number" then return safe_number(value) end
  if t == "string" then return valid_utf8(value) end
  if t == "boolean" then return true end
  if t ~= "table" then return false end
  if table_kind(value) == "null" then return true end

  depth = depth or 0
  if depth >= MAX_DEPTH then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true

  local arr = is_array(value)
  local valid = arr
  if arr then
    for k, child in pairs(value) do
      if type(k) ~= "number" or k < 1 or k ~= math.floor(k)
          or not is_json_value(child, seen, depth + 1) then
        valid = false
        break
      end
    end
  elseif is_object(value) then
    valid = true
    for k, child in pairs(value) do
      if type(k) ~= "string" or not is_json_value(child, seen, depth + 1) then
        valid = false
        break
      end
    end
  else
    valid = false
  end

  seen[value] = nil
  return valid
end

local function encode_table(val, depth, seen)
  if depth >= MAX_DEPTH then
    error("json encode: max nesting depth exceeded")
  end
  if seen[val] then
    error("json encode: circular table")
  end
  seen[val] = true

  local kind = table_kind(val)
  local res = {}
  local arr, max = is_array(val)
  local keys = {}
  local key_names = {}
  for k in pairs(val) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then
      error("json encode: unsupported table key type")
    end
    if kt == "number" then
      if not safe_number(k) then
        error("json encode: unsafe or non-finite table key")
      end
      if kind == "array" and (k < 1 or k ~= math.floor(k)) then
        error("json encode: explicit array has an invalid key")
      end
    elseif kind == "array" then
      error("json encode: explicit array has a non-numeric key")
    end
    local name = tostring(k)
    if key_names[name] then
      error("json encode: table keys collide on the wire")
    end
    key_names[name] = true
    keys[#keys + 1] = k
  end
  if not arr and kind ~= "object" and not is_object(val) then
    error("json encode: table must be an array or object")
  end

  if arr then
    for i = 1, max do
      res[#res + 1] = encode(val[i], depth + 1, seen)
    end
    seen[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
  end)
  for _, k in ipairs(keys) do
    res[#res + 1] = encode_string(tostring(k)) .. ":" .. encode(val[k], depth + 1, seen)
  end
  seen[val] = nil
  return "{" .. table.concat(res, ",") .. "}"
end

function encode(val, depth, seen)
  depth = depth or 0
  seen = seen or {}
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "number" then
    if not safe_number(val) then return "null" end
    return tostring(val)
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "string" then
    return encode_string(val)
  elseif t == "table" then
    if table_kind(val) == "null" then
      return "null"
    end
    return encode_table(val, depth, seen)
  end
  return "null"
end


json.encode = function(val)
  return encode(val, 0, {})
end

local function tagged(val, mt)
  val = val or {}
  if val == JSON_NULL then return val end
  if type(val) == "table" then setmetatable(val, mt) end
  return val
end

json.object = function(val) return tagged(val, OBJECT_MT) end
json.array = function(val) return tagged(val, ARRAY_MT) end

json.is_explicit_array = function(val)
  return type(val) == "table" and table_kind(val) == "array"
end

json.is_array = function(val)
  return type(val) == "table" and is_array(val)
end

json.is_object = function(val)
  return type(val) == "table" and is_object(val)
end
json.is_valid_utf8 = valid_utf8
json.scrub_utf8 = scrub_utf8
json.is_safe_number = safe_number
json.normalize_schema = function(value, key)
  return normalize_schema_inner(value, key or "schema", 0, {})
end

json.is_json_value = function(val)
  return is_json_value(val, {}, 0)
end

json.is_null = function(val)
  return val == JSON_NULL
end

json.null = JSON_NULL

local parse

local function decode_error(_str, idx, msg)
  error("json decode error at " .. tostring(idx) .. ": " .. msg)
end
local function semantic_error(_str, idx, msg)
  error("json semantic rejection at " .. tostring(idx) .. ": " .. msg)
end



local function skip_whitespace(str, idx)
  local _, e = str:find("^[ \n\r\t]+", idx)
  return (e or idx - 1) + 1
end

local LITERALS = { n = { "null", JSON_NULL }, t = { "true", true }, f = { "false", false } }

local function parse_literal(str, idx, lit)
  local word = lit[1]
  if str:sub(idx, idx + #word - 1) == word then return lit[2], idx + #word end
  decode_error(str, idx, "invalid '" .. word .. "'")
end

local function safe_number_literal(token, value)
  if not safe_number(value) then return false end
  local mantissa = token:match("^%-?([^eE]+)")
  -- Reject non-zero literals that underflow to zero during Lua conversion.
  local significant = mantissa and mantissa:gsub("%.", "")
  if value == 0 and significant and significant:match("[1-9]") then return false end
  local fraction = mantissa and mantissa:match("%.(%d+)")
  if fraction and value == math.floor(value) and fraction:find("[1-9]") then
    local digits = mantissa:gsub("[^%d]", "")
    if #digits > 15 then return false end
  end
  return true
end

local function parse_number(str, idx)
  local i = idx
  if str:sub(i, i) == "-" then i = i + 1 end
  local int_part = str:match("^%d+", i)
  if not int_part or (#int_part > 1 and int_part:sub(1, 1) == "0") then
    decode_error(str, idx, "invalid number")
  end
  i = i + #int_part
  if str:sub(i, i) == "." then
    local frac = str:match("^%.%d+", i)
    if not frac then decode_error(str, idx, "invalid number") end
    i = i + #frac
  end
  if str:sub(i, i):match("[eE]") then
    local exp = str:match("^[eE][%+%-]?%d+", i)
    if not exp then decode_error(str, idx, "invalid number") end
    i = i + #exp
  end
  local token = str:sub(idx, i - 1)
  local num = tonumber(token)
  if not num then decode_error(str, idx, "invalid number") end
  if not safe_number_literal(token, num) then
    semantic_error(str, idx, "number is outside the safe numeric profile")
  end
  return num, i
end
local UNESCAPE = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", ["b"] = "\b",
  ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t" }

local function parse_string(str, idx)
  idx = idx + 1
  local res = {}
  while idx <= #str do
    local c = str:sub(idx, idx)
    if c == '"' then
      return table.concat(res), idx + 1
    elseif c == "\\" then
      local esc = str:sub(idx + 1, idx + 1)
      if esc == "u" then
        local hex = str:sub(idx + 2, idx + 5)
        if not hex:match("%x%x%x%x") then
          decode_error(str, idx, "invalid unicode escape")
        end
        local codepoint = tonumber(hex, 16)
        idx = idx + 6
        if codepoint >= 0xD800 and codepoint <= 0xDBFF then
          local hex2 = str:sub(idx + 2, idx + 5)
          local low = hex2:match("%x%x%x%x") and tonumber(hex2, 16)
          if str:sub(idx, idx + 1) == "\\u"
              and low and low >= 0xDC00 and low <= 0xDFFF then
            codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
            idx = idx + 6
          else
            decode_error(str, idx, "invalid unicode surrogate pair")
          end
        elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
          decode_error(str, idx, "unexpected low unicode surrogate")
        end
        if codepoint < 0x80 then
          res[#res + 1] = string.char(codepoint)
        elseif codepoint < 0x800 then
          res[#res + 1] = string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + (codepoint % 0x40))
        elseif codepoint < 0x10000 then
          res[#res + 1] = string.char(0xE0 + math.floor(codepoint / 0x1000), 0x80 + math.floor((codepoint % 0x1000) / 0x40), 0x80 + (codepoint % 0x40))
        else
          res[#res + 1] = string.char(0xF0 + math.floor(codepoint / 0x40000), 0x80 + math.floor((codepoint % 0x40000) / 0x1000), 0x80 + math.floor((codepoint % 0x1000) / 0x40), 0x80 + (codepoint % 0x40))
        end
      else
        local repl = UNESCAPE[esc]
        if not repl then
          decode_error(str, idx, "invalid escape char")
        end
        res[#res + 1] = repl
        idx = idx + 2
      end
    else
      local byte = c:byte()
      if byte < 0x20 then
        decode_error(str, idx, "unescaped control character in string")
      end
      local len = utf8_sequence_length(str, idx)
      if not len then
        decode_error(str, idx, "invalid UTF-8 in string")
      end
      res[#res + 1] = str:sub(idx, idx + len - 1)
      idx = idx + len
    end
  end
  decode_error(str, idx, "unterminated string")
end

local function parse_container(str, idx, depth, close, mt, read_item)
  idx = idx + 1
  local res = setmetatable({}, mt)
  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == close then
    return res, idx + 1
  end
  while idx <= #str do
    idx = skip_whitespace(str, read_item(str, idx, depth, res))
    local c = str:sub(idx, idx)
    if c == close then
      return res, idx + 1
    elseif c ~= "," then
      decode_error(str, idx, "expected ',' or '" .. close .. "'")
    end
    idx = skip_whitespace(str, idx + 1)
  end
  decode_error(str, idx, close == "]" and "unterminated array" or "unterminated object")
end

local function read_element(str, idx, depth, res)
  local val
  val, idx = parse(str, idx, depth)
  res[#res + 1] = val
  return idx
end

local function read_member(str, idx, depth, res)
  if str:sub(idx, idx) ~= '"' then
    decode_error(str, idx, "expected string key")
  end
  local key
  key, idx = parse_string(str, idx)
  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) ~= ":" then
    decode_error(str, idx, "expected ':'")
  end
  local val
  val, idx = parse(str, skip_whitespace(str, idx + 1), depth)
  res[key] = val
  return idx
end

function parse(str, idx, depth)
  depth = (depth or 0) + 1
  idx = skip_whitespace(str, idx or 1)
  local c = str:sub(idx, idx)
  if depth > MAX_DEPTH and (c == "{" or c == "[") then
    decode_error(str, idx, "max nesting depth exceeded")
  end
  if c == "{" then
    return parse_container(str, idx, depth, "}", OBJECT_MT, read_member)
  elseif c == "[" then
    return parse_container(str, idx, depth, "]", ARRAY_MT, read_element)
  elseif c == '"' then
    return parse_string(str, idx)
  elseif LITERALS[c] then
    return parse_literal(str, idx, LITERALS[c])
  else
    return parse_number(str, idx)
  end
end

function json.decode(str)
  if type(str) ~= "string" then
    error("json decode: expected string")
  end
  local res, idx = parse(str, 1)
  idx = skip_whitespace(str, idx)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end

return json
