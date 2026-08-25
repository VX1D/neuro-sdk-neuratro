

local Cap = require("tests.raster_capture")
local check, done = require("tests.helpers").harness("raster stable x")

local function no_errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return false, fr.err end
  end
  return true
end

local function moments(n, span, t0)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = (t0 or 0.05) + span * i / (n - 1) end
  return out
end

local function panel_edges(frame, min_h, min_w)
  local lo, hi
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.w and op.h and (op.a or 0) >= 0.15
      and op.h >= min_h and op.w >= (min_w or 80) then
      local x = math.floor(op.x + 0.5)
      if not lo or x < lo then lo = x end
      if not hi or x > hi then hi = x end
    end
  end
  return lo, hi
end

local function edge_step(frames, min_h, min_w)
  local seq, prev, worst, at = {}, nil, 0, nil
  for _, fr in ipairs(frames) do
    local lo, hi = panel_edges(fr, min_h, min_w)
    if lo then
      seq[#seq + 1] = lo .. "/" .. hi
      if prev then
        local d = math.max(math.abs(lo - prev[1]), math.abs(hi - prev[2]))
        if d > worst then worst, at = d, fr.t end
      end
      prev = { lo, hi }
    end
  end
  return worst, at, seq
end

local Rows = require("hud.rows")
local function count_latch_holds(fn)
  local real = Rows.latch_columns
  local held = 0
  Rows.latch_columns = function(latch, want, sig, max_cols)
    local l, c = real(latch, want, sig, max_cols)
    if c > want then held = held + 1 end
    return l, c
  end
  local ok, out = pcall(fn)
  Rows.latch_columns = real
  if not ok then error(out) end
  return held, out
end

local function all_text(frame)
  local out = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.text then out[#out + 1] = op.text end
  end
  return table.concat(out)
end

local FLIP = { w = 1280, h = 460 }
for _, persona in ipairs({ "neuro", "evil" }) do
  local held, frames = count_latch_holds(function()
    return Cap.capture({ scene = "lastcons", persona = persona,
      size = FLIP, moments = moments(12, 2.4, 0.4) })
  end)
  local ok, err = no_errors(frames)
  check("lastcons captures cleanly (" .. persona .. ")", ok, err)
  check("the column latch is actually exercised at this viewport (" .. persona .. ")",
    held > 0, held)

  local worst, at, seq = edge_step(frames, 100)
  check("losing the last consumable does not move the panel (" .. persona .. ")",
    worst == 0, string.format("%d px at t=%s [%s]", worst, tostring(at), table.concat(seq, " ")))
end

do
  local frames = Cap.capture({ scene = "lastcons", persona = "neuro",
    size = { w = 1280, h = 720 }, moments = moments(12, 2.8) })
  check("lastcons captures cleanly (roomy)", no_errors(frames))
  local worst, at, seq = edge_step(frames, 100)
  check("a single-column viewport holds its edges too", worst == 0,
    string.format("%d px at t=%s [%s]", worst, tostring(at), table.concat(seq, " ")))
end

do
  local frames = Cap.capture({ scene = "toasts", persona = "neuro", moments = moments(8, 0.24) })
  check("toasts captures cleanly", no_errors(frames))
  local worst, at, seq = edge_step(frames, 40, 80)
  check("the receipt fades in where it will stand, it does not drive in", worst == 0,
    string.format("%d px at t=%s [%s]", worst, tostring(at), table.concat(seq, " ")))
end

do
  local frames = Cap.capture({ scene = "packclaim", persona = "neuro", moments = moments(14, 4.4) })
  check("packclaim captures cleanly", no_errors(frames))

  local said_picked, cinematic_up = false, false
  for _, fr in ipairs(frames) do
    if all_text(fr):find("PICKED", 1, true) then said_picked = true end
    if panel_edges(fr, 40, 120) then cinematic_up = true end
  end
  check("a claim's receipt never reaches the screen", not said_picked)
  check("because the pack cinematic owns the beat, and it is on screen", cinematic_up)
end

do
  local frames = Cap.capture({ scene = "boosteropen", persona = "neuro", moments = moments(10, 3.0) })
  check("boosteropen captures cleanly", no_errors(frames))
  local said_opened = false
  for _, fr in ipairs(frames) do
    if all_text(fr):find("OPENED", 1, true) then said_opened = true end
  end
  check("a booster purchase's receipt never draws over the pack it opened", not said_opened)
end

do
  local frames = Cap.capture({ scene = "pickmorph", persona = "neuro", moments = moments(10, 4.0) })
  check("pickmorph captures cleanly", no_errors(frames))
  local said_picked = false
  for _, fr in ipairs(frames) do
    if all_text(fr):find("PICKED", 1, true) then said_picked = true end
  end
  check("off the pack stage the same receipt still speaks", said_picked)
end

local function receipt_frame(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.h and op.x
      and op.x > 300 and op.x < 950 and op.h >= 30 and op.h <= 130 and op.w >= 120 then
      if not best or op.w > best.w then best = op end
    end
  end
  return best
end

do
  local frames = Cap.capture({ scene = "shoptopack", persona = "neuro",
    size = { w = 1280, h = 720 }, moments = moments(12, 0.66, 0.30) })
  check("shoptopack captures cleanly", no_errors(frames))

  local xs, seen, drawn = {}, {}, 0
  for _, fr in ipairs(frames) do
    local b = receipt_frame(fr)
    if b then
      drawn = drawn + 1
      local k = tostring(b.x)
      if not seen[k] then seen[k] = true; xs[#xs + 1] = k end
    end
  end
  check("the receipt is on screen across the whole transition", drawn == #frames,
    drawn .. "/" .. #frames)
  check("a corridor recompute does not move a live receipt", #xs == 1, table.concat(xs, " | "))
end

done()
