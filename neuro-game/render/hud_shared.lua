local Palette  = require("render.palette")
local Prims    = require("hud.prims")
local Cards    = require("hud.cards")
local CardUtil = require("facts.card_util")
local Showcase = require("hud.showcase")
local Utils    = require("util.utils")
local S        = require("hud.state")

local lg = love.graphics
local Motion = Prims.Motion

local CAROUSEL_PERIOD = 2 * Motion.dur(Motion.MED) + Motion.SLOW * 5

local function carousel_clock(now)
  local e = math.floor(now / CAROUSEL_PERIOD)
  return e, now - e * CAROUSEL_PERIOD
end

local function buy_flare01(now)
  local bs = S.buy_showcase
  if not bs or not bs.started or Motion.reduced then return 0 end
  local t = now - bs.started
  if t >= 0 and t < 0.5 then return math.sin(math.pi * t / 0.5) end
  return 0
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

local set_col = Prims.set_col
local shadow_text = Prims.shadow_text

-- opts: { a, sh, rad, title_h, skip_body (neuro), glow (evil counter_glow) }; returns prad
local function persona_frame(th, mo, x, y, w, h, u, opts)
  opts = opts or {}
  local a = opts.a or 1
  local prad = th.persona_neuro and (opts.rad or u * 9) or 0
  Prims.panel_base(x, y, w, h, prad, opts.sh or 2, a, th.bg, th.FR)
  if th.persona_evil then
    Prims.gothic_frame(x, y, w, h, u, th.GOLD, th.FRD, a, 0, mo.pulse)
    if opts.title_h then
      set_col(th.pg, Prims.EVIL.A_WASH * a)
      lg.rectangle("fill", x + 1, y + 1, w - 2, opts.title_h)
    end
    if opts.glow then Prims.counter_glow(x, y, w, h, th.GOLD, a, mo.pulse, 0) end
  elseif th.persona_neuro then
    Prims.neuro_frame_deco(x, y, w, h, prad, u, opts.title_h or u * 44, th.ACC, th.pg,
      mo.shimr, mo.shimg, mo.shimb, a, opts.skip_body)
  end
  return prad
end

local function evil_frame(x, y, w, h, u, title_h, GOLD, GLOW, bg, pulse, now, a, flare, cxf)
  Prims.evil_frame_deco(x, y, w, h, u, title_h, GOLD, GLOW, pulse, now, Motion.reduced, cxf or 0.30, a, flare or 0)
  Prims.cornice_crenel(x, y, w, u, bg, GOLD, a)
end

local print_tracked = Prims.print_tracked
local tracked_width = Prims.tracked_width
local function caps_label(s, x, y, col, a, track, f, sh_a)
  track = track or 0
  if sh_a and sh_a > 0 then
    lg.setColor(0, 0, 0, sh_a)
    print_tracked(s, x + 1, y + 1, track, f)
  end
  set_col(col, a)
  return print_tracked(s, x, y, track, f)
end

return {
  lg = lg,
  set_col = set_col,
  shadow_text = shadow_text,
  print_tracked = print_tracked,
  tracked_width = tracked_width,
  caps_label = caps_label,
  persona_frame = persona_frame,
  carousel_clock = carousel_clock,
  buy_flare01 = buy_flare01,
  evil_frame = evil_frame,
  bind = bind,
  motion = motion,
  persona = persona,

  Palette = Palette,
  Prims = Prims,
  Cards = Cards,
  CardUtil = CardUtil,
  Showcase = Showcase,
  Utils = Utils,
  S = S,

  Motion = Motion,
  DEFAULT_MOTION = Prims.DEFAULT_MOTION,
  smoothstep01 = Prims.smoothstep01,
  ease_out_cubic01 = Prims.ease_out_cubic01,
  neuro_now = Prims.now,

  draw_card_mini = Cards.draw_card_mini,
  card_edition_tag = Cards.card_edition_tag,
  draw_animated_edition = Cards.draw_animated_edition,
  card_display_name = Cards.card_display_name,
  card_description = Cards.card_description,
  rarity_color = Cards.rarity_color,

  joker_fx = CardUtil.joker_fx,
  buy_showcase_alpha = Showcase.buy_alpha,
  card_set_label = Showcase.card_set_label,

  SHOP_SLIDE_IN_PX = 24,
  PACK_CARD_APPEAR_D = Motion.dur(0.35),
  DESC_FADE_D = Motion.dur(Motion.MED),
  DESC_SHOW_D = Motion.SLOW * 5,
  -- must match the carousel's D_TOTAL; voucher rotation derives its dwell from this to stay in sync
  CAROUSEL_PERIOD = CAROUSEL_PERIOD,
  BUY_SHOWCASE_DURATION = Showcase.BUY_SHOWCASE_DURATION,
}
