_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("motion primitives")

_G.G = {
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1 }, NEURO = {},
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
}
_G.SMODS = { current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end, Mods = {} }
love = setmetatable({
  timer = { getTime = function() return G.TIMERS.REAL end },
  graphics = setmetatable({}, { __index = function() return function() end end }),
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

local NeuroAnim = require("render.neuro-anim")
local Motion = NeuroAnim.Motion

local DT = 1 / 60
local RATE = Motion.MED / 4

local function fail_count(site)
  return (NeuroAnim._anim_fails and NeuroAnim._anim_fails[site]) or 0
end

check("Motion.glide is gone; the shape that hid the defect cannot be reached by name",
  Motion.glide == nil)
check("the three primitives exist", type(Motion.snap) == "function"
  and type(Motion.tween) == "function" and type(Motion.approach) == "function")

check("anim01 leads before its window (t < 0 -> 0)", Motion.anim01(-1, 0.25) == 0)
check("anim01 snaps on a zero duration (d <= 0 -> 1)", Motion.anim01(0, 0) == 1)
check("anim01 is saturated at its end", Motion.anim01(0.25, 0.25) == 1)

for _, frames in ipairs({ 1, 2, 5, 10, 15, 30, 60 }) do
  local s = {}
  Motion.approach(s, "y", 100, DT, RATE)
  local start = s.y_current
  for i = 1, frames do Motion.approach(s, "y", 100 + i, DT, RATE) end
  local moved = s.y_current - start
  check(string.format("approach moves on a target that steps every frame (%d frames, %.4f px)",
    frames, moved), moved > 0)
end

do
  local s = {}
  Motion.approach(s, "y", 300, DT, RATE)
  local lo, hi = math.huge, -math.huge
  for i = 1, 600 do
    Motion.approach(s, "y", (i % 2 == 0) and 300 or 301, DT, RATE)
    if s.y_current < lo then lo = s.y_current end
    if s.y_current > hi then hi = s.y_current end
  end
  check(string.format("approach tracks an alternating target rather than freezing (range %.4f)",
    hi - lo), hi - lo > 0)
  check("and stays inside the two values it is handed",
    s.y_current >= 299.999 and s.y_current <= 301.001, s.y_current)
end

do
  local s = {}
  Motion.approach(s, "y", 0, DT, RATE)
  local frames = 0
  while s.y_current ~= 100 and frames < 600 do
    Motion.approach(s, "y", 100, DT, RATE)
    frames = frames + 1
  end
  check(string.format("approach converges exactly on a static target (%d frames, %.2f s)",
    frames, frames * DT), s.y_current == 100 and frames * DT < 1.0)
end

do
  local s = {}
  Motion.approach(s, "y", 0, DT, RATE)
  for _ = 1, 5 do Motion.approach(s, "y", 100, DT, RATE) end
  local mid = s.y_current
  local after_retarget = Motion.approach(s, "y", -50, DT, RATE)
  check("a retarget is continuous: the value does not jump on the frame the target flips",
    math.abs(after_retarget - mid) < math.abs(mid - (-50)), mid .. " -> " .. after_retarget)
  check("and it then heads for the new target",
    after_retarget < mid, mid .. " -> " .. after_retarget)
end

-- A run reset rewinds G.TIMERS.REAL to 12 (dump game.lua:1556-1558). approach never reads an
-- instant, so the rewind reaches it only as a non-positive dt, which must leave the value alone.
do
  local s = {}
  Motion.approach(s, "y", 0, DT, RATE)
  for _ = 1, 10 do Motion.approach(s, "y", 100, DT, RATE) end
  local before = s.y_current
  Motion.approach(s, "y", 100, -5000, RATE)
  Motion.approach(s, "y", 100, 0, RATE)
  check("a rewound clock does not teleport an approach", s.y_current == before,
    before .. " -> " .. s.y_current)
end

do
  local s = {}
  Motion.approach(s, "f", 0, DT, RATE)
  local frames = 0
  while s.f_current ~= 1 and frames < 600 do
    Motion.approach(s, "f", 1, DT, RATE)
    frames = frames + 1
  end
  check("approach settles exactly on a 0..1 fraction too, not only in pixels",
    s.f_current == 1, tostring(s.f_current) .. " after " .. frames)
end

do
  local s = {}
  check("approach with no rate is a snap", Motion.approach(s, "y", 42, DT, 0) == 42)
  check("snap writes the value and nothing else",
    Motion.snap(s, "z", 7) == 7 and s.z_current == 7 and s.z_at == nil and s.z_target == nil)
end

do
  local s = {}
  local now = 0
  Motion.tween(s, "y", 0, now, Motion.MED)
  for _ = 1, 20 do
    now = now + DT
    Motion.tween(s, "y", 100, now, Motion.MED)
  end
  check("tween completes a single step within its duration", s.y_current == 100, s.y_current)
end

do
  local before = fail_count("tween_continuous:diag_a")
  local s = {}
  local now = 0
  Motion.tween(s, "diag_a", 0, now, Motion.MED)
  for i = 1, 30 do
    now = now + DT
    Motion.tween(s, "diag_a", i, now, Motion.MED)
  end
  check("tween diagnoses a target that moves on consecutive frames ("
    .. (fail_count("tween_continuous:diag_a") - before) .. ")",
    fail_count("tween_continuous:diag_a") - before == 1)
  check("and the value it produced really did stand still, which is what the diagnostic is about",
    s.diag_a_current == 0, s.diag_a_current)
end

do
  local before = fail_count("tween_continuous:diag_b")
  local s = {}
  local now = 0
  Motion.tween(s, "diag_b", 0, now, Motion.MED)
  for i = 1, 40 do
    now = now + DT
    Motion.tween(s, "diag_b", math.floor(i / 5), now, Motion.MED)
  end
  check("a discrete target is not diagnosed (" .. (fail_count("tween_continuous:diag_b") - before)
    .. ")", fail_count("tween_continuous:diag_b") - before == 0)
  for _ = 1, 20 do
    now = now + DT
    Motion.tween(s, "diag_b", 8, now, Motion.MED)
  end
  check("and it does reach its target once the stepping stops", s.diag_b_current == 8,
    s.diag_b_current)
end

do
  local before = fail_count("tween_continuous:diag_c")
  local s = {}
  local now = 0
  Motion.tween(s, "diag_c", 0, now, 0)
  for i = 1, 30 do
    now = now + DT
    Motion.tween(s, "diag_c", i, now, 0)
  end
  check("a zero-duration tween is a snap, so a moving target is not an error there ("
    .. (fail_count("tween_continuous:diag_c") - before) .. ")",
    fail_count("tween_continuous:diag_c") - before == 0)
  check("and it tracks the target exactly", s.diag_c_current == 30, s.diag_c_current)
end

do
  local function src(path) return io.open(path, "r"):read("a") end
  local overlay = src("render/hud_overlay.lua")
  local shared = src("render/hud_shared.lua")
  local vouchers = src("hud/vouchers.lua")

  check("panel_x is a snap", overlay:find('Motion.snap(S, "panel_x"', 1, true) ~= nil)
  check("panel_y takes the follower", overlay:find('Motion.approach(S, "panel_y"', 1, true) ~= nil)
  check("the right-panel slide is a tween, not a fourth inlined copy of the formula",
    overlay:find('Motion.tween(S, "rp_slide"', 1, true) ~= nil)
  check("the left-panel slide too", overlay:find('Motion.tween(S, "lp_slide"', 1, true) ~= nil)
  check("no inlined ramp is left in the overlay",
    overlay:find("_slide_from\n", 1, true) == nil and overlay:find("S.rp_slide_at, PANEL", 1, true) == nil)
  check("the corridor snaps", shared:find('Motion.snap(S, "center_cx"', 1, true) ~= nil
    and shared:find('Motion.snap(S, "center_w"', 1, true) ~= nil)
  check("the voucher drawer keeps its discrete tween",
    vouchers:find('Motion.tween(S, "drawer_slide"', 1, true) ~= nil)
  for _, path in ipairs({ "render/hud_overlay.lua", "render/hud_shared.lua", "hud/vouchers.lua",
                          "render/neuro-anim.lua" }) do
    check("no Motion.glide call survives in " .. path,
      src(path):find("Motion.glide", 1, true) == nil)
  end
end

done()
