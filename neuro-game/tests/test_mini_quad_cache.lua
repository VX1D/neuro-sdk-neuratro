
local QUAD_COUNT = 0
local QUAD_LOGS = {}
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local function record_draw(...)
  local args = { ... }
  QUAD_LOGS[#QUAD_LOGS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4] }
end
local function new_quad(x, y, w, h)
  QUAD_COUNT = QUAD_COUNT + 1
  return { id = QUAD_COUNT, x = x, y = y, w = w, h = h }
end
local function new_img(id)
  return { id = id, getWidth = function() return 512 end, getHeight = function() return 512 end,
    getDimensions = function() return 512, 512 end }
end
local IMG_A = new_img("A")
local IMG_B = new_img("B")
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = new_quad,
  newImage = function() return IMG_A end,
  newMesh = function() return {} end,
  print = record_print,
  draw = record_draw,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("mini quad cache atlas identity")

local Cards = require("hud.cards")
local State = require("hud.state")

local function make_card(atlas_key, soul_pos, pos)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = atlas_key,
      pos = pos or { x = 1, y = 0 }, soul_pos = soul_pos, name = "CacheCard" } },
    ability = {},
    cost = 3,
  }
end

local function leaf_count(t)
  local n = 0
  for _, v in pairs(t) do
    if type(v) == "table" then
      if v.img ~= nil then n = n + 1 else n = n + leaf_count(v) end
    end
  end
  return n
end

local function cache_size()
  return leaf_count(State.quad_cache)
end

G.ASSET_ATLAS.FIX71 = { image = IMG_A, px = 71, py = 95 }
Cards.reset_mini_counters()
QUAD_COUNT = 0
QUAD_LOGS = {}

Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("first draw creates one base quad", QUAD_COUNT == 1, QUAD_COUNT)
check("draw uses the atlas image", QUAD_LOGS[1] and QUAD_LOGS[1].image == IMG_A)

Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("same key and image shares the cached quad", QUAD_COUNT == 1, QUAD_COUNT)

G.ASSET_ATLAS.FIX71.image = IMG_B
Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("image swap under same key rebuilds the quad", QUAD_COUNT == 2, QUAD_COUNT)
check("rebuilt draw uses the new image", QUAD_LOGS[#QUAD_LOGS].image == IMG_B)
Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("new image cached for repeated draws", QUAD_COUNT == 2, QUAD_COUNT)

G.ASSET_ATLAS.FIX71.px = 50
G.ASSET_ATLAS.FIX71.py = 100
Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("px/py change under same key rebuilds the quad", QUAD_COUNT == 3, QUAD_COUNT)
Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("changed geometry cached for repeated draws", QUAD_COUNT == 3, QUAD_COUNT)

G.ASSET_ATLAS.FIX71.px = 71
G.ASSET_ATLAS.FIX71.py = 95
G.ASSET_ATLAS.FIX71.image = IMG_A
Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
check("restored key reuses distinct cache slot", QUAD_COUNT == 4, QUAD_COUNT)

Cards.clear_quad_cache()
check("explicit clear empties the quad cache", cache_size() == 0, cache_size())

G.ASSET_ATLAS.FIX71 = { image = IMG_B, px = 71, py = 95 }
local q0 = QUAD_COUNT
Cards.draw_card_mini(make_card("FIX71", { x = 2, y = 1 }), 0, 0, 95, 1)
check("soul card creates base and soul quads", QUAD_COUNT == q0 + 2, QUAD_COUNT .. " vs " .. q0)
Cards.draw_card_mini(make_card("FIX71", { x = 2, y = 1 }), 0, 0, 95, 1)
check("soul quad shared on repeat draw", QUAD_COUNT == q0 + 2, QUAD_COUNT)

local soul_seen = false
if State.quad_cache.soul then
  for _ in pairs(State.quad_cache.soul) do soul_seen = true end
end
check("soul quads live under the soul namespace", soul_seen)

Cards.clear_quad_cache()
local q1 = QUAD_COUNT
Cards.draw_card_mini(make_card("FIX71", { x = 2, y = 1 }), 0, 0, 95, 1)
check("reset clears stale quads after reload", QUAD_COUNT == q1 + 2, QUAD_COUNT)
check("post-reload draw uses current image", QUAD_LOGS[#QUAD_LOGS].image == IMG_B)

local before_size = cache_size()
for i = 1, 4 do
  G.ASSET_ATLAS.FIX71.px = 60 + i
  G.ASSET_ATLAS.FIX71.py = 90 + i
  Cards.clear_quad_cache()
  Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
end
check("repeated reload with reset stays bounded", cache_size() <= before_size + 1, cache_size())

Cards.clear_quad_cache()
for i = 1, 620 do
  G.ASSET_ATLAS.FIX71.px = 10 + (i % 600)
  G.ASSET_ATLAS.FIX71.py = 20 + (i % 600)
  Cards.draw_card_mini(make_card("FIX71"), 0, 0, 95, 1)
end
check("unbounded key churn is capped", cache_size() <= 512, cache_size())
check("leaf counter matches the recursive leaf count", State.quad_cache_n == cache_size(),
  tostring(State.quad_cache_n) .. " vs " .. cache_size())

Cards.clear_quad_cache()
check("leaf counter resets with the cache", State.quad_cache_n == 0 and cache_size() == 0)

Cards.clear_quad_cache()
local SHARED = new_img("shared")
G.ASSET_ATLAS.foo = { image = SHARED, px = 71, py = 95 }
G.ASSET_ATLAS.foo_soul = { image = SHARED, px = 71, py = 95 }
QUAD_COUNT = 0
QUAD_LOGS = {}
local card_a = make_card("foo_soul", nil, { x = 2, y = 1 })
local card_b = make_card("foo", { x = 2, y = 1 }, { x = 1, y = 0 })
Cards.draw_card_mini(card_a, 0, 0, 95, 1)
Cards.draw_card_mini(card_b, 0, 0, 95, 1)
check("base foo_soul@2,1 and soul foo@2,1 get distinct quads", QUAD_COUNT == 3, QUAD_COUNT)
local q_soul = QUAD_LOGS[3].quad
local q_base = QUAD_LOGS[1].quad
check("soul quad is a distinct object from the colliding base quad", q_soul ~= q_base)
check("base quad of foo_soul keeps its own cell",
  q_base.x == 142 and q_base.y == 95 and q_base.w == 71 and q_base.h == 95,
  tostring(q_base.x) .. "," .. tostring(q_base.y) .. " " .. tostring(q_base.w) .. "x" .. tostring(q_base.h))
Cards.draw_card_mini(card_a, 0, 0, 95, 1)
Cards.draw_card_mini(card_b, 0, 0, 95, 1)
check("collision-free namespaces share each quad on repeat", QUAD_COUNT == 3, QUAD_COUNT)

done()
