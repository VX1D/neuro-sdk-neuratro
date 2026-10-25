-- Internal `name` fields are not display text; localize `name_text` instead.
local M = {}

local PREFIXES = { "tag_", "stake_", "bl_", "j_", "v_", "c_", "b_", "p_", "m_", "e_" }

function M.humanize_key(key)
  local s = tostring(key or "")
  for _, prefix in ipairs(PREFIXES) do
    if s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1); break end
  end
  s = s:gsub("_", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end)
  return s ~= "" and s or "Unknown"
end

local function text(value)
  if type(value) == "table" then value = table.concat(value, " ") end
  if type(value) ~= "string" then return nil end
  value = value:gsub("{.-}", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function key_shaped(value)
  return type(value) == "string" and value:find("_") ~= nil and not value:find(" ")
end

local function localized(set, key)
  if type(set) ~= "string" or type(key) ~= "string" then return nil end
  local loc = rawget(_G, "localize")
  if type(loc) ~= "function" then return nil end
  local ok, out = pcall(loc, { type = "name_text", set = set, key = key })
  out = ok and text(out) or nil
  if out == nil or out == "ERROR" then return nil end
  return out
end

function M.of(set, key, proto)
  local nm = localized(set, key)
  if nm then return nm end
  if type(proto) == "table" then
    local lt = proto.loc_txt
    nm = type(lt) == "table" and text(lt.name) or nil
    if nm then return nm end
    nm = text(proto.name)
    if nm and nm ~= key and not key_shaped(nm) then return nm end
  end
  return M.humanize_key(key)
end

local function defs(field, key)
  local t = G and G[field]
  return type(t) == "table" and type(key) == "string" and t[key] or nil
end

function M.center(key, set_hint)
  if type(key) ~= "string" then return nil end
  local proto = defs("P_CENTERS", key)
  local set = type(proto) == "table" and proto.set or set_hint
  if set == "Booster" then
    return localized("Other", key) or M.of("Other", (key:gsub("_%d+$", "")), proto)
  end
  return M.of(set, key, proto)
end

function M.tag(key)
  if type(key) ~= "string" then return nil end
  return M.of("Tag", key, defs("P_TAGS", key))
end

function M.blind(key)
  if type(key) ~= "string" then return nil end
  return M.of("Blind", key, defs("P_BLINDS", key))
end

function M.seal(key)
  if type(key) ~= "string" or key == "" then return nil end
  local loc_key = key:lower() .. "_seal"
  return localized("Other", loc_key) or M.of("Other", loc_key, defs("P_SEALS", key))
end

function M.challenge(ch)
  if type(ch) ~= "table" then return nil end
  local loc = rawget(_G, "localize")
  if type(loc) == "function" and type(ch.id) == "string" then
    local ok, out = pcall(loc, ch.id, "challenge_names")
    out = ok and text(out) or nil
    if out and out ~= "ERROR" then return out end
  end
  return text(ch.name) or (type(ch.id) == "string" and M.humanize_key(ch.id)) or nil
end

function M.live_blind(blind)
  if type(blind) ~= "table" then return nil end
  local def = blind.config and blind.config.blind
  local key = (type(def) == "table" and def.key) or blind.key
  if type(key) == "string" then
    return M.of("Blind", key, defs("P_BLINDS", key) or { name = blind.name })
  end
  return text(blind.name)
end

return M
