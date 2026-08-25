local H = require("render.hud_shared")
local Acquire = require("render.panels.acquire")
local premix = Acquire.premix
local Prims = H.Prims
local set_col = H.set_col
local round = Prims.round
local clamp01 = Prims.clamp01
local lg = love.graphics

local TL = { IN = 0.42, HOLD = 0.55, MORPH = 0.35, FX_LEAD = 0.15, OUT = 0.55 }

local GLITCH_RED = { 0.95, 0.10, 0.16 }
local GLITCH_CYAN = { 0.12, 0.80, 0.90 }
local FLASH_HOT = { 1, 0.95, 0.85 }

local function ease(m01)   -- gate-slam
  local t = clamp01(m01)
  local inv = 1 - t
  local inv2 = inv * inv
  return 1 - inv2 * inv2 * inv
end

local _bands = {
  { 0, 0, { 0, 0, 0 }, 0, 0, 0 },
  { 0, 0, { 0, 0, 0 }, 0, 0, 0 },
  { 0, 0, { 0, 0, 0 }, 0, 0, 0 },
}
local _wash_frame = { 0, 0, 0 }

local function frame(ctx, g)
  local th = ctx.theme
  local cn = g.cn
  local u = cn(4)
  local a = g.a
  local caf = g.content_a_full
  local wash_a = g.wash and caf > 0 and (0.16 * a * caf) or 0
  local frame_col = th.FR
  if wash_a > 0 then
    frame_col = premix(_wash_frame, th.FR, g.wash, wash_a)
  end
  local burn = 0.35 + 0.65 * Prims.candle01(g.now)
  local pg_a = (Prims.EVIL.A_WASH + 0.015 * burn) * a
  local bands
  if g.w > 2 and g.h > 2 then
    local mid_a = pg_a + wash_a * (1 - pg_a)
    local b1, b2, b3 = _bands[1], _bands[2], _bands[3]
    local edge, mid = b1[3], b2[3]
    if wash_a > 0 then
      edge[1], edge[2], edge[3] = g.wash[1], g.wash[2], g.wash[3]
    end
    if mid_a > 0 then
      local pk, wk = pg_a / mid_a, wash_a * (1 - pg_a) / mid_a
      mid[1] = th.pg[1] * pk + (wash_a > 0 and g.wash[1] * wk or 0)
      mid[2] = th.pg[2] * pk + (wash_a > 0 and g.wash[2] * wk or 0)
      mid[3] = th.pg[3] * pk + (wash_a > 0 and g.wash[3] * wk or 0)
    end
    b1[1], b1[2], b1[4], b1[5], b1[6] = 0, 1, wash_a, 0, g.w
    b2[1], b2[2], b2[4], b2[5], b2[6] = 1, g.h - 1, mid_a, 1, g.w - 1
    b3[1], b3[2], b3[4], b3[5], b3[6] = g.h - 1, g.h, wash_a, 0, g.w
    b3[3] = edge
    bands = _bands
  end
  if bands then
    Prims.panel_shell(g.x, g.y, g.w, g.h, 0, 2, 2, 0.55 * a, th.bg, 0.97 * a, a, bands)
    if wash_a > 0 then
      set_col(g.wash, wash_a)
      lg.rectangle("fill", g.x, g.y + 1, 1, g.h - 2)
      lg.rectangle("fill", g.x + g.w - 1, g.y + 1, 1, g.h - 2)
    end
    lg.setColor(frame_col[1], frame_col[2], frame_col[3], 0.90 * a)
    lg.setLineWidth(1)
    lg.rectangle("line", g.x, g.y, g.w, g.h, 0, 0)
  else
    Prims.panel_base(g.x, g.y, g.w, g.h, 0, 2, a, th.bg, frame_col)
    set_col(th.pg, pg_a)
    lg.rectangle("fill", g.x + 1, g.y + 1, g.w - 2, g.h - 2)
    if wash_a > 0 then
      set_col(g.wash, wash_a)
      lg.rectangle("fill", g.x, g.y, g.w, g.h)
    end
  end
  if caf > 0 then
    Prims.counter_glow(g.x, g.y, g.w, g.h, th.GOLD, 0.55 * a * caf, g.pulse, 0)
    Prims.embers(g.x + cn(6), g.y + cn(6), g.w - cn(12), g.h - cn(10), cn(1),
      g.now, 0.45 * a * caf, 4)
  end
  Prims.gothic_frame(g.x, g.y, g.w, g.h, u, th.GOLD, th.FRD, a, 0, g.pulse, caf <= 0)
end

local function accent(ctx, g)
  if not g.accent or g.content_a_receipt <= 0 then return end
  local th = ctx.theme
  local a = g.a * g.content_a_receipt
  local aw = g.accent_w or 3
  set_col(g.accent, 0.90 * a)
  lg.rectangle("fill", g.x, g.y, aw, g.h)
  set_col(th.GOLD, 0.50 * a)
  lg.rectangle("fill", g.x + aw, g.y, 1, g.h)
