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
local st_clock = 0

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

local function st_lookup(fid, vkey, s)
  local by_variant = st_map[fid]
  local by_text = by_variant and by_variant[vkey]
  return by_text and by_text[s]
end

local function st_store(fid, vkey, s, e)
  local by_variant = st_map[fid]
  if not by_variant then by_variant = {}; st_map[fid] = by_variant end
  local by_text = by_variant[vkey]
  if not by_text then by_text = {}; by_variant[vkey] = by_text end
  by_text[s] = e
end

local function st_evict_lru()
  local v_fid, v_vkey, v_s, v_used = nil, nil, nil, math.huge
  for fid, by_variant in pairs(st_map) do
    for vkey, by_text in pairs(by_variant) do
      for s, e in pairs(by_text) do
        if e.used < v_used then v_fid, v_vkey, v_s, v_used = fid, vkey, s, e.used end
      end
    end
  end
  if v_s then
    local by_variant = st_map[v_fid]
    local by_text = by_variant[v_vkey]
    local victim = by_text[v_s]
    if victim and victim.text and victim.text.release then pcall(victim.text.release, victim.text) end
    by_text[v_s] = nil
    -- Clear the empty shells too, or st_map and by_variant grow unbounded while the leaf entries
    -- stay capped at ST_MAX.
    if next(by_text) == nil then
      by_variant[v_vkey] = nil
      if next(by_variant) == nil then st_map[v_fid] = nil end
    end
    st_n = st_n - 1
  end
end

local function st_entry(s, col, a, sh_a, off, outline, variant)
  local lg = love.graphics
  if type(lg.newText) ~= "function" then return nil end
  local f = lg.getFont and lg.getFont()
  if not f then return nil end
  local fid = st_font_id(f)
  local vkey = variant or ""
  local e = st_lookup(fid, vkey, s)
  st_clock = st_clock + 1
  if e then
    e.used = st_clock
    if e.off == off and e.outline == outline and e.a == a and e.sh == sh_a
      and e.r == col[1] and e.g == col[2] and e.b == col[3] then
      return e
    end
    if st_fill(e, s, col, a, sh_a, off, outline) then return e end
    -- The refill cleared the Text before it threw; poison the descriptor or the fast path draws
    -- an empty buffer.
    e.r, e.g, e.b, e.a, e.sh = nil, nil, nil, nil, nil
    return nil
  end
  local ok, text = pcall(lg.newText, f)
  if not ok or not text or type(text.add) ~= "function" or type(text.clear) ~= "function" then
    return nil
  end
  e = { text = text, used = st_clock }
  if not st_fill(e, s, col, a, sh_a, off, outline) then
    if text.release then pcall(text.release, text) end
    return nil
  end
  if st_n >= ST_MAX then
    st_evict_lru()
  end
  st_store(fid, vkey, s, e)
  st_n = st_n + 1
  return e
end

function gfx.shadow_text(txt, x, y, col, a, sh_a, off, outline, tint, variant)
  off = off or 1
  tint = tint or 1
  local s = tostring(txt)
  if s ~= "" then
    local e = st_entry(s, col, a or 1, sh_a or 1, off, outline or false, variant)
    if e then
      local lg = love.graphics
      lg.setColor(1, 1, 1, tint)
      lg.draw(e.text, x, y)
      -- Match the fallback's residual colour, which is tinted too.
      lg.setColor(col[1], col[2], col[3], (a or 1) * tint)
      return
    end
  end
  print_shadow_text(txt, x, y, col, (a or 1) * tint, (sh_a or 1) * tint, off, outline)
end

function gfx.release_text_cache()
  for _, by_variant in pairs(st_map) do
    for _, by_text in pairs(by_variant) do
      for _, e in pairs(by_text) do
        if e and e.text and e.text.release then pcall(e.text.release, e.text) end
      end
    end
  end
  st_map, st_n = {}, 0
end

gfx._hot_reload_release = gfx.release_text_cache

return gfx
