local Utils = require "util.utils"
local dotenv = require("util.dotenv")
local NeuroAnim = require("render.neuro-anim")

local Prims = {}

Prims.Motion = NeuroAnim.Motion

Prims.DEFAULT_MOTION = { pulse_hz = 2.7 }

Prims.EVIL = {
  A_HAIR = 0.16,
  A_INSET = 0.30,
  A_STRUCT = 0.30,
  A_ACCENT = 0.50,
  A_PLATE = 0.30,
  A_WASH = 0.030,
  A_DIVIDER_MAX = 0.95,
  A_PANE = 0.26,
  PULSE_AMP = 0.20,
}

Prims.now = Utils.now

function Prims.smoothstep01(f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f * f * (3 - 2 * f)
end

function Prims.ease_out_cubic01(f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  local inv = 1 - f
  return 1 - inv * inv * inv
end

function Prims.twinkle01(now, i)
  local t = 0.5 + 0.5 * math.sin(now * (1.1 + (i % 3) * 0.5) + i * 2.399)
  return t * t
end

function Prims.print_tracked(s, x, y, track, f)
  if not s or s == "" then return x end
  for i = 1, #s do
    if s:byte(i) > 127 then love.graphics.print(s, x, y); return x + f:getWidth(s) end
  end
  local cx = x
  for i = 1, #s do
    local ch = s:sub(i, i)
    love.graphics.print(ch, cx, y)
    cx = cx + f:getWidth(ch) + track
  end
  return cx - track
end

function Prims.tracked_width(s, track, f)
  if not s or s == "" then return 0 end
  for i = 1, #s do
    if s:byte(i) > 127 then return f:getWidth(s) end
  end
  local w = 0
  for i = 1, #s do w = w + f:getWidth(s:sub(i, i)) + track end
  return w - track
end

function Prims.candle01(t)
  local f = 0.6 * math.sin(t * 4.3) + 0.25 * math.sin(t * 11.7 + 1.3) + 0.15 * math.sin(t * 23.1)
  if f > 1 then f = 1 elseif f < -1 then f = -1 end
  return 0.5 + 0.5 * f
end


local WHITE_C = { 1, 1, 1 }

local function parse_px(rows)
  local out = { w = #rows[1], h = #rows }
  for ry = 1, #rows do
    local row = rows[ry]
    for rx = 1, #row do
      local ch = row:sub(rx, rx)
      if ch ~= "." then
        out[#out + 1] = rx - 1
        out[#out + 1] = ry - 1
        out[#out + 1] = (ch == "O" and 1) or (ch == "W" and 2) or 0
      end
    end
  end
  return out
end

local BOW_PX = parse_px({
  "XX.........XX",
  "XXXX.....XXXX",
  "XXXX.OOO.XXXX",
  "XXXXXOWOXXXXX",
  "XXXX.OOO.XXXX",
  "XXXX.....XXXX",
  "XX.........XX",
  "....XX.XX....",
  "....XX.XX....",
  "...XX...XX...",
  "...XX...XX...",
  "..XX.....XX..",
})
local BOW_HEAD_PX = parse_px({
  "XX.........XX",
  "XXXX.....XXXX",
  "XXXX.OOO.XXXX",
  "XXXXXOWOXXXXX",
  "XXXX.OOO.XXXX",
  "XXXX.....XXXX",
  "XX.........XX",
})
local BOW_SKULL_PX = parse_px({
  "XX.........XX",
  "XXXX.WWW.XXXX",
  "XXXXWWWWWXXXX",
  "XXXXW.W.WXXXX",
  "XXXXWWWWWXXXX",
  "XXXX.W.W.XXXX",
  "XX.........XX",
  "....XX.XX....",
  "....XX.XX....",
  "...XX...XX...",
  "...XX...XX...",
  "..XX.....XX..",
})
local HEART_PX = parse_px({
  ".XX.XX.",
  "XWXXXXX",
  "XXXXXXX",
  ".XXXXX.",
  "..XXX..",
  "...X...",
})
local SPARK_PX = parse_px({
  "..X..",
  "..X..",
  "XXXXX",
  "..X..",
  "..X..",
})

local DARK_BOW_PX = parse_px({
  "X.X.......X.X",
  "XXX.......XXX",
  "XXXX.OOO.XXXX",
  "XXXXXOWOXXXXX",
  "XXXX.OOO.XXXX",
  "XXX.......XXX",
  "X.X.......X.X",
  "....XX.XX....",
  "....XX.XX....",
  "...XX...XX...",
  "...X.....X...",
  "..OX.....XO..",
})
local DARK_BOW_HEAD_PX = parse_px({
  "X.X.......X.X",
  "XXX.......XXX",
  "XXXX.OOO.XXXX",
  "XXXXXOWOXXXXX",
  "XXXX.OOO.XXXX",
  "XXX.......XXX",
  "X.X.......X.X",
})
local EVIL_HEART_PX = parse_px({
  "O.....O",
  ".O...O.",
  ".XX.XX.",
  "XWXXXXX",
  "XXXXXXX",
  ".XXXXX.",
  "..XXX..",
  "...X...",
})
local HORNS_PX = parse_px({
  "O.......O",
  "OO.....OO",
  ".OO...OO.",
  ".XX...XX.",
  "..XX.XX..",
  "..XXXXX..",
})
local SKULL_PX = parse_px({
  ".OXXXO.",
  "XXXXXXX",
  "XWXXXWX",
  "XXXWXXX",
  ".XXXXX.",
  ".X.X.X.",
})
local GLINT_PX = parse_px({
  "X...X",
  ".O.O.",
  "..W..",
  ".O.O.",
  "X...X",
})
local KNIFE_PX = parse_px({
  ".XXX.",
  ".XXX.",
  ".XXX.",
  "OOOOO",
  ".WWW.",
  ".WWW.",
  "..W..",
  "..W..",
  "..W..",
  "..W..",
})
local EYE_PX = parse_px({
  "..XXXXX..",
  ".XXWOXXX.",
  "XXXXOXXXX",
  ".XXXOXXX.",
  "..XXXXX..",
})
local EYE_SHUT_PX = parse_px({  -- same 9x5 footprint so open/shut center identically
  ".........",
  "X.......X",
  ".XXXXXXX.",
  "..X.X.X..",
  ".........",
})
local EYE_L_PX = parse_px({  -- same footprint
  "..XXXXX..",
  ".XWOXXXX.",
  "XXXOXXXXX",
  ".XXOXXXX.",
  "..XXXXX..",
})
local EYE_R_PX = parse_px({  -- same footprint
  "..XXXXX..",
  ".XXXXWOX.",
  "XXXXXXOXX",
  ".XXXXXOX.",
  "..XXXXX..",
})
local DIAMOND_PX = parse_px({
  "..X..",
  ".XXX.",
  "XXXXX",
  ".XXX.",
  "..X..",
})
local QUATREFOIL_PX = parse_px({
  "...XXX...",
  "..XOOOX..",
  ".XXOOOXX.",
  "XOOXXXOOX",
  "XOOXWXOOX",
  "XOOXXXOOX",
  ".XXOOOXX.",
  "..XOOOX..",
  "...XXX...",
})
local SEAL_PX = parse_px({
  "..XXXX...",
  ".XWXXXXX.",
  "XXOOOOOXX",
  "XXOXXXOXX",
  "XXOXXXOXX",
  "XXOXXXOXX",
  "XXOOOOOXX",
  ".XXXXXXX.",
  "...XXXX..",
})
local FLAME_A_PX = parse_px({
  ".X.",
  ".X.",
  "XXX",
  "XWX",
  "XWX",
})
local FLAME_B_PX = parse_px({
  "..X",
  ".X.",
  "XX.",
  "XWX",
  "XWX",
})
local ROSE_PX = parse_px({
  ".....WWWWW.....",
  "...WWOO.XXWW...",
  "..WOOOO.XXXXW..",
  ".WW.OOO.XXX.WW.",
  ".WXX.OO.XX.OOW.",
  "WXXXX.O.X.OOOOW",
  "WXXXXXWWWOOOOOW",
  "W.....WWW.....W",
  "WOOOOOWWWXXXXXW",
  "WOOOO.X.O.XXXXW",
  ".WOO.XX.OO.XXW.",
  ".WW.XXX.OOO.WW.",
  "..WXXXX.OOOOW..",
  "...WWXX.OOWW...",
  ".....WWWWW.....",
})
local LINK_PX = parse_px({
  ".XX.",
  "X..X",
  "X..X",
  "X..X",
  ".XX.",
})
local PANE_A_PX = parse_px({
  "....X....",
  "...XXX...",
  "..XXXXX..",
  ".XXXXXXX.",
  ".........",
  "XX..O..XX",
  "XX.OOO.XX",
  "X.OOWOO.X",
  "XX.OOO.XX",
  "XX..O..XX",
  ".........",
  "XXXX.XXXX",
  "XXXX.XXXX",
  "XXXX.XXXX",
})
local PANE_B_PX = parse_px({
  "....X....",
  "...XXX...",
  "..XX.XX..",
  ".XXX.XXX.",
  ".........",
  "X.O...O.X",
  "X..O.O..X",
  "XX..W..XX",
  "X..O.O..X",
  "X.O...O.X",
  ".........",
  "XXX.X.XXX",
  "XXX.X.XXX",
  "XXXXXXXXX",
})
local PANE_C_PX = parse_px({
  "....X....",
  "...XXX...",
  "..XXXXX..",
  ".........",
  "XXX.OO.XX",
  "XXX.OO.XX",
  ".........",
  "OO.XX.WW.",
  "OO.XX.WW.",
  ".........",
  "XXX.OO.XX",
  "XXX.OO.XX",
  ".........",
  "XXXXXXXXX",
})
local PANE_PATS = { PANE_A_PX, PANE_B_PX, PANE_C_PX }
local GLASS_X = { 0, 0, 0 }
local GLASS_O = { 0, 0, 0 }
local GLASS_B = { 0, 0, 0 }
local GLASS_W = { 1, 0.93, 0.72 }

local function draw_px(pat, cx, cy, s, col, a, col2, colw, shadow)
  local x0 = math.floor(cx - pat.w * s / 2 + 0.5)
  local y0 = math.floor(cy - pat.h * s / 2 + 0.5)
  if shadow then
    love.graphics.setColor(0, 0, 0, 0.55 * a)
    for i = 1, #pat, 3 do
      love.graphics.rectangle("fill", x0 + pat[i] * s + 1, y0 + pat[i + 1] * s + 1, s, s)
    end
  end
  for i = 1, #pat, 3 do
    local f = pat[i + 2]
    local c = (f == 1 and col2) or (f == 2 and (colw or WHITE_C)) or col
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.rectangle("fill", x0 + pat[i] * s, y0 + pat[i + 1] * s, s, s)
  end
end

function Prims.draw_bow(cx, cy, u, col, a, col2)
  draw_px(BOW_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), col, a, col2)
end

function Prims.draw_bow_mini(cx, cy, u, col, a, col2)
  draw_px(BOW_HEAD_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), col, a, col2)
end

function Prims.draw_heart(cx, cy, r, col, a)
  draw_px(HEART_PX, cx, cy, math.max(1, math.floor(r / 3 + 0.5)), col, a)
end

local BOW_WINE = { 0.45, 0.09, 0.13 }
local EYE_PUPIL = { 0.06, 0.01, 0.02 }
local SKULL_SOCK = { 0.05, 0.01, 0.02 }
local FLAME_HOT = { 1, 0.95, 0.75 }
local SEAL_WAX = { 0.34, 0.035, 0.065 }
local SEAL_HI = { 1, 0.92, 0.85 }

function Prims.draw_dark_bow(cx, cy, u, acc, a, gold, shadow, body)
  draw_px(DARK_BOW_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), body or BOW_WINE, a, acc, gold, shadow)
end

function Prims.draw_dark_bow_mini(cx, cy, u, acc, a, gold, shadow, body)
  draw_px(DARK_BOW_HEAD_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), body or BOW_WINE, a, acc, gold, shadow)
end

function Prims.draw_evil_heart(cx, cy, r, acc, a, gold, shadow)
  draw_px(EVIL_HEART_PX, cx, cy, math.max(1, math.floor(r / 3 + 0.5)), acc, a, gold, nil, shadow)
end

function Prims.draw_horns(cx, cy, r, acc, a, gold, shadow)
  draw_px(HORNS_PX, cx, cy, math.max(1, math.floor(r / 3 + 0.5)), acc, a, gold, nil, shadow)
end

function Prims.draw_skull(cx, cy, r, col, a, gold, shadow)
  draw_px(SKULL_PX, cx, cy, math.max(1, math.floor(r / 3 + 0.5)), col, a, gold, SKULL_SOCK, shadow)
end

function Prims.corner_brand(cx, cy, u, crimson, bone, a, shadow)
  draw_px(BOW_SKULL_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), crimson, a, nil, bone, shadow)
end

function Prims.draw_glint(cx, cy, r, acc, a, gold, shadow)
  draw_px(GLINT_PX, cx, cy, math.max(1, math.floor(r / 2 + 0.5)), acc, a, gold, nil, shadow)
end

function Prims.draw_knife(cx, cy, u, gold, silver, a, shadow)
  draw_px(KNIFE_PX, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), BOW_WINE, a, gold, silver, shadow)
