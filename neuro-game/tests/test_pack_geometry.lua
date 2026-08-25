
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

local check, done = require("tests.helpers").harness("pack claim geometry")

local Cards = require("hud.cards")
local Pack = require("render.panels.pack")
local HudState = require("hud.state")
local SZ = Pack.SIZING
local TL = Pack.TIMELINES.soft

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

local SW = 1920
local function mock_ctx(card)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  local metrics = {
    rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = SW, sh = 1080, U = 6,
    GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
    c_text_h = 12, c_small_text_h = 10, text_h = 12,
    r_text_h = 12, r_small_text_h = 10,
  }
  local data = {
    sn = "SHOP", state_name = "SHOP",
    pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
      cards = { { card = card, name = "Joker", desc = "", rc = CLR(), index = 1, badges = {} } } },
  }
  local draw = {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = noop,
    draw_desc_lines = noop, print_colored_desc = noop,
    row_h = function() return 16 end,
    showcase_type_colors = function() return CLR(), CLR() end,
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

local function reset_pack_state()
  HudState.pack_collapse_t, HudState.pack_collapse_snap = nil, nil
  HudState.pack_collapse_req, HudState.pack_collapse_done = nil, nil
  HudState.pack_losers, HudState.pack_disp = nil, nil
  HudState.pack_leave_t, HudState.pack_leave_snap, HudState.pack_leave_n = nil, nil, nil
  HudState.pack_last_sn, HudState.pack_appear_t, HudState.pack_hl_t = nil, nil, nil
  HudState.pack_winners = {}
  HudState.pack_card_indices = {}
  HudState.pack_hidden_indices = {}
  HudState.pack_initial_count = 0
  HudState.pack_hl = false
  HudState.pack_w_hi = nil
  HudState.pack_env_last, HudState.pack_exit_last = nil, nil
end

local function winner_rec(card, name, extra)
  local rec = { slot = 1, card = card, name = name, badges = {},
    mini = Cards.art_prefers_mini(card) }
  local ak, pos = Cards.card_sprite(card)
  if ak then rec.ak, rec.pos = ak, pos end
  for k, v in pairs(extra or {}) do rec[k] = v end
  return rec
end

local function find_draw(x, y, sx, sy)
  for _, d in ipairs(DRAWS) do
    if d.x == x and d.y == y and d.sx == sx and d.sy == sy then return d end
  end
  return nil
end

local function find_rect_near(mode, x, y, w, h)
  for _, r in ipairs(RECTS) do
    if r.mode == mode and math.abs(r.x - x) < 0.01 and math.abs(r.y - y) < 0.01
      and math.abs(r.w - w) < 0.01 and math.abs(r.h - h) < 0.01 then return r end
  end
  return nil
end

local function panel_rect()
  local best
  for _, r in ipairs(RECTS) do
    if r.mode == "line" and r.w and r.h and r.w > 100 and r.w < SW - 40 then
      if not best or r.w * r.h > best.w * best.h then best = r end
    end
  end
  return best
end

local function clampv(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function expected_slots(n)
  local avail = SW - 40
  local sp_w = clampv(
    math.floor((avail - 2 * SZ.PANEL_PAD - (n - 1) * SZ.SLOT_GAP) / n) - 2 * SZ.SLOT_PAD,
    SZ.SP_MIN, SZ.SP_MAX)
  local sp_h = math.floor(sp_w / SZ.SP_ASPECT)
  return sp_w, sp_h, sp_w + 2 * SZ.SLOT_PAD
end

local function pack_collapse_ctx(winner_card, loser_card)
  local ctx = mock_ctx(winner_card)
  ctx.data.pack_rows = { title = "Pack", picks_left = 1, total = 2, pg = CLR(),
    cards = {
      { card = winner_card, name = "W", desc = "", rc = CLR(), index = 1, badges = {} },
      { card = loser_card, name = "L", desc = "", rc = CLR(), index = 2, badges = {} },
    } }
  return ctx
end

local collapse_atlases = { "FIX71", "FIX95", "FIX50", "FIX120" }
local winner_keys = { "j_fixture", "j_half", "j_photograph", "j_square", "j_wee" }
local loser_keys = { "j_wee", "j_square", "j_half", "j_photograph", "j_fixture" }

local COLLAPSE_T0 = 0.9
local GLIDE_START = COLLAPSE_T0 + TL.ANOINT
local DISSOLVE_AT = GLIDE_START + 0.12

local function draw_frame(ctx, cty, t)
  ctx.center_top_y = cty
  ctx.motion.now = t
  RECTS, DRAWS, PRINTED = {}, {}, {}
  return xpcall(function() Pack.draw(ctx) end, debug.traceback)
end

local ENTRY_SETTLE = 0.60
local function settled_pack(ctx)
  reset_pack_state()
  HudState.pack_appear_t = COLLAPSE_T0 - ENTRY_SETTLE
  HudState.pack_initial_count = #ctx.data.pack_rows.cards
end

local SP_W2, SP_H2, SLOT_W2 = expected_slots(2)
local TITLE_H2 = (12 + 4) + 6
local SLOT_Y = 8 + TITLE_H2 + 4

for ai, ak in ipairs(collapse_atlases) do
  for wi, wk in ipairs(winner_keys) do
    local lk = loser_keys[(wi + ai - 2) % #loser_keys + 1]
    local tag = "collapse " .. wk .. ">" .. lk .. "@" .. ak
    local winner_card = make_card(wk, ak)
    local loser_card = make_card(lk, ak)
    local pack_ctx = pack_collapse_ctx(winner_card, loser_card)
    local pack_cty = pack_ctx.center_top_y
    settled_pack(pack_ctx)
    HudState.pack_winners = { winner_rec(winner_card, wk) }
    local ok_pk, err_pk = draw_frame(pack_ctx, pack_cty, COLLAPSE_T0)
    check(tag .. " executes without error", ok_pk, err_pk)
    local snap = HudState.pack_collapse_snap
    check(tag .. " creates a real collapse snapshot", snap ~= nil)
    if snap then
      check(tag .. " snapshot sprite width follows SIZING", snap.sp_w == SP_W2,
        tostring(snap.sp_w) .. " vs " .. tostring(SP_W2))
      check(tag .. " snapshot sprite height follows SIZING aspect", snap.sp_h == SP_H2,
        tostring(snap.sp_h) .. " vs " .. tostring(SP_H2))
      check(tag .. " sprite fills at least 70% of the slot width",
        snap.sp_w / snap.slot_w >= 0.70,
        string.format("%.2f", snap.sp_w / snap.slot_w))
      check(tag .. " sprite width stays within an absolute ceiling, not just a slot ratio",
        snap.sp_w >= 90 and snap.sp_w <= 140, snap.sp_w)

      local ww, wh, wsx, wsy = Cards.card_dimensions(winner_card, snap.sp_h)

      local ok_g, err_g = draw_frame(pack_ctx, pack_cty, GLIDE_START)
      check(tag .. " glide-start frame executes without error", ok_g, err_g)
      check(tag .. " winner drawn with exact geometry scale_x and scale_y",
        find_draw(0, 0, wsx, wsy) ~= nil)
      local exp_ocx = snap.sx0 + math.floor(snap.slot_w / 2)
      local exp_cy = SLOT_Y + snap.sp_dy + math.floor(wh / 2)
      check(tag .. " winner starts at slot sprite size and position (scale continuity)",
        find_rect_near("line", exp_ocx - ww / 2, exp_cy - wh / 2, ww, wh) ~= nil)

      local ok_d, err_d = draw_frame(pack_ctx, pack_cty, DISSOLVE_AT)
      check(tag .. " dissolve frame executes without error", ok_d, err_d)
      local lw, lh, lsx, lsy = Cards.card_dimensions(loser_card, snap.sp_h)
      local exp_lx = snap.sx0 + snap.slot_w + snap.slot_gap + math.floor((snap.slot_w - lw) / 2)
      local exp_ly = SLOT_Y + snap.sp_dy
      check(tag .. " loser drawn at snapshot slot position with single geometry scale",
        find_draw(exp_lx, exp_ly, lsx, lsy) ~= nil)
      if lk == "j_square" then
        check(tag .. " loser square geometry applied exactly once (h == w)", lh == lw,
          tostring(lw) .. "x" .. tostring(lh))
      elseif lk ~= "j_fixture" then
        local _, l_double = Cards.card_dimensions(loser_card, lh)
        check(tag .. " loser height reduced exactly once, not twice", lh > l_double,
          tostring(lh) .. " vs " .. tostring(l_double))
      end
      if lk == "j_half" or lk == "j_photograph"
        or (lk == "j_square" and G.ASSET_ATLAS[ak].px ~= G.ASSET_ATLAS[ak].py) then
        check(tag .. " loser keeps non-uniform scale_y", lsy ~= lsx,
          tostring(lsx) .. "/" .. tostring(lsy))
      end

      if wk == "j_square" then
        check(tag .. " winner square geometry applied exactly once (h == w)", wh == ww,
          tostring(ww) .. "x" .. tostring(wh))
      elseif wk ~= "j_fixture" then
        local _, w_double = Cards.card_dimensions(winner_card, wh)
        check(tag .. " winner height reduced exactly once, not twice", wh > w_double,
          tostring(wh) .. " vs " .. tostring(w_double))
      end
      if wk == "j_half" or wk == "j_photograph"
        or (wk == "j_square" and G.ASSET_ATLAS[ak].px ~= G.ASSET_ATLAS[ak].py) then
        check(tag .. " winner keeps non-uniform scale_y", wsy ~= wsx,
          tostring(wsx) .. "/" .. tostring(wsy))
      end
    end
  end
end

local function rects_outside(px, py, pw, ph)
  local out = 0
  for _, r in ipairs(RECTS) do
    if r.w and r.h and r.w > 0 then
      if r.x < px - 6 or r.y < py - 6 or r.x + r.w > px + pw + 6 or r.y + r.h > py + ph + 16 then
        out = out + 1
      end
    end
  end
  return out
end

do
  local winner_card = make_card("j_fixture", "FIX71")
  local loser_card = make_card("j_wee", "FIX71")
  local ctx = pack_collapse_ctx(winner_card, loser_card)
  local cty = ctx.center_top_y
  settled_pack(ctx)
  HudState.pack_winners = { winner_rec(winner_card, "W") }
  draw_frame(ctx, cty, COLLAPSE_T0)
  local snap = HudState.pack_collapse_snap
  check("containment: snapshot exists", snap ~= nil)
  local loser_max = Pack.LOSER_D + 1 * Pack.LOSER_SPREAD
  local shrink_at = COLLAPSE_T0 + TL.ANOINT + math.max(TL.GLIDE, loser_max)
  local beats_t = {
    ANOINT = COLLAPSE_T0 + 0.5 * TL.ANOINT,
    GLIDE = GLIDE_START + 0.5 * TL.GLIDE,
    SHRINK = shrink_at + 0.5 * TL.SHRINK,
    HOLD = shrink_at + TL.SHRINK + 0.5 * TL.HOLD,
    EXIT = shrink_at + TL.SHRINK + TL.HOLD + 0.5 * TL.EXIT,
  }
  for beat, t in pairs(beats_t) do
    local ok_b, err_b = draw_frame(ctx, cty, t)
    check("containment: " .. beat .. " frame executes", ok_b, err_b)
    local p = panel_rect()
    check("containment: " .. beat .. " has a panel rect", p ~= nil)
    if p then
      check("containment: no rect escapes the envelope during " .. beat,
        rects_outside(p.x, p.y, p.w, p.h) == 0, rects_outside(p.x, p.y, p.w, p.h))
    end
  end

  local function hero_border()
    local best
    for _, r in ipairs(RECTS) do
      if r.mode == "line" and r.w and r.h and r.h > SP_H2 then
        if not best or r.w * r.h > best.w * best.h then best = r end
      end
    end
    return best
  end
  local exit0 = shrink_at + TL.SHRINK + TL.HOLD
  draw_frame(ctx, cty, exit0 + 0.25 * TL.EXIT)
  local ha = hero_border()
  draw_frame(ctx, cty, exit0 + 0.75 * TL.EXIT)
  local hb = hero_border()
  check("EXIT keeps hero geometry across the beat (alpha and lift only)",
    ha and hb and math.abs(ha.x - hb.x) < 0.01 and math.abs(ha.y - hb.y) < 0.01
    and math.abs(ha.w - hb.w) < 0.01 and math.abs(ha.h - hb.h) < 0.01,
    ha and hb and string.format("%.1f,%.1f %.1fx%.1f vs %.1f,%.1f %.1fx%.1f",
      ha.x, ha.y, ha.w, ha.h, hb.x, hb.y, hb.w, hb.h) or "missing hero border")
end

do
  local winner_card = make_card("j_fixture", "FIX71")
  local loser_card = make_card("j_wee", "FIX71")
  winner_card.facing = "back"
  local ctx = pack_collapse_ctx(winner_card, loser_card)
  local cty = ctx.center_top_y
  settled_pack(ctx)
  HudState.pack_winners = { winner_rec(winner_card, "W", { hidden = true }) }
  local ok_h, err_h = draw_frame(ctx, cty, COLLAPSE_T0)
  check("face-down hero: collapse executes without error", ok_h, err_h)
  local snap = HudState.pack_collapse_snap
  check("face-down hero: snapshot exists", snap ~= nil)
  if snap then
    local loser_max = Pack.LOSER_D + 1 * Pack.LOSER_SPREAD
    local shrink_at = COLLAPSE_T0 + TL.ANOINT + math.max(TL.GLIDE, loser_max)
    local t_peak = shrink_at + TL.SHRINK + 0.02
    local ok_p, err_p = draw_frame(ctx, cty, t_peak)
    check("face-down hero: peak frame executes without error", ok_p, err_p)
    local ww, wh, wsx, wsy = Cards.card_dimensions(winner_card, snap.sp_h)
    check("face-down hero: no sprite draw for the hidden winner",
      find_draw(0, 0, wsx, wsy) == nil)
    local p = panel_rect()
    local hero_h = math.floor(wh * SZ.HERO_SCALE)
    local exp_h = TITLE_H2 + 4 + 9 + hero_h + 4 + snap.cap_h + 6
    check("face-down hero: envelope height still budgets the hero box and caption",
      p ~= nil and math.abs(p.h - exp_h) <= 2,
      p and (tostring(p.h) .. " vs " .. tostring(exp_h)) or "no panel")
    local hero_w = math.floor(ww * SZ.HERO_SCALE)
    local exp_w = hero_w + 2 * (SZ.PANEL_PAD + SZ.ENV_PAD)
    check("face-down hero: envelope width wraps the neutral hero box",
      p ~= nil and math.abs(p.w - exp_w) <= 2,
      p and (tostring(p.w) .. " vs " .. tostring(exp_w)) or "no panel")
  end
end

local h_winner = make_card("j_wee", "FIX95")
local h_loser = make_card("j_half", "FIX95")
h_loser.facing = "back"
local h_ctx = pack_collapse_ctx(h_winner, h_loser)
local h_cty = h_ctx.center_top_y
settled_pack(h_ctx)
HudState.pack_winners = { winner_rec(h_winner, "j_wee") }
local ok_h, err_h = draw_frame(h_ctx, h_cty, COLLAPSE_T0)
check("collapse with hidden loser executes without error", ok_h, err_h)
local h_snap = HudState.pack_collapse_snap
check("hidden loser recorded in snapshot as hidden",
  h_snap ~= nil and h_snap.slots ~= nil and h_snap.slots[2] ~= nil and h_snap.slots[2].hidden == true)
if h_snap then
  draw_frame(h_ctx, h_cty, DISSOLVE_AT)
  local hlw, _, hlsx, hlsy = Cards.card_dimensions(h_loser, h_snap.sp_h)
  local hx = h_snap.sx0 + h_snap.slot_w + h_snap.slot_gap + math.floor((h_snap.slot_w - hlw) / 2)
  local hy = SLOT_Y + h_snap.sp_dy
  check("hidden loser produces no sprite draw", find_draw(hx, hy, hlsx, hlsy) == nil)
  local _, _, hwsx, hwsy = Cards.card_dimensions(h_winner, h_snap.sp_h)
  check("winner still drawn when loser is hidden", find_draw(0, 0, hwsx, hwsy) ~= nil)
end

local m_winner = make_card("j_square", "FIX50")
local m_loser = make_card("j_half", "MISSING_ATLAS")
local m_ctx = pack_collapse_ctx(m_winner, m_loser)
local m_cty = m_ctx.center_top_y
settled_pack(m_ctx)
HudState.pack_winners = { winner_rec(m_winner, "j_square") }
local ok_m, err_m = draw_frame(m_ctx, m_cty, COLLAPSE_T0)
check("collapse with missing-atlas loser executes without error", ok_m, err_m)
local m_snap = HudState.pack_collapse_snap
check("missing-atlas loser snapshot keeps SIZING sprite height",
  m_snap ~= nil and m_snap.sp_h == math.floor(m_snap.sp_w / SZ.SP_ASPECT),
  m_snap and tostring(m_snap.sp_h) or "nil")
if m_snap then
  draw_frame(m_ctx, m_cty, DISSOLVE_AT)
  local mlw, _, mlsx, mlsy = Cards.card_dimensions(m_loser, m_snap.sp_h)
  local mx = m_snap.sx0 + m_snap.slot_w + m_snap.slot_gap + math.floor((m_snap.slot_w - mlw) / 2)
  local my = m_cty + TITLE_H2 + 4 + m_snap.sp_dy
  check("missing-atlas loser uses mini fallback without quad draw",
    find_draw(mx, my, mlsx, mlsy) == nil)
  local _, _, mwsx, mwsy = Cards.card_dimensions(m_winner, m_snap.sp_h)
  check("winner still drawn when loser atlas is missing", find_draw(0, 0, mwsx, mwsy) ~= nil)
end

local f_winner = make_card("j_photograph", "MISSING_ATLAS")
local f_loser = make_card("j_wee", "FIX120")
local f_ctx = pack_collapse_ctx(f_winner, f_loser)
local f_cty = f_ctx.center_top_y
settled_pack(f_ctx)
HudState.pack_winners = { winner_rec(f_winner, "j_photograph") }
local ok_f, err_f = draw_frame(f_ctx, f_cty, COLLAPSE_T0)
check("collapse with missing-atlas winner executes without error", ok_f, err_f)
local f_snap = HudState.pack_collapse_snap
check("missing-atlas winner snapshot keeps SIZING sprite height",
  f_snap ~= nil and f_snap.sp_h == math.floor(f_snap.sp_w / SZ.SP_ASPECT),
  f_snap and tostring(f_snap.sp_h) or "nil")
if f_snap then
  draw_frame(f_ctx, f_cty, DISSOLVE_AT)
  local flw, _, flsx, flsy = Cards.card_dimensions(f_loser, f_snap.sp_h)
  local fx = f_snap.sx0 + f_snap.slot_w + f_snap.slot_gap + math.floor((f_snap.slot_w - flw) / 2)
  local fy = f_cty + TITLE_H2 + 4 + f_snap.sp_dy
  check("loser still drawn when winner atlas is missing",
    find_draw(fx, fy, flsx, flsy) ~= nil)
end

do
  local fw = Pack.frame_w
  check("frame_w is exported", type(fw) == "function")
  if type(fw) == "function" then
    check("a narrow sprite is framed at its own width", fw(97, 71) == 71, tostring(fw(97, 71)))
    check("a card at least as wide as the slot keeps the nominal", fw(97, 97) == 97, tostring(fw(97, 97)))
    check("an over-wide measurement is ignored", fw(97, 140) == 97, tostring(fw(97, 140)))
    check("a missing measurement falls back to nominal", fw(97, nil) == 97, tostring(fw(97, nil)))
    check("a zero measurement falls back to nominal", fw(97, 0) == 97, tostring(fw(97, 0)))
  end
end

do
  local source = assert(io.open("render/panels/pack.lua", "r")):read("*all")
  check("pack.lua carries no pack_w_current/_from/_target/_at glide quartet",
    source:find("pack_w_current", 1, true) == nil
    and source:find("pack_w_from", 1, true) == nil
    and source:find("pack_w_target", 1, true) == nil
    and source:find("pack_w_at", 1, true) == nil)
end

done()
