local Prims = require("hud.prims")
local gfx = require("render.gfx")
local set_col = gfx.set_col
local lg = love.graphics
local clamp01 = Prims.clamp01
local round = Prims.round

local PLUNGE_D = 0.15

local M = {
  TL = { ANOINT = 0.26, GLIDE = 0.46, CROWN = 0.36, SHRINK = 0.30, HOLD = 0.16, EXIT = 0.55, FOLD = 0.22 },
  HEAD_UNITS = 0,
  CAP_EXTRA_UNITS = 5,
  GLIDE_ANT = 0.20,
  GLIDE_OVER = 0.10,
  HL_GOLD = true,
  COVERS_PICKED = true,
  CROWN_JOLT = true,
  ENTRY = { 1.9, 0.9, 40 },
  DISSOLVE = { { 0.95, 0.55, 0.12, 1 }, { 0.72, 0.09, 0.05, 1 } },
  MARK_HEAD_UNITS = 26, -- clears the slot_mark knife above the title band
}


function M.frame(h, g)
  local cn = h.cn
  local x, y, w = g.x, g.y, g.w
  local a = g.a
  Prims.cornice_crenel(x, y, w, cn(1), h.bg, h.GOLD, a, true)
  lg.setColor(h.pg[1], h.pg[2], h.pg[3], 0.05 * (0.8 + 0.2 * h.pulse) * a)
  lg.ellipse("fill", x + math.floor(w * 0.30), y + math.floor(g.title_h * 0.55),
    math.floor(w * 0.28), math.floor(g.title_h * 0.42))
  set_col(h.GOLD, 0.08 * a)
  lg.rectangle("fill", x + cn(4), y + 1, w - cn(8), 1)
  Prims.embers(x + math.floor(w * 0.09), y + g.title_h, math.floor(w * 0.82),
    g.h - g.title_h - cn(4), cn(1), h.now, 0.55 * a, 4)
  if g.flare < 1 then
    Prims.ember_bloom(g.cx, y + g.title_h, cn(24), cn(1), g.flare, h.GOLD, a)
  end
  Prims.blood_ledge(x + cn(8), y + g.h - 1, w - cn(16), cn(2), a,
    0.35 + 0.65 * Prims.candle01(h.now), h.pulse, cn(14))
end

function M.title_deco(h, g)
  Prims.evil_divider(g.x, g.y + g.title_h - 1, g.w, h.cn(1), g.title_col, h.GOLD,
    g.a, h.pulse, nil, nil, g.a)
end

function M.slot(h, sg, st, scan)
  local cn = h.cn
  local u = sg.u
  if st == "picked" then
    Prims.niche(sg.x, sg.y, sg.w, sg.h, u, h.GOLD, h.pg, h.pulse, 0.5 * sg.a, true)
  elseif st == "highlighted" then
    Prims.niche(sg.x, sg.y, sg.w, sg.h, u, h.GOLD, h.pg, 0.5 + 0.5 * h.pulse, sg.a, true)
    lg.setColor(h.ACC[1], h.ACC[2], h.ACC[3], (0.10 + 0.06 * scan) * sg.a)
    lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
    set_col(h.GOLD, (0.80 + 0.15 * scan) * sg.a)
    lg.setLineWidth(cn(2))
    lg.rectangle("line", sg.x, sg.y, sg.w, sg.h)
    Prims.photo_corners(sg.x - 1, sg.y - 1, sg.w + 2, sg.h + 2, h.GOLD, (0.85 + 0.15 * scan) * sg.a, cn(9))
  else
    Prims.niche(sg.x, sg.y, sg.w, sg.h, u, h.GOLD, h.pg, h.pulse, sg.a, true)
    set_col(sg.rc, (0.30 + 0.10 * h.pulse) * sg.a)
    lg.setLineWidth(cn(1))
    lg.rectangle("line", sg.x, sg.y, sg.w, sg.h)
  end
  Prims.photo_corners(sg.sp_x - 2, sg.sp_y - 2, sg.sp_w + 4, sg.sp_h + 4, h.GOLD, 0.60 * sg.a, cn(4))
  if sg.appear < 1 then
    Prims.ember_bloom(sg.cx, sg.y + sg.h - cn(6), sg.w * 0.30, u, sg.appear, h.GOLD, sg.a)
  end
end

function M.slot_mark(h, sg, _, bob)
  local cn = h.cn
  Prims.draw_knife(sg.cx, sg.y - cn(9) + bob, cn(1), h.GOLD, h.WHITE, (0.85 + 0.15 * sg.scan) * sg.a, true)
  Prims.draw_glint(sg.x + 4, sg.y + 4, cn(2), h.ACC, (0.5 + 0.3 * sg.scan) * sg.a, h.GOLD, true)
  Prims.draw_glint(sg.x + sg.w - 4, sg.y + sg.h - 4, cn(2), h.ACC, (0.5 + 0.3 * sg.scan) * sg.a, h.GOLD, true)
end

