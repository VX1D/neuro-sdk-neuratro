_G.NEURO_TEST = true

local ARCS, CIRCLES = {}, {}
local function noop() end
love = {
  graphics = setmetatable({
    arc = function(mode, kind, cx, cy, r) ARCS[#ARCS + 1] = { cx = cx, cy = cy, r = r, mode = mode } end,
    circle = function(mode, cx, cy, r) CIRCLES[#CIRCLES + 1] = { cx = cx, cy = cy, r = r } end,
    rectangle = noop, setColor = noop, setLineWidth = noop, print = noop,
    getColor = function() return 1, 1, 1, 1 end,
    getLineWidth = function() return 1 end,
    getFont = function() return { getWidth = function() return 7 end, getHeight = function() return 14 end } end,
    setFont = noop,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end },
}
_G.G = { STATES = {}, GAME = {}, TIMERS = { REAL = 0 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }

local check, done = require("tests.helpers").harness("scallop tangency")
local Prims = require("hud.prims")

local A = { 0.9, 0.4, 0.5 }
local B = { 0.3, 0.2, 0.4 }

local function worst_overlap(list)
  local rows = {}
  for _, s in ipairs(list) do
    local key = string.format("%.3f/%.3f", s.cy, s.r)
    local row = rows[key]
    if not row then row = { seen = {} }; rows[key] = row end
    local at = string.format("%.6f", s.cx)
    if not row.seen[at] then row.seen[at] = true; table.insert(row, s) end
  end
  local worst, where = 0, nil
  for key, row in pairs(rows) do
    if #row >= 2 then
      table.sort(row, function(p, q) return p.cx < q.cx end)
      for i = 1, #row - 1 do
        local gap = row[i + 1].cx - row[i].cx
        local need = row[i].r + row[i + 1].r
        local over = need - gap
        if over > worst then worst, where = over, key end
      end
    end
  end
  return worst, where
end

local WIDTHS = { 208, 235, 247, 320, 356, 362, 380, 432, 489, 513, 640, 724, 760 }
local UNITS = { 1, 2 }

for _, fn_name in ipairs({ "awning", "valance" }) do
  local fn = Prims[fn_name]
  check(fn_name .. " exists", type(fn) == "function")
  local checked = 0
  local worst_all, worst_ctx = 0, nil
  for _, w in ipairs(WIDTHS) do
    for _, u in ipairs(UNITS) do
      ARCS, CIRCLES = {}, {}
      fn(0, 0, w, u, A, B, 1, false)
      if #ARCS >= 2 then
        checked = checked + 1
        local over, key = worst_overlap(ARCS)
        if over > worst_all then worst_all, worst_ctx = over, w .. "/" .. u .. " row " .. tostring(key) end
      end
    end
  end
  check(fn_name .. " actually emitted scallops to measure", checked >= 8, checked .. " shapes")
  check(fn_name .. " keeps adjacent scallops tangent, never overlapping -- the batching premise",
    worst_all <= 1e-9,
    string.format("worst overlap %.6f px at %s", worst_all, tostring(worst_ctx)))
end

done()
