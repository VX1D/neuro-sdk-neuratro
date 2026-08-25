_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("highlight-ownership")

local function count_highlighted_assignments(line)
  local n = 0
  local i = 1
  while true do
    local s, e = line:find("%.highlighted%s*=", i)
    if not s then break end
    if line:sub(e + 1, e + 1) ~= "=" then n = n + 1 end
    i = e + 1
  end
  return n
end

local runtime_dirs = { "core", "context", "force", "facts", "handlers", "hud", "render", "util" }
local top_files = { "neuro-game.lua" }
local exempt = { ["core/game_actions.lua"] = true }
local files = {}

for _, dir in ipairs(runtime_dirs) do
  local pipe = io.popen('find "' .. dir .. '" -type f -name "*.lua" 2>/dev/null')
  if pipe then
    for path in pipe:lines() do files[#files + 1] = path end
    pipe:close()
  end
end
for _, path in ipairs(top_files) do
  local file = io.open(path, "r")
  if file then file:close(); files[#files + 1] = path end
end

local offenders = {}
for _, path in ipairs(files) do
  if not exempt[path] then
    local file = io.open(path, "r")
    if file then
      local lineno = 0
      for line in file:lines() do
        lineno = lineno + 1
        if count_highlighted_assignments(line) > 0 then
          offenders[#offenders + 1] = path .. ":" .. lineno
        end
      end
      file:close()
    end
  end
end

check("raw highlighted writes are owned exclusively by core/game_actions.lua",
  #offenders == 0, table.concat(offenders, ", "))

done()
