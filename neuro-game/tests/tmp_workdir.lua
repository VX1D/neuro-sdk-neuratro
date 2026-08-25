local M = {}

local opened = {}

local function token()
  local name = os.tmpname()
  os.remove(name)
  return (name:gsub(".*/", ""):gsub("[^%w_]", "_"))
end

function M.open(label)
  local base = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  local dir = base .. "/" .. tostring(label) .. "." .. token()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  opened[#opened + 1] = dir
  return dir
end

function M.close()
  for _, dir in ipairs(opened) do os.execute("rm -rf '" .. dir .. "'") end
  opened = {}
end

return M
