local H = require("render.hud_shared")
local Acquire = require("render.panels.acquire")
local Prims, Motion = H.Prims, H.Motion
local set_col = H.set_col
local premix, wash_plate = Acquire.premix, Acquire.wash_plate

local TL = { IN = 0.30, HOLD = 0.45, MORPH = 0.30, FX_LEAD = 0.12, OUT = 0.45 }

local _wash_plate, _wash_frame = { 0, 0, 0 }, { 0, 0, 0 }

local function frame(ctx, g)
  local th = ctx.theme
  local a = g.a
  local wash_a = g.wash and g.content_a_full > 0 and (0.14 * a * g.content_a_full) or 0
  local bg, bg_a, fr = th.bg, 0.97 * a, th.FR
  if wash_a > 0 then
    bg, bg_a = wash_plate(_wash_plate, th.bg, g.wash, wash_a, a)
    fr = premix(_wash_frame, th.FR, g.wash, wash_a)
  end
  Prims.panel_shell(g.x, g.y, g.w, g.h, g.rad, 1, 1, 0.55 * a, bg, bg_a, a)
  love.graphics.setColor(fr[1], fr[2], fr[3], 0.90 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", g.x, g.y, g.w, g.h, g.rad, g.rad)
  set_col(th.pg, 0.035 * a)
  love.graphics.rectangle("fill", g.x + 1, g.y + 1, g.w - 2, g.h - 2, g.rad, g.rad)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(g.shimr, g.shimg, g.shimb, 0.16 * a)
  love.graphics.rectangle("line", g.x - 1, g.y - 1, g.w + 2, g.h + 2, g.rad + 1, g.rad + 1)
  love.graphics.setColor(g.shimr, g.shimg, g.shimb, 0.08 * a)
  love.graphics.rectangle("line", g.x - 2, g.y - 2, g.w + 4, g.h + 4, g.rad + 2, g.rad + 2)
  love.graphics.setColor(1, 1, 1, 0.07 * a)
  love.graphics.rectangle("fill", g.x + g.rad, g.y + 1, g.w - g.rad * 2, 1)
end

local function crest(ctx, g)
  local th = ctx.theme
  local u = g.cn(4) * 0.45
  Prims.draw_bow_mini(g.crest_cx, g.crest_cy, u, th.ACC, 0.95 * g.a, th.pg)
end

local function burst(ctx, g, phase, t01)
  local th = ctx.theme
  local cn = g.cn
  if phase == "in" then
    local pk = t01
    local span = math.max(0, g.h - cn(16))
    for si = 0, 2 do
      Prims.draw_sparkle(g.x + (g.accent_w or 3) + cn(3),
        g.y + cn(8) + si * math.floor(span / 2),
        cn(4) + pk * cn(4), th.pg, (1 - pk) * 0.9 * g.a)
    end
  elseif phase == "morph_end" then
    local cx = g.crest_cx - cn(10)
    local cy = g.crest_cy + cn(6)
    local r = math.min(cn(36),
      cx - g.x - cn(2), g.x + g.w - cx + cn(2),
      cy - g.y + cn(2), g.y + g.h - cy + cn(2))
    if r >= 2 then
      Prims.confetti_burst(cx, cy, t01, r, cn(5), 0.4, th.pg, th.ACC, g.a)
      local pk3 = math.sin(math.pi * t01)
      Prims.draw_sparkle(cx - cn(8), cy + cn(4), cn(4) + pk3 * cn(6), th.pg, 0.85 * pk3 * g.a)
    end
  end
end

local function timer(ctx, g, _frac)
  local th = ctx.theme
  local a = g.a * g.content_a_receipt
  if a <= 0 then return end
  local cn = g.cn
  Prims.tag_string(g.x + g.rad, g.timer_y, g.timer_w, 1, g.shimr, g.shimg, g.shimb, a)
  Prims.draw_heart(g.x + g.rad + g.timer_w, g.timer_y + 1, cn(4) * 1.2, th.pg, 0.9 * a)
end

local function card_frame(ctx, g)
  local th = ctx.theme
  love.graphics.setLineWidth(1)
  love.graphics.setColor(g.shimr, g.shimg, g.shimb, 0.38 * g.a)
  love.graphics.rectangle("line", g.card_x - 1, g.card_y - 1, g.card_w + 2, g.card_h + 2, 2, 2)
  if g.content_a_full > 0 then
    local cn = g.cn
    local r = cn(6)
    Prims.draw_heart(g.card_x - 1, g.card_y - 1, r, th.pg, 0.85 * g.a * g.content_a_full)
    Prims.draw_heart(g.card_x + g.card_w + 1, g.card_y + g.card_h - cn(2), r, th.pg,
      0.85 * g.a * g.content_a_full)
  end
end

local function label_deco(ctx, g, lbl_end)
  local th = ctx.theme
  local cn = g.cn
  local a = g.a * g.content_a_full
  if a <= 0 then return end
  local ey = g.eyebrow_y + g.text_h + 1
  love.graphics.setColor(g.shimr, g.shimg, g.shimb, 0.55 * a)
  love.graphics.rectangle("fill", g.text_x, ey, math.max(0, lbl_end - g.text_x), 1)
  local hs_x = lbl_end + cn(8)
  if hs_x + cn(6) <= g.x + g.w - cn(6) then
    Prims.draw_heart(hs_x, g.eyebrow_y + cn(5), cn(5), th.pg, 0.75 * a)
  end
end

return {
  TL = TL,
  ease = Motion.ease_out_cubic,
  rad = function(cn) return cn(9) end,
  frame = frame,
  crest = crest,
  burst = burst,
  timer = timer,
  card_frame = card_frame,
  label_deco = label_deco,
}
