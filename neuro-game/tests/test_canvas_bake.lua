
local Cap = require("tests.raster_capture")
Cap.enable_canvas_capture()

local check, done = require("tests.helpers").harness("canvas bake")
local Prims = require("hud.prims")

local lg = love.graphics
local A = { 0.275, 0.847, 0.812 }
local B = { 1.000, 0.420, 0.541 }

local baked_canvas, canvas_blits, canvases_made, canvases_live, canvases_peak = nil, 0, 0, 0, 0

local real_new = lg.newCanvas
lg.newCanvas = function(w, h)
  local c = real_new(w, h)
  if c then
    canvases_made = canvases_made + 1
    canvases_live = canvases_live + 1
    if canvases_live > canvases_peak then canvases_peak = canvases_live end
    local rel = c.release
    c.release = function(self) canvases_live = canvases_live - 1; return rel(self) end
  end
  return c
end

local real_draw = lg.draw
lg.draw = function(img, ...)
  if type(img) == "table" and img.__raster_canvas then
    baked_canvas = img
    canvas_blits = canvas_blits + 1
  end
  return real_draw(img, ...)
end

local function reset_counters()
  baked_canvas, canvas_blits, canvases_made, canvases_peak = nil, 0, 0, 0
end

local function ops_of(fn)
  Cap.rec.take()
  fn()
  return Cap.rec.take()
end

local function count_verb(ops, letter)
  local n = 0
  for i = 1, #ops do if ops[i]:sub(1, 1) == letter then n = n + 1 end end
  return n
end

local function blit_origin(ops)
  for i = 1, #ops do
    if ops[i]:sub(1, 1) == "I" then
      local x, y = ops[i]:match("^I %S+ %S+ %S+ %S+ %S+ (%S+) (%S+)")
      return tonumber(x), tonumber(y)
    end
  end
end

local function same_ops(got, want)
  if #got ~= #want then return false, string.format("%d ops vs %d", #got, #want) end
  for i = 1, #got do
    if got[i] ~= want[i] then
      return false, string.format("op %d:\n  baked    %s\n  fallback %s", i, got[i], want[i])
    end
  end
  return true
end

local function arc_box(cx, cy, r, a1, a2, pie)
  local x0, y0, x1, y1
  local function put(px, py)
    x0 = math.min(x0 or px, px); y0 = math.min(y0 or py, py)
    x1 = math.max(x1 or px, px); y1 = math.max(y1 or py, py)
  end
  if pie then put(cx, cy) end
  put(cx + r * math.cos(a1), cy + r * math.sin(a1))
  put(cx + r * math.cos(a2), cy + r * math.sin(a2))
  local lo, hi = math.min(a1, a2), math.max(a1, a2)
  for k = -4, 8 do
    local t = k * math.pi / 2
    if t >= lo and t <= hi then put(cx + r * math.cos(t), cy + r * math.sin(t)) end
  end
  return x0, y0, x1, y1
end

