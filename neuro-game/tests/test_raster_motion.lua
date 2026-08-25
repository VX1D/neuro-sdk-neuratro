

local Cap = require("tests.raster_capture")
local Drive = require("tests.raster_drive")
local check, done = require("tests.helpers").harness("raster motion")

local SIZE = { w = 1280, h = 720 }
local LEFT_EDGE = 290          -- separates shop panel (left) from right panel (starts past x=1000)

local function no_errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return false, fr.err end
  end
  return true
end

local function moments(t0, step, n)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = t0 + step * i end
  return out
end

local function plate_count(frame)
  local n = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.w and op.h
      and op.w >= 150 and op.h >= 200 and (op.a or 0) >= 0.90 then
      n = n + 1
    end
  end
  return n
end

local function shop_plate_alpha(frame)
  local best = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.w and op.h and op.x
      and op.x < LEFT_EDGE and op.w >= 150 and op.h >= 200 and (op.a or 0) > best then
      best = op.a
    end
  end
  return best
end

local function text_extent(frame)
  local n, top, bottom
  n = 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.x and op.y and op.x < LEFT_EDGE and (op.a or 1) > 0.12 then
      n = n + 1
      if not top or op.y < top then top = op.y end
      if not bottom or op.y > bottom then bottom = op.y end
    end
  end
  return n, top, bottom
end

local LEAVE_AT = 0.8

