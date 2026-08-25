local json = {}

local encode

local MAX_DEPTH = 50
local ARRAY_MT = {}
local OBJECT_MT = {}

local function table_kind(value)
  local mt = getmetatable(value)
  if mt == ARRAY_MT then return "array" end
  if mt == OBJECT_MT then return "object" end
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

local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local REPLACEMENT = "\239\191\189"

local function scrub_utf8(s)
  if not s:find("[\128-\255]") then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    if b < 0x80 then
      out[#out + 1] = s:sub(i, i); i = i + 1
    else
      local len, lo, hi
      if b >= 0xC2 and b <= 0xDF then len, lo, hi = 2, 0x80, 0xBF
      elseif b == 0xE0 then len, lo, hi = 3, 0xA0, 0xBF
      elseif (b >= 0xE1 and b <= 0xEC) or (b >= 0xEE and b <= 0xEF) then
        len, lo, hi = 3, 0x80, 0xBF
      elseif b == 0xED then len, lo, hi = 3, 0x80, 0x9F
      elseif b == 0xF0 then len, lo, hi = 4, 0x90, 0xBF
      elseif b >= 0xF1 and b <= 0xF3 then len, lo, hi = 4, 0x80, 0xBF
      elseif b == 0xF4 then len, lo, hi = 4, 0x80, 0x8F
      else len = 0 end
      local ok = len > 0 and (i + len - 1) <= n
      if ok then
        local c2 = s:byte(i + 1)
        if c2 < lo or c2 > hi then ok = false end
        if ok then
          for k = 2, len - 1 do
            local cb = s:byte(i + k)
            if cb < 0x80 or cb > 0xBF then ok = false; break end
          end
        end
      end
      if ok then
        out[#out + 1] = s:sub(i, i + len - 1); i = i + len
      else
        out[#out + 1] = REPLACEMENT; i = i + 1
      end
    end
  end
  return table.concat(out)
end

local function encode_string(val)
  return '"' .. scrub_utf8(val):gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function is_array(t)
  local kind = table_kind(t)
  if kind == "object" then
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

local function encode_table(val, depth, seen)
  if depth > MAX_DEPTH then
    return '"<max depth>"'
  end
  if seen[val] then
    return '"<circular>"'
  end
  seen[val] = true

  local res = {}
  local arr, max = is_array(val)
  if arr then
    for i = 1, max do
      res[#res + 1] = encode(val[i], depth + 1, seen)
    end
    seen[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  end
  local keys = {}
  for k in pairs(val) do
    local kt = type(k)
    if kt == "string" or kt == "number" then keys[#keys + 1] = k end
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
    if val ~= val or val <= -math.huge or val >= math.huge then
      return "null"
    end
    return tostring(val)
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "string" then
    return encode_string(val)
  elseif t == "table" then
    return encode_table(val, depth, seen)
  else
    return "null"
  end
end

json.encode = function(val)
  return encode(val, 0, {})
end

json.object = function(val)
  val = val or {}
  if type(val) == "table" then
    setmetatable(val, OBJECT_MT)
  end
  return val
end

json.is_array = function(val)
  return type(val) == "table" and table_kind(val) == "array"
end

json.is_object = function(val)
  return type(val) == "table" and table_kind(val) == "object"
end

local parse

local function decode_error(_str, idx, msg)
  error("json decode error at " .. tostring(idx) .. ": " .. msg)
end

-- SPECIFICATION.md:234-236: valid-JSON-but-rejected must not be reported to Neuro as invalid JSON
local function semantic_error(_str, idx, msg)
  error("json semantic rejection at " .. tostring(idx) .. ": " .. msg)
end

local function skip_whitespace(str, idx)
  local _, e = str:find("^[ \n\r\t]+", idx)
  return (e or idx - 1) + 1
end

local function parse_null(str, idx)
  if str:sub(idx, idx + 3) == "null" then
    return nil, idx + 4
  end
  decode_error(str, idx, "invalid 'null'")
end

local function parse_true(str, idx)
  if str:sub(idx, idx + 3) == "true" then
    return true, idx + 4
  end
  decode_error(str, idx, "invalid 'true'")
end

local function parse_false(str, idx)
  if str:sub(idx, idx + 4) == "false" then
    return false, idx + 5
  end
  decode_error(str, idx, "invalid 'false'")
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
    if not frac then
      decode_error(str, idx, "invalid number")
    end
    i = i + #frac
  end
  if str:sub(i, i):match("[eE]") then
    local exp = str:match("^[eE][%+%-]?%d+", i)
    if not exp then
      decode_error(str, idx, "invalid number")
    end
    i = i + #exp
  end
  local num = tonumber(str:sub(idx, i - 1))
  if not num then
    decode_error(str, idx, "invalid number")
  end
  return num, i
end

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
        if codepoint >= 0xD800 and codepoint <= 0xDBFF and str:sub(idx, idx + 1) == "\\u" then
          local hex2 = str:sub(idx + 2, idx + 5)
          local low = hex2:match("%x%x%x%x") and tonumber(hex2, 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
            idx = idx + 6
          end
        end
        if codepoint >= 0xD800 and codepoint <= 0xDFFF then
          codepoint = 0xFFFD
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
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", ["b"] = "\b",
          ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t" }
        local repl = map[esc]
        if not repl then
          decode_error(str, idx, "invalid escape char")
        end
        res[#res + 1] = repl
        idx = idx + 2
      end
    else
      res[#res + 1] = c
      idx = idx + 1
    end
  end
  decode_error(str, idx, "unterminated string")
end

local function parse_array(str, idx, depth)
  idx = idx + 1
  local res = setmetatable({}, ARRAY_MT)
  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == "]" then
    return res, idx + 1
  end
  while idx <= #str do
    local val
    val, idx = parse(str, idx, depth)
    if val == nil then
      semantic_error(str, idx, "null is valid JSON but is not accepted as an array element")
    end
    res[#res + 1] = val
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == "]" then
      return res, idx + 1
    elseif c ~= "," then
      decode_error(str, idx, "expected ',' or ']'")
    end
    idx = skip_whitespace(str, idx + 1)
  end
  decode_error(str, idx, "unterminated array")
end

local function parse_object(str, idx, depth)
  idx = idx + 1
  local res = setmetatable({}, OBJECT_MT)
  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == "}" then
    return res, idx + 1
  end
  while idx <= #str do
    if str:sub(idx, idx) ~= '"' then
      decode_error(str, idx, "expected string key")
    end
    local key
    key, idx = parse_string(str, idx)
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) ~= ":" then
      decode_error(str, idx, "expected ':'")
    end
    idx = skip_whitespace(str, idx + 1)
    local val
    val, idx = parse(str, idx, depth)
    res[key] = val
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == "}" then
      return res, idx + 1
    elseif c ~= "," then
      decode_error(str, idx, "expected ',' or '}'")
    end
    idx = skip_whitespace(str, idx + 1)
  end
  decode_error(str, idx, "unterminated object")
end

function parse(str, idx, depth)
  depth = (depth or 0) + 1
  if depth > MAX_DEPTH then
    decode_error(str, idx, "max nesting depth exceeded")
  end
  idx = skip_whitespace(str, idx or 1)
  local c = str:sub(idx, idx)
  if c == "{" then
    return parse_object(str, idx, depth)
  elseif c == "[" then
    return parse_array(str, idx, depth)
  elseif c == '"' then
    return parse_string(str, idx)
  elseif c == "n" then
    return parse_null(str, idx)
  elseif c == "t" then
    return parse_true(str, idx)
  elseif c == "f" then
    return parse_false(str, idx)
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
