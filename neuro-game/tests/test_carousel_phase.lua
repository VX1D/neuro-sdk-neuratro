

local Cap = require("tests.raster_capture")
Cap.rec.enabled = false

local check, done = require("tests.helpers").harness("carousel phase")

local Dev = require("hud.dev_scenario")
local HUD = require("render.hud_overlay")
local S = require("hud.state")
local H = require("render.hud_shared")

Cap.SIZE.w, Cap.SIZE.h = 1280, 720

local PERIOD = H.CAROUSEL_PERIOD
local DT = 1 / 30
local clock_at = Cap.BASE_T

local function scene_index(id)
  for i, sc in ipairs(Dev.SCENES) do if sc.id == id then return i end end
  error("unknown scene '" .. tostring(id) .. "'")
end

local function play(opts)
  Dev.set(false)
  G.TIMERS.REAL = clock_at
  Dev.set(true)
  Dev.select(scene_index(opts.scene))
  if opts.mod then Cap.set_axis("MOD", opts.mod) end
  local tl, err = {}, nil
  local t = 0
  while t <= opts.span + 1e-9 do
    G.TIMERS.REAL = clock_at + t
    Cap.rec.enabled = opts.record and true or false
    Cap.rec.reset()
    Dev.mount()
    if opts.on_frame then opts.on_frame(t) end
    local ok, e = pcall(HUD.draw_indicator)
    local fr = {
      t = t,
      joker = S.desc_slot, cons = S.cons_slot,
      footer = tostring(S.ov and S.ov.footer_sig),
      voucher = S.voucher_rot_idx,
      texts = opts.record and Cap.rec.take() or nil,
    }
    Dev.unmount()
    Cap.rec.enabled = false
    if not ok and not err then err = tostring(e) end
    tl[#tl + 1] = fr
    t = t + DT
  end
  Dev.set(false)
  clock_at = clock_at + opts.span + 1
  return tl, err
end

local function flips(tl, key, from)
  local out = {}
  for i = 2, #tl do
    if tl[i].t >= (from or 0) - 1e-9 and tl[i][key] ~= tl[i - 1][key] then out[#out + 1] = tl[i].t end
  end
  return out
end

local function as_set(list)
  local set = {}
  for _, v in ipairs(list) do set[string.format("%.4f", v)] = true end
  return set
end

local function missing(a, b)
  local sb = as_set(b)
  local out = {}
  for _, v in ipairs(a) do
    if not sb[string.format("%.4f", v)] then out[#out + 1] = string.format("%.2f", v) end
  end
  return out
end

local function fmt(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = string.format("%.2f", v) end
  return "[" .. table.concat(out, " ") .. "]"
end

local JOKERS_AT = 1.5
local held
local tl1, err1 = play({
  scene = "overflow", mod = "All at once", span = 30,
  on_frame = function(t)
    if not held then held = G.jokers.cards end
    G.jokers.cards = (t < JOKERS_AT) and {} or held
  end,
})
check("shared-phase run draws without error", err1 == nil, err1)

local FROM = 2.0
local j1 = flips(tl1, "joker", FROM)
local c1 = flips(tl1, "cons", FROM)
local f1 = flips(tl1, "footer", FROM)

check("both plates rotate in the sample (" .. #j1 .. " joker, " .. #c1 .. " consumable flips)",
  #j1 >= 6 and #c1 >= 6, fmt(j1) .. " vs " .. fmt(c1))
check("the footer turns in the sample (" .. #f1 .. " changes)", #f1 >= 3, fmt(f1))

local jc_extra, cj_extra = missing(j1, c1), missing(c1, j1)
check("jokers and consumables advance on the same frame, every time",
  #jc_extra == 0 and #cj_extra == 0,
  "joker-only " .. table.concat(jc_extra, " ") .. " / consumable-only " .. table.concat(cj_extra, " ")
    .. "  joker=" .. fmt(j1) .. " cons=" .. fmt(c1))

check("the footer only ever changes on a frame the plates flip",
  #missing(f1, j1) == 0,
  "footer alone at " .. table.concat(missing(f1, j1), " ") .. "  footer=" .. fmt(f1)
    .. " plates=" .. fmt(j1))

local cadence_bad = {}
for i = 2, #j1 do
  local gap = j1[i] - j1[i - 1]
  if math.abs(gap - PERIOD) > DT then cadence_bad[#cadence_bad + 1] = string.format("%.2f", gap) end
end
check("the plates hold one cadence across the whole sample",
  #cadence_bad == 0, "gaps off " .. string.format("%.2f", PERIOD) .. "s: " .. table.concat(cadence_bad, " "))

local CUT_AT = 4.0
local cut_done = false
local tl2, err2 = play({
  scene = "overflow", mod = "All at once", span = 16,
  on_frame = function(t)
    if not cut_done and t >= CUT_AT - 1e-9 then
      table.remove(G.jokers.cards, 2)
      cut_done = true
    end
  end,
})
check("content-change run draws without error", err2 == nil, err2)

local j2 = flips(tl2, "joker", 0)
local c2 = flips(tl2, "cons", 0)
local f2 = flips(tl2, "footer", 0)

local jumped = {}
for _, t in ipairs(j2) do
  if t >= CUT_AT - 1e-9 and t <= CUT_AT + 0.30 then jumped[#jumped + 1] = string.format("%.2f", t) end
end
check("a card changing under the cursor does not skip the plate to the next slot",
  #jumped == 0, "flipped at " .. table.concat(jumped, " ") .. " within 0.30s of the change")

local next_flip
for _, t in ipairs(j2) do
  if t > CUT_AT + 0.30 then next_flip = t; break end
end
check("the card that arrives under the cursor gets a whole dwell",
  next_flip ~= nil and (next_flip - CUT_AT) >= PERIOD - DT,
  "next flip at " .. tostring(next_flip) .. " vs change at " .. CUT_AT)

check("a restarted dwell keeps the other two on the same frames",
  #missing(j2, c2) == 0 and #missing(c2, j2) == 0 and #missing(f2, j2) == 0,
  "joker=" .. fmt(j2) .. " cons=" .. fmt(c2) .. " footer=" .. fmt(f2))

local tl3, err3 = play({ scene = "overflow", mod = "All at once", span = PERIOD + 0.6,
  record = true })
check("voucher run draws without error", err3 == nil, err3)

check("the tray opens a run on its first voucher",
  tl3[1] and tl3[1].voucher == 1, "voucher_rot_idx=" .. tostring(tl3[1] and tl3[1].voucher))

local first_counter, counters = nil, {}
for _, fr in ipairs(tl3) do
  for _, line in ipairs(fr.texts or {}) do
    local op = Cap.parse_op(line)
    if op and op.v == "T" and op.text then
      local a, b = op.text:match("^(%d+)/(%d+)$")
      if a and tonumber(b) == 5 then
        counters[#counters + 1] = a .. "/" .. b
        if not first_counter then first_counter = a .. "/" .. b end
      end
    end
  end
end
check("the counter reads 1/N before it ever reads 2/N",
  first_counter == "1/5", "first counter drawn: " .. tostring(first_counter))

local first_turn
for _, fr in ipairs(tl3) do
  if fr.voucher ~= 1 and not first_turn then first_turn = fr.t end
end
check("the tray still rotates after the first voucher", first_turn ~= nil,
  "voucher never left slot 1 across " .. #tl3 .. " frames")
check("and not before its first row has had a whole dwell",
  first_turn ~= nil and first_turn >= PERIOD - DT,
  "turned at " .. tostring(first_turn) .. " of " .. string.format("%.2f", PERIOD))

done()
