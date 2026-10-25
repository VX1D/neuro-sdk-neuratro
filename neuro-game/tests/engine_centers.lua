local M = {}

local REAL

local function read(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("*a")
  fh:close()
  return s
end

local function load_real()
  local dump = os.getenv("BALATRO_DUMP")
  assert(dump and dump ~= "", "engine_centers: BALATRO_DUMP is unset; set it to the lovely dump directory")
  local game = assert(read(dump .. "/game.lua"), "engine_centers: game.lua unreadable in " .. dump)
  local body = assert(game:match("self%.P_CENTERS%s*=%s*(%b{})"), "engine_centers: P_CENTERS literal not found")
  local centers = assert((loadstring or load)("return " .. body, "@game.lua:P_CENTERS"))()
  for k, v in pairs(centers) do v.key = k end
  local smods = dump .. "/../../smods/src/game_object.lua"
  local go = assert(read(smods), "engine_centers: Steamodded source unreadable at " .. smods)
  local n = 0
  for name, rest in go:gmatch("SMODS%.Edition:take_ownership%('(%w+)',%s*(%b{})") do
    local cfg = rest:match("config%s*=%s*(setmetatable%b())")
    if cfg then
      centers["e_" .. name].config = assert((loadstring or load)("return " .. cfg, "@smods:e_" .. name))()
      n = n + 1
    end
  end
  assert(n == 4, "engine_centers: expected Steamodded's four edition configs, found " .. n)
  return centers
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return setmetatable(out, getmetatable(v))
end

function M.centers()
  REAL = REAL or load_real()
  return copy(REAL)
end

function M.with(extra)
  local out = M.centers()
  for k, v in pairs(extra or {}) do
    if out[k] then
      for f, x in pairs(v) do out[k][f] = x end
    else
      v.key = v.key or k
      out[k] = v
    end
  end
  return out
end

return M
