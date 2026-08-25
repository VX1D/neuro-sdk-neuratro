
_G.NEURO_TEST = true

local function noop() end
local function px_font(px)
  return {
    getWidth = function(_, s) return math.floor(0.5 * px * #tostring(s or "") + 0.5) end,
    getHeight = function() return math.floor(1.3 * px + 0.5) end,
  }
end
local FONT = px_font(24)
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getScissor = function() return nil end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end },
  mouse = { getPosition = function() return -1, -1 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = { persona = "neuro" }, FUNCS = {}, TIMERS = { REAL = 0 },
  GAME = { dollars = 10, current_round = { reroll_cost = 5 } },
  STATES = {}, SETTINGS = { paused = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("buy beat polarity")

local H = require("render.hud_shared")
local S = H.S
local Showcase = require("hud.showcase")
local Dev = require("hud.dev_scenario")

local SAMPLES = { 0.02, 0.10, 0.17, 0.25, 0.33, 0.42, 0.49 }

local function peak_beat(area)
  S.buy_showcase = area and { started = 0, area = area, name = "Blueprint", cost = 8,
                              code = "INSUFFICIENT_FUNDS" } or nil
  local pop, flare = 0, 0
  for _, t in ipairs(SAMPLES) do
    pop = math.max(pop, H.buy_pop01(t))
    flare = math.max(flare, H.buy_flare01(t))
  end
  return pop, flare
end

local ACQUISITIONS, NON_EVENTS = {}, {}
for _, v in ipairs(Dev.ACQUIRE_VARIANTS) do
  local seen = ACQUISITIONS[v.area] or NON_EVENTS[v.area]
  if not seen then
    if v.area == "refused" or v.area == "lost" then NON_EVENTS[v.area] = true
    else ACQUISITIONS[v.area] = true end
  end
end
NON_EVENTS.refused, NON_EVENTS.lost = true, true

do
  local pop, flare = peak_beat(nil)
  check(string.format("control: no receipt, no beat (pop %.2f flare %.2f)", pop, flare),
    pop == 0 and flare == 0)
end

for area in pairs(NON_EVENTS) do
  local pop, flare = peak_beat(area)
  check(string.format("a '%s' receipt fires no celebration (pop %.2f flare %.2f)",
    area, pop, flare), pop == 0 and flare == 0)
end

for area in pairs(ACQUISITIONS) do
  local pop, flare = peak_beat(area)
  check(string.format("a '%s' receipt still gets its beat (pop %.2f flare %.2f)",
    area, pop, flare), pop > 0.9 and flare > 0.9)
end

do
  local sc = { started = 0, area = "refused", name = "Blueprint", cost = 8,
               code = "INSUFFICIENT_FUNDS" }
  check("a refusal still fades its receipt panel in", Showcase.buy_alpha(sc, 0.20) > 0.5)
  check("and the queue still accepts it as a receipt",
    Showcase.money_direction("refused") == "none")
end

do
  local shared = io.open("render/hud_shared.lua", "r"):read("a")
  check("the discrimination lives in the shared helper",
    shared:find("NOT_AN_ACQUISITION", 1, true) ~= nil)
  local pop_body = shared:match("local function buy_pop01.-\nend")
  local flare_body = shared:match("local function buy_flare01.-\nend")
  check("buy_pop01 does not read `started` off the showcase itself",
    pop_body ~= nil and pop_body:find("buy_showcase", 1, true) == nil, tostring(pop_body))
  check("buy_flare01 does not either",
    flare_body ~= nil and flare_body:find("buy_showcase", 1, true) == nil, tostring(flare_body))
  for _, path in ipairs({ "render/panels/right_panel.lua", "render/panels/shop.lua" }) do
    local src = io.open(path, "r"):read("a")
    check(path .. " takes the beat from the shared helper, not from its own timer",
      src:find("buy_pop01", 1, true) ~= nil or src:find("buy_flare01", 1, true) ~= nil)
    check(path .. " does not compute a celebration window of its own",
      src:find("buy_showcase.started", 1, true) == nil)
  end
end

S.buy_showcase = nil
done()
