local RectMesh = {}

local supported

function RectMesh.add(v, i, x, y, w, h, r, g, b, a)
  local n = #v
  v[n + 1] = { x,     y,     0, 0, r, g, b, a }
  v[n + 2] = { x + w, y,     0, 0, r, g, b, a }
  v[n + 3] = { x + w, y + h, 0, 0, r, g, b, a }
  v[n + 4] = { x,     y + h, 0, 0, r, g, b, a }
  local m = #i
  i[m + 1], i[m + 2], i[m + 3] = n + 1, n + 2, n + 3
  i[m + 4], i[m + 5], i[m + 6] = n + 1, n + 3, n + 4
end

function RectMesh.build(v, i)
  if supported == false or #v == 0 then return nil end
  local lg = love and love.graphics
  if not lg or type(lg.newMesh) ~= "function" then
    supported = false
    return nil
  end
  local ok, mesh = pcall(function()
    local m = lg.newMesh(v, "triangles", "static")
    if not m or type(m.setVertexMap) ~= "function" or type(m.getVertexCount) ~= "function" then
      return nil
    end
    m:setVertexMap(i)
    if m:getVertexCount() ~= #v then return nil end
    return m
  end)
  if not ok or not mesh then
    supported = false
    return nil
  end
  supported = true
  return mesh
end

function RectMesh.available()
  return supported ~= false
end

local LIMIT = 24
local cache = {}
local clock = 0

function RectMesh.get(kind, p1, p2, p3, p4, p5, p6)
  if supported == false then return nil end
  for n = 1, #cache do
    local e = cache[n]
    if e.kind == kind and e.p1 == p1 and e.p2 == p2 and e.p3 == p3
      and e.p4 == p4 and e.p5 == p5 and e.p6 == p6
    then
      clock = clock + 1
      e.used = clock
      return e.mesh
    end
  end
  return nil
end

function RectMesh.put(kind, p1, p2, p3, p4, p5, p6, mesh)
  clock = clock + 1
  local slot = #cache + 1
  if slot > LIMIT then
    slot = 1
    for n = 2, #cache do
      if cache[n].used < cache[slot].used then slot = n end
    end
  end
  cache[slot] = { kind = kind, p1 = p1, p2 = p2, p3 = p3, p4 = p4, p5 = p5, p6 = p6,
    mesh = mesh, used = clock }
end

return RectMesh
