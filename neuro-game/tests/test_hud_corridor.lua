_G.NEURO_TEST = true

local function noop() end
local function px_font(px)
  return {
    getWidth = function(_, s) return math.floor(0.5 * px * #tostring(s or "") + 0.5) end,
    getHeight = function() return math.floor(1.3 * px + 0.5) end,
  }
end
local FONT = px_font(24)
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getScissor = function() return nil end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end },
  mouse = { getPosition = function() return -1, -1 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = { persona = "neuro" }, FUNCS = {}, TIMERS = { REAL = 0 },
  GAME = { dollars = 10, current_round = { reroll_cost = 5 } },
  STATES = {}, SETTINGS = { paused = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("hud corridor")

local H = require("render.hud_shared")
local S = H.S

local function cn(v) return math.max(1, math.floor((tonumber(v) or 0) + 0.5)) end

local function reset_corridor_state()
  S.center_cx_current, S.center_cx_from, S.center_cx_target, S.center_cx_at = nil, nil, nil, nil
  S.center_w_current, S.center_w_from, S.center_w_target, S.center_w_at = nil, nil, nil, nil
end

local DT = 1 / 60

do
  reset_corridor_state()
  local ctx1 = {}
  local cx0 = H.corridor(ctx1, 1920, "left", 100, 0, 0, DT, cn)

  local ctx2 = {}
  local cx1 = H.corridor(ctx2, 1920, "right", 100, 0, DT, DT, cn)
  check("corridor: cx snaps to the new midpoint on the frame the target flips",
    cx1 ~= cx0 and cx1 == 140, cx1 .. " vs " .. cx0)

  local ctx3 = {}
  local cx2 = H.corridor(ctx3, 1920, "right", 100, 0, 2 * DT, DT, cn)
  check("corridor: a frame whose lo/hi did not change does not move cx",
    cx2 == cx1, cx2 .. " vs " .. cx1)
end

do
  reset_corridor_state()
  local seen = {}
  for i = 0, 29 do
    local ctx = {}
    seen[#seen + 1] = H.corridor(ctx, 1920, "right", 400 + i, 0, i * DT, DT, cn)
  end
  local moved = seen[#seen] - seen[1]
  check("corridor: a per-frame edge is tracked, not frozen (" .. moved .. " px over 30 frames)",
    moved > 0 and math.abs(moved - 29 / 2) <= 1, table.concat({ seen[1], seen[#seen] }, " -> "))
end

do
  local overlay = io.open("render/hud_overlay.lua", "r"):read("a")
  local call = overlay:match("local settled_px = p_x_target.-H%.corridor%b()")
  check("corridor: hud_overlay feeds it the settled edge, not the mid-slide one",
    call ~= nil and call:find("rp_slide_target", 1, true) ~= nil
      and call:find("settled_px", 1, true) ~= nil, tostring(call))
  check("corridor: and the animating fraction is not what reaches it",
    call ~= nil and call:find("right_panel_slide_frac", 1, true) == nil)
end

do
  reset_corridor_state()
  local ctx = {}
  local _, max_w = H.corridor(ctx, 1920, "right", 100, 0, 0, DT, cn)
  check("corridor: squeezed window is widened to at least min_w",
    max_w >= 224, "max_w=" .. tostring(max_w))
  check("corridor: squeezed min_w is quantized to the configured 240, not some other floor",
    max_w == 240, "max_w=" .. tostring(max_w))
end

do
  reset_corridor_state()
  local ctx = {}
  local cx, max_w = H.corridor(ctx, 1920, "left", 100, 0, 0, DT, cn)
  local expect_lo, expect_hi = 108, 1900
  local expect_cx = math.floor((expect_lo + expect_hi) / 2 + 0.5)
  local expect_w = math.floor((expect_hi - expect_lo) / 16) * 16
  check("corridor: cx tracks the real lo/hi midpoint", math.abs(cx - expect_cx) <= 1,
    "cx=" .. cx .. " expect=" .. expect_cx)
  check("corridor: max_w tracks the real lo/hi span (not scaled)", max_w == expect_w,
    "max_w=" .. tostring(max_w) .. " expect=" .. expect_w)
end

done()
