local RectMesh = {}

local supported, supported_lg

local function graphics()
  local lg = love and love.graphics
  if lg ~= supported_lg then supported_lg, supported = lg, nil end
  return lg
end

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

function RectMesh.add_pie(v, i, cx, cy, radius, a1, a2)
  local segments = 16
  local n = #v
  v[n + 1] = { cx, cy, 0, 0, 1, 1, 1, 1 }
  for k = 0, segments do
    local t = a1 + (a2 - a1) * (k / segments)
    v[n + 2 + k] = { cx + math.cos(t) * radius, cy + math.sin(t) * radius, 0, 0, 1, 1, 1, 1 }
  end
  for k = 1, segments do
    local m = #i
    i[m + 1], i[m + 2], i[m + 3] = n + 1, n + 1 + k, n + 2 + k
  end
end

function RectMesh.build(v, i)
  local lg = graphics()
  if supported == false or #v == 0 then return nil end
  if not lg then
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
  graphics()
  return supported ~= false
end

function RectMesh.rect(list, x, y, w, h, r, g, b, a)
  local n = #list
  list[n + 1], list[n + 2], list[n + 3], list[n + 4] = x, y, w, h
  list[n + 5], list[n + 6], list[n + 7], list[n + 8] = r, g, b, a
end

function RectMesh.from_rects(list)
  local v, i = {}, {}
  for k = 1, #list, 8 do
    RectMesh.add(v, i, list[k], list[k + 1], list[k + 2], list[k + 3],
      list[k + 4], list[k + 5], list[k + 6], list[k + 7])
  end
  return RectMesh.build(v, i)
end

function RectMesh.paint(list, x, y, tr, tg, tb, ta)
  local lg = love.graphics
  for k = 1, #list, 8 do
    lg.setColor(list[k + 4] * tr, list[k + 5] * tg, list[k + 6] * tb, list[k + 7] * ta)
    lg.rectangle("fill", x + list[k], y + list[k + 1], list[k + 2], list[k + 3])
  end
end

local Lru = {}
Lru.__index = Lru

local function release_object(o)
  if o and o.release then pcall(o.release, o) end
end

function RectMesh.lru(limit, release)
  return setmetatable({ limit = limit, release = release or release_object, clock = 0 }, Lru)
end

function Lru:get(kind, p1, p2, p3, p4, p5, p6, p7, p8)
  for n = 1, #self do
    local e = self[n]
    if e.kind == kind and e.p1 == p1 and e.p2 == p2 and e.p3 == p3 and e.p4 == p4
      and e.p5 == p5 and e.p6 == p6 and e.p7 == p7 and e.p8 == p8
    then
      self.clock = self.clock + 1
      e.used = self.clock
      return e.value
    end
  end
  return nil
end

function Lru:put(kind, p1, p2, p3, p4, p5, p6, p7, p8, value)
  self.clock = self.clock + 1
  local slot = #self + 1
  if slot > self.limit then
    slot = 1
    for n = 2, #self do
      if self[n].used < self[slot].used then slot = n end
    end
    self.release(self[slot].value)
  end
  self[slot] = { kind = kind, p1 = p1, p2 = p2, p3 = p3, p4 = p4, p5 = p5, p6 = p6, p7 = p7,
    p8 = p8, value = value, used = self.clock }
end

function Lru:clear()
  for n = #self, 1, -1 do
    self.release(self[n].value)
    self[n] = nil
  end
end

function RectMesh.cached(cache, kind, p1, p2, p3, p4, p5, p6, p7, p8, rects, a1, a2, a3, a4, a5)
  if not RectMesh.available() then return nil end
  local m = cache:get(kind, p1, p2, p3, p4, p5, p6, p7, p8)
  if m == nil then
    m = RectMesh.from_rects(rects(a1, a2, a3, a4, a5))
    if m then cache:put(kind, p1, p2, p3, p4, p5, p6, p7, p8, m) end
  end
  return m
end

function RectMesh.fill(mesh, x, y, r, g, b, a, rects, a1, a2, a3, a4, a5)
  if mesh then
    love.graphics.setColor(r, g, b, a)
    love.graphics.draw(mesh, x, y)
  else
    RectMesh.paint(rects(a1, a2, a3, a4, a5), x, y, r, g, b, a)
  end
end

local shared = RectMesh.lru(24)
RectMesh.shared = shared

return RectMesh
