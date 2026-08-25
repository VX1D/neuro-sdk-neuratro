
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local LOG = {}
local RECTS = {}
local function record_print(text)
  PRINTED[#PRINTED + 1] = tostring(text or "")
  LOG[#LOG + 1] = { kind = "print", text = tostring(text or "") }
end
local function record_draw(...)
  local args = { ... }
  LOG[#LOG + 1] = { kind = "draw", image = args[1], quad = args[2], x = args[3], y = args[4], sx = args[6], sy = args[7] }
end
local function record_rect(mode, x, y, w, h)
  RECTS[#RECTS + 1] = { mode = mode, x = x, y = y, w = w, h = h }
  LOG[#LOG + 1] = { kind = "rect", mode = mode, x = x, y = y, w = w, h = h }
end
local function record_circle(mode, x, y, r)
  LOG[#LOG + 1] = { kind = "circle", mode = mode, x = x, y = y, r = r }
end
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local STICKERS_IMG = { getWidth = function() return 142 end, getHeight = function() return 190 end,
  getDimensions = function() return 142, 190 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  print = record_print,
  draw = record_draw,
  rectangle = record_rect,
  circle = record_circle,
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

local check, done = require("tests.helpers").harness("acquire sticker passes on joker miniatures")

local Cards = require("hud.cards")

local atlas_entry = function(px, py, image) return { image = image or IMG, px = px, py = py } end
G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
G.ASSET_ATLAS.stickers = atlas_entry(71, 95, STICKERS_IMG)

local function reset_gfx()
  PRINTED, LOG, RECTS = {}, {}, {}
  Cards.reset_mini_counters()
end

local function filter_draws()
  local out = {}
  for _, item in ipairs(LOG) do
    if item.kind == "draw" then out[#out + 1] = item end
  end
  return out
end

local function joker_stickers(ability, ed, seal, debuff, soul_pos)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 }, soul_pos = soul_pos, name = "StickerJoker" } },
    ability = ability or {},
    edition = ed,
    seal = seal,
    debuff = debuff,
    cost = 4,
  }
end

reset_gfx()
Cards.draw_card_mini(joker_stickers({ eternal = true }), 0, 0, 95, 1)
local d1 = filter_draws()
check("eternal sticker renders 1 base quad + 1 sticker quad", #d1 == 2, #d1)
check("sticker quad uses stickers image", d1[2].image == STICKERS_IMG)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ perishable = true }), 0, 0, 95, 1)
local d2 = filter_draws()
check("perishable sticker renders 1 base quad + 1 sticker quad", #d2 == 2, #d2)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ rental = true }), 0, 0, 95, 1)
local d3 = filter_draws()
check("rental sticker renders 1 base quad + 1 sticker quad", #d3 == 2, #d3)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ eternal = true, perishable = true }), 0, 0, 95, 1)
local dp1 = filter_draws()
check("eternal+perishable pair renders 1 base + 2 sticker quads", #dp1 == 3, #dp1)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ eternal = true, rental = true }), 0, 0, 95, 1)
local dp2 = filter_draws()
check("eternal+rental pair renders 1 base + 2 sticker quads", #dp2 == 3, #dp2)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ perishable = true, rental = true }), 0, 0, 95, 1)
local dp3 = filter_draws()
check("perishable+rental pair renders 1 base + 2 sticker quads", #dp3 == 3, #dp3)

reset_gfx()
Cards.draw_card_mini(joker_stickers({ eternal = true, perishable = true, rental = true }), 0, 0, 95, 1)
local dall = filter_draws()
check("all 3 stickers render 1 base + 3 sticker quads", #dall == 4, #dall)

reset_gfx()
local full_combo = joker_stickers({ eternal = true }, { holo = true }, "Gold", true, { x = 1, y = 0 })
Cards.draw_card_mini(full_combo, 0, 0, 95, 1)

local layers = {}
for _, item in ipairs(LOG) do
  if item.kind == "draw" then
    if item.image == IMG then
      if item.quad and item.quad.x == 71 then
        layers[#layers + 1] = "soul"
      else
        layers[#layers + 1] = "center"
      end
    elseif item.image == STICKERS_IMG then
      layers[#layers + 1] = "sticker"
    end
  elseif item.kind == "rect" then
    layers[#layers + 1] = "edition"
  elseif item.kind == "circle" then
    layers[#layers + 1] = "seal"
  elseif item.kind == "print" and item.text == "DB" then
    layers[#layers + 1] = "debuff"
  end
end

local c_i, s_i, e_i, sl_i, st_i, db_i = 0, 0, 0, 0, 0, 0
for idx, l in ipairs(layers) do
  if l == "center" and c_i == 0 then c_i = idx end
  if l == "soul" and s_i == 0 then s_i = idx end
  if l == "edition" and e_i == 0 then e_i = idx end
  if l == "seal" and sl_i == 0 then sl_i = idx end
  if l == "sticker" and st_i == 0 then st_i = idx end
  if l == "debuff" and db_i == 0 then db_i = idx end
end

check("center layer drawn first", c_i > 0 and c_i < e_i, c_i .. " vs " .. e_i)
check("edition wash drawn after center", e_i > 0 and e_i < sl_i, e_i .. " vs " .. sl_i)
check("seal drawn after edition", sl_i > 0 and sl_i < st_i, sl_i .. " vs " .. st_i)
check("stickers drawn after seal", st_i > 0 and st_i < s_i, st_i .. " vs " .. s_i)
check("soul drawn after stickers (card.lua:4499 -> :4512)", s_i > 0 and s_i < db_i,
  s_i .. " vs " .. db_i)
check("debuff drawn on top of everything", db_i > 0 and db_i > s_i, db_i .. " vs " .. s_i)

G.ASSET_ATLAS.stickers = nil
reset_gfx()
Cards.draw_card_mini(joker_stickers({ eternal = true }), 0, 0, 95, 1)
local dmiss = filter_draws()
check("missing stickers atlas does not break base card draw", #dmiss == 1 and dmiss[1].image == IMG)
check("missing stickers atlas increments sticker fail counter", Cards._mini_sticker_fail == 1, Cards._mini_sticker_fail)

done()