do
  local frames = Cap.capture({ scene = "leaveshop", persona = "neuro", size = SIZE,
    moments = moments(0.74, 0.03, 8) })
  check("leaveshop captures cleanly", no_errors(frames))

  local before, during = plate_count(frames[1]), plate_count(frames[#frames])
  check("both panels are up before the shop leaves", before == 2, before)
  check("the shop panel is still drawn after its state has gone", during == 2, during)

  local alphas, monotone, prev = {}, true, nil
  for _, fr in ipairs(Cap.capture({ scene = "leaveshop", persona = "neuro", size = SIZE,
    moments = moments(LEAVE_AT, 0.04, 14) })) do
    local a = shop_plate_alpha(fr)
    alphas[#alphas + 1] = string.format("%.2f", a)
    if prev and a > prev + 0.02 then monotone = false end
    prev = a
  end
  check("the plate fades, it never brightens back", monotone, table.concat(alphas, " "))
end

do
  local frames = Cap.capture({ scene = "leaveshop", persona = "neuro", size = SIZE,
    moments = moments(LEAVE_AT, 0.04, 16) })
  check("leaveshop ramp capture is clean", no_errors(frames))

  local mid, seen = 0, {}
  for _, fr in ipairs(frames) do
    local a = shop_plate_alpha(fr)
    seen[#seen + 1] = string.format("%.2f", a)
    if a > 0.10 and a < 0.85 then mid = mid + 1 end
  end
  check("the plate is caught mid-ramp, not stepping", mid >= 4, mid .. " of " .. #frames
    .. " [" .. table.concat(seen, " ") .. "]")

  local late = Cap.capture({ scene = "leaveshop", persona = "neuro", size = SIZE,
    moments = { 1.60, 1.80 } })
  check("leaveshop late capture is clean", no_errors(late))
  local still_up = 0
  for _, fr in ipairs(late) do
    if shop_plate_alpha(fr) > 0.01 then still_up = still_up + 1 end
  end
  check("and it finishes -- no ghost is parked on screen", still_up == 0, still_up)
end

do
  local ms = moments(0.78, 0.035, 14)
  local frames = Cap.capture({ scene = "leaveshop", persona = "neuro", size = SIZE, moments = ms })
  check("leaveshop stagger capture is clean", no_errors(frames))

  local n0, top0, bottom0 = text_extent(frames[1])
  check("the shop stack is full before the leave", n0 > 40 and top0 and bottom0, tostring(n0))

  local probe
  for i, fr in ipairs(frames) do
    local n = text_extent(fr)
    if n > 0 and n <= n0 * 0.6 and not probe then probe = i end
  end
  check("the stack does drain within the window", probe ~= nil, tostring(probe))

  if probe then
    local _, top1, bottom1 = text_extent(frames[probe])
    check("the bottom of the stack goes first", bottom1 < bottom0 - 40,
      tostring(bottom0) .. " -> " .. tostring(bottom1))
    check("while the top is still there", top1 <= top0 + 8,
      tostring(top0) .. " -> " .. tostring(top1))
  end
end

local function clone_card(c)
  local t = {}
  for k, v in pairs(c) do t[k] = v end
  return setmetatable(t, getmetatable(c))
end

local function drive_reroll(at)
  local fired = false
  return function(t)
    if t >= at - 1e-9 and not fired then
      fired = true
      local cards = G.shop_jokers and G.shop_jokers.cards
      if cards then
        for i = 1, #cards do cards[i] = clone_card(cards[i]) end
      end
    end
  end, function() return fired end
end

do
  local on_frame, fired = drive_reroll(3.00)
  local frames = Drive.play({ scene = "shop", persona = "neuro", size = SIZE,
    span = 3.30, from = 2.98, fps = 40, on_frame = on_frame })
  check("shop reroll capture is clean", Drive.errors(frames) == nil, Drive.errors(frames))
  check("the reroll really happened", fired())

  local lo, hi, seen = 9, 0, {}
  for _, fr in ipairs(frames) do
    local a = shop_plate_alpha(fr)
    seen[#seen + 1] = string.format("%.2f", a)
    if a < lo then lo = a end
    if a > hi then hi = a end
  end
  check("a reroll does not make the panel see-through", hi > 0 and lo >= hi * 0.95,
    table.concat(seen, " "))
end

local function showcase_frame_y(frame, sw)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.h and op.x and op.y
      and op.x > sw * 0.25 and op.x < sw * 0.75 and op.h >= 60 and op.w >= 120 then
      if not best or op.w > best.w then best = op end
    end
  end
  return best and best.y
end

local function travel(size)
  local ms = {}
  for i = 0, 39 do ms[#ms + 1] = 0.03 + i * 0.13 end
  local frames = Cap.capture({ scene = "showcase", persona = "neuro", size = size, moments = ms })
  local ys = {}
  for i, fr in ipairs(frames) do ys[i] = showcase_frame_y(fr, size.w) end

  local tally, settled, best_n = {}, nil, 0
  for _, y in pairs(ys) do if y then tally[y] = (tally[y] or 0) + 1 end end
  for y, n in pairs(tally) do if n > best_n then settled, best_n = y, n end end
  if not settled then return nil end

  local first, last
  for i, y in ipairs(ys) do
    if y == settled then first = first or i; last = i end
  end
  local rise, fall = 0, 0
  for i = 1, (first or 1) - 1 do
    if ys[i] then rise = math.max(rise, ys[i] - settled) end
  end
  for i = (last or #ys) + 1, #ys do
    if ys[i] then fall = math.max(fall, ys[i] - settled) end
  end
  return { settled = settled, rise = rise, fall = fall, frames = frames }
end

do
  local small = travel({ w = 1280, h = 720 })
  local large = travel({ w = 1920, h = 1080 })
  check("showcase travel measured at 720", small ~= nil)
  check("showcase travel measured at 1080", large ~= nil)

  if small and large then
    check("showcase captures cleanly at 720", no_errors(small.frames))
    check("showcase captures cleanly at 1080", no_errors(large.frames))

    check("it arrives from below and withdraws downward",
      small.rise > 0 and small.fall > 0 and large.rise > 0 and large.fall > 0,
      small.rise .. "/" .. small.fall .. "  " .. large.rise .. "/" .. large.fall)

    check("it leaves by the distance it arrived (720)",
      math.abs(small.rise - small.fall) <= 1, small.rise .. " vs " .. small.fall)
    check("it leaves by the distance it arrived (1080)",
      math.abs(large.rise - large.fall) <= 1, large.rise .. " vs " .. large.fall)

    check("and the distance actually scales with the viewport", large.rise > small.rise + 1,
      small.rise .. " at 720 vs " .. large.rise .. " at 1080")
  end
end

local function receipt_body(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.x and op.w and op.h
      and op.x > 260 and op.x < 1020 and op.w >= 100 and op.h >= 25 and (op.a or 0) >= 0.5 then
      if not best or (op.a or 0) > (best.a or 0) then best = op end
    end
  end
  return best
end

for _, persona in ipairs({ "neuro", "evil", "hiyori" }) do
  local ms = {}
  for i = 0, 25 do ms[#ms + 1] = 0.80 + i * 0.025 end
  local frames = Cap.capture({ scene = "crosscut", persona = persona, size = SIZE, moments = ms })
  check("crosscut captures cleanly (" .. persona .. ")", no_errors(frames))

  local alphas, widths, drawn = {}, {}, 0
  for _, fr in ipairs(frames) do
    local b = receipt_body(fr)
    if b then
      drawn = drawn + 1
      alphas[#alphas + 1] = b.a
      widths[#widths + 1] = b.w
    else
      alphas[#alphas + 1] = 0
      widths[#widths + 1] = 0
    end
  end

  check("the receipt body is drawn on every frame of the swap (" .. persona .. ")",
    drawn == #frames, drawn .. "/" .. #frames)

  local lo, hi = 9, 0
  for _, a in ipairs(alphas) do
    if a < lo then lo = a end
    if a > hi then hi = a end
  end
  check("the frame holds its alpha across a cross-cut (" .. persona .. ")",
    hi > 0 and lo >= hi * 0.95, string.format("%.2f..%.2f", lo, hi))

  local w_lo, w_hi = 9999, 0
  for _, w in ipairs(widths) do
    if w > 0 then
      if w < w_lo then w_lo = w end
      if w > w_hi then w_hi = w end
    end
  end
  local between = 0
  for _, w in ipairs(widths) do
    if w > w_lo and w < w_hi then between = between + 1 end
  end
  check("the box width interpolates rather than snapping (" .. persona .. ")",
    w_hi > w_lo and between >= 2,
    w_lo .. ".." .. w_hi .. " with " .. between .. " between")
end

local function flying_card(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and op.x and op.x > 400 and op.x < 1065 and op.y and op.y > 20 then
      if not best or op.x > best.x then best = op end
    end
  end
  return best
end

do
  local ms = {}
  for i = 0, 15 do ms[#ms + 1] = 4.60 + i * 0.06 end
  local frames = Cap.capture({ scene = "vouchers", persona = "neuro", size = SIZE, moments = ms })
  check("voucher flight captures cleanly", no_errors(frames))

  local path = {}
  for _, fr in ipairs(frames) do
    local c = flying_card(fr)
    if c then path[#path + 1] = { x = c.x, y = c.y, a = c.a or 1 } end
  end
  check("the card is seen in transit", #path >= 5, #path)

  if #path >= 5 then
    check("the flight actually moves toward the drawer",
      path[#path].x > path[1].x + 200,
      math.floor(path[1].x) .. " -> " .. math.floor(path[#path].x))

    local mid_a, end_a = 0, 9
    for i, pt in ipairs(path) do
      if i <= math.floor(#path / 2) and pt.a > mid_a then mid_a = pt.a end
      if i >= #path - 1 and pt.a < end_a then end_a = pt.a end
    end
    check("the card is solid in mid-flight", mid_a > 0.9, string.format("%.2f", mid_a))
    check("and dissolves into the badge as it lands, rather than vanishing at full opacity",
      end_a < 0.5, string.format("%.2f", end_a))
  end
end

local function divider_segments(frame)
  local out = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.x and op.x < LEFT_EDGE and op.w and op.h
      and op.w >= 25 and op.w <= 40 and op.h <= 4 then
      out[#out + 1] = op.a or 0
    end
  end
  table.sort(out)
  return out
end

do
  local on_frame, fired = drive_reroll(3.00)
  local frames = Drive.play({ scene = "shop", persona = "evil", size = SIZE,
    span = 3.79, from = 2.94, fps = 20, on_frame = on_frame })
  check("shop divider capture is clean", Drive.errors(frames) == nil, Drive.errors(frames))
  check("the fixture really did replace every shop joker", fired())

  local settled, dipped, swept = 0, 9, false
  for i, fr in ipairs(frames) do
    local segs = divider_segments(fr)
    if #segs >= 4 then
      local top = segs[#segs]
      if i <= 2 and top > settled then settled = top end
      if i > 2 and top < dipped then dipped = top end
      if i > 2 and i < #frames - 4 and segs[#segs] > segs[#segs - 3] * 1.2 then swept = true end
    end
  end

  check("the divider re-lights on a reroll rather than holding", dipped < settled * 0.7,
    string.format("settled %.2f, dipped %.2f", settled, dipped))
  check("and it lights segment by segment, not all at once", swept)
end

local function card_art_count(frame)
  return (Drive.pack_art(frame))
end

do
  local AREA_GONE_AT, STATE_LEFT_AT = 0.80, 1.20
  local frames = Drive.play({
    scene = "buffoon", persona = "neuro", size = SIZE, span = 1.60, from = 0.60, fps = 30,
    on_frame = function(t)
      if t >= AREA_GONE_AT then G.pack_cards = nil end
      if t >= STATE_LEFT_AT then G.NEURO.state, G.NEURO.force_state = "SHOP", "SHOP" end
    end,
  })
  check("the pack teardown captures cleanly", Drive.errors(frames) == nil, Drive.errors(frames))

  local counts, snap_only = {}, 0
  for _, fr in ipairs(frames) do
    local n = card_art_count(fr)
    counts[#counts + 1] = n
    if fr.t >= AREA_GONE_AT + 0.20 and fr.t < STATE_LEFT_AT and n > 0 then snap_only = snap_only + 1 end
  end

  local before = counts[1]
  check("the pack is showing its cards before it closes", before >= 3, before)
  check("the leave snapshot carries the card itself, not just its nameplate", snap_only >= 4,
    table.concat(counts, ","))
  check("the art drains as the panel leaves", counts[#counts] < before,
    before .. " -> " .. counts[#counts])
  check("and it drains monotonically, never coming back", (function()
    local prev, worst = nil, 0
    for _, n in ipairs(counts) do
      if prev and n - prev > worst then worst = n - prev end
      prev = n
    end
    return worst == 0
  end)(), table.concat(counts, ","))
end

local PACK_BANDS = { { 440, 480 }, { 537, 577 }, { 634, 674 }, { 731, 771 } }

local function band_weight(frame)
  local sums = { 0, 0, 0, 0 }
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.x and op.w and op.h and op.w >= 40 and op.w <= 120
      and op.h >= 55 and op.h <= 160 and (op.a or 0) > 0.01 then
      for i, b in ipairs(PACK_BANDS) do
        if op.x >= b[1] and op.x <= b[2] then sums[i] = sums[i] + op.a end
      end
    end
  end
  return sums
end

do
  local frames = Cap.capture({ scene = "packhidden", persona = "neuro", size = SIZE,
    moments = { 1.30, 1.50, 1.60 } })
  check("packhidden captures cleanly", no_errors(frames))

  local mid = band_weight(frames[2])
  local peers = math.min(mid[3], mid[4])
  check("the losers really are mid-dissolve at the sampled moment", peers > 0.05 and peers < 1.0,
    string.format("%.2f", peers))
  check("the face-down slot dissolves with its neighbours rather than leaving a hole",
    mid[1] >= peers, string.format("hidden %.2f vs peers %.2f", mid[1], peers))

  local late = band_weight(frames[3])
  check("and it finishes leaving too", late[1] < mid[1],
    string.format("%.2f -> %.2f", mid[1], late[1]))
end

local function slot_plates(frame)
  local out = {}
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "fill" and op.w and op.h and op.x
      and op.w >= 40 and op.w <= 130 and op.h >= 40 and op.h <= 170 then
      out[#out + 1] = { x = op.x, h = op.h, a = op.a or 0 }
    end
  end
  return out
end

local function first_slot_plate_h(frame)
  local best
  for _, p in ipairs(slot_plates(frame)) do
    if p.x > 440 and p.x < 480 and (not best or p.a > best.a) then best = p end
  end
  return best and best.h
end

do
  local function plate_for(card_label)
    local frames = Cap.capture({ scene = "buffoon", persona = "neuro", size = SIZE,
      moments = { 1.6 }, axes = { CARD = card_label } })
    return no_errors(frames) and first_slot_plate_h(frames[1]) or nil
  end

  local tall = plate_for("Joker")
  local short = plate_for("Wide art")
  check("both pack captures are clean and find a slot plate", tall ~= nil and short ~= nil,
    tostring(tall) .. " / " .. tostring(short))

  if tall and short then
    check("a short-art joker does not sit on a full-height black plate", short < tall,
      tall .. " (ordinary) vs " .. short .. " (short art)")
    check("an ordinary joker keeps the nominal plate", tall >= 100, tostring(tall))
  end
end

done()
