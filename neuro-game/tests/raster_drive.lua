
local Cap = require("tests.raster_capture")
Cap.scenes()   -- forces raster_capture's lazy require of dev_scenario/hud_overlay

local Dev = require("hud.dev_scenario")
local HUD = require("render.hud_overlay")

local M = { Cap = Cap }

local function scene_index(id)
  for i, sc in ipairs(Dev.SCENES) do if sc.id == id then return i end end
  error("unknown scene '" .. tostring(id) .. "'")
end

function M.play(opts)
  Cap.SIZE.w = opts.size and opts.size.w or 1280
  Cap.SIZE.h = opts.size and opts.size.h or 720
  Dev.set(false)
  G.TIMERS.REAL = Cap.BASE_T
  Dev.set(true)
  Dev.select(scene_index(opts.scene))
  if opts.persona then Cap.set_axis("PERSONA", opts.persona) end
  if opts.speed then Cap.set_axis("SPEED", opts.speed) end

  local dt = 1 / (opts.fps or Cap.FPS)
  local from = opts.from or 0
  local out = {}
  local t = 0
  while t <= opts.span + 1e-9 do
    local keep = t >= from - 1e-9
    G.TIMERS.REAL = Cap.BASE_T + t
    Cap.rec.enabled = keep
    Cap.rec.reset()
    Cap.rec.enabled = keep
    local err
    local ok, e = xpcall(function()
      Dev.mount()
      if opts.on_frame then opts.on_frame(t) end
      HUD.draw_indicator()
    end, debug.traceback)
    if not ok then err = tostring(e) end
    local uok, uerr = pcall(Dev.unmount)
    if not uok then err = (err and (err .. "\n") or "") .. "unmount: " .. tostring(uerr) end
    Cap.rec.enabled = true
    if keep or err then
      out[#out + 1] = { t = t, ops = Cap.rec.take(), err = err }
    else
      Cap.rec.take()
    end
    t = t + dt
  end
  Dev.set(false)
  return out
end

function M.errors(frames)
  for _, fr in ipairs(frames) do
    if fr.err then return fr.err end
  end
  return nil
end

function M.pack_panel(frame)
  local best
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "R" and op.mode == "line" and op.w and op.w >= 260 and op.h and op.h > 25
      and op.x and op.y and op.y < 260 and (op.a or 0) >= 0.005 then
      if not best or op.a > best.a then best = op end
    end
  end
  return best
end

function M.pack_art(frame)
  local p = M.pack_panel(frame)
  if not p then return 0, 0 end
  local n, amax = 0, 0
  for _, line in ipairs(frame.ops) do
    local op = Cap.parse_op(line)
    if op and op.v == "I" and (op.a or 0) > 0.02 and op.x and op.y
      and op.x >= p.x - 40 and op.x <= p.x + p.w + 40 and op.y < p.y + p.h + 60 then
      n = n + 1
      if op.a > amax then amax = op.a end
    end
  end
  return n, amax
end

return M
