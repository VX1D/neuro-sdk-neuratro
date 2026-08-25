

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local DRAWS, RECTS = {}, {}
local function record_draw(...)
  local a = { ... }
  DRAWS[#DRAWS + 1] = { image = a[1], quad = a[2], x = a[3], y = a[4], sx = a[6], sy = a[7] }
end
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
local IMG = { getWidth = function() return 512 end, getHeight = function() return 512 end,
  getDimensions = function() return 512, 512 end }
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
  draw = record_draw,
  rectangle = record_rect,
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
  GAME = { dollars = 20, round = 1, blind = {}, used_vouchers = {}, modifiers = {},
    round_resets = { ante = 1, blind_choices = {} } },
  jokers = area(), consumeables = area(), hand = area(),
  shop_jokers = area(), shop_vouchers = area(), shop_booster = area(),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1, colourblind_option = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local function atlas_entry(px, py)
  return { image = IMG, px = px, py = py, name = "atlas" }
end
G.ASSET_ATLAS.FIX71  = atlas_entry(71, 95)
G.ASSET_ATLAS.FIX95  = atlas_entry(95, 95)
G.ASSET_ATLAS.FIX50  = atlas_entry(50, 100)
G.ASSET_ATLAS.FIX120 = atlas_entry(120, 80)
G.ASSET_ATLAS.centers  = atlas_entry(71, 95)
G.ASSET_ATLAS.stickers = atlas_entry(71, 95)

local check, done = require("tests.helpers").harness("card proportions")
local Cards = require("hud.cards")

local function make_card(key, atlas_key, opts)
  opts = opts or {}
  return {
    config = { center = { key = key, set = "Joker", atlas = atlas_key or "FIX71",
      pos = { x = 0, y = 0 }, name = key } },
    ability = opts.ability or {},
    edition = opts.edition,
    seal = opts.seal,
    cost = 5,
  }
end

local SPECIAL = { "j_half", "j_photograph", "j_square", "j_wee" }
local ALL = { "j_half", "j_photograph", "j_square", "j_wee", "j_fixture" }
local ATLASES = { "FIX71", "FIX95", "FIX50", "FIX120" }

local function near(a, b, tol) return math.abs(a - b) <= (tol or 1) end

for _, key in ipairs(SPECIAL) do
  local w, h = Cards.card_dimensions(make_card(key, "FIX71"), 95)
  local plain_w, plain_h = Cards.card_dimensions(make_card("j_fixture", "FIX71"), 95)
  check(key .. " renders smaller than an ordinary joker on the shipping cell",
    (w < plain_w) or (h < plain_h),
    string.format("%dx%d vs %dx%d", w, h, plain_w, plain_h))
end

for _, key in ipairs(SPECIAL) do
  for _, ak in ipairs(ATLASES) do
    local w, h = Cards.card_dimensions(make_card(key, ak), 95)
    check(key .. " @" .. ak .. " still has positive extents", w > 0 and h > 0,
      string.format("%dx%d", w, h))
  end
end

do
  local _, h = Cards.card_dimensions(make_card("j_square", "FIX120"), 95)
  check("j_square on a wide cell is documented as growing, not shrinking", h > 95, h)
end

do
  local w, h = Cards.card_dimensions(make_card("j_fixture", "FIX71"), 95)
  check("an ordinary joker is not reduced at all", w == 71 and h == 95,
    string.format("%dx%d", w, h))
end

for _, key in ipairs(ALL) do
  for _, ak in ipairs(ATLASES) do
    local w1, h1 = Cards.card_dimensions(make_card(key, ak), 100)
    local w2, h2 = Cards.card_dimensions(make_card(key, ak), 200)
    check(key .. " @" .. ak .. " scales its height proportionally",
      near(h2, h1 * 2, 2), string.format("h(100)=%d h(200)=%d", h1, h2))
    check(key .. " @" .. ak .. " scales its width proportionally",
      near(w2, w1 * 2, 2), string.format("w(100)=%d w(200)=%d", w1, w2))
  end
end

for _, key in ipairs(ALL) do
  for _, ak in ipairs(ATLASES) do
    local card = make_card(key, ak)
    local w, h = Cards.card_dimensions(card, 95)
    for i = #DRAWS, 1, -1 do DRAWS[i] = nil end
    local dw, dh = Cards.draw_card_mini(card, 0, 0, 95, 1)
    check(key .. " @" .. ak .. " draws at the size it reports",
      dw and dh and near(dw, w) and near(dh, h),
      string.format("drew %sx%s, reports %dx%d", tostring(dw), tostring(dh), w, h))
  end
end

for _, key in ipairs(ALL) do
  local card = make_card(key, "FIX71", { seal = "Gold" })
  local _, _, scale_x, scale_y = Cards.card_dimensions(card, 95)
  for i = #DRAWS, 1, -1 do DRAWS[i] = nil end
  Cards.draw_card_mini(card, 0, 0, 95, 1)

  local matched, seen = false, {}
  for _, dr in ipairs(DRAWS) do
    if dr.sx and dr.sy then
      seen[#seen + 1] = string.format("%.3f/%.3f", dr.sx, dr.sy)
      if near(dr.sx, scale_x, 0.01) and near(dr.sy, scale_y, 0.01) then matched = true end
    end
  end
  check("a sealed " .. key .. " draws something at the card's own scale", matched,
    string.format("card scale %.3f/%.3f, saw %s", scale_x, scale_y,
      #seen > 0 and table.concat(seen, " ") or "nothing"))
end

for _, key in ipairs(ALL) do
  local card = make_card(key, "FIX71",
    { ability = { eternal = true, perishable = true, rental = true } })
  local _, _, _, scale_y = Cards.card_dimensions(card, 95)
  for i = #DRAWS, 1, -1 do DRAWS[i] = nil end
  Cards.draw_card_mini(card, 0, 0, 95, 1)

  local over = 0
  for _, dr in ipairs(DRAWS) do
    if dr.sy and dr.sy > scale_y * 1.05 then over = over + 1 end
  end
  check("stickers on " .. key .. " are not scaled past the card", over == 0, over .. " oversized")
end

for _, key in ipairs(ALL) do
  for _, ed in ipairs({ "negative", "polychrome", "holo", "foil" }) do
    local card = make_card(key, "FIX71", { edition = { [ed] = true } })
    local _, render_h = Cards.card_dimensions(card, 95)
    for i = #RECTS, 1, -1 do RECTS[i] = nil end
    Cards.draw_card_mini(card, 0, 0, 95, 1)

    local too_tall = 0
    for _, r in ipairs(RECTS) do
      if r.x == 0 and r.y == 0 and r.h and r.h > render_h + 1 then too_tall = too_tall + 1 end
    end
    check(ed .. " fallback on " .. key .. " does not overhang the art", too_tall == 0,
      too_tall .. " rect(s) taller than " .. render_h)
  end
end

do
  local card = make_card("j_half", "FIX71")
  local function alpha_of_draws()
    local n = 0
    for _, _ in ipairs(DRAWS) do n = n + 1 end
    return n
  end
  local _, _, scale_x, scale_y = Cards.card_dimensions(card, 95)
  for i = #DRAWS, 1, -1 do DRAWS[i] = nil end
  Cards.draw_sprite_shaded("FIX71", { x = 0, y = 0 }, 0, 0, scale_x, scale_y, 1, 0.0)
  local n_none = alpha_of_draws()
  for i = #DRAWS, 1, -1 do DRAWS[i] = nil end
  Cards.draw_sprite_shaded("FIX71", { x = 0, y = 0 }, 0, 0, scale_x, scale_y, 1, 0.9)
  local n_deep = alpha_of_draws()
  check("the shaderless dissolve fallback still draws the card", n_none > 0 and n_deep > 0,
    n_none .. " / " .. n_deep)
end

for _, key in ipairs(SPECIAL) do
  local card = make_card(key, "FIX71")
  local NOMINAL = 110
  local _, once = Cards.card_dimensions(card, NOMINAL)
  local _, twice = Cards.card_dimensions(card, once)

  check(key .. " shrinks again when its own reduced height is fed back in", twice < once,
    string.format("once=%d twice=%d", once, twice))

  local _, probe_h = Cards.card_dimensions(card, 1000)
  local ratio = probe_h / 1000
  check(key .. " has a usable reduction ratio", ratio > 0 and ratio <= 1, string.format("%.4f", ratio))
  check(key .. " ratio probe recovers the nominal from the reduced height",
    near(once / ratio, NOMINAL, 2), string.format("%.1f vs %d", once / ratio, NOMINAL))
end

do
  local card = make_card("j_fixture", "FIX71")
  local _, once = Cards.card_dimensions(card, 110)
  local _, twice = Cards.card_dimensions(card, once)
  check("an ordinary joker is unaffected either way", once == twice, once .. " / " .. twice)
end

done()