local function outside_canvas(ops, cw, ch)
  for i = 1, #ops do
    local t = {}
    for tokn in ops[i]:gmatch("%S+") do t[#t + 1] = tokn end
    local verb, mode = t[1], t[2]
    local x, y = tonumber(t[8]), tonumber(t[9])
    local pad = (mode == "line") and tonumber(t[#t]) / 2 or 0
    local x0, y0, x1, y1
    if verb == "R" then
      x0, y0, x1, y1 = x, y, x + tonumber(t[10]), y + tonumber(t[11])
    elseif verb == "C" then
      local r = tonumber(t[10])
      x0, y0, x1, y1 = x - r, y - r, x + r, y + r
    elseif verb == "A" then
      x0, y0, x1, y1 = arc_box(x, y, tonumber(t[10]), tonumber(t[11]), tonumber(t[12]),
        mode == "fill")
    end
    if x0 and (x0 - pad < 0 or y0 - pad < 0 or x1 + pad > cw or y1 + pad > ch) then
      return string.format("%s %s at [%.2f,%.2f]-[%.2f,%.2f] escapes %dx%d",
        verb, mode, x0 - pad, y0 - pad, x1 + pad, y1 + pad, cw, ch)
    end
  end
end

local CASES = {
  { name = "valance", fn = function(...) return Prims.valance(...) end,
    x = 40, y = 24, w = 208, u = 1, a = 0.9 },
  { name = "awning", fn = function(...) return Prims.awning(...) end,
    x = 17, y = 61, w = 235, u = 1, a = 1.0 },
  { name = "valance u=2", fn = function(...) return Prims.valance(...) end,
    x = 8, y = 8, w = 362, u = 2, a = 0.55 },
  { name = "awning u=2", fn = function(...) return Prims.awning(...) end,
    x = 8, y = 8, w = 489, u = 2, a = 0.42 },
}

for _, C in ipairs(CASES) do
  reset_counters()

  local first = ops_of(function() C.fn(C.x, C.y, C.w, C.u, A, B, C.a, true) end)
  check(C.name .. ": first sight of a key draws primitives and allocates nothing",
    canvases_made == 0 and count_verb(first, "I") == 0 and #first > 10, #first)

  local second = ops_of(function() C.fn(C.x, C.y, C.w, C.u, A, B, C.a, true) end)
  check(C.name .. ": second sight bakes once and emits a single blit",
    canvases_made == 1 and canvas_blits == 1 and #second == 1 and second[1]:sub(1, 1) == "I",
    string.format("made=%d blits=%d ops=%d", canvases_made, canvas_blits, #second))

  local bx, by = blit_origin(second)
  local ox, oy = bx and (C.x - bx), by and (C.y - by)
  check(C.name .. ": blit lands one pad up and left of the caller's origin",
    ox ~= nil and oy ~= nil and ox > 0 and oy > 0,
    tostring(ox) .. "," .. tostring(oy))

  local painted = Cap.canvas_ops(baked_canvas)
  local reference = ops_of(function() C.fn(ox, oy, C.w, C.u, A, B, C.a, false) end)
  local ok, why = same_ops(painted or {}, reference)
  check(C.name .. ": baked content is element-for-element the fallback drawing", ok, why)

  check(C.name .. ": the bake replaces more than 20 primitive calls with one",
    #reference >= 20, #reference)

  local cw, ch = baked_canvas:getDimensions()
  local escaped = outside_canvas(painted or {}, cw, ch)
  check(C.name .. ": every baked shape fits inside the padded canvas", escaped == nil, escaped)

  local additive = 0
  for i = 1, #reference do if reference[i]:find(" add ", 1, true) then additive = additive + 1 end end
  check(C.name .. ": no additive layer inside the baked band", additive == 0, additive)

  reset_counters()
  for _ = 1, 200 do C.fn(C.x, C.y, C.w, C.u, A, B, C.a, true) end
  check(C.name .. ": 200 identical frames rebake nothing",
    canvases_made == 0 and canvas_blits == 200,
    string.format("made=%d blits=%d", canvases_made, canvas_blits))

  reset_counters()
  local moving = 0
  for i = 1, 200 do
    local a = 0.20 + i * 0.001
    Cap.rec.take()
    C.fn(C.x, C.y, C.w, C.u, A, B, a, true)
    moving = moving + count_verb(Cap.rec.take(), "I")
  end
  check(C.name .. ": an alpha that moves every frame never allocates a canvas",
    canvases_made == 0 and moving == 0,
    string.format("made=%d blits=%d", canvases_made, moving))

  reset_counters()
  Cap.rec.take()
  C.fn(C.x + 0.5, C.y, C.w, C.u, A, B, C.a, true)
  local frac = Cap.rec.take()
  check(C.name .. ": a fractional position keeps the primitive path",
    canvases_made == 0 and count_verb(frac, "I") == 0, #frac)

  reset_counters()
  Cap.rec.take()
  C.fn(C.x, C.y, C.w, C.u, A, B, C.a, false)
  local unstable = Cap.rec.take()
  check(C.name .. ": an unstable caller is never baked",
    canvases_made == 0 and count_verb(unstable, "I") == 0, #unstable)
end

local SWEEP_W = { 208, 235, 247, 320, 356, 362, 380, 432, 489, 513, 640, 724, 760 }
local sweep_bad, sweep_diff, sweep_n = nil, nil, 0
for _, fn in ipairs({ Prims.valance, Prims.awning }) do
  for _, w in ipairs(SWEEP_W) do
    for _, u in ipairs({ 1, 2, 3 }) do
      reset_counters()
      fn(24, 12, w, u, A, B, 0.83, true)
      Cap.rec.take()
      fn(24, 12, w, u, A, B, 0.83, true)
      local blit = Cap.rec.take()
      if baked_canvas then
        sweep_n = sweep_n + 1
        local bx, by = blit_origin(blit)
        local cw, ch = baked_canvas:getDimensions()
        local painted = Cap.canvas_ops(baked_canvas) or {}
        sweep_bad = sweep_bad or outside_canvas(painted, cw, ch)
        local ref = ops_of(function() fn(24 - bx, 12 - by, w, u, A, B, 0.83, false) end)
        local ok2, why2 = same_ops(painted, ref)
        if not ok2 then sweep_diff = sweep_diff or (w .. "/" .. u .. ": " .. tostring(why2)) end
      end
    end
  end
end
check("every swept band bakes and stays inside its canvas", sweep_n == 78 and sweep_bad == nil,
  sweep_bad or ("baked " .. sweep_n .. " of 78"))
check("every swept band is element-for-element its fallback drawing", sweep_diff == nil, sweep_diff)

reset_counters()
local WIDTHS = { 208, 216, 224, 232, 240, 248, 256, 264, 272, 280, 288, 296 }
for _ = 1, 3 do
  for _, w in ipairs(WIDTHS) do
    Prims.valance(40, 24, w, 1, A, B, 0.9, true)
    Prims.valance(40, 24, w, 1, A, B, 0.9, true)
  end
end
check("the bake cache is bounded: live canvases stay far below the number of keys",
  canvases_peak <= 8 and canvases_made >= #WIDTHS,
  string.format("peak=%d made=%d keys=%d", canvases_peak, canvases_made, #WIDTHS))

reset_counters()
lg.setBlendMode("add")
lg.setLineWidth(3)
Prims.valance(64, 24, 320, 1, A, B, 0.77, true)
Prims.valance(64, 24, 320, 1, A, B, 0.77, true)
check("a bake restores blend mode, render target and line width",
  canvases_made == 1 and lg.getBlendMode() == "add" and lg.getLineWidth() == 1
  and lg.getCanvas() == nil,
  string.format("made=%d blend=%s lw=%s canvas=%s", canvases_made,
    tostring(lg.getBlendMode()), tostring(lg.getLineWidth()), tostring(lg.getCanvas())))

local ambient_leak = 0
for _, op in ipairs(Cap.canvas_ops(baked_canvas) or {}) do
  if not op:find(" alpha ", 1, true) then ambient_leak = ambient_leak + 1 end
end
check("an ambient blend mode does not leak into the bake",
  ambient_leak == 0 and #(Cap.canvas_ops(baked_canvas) or {}) > 10, ambient_leak)
lg.setBlendMode("alpha")

done()
