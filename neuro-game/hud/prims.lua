local Utils = require("util.utils")
local NeuroAnim = require("render.neuro-anim")
local gfx = require("render.gfx")
local RectMesh = require("render.rect_mesh")
local set_col = gfx.set_col

local Prims = {}

Prims.Motion = NeuroAnim.Motion

Prims.EVIL = {
  A_HAIR = 0.16,
  A_INSET = 0.30,
  A_STRUCT = 0.30,
  A_ACCENT = 0.50,
  A_PLATE = 0.30,
  A_WASH = 0.030,
  A_DIVIDER_MAX = 0.95,
  PULSE_AMP = 0.20,
}

Prims.now = Utils.now

local round = gfx.round
Prims.round = gfx.round
Prims.set_col = gfx.set_col
Prims.shadow_text = gfx.shadow_text
Prims.clamp = gfx.clamp
Prims.clamp01 = gfx.clamp01

function Prims.smoothstep01(f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f * f * (3 - 2 * f)
end

function Prims.quant_alpha(f)
  return math.floor(f * 20 + 0.5) / 20
end

Prims.ease_out_cubic01 = Prims.Motion.ease_out_cubic

function Prims.twinkle01(now, i)
  local t = 0.5 + 0.5 * math.sin(now * (1.1 + (i % 3) * 0.5) + i * 2.399)
  return t * t
end

local CHR = {}
for b = 0, 127 do CHR[b] = string.char(b) end
local _char_w = setmetatable({}, { __mode = "k" })
local function char_width(f, b)
  local per = _char_w[f]
  if not per then per = {}; _char_w[f] = per end
  local w = per[b]
  if not w then w = f:getWidth(CHR[b]); per[b] = w end
  return w
end

function Prims.print_tracked(s, x, y, track, f)
  if not s or s == "" then return x end
  for i = 1, #s do
    if s:byte(i) > 127 then love.graphics.print(s, x, y); return x + f:getWidth(s) end
  end
  local cx = x
  for i = 1, #s do
    local b = s:byte(i)
    love.graphics.print(CHR[b], cx, y)
    cx = cx + char_width(f, b) + track
  end
  return cx - track
end

function Prims.tracked_width(s, track, f)
  if not s or s == "" then return 0 end
  for i = 1, #s do
    if s:byte(i) > 127 then return f:getWidth(s) end
  end
  local w = 0
  for i = 1, #s do w = w + char_width(f, s:byte(i)) + track end
  return w - track
end

local function text_block_same(e, s, f, track, o)
  local mc = o.main_color
  if e.s ~= s or e.font ~= f or e.track ~= track then return false end
  if e.main_a ~= o.main_alpha
    or e.mr ~= mc[1] or e.mg ~= mc[2] or e.mb ~= mc[3] then
    return false
  end
  local sa = o.shadow_alpha or 0
  if e.shadow_a ~= sa then return false end
  if sa <= 0 then return true end
  local sc = o.shadow_color
  return e.shadow_dx == o.shadow_dx and e.shadow_dy == o.shadow_dy
    and e.sr == sc[1] and e.sg == sc[2] and e.sb == sc[3]
end

local function build_tracked_text_block(s, f, track, o)
  local ok, text = pcall(love.graphics.newText, f)
  if not ok or not text or type(text.add) ~= "function" then return nil end

  local sc, mc = o.shadow_color, o.main_color
  local sa = o.shadow_alpha or 0
  local width = 0
  local function add_copy(colored, dx, dy)
    local cx = 0
    for i = 1, #s do
      local ch = s:sub(i, i)
      text:add({ colored, ch }, cx + dx, dy)
      cx = cx + f:getWidth(ch) + track
    end
    width = cx - track
  end
  ok = pcall(function()
    if sa > 0 then add_copy({ sc[1], sc[2], sc[3], sa }, o.shadow_dx, o.shadow_dy) end
    add_copy({ mc[1], mc[2], mc[3], o.main_alpha }, 0, 0)
  end)
  if not ok then return nil end
  return text, width
end

local TEXT_BLOCK_MAX = 24
local text_block_clock = 0

function Prims.draw_cached_tracked_text(batch, key, s, x, y, opts)
  if type(batch) ~= "table" or type(key) ~= "string" or type(s) ~= "string" or s == "" then
    return false
  end
  if type(opts) ~= "table" or opts.dynamic_color then return false end
  local f, track = opts.font, tonumber(opts.track) or 0
  if not f or type(f.getWidth) ~= "function" or type(opts.main_color) ~= "table" then
    return false
  end
  local shadow_alpha = opts.shadow_alpha or 0
  if shadow_alpha > 0 and type(opts.shadow_color) ~= "table" then return false end
  local lg = love.graphics

  local cache = batch._text_blocks
  if not cache then cache = {}; batch._text_blocks = cache; batch._text_blocks_n = 0 end
  local entry = cache[key]
  text_block_clock = text_block_clock + 1
  if entry and text_block_same(entry, s, f, track, opts) then
    entry.used = text_block_clock
  else
    for i = 1, #s do
      if s:byte(i) > 127 then return false end
    end
    local text, width = build_tracked_text_block(s, f, track, opts)
    if not text then return false end
    local sc, mc = opts.shadow_color, opts.main_color
    entry = {
      text = text, s = s, font = f, track = track,
      shadow_dx = opts.shadow_dx, shadow_dy = opts.shadow_dy,
      shadow_a = shadow_alpha, main_a = opts.main_alpha,
      sr = sc and sc[1], sg = sc and sc[2], sb = sc and sc[3],
      mr = mc[1], mg = mc[2], mb = mc[3],
      width = width, used = text_block_clock,
    }
    if cache[key] == nil then
      if (batch._text_blocks_n or 0) >= TEXT_BLOCK_MAX then
        local victim_key, victim_used = nil, math.huge
        for k, v in pairs(cache) do
          if v.used < victim_used then victim_key, victim_used = k, v.used end
        end
        if victim_key then
          local victim = cache[victim_key]
          if victim and victim.text and victim.text.release then pcall(victim.text.release, victim.text) end
          cache[victim_key] = nil
          batch._text_blocks_n = batch._text_blocks_n - 1
        end
      end
      batch._text_blocks_n = (batch._text_blocks_n or 0) + 1
    else
      local prev = cache[key]
      if prev and prev.text and prev.text.release then pcall(prev.text.release, prev.text) end
    end
    cache[key] = entry
  end

  lg.setColor(1, 1, 1, opts.tint_alpha or 1)
  lg.draw(entry.text, x, y)
  return true, entry.width
end

function Prims.candle01(t)
  local f = 0.6 * math.sin(t * 4.3) + 0.25 * math.sin(t * 11.7 + 1.3) + 0.15 * math.sin(t * 23.1)
  if f > 1 then f = 1 elseif f < -1 then f = -1 end
  return 0.5 + 0.5 * f
end

local WHITE_C = { 1, 1, 1 }
Prims.WHITE = WHITE_C
Prims.GLITCH_RED, Prims.GLITCH_CYAN = { 0.95, 0.10, 0.16 }, { 0.12, 0.80, 0.90 }

local function set_color_if_changed(r, g, b, a)
  local get_color = love.graphics.getColor
  if type(get_color) == "function" then
    local cr, cg, cb, ca = get_color()
    if cr == r and cg == g and cb == b and ca == a then return end
  end
  love.graphics.setColor(r, g, b, a)
end

local function parse_px(rows)
  local out = { w = #rows[1], h = #rows }
  local by_shade, order = {}, {}
  for ry = 1, #rows do
    local row = rows[ry]
    local n = #row
    local rx = 1
    while rx <= n do
      local ch = row:sub(rx, rx)
      if ch == "." then
        rx = rx + 1
      else
        local run = 1
        while rx + run <= n and row:sub(rx + run, rx + run) == ch do run = run + 1 end
        local shade = (ch == "O" and 1) or (ch == "W" and 2) or (ch == "D" and 3) or 0
        local bin = by_shade[shade]
        if not bin then bin = {}; by_shade[shade] = bin; order[#order + 1] = shade end
        bin[#bin + 1] = rx - 1
        bin[#bin + 1] = ry - 1
        bin[#bin + 1] = run
        rx = rx + run
      end
    end
  end
  for _, shade in ipairs(order) do
    local bin = by_shade[shade]
    for i = 1, #bin, 3 do
      out[#out + 1] = bin[i]
      out[#out + 1] = bin[i + 1]
      out[#out + 1] = bin[i + 2]
      out[#out + 1] = shade
    end
  end
  return out
end

local function cat(a, b)
  local out = { unpack(a) }
  for i = 1, #b do out[#out + 1] = b[i] end
  return out
end

local BOW_HEAD = {
  "XX.........XX",
  "XXXX.....XXXX",
  "XXXX.OOO.XXXX",
  "XXXXXOWOXXXXX",
  "XXXX.OOO.XXXX",
  "XXXX.....XXXX",
  "XX.........XX",
}
local BOW_LEGS = {
  "....XX.XX....",
  "....XX.XX....",
  "...XX...XX...",
  "...XX...XX...",
  "..XX.....XX..",
}
local HEART = {
  ".XX.XX.",
  "XWXXXXX",
  "XXXXXXX",
  ".XXXXX.",
  "..XXX..",
  "...X...",
}
local BOW_PX = parse_px(cat(BOW_HEAD, BOW_LEGS))
local BOW_HEAD_PX = parse_px(BOW_HEAD)
local BOW_SKULL_PX = parse_px(cat({
  "XX.........XX",
  "XXXX.WWW.XXXX",
  "XXXXWWWWWXXXX",
  "XXXXW.W.WXXXX",
  "XXXXWWWWWXXXX",
  "XXXX.W.W.XXXX",
  "XX.........XX",
}, BOW_LEGS))
local HEART_PX = parse_px(HEART)
local SPARK_PX = parse_px({
  "..X..",
  "..X..",
  "XXXXX",
  "..X..",
  "..X..",
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
local EVIL_HEART_PX = parse_px(cat({ "O.....O", ".O...O." }, HEART))
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
local EYE_SHUT_PX = parse_px({
  ".........",
  "X.......X",
  ".XXXXXXX.",
  "..X.X.X..",
  ".........",
})
local EYE_L_PX = parse_px({
  "..XXXXX..",
  ".XWOXXXX.",
  "XXXOXXXXX",
  ".XXOXXXX.",
  "..XXXXX..",
})
local EYE_R_PX = parse_px({
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
local BADGE_EDITION_PX = parse_px({
  "...X...",
  "..XXX..",
  ".XXXXX.",
  "XXXXXXX",
  ".XXXXX.",
  "..XXX..",
  "...X...",
})
local BADGE_SEAL_PX = parse_px({
  "..XXX..",
  ".X...X.",
  "X.....X",
  "X..X..X",
  "X.....X",
  ".X...X.",
  "..XXX..",
})
local BADGE_STICKER_PX = parse_px({
  "XXXXX..",
  "X....X.",
  "X.....X",
  "X.....X",
  "X.....X",
  "X.....X",
  "XXXXXXX",
})
local BADGE_ENHANCEMENT_PX = parse_px({
  "XXXXX",
  "X...X",
  "X...X",
  "X...X",
  "X...X",
  "X...X",
  "XXXXX",
})
local BADGE_GLYPH_PX = {
  edition = BADGE_EDITION_PX,
  seal = BADGE_SEAL_PX,
  sticker = BADGE_STICKER_PX,
  enhancement = BADGE_ENHANCEMENT_PX,
}

local PIN_GLYPH_PX = {
  sticker = {
    eternal = parse_px({
      "..XXXX..", ".X....X.", ".X....X.", "XXXXXXXX",
      "XXX..XXX", "XXX..XXX", "XXXXXXXX", ".XXXXXX.",
    }),
    perishable = parse_px({
      "XXXXXXXX", ".XXXXXX.", "..XXXX..", "...XX...",
      "...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX",
    }),
    rental = parse_px({
      ".XXXX...", "X....X..", "X....X..", ".XXXX...",
      "........", "XXXXXX..", ".XXXX...", "..XX....",
    }),
  },
  edition = {
    Foil = parse_px({
      "....X..X", "...X..X.", "..X..X..", ".X..X...",
      "X..X....", "..X.....", ".X......", "X.......",
    }),
    Holo = parse_px({
      "........", "...XX...", "........", "XXXXXXXX",
      "XXXXXXXX", "........", "...XX...", "........",
    }),
    Poly = parse_px({
      "........", "...XX...", "..XXXX..", ".XXXXXX.",
      ".XXXXXX.", "..XXXX..", "...XX...", "........",
    }),
    Neg = parse_px({
      "........", ".XXXXXX.", ".XXXXXX.", ".XXXXXX.",
      ".XXXXXX.", ".XXXXXX.", ".XXXXXX.", "........",
    }),
  },
  seal = {
    Gold = parse_px({
      "..XXXX..", ".XXXXXX.", "XXX..XXX", "XXX..XXX",
      "XXX..XXX", "XXX..XXX", ".XXXXXX.", "..XXXX..",
    }),
    Red = parse_px({
      "X...X...", ".X...X..", "..X...X.", "...X...X",
      "..X...X.", ".X...X..", "X...X...", "........",
    }),
    Blue = parse_px({
      "........", "...XX...", "..XXXX..", "XXXXXXXX",
      "XXXXXXXX", "..XXXX..", "...XX...", "........",
    }),
    Purple = parse_px({
      "...XX...", "...XX...", "XXXXXXXX", ".XXXXXX.",
      "..XXXX..", "..X..X..", ".X....X.", "........",
    }),
  },
  enhancement = {
    m_bonus = parse_px({
      "........", "...XX...", "...XX...", ".XXXXXX.",
      ".XXXXXX.", "...XX...", "...XX...", "........",
    }),
    m_mult = parse_px({
      "........", ".X....X.", "..X..X..", "...XX...",
      "...XX...", "..X..X..", ".X....X.", "........",
    }),
    m_wild = parse_px({
      "XX....XX", "XX....XX", "........", "........",
      "........", "........", "XX....XX", "XX....XX",
    }),
    m_glass = parse_px({
      ".XXXXXX.", ".X....X.", ".X.X..X.", ".X..X.X.",
      ".X.X..X.", ".X..X.X.", ".X....X.", ".XXXXXX.",
    }),
    m_steel = parse_px({
      "........", "........", "X......X", "XXXXXXXX",
      "XXXXXXXX", "X......X", "........", "........",
    }),
    m_gold = parse_px({
      "........", "........", "..XXXX..", ".XXXXXX.",
      "XXXXXXXX", "XXXXXXXX", "........", "........",
    }),
    m_lucky = parse_px({
      ".XX..XX.", "XXXXXXXX", "XXXXXXXX", ".XXXXXX.",
      ".XXXXXX.", "XXXXXXXX", "XXXXXXXX", ".XX..XX.",
    }),
    m_stone = parse_px({
      "........", ".XXXX...", ".XXXX...", ".XXXXXX.",
      ".XXXXXX.", ".XXXXXX.", ".XXXXXX.", "........",
    }),
  },
}

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
  ".XWWXXXX.",
  "XWXOOOXX.",
  "XXOXXXOXX",
  "XXOXOXOXX",
  ".XOXXXOXD",
  ".XXOOOXDD",
  "..XXXXXDD",
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
local LINK_PX = parse_px({
  ".XX.",
  "X..X",
  "X..X",
  "X..X",
  ".XX.",
})

local function silhouette(pat, dc)
  dc = math.floor(dc)
  if dc <= 0 then return nil end
  local cache = pat.sil
  if not cache then cache = {}; pat.sil = cache end
  local hit = cache[dc]
  if hit ~= nil then return hit or nil end

  local w, h = pat.w, pat.h
  local lit = {}
  for i = 1, #pat, 4 do
    local x, y, len = pat[i], pat[i + 1], pat[i + 2]
    for k = 0, len - 1 do lit[y * w + x + k] = true end
  end

  local out = {}
  for y = 0, h + dc - 1 do
    local run_x, run_len = nil, 0
    for x = 0, w + dc - 1 do
      local sx, sy = x - dc, y - dc
      local covers = sx >= 0 and sy >= 0 and sx < w and sy < h and lit[sy * w + sx]
      local hidden = x < w and y < h and lit[y * w + x]
      if covers and not hidden then
        if run_x then run_len = run_len + 1 else run_x, run_len = x, 1 end
      elseif run_x then
        out[#out + 1] = run_x; out[#out + 1] = y; out[#out + 1] = run_len
        run_x, run_len = nil, 0
      end
    end
    if run_x then
      out[#out + 1] = run_x; out[#out + 1] = y; out[#out + 1] = run_len
    end
  end
  cache[dc] = (#out > 0) and out or false
  return cache[dc] or nil
end

local PX_MESH_VARIANTS = 4
local append_mesh_rect, build_mesh = RectMesh.add, RectMesh.build

local function release_deco_mesh(m)
  if type(m) == "table" and not m.release then
    for _, sub in pairs(m) do
      local st = type(sub)
      if (st == "userdata" or st == "table") and sub.release then pcall(sub.release, sub) end
    end
  elseif m and m.release then
    pcall(m.release, m)
  end
end
local deco = RectMesh.lru(32, release_deco_mesh)

local function px_variant_mesh(cache, r0, g0, b0, r1, g1, b1, r2, g2, b2)
  for i = 1, PX_MESH_VARIANTS do
    local e = cache[i]
    if e
      and e.r0 == r0 and e.g0 == g0 and e.b0 == b0
      and e.r1 == r1 and e.g1 == g1 and e.b1 == b1
      and e.r2 == r2 and e.g2 == g2 and e.b2 == b2
    then
      return e.mesh
    end
  end
end

local function px_variant_store(cache, mesh, r0, g0, b0, r1, g1, b1, r2, g2, b2)
  local slot = cache.next
  local prev = cache[slot]
  if prev and prev.mesh and prev.mesh ~= mesh and prev.mesh.release then
    pcall(prev.mesh.release, prev.mesh)
  end
  cache[slot] = {
    mesh = mesh,
    r0 = r0, g0 = g0, b0 = b0,
    r1 = r1, g1 = g1, b1 = b1,
    r2 = r2, g2 = g2, b2 = b2,
  }
  cache.next = slot % PX_MESH_VARIANTS + 1
end

local function append_px_body(vertices, indices, pat, r0, g0, b0, r1, g1, b1, r2, g2, b2)
  for i = 1, #pat, 4 do
    local x, y, len, shade = pat[i], pat[i + 1], pat[i + 2], pat[i + 3]
    local r, g, b
    if shade == 1 then
      r, g, b = r1, g1, b1
    elseif shade == 2 then
      r, g, b = r2, g2, b2
    elseif shade == 3 then
      r, g, b = r0 * 0.45, g0 * 0.45, b0 * 0.6
    else
      r, g, b = r0, g0, b0
    end
    append_mesh_rect(vertices, indices, x, y, len, 1, r, g, b, 1)
  end
end

local function variant_mesh(pat, field, key, sil, off, col, col2, colw)
  if not RectMesh.available() then return nil end

  local c1 = col2 or col
  local c2 = colw or WHITE_C
  local r0, g0, b0 = col[1], col[2], col[3]
  local r1, g1, b1 = c1[1], c1[2], c1[3]
  local r2, g2, b2 = c2[1], c2[2], c2[3]
  local root = pat[field]
  if not root then root = {}; pat[field] = root end
  local cache = root[key]
  if cache then
    local hit = px_variant_mesh(cache, r0, g0, b0, r1, g1, b1, r2, g2, b2)
    if hit then return hit end
  else
    cache = { next = 1 }
    root[key] = cache
  end

  local vertices, indices = {}, {}
  if sil then
    for i = 1, #sil, 3 do
      append_mesh_rect(vertices, indices, sil[i], sil[i + 1], sil[i + 2], 1, 0, 0, 0, 0.55)
    end
  elseif off then
    for i = 1, #pat, 4 do
      append_mesh_rect(vertices, indices, pat[i] + off, pat[i + 1] + off, pat[i + 2], 1,
        0, 0, 0, 0.55)
    end
  end
  append_px_body(vertices, indices, pat, r0, g0, b0, r1, g1, b1, r2, g2, b2)

  local mesh = build_mesh(vertices, indices)
  if not mesh then return nil end
  px_variant_store(cache, mesh, r0, g0, b0, r1, g1, b1, r2, g2, b2)
  return mesh
end

local function shape_mesh(pat)
  if not RectMesh.available() then return nil end
  if pat.shape_mesh_built then return pat.shape_mesh end
  pat.shape_mesh_built = true
  local vertices, indices = {}, {}
  for i = 1, #pat, 4 do
    append_mesh_rect(vertices, indices, pat[i], pat[i + 1], pat[i + 2], 1, 0, 0, 0, 0.55)
  end
  pat.shape_mesh = build_mesh(vertices, indices)
  return pat.shape_mesh
end

local bake_supported
local bakes = RectMesh.lru(6, function(e)
  local c = e and e.canvas
  if c and c.release then pcall(c.release, c) end
end)

local function bake_slot(kind, w, u, p1, p2, p3, p4, p5, p6)
  local e = bakes:get(kind, w, u, p1, p2, p3, p4, p5, p6)
  if not e then
    e = { canvas = false }
    bakes:put(kind, w, u, p1, p2, p3, p4, p5, p6, e)
  end
  return e
end

local function bake_placement_ok(x, y)
  if x % 1 ~= 0 or y % 1 ~= 0 then return false end
  local tp = love.graphics.transformPoint
  local ok, ox, oy = pcall(tp, 0, 0)
  if not ok or type(ox) ~= "number" or type(oy) ~= "number" then return true end
  local ok1, ux, uy = pcall(tp, 1, 1)
  if not ok1 or type(ux) ~= "number" or type(uy) ~= "number" then return true end
  return ox % 1 == 0 and oy % 1 == 0 and ux - ox == 1 and uy - oy == 1
end

local function bake_run(cw, ch, ox, oy, paint)
  if bake_supported == false then return nil end
  local made, canvas = pcall(love.graphics.newCanvas, cw, ch)
  if not made or not canvas then bake_supported = false; return nil end
  bake_supported = true
  if canvas.setFilter then pcall(canvas.setFilter, canvas, "nearest", "nearest") end

  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  if love.graphics.getScissor() then love.graphics.setScissor() end
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha", "alphamultiply")
  love.graphics.clear(0, 0, 0, 0)
  local painted = pcall(paint, ox, oy)
  love.graphics.pop()

  if not painted then
    if canvas.release then pcall(canvas.release, canvas) end
    bake_supported = false
    return nil
  end
  return canvas
end

local function bake_draw(canvas, dx, dy, a)
  local mode, alphamode = love.graphics.getBlendMode()
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(a, a, a, a)
  love.graphics.draw(canvas, dx, dy)
  love.graphics.setBlendMode(mode, alphamode)
end

local function draw_px(pat, cx, cy, s, col, a, col2, colw, shadow)
  -- Below one 8-bit alpha step, drawing has no visible effect.
  a = a or 1
  if a <= 1 / 255 then return end
  local x0 = round(cx - pat.w * s / 2)
  local y0 = round(cy - pat.h * s / 2)
  if shadow then
    local so = (shadow == true) and 1 or shadow
    local dc = (s > 0 and a >= 0.9 and so % s == 0) and so / s or nil
    local sil = dc and silhouette(pat, dc) or nil
    local off = (not sil) and s > 0 and s % 1 == 0 and so % 1 == 0 and so / s or nil
    local mesh = (sil and variant_mesh(pat, "sil_combo", dc, sil, nil, col, col2, colw))
      or (off and variant_mesh(pat, "off_combo", off, nil, off, col, col2, colw))
      or nil
    if mesh then
      set_color_if_changed(1, 1, 1, a)
      love.graphics.draw(mesh, x0, y0, 0, s, s)
      return
    end
    if sil then
      set_color_if_changed(0, 0, 0, 0.55 * a)
      for i = 1, #sil, 3 do
        love.graphics.rectangle("fill", x0 + sil[i] * s, y0 + sil[i + 1] * s, sil[i + 2] * s, s)
      end
    else
      local shape = shape_mesh(pat)
      if shape then
        set_color_if_changed(1, 1, 1, a)
        love.graphics.draw(shape, x0 + so, y0 + so, 0, s, s)
      else
        set_color_if_changed(0, 0, 0, 0.55 * a)
        for i = 1, #pat, 4 do
          love.graphics.rectangle("fill", x0 + pat[i] * s + so, y0 + pat[i + 1] * s + so,
            pat[i + 2] * s, s)
        end
      end
    end
  end
  local mesh = variant_mesh(pat, "px_meshes", 1, nil, nil, col, col2, colw)
  if mesh then
    set_color_if_changed(1, 1, 1, a)
    love.graphics.draw(mesh, x0, y0, 0, s, s)
  else
    local last
    for i = 1, #pat, 4 do
      local f = pat[i + 3]
      if f ~= last then
        last = f
        if f == 3 then
          set_color_if_changed(col[1] * 0.45, col[2] * 0.45, col[3] * 0.6, a)
        else
          local c = (f == 1 and col2) or (f == 2 and (colw or WHITE_C)) or col
          set_color_if_changed(c[1], c[2], c[3], a)
        end
      end
      love.graphics.rectangle("fill", x0 + pat[i] * s, y0 + pat[i + 1] * s, pat[i + 2] * s, s)
    end
  end
end

function Prims.draw_bow(cx, cy, u, col, a, col2)
  draw_px(BOW_PX, cx, cy, math.max(1, round(u * 1.5)), col, a, col2)
end

function Prims.draw_bow_mini(cx, cy, u, col, a, col2)
  draw_px(BOW_HEAD_PX, cx, cy, math.max(1, round(u * 1.5)), col, a, col2)
end

function Prims.draw_heart(cx, cy, r, col, a)
  draw_px(HEART_PX, cx, cy, math.max(1, round(r / 3)), col, a)
end

function Prims.heart_extent(r)
  local s = math.max(1, round(r / 3))
  return HEART_PX.w * s, HEART_PX.h * s
end

local BOW_WINE = { 0.45, 0.09, 0.13 }
local EYE_PUPIL = { 0.06, 0.01, 0.02 }
local SKULL_SOCK = { 0.05, 0.01, 0.02 }
local FLAME_HOT = { 1, 0.95, 0.75 }
local SEAL_WAX = { 0.34, 0.035, 0.065 }
local SEAL_HI = { 1, 0.92, 0.85 }

function Prims.draw_dark_bow_mini(cx, cy, u, acc, a, gold, shadow, body)
  draw_px(DARK_BOW_HEAD_PX, cx, cy, math.max(1, round(u * 1.5)), body or BOW_WINE, a, acc, gold, shadow)
end

function Prims.draw_evil_heart(cx, cy, r, acc, a, gold, shadow)
  draw_px(EVIL_HEART_PX, cx, cy, math.max(1, round(r / 3)), acc, a, gold, nil, shadow)
end

function Prims.draw_horns(cx, cy, r, acc, a, gold, shadow)
  draw_px(HORNS_PX, cx, cy, math.max(1, round(r / 3)), acc, a, gold, nil, shadow)
end

function Prims.draw_skull(cx, cy, r, col, a, gold, shadow)
  draw_px(SKULL_PX, cx, cy, math.max(1, round(r / 3)), col, a, gold, SKULL_SOCK, shadow)
end

function Prims.corner_brand(cx, cy, u, crimson, bone, a, shadow)
  draw_px(BOW_SKULL_PX, cx, cy, math.max(1, round(u * 1.5)), crimson, a, nil, bone, shadow)
end

function Prims.draw_glint(cx, cy, r, acc, a, gold, shadow)
  draw_px(GLINT_PX, cx, cy, math.max(1, round(r / 2)), acc, a, gold, nil, shadow)
end

function Prims.draw_knife(cx, cy, u, gold, silver, a, shadow)
  draw_px(KNIFE_PX, cx, cy, math.max(1, round(u * 1.5)), BOW_WINE, a, gold, silver, shadow)
end

function Prims.draw_evil_eye(cx, cy, u, acc, a, now, shadow, look, hold)
  local pat = EYE_PX
  if not hold and (now % 4.7) < 0.12 then pat = EYE_SHUT_PX
  elseif look and look < 0 then pat = EYE_L_PX
  elseif look and look > 0 then pat = EYE_R_PX end
  draw_px(pat, cx, cy, math.max(1, round(u * 1.5)), acc, a, EYE_PUPIL, nil, shadow)
end

function Prims.draw_diamond(cx, cy, u, col, a)
  draw_px(DIAMOND_PX, cx, cy, math.max(1, round(u * 0.75)), col, a)
end

local function pin_glyph_pat(kind, key)
  local per = kind and PIN_GLYPH_PX[kind]
  return (per and key and per[key]) or BADGE_GLYPH_PX[kind]
end

function Prims.pin_glyph(kind, key, cx, cy, size, col, a)
  local pat = pin_glyph_pat(kind, key)
  if not pat or not size or size <= 0 then return 0 end
  local s = math.max(1, round(size / pat.h))
  draw_px(pat, cx, cy, s, col, a)
  return pat.w * s
end

function Prims.pin_silhouette(kind, x, y, w, h, ink, a)
  if a <= 0.01 then return end
  local r, g, b = ink[1], ink[2], ink[3]
  if kind == "sticker" then
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", x + w - 2, y, 2, 1)
    love.graphics.rectangle("fill", x + w - 1, y + 1, 1, 1)
  elseif kind == "seal" then
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", x, y, 1, 1)
    love.graphics.rectangle("fill", x + w - 1, y, 1, 1)
    love.graphics.rectangle("fill", x, y + h - 1, 1, 1)
    love.graphics.rectangle("fill", x + w - 1, y + h - 1, 1, 1)
  elseif kind == "enhancement" then
    love.graphics.setColor(r, g, b, a * 0.55)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
  end
end

function Prims.pin_pips(n, x, y, w, h, col, a)
  n = math.max(0, math.min(9, math.floor(n or 0)))
  if n == 0 or a <= 0.01 or w <= 0 or h <= 0 then return end
  local s = math.max(1, math.floor(w / 6))
  local gap = math.max(1, math.floor(s / 2))
  local span = 3 * s + 2 * gap
  local x0 = x + math.floor((w - span) / 2)
  local y0 = y + math.floor((h - span) / 2)
  set_col(col, a)
  for i = 0, n - 1 do
    love.graphics.rectangle("fill", x0 + (i % 3) * (s + gap),
      y0 + math.floor(i / 3) * (s + gap), s, s)
  end
end

local function gothic_stud_rects(w, h, u, gold)
  local list = {}
  local c2 = u * 2
  for sx2 = 0, 1 do
    for sy2 = 0, 1 do
      for i = 0, 2 do
        local sx = u * (1 + i * 2)
        local sy = u * (5 - i * 2)
        RectMesh.rect(list, sx2 == 0 and sx or (w - sx - c2), sy2 == 0 and sy or (h - sy - c2), c2, c2,
          gold[1], gold[2], gold[3], 1)
      end
    end
  end
  return list
end

function Prims.gothic_frame(x, y, w, h, u, gold, frd, a, rad, pulse, quiet)
  rad = rad or 0
  pulse = pulse or 0.5
  local E = Prims.EVIL
  love.graphics.setLineWidth(1)
  set_col(gold, E.A_HAIR * a)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
  set_col(gold, 0.10 * a)
  love.graphics.rectangle("fill", x + rad + 1, y + 1, w - rad * 2 - 2, 1)
  if rad > 0 or quiet then return end
  if w < u * 40 or h < u * 24 then return end
  set_col(frd, E.A_INSET * a)
  local i3 = u * 3
  love.graphics.rectangle("line", x + i3, y + i3, w - i3 * 2, h - i3 * 2)
  local qw, qh = math.floor(w / 4 + 0.5) * 4, math.floor(h / 4 + 0.5) * 4
  local studs = qw > 0 and qh > 0 and RectMesh.cached(deco, "gothic_studs", qw, u, qh, gold[1], gold[2],
    gold[3], nil, nil, gothic_stud_rects, qw, qh, u, gold)
  if studs then
    love.graphics.setColor(1, 1, 1, E.A_STRUCT * a)
    love.graphics.draw(studs, x, y, 0, w / qw, h / qh)
  else
    RectMesh.paint(gothic_stud_rects(w, h, u, gold), x, y, 1, 1, 1, E.A_STRUCT * a)
  end
  local sa = (E.A_ACCENT + E.PULSE_AMP * pulse) * a
  Prims.draw_diamond(x + u * 8, y + u * 8, u, gold, sa)
  Prims.draw_diamond(x + w - u * 8, y + u * 8, u, gold, sa)
  Prims.draw_diamond(x + u * 8, y + h - u * 8, u, gold, sa)
  Prims.draw_diamond(x + w - u * 8, y + h - u * 8, u, gold, sa)
end

local DIVIDER_SEGS = 4
local function divider_seg_w(w) return math.ceil(w / (DIVIDER_SEGS * 2)) end
local function divider_seg_h(i, weight) return (i == 1) and 1 or weight end
local function divider_base(i)
  return 0.30 + (Prims.EVIL.A_DIVIDER_MAX - 0.30) * i / DIVIDER_SEGS
end

local function divider_rects(w, weight)
  local list = {}
  local segw = divider_seg_w(w)
  for i = 1, DIVIDER_SEGS do
    local hh, base = divider_seg_h(i, weight), divider_base(i)
    RectMesh.rect(list, (i - 1) * segw, -hh, segw, hh, 1, 1, 1, base)
    RectMesh.rect(list, w - i * segw, -hh, segw, hh, 1, 1, 1, base)
  end
  return list
end

function Prims.evil_divider(x, y, w, u, acc, gold, a, pulse, weight, no_center, ignite01)
  a = a or 1
  pulse = pulse or 0.5
  weight = weight or 2
  local mesh = not ignite01 and RectMesh.cached(deco, "evil_divider", w, weight, nil, nil, nil, nil, nil, nil,
    divider_rects, w, weight)
  if mesh then
    set_col(acc, (0.85 + 0.10 * pulse) * a)
    love.graphics.draw(mesh, x, y)
  else
    local segw = divider_seg_w(w)
    for i = 1, DIVIDER_SEGS do
      local ik = ignite01 and Prims.smoothstep01((ignite01 - (DIVIDER_SEGS - i) * 0.18) / 0.35) or 1
      local hh = divider_seg_h(i, weight)
      set_col(acc, divider_base(i) * (0.85 + 0.10 * pulse) * ik * a)
      love.graphics.rectangle("fill", x + (i - 1) * segw, y - hh, segw, hh)
      love.graphics.rectangle("fill", x + w - i * segw, y - hh, segw, hh)
    end
  end
  if no_center then return end
  Prims.quatrefoil(x + math.floor(w / 2), y - 1, u * 5, gold, a, pulse)
end

function Prims.plate_label(x, y, w, h, gold, a, rivets, fill_a)
  a = a or 1
  love.graphics.setColor(0, 0, 0, (fill_a or 0.35) * a)
  love.graphics.rectangle("fill", x, y, w, h)
  set_col(gold, Prims.EVIL.A_PLATE * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  if rivets then
    local my = y + math.floor(h / 2)
    local ru = math.max(1, math.floor(h / 8))
    Prims.draw_diamond(x, my, ru, gold, 0.90 * a)
    Prims.draw_diamond(x + w, my, ru, gold, 0.90 * a)
  end
end

function Prims.candle_finial(cx, base_y, u, gold, a, now, flare)
  if (a or 1) <= 0.01 then return end
  a = a or 1
  flare = flare or 0
  cx, base_y = round(cx), round(base_y)
  local bw, bh = u * 4, u * 7
  love.graphics.setColor(0.46, 0.06, 0.09, 0.95 * a)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh, bw, bh)
  love.graphics.setColor(0.72, 0.16, 0.16, 0.90 * a)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh, bw, u)
  love.graphics.rectangle("fill", cx - u * 2, base_y - bh + u, u, u * 3)
  local flick = Prims.candle01(now + cx * 0.13)
  local fy = base_y - bh - u
  love.graphics.setColor(1, 0.95, 0.85, 0.95 * a)
  love.graphics.rectangle("fill", cx - math.floor(u / 2), fy, u, u)
  local gr = u * 6 + math.floor(u * 4 * flare)
  set_col(gold, (0.05 + 0.04 * flick + 0.08 * flare) * a)
  love.graphics.rectangle("fill", cx - gr, fy - u * 4 - gr, gr * 2, gr * 2)
  local gr2 = math.floor(gr * 0.55)
  set_col(gold, (0.08 + 0.05 * flick + 0.10 * flare) * a)
  love.graphics.rectangle("fill", cx - gr2, fy - u * 4 - gr2, gr2 * 2, gr2 * 2)
  local s = math.max(1, round(u * (1 + 0.5 * flick + 0.8 * flare)))
  local pat = (flick > 0.5) and FLAME_A_PX or FLAME_B_PX
  draw_px(pat, cx, fy - s * 2, s, gold, (0.85 + 0.10 * flick) * a, nil, FLAME_HOT)
end

local EMBER_BLOOM_RINGS = { { 1, 0.05 }, { 0.62, 0.08 }, { 0.34, 0.13 } }
function Prims.ember_bloom(cx, cy, r, u, t01, gold, a)
  if t01 <= 0 or t01 >= 1 then return end
  a = a or 1
  local env = math.sin(math.pi * t01)
  cx, cy = round(cx), round(cy)
  for _, rf in ipairs(EMBER_BLOOM_RINGS) do
    local rr = round(r * rf[1])
    set_col(gold, rf[2] * env * a)
    love.graphics.rectangle("fill", cx - rr, cy - rr, rr * 2, rr * 2)
  end
  local rise = Prims.ease_out_cubic01(t01)
  for ei = 1, 5 do
    local xr = math.sin(ei * 12.9898)
    local ex = round(cx + xr * r * 0.7 + math.sin(t01 * 5 + ei * 1.7) * u * 2)
    local ey = round(cy - rise * (r * (0.7 + 0.3 * math.abs(math.sin(ei * 78.233)))))
    local gg = 0.62 - 0.40 * rise
    love.graphics.setColor(1, gg, 0.16, (1 - t01) * 0.85 * a)
    love.graphics.rectangle("fill", ex, ey, (ei % 3 == 0) and u * 2 or u, (ei % 3 == 0) and u * 2 or u)
  end
end

Prims.SHADOW_LAYERS = { { 0, 1, 0, 0.20 }, { 1, 2, 1, 0.28 }, { 2, 4, 3, 0.20 } }
local shadow_sink = nil
local function panel_shadow_rect(x, y, w, h)
  if w > 0 and h > 0 then
    if shadow_sink then
      append_mesh_rect(shadow_sink.v, shadow_sink.i, x, y, w, h, 1, 1, 1, 1)
    else
      love.graphics.rectangle("fill", x, y, w, h)
    end
  end
end

local function panel_shadow_corners(x, y, w, h, rad)
  local right, bottom = x + w, y + h
  if shadow_sink then
    local PI = math.pi
    RectMesh.add_pie(shadow_sink.v, shadow_sink.i, x + rad, y + rad, rad, PI, PI * 1.5)
    RectMesh.add_pie(shadow_sink.v, shadow_sink.i, right - rad, y + rad, rad, PI * 1.5, PI * 2)
    RectMesh.add_pie(shadow_sink.v, shadow_sink.i, right - rad, bottom - rad, rad, 0, PI * 0.5)
    RectMesh.add_pie(shadow_sink.v, shadow_sink.i, x + rad, bottom - rad, rad, PI * 0.5, PI)
    return
  end
  love.graphics.arc("fill", "pie", x + rad, y + rad, rad, math.pi, math.pi * 1.5)
  love.graphics.arc("fill", "pie", right - rad, y + rad, rad, math.pi * 1.5, math.pi * 2)
  love.graphics.arc("fill", "pie", right - rad, bottom - rad, rad, 0, math.pi * 0.5)
  love.graphics.arc("fill", "pie", x + rad, bottom - rad, rad, math.pi * 0.5, math.pi)
end

local function panel_shadow_ring(x, y, w, h, rad, square, plate_x, plate_y, plate_w, plate_h)
  local right, bottom = x + w, y + h
  local plate_right, plate_bottom = plate_x + plate_w, plate_y + plate_h
  local top_w = math.max(1, plate_y - y)
  local bottom_w = math.max(1, bottom - plate_bottom)
  local left_w = math.max(1, plate_x - x)
  local right_w = math.max(1, right - plate_right)

  if square then
    top_w = math.min(top_w, h)
    bottom_w = math.min(bottom_w, h - top_w)
    panel_shadow_rect(x, y, w, top_w)
    panel_shadow_rect(x, bottom - bottom_w, w, bottom_w)
    local middle_h = h - top_w - bottom_w
    left_w = math.min(left_w, w)
    right_w = math.min(right_w, w - left_w)
    panel_shadow_rect(x, y + top_w, left_w, middle_h)
    panel_shadow_rect(right - right_w, y + top_w, right_w, middle_h)
    return
  end

  local edge_w = w - rad * 2
  local edge_h = h - rad * 2
  panel_shadow_rect(x + rad, y, edge_w, top_w)
  panel_shadow_rect(x + rad, bottom - bottom_w, edge_w, bottom_w)
  panel_shadow_rect(x, y + rad, left_w, edge_h)
  panel_shadow_rect(right - right_w, y + rad, right_w, edge_h)
  panel_shadow_corners(x, y, w, h, rad)
end

local function build_panel_shadow_meshes(w, h, rad, ux, uy, square)
  local out = {}
  for i = 1, #Prims.SHADOW_LAYERS do
    local L = Prims.SHADOW_LAYERS[i]
    local sp = L[3]
    local sr = rad + sp
    local v, idx = {}, {}
    shadow_sink = { v = v, i = idx }
    panel_shadow_ring(-sp + L[1] * ux, -sp + L[2] * uy, w + sp * 2, h + sp * 2, sr, square or sr <= 0,
      0, 0, w, h)
    shadow_sink = nil
    if #v == 0 then
      out[i] = false
    else
      local mesh = build_mesh(v, idx)
      if not mesh then return nil end
      out[i] = mesh
    end
  end
  return out
end

local function panel_body(x, y, w, h, rad, bg, bg_a, bands)
  local tiled = rad == 0 and type(bands) == "table" and #bands > 0
  local edge = 0
  if tiled then
    for i = 1, #bands do
      local band = bands[i]
      local y0, y1 = band and band[1], band and band[2]
      local col, oa, x0, x1 = band and band[3], band and band[4],
        band and band[5] or 0, band and band[6] or w
      if type(y0) ~= "number" or type(y1) ~= "number" or y0 ~= edge or y1 <= y0 or y1 > h
        or type(col) ~= "table" or type(col[1]) ~= "number" or type(oa) ~= "number"
        or oa < 0 or oa > 1 or type(x0) ~= "number" or type(x1) ~= "number"
        or x0 < 0 or x1 > w or x1 <= x0 then
        tiled = false
        break
      end
      edge = y1
    end
    tiled = tiled and edge == h
  end

  if not tiled then
    set_col(bg, bg_a)
    love.graphics.rectangle("fill", x, y, w, h, rad, rad)
    return false
  end

  for i = 1, #bands do
    local band = bands[i]
    local y0, y1, col, oa = band[1], band[2], band[3], band[4] or 0
    local x0, x1 = band[5] or 0, band[6] or w
    local inv = 1 - oa
    local out_a = oa + bg_a * inv
    if x0 > 0 or x1 < w then
      set_col(bg, bg_a)
      if x0 > 0 then love.graphics.rectangle("fill", x, y + y0, x0, y1 - y0) end
      if x1 < w then love.graphics.rectangle("fill", x + x1, y + y0, w - x1, y1 - y0) end
    end
    if out_a > 0 then
      local base_k, over_k = bg_a * inv / out_a, oa / out_a
      love.graphics.setColor(
        bg[1] * base_k + col[1] * over_k,
        bg[2] * base_k + col[2] * over_k,
        bg[3] * base_k + col[3] * over_k,
        out_a)
    else
      love.graphics.setColor(0, 0, 0, 0)
    end
    love.graphics.rectangle("fill", x + x0, y + y0, x1 - x0, y1 - y0)
  end
  return true
end

local SHADOW_MESH_QUANT = 4
local function quant(v, step) return math.floor(v / step + 0.5) * step end

function Prims.panel_shell(x, y, w, h, rad, sh_dx, sh_dy, sh_a, bg, bg_a, a, bands, square)
  local ux = (sh_dx or 0) * 0.5
  local uy = (sh_dy or 0) * 0.5
  local meshes
  local qw, qh = w, h
  -- `quant()` floors to zero below half a step, and the draw call divides by it.
  if a >= 0.98 and RectMesh.available()
      and w >= SHADOW_MESH_QUANT and h >= SHADOW_MESH_QUANT then
    qw, qh = quant(w, SHADOW_MESH_QUANT), quant(h, SHADOW_MESH_QUANT)
    local kind = square and "panel_shadow_sq" or "panel_shadow"
    meshes = deco:get(kind, qw, qh, rad, ux, uy)
    if not meshes then
      meshes = build_panel_shadow_meshes(qw, qh, rad, ux, uy, square)
      if meshes then deco:put(kind, qw, qh, rad, ux, uy, nil, nil, nil, meshes) end
    end
  end
  for i = 1, #Prims.SHADOW_LAYERS do
    local L = Prims.SHADOW_LAYERS[i]
    local sp = L[3]
    love.graphics.setColor(0, 0, 0, L[4] * sh_a)
    local sx, sy = x - sp + L[1] * ux, y - sp + L[2] * uy
    local sw, shh, sr = w + sp * 2, h + sp * 2, rad + sp
    if a >= 0.98 then
      if meshes then
        if meshes[i] then love.graphics.draw(meshes[i], x, y, 0, w / qw, h / qh) end
      else
        panel_shadow_ring(sx, sy, sw, shh, sr, square or sr <= 0, x, y, w, h)
      end
    elseif square then
      love.graphics.rectangle("fill", sx, sy, sw, shh)
    else
      love.graphics.rectangle("fill", sx, sy, sw, shh, sr, sr)
    end
  end
  return panel_body(x, y, w, h, rad, bg, bg_a, bands)
end

function Prims.panel_base(x, y, w, h, rad, sh, a, bg, frame, bands, square)
  local tiled = Prims.panel_shell(x, y, w, h, rad, sh, sh, 0.55 * a, bg, 0.97 * a, a, bands, square)
  set_col(frame, 0.90 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h, rad, rad)
  return tiled
end

function Prims.neuro_frame_deco(x, y, w, h, u, th, GLOW, ACC, a, skip_body)
  a = a or 1
  set_col(GLOW, 0.035 * a)
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, th)
  if not skip_body then
    set_col(GLOW, 0.018 * a)
    love.graphics.rectangle("fill", x + 1, y + th, w - 2, u * 16)
    set_col(ACC, 0.02 * a)
    love.graphics.rectangle("fill", x, y + math.floor(h * 0.55), w, math.floor(h * 0.15))
    set_col(ACC, 0.04 * a)
    love.graphics.rectangle("fill", x, y + math.floor(h * 0.70), w, math.floor(h * 0.30) - 2)
  end
end

function Prims.evil_frame_deco(x, y, w, _h, u, th, GOLD, GLOW, pulse, _now, cxf, a, flare)
  a = a or 1
  cxf = cxf or 0.30
  local gcx = x + math.floor(w * cxf)
  local gcy = y + math.floor(th * 0.55)
  local grx = math.floor(w * 0.30)
  local gry = math.floor(th * 0.85)
  local gk = (0.8 + 0.2 * pulse + 0.6 * (flare or 0)) * a
  set_col(GLOW, 0.020 * gk)
  love.graphics.ellipse("fill", gcx, gcy, grx, gry)
  set_col(GLOW, 0.030 * gk)
  love.graphics.ellipse("fill", gcx, gcy, math.floor(grx * 0.66), math.floor(gry * 0.7))
  set_col(GLOW, 0.045 * gk)
  love.graphics.ellipse("fill", gcx, gcy, math.floor(grx * 0.38), math.floor(gry * 0.5))
  if _h > th * 2 then
    local bcx = x + math.floor(w / 2)
    local bcy = y + _h
    local brx, bry = math.floor(w * 0.5), math.floor(_h * 0.42)
    set_col(GLOW, 0.016 * gk)
    love.graphics.ellipse("fill", bcx, bcy, brx, bry)
    set_col(GLOW, 0.022 * gk)
    love.graphics.ellipse("fill", bcx, bcy, math.floor(w * 0.30), math.floor(_h * 0.24))
  end
  set_col(GOLD, 0.08 * a)
  love.graphics.rectangle("fill", x + u * 4, y + 1, w - u * 8, 1)
end

function Prims.counter_glow(x, y, w, h, col, a, pulse, rad)
  pulse = pulse or 0.5
  rad = rad or 0
  local gk = (0.75 + 0.25 * pulse) * (a or 1)
  local base_y = y + h
  if rad ~= 0 then
    for i = 1, 3 do
      local bh = math.floor(h * (0.10 + i * 0.06))
      set_col(col, (0.05 - i * 0.012) * gk)
      love.graphics.rectangle("fill", x + 1, base_y - bh, w - 2, bh, rad, rad)
    end
    return
  end

  local h1, h2, h3 = math.floor(h * 0.16), math.floor(h * 0.22), math.floor(h * 0.28)
  local a1, a2, a3 = 0.038 * gk, 0.026 * gk, 0.014 * gk
  local a12 = a2 + a1 * (1 - a2)
  local a123 = a3 + a12 * (1 - a3)
  if h3 > h2 then
    set_col(col, a3)
    love.graphics.rectangle("fill", x + 1, base_y - h3, w - 2, h3 - h2)
  end
  if h2 > h1 then
    set_col(col, a3 + a2 * (1 - a3))
    love.graphics.rectangle("fill", x + 1, base_y - h2, w - 2, h2 - h1)
  end
  if h1 > 0 then
    set_col(col, a123)
    love.graphics.rectangle("fill", x + 1, base_y - h1, w - 2, h1)
  end
end

local BLOOD_DARK = { 0.29, 0.030, 0.055 }
local BLOOD_FRESH = { 0.46, 0.06, 0.09 }

function Prims.wax_seal(cx, cy, r, _u, gold, a, pulse, drip, now)
  if (a or 1) <= 0.01 then return end
  pulse = pulse or 0.5
  cx, cy = round(cx), round(cy)
  local s = r * 2 / 9   -- fractional cells above 2 keep animated sizes smooth
  if s < 2 then s = math.max(1, round(s)) end
  if drip then
    local swell = 0.5 + 0.5 * math.sin((now or Prims.now()) * 0.6 + cx * 0.05)
    local bw = math.max(1, round(s))
    local nw = s >= 2 and math.max(1, round(s * 0.6)) or bw
    local dx = round(cx + s)
    local dy = round(cy + 4 * s)
    local dl = round(s * (1.5 + 1.5 * swell))
    set_col(BLOOD_DARK, 0.95 * a)
    love.graphics.rectangle("fill", dx, round(cy + 3.5 * s), bw * 2, bw)
    love.graphics.rectangle("fill", dx + math.floor((bw - nw) / 2), dy, nw, dl)
    local bh = math.max(bw, round(s * (1 + 0.5 * pulse)))
    set_col(BLOOD_FRESH, 0.90 * a)
    love.graphics.rectangle("fill", dx, dy + dl, bw, bh)
    if s >= 2 then
      local hs = math.max(1, round(s * 0.5))
      set_col(SEAL_HI, 0.45 * a)
      love.graphics.rectangle("fill", dx, dy + dl, hs, hs)
    end
  end
  draw_px(SEAL_PX, cx, cy, s, SEAL_WAX, 0.95 * a, gold, SEAL_HI, math.max(1, round(s * 0.5)))
end
local DRIP_AT = { 0.22, 0.54, 0.79 }
local function drip_len(i, u, t01, room)
  local grow = 0.35 + 0.65 * math.abs(math.sin(i * 12.9898))
  local l = round(u * (1 + 5 * t01 * grow))
  return (room and l > room) and room or l
end
function Prims.blood_ledge(x, y, w, u, a, t01, pulse, max_h)
  if w < u * 10 then return end
  a = a or 1
  t01 = math.max(0, math.min(1, t01 or 0))
  pulse = pulse or 0.5
  local s = math.max(1, round(u / 3))
  local tip = s + round(s * pulse)
  local room = max_h and math.max(0, max_h - s - tip) or nil
  if room == 0 then return end
  x, y = round(x), round(y)
  set_col(BLOOD_DARK, 0.55 * a)
  love.graphics.rectangle("fill", x, y, w, s)
  for i = 1, #DRIP_AT do
    love.graphics.rectangle("fill", round(x + w * DRIP_AT[i]), y + s, s, drip_len(i, u, t01, room))
  end
  set_col(BLOOD_FRESH, 0.85 * a)
  for i = 1, #DRIP_AT do
    love.graphics.rectangle("fill", round(x + w * DRIP_AT[i]),
      y + s + drip_len(i, u, t01, room), s, tip)
  end
end

-- Column entries run top-to-bottom; k advances inward from the heart corner.
local FALBANKA = {
  awning = {
    P = 12,
    tongue = {
      "eeeeeeeeeeee",
      "SSSSSSSSSSSS",
      "SSSSSSSSSSSS",
      "SSSSSSSSSSSS",
      "SSSSSSSSSSSS",
      "SSSSSSSSSSSS",
      "#SSSSSSSSSS#",
      "#SSSSSSSSSS#",
      ".#SSSSSSSS#.",
      "..#eeeeee#..",
      "...######...",
      "...ssssss...",
    },
    fold = "eeeeee#s....",
    plain = "eSSSSS#s....",
  },
  valance = {
    P = 8,
    tongue = {
      "eeeeeeee",
      "#SSSSSS#",
      ".#SSSS#.",
      "..####..",
      "..ssss..",
    },
    fold = "ee#s.",
    plain = "eS#s.",
  },
  folds = { [1] = true, [3] = true, [6] = true, [10] = true, [15] = true },
}
function Prims.falbanka_layout(spec, w, u)
  local cells = math.floor(w / u)
  local n = math.floor((cells - 4) / spec.P)
  if n % 2 == 0 then n = n - 1 end
  if n < 1 then return nil end
  local left = cells - n * spec.P
  local cap_l = math.floor(left / 2)
  return { n = n, cells = cells, cap_l = cap_l, cap_r = left - cap_l,
    off = math.floor((w - cells * u) / 2) }
end

local function cap_char(spec, row, k)
  local col = FALBANKA.folds[k] and spec.fold or spec.plain
  return col:sub(row, row)
end

local function falbanka_role(ch, stripe)
  if ch == "S" or ch == "e" then return ch .. stripe end
  if ch == "#" or ch == "s" then return ch end
  return nil
end

local function falbanka_cells(spec, lay)
  local rows = {}
  local mid = (lay.n - 1) / 2
  local function stripe_of(i) return ((i - mid) % 2 == 0) and 1 or 2 end
  local cap_stripe = stripe_of(lay.n)
  for r = 1, #spec.tongue do
    local row = {}
    for d = 1, lay.cap_l do
      row[#row + 1] = falbanka_role(cap_char(spec, r, d), cap_stripe) or false
    end
    local line = spec.tongue[r]
    for i = 0, lay.n - 1 do
      local stripe = stripe_of(i)
      for c = 1, spec.P do
        row[#row + 1] = falbanka_role(line:sub(c, c), stripe) or false
      end
    end
    for j = 1, lay.cap_r do
      row[#row + 1] = falbanka_role(cap_char(spec, r, lay.cap_r - j + 1), cap_stripe) or false
    end
    rows[r] = row
  end
  return rows
end

local function cell_rects(rows, roles, u, ox, oy)
  local runs = {}
  for r = 1, #rows do
    local row, c = rows[r], 1
    while c <= #row do
      local role = row[c]
      local c0 = c
      while c + 1 <= #row and row[c + 1] == role do c = c + 1 end
      if role then runs[#runs + 1] = { role = role, c = c0 - 1, n = c - c0 + 1, r = r - 1, h = 1 } end
      c = c + 1
    end
  end
  local open, merged = {}, {}
  for _, run in ipairs(runs) do
    local key = run.role .. ":" .. run.c .. ":" .. run.n
    local above = open[key]
    if above and above.r + above.h == run.r then
      above.h = above.h + 1
    else
      open[key] = run
      merged[#merged + 1] = run
    end
  end
  local by_role = {}
  for _, role in ipairs(roles) do by_role[role] = {} end
  for _, run in ipairs(merged) do
    local list = by_role[run.role]
    list[#list + 1] = ox + run.c * u
    list[#list + 1] = oy + run.r * u
    list[#list + 1] = run.n * u
    list[#list + 1] = run.h * u
  end
  return by_role
end

local FALBANKA_ROLES = { "#", "s", "e1", "e2", "S1", "S2" }

local function falbanka_geom(spec, w, u)
  local lay = Prims.falbanka_layout(spec, w, u)
  if not lay then return nil end
  local rows = falbanka_cells(spec, lay)
  return { by_role = cell_rects(rows, FALBANKA_ROLES, u, lay.off, 0), h = #spec.tongue * u }
end

local falbanka_geom_cache = {}

local function falbanka_geom_get(kind, w, u)
  local g = falbanka_geom_cache[kind]
  if g and g.w == w and g.u == u then return g.geom end
  local geom = falbanka_geom(FALBANKA[kind], w, u)
  falbanka_geom_cache[kind] = { w = w, u = u, geom = geom }
  return geom
end

local function falbanka_role_colour(role, pal)
  if role == "#" then return pal.DEEP[1], pal.DEEP[2], pal.DEEP[3], 1 end
  if role == "s" then return 0, 0, 0, 0.3 end
  local c = (role == "S1" and pal.ACCENT) or (role == "S2" and pal.FLASH_L)
    or (role == "e1" and pal.PRIMARY) or pal.FLASH_D
  return c[1], c[2], c[3], 1
end

local function paint_rects(by_role, roles, colour, x, y, pal, a)
  for _, role in ipairs(roles) do
    local list = by_role[role]
    if #list > 0 then
      local r, g, b, ca = colour(role, pal)
      love.graphics.setColor(r, g, b, ca * a)
      for i = 1, #list, 4 do
        love.graphics.rectangle("fill", x + list[i], y + list[i + 1], list[i + 2], list[i + 3])
      end
    end
  end
end

local function rgb24(c)
  return math.floor(c[1] * 255 + 0.5) * 65536 + math.floor(c[2] * 255 + 0.5) * 256
    + math.floor(c[3] * 255 + 0.5)
end

local function falbanka(kind, x, y, w, u, pal, a)
  a = a or 1
  if a <= 0.01 then return end
  local geom = falbanka_geom_get(kind, w, u)
  if not geom then return end
  if bake_supported ~= false and bake_placement_ok(x, y) then
    local e = bake_slot(kind, w, u, rgb24(pal.ACCENT), rgb24(pal.PRIMARY), rgb24(pal.FLASH_L),
      rgb24(pal.FLASH_D), rgb24(pal.DEEP))
    if not e.canvas then
      e.canvas = bake_run(w, geom.h, 0, 0, function()
        paint_rects(geom.by_role, FALBANKA_ROLES, falbanka_role_colour, 0, 0, pal, 1)
      end)
    end
    if e.canvas then
      bake_draw(e.canvas, x, y, a)
      return
    end
  end
  paint_rects(geom.by_role, FALBANKA_ROLES, falbanka_role_colour, x, y, pal, a)
end

function Prims.awning(x, y, w, u, pal, a) return falbanka("awning", x, y, w, u, pal, a) end

function Prims.valance(x, y, w, u, pal, a) return falbanka("valance", x, y, w, u, pal, a) end

-- Tiles extend beyond the panel; inset marks the valance’s inward start.
local HEART_FRAME = {
  out = 5,
  inset = 7,
  tl = {
    "..##.##.....",
    ".#HH#HH#....",
    "#HWHHHHH#...",
    "#HHHHHHH####",
    ".#HHHHH#AAAA",
    "..#HHH#FFFFF",
    "...#H#......",
    "...##F......",
    "...#AF......",
    "...#AF......",
    "...#AF......",
    "...#AF......",
  },
  bl = {
    "...#AF......",
    "...#AF......",
    "...#AF......",
    "...#AF......",
    "...#AF......",
    "...#AFFFFFFF",
    "...#AAAAAAAA",
    "....########",
  },
  bl_row0 = 6,
  top = "...#AF",
  bottom = ".....FA#",
  left = "...#AF",
  right = "......FA#",
}
Prims.HEART_FRAME = HEART_FRAME

local HEART_ROLES = { "#", "A", "F", "H", "W" }

local function heart_role_colour(role, pal)
  if role == "W" then return 1, 1, 1, 1 end
  local c = (role == "#" and pal.DEEP) or (role == "F" and pal.FRAME) or (role == "A" and pal.ACCENT) or pal.GLOW
  return c[1], c[2], c[3], 1
end

local function heart_rows(bitmap, mirror)
  local rows = {}
  for r = 1, #bitmap do
    local line = mirror and bitmap[r]:reverse() or bitmap[r]
    local row = {}
    for c = 1, #line do
      local ch = line:sub(c, c)
      row[c] = ch ~= "." and ch or false
    end
    rows[r] = row
  end
  return rows
end

local heart_geom_cache = {}

local function heart_geom(u)
  local g = heart_geom_cache[u]
  if g then return g end
  local tw, th, bh = #HEART_FRAME.tl[1], #HEART_FRAME.tl, #HEART_FRAME.bl
  local tiles = {
    { rows = heart_rows(HEART_FRAME.tl, false), ax = 0, ay = 0, h = th },
    { rows = heart_rows(HEART_FRAME.tl, true), ax = tw, ay = 0, h = th },
    { rows = heart_rows(HEART_FRAME.bl, false), ax = 0, ay = th, h = bh },
    { rows = heart_rows(HEART_FRAME.bl, true), ax = tw, ay = th, h = bh },
  }
  for _, t in ipairs(tiles) do
    t.by_role = cell_rects(t.rows, HEART_ROLES, u, 0, 0)
    t.ax, t.ay, t.w, t.h = t.ax * u, t.ay * u, tw * u, t.h * u
  end
  g = { tiles = tiles, w = 2 * tw * u, h = (th + bh) * u }
  heart_geom_cache[u] = g
  return g
end

local STRIP_ROLES = { "#", "A", "F" }

local strip_cells_cache = {}
local function strip_cells(line, role)
  local by_role = strip_cells_cache[line]
  if not by_role then
    by_role = {}
    for i = 1, #line do
      local ch = line:sub(i, i)
      local list = by_role[ch]
      if not list then list = {}; by_role[ch] = list end
      list[#list + 1] = i
    end
    strip_cells_cache[line] = by_role
  end
  return by_role[role]
end

local function heart_strip(line, role, horiz, at, from, len, u)
  if len <= 0 then return end
  local cells = strip_cells(line, role)
  if not cells then return end
  for k = 1, #cells do
    local i = cells[k]
    if horiz then
      love.graphics.rectangle("fill", from, at + (i - 1) * u, len, u)
    else
      love.graphics.rectangle("fill", at + (i - 1) * u, from, u, len)
    end
  end
end

function Prims.heart_frame(x, y, w, h, u, pal, a)
  a = a or 1
  if a <= 0.01 then return end
  local HF = HEART_FRAME
  local out, tw = HF.out, #HF.tl[1]
  -- Whole pixels keep the cell grid crisp and let the baked corners serve a panel mid-slide.
  local x0, y0 = round(x - out * u), round(y - out * u)
  local x1, y1 = round(x + w + (out - tw) * u), round(y + h - HF.bl_row0 * u)
  local hx, hw = x0 + tw * u, x1 - x0 - tw * u
  local vy, vh = y0 + #HF.tl * u, y1 - y0 - #HF.tl * u
  for _, role in ipairs(STRIP_ROLES) do
    local r, g, b, ca = heart_role_colour(role, pal)
    love.graphics.setColor(r, g, b, ca * a)
    heart_strip(HF.top, role, true, y0, hx, hw, u)
    heart_strip(HF.bottom, role, true, y1, hx, hw, u)
    heart_strip(HF.left, role, false, x0, vy, vh, u)
    heart_strip(HF.right, role, false, x1, vy, vh, u)
  end

  local geom = heart_geom(u)
  local tiles = geom.tiles
  if bake_supported ~= false and bake_placement_ok(x0, y0) and bake_placement_ok(x1, y1) then
    local e = bake_slot("heart", 0, u, rgb24(pal.DEEP), rgb24(pal.FRAME), rgb24(pal.ACCENT),
      rgb24(pal.PRIMARY), rgb24(pal.FLASH_L), rgb24(pal.GLOW))
    if not e.canvas then
      e.canvas = bake_run(geom.w, geom.h, 0, 0, function()
        for _, t in ipairs(tiles) do
          paint_rects(t.by_role, HEART_ROLES, heart_role_colour, t.ax, t.ay, pal, 1)
        end
      end)
      if e.canvas then
        e.quads = {}
        for i, t in ipairs(tiles) do
          e.quads[i] = love.graphics.newQuad(t.ax, t.ay, t.w, t.h, geom.w, geom.h)
        end
      end
    end
    if e.canvas then
      local mode, alphamode = love.graphics.getBlendMode()
      love.graphics.setBlendMode("alpha", "premultiplied")
      love.graphics.setColor(a, a, a, a)
      for i = 1, 4 do
        love.graphics.draw(e.canvas, e.quads[i], i % 2 == 1 and x0 or x1, i <= 2 and y0 or y1)
      end
      love.graphics.setBlendMode(mode, alphamode)
      return
    end
  end
  for i = 1, 4 do
    paint_rects(tiles[i].by_role, HEART_ROLES, heart_role_colour, i % 2 == 1 and x0 or x1,
      i <= 2 and y0 or y1, pal, a)
  end
end

function Prims.heart_valance_span(x, w, u)
  local inset = HEART_FRAME.inset * u
  return x + inset, w - 2 * inset
end

local function tag_string_rects(w, u)
  local list = {}
  local dash = math.max(2, u * 2)
  local dx = 0
  while dx < w do
    RectMesh.rect(list, dx, 0, math.min(dash, w - dx), 1, 1, 1, 1, 0.85)
    dx = dx + dash * 2
  end
  return list
end

function Prims.tag_string(x, y, w, u, r, g, b, a, mesh_stable)
  local mesh = mesh_stable and w > 0 and u > 0
    and RectMesh.cached(deco, "tag_string", w, u, nil, nil, nil, nil, nil, nil, tag_string_rects, w, u)
  RectMesh.fill(mesh, x, y, r, g, b, a, tag_string_rects, w, u)
end
function Prims.quatrefoil(cx, cy, r, gold, a, pulse)
  pulse = pulse or 0.5
  local s = math.max(1, round(r * 2 / 9))
  draw_px(QUATREFOIL_PX, cx, cy, s, gold, (0.80 + Prims.EVIL.PULSE_AMP * pulse) * a, BOW_WINE)
end

local function cornice_rects(w, u, bg, gold)
  local E = Prims.EVIL
  local list = {}
  local ch, pitch, mw = u * 4, u * 12, u * 6
  local n = math.floor(w / pitch)
  RectMesh.rect(list, 0, -2, w, 2, bg[1], bg[2], bg[3], 0.97)
  RectMesh.rect(list, 0, -1, w, 1, gold[1], gold[2], gold[3], E.A_HAIR)
  if n >= 2 then
    local x0 = math.floor((w - (n - 1) * pitch - mw) / 2)
    for i = 0, n - 1 do RectMesh.rect(list, x0 + i * pitch, -ch, mw, ch, bg[1], bg[2], bg[3], 0.97) end
    for i = 0, n - 1 do
      RectMesh.rect(list, x0 + i * pitch, -ch, mw, 1, gold[1], gold[2], gold[3], E.A_ACCENT)
    end
    for i = 0, n - 1 do RectMesh.rect(list, x0 + i * pitch, -ch + 1, mw, 1, 0, 0, 0, 0.30) end
  end
  return list
end

function Prims.cornice_crenel(x, y, w, u, bg, gold, a, mesh_stable)
  if (a or 1) <= 0.01 then return end
  local mesh = mesh_stable and w > 0 and u > 0 and RectMesh.cached(deco, "cornice_crenel", w, u,
    bg[1], bg[2], bg[3], gold[1], gold[2], gold[3], cornice_rects, w, u, bg, gold)
  RectMesh.fill(mesh, x, y, 1, 1, 1, a, cornice_rects, w, u, bg, gold)
end

local OGIVE_STEPS = 4

local function ogive_rects(w, u, gold)
  local list = {}
  local sa, gr, gg, gb = Prims.EVIL.A_STRUCT, gold[1], gold[2], gold[3]
  local sh = math.max(1, math.floor(math.min(u * 8, math.floor(w * 0.35)) / OGIVE_STEPS))
  local half = math.floor(w / 2)
  local wprev = half
  for i = 0, OGIVE_STEPS - 1 do
    local wi = math.floor(half * (OGIVE_STEPS - 1 - i) / OGIVE_STEPS)
    local y = i * sh
    RectMesh.rect(list, 0, y, wi, sh, 0, 0, 0, 0.35)
    RectMesh.rect(list, w - wi, y, wi, sh, 0, 0, 0, 0.35)
    if wi > 0 then
      RectMesh.rect(list, wi, y, 1, sh, gr, gg, gb, sa)
      RectMesh.rect(list, w - wi - 1, y, 1, sh, gr, gg, gb, sa)
    end
    if wprev > wi then
      RectMesh.rect(list, wi, y, wprev - wi, 1, gr, gg, gb, sa)
      RectMesh.rect(list, w - wprev, y, wprev - wi, 1, gr, gg, gb, sa)
    end
    wprev = wi
  end
  return list
end

function Prims.ogive_top(x, y, w, u, gold, a, pulse)
  pulse = pulse or 0.5
  x, y, w = round(x), round(y), round(w)
  local E = Prims.EVIL
  local mesh = RectMesh.cached(deco, "ogive_top", w, u, gold[1], gold[2], gold[3], nil, nil, nil,
    ogive_rects, w, u, gold)
  RectMesh.fill(mesh, x, y, 1, 1, 1, a, ogive_rects, w, u, gold)
  Prims.draw_diamond(x + math.floor(w / 2), y - u * 3, u, gold, (E.A_ACCENT + E.PULSE_AMP * pulse) * a)
end

function Prims.chains(x, y0, y1, u, gold, a, sway)
  sway = sway or 0
  local s = math.max(1, round(u / 2))
  local lh = s * 4   -- 1px shorter than a link so adjacent links interlock
  local n = math.max(2, math.floor((y1 - y0) / lh))
  local la = 0.60 * a
  for i = 0, n - 1 do
    local t = i / n
    local lx = round(x + sway * t)
    local ly = round(y0 + lh * i)
    draw_px(LINK_PX, lx, ly + s * 2, s, gold, la)
  end
  set_col(gold, 0.80 * a)
  love.graphics.rectangle("fill", round(x) - 1, round(y0) - 1, 2, 2)
  love.graphics.rectangle("fill", round(x + sway) - 1, round(y1) - 1, 2, 2)
end

function Prims.draw_sparkle(cx, cy, r, col, a)
  draw_px(SPARK_PX, cx, cy, math.max(1, round(r / 2)), col, a)
end

function Prims.embers(x, y, w, h, u, now, a, n, span)
  if h < u * 20 then return end
  n = n or 7
  local cyc = math.max(1, span or h)
  for ei = 1, n do
    local sp = (14 + (ei % 4) * 5.5) * u
    local yr = (now * sp + ei * 97.3 * u) % cyc
    if yr <= h then
    local ex = x + (0.5 + 0.5 * math.sin(ei * 12.9898)) * w + math.sin(now * 1.6 + ei * 1.7) * u * 4
    local ey = y + h - yr
    local rise = yr / cyc
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
end

function Prims.photo_corners(x, y, w, h, col, a, arm)
  arm = arm or 3
  set_col(col, a)
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
  set_col(glow, 0.05 * a)
  love.graphics.rectangle("fill", x, y + math.floor(h * 0.45), w, math.ceil(h * 0.55))
  Prims.counter_glow(x, y, w, h, gold, 0.9 * a, pulse, 0)
  set_col(gold, 0.22 * a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  if arch then Prims.ogive_top(x, y, w, u, gold, a, pulse) end
end

function Prims.card_sleeve(x, y, w, h, u, acc, glow, shr, shg, shb, a)
  a = a or 1
  local rad = math.max(2, u * 3)
  set_col(glow, 0.06 * a)
  love.graphics.rectangle("fill", x, y, w, h, rad, rad)
  set_col(acc, 0.05 * a)
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

function Prims.petals(x, y, w, h, u, now, a, n)
  if (a or 1) <= 0.01 then return end
  if w < u * 12 or h < u * 6 then return end
  a = a or 1
  n = n or 5
  for pi = 1, n do
    local sp  = (3 + (pi % 3) * 1.5) * u
    local yr  = (now * sp + pi * 61.7 * u) % h
    local mx  = x + (0.5 + 0.5 * math.sin(pi * 12.9898)) * w + math.sin(now * 0.9 + pi * 2.1) * u * 4
    local my  = y + yr
    local tw  = Prims.twinkle01(now, pi)
    local env = math.min(1, yr / (h * 0.18)) * math.min(1, (h - yr) / (h * 0.25))
    local aa  = (0.30 + 0.45 * tw) * env * a
    local sz  = math.max(2, (pi % 4 == 0) and u * 3 or u * 2)
    local px, py = round(mx), round(my)
    if pi % 2 == 0 then love.graphics.setColor(0.98, 0.72, 0.82, aa)
    else                love.graphics.setColor(0.62, 0.86, 0.86, aa) end
    love.graphics.rectangle("fill", px, py, sz, sz)
    love.graphics.rectangle("fill", px + math.floor(sz / 4), py - math.max(1, math.floor(sz / 2)),
      math.max(1, math.ceil(sz / 2)), math.max(1, math.floor(sz / 2)))
    love.graphics.setColor(1, 1, 1, aa * 0.4)
    love.graphics.rectangle("fill", px, py, math.max(1, math.floor(sz / 2)), 1)
  end
end

local HEART_SEAL_PX = parse_px({
  "..O...O..",
  ".OXO.OXO.",
  "OXXXOXXXO",
  "OXXXXXXXO",
  "OXWXXXWXO",
  ".OXXXXXO.",
  "..OXXXO..",
  "...OXO...",
  "....O....",
})

function Prims.heart_seal(cx, cy, r, pg, acc, a)
  a = a or 1
  cx, cy = round(cx), round(cy)
  local s  = math.max(1, round(r * 2 / 9))
  local hr = s * 5
  set_col(pg, 0.14 * a)
  love.graphics.rectangle("fill", cx - hr, cy - hr, hr * 2, hr * 2, hr, hr)
  draw_px(HEART_SEAL_PX, cx, cy, s, pg, 0.95 * a, acc, WHITE_C, true)
  Prims.draw_sparkle(cx + s * 2, cy - s * 3, math.max(1, s * 1.5), WHITE_C, 0.7 * a)
end

return Prims
