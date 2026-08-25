
_G.NEURO_TEST = true  -- reaches module internals published only behind the test seam

local Cap = require("tests.raster_capture")
local check, done = require("tests.helpers").harness("evil glow pool")

local Palette = require("render.palette")
local EMBER = Palette.PALETTES.evil.D_ORANGE

local TSS = G.TILESCALE * G.TILESIZE
local VT = { x = 0, y = 0, w = 1, h = 1.4, scale = 1 }
local CARD = { x = 0, y = 0, w = VT.w * TSS, h = VT.h * TSS }
local PAD = VT.w * 0.05 * TSS
local BAND = { x = CARD.x - PAD, w = CARD.w + PAD * 2,
  h = CARD.h * 0.34, y = CARD.y + CARD.h + PAD - CARD.h * 0.34 }
local COMMIT, NOW = 0.5, 3.0
local EPS = 0.02

local function broken_mesh()
  return setmetatable({}, { __index = function() return function() end end })
end

local function mesh_recorder()
  local made = {}
  return made, function(vertices)
    local m = { __raster_mesh = true, vertices = vertices }
    function m:setVertexMap(ix) self.map = ix end
    function m:getVertexCount() return #self.vertices end
    made[#made + 1] = m
    return m
  end
end

local function partial_mesh()
  return { setVertexMap = function() end, getVertexCount = function() return 0 end }
end

local paint_err

local function paint(new_mesh)
  package.loaded["hud.cards"] = nil
  Cap.gfx.newMesh = new_mesh
  local Cards = require("hud.cards")
  G.NEURO.persona = "evil"
  Cap.rec.reset()
  Cap.rec.enabled = true
  local ok, err = pcall(Cards.run_glow, {}, VT, 1, COMMIT, NOW)
  paint_err = nil
  if not ok then paint_err = tostring(err) end
  pcall(love.graphics.pop)
  return Cap.rec.take()
end

local function is_ember(op)
  return op.r and math.abs(op.r - EMBER[1]) < 0.002
    and math.abs(op.g - EMBER[2]) < 0.002
    and math.abs(op.b - EMBER[3]) < 0.002
end

local function ember_washes(ops, meshes)
  local out, mi = {}, 0
  for _, line in ipairs(ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "M" then
      mi = mi + 1
      local m = meshes[mi]
      if is_ember(op) and m then
        local x, y, sx, sy = op.n[1], op.n[2], op.n[3], op.n[4]
        local ymin, ymax = math.huge, -math.huge
        for _, v in ipairs(m.vertices) do
          if v[2] < ymin then ymin = v[2] end
          if v[2] > ymax then ymax = v[2] end
        end
        local top, bot = 0, 0
        for _, v in ipairs(m.vertices) do
          if v[2] <= ymin then top = math.max(top, v[8] or 1) end
          if v[2] >= ymax then bot = math.max(bot, v[8] or 1) end
        end
        out[#out + 1] = { kind = "mesh", x0 = x, x1 = x + sx, y0 = y, y1 = y + sy,
          a0 = top * op.a, a1 = bot * op.a, rx = 0, line = line }
      end
    elseif op and op.v == "R" and op.mode == "fill" and is_ember(op)
      and (op.w or 0) > CARD.w * 0.5 then
      out[#out + 1] = { kind = "rect", x0 = op.x, x1 = op.x + op.w, y0 = op.y, y1 = op.y + op.h,
        a0 = op.a, a1 = op.a, rx = op.n[5], line = line }
    end
  end
  return out
end

local SAMPLES = 800

local function worst_interior_step(washes)
  local y0, y1 = CARD.y - 8, CARD.y + CARD.h + 8
  local prev, peak, worst, worst_y = nil, 0, 0, nil
  for i = 0, SAMPLES do
    local y = y0 + (y1 - y0) * i / SAMPLES
    local s = 0
    for _, w in ipairs(washes) do
      if y >= w.y0 and y <= w.y1 then
        local f = (w.y1 > w.y0) and (y - w.y0) / (w.y1 - w.y0) or 1
        s = s + w.a0 + (w.a1 - w.a0) * f
      end
    end
    if s > peak then peak = s end
    if prev and y > CARD.y + 1 and y < CARD.y + CARD.h - 1 then
      local d = math.abs(s - prev)
      if d > worst then worst, worst_y = d, y end
    end
    prev = s
  end
  return worst, peak, worst_y
end

local function bounds(washes)
  local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
  for _, w in ipairs(washes) do
    if w.x0 < x0 then x0 = w.x0 end
    if w.x1 > x1 then x1 = w.x1 end
    if w.y0 < y0 then y0 = w.y0 end
    if w.y1 > y1 then y1 = w.y1 end
  end
  return x0, x1, y0, y1
end

local function kinds(washes)
  local r, m = 0, 0
  for _, w in ipairs(washes) do
    if w.kind == "rect" then r = r + 1 else m = m + 1 end
  end
  return r, m
end

local function peak_alpha(washes)
  local p = 0
  for _, w in ipairs(washes) do p = math.max(p, w.a0, w.a1) end
  return p
end

local function verdict(tag, washes)
  local worst, peak, wy = worst_interior_step(washes)
  local x0, x1, y0, y1 = bounds(washes)
  local top_a, peak_a = nil, peak_alpha(washes)
  for _, w in ipairs(washes) do
    if not top_a or w.y0 < top_a[1] then top_a = { w.y0, w.a0 } end
  end

  check(tag .. ": the painter runs to completion", paint_err == nil, paint_err)
  check(tag .. ": the ember pool is still painted",
    #washes >= 1 and peak_a > 0.01, string.format("%d elements, peak %.4f", #washes, peak_a))
  check(tag .. ": the ember pool reaches the glow band's bottom edge",
    y1 >= BAND.y + BAND.h - 1, string.format("%.2f vs %.2f", y1, BAND.y + BAND.h))
  check(tag .. ": the ember pool fades to nothing at its top edge",
    top_a ~= nil and top_a[2] <= 0.15 * peak_a,
    string.format("%.4f of peak %.4f", top_a and top_a[2] or -1, peak_a))
  check(tag .. ": the ember pool lays no hard alpha step inside the card",
    peak > 0 and worst <= 0.25 * peak,
    string.format("step %.4f of peak %.4f at y=%.1f", worst, peak, wy or -1))
  check(tag .. ": the ember pool covers the band it is seated in and no more",
    math.abs(x0 - BAND.x) <= EPS and math.abs(x1 - (BAND.x + BAND.w)) <= EPS
    and math.abs(y0 - BAND.y) <= EPS and math.abs(y1 - (BAND.y + BAND.h)) <= EPS,
    string.format("x %.2f..%.2f y %.2f..%.2f vs band %.2f..%.2f / %.2f..%.2f",
      x0, x1, y0, y1, BAND.x, BAND.x + BAND.w, BAND.y, BAND.y + BAND.h))
  local rounded = 0
  for _, w in ipairs(washes) do
    if w.kind == "rect" and (w.rx or 0) > 0.001 then rounded = rounded + 1 end
  end
  check(tag .. ": the ember pool carries no corner radius", rounded == 0, rounded .. " rounded")
end

local mesh_peak
do
  local meshes, factory = mesh_recorder()
  local ops = paint(factory)
  local washes = ember_washes(ops, meshes)
  local nrect, nmesh = kinds(washes)
  check("mesh path: the pool is one graded mesh, never a flat fill",
    nmesh == 1 and nrect == 0, string.format("%d mesh, %d rect", nmesh, nrect))
  verdict("mesh path", washes)
  mesh_peak = peak_alpha(washes)
end

local flat_peak
do
  local ops = paint(broken_mesh)
  local washes = ember_washes(ops, {})
  local nrect, nmesh = kinds(washes)
  check("no-mesh path: the pool falls back to a stack of slices, not one flat band",
    nmesh == 0 and nrect >= 6, string.format("%d mesh, %d rect", nmesh, nrect))
  verdict("no-mesh path", washes)
  flat_peak = peak_alpha(washes)
end

do
  local ops = paint(partial_mesh)
  local washes = ember_washes(ops, {})
  local nrect, nmesh = kinds(washes)
  check("partial-mesh path: an incomplete Mesh handle is rejected, not drawn",
    nmesh == 0 and nrect >= 6, string.format("%d mesh, %d rect", nmesh, nrect))
  verdict("partial-mesh path", washes)
end

check("both paths lay the same ember strength",
  mesh_peak > 0 and math.abs(mesh_peak - flat_peak) < 1e-6,
  string.format("mesh %.4f vs slices %.4f", mesh_peak, flat_peak))

do
  local meshes, factory = mesh_recorder()
  local ops = paint(factory)
  local scrim, outline, arms, marks = 0, 0, 0, 0
  for _, line in ipairs(ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" then
      if op.r and op.r < 0.01 and op.g < 0.01 and op.b < 0.01 then scrim = scrim + 1
      else outline = outline + 1 end
    end
    if op and op.v == "L" then arms = arms + 1 end
    if op and op.v == "P" and op.mode == "fill" then marks = marks + 1 end
  end
  check("the three scrim bands survive", scrim == 3, scrim)
  check("the pulsing border survives", outline >= 1, outline)
  check("the four corner arms survive", arms == 4, arms)
  check("the mark and its hot core survive", marks == 2, marks)
end

done()
