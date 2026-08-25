
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local DRAWS = {}
local RECTS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local function record_draw(...)
  local args = { ... }
  DRAWS[#DRAWS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4], sx = args[6], sy = args[7] }
end
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
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

local check, done = require("tests.helpers").harness("acquire unified sprite geometry")

local Cards = require("hud.cards")
local Rows = require("hud.rows")
local Shop = require("render.panels.shop")
local RightPanel = require("render.panels.right_panel")
local HudState = require("hud.state")

local atlas_entry = function(px, py) return { image = IMG, px = px, py = py } end
G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
G.ASSET_ATLAS.FIX95 = atlas_entry(95, 95)
G.ASSET_ATLAS.FIX50 = atlas_entry(50, 100)
G.ASSET_ATLAS.FIX120 = atlas_entry(120, 80)
G.ASSET_ATLAS.centers = atlas_entry(71, 95)

local function make_card(key, atlas_key)
  return {
    config = { center = { key = key or "j_fixture", set = "Joker", atlas = atlas_key or "FIX71", pos = { x = 0, y = 0 }, name = key } },
    ability = {},
    cost = 5,
  }
end


local w71, h71 = Cards.card_dimensions(make_card("j_fixture", "FIX71"), 95)
check("71x95 atlas dimensions at h=95", w71 == 71 and h71 == 95, w71 .. "x" .. h71)

local w95, h95 = Cards.card_dimensions(make_card("j_fixture", "FIX95"), 95)
check("95x95 atlas dimensions at h=95", w95 == 95 and h95 == 95, w95 .. "x" .. h95)

local w50, h50 = Cards.card_dimensions(make_card("j_fixture", "FIX50"), 100)
check("50x100 atlas dimensions at h=100", w50 == 50 and h50 == 100, w50 .. "x" .. h50)

local w120, h120 = Cards.card_dimensions(make_card("j_fixture", "FIX120"), 80)
check("120x80 atlas dimensions at h=80", w120 == 120 and h120 == 80, w120 .. "x" .. h120)

local w_half, h_half = Cards.card_dimensions(make_card("j_half", "FIX71"), 95)
check("Half Joker reduced height (h/1.7)", w_half == 71 and h_half == math.ceil(95 / 1.7), w_half .. "x" .. h_half)

local w_photo, h_photo = Cards.card_dimensions(make_card("j_photograph", "FIX71"), 95)
check("Photograph reduced height (h/1.2)", w_photo == 71 and h_photo == math.ceil(95 / 1.2), w_photo .. "x" .. h_photo)

local w_square, h_square = Cards.card_dimensions(make_card("j_square", "FIX71"), 95)
check("Square Joker 1:1 aspect ratio (w == h == 71)", w_square == 71 and h_square == 71, w_square .. "x" .. h_square)

local w_wee, h_wee = Cards.card_dimensions(make_card("j_wee", "FIX71"), 95)
check("Wee Joker scaled 0.7x in both dimensions", w_wee == math.ceil(71 * 0.7) and h_wee == math.ceil(95 * 0.7), w_wee .. "x" .. h_wee)

DRAWS = {}
local draw_w, draw_h = Cards.draw_card_mini(make_card("j_square", "FIX71"), 0, 0, 95, 1)
check("draw_card_mini for Square Joker returns dimensions width 71 and height 71", draw_w == w_square and draw_h == h_square, draw_w .. "x" .. tostring(draw_h))


local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = CLR(), CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
}

local function mock_ctx(card)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  local metrics = {
    rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
    GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
    p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
    total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
    rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
    r_text_h = 12, r_small_text_h = 10,
    c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
    card_line_h = 28, lp_card_line_h = 28, sep_h = 6, text_h = 12,
    lp_w = 300, rp_w = 300, sc_w = 400, sc_h = 200,
  }
  local data = {
    sn = "SHOP", state_name = "SHOP",
    panel_rows = { Rows.carousel({ card }, "jokers") },
    shop_rows = { Rows.shopcard(CLR(), "Joker", card, 3, true) },
    pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
      cards = { { card = card, name = "Joker", desc = "", rc = CLR(), index = 1, badges = {} } } },
    showcase_card = card, showcase_name = "Joker", showcase_label = "Joker", showcase_desc = "desc", showcase_alpha = 1, showcase_slide = 0,
  }
  local draw = {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = noop,
    draw_desc_lines = noop, print_colored_desc = noop,
    row_h = function() return 16 end,
    showcase_type_colors = function() return CLR(), CLR() end,
    title_h = 24,
  }
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = metrics,
    data = data,
    draw = draw,
    center_top_y = 8,
  }
end


local jokers_list = { "j_half", "j_photograph", "j_square", "j_wee" }
local atlases_list = { "FIX71", "FIX95", "FIX50", "FIX120" }

for _, jk in ipairs(jokers_list) do
  for _, ak in ipairs(atlases_list) do
    local card = make_card(jk, ak)
    local tag = jk .. "@" .. ak
    local ctx = mock_ctx(card)

    RECTS, DRAWS = {}, {}
    G.shop_jokers = area({ card })
    local ok_sh, err_sh = xpcall(function() Shop.draw(ctx) end, debug.traceback)
    check("shop panel renders " .. tag .. " without error", ok_sh, err_sh)
    local sh_w, sh_h = Cards.card_dimensions(card, 24)
    local found_sh_rect = false
    for _, r in ipairs(RECTS) do
      if r.w == sh_w + 2 and r.h == sh_h + 2 then found_sh_rect = true end
    end
    check("shop panel outline rect matches geom w and h for " .. tag, found_sh_rect)

    G.jokers = area({ card })
    RECTS, DRAWS = {}, {}
    HudState.desc_slot = 1
    HudState.desc_cache_n = 0
    local ok_rp, err_rp = xpcall(function() RightPanel.rows(ctx) end, debug.traceback)
    check("right panel renders " .. tag .. " without error", ok_rp, err_rp)
    local rp_w, rp_h = Cards.card_dimensions(card, 24)
    local found_rp_rect = false
    for _, r in ipairs(RECTS) do
      if r.w == rp_w + 2 and r.h == rp_h + 2 then found_rp_rect = true end
    end
    check("right panel outline rect matches geom w and h for " .. tag, found_rp_rect)

  end
end

done()
