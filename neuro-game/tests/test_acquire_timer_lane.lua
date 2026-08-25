_G.NEURO_TEST = true  -- reaches module internals published only behind the test seam

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local DRAWS = {}
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

local check, done = require("tests.helpers").harness("acquire timer lane")

local HudState = require("hud.state")
local Showcase = require("hud.showcase")
local Acquire = require("render.panels.acquire")
local layout_receipt = Acquire._layout_receipt

G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }

local function id_cn(v) return v end
for _, fh in ipairs({ { 12, 12 }, { 18, 10 }, { 22, 14 } }) do
  local name_h, eyebrow_h = fh[1], fh[2]
  local L = layout_receipt(id_cn, name_h, eyebrow_h)
  local tag = "name=" .. name_h .. " eyebrow=" .. eyebrow_h
  check("box tall enough for the two-line stack (" .. tag .. ")",
    L.box_h >= name_h + eyebrow_h + L.lead, L.box_h)
  check("timer rule at least 2px (" .. tag .. ")", L.timer_h >= 2, L.timer_h)
  check("thumbnail fits inside the box (" .. tag .. ")", L.thumb_h < L.box_h,
    L.thumb_h .. " vs " .. L.box_h)
  check("accent bar at least 2px (" .. tag .. ")", L.accent_w >= 2, L.accent_w)
  check("width clamp is ordered (" .. tag .. ")", L.min_w <= L.max_w,
    L.min_w .. " vs " .. L.max_w)
  check("width quantum positive (" .. tag .. ")", L.quant > 0, L.quant)
