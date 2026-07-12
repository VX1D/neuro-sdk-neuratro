package.path = "./?.lua;;" .. package.path

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local gfx = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
}, { __index = function() return function() return nil end end })

_G.G = { NEURO = {}, TIMERS = { REAL = 0 }, C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }
love = setmetatable({
  graphics = gfx,
  timer = { getTime = function() return G.TIMERS.REAL end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.SMODS = { current_mod = { path = "./" }, Mods = {} }

local NeuroAnim = require("render.neuro-anim")

local function col() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({ ACCENT = col(), D_WHITE = col(), D_DIM = col(), NAME = "Neuro-sama" },
  { __index = function() return col() end })
local LINES = {
  { text = "bios check ....", status = "OK", accent = nil, thr = 0.06 },
  { text = "heart ....", status = "FOUND", accent = true, thr = 0.60 },
  { text = "uplink ....", status = "ESTABLISHED", accent = nil, thr = 0.70 },
}

local fails = 0
local phases = { 0.10, 1.00, 2.20, 2.60, 3.50, 4.40 }
for _, t in ipairs(phases) do
  G.NEURO.login_anim = {
    start = 0, name = "Neuro-sama",
    cached_pal = PAL, cached_lines = LINES, name_str = "NEURO-SAMA",
  }
  G.TIMERS.REAL = t
  local ok, err = xpcall(NeuroAnim.draw_login_anim, debug.traceback)
  if not ok then
    fails = fails + 1
    print(string.format("FAIL login draw at t=%.2f: %s", t, tostring(err)))
  end
end

G.NEURO.persona = "evil"
G.NEURO.login_anim = { start = 0, name = "Evil Neuro" }
G.TIMERS.REAL = 2.20
local ok2, err2 = xpcall(NeuroAnim.draw_login_anim, debug.traceback)
if not ok2 then
  fails = fails + 1
  print("FAIL login draw (uncached entry): " .. tostring(err2))
end

print(string.format("==== login-anim: %d phase draws, %d FAIL ====", #phases + 1, fails))
print("LOGIN_ANIM_FAILS=" .. fails .. " (0 = clean)")
os.exit(fails == 0 and 0 or 1)
