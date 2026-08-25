

local Cap = require("tests.raster_capture")
local check, done = require("tests.helpers").harness("raster pack claim")

local function ops_of(frames, persona, t)
  for _, fr in ipairs(frames) do
    if fr.persona == persona and math.abs(fr.t - t) < 1e-6 then return fr end
  end
end

local function no_errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return false, fr.err end
  end
  return true
end

local function text_on_line(frame, y_lo, y_hi, min_alpha)
  local rows = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.y and op.y >= y_lo and op.y <= y_hi
      and (op.a or 0) >= (min_alpha or 0.5) then
      local key = string.format("%.0f", op.y)
      rows[key] = rows[key] or {}
      table.insert(rows[key], op)
    end
  end
  local out = {}
  for _, row in pairs(rows) do
    table.sort(row, function(p, q) return p.x < q.x end)
    local s = {}
    for _, op in ipairs(row) do s[#s + 1] = op.text end
    out[#out + 1] = table.concat(s)
  end
  return out
end

local function label_clusters(frame, y_lo, y_hi, min_alpha, gap)
  local rows = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.y and op.y >= y_lo and op.y <= y_hi
      and (op.a or 0) >= (min_alpha or 0.15) then
      local key = string.format("%.0f", op.y)
      rows[key] = rows[key] or {}
      table.insert(rows[key], op)
    end
  end
  local best = 0
  for _, row in pairs(rows) do
    table.sort(row, function(p, q) return p.x < q.x end)
    local n, prev = 0, nil
    for _, op in ipairs(row) do
      if not prev or (op.x - prev) > (gap or 12) then n = n + 1 end
      prev = op.x
    end
    if n > best then best = n end
  end
  return best
end

local function has_line(frame, y_lo, y_hi, want)
  for _, s in ipairs(text_on_line(frame, y_lo, y_hi)) do
    if s:find(want, 1, true) then return true end
  end
  return false
end

local function pack_clip(frame)
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "S" and not op.off and op.n[2] and op.n[2] < 40
      and op.n[3] and op.n[3] > 80 and op.n[3] < 1100 then
      return op.n
    end
  end
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

local ENV_PAD, ENV_TAIL = 4, 28
local function card_ops_outside_envelope(frame)
  local panel = pack_panel_rect(frame)
  if not panel then return -1 end
  local x0, y0 = panel.x - ENV_PAD, panel.y - ENV_PAD
  local x1, y1 = panel.x + panel.w + ENV_PAD, panel.y + panel.h + ENV_TAIL
  local out = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and (op.a or 0) > 0.01 then
      if op.x < x0 - 0.5 or op.y < y0 - 0.5
        or op.x + op.w > x1 + 0.5 or op.y + op.h > y1 + 0.5 then out = out + 1 end
    end
  end
  return out
end

local function card_ops_outside_clip(frame)
  local clip = pack_clip(frame)
  if not clip then return -1 end
  local out = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and (op.a or 0) > 0.01 then
      if op.x < clip[1] - 0.5 or op.y < clip[2] - 0.5
        or op.x + op.w > clip[1] + clip[3] + 0.5
        or op.y + op.h > clip[2] + clip[4] + 0.5 then out = out + 1 end
    end
  end
  return out
end

local Pack = require("render.panels.pack")
local PACK_TL = Pack.TIMELINES
local NEURO_TL = require("render.panels.pack_neuro").TL
local CLAIMED_AT = 1.20
local LOSER_MAX = Pack.LOSER_D + 2 * Pack.LOSER_SPREAD

local function beat_times(tl)
  local shrink_at = CLAIMED_AT + tl.ANOINT + math.max(tl.GLIDE, LOSER_MAX)
  return {
    claim = CLAIMED_AT + 0.75 * tl.ANOINT,
    pre_shrink = shrink_at - 0.04,
    shrunk = shrink_at + tl.SHRINK + 0.02,
    exit_a = shrink_at + tl.SHRINK + tl.HOLD + 0.25 * tl.EXIT,
    exit_b = shrink_at + tl.SHRINK + tl.HOLD + 0.75 * tl.EXIT,
  }
end

local personas = {
  { key = "neuro",  tl = NEURO_TL },
  { key = "evil",   tl = PACK_TL.evil },
  { key = "hiyori", tl = PACK_TL.soft },
}

for _, p in ipairs(personas) do
  local bt = beat_times(p.tl)
  local frames = Cap.capture({ scene = "pick", persona = p.key,
    moments = { bt.claim, bt.pre_shrink, bt.shrunk, bt.exit_a, bt.exit_b } })
  check(p.key .. ": pack capture raises no draw error", no_errors(frames))

  local claim_fr = ops_of(frames, p.key, bt.claim)

  local named = label_clusters(claim_fr, 0, 720, 0.15, 12)
  check(p.key .. ": all four pack cards are still named on the claim frame", named >= 4, named)

  local pre = pack_clip(ops_of(frames, p.key, bt.pre_shrink))
  local post = pack_clip(ops_of(frames, p.key, bt.shrunk))
  check(p.key .. ": SHRINK narrows the envelope to the hero",
    pre and post and post[3] < pre[3] * 0.6,
    string.format("%s -> %s", pre and pre[3] or "nil", post and post[3] or "nil"))

  for _, t in ipairs({ bt.shrunk, bt.exit_a, bt.exit_b }) do
    local fr = ops_of(frames, p.key, t)
    check(string.format("%s: no card op escapes the envelope at t=%.2f", p.key, t),
      card_ops_outside_clip(fr) == 0, card_ops_outside_clip(fr))
    check(string.format("%s: no card op escapes the drawn panel rect at t=%.2f", p.key, t),
      card_ops_outside_envelope(fr) == 0, card_ops_outside_envelope(fr))
  end

  local ea = ops_of(frames, p.key, bt.exit_a)
  local eb = ops_of(frames, p.key, bt.exit_b)
  local function hero_img(fr)
    local best
    for _, line in ipairs(fr.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "I" and (not best or (op.w or 0) > best.w) then best = op end
    end
    return best
  end
  local ha, hb = hero_img(ea), hero_img(eb)
  check(p.key .. ": EXIT keeps the hero geometry (size unchanged, only lift and fade)",
    ha and hb and math.abs(ha.w - hb.w) < 1.5 and math.abs(ha.h - hb.h) < 1.5
    and math.abs(ha.x - hb.x) < 1.5 and hb.y <= ha.y + 0.5 and (hb.a or 0) <= (ha.a or 1),
    ha and hb and string.format("%.1fx%.1f@%.1f,%.1f a=%.2f -> %.1fx%.1f@%.1f,%.1f a=%.2f",
      ha.w, ha.h, ha.x, ha.y, ha.a or 1, hb.w, hb.h, hb.x, hb.y, hb.a or 1) or "missing hero")
end

local SWEEP_SPAN = NEURO_TL.ANOINT + math.max(NEURO_TL.GLIDE, LOSER_MAX)
  + NEURO_TL.SHRINK + NEURO_TL.HOLD + NEURO_TL.EXIT
local SWEEP = {}
for i = 0, math.ceil(SWEEP_SPAN * 60) do SWEEP[#SWEEP + 1] = CLAIMED_AT + i / 60 end
local sweep = Cap.capture({ scene = "pick", persona = "neuro", moments = SWEEP })
check("the claim sweep raises no draw error", no_errors(sweep))
local prev_a, revive, worst = {}, nil, 0
for _, fr in ipairs(sweep) do
  local cur = {}
  for _, line in ipairs(fr.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and op.x then
      local col = math.floor(op.x / 8) * 8
      cur[col] = math.max(cur[col] or 0, op.a or 0)
    end
  end
  for col, a in pairs(cur) do
    local p = prev_a[col]
    if p and p < 0.30 and a - p > worst then worst, revive = a - p, fr.t end
  end
  prev_a = cur
end
check("no pack card re-brightens after fading out during the claim", worst <= 0.05,
  string.format("+%.2f alpha at t=%.3f", worst, revive or -1))

do
  local SWEEP2 = {}
  local span2 = PACK_TL.soft.ANOINT + math.max(PACK_TL.soft.GLIDE, LOSER_MAX)
    + PACK_TL.soft.SHRINK + PACK_TL.soft.HOLD + PACK_TL.soft.EXIT
  for i = 0, math.floor(span2 * 60) do SWEEP2[#SWEEP2 + 1] = CLAIMED_AT + i / 60 end
  local fr2 = Cap.capture({ scene = "pick", persona = "hiyori", moments = SWEEP2 })

  local band_lo, band_hi
  for _, line in ipairs(fr2[1].ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and (op.a or 0) > 0.01 and op.x then
      if not band_lo or op.x > band_lo then band_lo = op.x; band_hi = op.x + (op.w or 60) end
    end
  end
  check("the far loser slot band was located", band_lo ~= nil, tostring(band_lo))

  local last_art, last_text = -1, -1
  if band_lo then
    local lo, hi = band_lo - 4, band_hi + 4
    for _, f in ipairs(fr2) do
      for _, line in ipairs(f.ops) do
        local op = Cap.parse_op(line)
        if op and (op.a or 0) >= 0.05 and op.x and op.x >= lo and op.x <= hi then
          if op.v == "I" then last_art = math.max(last_art, f.t)
          elseif op.v == "T" and op.text and #op.text > 0 then last_text = math.max(last_text, f.t) end
        end
      end
    end
  end
  check("that slot really had both channels on screen",
    last_art > CLAIMED_AT and last_text > CLAIMED_AT,
    string.format("art=%.3f text=%.3f", last_art, last_text))
  check("a loser's caption never leaves before the card art it labels",
    last_text >= last_art - 1 / 30,
    string.format("text out at %.3f, art out at %.3f", last_text, last_art))
end

done()
