local json = { _version = "0.1.3" }

local encode

local MAX_DEPTH = 50

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

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function is_array(t)
  local max = 0
  local count = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    if k < 1 or k ~= math.floor(k) then
      return false
    end
    if k > max then
      max = k
    end
    count = count + 1
  end
  if count == 0 then
    return false
  end
  if max > count * 2 then
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
  for k, v in pairs(val) do
    if type(k) == "string" then
      res[#res + 1] = encode_string(k) .. ":" .. encode(v, depth + 1, seen)
    end
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

local parse

local function decode_error(str, idx, msg)
  error("json decode error at " .. tostring(idx) .. ": " .. msg)
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
  local num_str = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", idx)
  if not num_str or #num_str == 0 then
    decode_error(str, idx, "invalid number")
  end
  local num = tonumber(num_str)
  if not num then
    decode_error(str, idx, "invalid number")
  end
  return num, idx + #num_str
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
        if not codepoint then
          decode_error(str, idx, "invalid unicode escape value")
        end
        if codepoint < 0x80 then
          res[#res + 1] = string.char(codepoint)
        elseif codepoint < 0x800 then
          res[#res + 1] = string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + (codepoint % 0x40))
        else
          res[#res + 1] = string.char(0xE0 + math.floor(codepoint / 0x1000), 0x80 + math.floor((codepoint % 0x1000) / 0x40), 0x80 + (codepoint % 0x40))
        end
        idx = idx + 6
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

local function parse_array(str, idx)
  idx = idx + 1
  local res = {}
  idx = skip_whitespace(str, idx)
  if str:sub(idx, idx) == "]" then
    return res, idx + 1
  end
  while idx <= #str do
    local val
    val, idx = parse(str, idx)
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

local function parse_object(str, idx)
  idx = idx + 1
  local res = {}
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
    val, idx = parse(str, idx)
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

function parse(str, idx)
  idx = skip_whitespace(str, idx or 1)
  local c = str:sub(idx, idx)
  if c == "{" then
    return parse_object(str, idx)
  elseif c == "[" then
    return parse_array(str, idx)
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
