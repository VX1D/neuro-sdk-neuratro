

local Drive = require("tests.raster_drive")
local check, done = require("tests.helpers").harness("pack episode")

local S = require("hud.state")
local NeuroAnim = require("render.neuro-anim")

do
  local corridor = {}
  local frames = Drive.play({
    scene = "picklive", persona = "neuro", span = 2.1, from = 1.2,
    on_frame = function(t) corridor[#corridor + 1] = { t = t, cx = S.center_cx_current } end,
  })
  check("picklive drives cleanly", Drive.errors(frames) == nil, Drive.errors(frames))

  local cx_lo, cx_hi
  for _, c in ipairs(corridor) do
    if c.t >= 1.2 and c.cx then
      if not cx_lo or c.cx < cx_lo then cx_lo = c.cx end
      if not cx_hi or c.cx > cx_hi then cx_hi = c.cx end
    end
  end
  check("the corridor holds still for the whole cinematic",
    cx_lo and cx_hi and (cx_hi - cx_lo) <= 2,
    string.format("%s .. %s", tostring(cx_lo), tostring(cx_hi)))

  local prev, worst, worst_t, seen = nil, 0, nil, 0
  for _, fr in ipairs(frames) do
    local p = Drive.pack_panel(fr)
    if p then
      seen = seen + 1
      local c = p.x + p.w / 2
      if prev and math.abs(c - prev) > worst then worst, worst_t = math.abs(c - prev), fr.t end
      prev = c
    end
  end
  check("the cinematic was on screen for the whole window", seen >= 40, seen)
  check("the envelope centre never steps while the card stage is frozen",
    worst <= 2, string.format("%.1f px at t=%s", worst, tostring(worst_t)))
end

do
  local AREA_GONE_AT, STATE_LEFT_AT = 1.00, 1.40
  local overlap = 0
  local frames = Drive.play({
    scene = "buffoon", persona = "neuro", span = 2.4, from = 0.60,
    on_frame = function(t)
      if t >= 0.30 and G.pack_cards and G.pack_cards.cards[2] then
        G.NEURO.ai_highlighted = { [G.pack_cards.cards[2]] = true }
      end
      if t >= AREA_GONE_AT then G.pack_cards = nil end
      if t >= STATE_LEFT_AT then G.NEURO.state, G.NEURO.force_state = "SHOP", "SHOP" end
      if G.pack_cards == nil and (G.NEURO.state or ""):find("_PACK") then overlap = overlap + 1 end
    end,
  })
  check("the teardown drives cleanly", Drive.errors(frames) == nil, Drive.errors(frames))
  check("the fixture really does destroy the area before the state leaves", overlap >= 20, overlap)

  local runs, on, before, first_gone = 0, false, 0, nil
  local traces = {}
  for _, fr in ipairs(frames) do
    local p = Drive.pack_panel(fr)
    local n, amax = Drive.pack_art(fr)
    traces[#traces + 1] = { t = fr.t, p = p, n = n, a = amax }
    if p and not on then runs = runs + 1 end
    if p and fr.t < AREA_GONE_AT then before = before + 1 end
    if not p and on then first_gone = first_gone or fr.t end
    on = p ~= nil
  end
  check("the pack was on screen before the teardown", before >= 20, before)
  check("the panel leaves once and does not come back", runs == 1, runs)

  local x0, h0, moved_x, moved_h = nil, nil, 0, 0
  for _, tr in ipairs(traces) do
    if tr.p and tr.t >= AREA_GONE_AT then
      x0, h0 = x0 or tr.p.x, h0 or tr.p.h
      moved_x = math.max(moved_x, math.abs(tr.p.x - x0))
      moved_h = math.max(moved_h, math.abs(tr.p.h - h0))
    end
  end
  check("the exit holds the frame it was latched at, in x", moved_x <= 1, moved_x)
  check("and in height", moved_h <= 1, moved_h)

  local peak_after_fall, falling, prev_a = 0, false, nil
  for _, tr in ipairs(traces) do
    if tr.p and tr.t >= AREA_GONE_AT then
      if prev_a and tr.a < prev_a - 0.02 then falling = true end
      if falling and prev_a and tr.a - prev_a > peak_after_fall then peak_after_fall = tr.a - prev_a end
      prev_a = tr.a
    end
  end
  check("the exit is a fade, never a relight", falling and peak_after_fall <= 0.02,
    string.format("falling=%s, worst rise +%.3f", tostring(falling), peak_after_fall))
  check("and the panel is gone by the end of it", traces[#traces].p == nil,
    tostring(first_gone))
end

do
  local claimed = false
  local frames = Drive.play({
    scene = "buffoon", persona = "neuro", span = 3.2, from = 0.90,
    on_frame = function(t)
      G.GAME.pack_choices = 2
      if t >= 1.0 and not claimed then
        claimed = true
        local pack = G.pack_cards
        local w = pack and pack.cards and pack.cards[2]
        if w then
          NeuroAnim.pick_pack_card(w, pack)
          for i, c in ipairs(pack.cards) do
            if c == w then table.remove(pack.cards, i) break end
          end
        end
      end
    end,
  })
  check("the mega-pack claim drives cleanly", Drive.errors(frames) == nil, Drive.errors(frames))

  local h_lo, h_hi, worst, worst_t, prev = nil, nil, 0, nil, nil
  for _, fr in ipairs(frames) do
    local p = Drive.pack_panel(fr)
    if p then
      h_lo = math.min(h_lo or p.h, p.h)
      h_hi = math.max(h_hi or p.h, p.h)
      if prev and prev - p.h > worst then worst, worst_t = prev - p.h, fr.t end
      prev = p.h
    end
  end
  check("the collapse really does grow the envelope", h_lo and (h_hi - h_lo) >= 15,
    string.format("%s .. %s", tostring(h_lo), tostring(h_hi)))
  check("and it eases back to the slot layout instead of cutting back",
    worst <= 8, string.format("%.0f px in one frame at t=%s", worst, tostring(worst_t)))
  check("the panel is still on screen after the handback", prev ~= nil and prev == h_lo,
    string.format("last %s, floor %s", tostring(prev), tostring(h_lo)))
end

do
  local Showcase = require("hud.showcase")
  local Episode = require("hud.episode")

  local function gain(name)
    return { card = { ability = { name = name }, config = { center = { set = "Tarot" } } }, label = name }
  end

  Showcase.reset_run_state()
  G.NEURO.state, G.NEURO.force_state = "SHOP", "SHOP"
  Episode.claim_pack(1)
  S.pack_gained_q[#S.pack_gained_q + 1] = gain("Parked")
  Showcase.update_joker(0.1)
  check("a gain parked during the cinematic is held even though the state has left the pack",
    #S.pack_gained_q == 1 and #S.joker_showcase_q == 0 and S.joker_showcase == nil,
    string.format("parked %d, queued %d", #S.pack_gained_q, #S.joker_showcase_q))

  Episode.claim_pack(false)
  Showcase.update_joker(0.2)
  check("and is released the moment the panel gives the stage back",
    #S.pack_gained_q == 0 and (S.joker_showcase ~= nil or #S.joker_showcase_q > 0),
    string.format("parked %d, queued %d, live %s",
      #S.pack_gained_q, #S.joker_showcase_q, tostring(S.joker_showcase ~= nil)))
  Showcase.reset_run_state()
end

do
  local corridor = {}
  local frames = Drive.play({
    scene = "packtear", persona = "neuro", span = 2.6, from = 1.2,
    on_frame = function(t) corridor[#corridor + 1] = { t = t, cx = S.center_cx_current } end,
  })
  check("packtear drives cleanly", Drive.errors(frames) == nil, Drive.errors(frames))

  local cx_lo, cx_hi
  for _, c in ipairs(corridor) do
    if c.cx then
      cx_lo = math.min(cx_lo or c.cx, c.cx)
      cx_hi = math.max(cx_hi or c.cx, c.cx)
    end
  end
  check("the corridor holds still across both observables",
    cx_lo and (cx_hi - cx_lo) <= 2, string.format("%s .. %s", tostring(cx_lo), tostring(cx_hi)))

  local gap, worst, worst_t, prev_seen, prev_c = 0, 0, nil, false, nil
  local run = 0
  for _, fr in ipairs(frames) do
    local p = Drive.pack_panel(fr)
    if p then
      if prev_c and math.abs((p.x + p.w / 2) - prev_c) > worst then
        worst, worst_t = math.abs((p.x + p.w / 2) - prev_c), fr.t
      end
      prev_c = p.x + p.w / 2
      if prev_seen == false and run > 0 then gap = math.max(gap, run) end
      run = 0
    elseif prev_seen then
      run = run + 1
    end
    prev_seen = p ~= nil
  end
  check("the envelope centre never steps while the card stage is frozen",
    worst <= 2, string.format("%.1f px at t=%s", worst, tostring(worst_t)))
  check("and the panel never blanks and comes back", gap == 0, gap)

  local src = io.open("render/panels/pack.lua", "r"):read("a")
  check("the collapse snapshot owns the envelope centre, not the live corridor",
    src:find("snap.center_cx", 1, true) ~= nil)
end

done()