end

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
local function receipt_ctx(evil, neuro, now, sw)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  theme.pk = (neuro and "neuro") or (evil and "evil") or "hiyori"
  return {
    theme = theme,
    motion = { now = now, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = {
      rn = id, ln = id, rp_sh = 1, lp_sh = 1, sw = sw or 1920, sh = 1080, U = 4,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      text_h = 12,
    },
    data = { sn = "SHOP", state_name = "SHOP" },
    draw = { trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end },
    center_top_y = 8,
  }
end

local function card_with(ability, with_atlas)
  local center = { key = "j_fx", set = "Joker", name = "Fixture",
    loc_txt = { name = "Fixture" }, rarity = 1 }
  if with_atlas then
    center.atlas, center.pos = "FIX71", { x = 0, y = 0 }
  end
  return { config = { center = center }, ability = ability or {}, cost = 3 }
end
local no_badges = card_with({})
local one_badge = card_with({ eternal = true })
local many_badges = card_with({ eternal = true, perishable = true, rental = true, perish_tally = 3 })
local atlas_card = card_with({}, true)

local BOX_H = layout_receipt(id_cn, 12, 12).box_h

local function draw_once(evil, neuro, card, started, sw, sc_extra)
  RECTS, PRINTED, DRAWS = {}, {}, {}
  HudState.joker_showcase = nil
  HudState.buy_showcase = {
    card = card, name = "Fixture", area = "shop", cost = 3, started = started,
  }
  for k, v in pairs(sc_extra or {}) do HudState.buy_showcase[k] = v end
  local ctx = receipt_ctx(evil, neuro, 0.9, sw)
  local ok, err = xpcall(function() Acquire.draw(ctx) end, debug.traceback)
  return ok, err, ctx
end

local function find_panel_rect()
  for _, r in ipairs(RECTS) do
    if r.mode == "line" and r.w >= 100 then return r end
  end
  return nil
end

local function timer_rects(pr, neuro)
  local out = {}
  local want_h = neuro and 1 or 2
  local want_y = pr.y + pr.h - 2
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.h == want_h and r.y >= want_y and r.y + r.h <= pr.y + pr.h then
      out[#out + 1] = r
    end
  end
  return out
end

local personas = { { "hiyori", false, false }, { "evil", true, false }, { "neuro", false, true } }
for _, p in ipairs(personas) do
  local heights = {}
  for ci, c in ipairs({ no_badges, one_badge, many_badges }) do
    local label = p[1] .. "/card" .. ci
    local ok, err, ctx = draw_once(p[2], p[3], c, 0.0)
    check(label .. " receipt draws without error", ok, err)
    if ok then
      local pr = find_panel_rect()
      check(label .. " panel outline recorded", pr ~= nil)
      if pr then
        heights[#heights + 1] = pr.h
        check(label .. " box height is the layout constant", pr.h == BOX_H, pr.h)
        local trs = timer_rects(pr, p[3])
        check(label .. " timer rule drawn on the bottom edge", #trs > 0, #trs)
        for _, r in ipairs(trs) do
          check(label .. " timer stays inside the box",
            r.x >= pr.x and r.x + r.w <= pr.x + pr.w and r.y + r.h <= pr.y + pr.h,
            r.x .. "+" .. r.w .. " in " .. pr.x .. "+" .. pr.w)
        end
        check(label .. " center stack advance matches the box",
          ctx.center_top_y == 8 + BOX_H + 10, ctx.center_top_y)
      end
    end
  end
  check(p[1] .. " box height never varies with badge load",
    #heights == 3 and heights[1] == heights[2] and heights[2] == heights[3],
    table.concat(heights, ","))
end

for _, fc in ipairs({ 0.2, 0.9, 1.6 }) do
  local ok, err = draw_once(false, true, one_badge, 0.9 - fc)
  check("neuro receipt draws at elapsed " .. fc, ok, err)
  if ok then
    local pr = find_panel_rect()
    if pr then
      for _, r in ipairs(timer_rects(pr, true)) do
        check("neuro timer inside the box at elapsed " .. fc,
          r.x >= pr.x and r.x + r.w <= pr.x + pr.w,
          r.x .. "+" .. r.w .. " in " .. pr.x .. "+" .. pr.w)
      end
    end
  end
end

local function count_glyph_px(y0, y1)
  local n = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w == r.h and r.w <= 3 and r.y >= y0 and r.y <= y1 then
      n = n + 1
    end
  end
  return n
end

do
  local ok = draw_once(true, false, one_badge, 0.0)
  check("evil deco frame draws", ok)
  local pr = find_panel_rect()
  check("evil timer keeps the plain rule under the ledge", pr and #timer_rects(pr, false) >= 1,
    pr and #timer_rects(pr, false))
  check("evil crest sits inside the frame, not on the corner",
    pr and count_glyph_px(pr.y, pr.y + 24) > 0)
  check("evil countdown carries the blood ledge",
    pr and (function()
      local n = 0
      for _, r in ipairs(RECTS) do
        if r.mode == "fill" and r.w <= 3 and r.h >= 1
          and r.y >= pr.y + pr.h - 4 and r.y <= pr.y + pr.h + 12 then n = n + 1 end
      end
      return n > 0
    end)())
end
do
  local ok = draw_once(false, true, one_badge, 0.0)
  check("neuro glyph frame draws", ok)
  local pr = find_panel_rect()
  check("neuro countdown carries the heart charm",
    pr and count_glyph_px(pr.y + pr.h - 12, pr.y + pr.h + 12) > 0)
  check("neuro crest sits inside the frame, not on the corner",
    pr and count_glyph_px(pr.y, pr.y + 24) > 0)
end
do
  local ok = draw_once(false, false, one_badge, 0.0)
  check("hiyori receipt draws", ok)
  local pr = find_panel_rect()
  check("hiyori keeps clean edges (no glyph pixels)",
    pr and count_glyph_px(pr.y - 12, pr.y + pr.h + 12) == 0,
    pr and count_glyph_px(pr.y - 12, pr.y + pr.h + 12))
end

local ok_thumb, err_thumb = draw_once(false, false, atlas_card, 0.0)
check("atlas-backed card draws without error", ok_thumb, err_thumb)
check("atlas-backed card reserves and draws the thumbnail", #DRAWS >= 1, #DRAWS)
local ok_plain = select(1, draw_once(false, false, no_badges, 0.0))
check("sprite-less card draws without error", ok_plain)
check("sprite-less card draws no thumbnail (no black-box fallback)", #DRAWS == 0, #DRAWS)

local ok_swap, err_swap, ctx_swap = draw_once(false, false, one_badge, 0.0, nil,
  { swap_started = 0.88 })
check("cross-cut frame draws without error", ok_swap, err_swap)
if ok_swap then
  local sc = HudState.buy_showcase
  check("box alpha holds through the cross-cut", Showcase.buy_alpha(sc, 0.9) == 1,
    Showcase.buy_alpha(sc, 0.9))
  local ca = Showcase.buy_content_alpha(sc, 0.9)
  check("content alpha dips during the cross-cut", ca < 1, ca)
  check("cross-cut does not move the center stack",
    ctx_swap.center_top_y == 8 + BOX_H + 10, ctx_swap.center_top_y)
end

local q_now = 0.9
HudState.buy_showcase = nil
G.NEURO.purchase_showcase_queue = nil
for i = 1, Showcase.PURCHASE_QUEUE_CAP + 3 do
  Showcase.enqueue_purchase({ card = no_badges, name = "P" .. i, cost = i, area = "shop" })
end
local q = G.NEURO.purchase_showcase_queue
check("queue holds the cap after overflow", #q == Showcase.PURCHASE_QUEUE_CAP, #q)
check("overflow merges into a +N count instead of erasing",
  (q[1].merged or 0) == 3, q[1].merged)
Showcase.update_buy(q_now)
check("merged count rides the pulled showcase",
  HudState.buy_showcase and HudState.buy_showcase.merged == 3,
  HudState.buy_showcase and HudState.buy_showcase.merged)
local ok_chip, err_chip
do
  RECTS, PRINTED, DRAWS = {}, {}, {}
  HudState.buy_showcase.started = 0.0
  local ctx = receipt_ctx(false, false, 0.9)
  ok_chip, err_chip = xpcall(function() Acquire.draw(ctx) end, debug.traceback)
end
check("merged receipt draws without error", ok_chip, err_chip)
local chip_text = table.concat(PRINTED, "|")
check("merged receipt prints the +N chip", chip_text:find("+3", 1, true) ~= nil)
check("merged receipt prints the head's own price, not the merged total",
  chip_text:find("|$4", 1, true) ~= nil and chip_text:find("|$10", 1, true) == nil, chip_text)
check("merged receipt prints the folded money on the chip, told apart from the price",
  chip_text:find("-$6", 1, true) ~= nil, chip_text)
HudState.buy_showcase = nil
G.NEURO.purchase_showcase_queue = nil

done()