end

-- look: -1/0/1 glances the pupil left/center/right (blink wins); hold: never blink
function Prims.draw_evil_eye(cx, cy, u, acc, a, now, reduced, shadow, look, hold)
  local pat = EYE_PX
  if not reduced and not hold and (now % 4.7) < 0.12 then pat = EYE_SHUT_PX
  elseif look and look < 0 then pat = EYE_L_PX
  elseif look and look > 0 then pat = EYE_R_PX end
  draw_px(pat, cx, cy, math.max(1, math.floor(u * 1.5 + 0.5)), acc, a, EYE_PUPIL, nil, shadow)
end

function Prims.draw_diamond(cx, cy, u, col, a, shadow)
  draw_px(DIAMOND_PX, cx, cy, math.max(1, math.floor(u * 0.75 + 0.5)), col, a, nil, nil, shadow)
end

function Prims.gothic_frame(x, y, w, h, u, gold, frd, a, rad, pulse)
  if w < u * 40 or h < u * 24 then return end
  rad = rad or 0
  pulse = pulse or 0.5
  local E = Prims.EVIL
  love.graphics.setLineWidth(1)
  love.graphics.setColor(gold[1], gold[2], gold[3], E.A_HAIR * a)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
  love.graphics.setColor(frd[1], frd[2], frd[3], E.A_INSET * a)
  local i3 = u * 3
  local ir = math.max(0, rad - u * 2)
  love.graphics.rectangle("line", x + i3, y + i3, w - i3 * 2, h - i3 * 2, ir, ir)
  love.graphics.setColor(gold[1], gold[2], gold[3], 0.10 * a)
  love.graphics.rectangle("fill", x + rad + 1, y + 1, w - rad * 2 - 2, 1)
  if rad > 0 then return end
  love.graphics.setColor(gold[1], gold[2], gold[3], E.A_STRUCT * a)
  local c2 = u * 2
  for sx2 = 0, 1 do
    for sy2 = 0, 1 do
      for i = 0, 2 do
        local sx = u * (1 + i * 2)
        local sy = u * (5 - i * 2)
        local mx = sx2 == 0 and (x + sx) or (x + w - sx - c2)
        local my = sy2 == 0 and (y + sy) or (y + h - sy - c2)
        love.graphics.rectangle("fill", mx, my, c2, c2)
      end
    end
  end
  local sa = (E.A_ACCENT + E.PULSE_AMP * pulse) * a
  Prims.draw_diamond(x + u * 8, y + u * 8, u, gold, sa)
  Prims.draw_diamond(x + w - u * 8, y + u * 8, u, gold, sa)
  Prims.draw_diamond(x + u * 8, y + h - u * 8, u, gold, sa)
  Prims.draw_diamond(x + w - u * 8, y + h - u * 8, u, gold, sa)
