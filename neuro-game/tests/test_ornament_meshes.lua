rawset(_G, "NEURO_TEST", true)

local check, done = require("tests.helpers").harness("ornament meshes")

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

  function gfx.arc(mode, arc_type, x, y, r, a1, a2)
    state.arcs = state.arcs + 1
    local c = state.colour
    state.ops[#state.ops + 1] = {
      kind = "arc", mode = mode, arc_type = arc_type, x = x, y = y, r = r, a1 = a1, a2 = a2,
      c = { c[1], c[2], c[3], c[4] },
    }
  end

  function gfx.circle(mode, x, y, r)
    state.circles = state.circles + 1
    local c = state.colour
    state.ops[#state.ops + 1] = {
      kind = "circle", mode = mode, x = x, y = y, r = r,
      c = { c[1], c[2], c[3], c[4] },
    }
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

local function reset(state)
  state.ops, state.draws, state.rects, state.arcs, state.circles = {}, 0, 0, 0, 0
end

local function selected_geometry(state, predicate)
  local out = {}
  for _, op in ipairs(state.ops) do
    if not predicate or predicate(op) then
      out[#out + 1] = string.format("%.6f,%.6f,%.6f,%.6f", op.x, op.y, op.w, op.h)
    end
  end
  table.sort(out)
  return table.concat(out, ";")
end

local function op_snapshot(state, want_rects)
  local out = {}
  for _, op in ipairs(state.ops) do
    local is_rect = op.w ~= nil and op.h ~= nil
    if is_rect == want_rects then
      local shape
      if is_rect then
        shape = string.format("R,%.6f,%.6f,%.6f,%.6f", op.x, op.y, op.w, op.h)
      elseif op.kind == "arc" then
        shape = string.format("A,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f",
          op.mode, op.arc_type, op.x, op.y, op.r, op.a1, op.a2)
      elseif op.kind == "circle" then
        shape = string.format("C,%s,%.6f,%.6f,%.6f", op.mode, op.x, op.y, op.r)
      end
      if shape then
        out[#out + 1] = shape .. string.format(",%.9f,%.9f,%.9f,%.9f",
          op.c[1], op.c[2], op.c[3], op.c[4])
      end
    end
  end
  table.sort(out)
  return out
end

local function same_snapshot(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function black_shadow(op)
  return op.c[1] == 0 and op.c[2] == 0 and op.c[3] == 0 and math.abs(op.c[4] - 0.55) < 1e-9
end

do
  local fallback, rf = load_prims(false)
  fallback.draw_dark_bow_mini(50, 60, 2, { 0.7, 0.1, 0.2 }, 1, { 0.9, 0.8, 0.3 }, 3)
  local fallback_all = op_snapshot(rf, true)
  local fallback_shadow = selected_geometry(rf, black_shadow)

  local gpu, rg = load_prims(true)
  gpu.draw_dark_bow_mini(50, 60, 2, { 0.7, 0.1, 0.2 }, 1, { 0.9, 0.8, 0.3 }, 3)
  local mesh_shadow = selected_geometry(rg, black_shadow)
  check("shadow mesh matches the exact silhouette rect coverage", mesh_shadow == fallback_shadow)
  check("merged mesh matches the whole fallback pass, colours included",
    same_snapshot(op_snapshot(rg, true), fallback_all))
  check("shadow and pixel passes share one draw", rg.draws == 1 and rg.rects == 0,
    string.format("%d draws, %d rects", rg.draws, rg.rects))
  check("the merged mesh builds once for a new pattern/key", rg.builds == 1, rg.builds)

  reset(rg)
  gpu.draw_dark_bow_mini(81, 94, 4, { 0.7, 0.1, 0.2 }, 0.95, { 0.9, 0.8, 0.3 }, 6)
  check("shadow cache key excludes position, scale, and tint", rg.builds == 1 and rg.draws == 1,
    string.format("%d builds, %d draws", rg.builds, rg.draws))

  reset(rg)
  local before = rg.builds
  for i = 1, 8 do
    gpu.wax_seal(120, 130, 9 + i * 0.37, 1, { 0.9, 0.7, 0.2 }, 1, 0.5, false, 0)
  end
  check("a fractional cell size never keys a merged mesh on the animated size",
    rg.builds - before == 2 and rg.draws == 16,
    string.format("%d builds, %d draws over 8 sizes", rg.builds - before, rg.draws))
end

do
  local Prims, state = load_prims(true)
  Prims.tag_string(11, 17, 37, 2, 0.2, 0.4, 0.6, 0.7)
  local tag_rects, tag_rect_count = selected_geometry(state), state.rects
  reset(state)
  Prims.tag_string(11, 17, 37, 2, 0.2, 0.4, 0.6, 0.7, true)
  check("tag_string mesh matches rect coverage", selected_geometry(state) == tag_rects)
  check("tag_string reduces its draw budget to one mesh draw",
    state.draws == 1 and state.rects == 0 and tag_rect_count > 1,
    string.format("fallback %d rects; mesh %d draws", tag_rect_count, state.draws))
  local built = state.builds
  reset(state)
  Prims.tag_string(90, 31, 37, 2, 0.2, 0.4, 0.6, 0.2, true)
  check("tag_string reuses a stable key across position and alpha", state.builds == built and state.draws == 1)

  local bg, gold = { 0.08, 0.04, 0.11 }, { 0.9, 0.7, 0.2 }
  reset(state)
  Prims.cornice_crenel(13, 41, 120, 1, bg, gold, 0.8)
  local cornice_rects, cornice_rect_count = selected_geometry(state), state.rects
  reset(state)
  Prims.cornice_crenel(13, 41, 120, 1, bg, gold, 0.8, true)
  check("cornice_crenel mesh matches rect coverage", selected_geometry(state) == cornice_rects)
  check("cornice_crenel reduces its draw budget to one mesh draw",
    state.draws == 1 and state.rects == 0 and cornice_rect_count > 20,
    string.format("fallback %d rects; mesh %d draws", cornice_rect_count, state.draws))
end

do
  local Prims, state = load_prims(true)
  for w = 20, 119 do Prims.tag_string(0, 0, w, 1, 0.2, 0.4, 0.6, 1) end
  check("transient animated widths do not build meshes", state.builds == 0, state.builds)

  reset(state)
  for w = 101, 133 do Prims.tag_string(0, 0, w, 1, 0.2, 0.4, 0.6, 1, true) end
  check("stable keys build one mesh apiece", state.builds == 33, state.builds)
  Prims.tag_string(0, 0, 101, 1, 0.2, 0.4, 0.6, 1, true)
  check("decoration mesh cache is bounded to 32 LRU entries", state.builds == 34, state.builds)
end

do
  local A, B = { 0.75, 0.18, 0.42 }, { 0.16, 0.62, 0.78 }
  local Prims, state = load_prims(true)
  Prims.awning(13, 19, 192, 2, A, B, 0.73, false)
  local fallback_rects = op_snapshot(state, true)
  local fallback_curves = op_snapshot(state, false)
  local fallback_calls = state.rects + state.arcs + state.circles
  check("an unstable awning builds no mesh", state.builds == 0 and state.draws == 0)

  reset(state)
  Prims.awning(13, 19, 192, 2, A, B, 0.73, true)
  local approx_calls = state.draws + state.rects + state.arcs + state.circles
  local awning_identical = same_snapshot(op_snapshot(state, true), fallback_rects)
    and same_snapshot(op_snapshot(state, false), fallback_curves)
  check("the awning mesh covers exactly what its rectangles covered", awning_identical)
  check("awning mesh replaces its rectangles with two draws",
    state.draws == 2 and state.rects == 0 and approx_calls < fallback_calls,
    string.format("fallback=%d approx=%d", fallback_calls, approx_calls))
  local awning_builds = state.builds
  reset(state)
  Prims.awning(71, 37, 192, 2, A, B, 0.21, true)
  check("awning cache key excludes position and alpha",
    state.builds == awning_builds and state.draws == 2)

  local V, vs = load_prims(true)
  V.valance(7, 11, 180, 2, A, B, 0.9, false)
  local valance_rects = op_snapshot(vs, true)
  local valance_curves = op_snapshot(vs, false)
  local valance_fallback_calls = vs.rects + vs.arcs + vs.circles
  reset(vs)
  V.valance(7, 11, 180, 2, A, B, 0.9, true)
  local valance_approx_calls = vs.draws + vs.rects + vs.arcs + vs.circles
  local valance_identical = same_snapshot(op_snapshot(vs, true), valance_rects)
    and same_snapshot(op_snapshot(vs, false), valance_curves)
  check("the valance mesh covers exactly what its rectangles covered", valance_identical)
  check("valance mesh replaces its rectangles with one draw",
    vs.draws == 1 and vs.rects == 0 and valance_approx_calls < valance_fallback_calls,
    string.format("fallback=%d approx=%d", valance_fallback_calls, valance_approx_calls))
  local valance_builds = vs.builds
  reset(vs)
  V.valance(101, 29, 180, 2, A, B, 0.3, true)
  check("valance cache key excludes position and alpha",
    vs.builds == valance_builds and vs.draws == 1)
end

do
  local A, B = { 0.7, 0.2, 0.4 }, { 0.2, 0.6, 0.8 }
  local Prims, state = load_prims(true)
  for w = 100, 199 do Prims.awning(0, 0, w, 1, A, B, 1) end
  check("transient awning widths never build meshes", state.builds == 0, state.builds)
  for w = 101, 133 do Prims.awning(0, 0, w, 1, A, B, 1, true) end
  check("stable awning keys build two meshes apiece", state.builds == 66, state.builds)
  Prims.awning(0, 0, 101, 1, A, B, 1, true)
  check("curved decoration cache remains bounded to 32 LRU keys", state.builds == 68, state.builds)
end

done()
