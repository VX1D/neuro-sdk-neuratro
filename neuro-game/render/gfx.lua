local gfx = {}

local floor = math.floor

function gfx.round(x) return floor(x + 0.5) end

function gfx.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function gfx.clamp01(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

function gfx.set_col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a)
end

local function print_shadow_text(txt, x, y, col, a, sh_a, off, outline)
  love.graphics.setColor(0, 0, 0, sh_a)
  love.graphics.print(txt, x + off, y + off)
  if outline then
    love.graphics.print(txt, x - off, y - off)
    love.graphics.print(txt, x + off, y - off)
    love.graphics.print(txt, x - off, y + off)
  end
  love.graphics.setColor(col[1], col[2], col[3], a)
  love.graphics.print(txt, x, y)
end

local ST_MAX = 256
local st_map, st_n = {}, 0

local st_font_ids = setmetatable({}, { __mode = "k" })
local st_font_next = 0
local function st_font_id(f)
  local id = st_font_ids[f]
  if not id then
    st_font_next = st_font_next + 1
    id = st_font_next
    st_font_ids[f] = id
  end
  return id
end

local function st_fill_body(t, s, col, a, sh_a, off, outline, sc, seg_sh, mc, seg_main)
  t:clear()
  sc[1], sc[2], sc[3], sc[4] = 0, 0, 0, sh_a
  seg_sh[1], seg_sh[2] = sc, s
  t:add(seg_sh, off, off)
  if outline then
    t:add(seg_sh, -off, -off)
    t:add(seg_sh, off, -off)
    t:add(seg_sh, -off, off)
  end
  mc[1], mc[2], mc[3], mc[4] = col[1], col[2], col[3], a
  seg_main[1], seg_main[2] = mc, s
  t:add(seg_main, 0, 0)
end

local function st_fill(e, s, col, a, sh_a, off, outline)
  local sc = e._sc
  if not sc then sc = { 0, 0, 0, 0 }; e._sc = sc end
  local seg_sh = e._seg_sh
  if not seg_sh then seg_sh = { sc, s }; e._seg_sh = seg_sh end
  local mc = e._mc
  if not mc then mc = { 0, 0, 0, 0 }; e._mc = mc end
  local seg_main = e._seg_main
  if not seg_main then seg_main = { mc, s }; e._seg_main = seg_main end
  local ok = pcall(st_fill_body, e.text, s, col, a, sh_a, off, outline, sc, seg_sh, mc, seg_main)
  if not ok then return false end
  e.off, e.outline = off, outline
  e.r, e.g, e.b, e.a, e.sh = col[1], col[2], col[3], a, sh_a
  return true
end

local function st_entry(s, col, a, sh_a, off, outline)
  local lg = love.graphics
  if type(lg.newText) ~= "function" then return nil end
  local f = lg.getFont and lg.getFont()
  if not f then return nil end
  local key = st_font_id(f) .. "\0" .. s
  local e = st_map[key]
  if e then
    if e.off == off and e.outline == outline and e.a == a and e.sh == sh_a
      and e.r == col[1] and e.g == col[2] and e.b == col[3] then
      return e
    end
    return st_fill(e, s, col, a, sh_a, off, outline) and e or nil
  end
  local ok, text = pcall(lg.newText, f)
  if not ok or not text or type(text.add) ~= "function" or type(text.clear) ~= "function" then
    return nil
  end
  e = { text = text }
  if not st_fill(e, s, col, a, sh_a, off, outline) then return nil end
  if st_n >= ST_MAX then st_map, st_n = {}, 0 end
  st_map[key], st_n = e, st_n + 1
  return e
end

function gfx.shadow_text(txt, x, y, col, a, sh_a, off, outline)
  off = off or 1
  local s = tostring(txt)
  if s ~= "" then
    local e = st_entry(s, col, a or 1, sh_a or 1, off, outline or false)
    if e then
      local lg = love.graphics
      lg.setColor(1, 1, 1, 1)
      lg.draw(e.text, x, y)
      lg.setColor(col[1], col[2], col[3], a)
      return
    end
  end
  print_shadow_text(txt, x, y, col, a, sh_a, off, outline)
end

return gfx