end

-- y is the baseline
function Prims.evil_divider(x, y, w, u, acc, gold, a, pulse, weight, no_center, ignite01)
  a = a or 1
  pulse = pulse or 0.5
  weight = weight or 2
  local E = Prims.EVIL
  local segs = 4
  local segw = math.ceil(w / (segs * 2))
  for i = 0, segs - 1 do
    local ik = ignite01 and Prims.smoothstep01((ignite01 - (segs - 1 - i) * 0.18) / 0.35) or 1
    local aa = (0.30 + (E.A_DIVIDER_MAX - 0.30) * (i + 1) / segs) * (0.85 + 0.10 * pulse) * ik * a
    local hh = (i == 0) and 1 or weight
    love.graphics.setColor(acc[1], acc[2], acc[3], aa)
    love.graphics.rectangle("fill", x + i * segw, y - hh, segw, hh)
    love.graphics.rectangle("fill", x + w - (i + 1) * segw, y - hh, segw, hh)
  end
  if no_center then return end
  Prims.quatrefoil(x + math.floor(w / 2), y - 1, u * 5, gold, a, pulse)
end

function Prims.plate_label(x, y, w, h, gold, a, rivets, fill_a)
  a = a or 1
  love.graphics.setColor(0, 0, 0, (fill_a or 0.35) * a)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(gold[1], gold[2], gold[3], Prims.EVIL.A_PLATE * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  if rivets then
    local my = y + math.floor(h / 2)
    local ru = math.max(1, math.floor(h / 8))
    Prims.draw_diamond(x, my, ru, gold, 0.90 * a)
    Prims.draw_diamond(x + w, my, ru, gold, 0.90 * a)
  end
end

function Prims.candle_finial(cx, base_y, u, gold, a, now, reduced, flare)
  a = a or 1
  flare = flare or 0
  cx, base_y = math.floor(cx + 0.5), math.floor(base_y + 0.5)
  local bw, bh = u * 4, u * 7
  love.graphics.setColor(0.46, 0.06, 0.09, 0.95 * a)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh, bw, bh)
  love.graphics.setColor(0.72, 0.16, 0.16, 0.90 * a)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh, bw, u)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh + u, u, u * 3)   -- drip down the side
  local flick = reduced and 0.5 or Prims.candle01(now + cx * 0.13)
  local fy = base_y - bh - u
  love.graphics.setColor(1, 0.95, 0.85, 0.95 * a)
  love.graphics.rectangle("fill", cx - math.floor(u / 2), fy, u, u)        -- wick
  local gr = u * 6 + math.floor(u * 4 * flare)
  love.graphics.setColor(gold[1], gold[2], gold[3], (0.05 + 0.04 * flick + 0.08 * flare) * a)
  love.graphics.rectangle("fill", cx - gr, fy - u * 4 - gr, gr * 2, gr * 2)
  local gr2 = math.floor(gr * 0.55)
  love.graphics.setColor(gold[1], gold[2], gold[3], (0.08 + 0.05 * flick + 0.10 * flare) * a)
  love.graphics.rectangle("fill", cx - gr2, fy - u * 4 - gr2, gr2 * 2, gr2 * 2)
  local s = math.max(1, math.floor(u * (1 + 0.5 * flick + 0.8 * flare) + 0.5))
  local pat = (flick > 0.5) and FLAME_A_PX or FLAME_B_PX
  draw_px(pat, cx, fy - s * 2, s, gold, (0.85 + 0.10 * flick) * a, nil, FLAME_HOT)
