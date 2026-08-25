

local Cap = require("tests.raster_capture")
local Drive = require("tests.raster_drive")
local check, done = require("tests.helpers").harness("pack standard hero")

local S = require("hud.state")
local Pack = require("render.panels.pack")
local NeuroAnim = require("render.neuro-anim")
local Cards = require("hud.cards")
local TL = require("render.panels.pack_neuro").TL

local CLAIM_AT = 1.0
local HERO_MIN = 1.3   -- hero scale is 1.42x the slot; nothing else in the collapse exceeds 1.0x

local function run(flip, mutate, scene)
  local claimed, obs = false, { hero = {} }
  local frames = Drive.play({
    scene = scene or "standard", persona = "neuro", span = 3.0, from = CLAIM_AT - 0.1, fps = 60,
    on_frame = function(t)
      if t >= CLAIM_AT and not claimed then
        claimed = true
        local pack = G.pack_cards
        local winner = pack.cards[2] or pack.cards[1]
        if flip == "before" then winner.facing = "back" end
        NeuroAnim.pick_pack_card(winner, pack)
        for i = #pack.cards, 1, -1 do pack.cards[i] = nil end
        if flip == "after" then winner.facing = "back" end
        if mutate then mutate(winner) end
        obs.card = winner
      end
      local w = (S.pack_winners or {})[1]
      if w then
        obs.t0, obs.anoint, obs.hidden = w.t0, w._anoint, w.hidden
      end
      local sn = S.pack_collapse_snap
      if sn then obs.sp_h, obs.loser_max, obs.ct = sn.sp_h, sn.loser_max, S.pack_collapse_t end
    end,
  })
  obs.claimed, obs.err, obs.frames = claimed, Drive.errors(frames), frames

  local thr = (obs.sp_h or 0) * HERO_MIN
  for _, fr in ipairs(frames) do
    local h, a = 0, 0
    for _, line in ipairs(fr.ops) do
      local op = Cap.parse_op(line)
      if op and op.v == "I" and (op.h or 0) > thr and (op.h or 0) > h then h, a = op.h, op.a or 0 end
    end
    obs.hero[#obs.hero + 1] = { t = fr.t, h = h, a = a }
  end
  return obs
end

local function hold_window(obs)
  local t0 = (obs.t0 or 0) - Cap.BASE_T
  local ct = (obs.ct or 0) - Cap.BASE_T
  local from = t0 + (obs.anoint or TL.ANOINT) + TL.GLIDE
  local to = ct + TL.ANOINT + math.max(TL.GLIDE, obs.loser_max or 0) + TL.SHRINK + TL.HOLD
  return from + 0.02, to - 0.02
end

do
  local obs = run("after")
  check("standard claim drives cleanly", obs.claimed and obs.err == nil, obs.err)
  check("the collapse snapshot was taken", obs.sp_h ~= nil and obs.ct ~= nil, obs.sp_h)
  check("the engine really did flip the claimed card", obs.card and obs.card.facing == "back",
    obs.card and obs.card.facing)
  check("the winner snapshot records the facing it was claimed at", obs.hidden == false,
    tostring(obs.hidden))

  local t_from, t_to = hold_window(obs)
  local seen, blank, worst_t = 0, 0, nil
  for _, fr in ipairs(obs.hero) do
    if fr.t >= t_from and fr.t <= t_to then
      seen = seen + 1
      if fr.h <= 0 or fr.a < 0.5 then blank = blank + 1; worst_t = worst_t or fr.t end
    end
  end
  check("the hold window was reached", seen >= 20, seen)
  check("the hero is on screen at hero scale for every frame of the collapse", blank == 0,
    string.format("%d/%d blank frames, first at t=%s", blank, seen, tostring(worst_t)))

  local peak = 0
  for _, fr in ipairs(obs.hero) do if fr.h > peak then peak = fr.h end end
  check("and it reaches full hero scale", obs.sp_h and peak >= obs.sp_h * 1.35,
    string.format("%.1f vs sp_h %s", peak, tostring(obs.sp_h)))
end

do
  local obs = run("before")
  check("face-down claim drives cleanly", obs.claimed and obs.err == nil, obs.err)
  check("a card claimed face down is snapshotted as hidden", obs.hidden == true, tostring(obs.hidden))
  local drew = 0
  for _, fr in ipairs(obs.hero) do if fr.h > 0 then drew = drew + 1 end end
  check("and its art is never drawn", drew == 0, drew)
end

do
  local base = run(nil, nil, "buffoon")
  local probe = {}
  local after = run(nil, function(card)
    probe.ak0, probe.mini0 = Cards.card_sprite(card), Cards.art_prefers_mini(card)
    card.config.card = { pos = { x = 0, y = 0 }, suit = "Spades" }
    probe.ak1, probe.mini1 = Cards.card_sprite(card), Cards.art_prefers_mini(card)
  end, "buffoon")
  check("both snapshot-invariance runs drove cleanly",
    base.claimed and after.claimed and base.err == nil and after.err == nil, base.err or after.err)
  check("the mutation is invisible to the sprite resolver and flips only the mini choice",
    probe.ak1 == probe.ak0 and probe.mini0 == false and probe.mini1 == true,
    string.format("%s/%s -> %s/%s", tostring(probe.ak0), tostring(probe.mini0),
      tostring(probe.ak1), tostring(probe.mini1)))

  local diff_t, diff_n = nil, 0
  check("the two runs produced the same frames", #base.frames == #after.frames,
    #base.frames .. " vs " .. #after.frames)
  for i = 1, math.min(#base.frames, #after.frames) do
    local a, b = base.frames[i], after.frames[i]
    local same = #a.ops == #b.ops
    if same then
      for j = 1, #a.ops do
        if a.ops[j] ~= b.ops[j] then same = false break end
      end
    end
    if not same then
      diff_n = diff_n + 1
      diff_t = diff_t or string.format("t=%.3f (%d vs %d ops)", a.t, #a.ops, #b.ops)
    end
  end
  check("a post-claim edit to the live card changes nothing the cinematic draws",
    diff_n == 0, string.format("%d frames differ, first %s", diff_n, tostring(diff_t)))
end

check("the hero scale the assertions key on is the panel's own", Pack.SIZING.HERO_SCALE > HERO_MIN,
  Pack.SIZING.HERO_SCALE)

done()
