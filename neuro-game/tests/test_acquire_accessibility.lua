
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local CIRCLES = {}
local ELLIPSES = {}
local COLORS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local function record_rect(mode, x, y, w, h)
  RECTS[#RECTS + 1] = { mode = mode, x = x, y = y, w = w, h = h, col = COLORS[#COLORS] }
end
local function record_ellipse(mode, x, y, rx, ry)
  ELLIPSES[#ELLIPSES + 1] = { mode = mode, x = x, y = y, rx = rx, ry = ry }
end
local function record_circle(mode, x, y, r)
  CIRCLES[#CIRCLES + 1] = { mode = mode, x = x, y = y, r = r, col = COLORS[#COLORS] }
end
local function record_color(r, g, b, a)
  COLORS[#COLORS + 1] = { r = r, g = g, b = b, a = a }
end
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  print = record_print,
  rectangle = record_rect,
  circle = record_circle,
  ellipse = record_ellipse,
  setColor = record_color,
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
  GAME = { dollars = 10, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
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

local check, done = require("tests.helpers").harness("acquire color-independent signals")

local Cards = require("hud.cards")
local Shop = require("render.panels.shop")
local Rows = require("hud.rows")

local atlas_entry = function(px, py) return { image = IMG, px = px, py = py } end
G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
G.ASSET_ATLAS.centers = atlas_entry(71, 95)

local function seal_card(seal)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 }, name = "Sealed" } },
    ability = {},
    seal = seal,
    cost = 5,
  }
end

local glyphs = Cards.seal_glyphs
check("seal glyph table defines all four seal types",
  glyphs.Red ~= nil and glyphs.Blue ~= nil and glyphs.Gold ~= nil and glyphs.Purple ~= nil)
local seen = {}
local glyph_ok = true
for _, g in pairs(glyphs) do
  if type(g) ~= "string" or g == "" then glyph_ok = false end
  if seen[g] then glyph_ok = false end
  seen[g] = true
end
check("seal glyphs are non-empty and pairwise distinct", glyph_ok)

local Badges = require("render.modifier_badges")
for _, seal in ipairs({ "Red", "Blue", "Gold", "Purple" }) do
  local named = false
  for _, b in ipairs(Badges.collect(seal_card(seal))) do
    if b.kind == "seal" and tostring(b.text):find(seal, 1, true) then named = true end
  end
  check("seal " .. seal .. " is named in text by the badge row", named)

  local keep = G.ASSET_ATLAS.centers
  G.ASSET_ATLAS.centers = nil
  PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
  Cards.draw_card_mini(seal_card(seal), 0, 0, 110, 1)
  G.ASSET_ATLAS.centers = keep
  local text = table.concat(PRINTED, "")
  check("seal " .. seal .. " falls back to a glyph when the atlas is gone",
    text:find(glyphs[seal], 1, true) ~= nil, glyphs[seal])
  local dot = false
  for _, c in ipairs(CIRCLES) do
    if c.mode == "fill" and c.r >= 6 then dot = true end
  end
  check("seal " .. seal .. " fallback keeps the colored dot", dot)
end

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = CLR(), CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  boss = false, is_round_eval = false,
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local METRICS = {
  rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 960, sh = 540, U = 6,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
  total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10,
  c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
  rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
}
local function shop_ctx(evil, neuro, rows)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = METRICS,
    data = {
      sn = "SHOP", state_name = "SHOP",
      shop_rows = rows,
      panel_rows = {},
    },
    draw = {
      trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end,
    },
    center_top_y = 8,
  }
end

local cheap_card = {
  config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 }, name = "Cheap" } },
  ability = {}, cost = 2,
}
local pricey_card = {
  config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 }, name = "Pricey" } },
  ability = { eternal = true }, cost = 99,
}

local function lock_circles()
  local n = 0
  for _, c in ipairs(CIRCLES) do
    if c.mode == "line" and c.r > 1 and c.r < 3 then n = n + 1 end
  end
  return n
end

local function lock_body_rects()
  local n = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w > 4 and r.w < 8 and r.h > 2 and r.h < 4 then n = n + 1 end
  end
  return n
end

local personas = {
  { label = "evil", evil = true, neuro = false },
  { label = "neuro", evil = false, neuro = true },
}

local ShopState = require("hud.state")
local function reset_shop_state()
  ShopState.shop_last_visible, ShopState.shop_h_current = false, nil
  ShopState.shop_x_current, ShopState.shop_y_current = nil, nil
  ShopState.lp_compact = false
end

for _, p in ipairs(personas) do
  local rows = {
    Rows.shopcard(CLR(), "Cheap", cheap_card, 2, true, nil, {}),
    Rows.shopcard(CLR(), "Pricey", pricey_card, 99, false, nil, {}),
  }
  reset_shop_state()
  PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
  local ok, err = xpcall(function() Shop.draw(shop_ctx(p.evil, p.neuro, rows)) end, debug.traceback)
  check("shop draw-exec " .. p.label .. " with unaffordable row executes", ok, err)
  local text = table.concat(PRINTED, "")
  check("shop " .. p.label .. " prints both prices", text:find("$2", 1, true) ~= nil and text:find("$99", 1, true) ~= nil)
  check("shop " .. p.label .. " prints both names", text:find("Cheap", 1, true) ~= nil and text:find("Pricey", 1, true) ~= nil)
  check("shop " .. p.label .. " draws one lock for the unaffordable row", lock_circles() == 1 and lock_body_rects() == 1,
    lock_circles() .. "/" .. lock_body_rects())
  local neutral = false
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w > 4 and r.w < 8 and r.h > 2 and r.h < 4 and r.col then
      local d1 = math.abs(r.col.r - r.col.g)
      local d2 = math.abs(r.col.g - r.col.b)
      if d1 < 0.02 and d2 < 0.02 then neutral = true end
    end
  end
  check("shop " .. p.label .. " lock keyway uses neutral color", neutral)

  local only_afford = {
    Rows.shopcard(CLR(), "Cheap", cheap_card, 2, true, nil, {}),
  }
  reset_shop_state()
  PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
  local ok2, err2 = xpcall(function() Shop.draw(shop_ctx(p.evil, p.neuro, only_afford)) end, debug.traceback)
  check("shop draw-exec " .. p.label .. " affordable only executes", ok2, err2)
  check("shop " .. p.label .. " affordable row has no lock", lock_circles() == 0 and lock_body_rects() == 0,
    lock_circles() .. "/" .. lock_body_rects())
