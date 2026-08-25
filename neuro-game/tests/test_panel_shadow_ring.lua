
local ops, colours, group = {}, {}, 0
love = { graphics = {} }

function love.graphics.setColor(r, g, b, a)
  group = group + 1
  colours[group] = { r, g, b, a }
end

function love.graphics.rectangle(mode, x, y, w, h, rx, ry)
  ops[#ops + 1] = {
    kind = "rect", group = group, mode = mode,
    x = x, y = y, w = w, h = h, rx = rx, ry = ry,
  }
end

function love.graphics.arc(mode, arc_type, x, y, r, a1, a2)
  ops[#ops + 1] = {
    kind = "arc", group = group, mode = mode, arc_type = arc_type,
    x = x, y = y, r = r, a1 = a1, a2 = a2,
  }
end

function love.graphics.setLineWidth() end

local Prims = require("hud.prims")
local check, done = require("tests.helpers").harness("panel shadow ring")
local PI = math.pi
local EPS = 1e-6

local function near(a, b)
  return math.abs(a - b) <= EPS
end

local function capture(x, y, w, h, rad, sh, a)
  ops, colours, group = {}, {}, 0
  Prims.panel_shell(x, y, w, h, rad, sh, sh, 0.55 * a, { 0.2, 0.3, 0.4 }, 0.97 * a, a)
  return ops, colours, group
end

local function layer_box(x, y, w, h, rad, sh, i)
  local L = Prims.SHADOW_LAYERS[i]
  local sp, u = L[3], sh * 0.5
  return x - sp + L[1] * u, y - sp + L[2] * u,
    w + sp * 2, h + sp * 2, rad + sp
end

