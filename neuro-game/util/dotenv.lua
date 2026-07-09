local M = {}
local _cache = nil

local function find_mod_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  local dir = source:match("(.+)[/\\]") or "."
  if dir:match("[/\\]util$") then
    dir = dir:gsub("[/\\]util$", "")
  elseif dir == "util" then
    dir = "."
  end
  if dir == "" then dir = "." end
  return dir
end

local function parse_env_file(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local vars = {}
  for line in f:lines() do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, val = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if key and val then
        local dquoted = val:match('^"(.*)"%s*$') or val:match('^"(.*)"%s*#')
        local squoted = not dquoted and (val:match("^'(.*)'%s*$") or val:match("^'(.*)'%s*#"))
        if dquoted then
          val = dquoted:gsub('\\"', '"')
        elseif squoted then
          val = squoted
        else
          val = val:gsub("%s+#.*$", "")
          val = val:match("^%s*(.-)%s*$") or val
        end
        vars[key] = val
      end
    end
  end
  f:close()
  return vars
end

local function load_env()
  if _cache then return _cache end
  local dir = find_mod_dir()
  _cache = parse_env_file(dir .. "/.env")
  return _cache
end

function M.get(key, default)
  local os_val = os.getenv(key)
  if os_val and os_val ~= "" then return os_val end
  local env = load_env()
  local val = env[key]
  if val ~= nil then return val end
  return default
end

function M.num(key, default)
  local val = M.get(key)
  return tonumber(val or "") or default
end

function M.dir()
  return find_mod_dir()
end

function M.normalize_persona(raw)
  if type(raw) == "string" then
    local s = raw:lower():gsub("[^a-z0-9]", "")
    if s == "evil" or s == "evilneuro" then return "evil", true end
    if s == "neuro" or s == "neurosama" then return "neuro", true end
  end
  return "neuro", false
end

function M.bool(key, default)
  local v = M.get(key)
  if v == nil then return default end
  v = tostring(v):lower():gsub("%s+", "")
  if v == "1" or v == "true" or v == "yes" or v == "y" or v == "on" then return true end
  if v == "0" or v == "false" or v == "no" or v == "n" or v == "off" or v == "" then return false end
  return default
end

M.parse_file = parse_env_file

return M
