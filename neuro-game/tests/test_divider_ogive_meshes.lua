rawset(_G, "NEURO_TEST", true)

local check, done = require("tests.helpers").harness("divider/ogive meshes")

local function load_prims(mesh_enabled)
  local state = { ops = {}, builds = 0, draws = 0, rects = 0, arcs = 0, circles = 0,
    colour = { 1, 1, 1, 1 } }
  local gfx = {}

  function gfx.setColor(r, g, b, a)
    state.colour = { r, g, b, a == nil and 1 or a }
  end

  function gfx.rectangle(mode, x, y, w, h)
    state.rects = state.rects + 1
    local c = state.colour
    state.ops[#state.ops + 1] = { x = x, y = y, w = w, h = h, c = { c[1], c[2], c[3], c[4] } }
  end

  function gfx.draw(mesh, x, y, rotation, sx, sy)
    state.draws = state.draws + 1
    sx, sy = sx or 1, sy or sx or 1
    local tint = state.colour
    for i = 1, #mesh.vertices, 4 do
      local v0, v2 = mesh.vertices[i], mesh.vertices[i + 2]
      state.ops[#state.ops + 1] = {
        x = x + v0[1] * sx, y = y + v0[2] * sy,
        w = (v2[1] - v0[1]) * sx, h = (v2[2] - v0[2]) * sy,
        c = { v0[5] * tint[1], v0[6] * tint[2], v0[7] * tint[3], v0[8] * tint[4] },
      }
    end
  end

  if mesh_enabled then
    function gfx.newMesh(vertices)
      state.builds = state.builds + 1
      local mesh = { vertices = vertices }
      function mesh:setVertexMap(indices) self.indices = indices end
      function mesh:getVertexCount() return #self.vertices end
      return mesh
    end
  end

  setmetatable(gfx, { __index = function() return function() end end })
  love = { graphics = gfx, timer = { getTime = function() return 0 end } }
  package.loaded["hud.prims"] = nil
  return require("hud.prims"), state
end

local function selected_ops(state, predicate)
  local out = {}
  for _, op in ipairs(state.ops) do
    if not predicate or predicate(op) then
      out[#out + 1] = string.format("%.6f,%.6f,%.6f,%.6f,%.9f,%.9f,%.9f,%.9f",
        op.x, op.y, op.w, op.h, op.c[1], op.c[2], op.c[3], op.c[4])
    end
  end
  table.sort(out)
  return table.concat(out, ";"), #out
end

do
  local x, y, w, u = 13, 41, 57, 2
  local acc, gold = { 0.75, 0.18, 0.42 }, { 0.9, 0.7, 0.2 }
  local a, pulse, weight = 0.8, 0.35, 3

  local fallback, fs = load_prims(false)
  fallback.evil_divider(x, y, w, u, acc, gold, a, pulse, weight, true, nil)
  local fallback_snap, fallback_n = selected_ops(fs)
  check("evil_divider fallback actually emitted bars to measure", fallback_n > 0, fallback_n)

  local gpu, gs = load_prims(true)
  gpu.evil_divider(x, y, w, u, acc, gold, a, pulse, weight, true, nil)
  local gpu_snap = selected_ops(gs)
  check("evil_divider mesh covers exactly what its fallback bars covered", gpu_snap == fallback_snap)
  check("evil_divider mesh replaces its bars with one draw",
    gs.draws == 1 and gs.rects == 0 and gs.builds == 1,
    string.format("%d draws, %d rects, %d builds", gs.draws, gs.rects, gs.builds))
end

do
  local x, y, w, u = 7, 19, 96, 3
  local gold = { 0.9, 0.7, 0.2 }
  local a, pulse = 0.8, 0.35

  local Prims, fs = load_prims(false)
  local A_STRUCT = Prims.EVIL.A_STRUCT

  local function is_black(op)
    return op.c[1] == 0 and op.c[2] == 0 and op.c[3] == 0
      and math.abs(op.c[4] - 0.35 * a) < 1e-9
  end
  local function is_ogive_gold(op)
    return math.abs(op.c[1] - gold[1]) < 1e-9 and math.abs(op.c[2] - gold[2]) < 1e-9
      and math.abs(op.c[3] - gold[3]) < 1e-9 and math.abs(op.c[4] - A_STRUCT * a) < 1e-9
  end

  Prims.ogive_top(x, y, w, u, gold, a, pulse)
  local fallback_black, black_n = selected_ops(fs, is_black)
  local fallback_gold, gold_n = selected_ops(fs, is_ogive_gold)
  check("ogive_top fallback actually emitted black shadow rects to measure", black_n > 0, black_n)
  check("ogive_top fallback actually emitted gold struct rects to measure", gold_n > 0, gold_n)

  local gpu, gs = load_prims(true)
  gpu.ogive_top(x, y, w, u, gold, a, pulse)
  check("ogive_top mesh covers exactly what its fallback black shadow rects covered",
    selected_ops(gs, is_black) == fallback_black)
  check("ogive_top mesh covers exactly what its fallback gold struct rects covered",
    selected_ops(gs, is_ogive_gold) == fallback_gold)
  check("ogive_top mesh replaces its step rects with mesh draws only",
    gs.draws == 2 and gs.rects == 0 and gs.builds == 2,
    string.format("%d draws, %d rects, %d builds", gs.draws, gs.rects, gs.builds))
end

done()
