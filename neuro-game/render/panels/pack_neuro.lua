local Prims = require("hud.prims")
local gfx = require("render.gfx")
local set_col = gfx.set_col
local lg = love.graphics
local clamp01 = Prims.clamp01

local RAD = 9 -- panel corner inset

local M = {
  TL = { ANOINT = 0.22, GLIDE = 0.44, CROWN = 0.30, SHRINK = 0.26, HOLD = 0.14, EXIT = 0.45, FOLD = 0.18 },
  GLIDE_ANT = 0.12,
  GLIDE_OVER = 0.16,
  ENTRY = { 2.7, 1.7, 44 },
  DISSOLVE = { { 1.00, 0.78, 0.86, 1 }, { 1.00, 0.30, 0.58, 1 } },
  MARK_HEAD_UNITS = 28, -- clears the slot_mark bow above the title band
  TITLE_RIGHT_RESERVE_UNITS = 14, -- clears the title-corner bow drawn in M.frame
}


function M.frame(h, g)
  local cn = h.cn
  local a = g.a
  local sr, sg2, sb = g.shimr, g.shimg, g.shimb
  local rad = cn(RAD)
  lg.setLineWidth(1)
  lg.setColor(sr, sg2, sb, 0.16 * a)
  lg.rectangle("line", g.x - 1, g.y - 1, g.w + 2, g.h + 2, rad + 1, rad + 1)
  lg.setColor(1, 1, 1, 0.07 * a)
  lg.rectangle("fill", g.x + rad, g.y + 1, g.w - rad * 2, 1)
  Prims.draw_bow(g.x + g.w - cn(24), g.y + cn(14), cn(2), h.ACC, 0.95 * a, h.pg)
  do
    for si = 1, 3 do
      local sxr = 0.5 + 0.5 * math.sin(si * 78.233 + 0.9)
      local tw = Prims.twinkle01(h.now, si)
      Prims.draw_sparkle(g.x + g.w * 0.38 + sxr * g.w * 0.33,
        g.y + cn(7) + (0.5 + 0.5 * math.sin(si * 39.425)) * cn(9),
        cn(2) + tw * cn(2), (si % 2 == 0) and h.pg or h.ACC, 0.5 * tw * a)
    end
  end
  if g.flare < 1 then
    Prims.confetti_burst(g.cx, g.y + g.title_h, g.flare, cn(18), cn(3), 0.4, h.pg, h.ACC, a)
  end
end

function M.title_deco(h, g)
  local cn = h.cn
  local sr, sg2, sb = g.shimr, g.shimg, g.shimb
  local rad = cn(RAD)
  local tag_w = g.w - rad * 2
  Prims.tag_string(g.x + rad, g.y + g.title_h - 2, tag_w, 1, sr, sg2, sb, g.a, true)
  Prims.draw_heart(g.x + cn(10), g.y + g.title_h - 2, cn(3), h.pg, 0.55 * g.a)
  Prims.draw_heart(g.x + g.w - cn(10), g.y + g.title_h - 2, cn(3), h.pg, 0.55 * g.a)
end

function M.slot(h, sg, st, scan)
  local cn = h.cn
  local a = sg.a
  local sr, sg2, sb = sg.shimr, sg.shimg, sg.shimb
  Prims.card_sleeve(sg.x, sg.y, sg.w, sg.h, sg.u, h.ACC, h.pg, sr, sg2, sb, a)
  if st == "picked" then
    lg.setColor(sr, sg2, sb, 0.16 * a)
    lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h, cn(6), cn(6))
  elseif st == "highlighted" then
    lg.setColor(sr, sg2, sb, (0.12 + 0.06 * scan) * a)
    lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h, cn(6), cn(6))
    lg.setColor(sr, sg2, sb, (0.65 + 0.20 * scan) * a)
    lg.setLineWidth(cn(2))
    lg.rectangle("line", sg.x, sg.y, sg.w, sg.h, cn(6), cn(6))
  else
    set_col(sg.rc, (0.30 + 0.10 * h.pulse) * a)
    lg.setLineWidth(cn(1))
    lg.rectangle("line", sg.x, sg.y, sg.w, sg.h, cn(3), cn(3))
  end
  if st ~= "normal" then
    lg.setColor(sr, sg2, sb, 0.45 * a)
    lg.setLineWidth(cn(1))
    lg.rectangle("line", sg.sp_x - 3, sg.sp_y - 3, sg.sp_w + 6, sg.sp_h + 6, cn(3), cn(3))
  end
  if sg.appear < 1 then
    Prims.draw_sparkle(sg.x + sg.w - cn(6), sg.y + cn(6),
      cn(3) + (1 - sg.appear) * cn(3), h.pg, (1 - sg.appear) * 0.9 * a)
  end
end

function M.slot_mark(h, sg, _, bob)
  local cn = h.cn
  Prims.draw_bow(sg.cx, sg.y - cn(7) + bob, cn(1.5), h.ACC, 0.95 * sg.a, h.pg)
  Prims.draw_sparkle(sg.x + cn(4), sg.y + cn(4), cn(2), h.pg, (0.5 + 0.3 * sg.scan) * sg.a)
  Prims.draw_sparkle(sg.x + sg.w - cn(4), sg.y + sg.h - cn(4), cn(2), h.pg, (0.5 + 0.3 * sg.scan) * sg.a)
end