end

function Prims.ash_motes(x, y, w, h, u, now, reduced, a, n)
  if reduced or w < u * 20 or h < u * 8 then return end
  n = n or 5
  for mi = 1, n do
    local sp = (4 + (mi % 3) * 2) * u
    local yr = (now * sp + mi * 61.7 * u) % h
    local mx = x + (0.5 + 0.5 * math.sin(mi * 12.9898)) * w + math.sin(now * 0.8 + mi * 2.1) * u * 3
    local my = y + h - yr
    local tw = Prims.twinkle01(now, mi)
    local env = math.min(1, yr / (h * 0.15)) * math.min(1, (h - yr) / (h * 0.25))
    local aa = (0.35 + 0.50 * tw) * env * a
    local sz = math.max(2, (mi % 4 == 0) and u * 3 or u * 2)
    if mi % 2 == 0 and mi % 4 ~= 0 then
      love.graphics.setColor(0.88, 0.34, 0.16, aa)
    else
      love.graphics.setColor(0.70, 0.18, 0.16, aa)
    end
    love.graphics.rectangle("fill", math.floor(mx + 0.5), math.floor(my + 0.5), sz, sz)
  end
end

function Prims.seal_after(end_x, cy, u, gold, a, pulse, r)
  r = r or u * 3
  local cx = end_x + u * 5
  Prims.wax_seal(cx, cy, r, u, gold, a, pulse)
  return cx + r
end

function Prims.ember_bloom(cx, cy, r, u, t01, gold, a, reduced)
  if reduced or t01 <= 0 or t01 >= 1 then return end
  a = a or 1
  local env = math.sin(math.pi * t01)
  cx, cy = math.floor(cx + 0.5), math.floor(cy + 0.5)
  for _, rf in ipairs({ { 1, 0.05 }, { 0.62, 0.08 }, { 0.34, 0.13 } }) do
    local rr = math.floor(r * rf[1] + 0.5)
    love.graphics.setColor(gold[1], gold[2], gold[3], rf[2] * env * a)
    love.graphics.rectangle("fill", cx - rr, cy - rr, rr * 2, rr * 2)
  end
  local rise = Prims.ease_out_cubic01(t01)
  for ei = 1, 5 do
    local xr = math.sin(ei * 12.9898)
    local ex = math.floor(cx + xr * r * 0.7 + math.sin(t01 * 5 + ei * 1.7) * u * 2 + 0.5)
    local ey = math.floor(cy - rise * (r * (0.7 + 0.3 * math.abs(math.sin(ei * 78.233)))) + 0.5)
    local gg = 0.62 - 0.40 * rise
    love.graphics.setColor(1, gg, 0.16, (1 - t01) * 0.85 * a)
    love.graphics.rectangle("fill", ex, ey, (ei % 3 == 0) and u * 2 or u, (ei % 3 == 0) and u * 2 or u)
  end
end

function Prims.panel_shell(x, y, w, h, rad, sh_dx, sh_dy, sh_a, bg, bg_a)
  love.graphics.setColor(0, 0, 0, sh_a)
  love.graphics.rectangle("fill", x + sh_dx, y + sh_dy, w, h, rad, rad)
  love.graphics.setColor(bg[1], bg[2], bg[3], bg_a)
  love.graphics.rectangle("fill", x, y, w, h, rad, rad)
end

