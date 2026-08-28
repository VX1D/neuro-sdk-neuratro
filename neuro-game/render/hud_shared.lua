local Prims    = require("hud.prims")
local Cards    = require("hud.cards")
local CardUtil = require("facts.card_util")
local ModifierBadges = require("render.modifier_badges")
local Showcase = require("hud.showcase")
local Utils    = require("util.utils")
local S        = require("hud.state")

local lg = love.graphics
local Motion = Prims.Motion
local round, clamp = Prims.round, Prims.clamp

local CAROUSEL_PERIOD = 2 * Motion.MED + Motion.SLOW * 5

local _carousel = { anchor = nil, epoch = 0 }

local function carousel_clock(now)
  local a = _carousel.anchor
  if not a or now < a then _carousel.anchor = now; return _carousel.epoch, 0 end
  local d = now - a
  if d >= CAROUSEL_PERIOD then
    local k = math.floor(d / CAROUSEL_PERIOD)
    _carousel.anchor, _carousel.epoch = a + k * CAROUSEL_PERIOD, _carousel.epoch + k
    d = now - _carousel.anchor
  end
  return _carousel.epoch, d
end

local function carousel_restart(now)
  _carousel.anchor = now
end

local function carousel_reset()
  _carousel.anchor, _carousel.epoch = nil, 0
end

local function footer_slot(now)
  return carousel_clock(now)
end

local NOT_AN_ACQUISITION = { refused = true, lost = true }

local function acquisition_started()
  local bs = S.buy_showcase
  local started = bs and bs.started
  if not started then return nil end
  if NOT_AN_ACQUISITION[tostring(bs.area or "")] then return nil end
  return started
end

local BUY_FLARE_D = 0.5
local BUY_POP_D = 0.35

local function acquisition_beat01(now, d)
  local started = acquisition_started()
  if not started then return 0 end
  local t = now - started
  if t >= 0 and t < d then return math.sin(math.pi * t / d) end
  return 0
end

local function buy_flare01(now) return acquisition_beat01(now, BUY_FLARE_D) end
local function buy_pop01(now) return acquisition_beat01(now, BUY_POP_D) end

local PANEL_MARGIN = 8
local CORRIDOR_EDGE = 20

local function corridor(ctx, sw, main_side, eff_px, pw_total, _now, _dt, cn)
  local E = CORRIDOR_EDGE
  local lo, hi = E, sw - E
  if main_side == "left" then lo = math.max(lo, eff_px + pw_total + PANEL_MARGIN)
  else hi = math.min(hi, eff_px - PANEL_MARGIN) end
  if ctx.occ_left then lo = math.max(lo, ctx.occ_left + PANEL_MARGIN) end
  if ctx.occ_right then hi = math.min(hi, ctx.occ_right - PANEL_MARGIN) end
  lo = clamp(lo, E, sw - E)
  hi = clamp(hi, E, sw - E)
  local min_w = cn(240)
  if hi - lo < min_w then
    local c = (lo + hi) / 2
    lo = clamp(c - min_w / 2, E, math.max(E, sw - E - min_w))
    hi = lo + min_w
  end
  Motion.snap(S, "center_cx", (lo + hi) / 2)
  Motion.snap(S, "center_w", hi - lo)
  ctx.center_cx = round(S.center_cx_current)
  ctx.center_max_w = math.floor(S.center_w_current / 16) * 16
  return ctx.center_cx, ctx.center_max_w
end

local function push_clip(x, y, w, h)
  if not (lg.setScissor and lg.getScissor) then return nil end
  local prev = { lg.getScissor() }
  local cw, ch = math.max(0, w), math.max(0, h)
  if lg.intersectScissor then lg.intersectScissor(x, y, cw, ch)
  else lg.setScissor(x, y, cw, ch) end
  return prev
end

local function pop_clip(prev)
  if not (lg.setScissor and prev) then return end
  if prev[1] then lg.setScissor(prev[1], prev[2], prev[3], prev[4]) else lg.setScissor() end
end

local function bind(ctx)
  return ctx.theme, ctx.motion, ctx.metrics, ctx.data, ctx.draw
end
local function motion(mo)
  return mo.now, mo.pulse, mo.shimr, mo.shimg, mo.shimb
end
local function persona(th)
  return th.persona_evil, th.persona_neuro
end

local gfx = require("render.gfx")
local set_col = gfx.set_col
local shadow_text = gfx.shadow_text

local _evil_panel_bands = {
  { 0, 0, false, 0 }, { 0, 0, false, 0 }, { 0, 0, false, 0 },
  { 0, 0, false, 0 }, { 0, 0, false, 0 },
}
local _evil_washed_gold = { 0, 0, 0 }

local function evil_panel_bands(th, w, h, title_h, title_a, body_a)
  if not title_h or title_h <= 1 or h <= title_h + 2 then return nil end
  local b1, b2, b3, b4, b5 = _evil_panel_bands[1], _evil_panel_bands[2],
    _evil_panel_bands[3], _evil_panel_bands[4], _evil_panel_bands[5]
  b1[1], b1[2], b1[3], b1[4], b1[5], b1[6] = 0, 1, th.pg, 0, nil, nil
  b2[1], b2[2], b2[3], b2[4], b2[5], b2[6] = 1, title_h, th.pg, title_a, 1, w - 1
  b3[1], b3[2], b3[3], b3[4], b3[5], b3[6] =
    title_h, title_h + 1, th.pg, body_a + title_a * (1 - body_a), 1, w - 1
  b4[1], b4[2], b4[3], b4[4], b4[5], b4[6] =
    title_h + 1, h - 1, th.pg, body_a, 1, w - 1
  b5[1], b5[2], b5[3], b5[4], b5[5], b5[6] = h - 1, h, th.pg, 0, nil, nil
  return _evil_panel_bands
