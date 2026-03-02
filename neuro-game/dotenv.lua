-- dotenv.lua — lightweight .env file reader for Neuro mod
-- Priority: OS env var > .env file value > hardcoded default

local M = {}
local _cache = nil

local function find_mod_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  local dir = source:match("(.+)[/\\]") or "."
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
        val = val:match('^"(.*)"$') or val:match("^'(.*)'$") or val
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

return M