function Prims.panel_base(x, y, w, h, rad, sh, a, bg, frame)
  Prims.panel_shell(x, y, w, h, rad, sh, sh, 0.55 * a, bg, 0.97 * a)
  love.graphics.setColor(frame[1], frame[2], frame[3], 0.90 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
end

function Prims.neuro_frame_deco(x, y, w, h, prad, u, th, ACC, GLOW, shr, shg, shb, a, skip_body)
  a = a or 1
  love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.035 * a)
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, th, prad, prad)
  if not skip_body then
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.018 * a)
    love.graphics.rectangle("fill", x + 1, y + th, w - 2, u * 16)
    love.graphics.setColor(ACC[1], ACC[2], ACC[3], 0.02 * a)
    love.graphics.rectangle("fill", x + prad, y + math.floor(h * 0.55), w - prad * 2, math.floor(h * 0.15))
    love.graphics.setColor(ACC[1], ACC[2], ACC[3], 0.04 * a)
    love.graphics.rectangle("fill", x + prad, y + math.floor(h * 0.70), w - prad * 2, math.floor(h * 0.30) - 2)
  end
  love.graphics.setColor(shr, shg, shb, 0.16 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 1, y - 1, w + 2, h + 2, prad + 1, prad + 1)
  love.graphics.setColor(shr, shg, shb, 0.08 * a)
  love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4, prad + 2, prad + 2)
  love.graphics.setColor(shr, shg, shb, 0.20 * a)
  local ir = math.max(2, prad - u * 3)
  love.graphics.rectangle("line", x + u * 3, y + u * 3, w - u * 6, h - u * 6, ir, ir)
  love.graphics.setColor(1, 1, 1, 0.07 * a)
  love.graphics.rectangle("fill", x + prad, y + 1, w - prad * 2, 1)
end

function Prims.evil_frame_deco(x, y, w, _h, u, th, GOLD, GLOW, pulse, _now, _reduced, cxf, a, flare)
  a = a or 1
  cxf = cxf or 0.30
  local gcx = x + math.floor(w * cxf)
  local gcy = y + math.floor(th * 0.55)
  local grx = math.floor(w * 0.30)
  local gry = math.floor(th * 0.85)
  local gk = (0.8 + 0.2 * pulse + 0.6 * (flare or 0)) * a
  love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.020 * gk)
  love.graphics.ellipse("fill", gcx, gcy, grx, gry)
  love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.030 * gk)
  love.graphics.ellipse("fill", gcx, gcy, math.floor(grx * 0.66), math.floor(gry * 0.7))
  love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.045 * gk)
  love.graphics.ellipse("fill", gcx, gcy, math.floor(grx * 0.38), math.floor(gry * 0.5))
  if _h > th * 2 then
    local bcx = x + math.floor(w / 2)
    local bcy = y + _h
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.016 * gk)
    love.graphics.ellipse("fill", bcx, bcy, math.floor(w * 0.5), math.floor(_h * 0.42))
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.022 * gk)
    love.graphics.ellipse("fill", bcx, bcy, math.floor(w * 0.30), math.floor(_h * 0.24))
  end
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.08 * a)
  love.graphics.rectangle("fill", x + u * 4, y + 1, w - u * 8, 1)
end

function Prims.counter_glow(x, y, w, h, col, a, pulse, rad)
  pulse = pulse or 0.5
  rad = rad or 0
  local gk = (0.75 + 0.25 * pulse) * (a or 1)
  local base_y = y + h
  for i = 1, 3 do
    local bh = math.floor(h * (0.10 + i * 0.06))
    love.graphics.setColor(col[1], col[2], col[3], (0.05 - i * 0.012) * gk)
    love.graphics.rectangle("fill", x + 1, base_y - bh, w - 2, bh, rad, rad)
  end
end

function Prims.wax_seal(cx, cy, r, _u, gold, a, pulse, drip)
  pulse = pulse or 0.5
  cx, cy = math.floor(cx + 0.5), math.floor(cy + 0.5)
  local s = math.max(1, math.floor(r * 2 / 9 + 0.5))
  if drip then
    local dl = math.floor(s * (2 + 2 * pulse) + 0.5)
    love.graphics.setColor(0.29, 0.030, 0.055, 0.95 * a)
    love.graphics.rectangle("fill", cx + s, cy + s * 4, s, dl)
    love.graphics.rectangle("fill", cx + s, cy + s * 4 + dl, s, s)
  end
  draw_px(SEAL_PX, cx, cy, s, SEAL_WAX, 0.95 * a, gold, SEAL_HI, true)
end

function Prims.awning(x, y, w, u, cA, cB, a)
  if w < u * 14 then return end
  local band = math.max(4, u * 5)
  local n = math.max(4, math.floor(w / (u * 12)))
  local sw = w / n
  local r = sw / 2
  local top_h = math.ceil(band / 2)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.20 * a)
  for i = 0, n - 1 do
    love.graphics.arc("fill", "pie", x + (i + 0.5) * sw, y + band + u, r, 0, math.pi)
  end
  for i = 0, n - 1 do
    local c = (i % 2 == 0) and cA or cB
    local cr2 = c[1] * 0.55 + 0.45
    local cg2 = c[2] * 0.55 + 0.45
    local cb2 = c[3] * 0.55 + 0.45
    local sx0 = x + i * sw
    local scx = sx0 + r
    love.graphics.setColor(math.min(1, cr2 * 1.10), math.min(1, cg2 * 1.10), math.min(1, cb2 * 1.10), 0.62 * a)
    love.graphics.rectangle("fill", sx0, y, sw, top_h)
    love.graphics.setColor(cr2, cg2, cb2, 0.62 * a)
    love.graphics.rectangle("fill", sx0, y + top_h, sw, band - top_h)
    love.graphics.arc("fill", "pie", scx, y + band, r, 0, math.pi)
    love.graphics.setColor(cr2 * 0.45, cg2 * 0.45, cb2 * 0.55, 0.55 * a)
    love.graphics.arc("line", "open", scx, y + band, r - 0.5, 0.12, math.pi - 0.12)
    love.graphics.setColor(1, 1, 1, 0.20 * a)
    love.graphics.arc("line", "open", scx, y + band, r - 1.5, math.pi * 0.58, math.pi * 0.86)
  end
  love.graphics.setColor(1, 1, 1, 0.32 * a)
  for i = 0, n - 1 do
    love.graphics.arc("line", "open", x + (i + 0.5) * sw, y + band, r, 0.10, math.pi - 0.10)
  end
  love.graphics.setColor(1, 1, 1, 0.55 * a)
  for i = 0, n - 1 do
    love.graphics.circle("fill", x + (i + 0.5) * sw, y + band + r - 1, math.max(1, u * 0.8))
  end
  love.graphics.setColor(1, 1, 1, 0.14 * a)
  local dash = math.max(2, u * 2)
  local dx2 = x + u
  while dx2 < x + w - u do
    love.graphics.rectangle("fill", dx2, y + band - 2, math.min(dash, x + w - u - dx2), 1)
    dx2 = dx2 + dash * 2
  end
  love.graphics.setColor(1, 1, 1, 0.30 * a)
  love.graphics.rectangle("fill", x, y, w, 1)
  love.graphics.setColor(1, 1, 1, 0.10 * a)
  love.graphics.rectangle("fill", x, y + 1, w, 1)
