_G.NEURO_TEST = true  -- reaches module internals published only behind the test seam

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED, RECTS, DRAWS = {}, {}, {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
local function record_draw(...)
  local args = { ... }
  DRAWS[#DRAWS + 1] = { x = args[3], y = args[4], sx = args[6], sy = args[7] }
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
  draw = record_draw,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true, purchase_showcase_queue = {},
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

local check, done = require("tests.helpers").harness("acquire geometry")

local HudState = require("hud.state")
local Acquire = require("render.panels.acquire")

local atlas_entry = function(px, py) return { image = IMG, px = px, py = py } end
G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
G.ASSET_ATLAS.FIX95 = atlas_entry(95, 95)
G.ASSET_ATLAS.FIX50 = atlas_entry(50, 100)
G.ASSET_ATLAS.FIX120 = atlas_entry(120, 80)
G.ASSET_ATLAS.centers = atlas_entry(71, 95)

local function make_card(key, atlas_key)
  return {
    config = { center = { key = key or "j_fixture", set = "Joker", atlas = atlas_key or "FIX71",
      pos = { x = 0, y = 0 }, name = key, loc_txt = { name = key } } },
    ability = {},
    cost = 5,
  }
end

local function id(v) return v end

for _, fh in ipairs({ { 12, 12 }, { 18, 10 }, { 22, 14 } }) do
  local name_h, eyebrow_h = fh[1], fh[2]
  local L = Acquire._layout_receipt(id, name_h, eyebrow_h)
  local tag = "name=" .. name_h .. " eyebrow=" .. eyebrow_h
  check("1 box holds the stack (" .. tag .. ")", L.box_h >= name_h + eyebrow_h + L.lead, L.box_h)
  check("1 thumb inside box (" .. tag .. ")", L.thumb_h < L.box_h)
  check("1 width clamp ordered (" .. tag .. ")", L.min_w <= L.max_w)
  check("1 quantum positive (" .. tag .. ")", L.quant > 0)
end

local Lr = {
  w = 220, h = 64, L = Acquire._layout_receipt(id, 12, 12),
  card_dx = 14, card_w = 40, card_h = 52,
  text_dx = 64, text_w = 120,
  eyebrow_dy = 19, name_dy = 33, badges_dy = 49, desc_dy = 49,
  price_dy = 26, price_w = 24,
  crest_dx = 14, crest_dy = 10,
  efh = 12, nfh = 12, pfh = 12,
}
local Lf = {
  w = 420, h = 118, compact = false,
  card_dx = 6, card_w = 82, card_h = 110, mini_h = 110,
  text_dx = 104, text_w = 300,
  eyebrow_dy = 4, name_dy = 20, badges_dy = 36, desc_dy = 52,
  crest_dx = 14, crest_dy = 10,
  efh = 12, nfh = 12, sfh = 12, lead = 4,
}
do
  local g1 = Acquire._geom(Lr, Lf, 0.5, 400, 8)
  local g2 = Acquire._geom(Lr, Lf, 0.5, 400, 8)
  local same = true
  for k, v in pairs(g1) do if g2[k] ~= v then same = false end end
  check("2a same inputs give the same geometry", same)
  local g0 = Acquire._geom(Lr, Lf, 0, 400, 8)
  local gm = Acquire._geom(Lr, Lf, 1, 400, 8)
  check("2b m=0 is the receipt box", g0.w == Lr.w and g0.h == Lr.h, g0.w .. "x" .. g0.h)
  check("2c m=1 is the showcase box", gm.w == Lf.w and gm.h == Lf.h, gm.w .. "x" .. gm.h)
  check("2d the receipt-only endpoint stands alone",
    Acquire._geom(Lr, nil, 0, 400, 8).w == Lr.w)
  check("2e the showcase-only endpoint stands alone",
    Acquire._geom(nil, Lf, 1, 400, 8).w == Lf.w)
end

do
  local prev
  local bad_mono, bad_top, bad_center, bad_contain = 0, 0, 0, 0
  for i = 0, 20 do
    local m = i / 20
    local g = Acquire._geom(Lr, Lf, m, 400, 8)
    if prev then
      if g.w < prev.w or g.h < prev.h then bad_mono = bad_mono + 1 end
      if g.card_h < prev.card_h then bad_mono = bad_mono + 1 end
    end
    if g.y ~= 8 then bad_top = bad_top + 1 end
    if math.abs((g.x + g.w / 2) - 400) > 1 then bad_center = bad_center + 1 end
    local inside = g.card_x >= g.x and g.card_x + g.card_w <= g.x + g.w
      and g.card_y >= g.y and g.card_y + g.card_h <= g.y + g.h
      and g.text_x >= g.x and g.text_x + g.text_w <= g.x + g.w
      and g.eyebrow_y >= g.y and g.name_y > g.eyebrow_y
      and g.badges_y >= g.name_y and g.desc_y >= g.badges_y
      and g.price_x + Lr.price_w <= g.x + g.w
      and g.crest_cx > g.x and g.crest_cx < g.x + g.w
      and g.crest_cy > g.y and g.crest_cy < g.y + g.h
      and g.timer_y >= g.y and g.timer_y <= g.y + g.h
    if not inside then bad_contain = bad_contain + 1 end
    prev = g
  end
  check("3a width, height and card grow monotonically", bad_mono == 0, bad_mono)
  check("3b the top edge is pinned for every m", bad_top == 0, bad_top)
  check("3c the panel stays centered on cx", bad_center == 0, bad_center)
  check("3d every content anchor stays inside the frame", bad_contain == 0, bad_contain)
end

do
  local g = Acquire._geom(Lr, Lf, 1, 400, 8)
  check("4a crest x sits cn(14) inside the right edge", g.crest_cx == g.x + g.w - 14, g.crest_cx)
  check("4b crest y sits cn(10) below the top edge", g.crest_cy == g.y + 10, g.crest_cy)
end

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = { 1, 1, 1, 1 }, CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local function mock_ctx(persona)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = persona == "evil", persona == "neuro"
  theme.pk = persona
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = { rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1, text_h = 12 },
    data = { sn = "SHOP", state_name = "SHOP", pack_rows = {} },
    draw = {
      trunc = function(s) return s end,
      wrapped_lines = function(s) return { tostring(s) } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end,
    },
    center_top_y = 8, center_cx = 640, center_max_w = 900,
  }
end

do
  local ctx = mock_ctx("hiyori")
  local card = make_card("j_fixture", "FIX71")
  local Lfx = Acquire._layout_full(ctx, { card = card, label = "NEW JOKER" })
  check("5a EYEBROW_LEAD keeps cn(4) between eyebrow and name",
    Lfx.name_dy - (Lfx.eyebrow_dy + Lfx.efh) >= 4,
    Lfx.name_dy - (Lfx.eyebrow_dy + Lfx.efh))
  check("5b the text column fits the frame", Lfx.text_dx + Lfx.text_w + 8 <= Lfx.w)
  check("5c the full frame clears its miniature", Lfx.h >= Lfx.card_h + 8)
end

for _, sc in ipairs({ 0.5, 1, 1.5 }) do
  local ctx = mock_ctx("hiyori")
  ctx.metrics.cn = function(v)
    local r = math.floor((tonumber(v) or 0) * sc + 0.5)
    return r < 1 and 1 or r
  end
  local pinned = make_card("j_fixture", "FIX71")
  pinned.ability.eternal = true
  pinned.edition = { holo = true }
  local L = Acquire._layout_full(ctx, { card = pinned, label = "NEW JOKER" })
  local tag = string.format("at scale %.1f", sc)

  check("5d the fixture wears pins and a description " .. tag,
    L.badge_layout.height > 0 and L.n_desc > 0,
    string.format("strip %dpx, %d description lines", L.badge_layout.height, L.n_desc))

  local eyebrow_lead = L.name_dy - (L.eyebrow_dy + L.efh)
  local pin_lead = L.badges_dy - (L.name_dy + L.nfh)
  check("5d the pin strip's leading is the column's own leading " .. tag,
    pin_lead == eyebrow_lead and pin_lead == L.lead,
    string.format("eyebrow->name %d, name->pins %d, lead %d", eyebrow_lead, pin_lead, L.lead))
  local under = L.desc_dy - (L.badges_dy + L.badge_layout.height)
  check("5d the gap under the pin strip scales with the panel " .. tag,
    under == ctx.metrics.cn(2), string.format("%d, want cn(2)=%d", under, ctx.metrics.cn(2)))

  local P = Acquire._layout_full(ctx, { card = make_card("j_fixture", "FIX71"), label = "NEW JOKER" })
  local bottom = (P.n_desc > 0)
    and (P.desc_dy + P.n_desc * (P.sfh + 1))
    or (P.badges_dy + P.badge_layout.height)
  local above, below = P.eyebrow_dy, P.h - bottom
  check("5e the miniature is what sets the box height " .. tag, P.h > bottom + 4,
    string.format("box %d, column ends %d", P.h, bottom))
  check("5e the text column is centred in the box " .. tag, math.abs(above - below) <= 1,
    string.format("%d above, %d below, in a box of %d", above, below, P.h))
end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function rects_sane(list)
  for _, r in ipairs(list) do
    if not (finite(r.x) and finite(r.y) and finite(r.w) and finite(r.h)) then
      return false, "non-finite rect"
    end
    if r.w < 0 or r.h < 0 then
      return false, string.format("negative rect %sx%s", tostring(r.w), tostring(r.h))
    end
  end
  return true
end
local function draws_sane(list)
  for _, d in ipairs(list) do
    if not (finite(d.x) and finite(d.y) and finite(d.sx) and finite(d.sy)) then
      return false, "non-finite draw"
    end
  end
  return true
end

local jokers_list = { "j_half", "j_photograph", "j_square", "j_wee" }
local atlases_list = { "FIX71", "FIX95", "FIX50", "FIX120" }
for _, persona in ipairs({ "hiyori", "evil", "neuro" }) do
  for _, jk in ipairs(jokers_list) do
    for _, ak in ipairs(atlases_list) do
      local card = make_card(jk, ak)
      local tag = persona .. "/" .. jk .. "@" .. ak
      HudState.buy_showcase = { card = card, name = jk, area = "shop", cost = 5, started = 0.4 }
      HudState.joker_showcase = nil
      RECTS, DRAWS, PRINTED = {}, {}, {}
      local ok_r, err_r = xpcall(function() Acquire.draw(mock_ctx(persona)) end, debug.traceback)
      check("6 receipt renders " .. tag, ok_r, err_r)
      if ok_r then
        check("6 receipt draws real content " .. tag, #RECTS > 0 and #PRINTED > 0,
          string.format("rects=%d printed=%d", #RECTS, #PRINTED))
        local rok, rwhy = rects_sane(RECTS)
        local dok, dwhy = draws_sane(DRAWS)
        check("6 receipt geometry stays finite and non-negative " .. tag,
          rok and dok, rwhy or dwhy)
      end
      HudState.buy_showcase = nil
      HudState.joker_showcase = { card = card, label = "NEW JOKER", started = 0.4 }
      RECTS, DRAWS, PRINTED = {}, {}, {}
      local ok_f, err_f = xpcall(function() Acquire.draw(mock_ctx(persona)) end, debug.traceback)
      check("6 full renders " .. tag, ok_f, err_f)
      if ok_f then
        check("6 full draws real content " .. tag, #RECTS > 0 and #PRINTED > 0,
          string.format("rects=%d printed=%d", #RECTS, #PRINTED))
        local rok, rwhy = rects_sane(RECTS)
        local dok, dwhy = draws_sane(DRAWS)
        check("6 full geometry stays finite and non-negative " .. tag,
          rok and dok, rwhy or dwhy)
      end
      HudState.joker_showcase = nil
    end
  end
end

done()