end

local function crest(ctx, g)
  local th = ctx.theme
  local cn = g.cn
  local car, caf = g.content_a_receipt, g.content_a_full
  if car > 0 then
    Prims.draw_dark_bow_mini(g.crest_cx - cn(3), g.crest_cy, cn(4) * 0.45, th.ACC,
      0.95 * g.a * car, th.GOLD, true)
  end
  if caf > 0 then
    Prims.wax_seal(g.crest_cx, g.crest_cy + cn(2), cn(9), cn(4), th.GOLD,
      g.a * caf, g.pulse, true)
  end
end

local function burst(ctx, g, phase, t01)
  local th = ctx.theme
  local cn = g.cn
  if phase == "in" then
    local fl = math.sin(math.pi * t01)
    set_col(th.ACC, 0.20 * fl * g.a)
    lg.rectangle("fill", g.x, g.y, g.w, g.h)
    local gj = math.max(1, round(cn(3) * (1 - t01)))
    lg.setLineWidth(1)
    lg.setColor(GLITCH_RED[1], GLITCH_RED[2], GLITCH_RED[3], 0.35 * (1 - t01) * g.a)
    lg.rectangle("line", g.x - gj, g.y, g.w, g.h)
    lg.setColor(GLITCH_CYAN[1], GLITCH_CYAN[2], GLITCH_CYAN[3], 0.28 * (1 - t01) * g.a)
    lg.rectangle("line", g.x + gj, g.y - 1, g.w, g.h)
  elseif phase == "morph_end" then
    local cx = g.crest_cx - cn(10)
    local cy = g.crest_cy + cn(8)
    local r = math.min(cn(30),
      cx - g.x - cn(2), g.x + g.w - cx + cn(2),
      cy - g.y + cn(2), g.y + g.h - cy + cn(2))
    if r >= 2 then
      Prims.ember_bloom(cx, cy, r, cn(1), t01, th.GOLD, g.a)
    end
    local fl = math.sin(math.pi * t01)
    lg.setColor(FLASH_HOT[1], FLASH_HOT[2], FLASH_HOT[3], 0.16 * fl * g.a)
    lg.rectangle("fill", g.x, g.y, g.w, g.h)
    Prims.draw_glint(g.x + cn(4), g.y + cn(4), cn(2), th.ACC, 0.85 * fl * g.a, th.GOLD, true)
    Prims.draw_glint(g.x + g.w - cn(4), g.y + g.h - cn(4), cn(2), th.ACC,
      0.85 * fl * g.a, th.GOLD, true)
  end
end

local function timer(ctx, g, frac)
  local th = ctx.theme
  local a = g.a * g.content_a_receipt
  if a <= 0 then return end
  local cn = g.cn
  local tw = g.timer_w
  set_col(th.ACC, 0.50 * a)
  lg.rectangle("fill", g.x, g.timer_y, tw, 2)
  Prims.blood_ledge(g.x, g.timer_y, tw, cn(3), a, 1 - frac, g.pulse, cn(14))
  set_col(th.GOLD, 0.85 * a)
  lg.rectangle("fill", g.x + tw - 1, g.timer_y - 1, 2, 3)
end

local function card_frame(ctx, g)
  local th = ctx.theme
  local cn = g.cn
  Prims.photo_corners(g.card_x - 2, g.card_y - 2, g.card_w + 4, g.card_h + 4,
    th.GOLD, 0.60 * g.a, cn(8))
  if g.content_a_full > 0 then
    local a = g.a * g.content_a_full
    Prims.draw_glint(g.card_x - 1, g.card_y - 1, cn(2), th.ACC, 0.85 * a, th.GOLD, true)
    Prims.draw_glint(g.card_x + g.card_w + 1, g.card_y + g.card_h - cn(2), cn(2),
      th.ACC, 0.85 * a, th.GOLD, true)
  end
end

local function label_deco(ctx, g, lbl_end)
  local th = ctx.theme
  local cn = g.cn
  local a = g.a * g.content_a_full
  if a <= 0 then return end
  local ey = g.eyebrow_y + g.text_h + 1
  set_col(th.GOLD, 0.50 * a)
  lg.rectangle("fill", g.text_x, ey, math.max(0, lbl_end - g.text_x), 1)
  local dx = lbl_end + cn(7)
  if dx + cn(6) <= g.x + g.w - cn(6) then
    Prims.draw_diamond(dx, g.eyebrow_y + cn(5), cn(2),
      th.GOLD, (0.65 + Prims.EVIL.PULSE_AMP * g.pulse) * a)
  end
end

return {
  TL = TL,
  ease = ease,
  frame = frame,
  accent = accent,
  crest = crest,
  burst = burst,
  timer = timer,
  card_frame = card_frame,
  label_deco = label_deco,
}