end

function Prims.tag_string(x, y, w, u, r, g, b, a)
  love.graphics.setColor(r, g, b, 0.85 * a)
  local dash = math.max(2, u * 2)
  local dx = x
  while dx < x + w do
    love.graphics.rectangle("fill", dx, y, math.min(dash, x + w - dx), 1)
    dx = dx + dash * 2
  end
end
function Prims.quatrefoil(cx, cy, r, gold, a, pulse)
  pulse = pulse or 0.5
  local s = math.max(1, math.floor(r * 2 / 9 + 0.5))
  draw_px(QUATREFOIL_PX, cx, cy, s, gold, (0.80 + Prims.EVIL.PULSE_AMP * pulse) * a, BOW_WINE)
end

function Prims.stained_glass_band(x, y, w, h, u, gold, c1, c2, c3, a, pulse, now, flare)
  if w < u * 60 or h < u * 10 then return end
  pulse = pulse or 0.5
  flare = flare or 0
  x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
  local E = Prims.EVIL
  local cols = { c1, c2, c3 }
  local gk = (0.9 + 0.1 * pulse) * a
  local border_h = u * 3
  local glass_h = h - border_h - 5
  local s = math.max(1, math.floor(glass_h / 14))
  local n = math.max(4, math.min(12, math.floor(w / (9 * s + u * 6))))
  local mid = math.floor(n / 2)
  local sel, selk = -1, 0
  if now and not Prims.Motion.reduced then
    sel = math.floor(now * 0.4) % n
    selk = math.sin(math.pi * ((now * 0.4) % 1)) * 0.12
  end
  local fits = (9 * s + 2) <= math.floor(w / n)
  local x0 = x
  for i = 0, n - 1 do
    local x1 = x + math.floor((i + 1) * w / n)
    local pw = x1 - x0
    local c = cols[(i * 2 + 1) % 3 + 1]
    love.graphics.setColor(c[1], c[2], c[3], (0.22 + 0.10 * flare) * gk)
    love.graphics.rectangle("fill", x0 + 1, y + 2, pw - 2, h - 3)
    if fits then
      GLASS_X[1], GLASS_X[2], GLASS_X[3] = c[1] * 0.70 + 0.18, c[2] * 0.70 + 0.18, c[3] * 0.70 + 0.18
      GLASS_O[1], GLASS_O[2], GLASS_O[3] = c[1] * 0.55 + 0.45, c[2] * 0.55 + 0.45, c[3] * 0.55 + 0.45
      local aX = 0.50 * gk
      local aL = (i == sel and selk or 0) + 0.25 * flare
      local aO = (0.60 + aL) * gk
      local aW = (0.55 + aL) * gk
      local pat = PANE_PATS[i % 3 + 1]
      local ox = x0 + 1 + math.floor((pw - 2 - 9 * s) / 2)
      local oy = y + 2 + (glass_h - 14 * s)
      for k = 1, #pat, 3 do
        local py2, cls = pat[k + 1], pat[k + 2]
        local lit = (py2 >= 5 and py2 <= 9) and 1.15 or 1
        if cls == 0 then
          love.graphics.setColor(math.min(1, GLASS_X[1] * lit), math.min(1, GLASS_X[2] * lit),
            math.min(1, GLASS_X[3] * lit), aX)
        elseif cls == 1 then
          love.graphics.setColor(math.min(1, GLASS_O[1] * lit), math.min(1, GLASS_O[2] * lit),
            math.min(1, GLASS_O[3] * lit), aO)
        else
          love.graphics.setColor(GLASS_W[1], GLASS_W[2], GLASS_W[3], aW)
        end
        love.graphics.rectangle("fill", ox + pat[k] * s, oy + py2 * s, s, s)
      end
      if i == mid then
        draw_px(QUATREFOIL_PX, ox + math.floor(4.5 * s), oy + math.floor(8.5 * s), s,
          gold, (0.70 + 0.20 * flare) * gk, BOW_WINE)
      end
    end
    x0 = x1
  end
  GLASS_B[1], GLASS_B[2], GLASS_B[3] = c1[1] * 0.55 + 0.45, c1[2] * 0.55 + 0.45, c1[3] * 0.55 + 0.45
  local by0 = y + h - border_h - 1
  love.graphics.setColor(0, 0, 0, 0.55 * a)
  love.graphics.rectangle("fill", x + 1, by0 - 1, w - 2, 1)
  local cell = u * 8
  local bx, ci = x + 1, 0
  while bx < x + w - 1 do
    local cw = math.min(cell, x + w - 1 - bx)
    if ci % 2 == 0 then
      love.graphics.setColor(gold[1], gold[2], gold[3], 0.40 * gk)
    else
      love.graphics.setColor(GLASS_B[1], GLASS_B[2], GLASS_B[3], (0.50 + 0.15 * flare) * gk)
    end
    love.graphics.rectangle("fill", bx, by0, cw - 1, border_h)
    bx = bx + cell
    ci = ci + 1
  end
  local uh = math.floor(u / 2)
  for i = 1, n - 1 do
    local mx = x + math.floor(i * w / n)
    love.graphics.setColor(0, 0, 0, 0.55 * a)
    love.graphics.rectangle("fill", mx - uh - 1, y + 2, 1, h - 3)
    love.graphics.rectangle("fill", mx - uh + u, y + 2, 1, h - 3)
    love.graphics.setColor(gold[1], gold[2], gold[3], E.A_ACCENT * a)
    love.graphics.rectangle("fill", mx - uh, y + 2, u, h - 3)
    love.graphics.setColor(gold[1], gold[2], gold[3], 0.80 * a)
    love.graphics.rectangle("fill", mx - 1, y + 1, 2, 2)
    love.graphics.rectangle("fill", mx - 1, y + h - 3, 2, 2)
  end
  love.graphics.setColor(0, 0, 0, 0.50 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y + 1, w, h - 1)
  love.graphics.setColor(gold[1], gold[2], gold[3], E.A_ACCENT * a)
  love.graphics.rectangle("fill", x, y + h - 1, w, 1)