local function group_ops(all, wanted)
  local got = {}
  for _, op in ipairs(all) do
    if op.group == wanted then got[#got + 1] = op end
  end
  return got
end

local function rounded_area(w, h, r)
  return w * h - (4 - PI) * r * r
end

local function shadow_area(all)
  local area = 0
  for _, op in ipairs(all) do
    if op.group <= 3 then
      if op.kind == "rect" then
        area = area + op.w * op.h
      else
        area = area + 0.5 * op.r * op.r * math.abs(op.a2 - op.a1)
      end
    end
  end
  return area
end

local function legacy_area(x, y, w, h, rad, sh)
  local area = 0
  for i = 1, 3 do
    local _, _, sw, shh, sr = layer_box(x, y, w, h, rad, sh, i)
    area = area + rounded_area(sw, shh, sr)
  end
  return area
end

local function add_point(bounds, x, y)
  bounds[1] = math.min(bounds[1], x)
  bounds[2] = math.min(bounds[2], y)
  bounds[3] = math.max(bounds[3], x)
  bounds[4] = math.max(bounds[4], y)
end

local function painted_extents(all, wanted)
  local bounds = { math.huge, math.huge, -math.huge, -math.huge }
  for _, op in ipairs(all) do
    if op.group == wanted then
      if op.kind == "rect" then
        add_point(bounds, op.x, op.y)
        add_point(bounds, op.x + op.w, op.y + op.h)
      else
        add_point(bounds, op.x + math.cos(op.a1) * op.r, op.y + math.sin(op.a1) * op.r)
        add_point(bounds, op.x + math.cos(op.a2) * op.r, op.y + math.sin(op.a2) * op.r)
        for k = 0, 4 do
          local a = k * PI * 0.5
          if a >= op.a1 and a <= op.a2 then
            add_point(bounds, op.x + math.cos(a) * op.r, op.y + math.sin(a) * op.r)
          end
        end
      end
    end
  end
  return bounds
end

do
  local x, y, w, h, rad, sh, a = 20, 30, 380, 585, 9, 2, 0.979
  local all, sets, set_count = capture(x, y, w, h, rad, sh, a)
  check("a=0.979 emits three full shadows plus the plate", #all == 4 and set_count == 4)
  for i = 1, 3 do
    local sx, sy, sw, shh, sr = layer_box(x, y, w, h, rad, sh, i)
    local op, L = all[i], Prims.SHADOW_LAYERS[i]
    check("legacy shadow " .. i .. " keeps its rounded-rectangle geometry",
      op.kind == "rect" and op.mode == "fill" and near(op.x, sx) and near(op.y, sy)
        and near(op.w, sw) and near(op.h, shh) and near(op.rx, sr) and near(op.ry, sr))
    check("legacy shadow " .. i .. " keeps colour order and alpha arithmetic",
      op.group == i and near(sets[i][1], 0) and near(sets[i][2], 0) and near(sets[i][3], 0)
        and near(sets[i][4], L[4] * 0.55 * a))
  end
  local plate = all[4]
  check("legacy plate geometry and alpha stay unchanged",
    plate.kind == "rect" and plate.group == 4 and near(plate.x, x) and near(plate.y, y)
      and near(plate.w, w) and near(plate.h, h) and near(plate.rx, rad)
      and near(sets[4][4], 0.97 * a))
end

local function check_stable_case(label, x, y, w, h, rad, sh, expected_ring, expected_legacy)
  local all, _, set_count = capture(x, y, w, h, rad, sh, 0.98)
  check(label .. " switches to the ring at a=0.98", #all > 4 and set_count == 4)
  for i = 1, 3 do
    local sx, sy, sw, shh, sr = layer_box(x, y, w, h, rad, sh, i)
    local bounds = painted_extents(all, i)
    check(label .. " layer " .. i .. " keeps the old outer extents",
      near(bounds[1], sx) and near(bounds[2], sy)
        and near(bounds[3], sx + sw) and near(bounds[4], sy + shh))
    local arcs = 0
    for _, op in ipairs(group_ops(all, i)) do
      if op.kind == "arc" then
        arcs = arcs + 1
      else
        check(label .. " has no large interior shadow fill",
          not (op.w > w * 0.5 and op.h > h * 0.5))
      end
    end
    check(label .. " layer " .. i .. (sr <= 0 and " uses only disjoint strips" or " uses four rounded corner caps"),
      arcs == (sr <= 0 and 0 or 4))
  end
  local ring, legacy = shadow_area(all), legacy_area(x, y, w, h, rad, sh)
  check(label .. " ring fill area is the expected geometry", near(ring, expected_ring), ring)
  check(label .. " legacy fill area baseline is stable", near(legacy, expected_legacy), legacy)
  check(label .. " cuts shadow fill area by at least 90%", ring <= legacy * 0.10,
    string.format("%.3f ring / %.3f legacy", ring, legacy))
  print(string.format("MEASURED  %s shadow fill = %.3f px^2 ring / %.3f px^2 legacy (%.2f%% less)",
    label, ring, legacy, (1 - ring / legacy) * 100))
end

check_stable_case("380x585 square", 20, 30, 380, 585, 0, 2,
  11782.415927, 674651.415927)
check_stable_case("247x437 rounded", 8, 273, 247, 437, 6, 1,
  7569.004381, 329186.504381)

do
  ops, colours, group = {}, {}, 0
  local x, y, w, h = 10, 20, 80, 100
  local bg, bg_a = { 0.2, 0.3, 0.4 }, 0.73
  local bands = {
    { 0, 30, { 0.9, 0.1, 0.2 }, 0.20 },
    { 30, h, { 0.1, 0.8, 0.5 }, 0.40 },
  }
  local tiled = Prims.panel_shell(x, y, w, h, 0, 1, 1, 0, bg, bg_a, 0.5, bands)
  local body = {}
  for _, op in ipairs(ops) do
    if op.group > 3 and op.mode == "fill" and op.x == x and op.w == w then
      body[#body + 1] = op
    end
  end
  check("square panel accepts exact full-width bands", tiled == true)
  check("panel bands emit one fill per disjoint tile", #body == 2, #body)
  local area = 0
  for _, op in ipairs(body) do area = area + op.w * op.h end
  check("panel band fill area equals the body exactly", near(area, w * h), area)
  check("panel bands are contiguous and non-overlapping",
    body[1] and body[2] and near(body[1].y, y) and near(body[1].h, 30)
      and near(body[2].y, y + 30) and near(body[2].h, h - 30))

  for i, band in ipairs(bands) do
    local op = body[i]
    local got = op and colours[op.group]
    local oa = band[4]
    local out_a = oa + bg_a * (1 - oa)
    local bk, ok = bg_a * (1 - oa) / out_a, oa / out_a
    local col = band[3]
    check("panel band " .. i .. " keeps source-over alpha and straight colour",
      got and near(got[4], out_a)
        and near(got[1], bg[1] * bk + col[1] * ok)
        and near(got[2], bg[2] * bk + col[2] * ok)
        and near(got[3], bg[3] * bk + col[3] * ok))
  end

  ops, colours, group = {}, {}, 0
  local rounded = Prims.panel_shell(x, y, w, h, 5, 1, 1, 0, bg, bg_a, 0.5, bands)
  local rounded_body = ops[#ops]
  check("rounded panels reject rectangular band tiling", rounded == false)
  check("rounded panel fallback keeps one rounded body",
    rounded_body and rounded_body.mode == "fill" and rounded_body.rx == 5)
end

do
  ops, colours, group = {}, {}, 0
  local x, y, w, h = 4, 7, 102, 100
  local col, a, pulse = { 0.7, 0.5, 0.2 }, 0.8, 0.6
  Prims.counter_glow(x, y, w, h, col, a, pulse, 0)
  local h1, h2, h3 = math.floor(h * 0.16), math.floor(h * 0.22), math.floor(h * 0.28)
  local gk = (0.75 + 0.25 * pulse) * a
  local a1, a2, a3 = 0.038 * gk, 0.026 * gk, 0.014 * gk
  local expected_a = {
    a3,
    a3 + a2 * (1 - a3),
    a3 + (a2 + a1 * (1 - a2)) * (1 - a3),
  }
  local expected_h = { h3 - h2, h2 - h1, h1 }
  check("square counter glow emits three disjoint strips", #ops == 3, #ops)
  local area = 0
  for i, op in ipairs(ops) do
    area = area + op.w * op.h
    local got = colours[op.group]
    check("counter glow strip " .. i .. " has the exact partition height",
      near(op.h, expected_h[i]), op.h)
    check("counter glow strip " .. i .. " keeps old composited colour and alpha",
      got and near(got[1], col[1]) and near(got[2], col[2]) and near(got[3], col[3])
        and near(got[4], expected_a[i]))
  end
  check("counter glow fill area is exactly its union",
    near(area, (w - 2) * h3), area)
  check("counter glow removes nested overdraw area",
    area < (w - 2) * (h1 + h2 + h3))
end

done()