function M.claim(h, sg, pe)
  local cn = h.cn
  local ca = sg.a
  local mcx, mcy = sg.cx, sg.cy
  if pe < PLUNGE_D then
    local pl = pe / PLUNGE_D
    local py0 = sg.y - cn(9)
    Prims.draw_knife(mcx, py0 + (mcy - py0) * pl * pl, cn(1), h.GOLD, h.WHITE, ca, true)
  end
  if pe >= PLUNGE_D and pe < 0.30 then
    local gl = (pe - PLUNGE_D) / 0.15
    Prims.draw_glint(mcx, mcy, cn(2) + cn(2) * gl, h.ACC, (1 - gl) * 0.9 * ca, h.GOLD, true)
  end
  if pe < 0.35 then
    local veil = (pe < 0.20) and (0.35 * pe / 0.20) or (0.35 * math.max(0, 1 - (pe - 0.20) / 0.15))
    set_col(h.ACC, veil * ca)
    lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
  end
  local brand_p = Prims.smoothstep01((pe - 0.15) / 0.30)
  if brand_p > 0 then
    local ease = 1 - (1 - brand_p) * (1 - brand_p)
    local ring_p = math.min(1, brand_p * 1.6)
    if ring_p < 1 then
      local rr = round(cn(9) * (2.3 - 1.3 * ring_p))
      local ra = (1 - ring_p) * 0.9 * ca
      local bar = math.max(2, round(rr * 0.7))
      set_col(h.GOLD, ra)
      lg.rectangle("fill", mcx - math.floor(bar / 2), mcy - rr, bar, 1)
      lg.rectangle("fill", mcx - math.floor(bar / 2), mcy + rr - 1, bar, 1)
      lg.rectangle("fill", mcx - rr, mcy - math.floor(bar / 2), 1, bar)
      lg.rectangle("fill", mcx + rr - 1, mcy - math.floor(bar / 2), 1, bar)
      local dk = round(rr * 0.7071)
      lg.rectangle("fill", mcx - dk - 1, mcy - dk - 1, 2, 2)
      lg.rectangle("fill", mcx + dk - 1, mcy - dk - 1, 2, 2)
      lg.rectangle("fill", mcx - dk - 1, mcy + dk - 1, 2, 2)
      lg.rectangle("fill", mcx + dk - 1, mcy + dk - 1, 2, 2)
    end
    local press = 1 + 0.35 * math.max(0, 1 - brand_p * 3)
    lg.push()
    lg.translate(mcx, mcy)
    lg.scale(press, press)
    Prims.wax_seal(0, 0, cn(9), h.U, h.GOLD, ease * ca, h.pulse, true, h.now)
    lg.pop()
  end
  Prims.ember_bloom(mcx, mcy, math.min(sg.w * 0.45, sg.burst_r), sg.u, (pe - 0.35) / 0.50, h.GOLD, ca)
  if pe >= 0.28 and pe < 0.52 then
    local fl = math.sin(math.pi * (pe - 0.28) / 0.24)
    lg.setColor(1, 0.95, 0.85, 0.40 * fl * ca)
    lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
    set_col(h.ACC, 0.28 * fl * ca)
    lg.rectangle("fill", sg.x - cn(2), sg.y - cn(2), sg.w + cn(4), sg.h + cn(4))
    local burst = (pe - 0.28) / 0.24
    Prims.confetti_burst(mcx, mcy, burst, sg.burst_r, cn(2), 0.6, h.GOLD, h.ACC, ca)
    Prims.confetti_burst(mcx, mcy, burst, sg.burst_r * 0.75, cn(2), 1.7, h.GOLD, h.ACC, 0.9 * ca)
  end
end

function M.crown(h, hg, cw01)
  local cn = h.cn
  local a = hg.a
  local sx_ = hg.cx + hg.w / 2 - cn(8)
  local sy_ = hg.cy + hg.h / 2 - cn(8)
  local salpha = math.min(1, cw01 * 4) * a
  do
    local drop = clamp01(cw01 / 0.30)
    local sscale, drip
    if drop < 1 then
      sscale, drip = 2.1 - 1.1 * drop * drop, false
    else
      local settle = clamp01((cw01 - 0.30) / 0.25)
      sscale = 1 - 0.10 * math.sin(math.pi * settle)
      drip = settle > 0.4
    end
    Prims.wax_seal(sx_, sy_, cn(12) * sscale, hg.u, h.GOLD, salpha, h.pulse, drip, h.now)
    Prims.draw_skull(sx_, sy_, cn(8) * sscale, h.WHITE, salpha, h.GOLD, true)
    local rp = (cw01 - 0.30) / 0.35
    if rp > 0 and rp < 1 then
      lg.setBlendMode("add")
      set_col(h.GOLD, 0.55 * (1 - rp) * a)
      lg.setLineWidth(cn(2))
      local rr = cn(8) + rp * cn(16)
      lg.rectangle("line", sx_ - rr, sy_ - rr, rr * 2, rr * 2, cn(3), cn(3))
      lg.setBlendMode("alpha")
    end
    Prims.ember_bloom(sx_, sy_, cn(16), hg.u, (cw01 - 0.30) / 0.45, h.GOLD, a)
  end
  if hg.cf > 0 then
    for k = 1, 3 do
      local ang = h.now * 1.6 + k * 2.0944
      local px = hg.cx + math.cos(ang) * hg.w * 0.60
      local py = hg.cy + math.sin(ang) * hg.h * 0.45
      Prims.draw_glint(px, py, cn(2), h.GOLD,
        (0.35 + 0.4 * Prims.twinkle01(h.now, k)) * hg.cf * a, h.ACC, true)
    end
  end
end

function M.exit(h, g, x01)
  local cn = h.cn
  Prims.embers(g.x + math.floor(g.w * 0.09), g.y + g.title_h, math.floor(g.w * 0.82),
    g.h - g.title_h - cn(4), cn(1), h.now, 0.7 * (1 - x01) * g.a, 6)
end

return M