end

-- alphas stay in the wash band so body text reads over it
function Prims.rose_medallion(cx, cy, r, u, gold, c1, c2, a, pulse)
  if r < u * 14 then return end
  pulse = pulse or 0.5
  local s = math.max(1, math.floor(r * 2 / 15 + 0.5))
  draw_px(ROSE_PX, math.floor(cx + 0.5), math.floor(cy + 0.5), s, c1, (0.07 + 0.02 * pulse) * a, c2, gold)
end

function Prims.cornice_crenel(x, y, w, u, bg, gold, a)
  local ch = u * 4
  love.graphics.setColor(bg[1], bg[2], bg[3], 0.97 * a)
  love.graphics.rectangle("fill", x, y - 2, w, 2)
  love.graphics.setColor(gold[1], gold[2], gold[3], Prims.EVIL.A_HAIR * a)
  love.graphics.rectangle("fill", x, y - 1, w, 1)
  local pitch = u * 12
  local mw = u * 6
  local n = math.floor(w / pitch)
  if n < 2 then return end
  local x0 = x + math.floor((w - (n - 1) * pitch - mw) / 2)
  for i = 0, n - 1 do
    local mx = x0 + i * pitch
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.97 * a)
    love.graphics.rectangle("fill", mx, y - ch, mw, ch)
    love.graphics.setColor(gold[1], gold[2], gold[3], Prims.EVIL.A_ACCENT * a)
    love.graphics.rectangle("fill", mx, y - ch, mw, 1)
    love.graphics.setColor(0, 0, 0, 0.30 * a)
    love.graphics.rectangle("fill", mx, y - ch + 1, mw, 1)
  end
end

-- pitch matches cornice_crenel
function Prims.bottom_dags(x, y, w, u, bg, gold, a)
  local pitch = u * 12
  local dw = u * 6
  local n = math.floor(w / pitch)
  if n < 2 then return end
  local x0 = x + math.floor((w - (n - 1) * pitch - dw) / 2)
  local ga = Prims.EVIL.A_STRUCT * a
  for i = 0, n - 1 do
    local dx2 = x0 + i * pitch
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.97 * a)
    love.graphics.rectangle("fill", dx2, y, dw, u * 2)
    love.graphics.rectangle("fill", dx2 + u, y + u * 2, dw - u * 2, u * 2)
    love.graphics.rectangle("fill", dx2 + u * 2, y + u * 4, dw - u * 4, u)
    love.graphics.setColor(gold[1], gold[2], gold[3], ga)
    love.graphics.rectangle("fill", dx2, y + u * 2 - 1, u, 1)
    love.graphics.rectangle("fill", dx2 + dw - u, y + u * 2 - 1, u, 1)
    love.graphics.rectangle("fill", dx2 + u, y + u * 4 - 1, u, 1)
    love.graphics.rectangle("fill", dx2 + dw - u * 2, y + u * 4 - 1, u, 1)
    love.graphics.rectangle("fill", dx2 + u * 2, y + u * 5 - 1, dw - u * 4, 1)
    love.graphics.setColor(0, 0, 0, 0.25 * a)
    love.graphics.rectangle("fill", dx2, y, dw, 1)
  end
end

function Prims.ogive_top(x, y, w, u, gold, a, pulse)
  pulse = pulse or 0.5
  x, y, w = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5)
  local E = Prims.EVIL
  local rise = math.min(u * 8, math.floor(w * 0.35))
  local steps = 4
  local sh = math.max(1, math.floor(rise / steps))
  local half = math.floor(w / 2)
  local wprev = half
  for i = 0, steps - 1 do
    local wi = math.floor(half * (steps - 1 - i) / steps)
    love.graphics.setColor(0, 0, 0, 0.35 * a)
    love.graphics.rectangle("fill", x, y + i * sh, wi, sh)
    love.graphics.rectangle("fill", x + w - wi, y + i * sh, wi, sh)
    love.graphics.setColor(gold[1], gold[2], gold[3], E.A_STRUCT * a)
    if wi > 0 then
      love.graphics.rectangle("fill", x + wi, y + i * sh, 1, sh)
      love.graphics.rectangle("fill", x + w - wi - 1, y + i * sh, 1, sh)
    end
    if wprev > wi then
      love.graphics.rectangle("fill", x + wi, y + i * sh, wprev - wi, 1)
      love.graphics.rectangle("fill", x + w - wprev, y + i * sh, wprev - wi, 1)
    end
    wprev = wi
  end
  Prims.draw_diamond(x + half, y - u * 3, u, gold, (E.A_ACCENT + E.PULSE_AMP * pulse) * a)
end

