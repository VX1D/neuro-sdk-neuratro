

local Cap = require("tests.raster_capture")
Cap.rec.enabled = false

local check, done = require("tests.helpers").harness("raster anchors")

local Dev = require("hud.dev_scenario")
local HUD = require("render.hud_overlay")
local S = require("hud.state")
local Config = require("core.config")

Cap.SIZE.w, Cap.SIZE.h = 1280, 720

local ANCHORS = Config.definition("NEURO_OVERLAY_ANCHOR").values
local DT = 1 / 60
local SETTLE_BUDGET = 0.90
local MAX_FREEZE_FRAMES = 6

check("the schema still ships seven placements (" .. #ANCHORS .. ")", #ANCHORS == 7)

local function frames_of(anchor, n, per_frame)
  Config.set("NEURO_OVERLAY_ANCHOR", anchor)
  Dev.set(false)
  G.TIMERS.REAL = Cap.BASE_T
  Dev.set(true)
  Dev.select(1)
  local ys, err = {}, nil
  for i = 1, n do
    if per_frame then per_frame(i) end
    G.TIMERS.REAL = Cap.BASE_T + i * DT
    Dev.mount()
    local ok, e = pcall(HUD.draw_indicator)
    ys[i] = S.panel_y_current
    Dev.unmount()
    if not ok and not err then err = tostring(e) end
  end
  Dev.set(false)
  return ys, err
end

local function longest_freeze(ys)
  local final = ys[#ys]
  local run, worst = 0, 0
  for i = 2, #ys do
    if math.abs(ys[i] - final) > 1 and ys[i] == ys[i - 1] then
      run = run + 1
      if run > worst then worst = run end
    else
      run = 0
    end
  end
  return worst
end

local function settle_time(ys)
  local final = ys[#ys]
  local last = 0
  for i = 1, #ys do
    if math.abs(ys[i] - final) >= 0.5 then last = i end
  end
  return last * DT
end

for _, anchor in ipairs(ANCHORS) do
  Config.set("NEURO_OVERLAY_OFFSET_Y", 0)
  local ys, err = frames_of(anchor, 90)
  check("anchor " .. anchor .. " renders without error", err == nil, err)
  local st, fz = settle_time(ys), longest_freeze(ys)
  check(string.format("anchor %s places the panel within %.2f s (%.3f s, y=%.1f)",
    anchor, SETTLE_BUDGET, st, ys[#ys]), st <= SETTLE_BUDGET)
  check(string.format("anchor %s never freezes the panel away from its place (%d frames)",
    anchor, fz), fz <= MAX_FREEZE_FRAMES)
  check("anchor " .. anchor .. " actually moves the panel off its initial 6 px",
    math.abs(ys[#ys] - 6) > 1 or anchor:sub(1, 3) == "top", ys[#ys])
end

for _, anchor in ipairs(ANCHORS) do
  Config.set("NEURO_OVERLAY_OFFSET_Y", -15)
  local settled = frames_of(anchor, 90)
  local base = settled[#settled]
  local ys = select(1, frames_of(anchor, 90, function(i)
    if i <= 30 then Config.set("NEURO_OVERLAY_OFFSET_Y", -15 + i) end
  end))
  local during = ys[30]
  local moved = math.abs(during - ys[1])
  check(string.format("anchor %s follows a slider dragged every frame (%.2f px, base %.1f)",
    anchor, moved, base), moved > 1)
  check(string.format("anchor %s does not stall mid-drag (%d frames)",
    anchor, longest_freeze(ys)), longest_freeze(ys) <= MAX_FREEZE_FRAMES)
  check(string.format("anchor %s arrives after the drag is released (%.3f s)",
    anchor, settle_time(ys)), settle_time(ys) <= 90 * DT - 0.05)
end

Config.set("NEURO_OVERLAY_OFFSET_Y", 0)
Config.set("NEURO_OVERLAY_ANCHOR", "auto")

done()
