

local Cap = require("tests.raster_capture")
local check, done = require("tests.helpers").harness("raster pack final pick")

local Pack = require("render.panels.pack")
local NEURO_TL = require("render.panels.pack_neuro").TL
local CLAIMED_AT = 1.2
local TORN_DOWN_AT = 3.0
local LOSER_MAX = Pack.LOSER_D + 2 * Pack.LOSER_SPREAD

local function no_errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return false, fr.err end
  end
  return true
end

local function pack_panel_rect(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.w > 100 and op.h and op.h > 25
      and op.x and op.x > 100 and op.x < 1800 and op.y and op.y < 400
      and (op.a or 0) >= 0.005 then
      if not best or op.a > best.a then best = op end
    end
  end
  return best
end

local CORRIDOR_MAX_X = 1000

local function total_card_area(frame)
  local area = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and (op.x or 0) + (op.w or 0) <= CORRIDOR_MAX_X then
      area = area + (op.w or 0) * (op.h or 0) * (op.a or 0)
    end
  end
  return area
end

local SWEEP_SPAN = NEURO_TL.ANOINT + math.max(NEURO_TL.GLIDE, LOSER_MAX)
  + NEURO_TL.SHRINK + NEURO_TL.HOLD + NEURO_TL.EXIT
local COLLAPSE_END = CLAIMED_AT + SWEEP_SPAN
local TARGET_T = COLLAPSE_END + 1 / 30

local moments = { TARGET_T }
local t = CLAIMED_AT
while t <= TORN_DOWN_AT + 0.2 + 1e-9 do
  moments[#moments + 1] = t
  t = t + 1 / 60
end

local frames = Cap.capture({ scene = "packfinal", persona = "neuro", moments = moments })
check("packfinal capture raises no draw error", no_errors(frames))

local function frame_at(want_t)
  for _, fr in ipairs(frames) do
    if math.abs(fr.t - want_t) < 1e-6 then return fr end
  end
end

local worst_rise, rise_t, prev = 0, nil, nil
for _, fr in ipairs(frames) do
  if fr.t >= COLLAPSE_END and fr.t <= TORN_DOWN_AT then
    local area = total_card_area(fr)
    if prev and area - prev > worst_rise then worst_rise, rise_t = area - prev, fr.t end
    prev = area
  end
end
check("the pack panel never brightens again after its own collapse",
  worst_rise <= 0.5, string.format("+%.1f at t=%s", worst_rise, tostring(rise_t)))

local target_fr = frame_at(TARGET_T)
check("the loser art is gone once the cinematic's own timeline ends",
  target_fr and total_card_area(target_fr) <= 0.5,
  target_fr and total_card_area(target_fr))

local peak, worst_drop, worst_t, prev_area = 0, 0, nil, nil
for _, fr in ipairs(frames) do
  if fr.t >= CLAIMED_AT and fr.t <= COLLAPSE_END + 1e-9 then
    local area = total_card_area(fr)
    if area > peak then peak = area end
    if prev_area and prev_area - area > worst_drop then worst_drop, worst_t = prev_area - area, fr.t end
    prev_area = area
  end
end
check("the losers dissolve, they do not teleport",
  peak <= 0 or worst_drop <= 0.35 * peak,
  string.format("drop %.1f of peak %.1f at t=%s", worst_drop, peak, tostring(worst_t)))

done()