function Prims.pilaster(x, y0, y1, u, gold, frd, a)
  if y1 - y0 < u * 20 then return end
  x, y0, y1 = math.floor(x + 0.5), math.floor(y0 + 0.5), math.floor(y1 + 0.5)
  local E = Prims.EVIL
  love.graphics.setColor(gold[1], gold[2], gold[3], E.A_HAIR * a)
  love.graphics.rectangle("fill", x - 1, y0 + u * 3, 1, y1 - y0 - u * 5)
  love.graphics.setColor(frd[1], frd[2], frd[3], 0.50 * a)
  love.graphics.rectangle("fill", x + 1, y0 + u * 3, 1, y1 - y0 - u * 5)
  love.graphics.setColor(gold[1], gold[2], gold[3], E.A_STRUCT * a)
  love.graphics.rectangle("fill", x - u, y0, u * 2, u)
  love.graphics.rectangle("fill", x - u * 2, y0 + u, u * 4, u * 2)
  love.graphics.rectangle("fill", x - u * 2, y1 - u * 2, u * 4, u * 2)
end

function Prims.chains(x, y0, y1, u, gold, a, sway)
  sway = sway or 0
  local s = math.max(1, math.floor(u / 2 + 0.5))
  local lh = s * 4   -- link is 5 tall; stride 4 overlaps 1px so links interlock
  local n = math.max(2, math.floor((y1 - y0) / lh))
  local la = 0.60 * a
  for i = 0, n - 1 do
    local t = i / n
    local lx = math.floor(x + sway * t + 0.5)
    local ly = math.floor(y0 + lh * i + 0.5)
    draw_px(LINK_PX, lx, ly + s * 2, s, gold, la)
  end
  love.graphics.setColor(gold[1], gold[2], gold[3], 0.80 * a)
  love.graphics.rectangle("fill", math.floor(x + 0.5) - 1, math.floor(y0 + 0.5) - 1, 2, 2)
  love.graphics.rectangle("fill", math.floor(x + sway + 0.5) - 1, math.floor(y1 + 0.5) - 1, 2, 2)
end

function Prims.draw_sparkle(cx, cy, r, col, a)
  draw_px(SPARK_PX, cx, cy, math.max(1, math.floor(r / 2 + 0.5)), col, a)
end

function Prims.embers(x, y, w, h, u, now, reduced, a, n)
  if reduced or h < u * 20 then return end
  n = n or 7
  for ei = 1, n do
    local sp = (14 + (ei % 4) * 5.5) * u
    local yr = (now * sp + ei * 97.3 * u) % h
    local ex = x + (0.5 + 0.5 * math.sin(ei * 12.9898)) * w + math.sin(now * 1.6 + ei * 1.7) * u * 4
    local ey = y + h - yr
    local rise = yr / h
    local flick = 0.5 + 0.5 * math.sin(now * (6 + ei % 3) + ei * 2.4)
    local aa = (1 - rise * 0.8) * (0.45 + 0.50 * flick) * a
    local gg = 0.62 - 0.45 * rise
    local bb = 0.18 - 0.14 * rise
    local sz = (ei % 3 == 0) and u * 2 or u
    love.graphics.setColor(1, gg, bb, aa)
    love.graphics.rectangle("fill", ex, ey, sz, sz)
    love.graphics.setColor(1, gg * 0.7, bb, aa * 0.35)
    love.graphics.rectangle("fill", ex, ey + sz, sz, sz)
  end
end

function Prims.photo_corners(x, y, w, h, col, a, arm)
  arm = arm or 3
  love.graphics.setColor(col[1], col[2], col[3], a)
  love.graphics.setLineWidth(1)
  local x1, y1 = x + w, y + h
  love.graphics.line(x, y + arm, x, y, x + arm, y)
  love.graphics.line(x1 - arm, y, x1, y, x1, y + arm)
  love.graphics.line(x, y1 - arm, x, y1, x + arm, y1)
  love.graphics.line(x1 - arm, y1, x1, y1, x1, y1 - arm)
end

function Prims.confetti_burst(cx, cy, progress, radius, sz, phase, pg, acc, a)
  local fade = (1 - progress) * 0.9 * a
  local pr = progress * radius
  for i = 0, 7 do
    local ang = i * 0.785 + (phase or 0.6)
    local px = cx + math.cos(ang) * pr
    local py = cy + math.sin(ang) * pr
    if i % 2 == 0 then Prims.draw_sparkle(px, py, sz, pg, fade)
    else Prims.draw_heart(px, py, sz, acc, fade) end
  end
end

function Prims.niche(x, y, w, h, u, gold, glow, pulse, a, arch)
  a = a or 1
  pulse = pulse or 0.5
  love.graphics.setColor(0, 0, 0, 0.45 * a)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(glow[1], glow[2], glow[3], 0.05 * a)
  love.graphics.rectangle("fill", x, y + math.floor(h * 0.45), w, math.ceil(h * 0.55))
  Prims.counter_glow(x, y, w, h, gold, 0.9 * a, pulse, 0)
  love.graphics.setColor(gold[1], gold[2], gold[3], 0.22 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  if arch then Prims.ogive_top(x, y, w, u, gold, a, pulse) end
end

function Prims.card_sleeve(x, y, w, h, u, acc, glow, shr, shg, shb, a)
  a = a or 1
  local rad = math.max(2, u * 3)
  love.graphics.setColor(glow[1], glow[2], glow[3], 0.06 * a)
  love.graphics.rectangle("fill", x, y, w, h, rad, rad)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.05 * a)
  love.graphics.rectangle("fill", x, y + math.floor(h * 0.6), w, math.ceil(h * 0.4), rad, rad)
  love.graphics.setColor(shr, shg, shb, 0.45 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
  love.graphics.setColor(shr, shg, shb, 0.18 * a)
  local ir = math.max(1, rad - u)
  love.graphics.rectangle("line", x + u, y + u, w - u * 2, h - u * 2, ir, ir)
  love.graphics.setColor(1, 1, 1, 0.08 * a)
  love.graphics.rectangle("fill", x + rad, y + 1, w - rad * 2, 1)
end

Prims.NEURO_PERSONA = dotenv.normalize_persona(dotenv.get("NEURO_PERSONA"))

return Prims
