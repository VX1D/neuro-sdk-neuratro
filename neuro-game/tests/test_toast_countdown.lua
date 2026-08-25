

local Drive = require("tests.raster_drive")
local Cap = Drive.Cap
local check, done = require("tests.helpers").harness("acquire toast countdown")

local S = require("hud.state")
local Showcase = require("hud.showcase")

local SIZE = { w = 1280, h = 720 }
local RIGHT_EDGE = 1000   -- the right panel starts past this; the acquire stage is the centre column

local function card_of(name, key)
  return {
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name } } },
    ability = { name = name, set = "Joker" }, cost = 5,
  }
end

local function bar_of(frame)
  local boxes, dashes = {}, {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.x and op.y then
      if op.mode == "line" and op.w and op.w >= 100 and op.h and op.h >= 20
        and op.y < 40 and op.x + op.w <= RIGHT_EDGE and (op.a or 0) > 0.02 then
        boxes[#boxes + 1] = op
      elseif op.mode == "fill" and op.h == 1 and op.w and op.w <= 2 and (op.a or 0) > 0.02 then
        dashes[#dashes + 1] = op
      end
    end
  end
  local best
  for _, b in ipairs(boxes) do
    local ty = b.y + b.h - 2
    local lo, hi, n = nil, nil, 0
    for _, d in ipairs(dashes) do
      if d.y == ty and d.x >= b.x and d.x + d.w <= b.x + b.w then
        n = n + 1
        if not lo or d.x < lo then lo = d.x end
        if not hi or d.x + d.w > hi then hi = d.x + d.w end
      end
    end
    if n > 0 and (not best or n > best.n) then
      local span = b.w - 2 * (lo - b.x)
      best = { n = n, frac = (hi - lo) / span, box = b }
    end
  end
  return best
end

local function trace(opts)
  local items, morphed = {}, {}
  local frames = Drive.play({
    scene = opts.scene, persona = "neuro", size = SIZE, span = opts.span, from = 0,
    on_frame = function(t)
      if opts.on_frame then opts.on_frame(t) end
      local sc = S.buy_showcase
      items[#items + 1] = sc and tostring(sc.name) or "-"
      morphed[#morphed + 1] = (sc and sc._morph_at ~= nil) or false
    end,
  })
  local out = { err = Drive.errors(frames) }
  for i, fr in ipairs(frames) do
    local b = bar_of(fr)
    if b then
      out[#out + 1] = { t = fr.t, frac = b.frac, item = items[i] or "?", morphed = morphed[i] }
    end
  end
  return out
end

local function episodes(rows)
  local out, cur = {}, nil
  for _, r in ipairs(rows) do
    if not cur or cur.item ~= r.item then
      cur = { item = r.item, rows = {} }
      out[#out + 1] = cur
    end
    cur.rows[#cur.rows + 1] = r
  end
  return out
end

local FINISH = 0.08     -- the rule's 2px floor alone is 0.015 of its travel
local START = 0.92
local MAX_DROP = 0.12
local BACKWARDS = 0.02  -- a box that resizes mid-episode quantises the rule by about a pixel

local function assert_countdown(tag, rows, want_episodes)
  check(tag .. ": captures cleanly", rows.err == nil, rows.err)
  local eps = episodes(rows)
  check(tag .. ": the countdown is drawn for " .. want_episodes .. " receipt(s)",
    #eps == want_episodes, #eps)
  for i, ep in ipairs(eps) do
    local label = tag .. " [" .. tostring(ep.item) .. "]"
    local first, last = ep.rows[1], ep.rows[#ep.rows]
    check(label .. ": starts full", first.frac >= START, string.format("%.3f", first.frac))
    check(label .. ": reaches zero before the receipt leaves", last.frac <= FINISH,
      string.format("%.3f at t=%.3f", last.frac, last.t))
    local worst_back, worst_drop = 0, 0
    local at_back, at_drop = nil, nil
    for k = 2, #ep.rows do
      local d = ep.rows[k].frac - ep.rows[k - 1].frac
      if d > worst_back then worst_back, at_back = d, ep.rows[k].t end
      if -d > worst_drop then worst_drop, at_drop = -d, ep.rows[k].t end
    end
    check(label .. ": never runs backwards", worst_back <= BACKWARDS,
      string.format("+%.3f at t=%s", worst_back, tostring(at_back)))
    check(label .. ": never jumps", worst_drop <= MAX_DROP,
      string.format("-%.3f at t=%s", worst_drop, tostring(at_drop)))
    if i > 1 then
      check(label .. ": a fresh receipt restarts its own countdown", first.frac >= START,
        string.format("%.3f", first.frac))
    end
  end
end

local PROBE = card_of("Probe", "j_probe")
local OTHER = card_of("Other", "j_other")

local function clear_jokers()
  if G and G.jokers then G.jokers.cards = {} end
end

assert_countdown("plain", trace({
  scene = "slots", span = 2.2,
  on_frame = function(t)
    if math.abs(t - 2 / 60) < 1e-6 then
      Showcase.enqueue_purchase({ card = PROBE, name = "Probe", cost = 5, area = "shop_jokers" })
    end
  end,
}), 1)
clear_jokers()

local morph_rows = trace({ scene = "shop", span = 1.6 })
assert_countdown("morph", morph_rows, 1)
do
  local commit
  for _, r in ipairs(morph_rows) do
    if r.morphed then break end
    commit = r
  end
  check("morph: the countdown aims at the fold before the fold commits",
    commit ~= nil and commit.frac <= 0.45,
    commit and string.format("%.3f at t=%.3f", commit.frac, commit.t))
end

assert_countdown("crosscut", trace({ scene = "crosscut", span = 3.0 }), 2)

assert_countdown("held", trace({
  scene = "slots", span = 4.6,
  on_frame = function(t)
    if math.abs(t - 2 / 60) < 1e-6 then
      Showcase.enqueue_purchase({ card = PROBE, name = "Probe", cost = 5, area = "shop" })
    end
    if math.abs(t - 36 / 60) < 1e-6 then
      G.jokers.cards[#G.jokers.cards + 1] = OTHER
    end
  end,
}), 1)
clear_jokers()

assert_countdown("forced-exit", trace({
  scene = "slots", span = 2.0,
  on_frame = function(t)
    if math.abs(t - 2 / 60) < 1e-6 then
      Showcase.enqueue_purchase({ card = PROBE, name = "Probe", cost = 0, area = "booster_pick" })
    end
    if t >= 40 / 60 - 1e-6 then S.pack_claim_at = G.TIMERS.REAL end
  end,
}), 1)
clear_jokers()

do
  local rows = trace({
    scene = "slots", span = 4.6,
    on_frame = function(t)
      if math.abs(t - 2 / 60) < 1e-6 then
        Showcase.enqueue_purchase({ card = PROBE, name = "Probe", cost = 5, area = "shop" })
      end
      if math.abs(t - 36 / 60) < 1e-6 then
        G.jokers.cards[#G.jokers.cards + 1] = OTHER
      end
    end,
  })
  check("held-dwell: captures cleanly", rows.err == nil, rows.err)
  local drawn = #rows / 60
  check("held-dwell: the hold is not added to the receipt's time on screen",
    drawn <= Showcase.BUY_SHOWCASE_DURATION + 6 / 60,
    string.format("%.3f drawn of %.3f", drawn, Showcase.BUY_SHOWCASE_DURATION))
  check("held-dwell: and the receipt is not cut short either",
    drawn >= Showcase.BUY_SHOWCASE_DURATION - 12 / 60, string.format("%.3f", drawn))
end
clear_jokers()

do
  local rows = trace({
    scene = "slots", span = 2.6,
    on_frame = function(t)
      if math.abs(t - 2 / 60) < 1e-6 then
        Showcase.enqueue_purchase({ card = PROBE, name = "Probe", cost = 5, area = "shop_jokers" })
      end
      if math.abs(t - 66 / 60) < 1e-6 then
        Showcase.enqueue_purchase({ card = OTHER, name = "Other", cost = 0, area = "booster_pick" })
      end
      if t >= 70 / 60 - 1e-6 then S.pack_claim_at = G.TIMERS.REAL end
    end,
  })
  check("abandon: captures cleanly", rows.err == nil, rows.err)
  local last = rows[#rows]
  check("abandon: the receipt keeps the stage to its own end",
    last ~= nil and last.t >= 1.6, last and string.format("%.3f", last.t))
  check("abandon: and the countdown ends with it", last ~= nil and last.frac <= FINISH,
    last and string.format("%.3f", last.frac))
  local low, high = 1, 0
  for _, r in ipairs(rows) do
    if r.t >= 1.15 and r.t <= 1.25 and r.frac < low then low = r.frac end
    if r.t >= 1.30 and r.t <= 1.60 and r.frac > high then high = r.frac end
  end
  check("abandon: the armed swap really did run the bar out", low <= 0.05,
    string.format("%.3f", low))
  check("abandon: the bar is not left empty for the receipt's remaining life", high >= 0.15,
    string.format("%.3f", high))
end
clear_jokers()

done()