function M.claim(h, sg, pe)
  local cn = h.cn
  local ca = sg.a
  local mcx, mcy = sg.cx, sg.cy
  local sr, sg2, sb = sg.shimr, sg.shimg, sg.shimb
  do
    if pe < 0.5 then
      local ov0 = math.min(1, pe / 0.32)
      local veil = (pe < 0.32) and (0.5 * ov0) or math.max(0, 0.5 * (1 - (pe - 0.32) / 0.18))
      set_col(h.ACC, veil * ca)
      lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h, cn(3), cn(3))
      lg.setColor(sr, sg2, sb, veil * 0.6 * ca)
      lg.rectangle("fill", sg.x, sg.y, sg.w, math.max(2, sg.h * 0.5))
    end
    local ov = math.min(1, pe / 0.32)
    local rmax = math.min(sg.w * 0.5, sg.burst_r)
    Prims.confetti_burst(mcx, mcy, ov, rmax, h.U * 1.7, 0.2, h.pg, h.ACC, ca)
    Prims.confetti_burst(mcx, mcy, ov, rmax * 0.66, h.U * 1.5, 1.1, h.pg, h.ACC, 0.9 * ca)
    Prims.confetti_burst(mcx, mcy, ov, rmax * 0.4, h.U * 1.3, 2.0, h.pg, h.ACC, 0.85 * ca)
    if pe < 0.42 then
      local sca = (1 - pe / 0.42) * ca
      for i = 1, 7 do
        local sxp = sg.x + (0.5 + 0.5 * math.sin(i * 12.9898)) * sg.w
        local syp = sg.y + (0.5 + 0.5 * math.sin(i * 78.233)) * sg.h
        if i % 2 == 0 then Prims.draw_sparkle(sxp, syp, h.U * 1.4, h.pg, 0.9 * sca)
        else Prims.draw_heart(sxp, syp, h.U * 1.2, h.ACC, 0.85 * sca) end
      end
    end
    if pe >= 0.30 and pe < 0.52 then
      local fl = math.sin(math.pi * (pe - 0.30) / 0.22)
      lg.setColor(1, 1, 1, 0.5 * fl * ca)
      lg.rectangle("fill", sg.x, sg.y, sg.w, sg.h, cn(3), cn(3))
      set_col(h.pg, 0.35 * fl * ca)
      lg.rectangle("fill", sg.x - cn(2), sg.y - cn(2), sg.w + cn(4), sg.h + cn(4), cn(4), cn(4))
      local burst = (pe - 0.30) / 0.22
      Prims.confetti_burst(mcx, mcy, burst, rmax, h.U * 1.8, 0.6, h.pg, h.ACC, ca)
      Prims.confetti_burst(mcx, mcy, burst, rmax * 0.8, h.U * 1.5, 1.7, h.pg, h.ACC, 0.9 * ca)
    end
    local pop = clamp01((pe - 0.30) / 0.22)
    local bsc = 1 + 0.6 * math.sin(math.pi * pop)
    Prims.draw_bow(mcx, mcy, cn(2) * bsc, h.ACC, 0.95 * ca, h.pg)
  end
end

function M.crown(h, hg, cw01)
  local cn = h.cn
  local a = hg.a
  local bx = hg.cx
  local by0 = hg.cy - math.floor(hg.h / 2) + cn(8)
  local salpha = math.min(1, cw01 * 4) * a
  do
    local drop = Prims.Motion.ease_out_back(clamp01(cw01 / 0.45))
    local by = by0 - cn(10) * (1 - drop)
    local pop = 1 + 0.30 * math.max(0, 1 - cw01 * 3)
    Prims.draw_bow(bx, by, cn(2) * pop, h.ACC, salpha, h.pg)
    Prims.draw_heart(bx - cn(14), by + cn(2), cn(4), h.pg, 0.8 * salpha)
    Prims.draw_heart(bx + cn(14), by + cn(2), cn(4), h.pg, 0.8 * salpha)
    local rp = (cw01 - 0.30) / 0.35
    if rp > 0 and rp < 1 then
      Prims.confetti_burst(bx, by, rp, cn(18), cn(3), 0.9, h.pg, h.ACC, a)
      Prims.draw_sparkle(bx - cn(10), by + cn(4),
        cn(3) + math.sin(math.pi * rp) * cn(4), h.pg, 0.85 * math.sin(math.pi * rp) * a)
    end
  end
  if hg.cf > 0 then
    for k = 1, 3 do
      local ang = h.now * 1.6 + k * 2.0944
      local px = hg.cx + math.cos(ang) * hg.w * 0.60
      local py = hg.cy + math.sin(ang) * hg.h * 0.45
      local tw = (0.35 + 0.4 * Prims.twinkle01(h.now, k)) * hg.cf * a
      if k == 2 then Prims.draw_heart(px, py, cn(4), h.pg, tw)
      else Prims.draw_sparkle(px, py, cn(2), h.pg, tw) end
    end
  end
end

function M.exit(h, g, x01)
  local cn = h.cn
  local a = (1 - x01) * g.a
  if a <= 0 then return end
  for k = 1, 5 do
    local fx = g.x + cn(12) + (0.5 + 0.5 * math.sin(k * 12.9898)) * (g.w - cn(24))
    local fy = g.y + g.title_h + (0.5 + 0.5 * math.sin(k * 78.233))
      * math.max(0, g.h - g.title_h - cn(12))
    if k % 2 == 0 then Prims.draw_heart(fx, fy, cn(3), h.pg, 0.5 * a)
    else Prims.draw_sparkle(fx, fy, cn(2) + x01 * cn(2), h.ACC, 0.6 * a) end
  end
end

return M