end

local function persona_frame(th, mo, x, y, w, h, u, opts)
  opts = opts or {}
  local a = opts.a or 1
  local prad = th.persona_neuro and (opts.rad or u * 9) or 0
  local approx_evil = th.persona_evil and opts.title_h
  local title_a = Prims.EVIL.A_WASH * a
  local body_a = (opts.body_wash_a or 0) * a
  local bands = approx_evil and evil_panel_bands(th, w, h, opts.title_h, title_a, body_a) or nil
  local tiled = Prims.panel_base(x, y, w, h, prad, opts.sh or 2, a, th.bg, th.FR, bands)
  if th.persona_evil then
    local gold = th.GOLD
    if bands then
      local inv = 1 - title_a
      gold = _evil_washed_gold
      gold[1] = th.GOLD[1] * inv + th.pg[1] * title_a
      gold[2] = th.GOLD[2] * inv + th.pg[2] * title_a
      gold[3] = th.GOLD[3] * inv + th.pg[3] * title_a
    end
    Prims.gothic_frame(x, y, w, h, u, gold, th.FRD, a, 0, mo.pulse, opts.quiet)
    if opts.title_h and not bands then
      set_col(th.pg, title_a)
      lg.rectangle("fill", x + 1, y + 1, w - 2, opts.title_h)
    end
    if opts.glow then Prims.counter_glow(x, y, w, h, th.GOLD, a, mo.pulse, 0) end
  elseif th.persona_neuro then
    Prims.neuro_frame_deco(x, y, w, h, prad, u, opts.title_h or u * 44, th.FR, th.pg,
      mo.shimr, mo.shimg, mo.shimb, a, opts.skip_body)
  end
  return prad, tiled
end

local function evil_frame(x, y, w, h, u, title_h, GOLD, GLOW, bg, pulse, now, a, flare, cxf)
  Prims.evil_frame_deco(x, y, w, h, u, title_h, GOLD, GLOW, pulse, now, cxf or 0.30, a, flare or 0)
  Prims.cornice_crenel(x, y, w, u, bg, GOLD, a, true)
end

local print_tracked = Prims.print_tracked
local tracked_width = Prims.tracked_width
local draw_cached_tracked_text = Prims.draw_cached_tracked_text
local CAPS_SHADOW = { 0, 0, 0 }
local _CAPS_BLOCK = {}

local function caps_label(s, x, y, col, a, track, f, sh_a, off, outline, owner, key, tint)
  track = track or 0
  local t = tint or 1
  if owner and key and not outline then
    local o = _CAPS_BLOCK
    o.font, o.track = f, track
    o.main_color, o.main_alpha = col, a
    o.shadow_alpha = (sh_a and sh_a > 0) and sh_a or 0
    o.shadow_color = (o.shadow_alpha > 0) and CAPS_SHADOW or nil
    o.shadow_dx, o.shadow_dy = off or 1, off or 1
    o.tint_alpha = t
    local hit, w = draw_cached_tracked_text(owner, key, s, x, y, o)
    if hit then
      return x + (w or tracked_width(s, track, f))
    end
  end
  local esh = sh_a and (sh_a * t) or nil
  if esh and esh > 0 then
    off = off or 1
    lg.setColor(0, 0, 0, esh)
    print_tracked(s, x + off, y + off, track, f)
    if outline then
      print_tracked(s, x - off, y - off, track, f)
      print_tracked(s, x + off, y - off, track, f)
      print_tracked(s, x - off, y + off, track, f)
    end
  end
  set_col(col, a * t)
  return print_tracked(s, x, y, track, f)
end

return {
  set_col = set_col,
  shadow_text = shadow_text,
  print_tracked = print_tracked,
  tracked_width = tracked_width,
  draw_cached_tracked_text = draw_cached_tracked_text,
  caps_label = caps_label,
  persona_frame = persona_frame,
  carousel_clock = carousel_clock,
  carousel_restart = carousel_restart,
  carousel_reset = carousel_reset,
  footer_slot = footer_slot,
  CAROUSEL_PERIOD = CAROUSEL_PERIOD,
  buy_pop01 = buy_pop01,
  buy_flare01 = buy_flare01,
  corridor = corridor,
  PANEL_MARGIN = PANEL_MARGIN,
  push_clip = push_clip,
  pop_clip = pop_clip,
  evil_frame = evil_frame,
  bind = bind,
  motion = motion,
  persona = persona,

  Prims = Prims,
  Utils = Utils,
  S = S,

  Motion = Motion,
  smoothstep01 = Prims.smoothstep01,

  draw_card_mini = Cards.draw_card_mini,
  card_dimensions = Cards.card_dimensions,
  card_sprite = Cards.card_sprite,
  card_display_name = Cards.card_display_name,
  card_description = Cards.card_description,
  rarity_color = Cards.rarity_color,

  modifier_badges = ModifierBadges.collect,
  layout_modifier_badges = ModifierBadges.layout,
  draw_modifier_badges = ModifierBadges.draw,
  badge_family_color = ModifierBadges.badge_color,

  joker_fx = CardUtil.joker_fx,
  buy_showcase_alpha = Showcase.buy_alpha,

  PACK_CARD_APPEAR_D = 0.35,
  DESC_FADE_D = Motion.MED,
  DESC_SHOW_D = Motion.SLOW * 5,
}