end

local STICKER_EXPECT = {
  { flag = "eternal",    col = { 0.78, 0.35, 0.52 } },
  { flag = "perishable", col = { 0.31, 0.36, 0.63 } },
  { flag = "rental",     col = { 0.69, 0.56, 0.26 } },
}
local function sticker_card(flag)
  return { config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker", [flag] = true } }
end
local function color_used(c)
  for _, col in ipairs(COLORS) do
    if math.abs((col.r or 0) - c[1]) < 0.01 and math.abs((col.g or 0) - c[2]) < 0.01
      and math.abs((col.b or 0) - c[3]) < 0.01 then return true end
  end
  return false
end
for _, sc in ipairs(STICKER_EXPECT) do
  G.C[sc.flag:upper()] = { sc.col[1], sc.col[2], sc.col[3], 1 }
end
for _, sc in ipairs(STICKER_EXPECT) do
  local layout = Badges.layout(Badges.collect(sticker_card(sc.flag)), FONT, 200, 1, 3)
  check("sticker " .. sc.flag .. " produces one badge", #layout.items == 1, #layout.items)
  PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
  Badges.draw(layout, 0, 0, 1, THEME)
  check("sticker " .. sc.flag .. " draws in its own tint", color_used(sc.col))
  for _, other in ipairs(STICKER_EXPECT) do
    if other.flag ~= sc.flag then
      check("sticker " .. sc.flag .. " does not borrow the " .. other.flag .. " tint",
        not color_used(other.col))
    end
  end
end

do
  local keep = G.C
  G.C = {}
  local layout = Badges.layout(Badges.collect(sticker_card("rental")), FONT, 200, 1, 3)
  PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
  Badges.draw(layout, 0, 0, 1, THEME)
  G.C = keep
  check("sticker fallback keeps the vanilla tint", color_used({ 0.69, 0.56, 0.26 }))
end

local Acquire = require("render.panels.acquire")
local HudState = require("hud.state")

local fixture_card = {
  config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71",
    pos = { x = 0, y = 0 }, name = "Fixture" } },
  ability = {}, cost = 5,
}
local function acquire_ctx(evil)
  local ctx = shop_ctx(evil, false, {})
  ctx.theme.pk = evil and "evil" or "hiyori"
  ctx.data.pack_rows = {}
  ctx.center_cx, ctx.center_max_w = 480, 640
  return ctx
end
local WINE = { 0.45, 0.09, 0.13 }
local WAX = { 0.34, 0.035, 0.065 }

for _, surface in ipairs({
  { label = "receipt", evil_mark = WINE, arm = function()
      HudState.joker_showcase = nil
      HudState.buy_showcase = { card = fixture_card, name = "Fixture",
        area = "shop", cost = 5, started = 0.4 }
    end },
  { label = "full showcase", evil_mark = WAX, arm = function()
      HudState.buy_showcase = nil
      HudState.joker_showcase = { card = fixture_card, label = "NEW JOKER", started = 0.4 }
    end },
}) do
  surface.arm()
  PRINTED, CIRCLES, RECTS, COLORS, ELLIPSES = {}, {}, {}, {}, {}
  local ok, err = xpcall(function() Acquire.draw(acquire_ctx(true)) end, debug.traceback)
  check("evil deco " .. surface.label .. " executes", ok, err)
  check("evil deco " .. surface.label .. " draws no glow ellipses", #ELLIPSES == 0, #ELLIPSES)
  check("evil deco " .. surface.label .. " stamps its evil mark",
    color_used(surface.evil_mark))
  local evil_ops = #RECTS

  surface.arm()
  PRINTED, CIRCLES, RECTS, COLORS, ELLIPSES = {}, {}, {}, {}, {}
  local ok_h, err_h = xpcall(function() Acquire.draw(acquire_ctx(false)) end, debug.traceback)
  check("hiyori neutral " .. surface.label .. " executes", ok_h, err_h)
  check("hiyori neutral " .. surface.label .. " keeps the neutral spine",
    not color_used(WINE) and not color_used(WAX))
  check("evil deco " .. surface.label .. " is materially richer than neutral",
    evil_ops > #RECTS, evil_ops .. " vs " .. #RECTS)
  HudState.buy_showcase, HudState.joker_showcase = nil, nil
end

do
  local Prims = require("hud.prims")
  local function snap(pulse)
    PRINTED, CIRCLES, RECTS, COLORS = {}, {}, {}, {}
    Prims.wax_seal(40, 40, 9, 1, { 0.9, 0.675, 0.275 }, 1, pulse, true)
    local out = {}
    for _, r in ipairs(RECTS) do
      out[#out + 1] = string.format("%s:%.2f,%.2f,%.2f,%.2f", r.mode, r.x, r.y, r.w, r.h)
    end
    return table.concat(out, ";"), #RECTS
  end
  local lo = snap(0.1)
  local hi, n = snap(0.9)
  check("the wax seal drip wobble follows pulse", lo ~= hi)
  check("the seal and its drip are drawn either way", n > 20, n)
end

done()
