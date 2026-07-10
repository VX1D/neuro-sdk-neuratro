local Palette = require "render.palette"
local Utils = require "util.utils"
local Motion = require("render.neuro-anim").Motion
local Metrics = require "util.metrics"

local M = {}

local MODE_OFF, MODE_COMPACT, MODE_EXPANDED = 0, 1, 2
local PAGES = { "PERF", "ENGINE", "FORCE", "ACTIONS", "CTX/IPC" }
local NPAGES = #PAGES
local FRAME_CAP = 180
local sf = string.format

local PERF_LOG = require("core.config").bool("NEURO_PERF_LOG")
local PERF_LOG_CAP = 16 * 1024 * 1024  -- append-only jsonl grew ~2MB/h unbounded on long streams
local _perf_bytes = 0
local _perf_seeded = false

M._mode = MODE_OFF
M._on = false
M._page = 1
M._force_stall = 12
M._font = nil
M._font_small = nil
M._setup_done = false
M._rows = nil
M._rows_at = 0
M._show_at = 0
M._hide_at = nil
M._hide_mode = nil

M._frame = { hist = {}, cap = FRAME_CAP, i = 0, n = 0, last_ms = 0, avg_ms = 0, max_ms = 0, spike_ms = 33.4, spikes = 0 }
-- same table refs as util/metrics, not copies
M._timings = Metrics._timings
M._starts = Metrics._starts
M._counters = Metrics._counters
M._gauges = Metrics._gauges
M._slow = {
  interval = 0.25, next_at = 0,
  moveable = 0, sprite = 0, card = 0, uibox = 0, node = 0,
  lua_kb = 0, lua_kb_prev = false, gc_rate = 0,
  move_prev = false, move_rate = 0,
  ctr_prev = {}, rate = {},
}

local function wall()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local game_now = Utils.now   -- G.TIMERS.REAL -> love.timer -> os.clock (wall() stays separate: unpaused)

local function cur_fps()
  if love and love.timer and love.timer.getFPS then return love.timer.getFPS() end
  return 0
end

local function tlen(t)
  if type(t) ~= "table" then return 0 end
  local n = #t
  if n > 0 then return n end
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c
end

local function gn()
  return (G and G.NEURO) or nil
end

function M.enabled() return M._on end
function M.visible() return M._mode ~= MODE_OFF end

function M.set_mode(mode)
  local was = M._mode
  M._mode = mode
  M._on = M._mode ~= MODE_OFF
  Metrics.set_enabled(M._on)
  if was == MODE_OFF and M._on then
    M._rows = nil
    M._show_at = wall()
    M._hide_at = nil
  elseif was ~= MODE_OFF and not M._on then
    M._hide_at = wall()
    M._hide_mode = was
  else
    M._rows = nil
  end
end

function M.toggle()
  M.set_mode((M._mode + 1) % 3)
end

local MODE_BY_NAME = { off = MODE_OFF, compact = MODE_COMPACT, expanded = MODE_EXPANDED }

function M.set_mode_name(name)
  M.set_mode(MODE_BY_NAME[tostring(name):lower()] or MODE_OFF)
end

function M.cycle_page(dir)
  if M._mode ~= MODE_EXPANDED then return end
  M._page = ((M._page - 1 + (dir or 1)) % NPAGES) + 1
  M._rows = nil
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  local Tuning = require("core.tuning")
  M.set_mode_name(Tuning.get("NEURO_DEBUG_OVERLAY"))
  M._force_stall = Tuning.force_stall_seconds()
end

function M.sample(dt)
  if not M._on and not PERF_LOG then return end
  local fr = M._frame
  local ms = (dt or 0) * 1000
  fr.last_ms = ms
  fr.i = (fr.i % fr.cap) + 1
  fr.hist[fr.i] = ms
  if fr.n < fr.cap then fr.n = fr.n + 1 end

  local now = wall()
  local sl = M._slow
  if now < sl.next_at then return end
  local interval = sl.interval
  sl.next_at = now + interval

  local sum, mx, spikes = 0, 0, 0
  for k = 1, fr.n do
    local v = fr.hist[k]
    sum = sum + v
    if v > mx then mx = v end
    if v > fr.spike_ms then spikes = spikes + 1 end
  end
  fr.avg_ms = fr.n > 0 and (sum / fr.n) or 0
  fr.max_ms = mx
  fr.spikes = spikes

  local GI = G and G.I
  sl.moveable = tlen(GI and GI.MOVEABLE)
  sl.sprite = tlen(GI and GI.SPRITE)
  sl.card = tlen(GI and GI.CARD)
  sl.uibox = tlen(GI and GI.UIBOX)
  sl.node = tlen(GI and GI.NODE)
  sl.move_rate = sl.move_prev and ((sl.moveable - sl.move_prev) / interval) or 0
  sl.move_prev = sl.moveable

  local kb = collectgarbage("count")
  sl.lua_kb = kb
  sl.gc_rate = sl.lua_kb_prev and ((kb - sl.lua_kb_prev) / interval) or 0
  sl.lua_kb_prev = kb

  for name, val in pairs(M._counters) do
    local prev = sl.ctr_prev[name]
    sl.rate[name] = prev and ((val - prev) / interval) or 0
    sl.ctr_prev[name] = val
  end

  if PERF_LOG and love and love.filesystem then
    if not _perf_seeded then
      _perf_seeded = true
      local info = love.filesystem.getInfo and love.filesystem.getInfo("neuro_perf.jsonl")
      _perf_bytes = (info and info.size) or 0
    end
    if _perf_bytes < PERF_LOG_CAP then
      local line = sf(
        '{"t":%.1f,"fps":%d,"ms_avg":%.2f,"ms_max":%.2f,"moveable":%d,"move_rate":%.2f,"sprite":%d,"card":%d,"uibox":%d,"node":%d,"lua_kb":%.0f,"gc_rate":%.1f}\n',
        wall(), cur_fps(), fr.avg_ms or 0, fr.max_ms or 0, sl.moveable or 0, sl.move_rate or 0,
        sl.sprite or 0, sl.card or 0, sl.uibox or 0, sl.node or 0, sl.lua_kb or 0, sl.gc_rate or 0)
      _perf_bytes = _perf_bytes + #line
      if _perf_bytes >= PERF_LOG_CAP then
        line = line .. '{"perf_log":"cap reached, logging stopped"}\n'
      end
      pcall(love.filesystem.append, "neuro_perf.jsonl", line)
    end
  end
end

local function seg(t, c) return { t = t, c = c } end

local function color_for_dt(pal, ms)
  if ms <= 16.8 then return pal.D_GREEN end
  if ms <= 33.4 then return pal.D_ORANGE end
  return pal.D_RED
end

local function rate_col(pal, v)
  if v > 1 then return pal.D_RED end
  if v < -1 then return pal.D_SKYBLUE end
  return pal.D_GREEN
end

local function kv(rows, pal, label, value, vcol)
  rows[#rows + 1] = { seg(label, pal.D_DIM), seg(value, vcol or pal.D_WHITE) }
end

local function fonts()
  if not M._font then
    M._font, M._font_small = Utils.load_font_pair("resources/fonts/m6x11plus.ttf", 14, 12)
  end
  return M._font, M._font_small
end

local function force_row(pal, n)
  if not (n and n.force_inflight) then
    return { seg("force ", pal.D_DIM), seg("idle", pal.D_DIM) }
  end
  if not n.force_sent_at then
    return {
      seg("force ", pal.D_DIM), seg(tostring(n.force_state or "?"), pal.D_SKYBLUE),
      seg("  inflight, no sent_at", pal.D_RED),
    }
  end
  local rtt = game_now() - n.force_sent_at
  local to = M._force_stall - rtt
  return {
    seg("force ", pal.D_DIM), seg(tostring(n.force_state or "?"), pal.D_SKYBLUE),
    seg(sf("  rtt %.1fs", rtt), pal.D_ORANGE),
    seg(sf("  TO %.0fs", to), to < 5 and pal.D_RED or pal.D_DIM),
  }
end

local function compact_rows(pal)
  local n = gn()
  local fr = M._frame
  local sl = M._slow
  local rows = {}
  rows[#rows + 1] = { seg("NEURO DBG", pal.ACCENT), seg("  F9 cycle", pal.D_DIM) }
  rows[#rows + 1] = {
    seg("fps ", pal.D_DIM), seg(sf("%d", cur_fps()), pal.D_WHITE),
    seg("  dt ", pal.D_DIM), seg(sf("%.1f/%.1f/%.1f", fr.last_ms, fr.avg_ms, fr.max_ms), color_for_dt(pal, fr.avg_ms)),
  }
  rows[#rows + 1] = {
    seg("heap ", pal.D_DIM), seg(sf("%dk", math.floor(sl.lua_kb)), pal.D_WHITE),
    seg(sf(" (%+.0f/s)", sl.gc_rate), rate_col(pal, sl.gc_rate)),
    seg("  move ", pal.D_DIM), seg(sf("%d", sl.moveable), pal.D_WHITE),
    seg(sf(" (%+.0f/s)", sl.move_rate), rate_col(pal, sl.move_rate)),
  }
  rows[#rows + 1] = {
    seg("state ", pal.D_DIM), seg(n and tostring(n.state or "?") or "?", pal.D_SKYBLUE),
    seg("  ph ", pal.D_DIM), seg(n and tostring(n.action_phase or "-") or "-", pal.D_WHITE),
  }
  rows[#rows + 1] = force_row(pal, n)
  return rows
end

local function page_perf(rows, pal)
  local fr = M._frame
  local sl = M._slow
  kv(rows, pal, "fps        ", sf("%d", cur_fps()))
  kv(rows, pal, "dt cur     ", sf("%.2f ms", fr.last_ms), color_for_dt(pal, fr.last_ms))
  kv(rows, pal, "dt avg     ", sf("%.2f ms", fr.avg_ms), color_for_dt(pal, fr.avg_ms))
  kv(rows, pal, "dt max     ", sf("%.2f ms", fr.max_ms), color_for_dt(pal, fr.max_ms))
  kv(rows, pal, "spikes     ", sf("%d (>%.0fms)", fr.spikes, fr.spike_ms), fr.spikes > 0 and pal.D_ORANGE or pal.D_GREEN)
  kv(rows, pal, "lua heap   ", sf("%d KB", math.floor(sl.lua_kb)))
  kv(rows, pal, "heap rate  ", sf("%+.0f KB/s", sl.gc_rate), rate_col(pal, sl.gc_rate))
end

local function page_engine(rows, pal)
  local sl = M._slow
  local arrow = sl.move_rate > 0.5 and " ^" or (sl.move_rate < -0.5 and " v" or " =")
  kv(rows, pal, "MOVEABLE   ", sf("%d%s", sl.moveable, arrow), rate_col(pal, sl.move_rate))
  kv(rows, pal, "  rate     ", sf("%+.1f /s", sl.move_rate), rate_col(pal, sl.move_rate))
  kv(rows, pal, "SPRITE     ", sf("%d", sl.sprite))
  kv(rows, pal, "CARD       ", sf("%d", sl.card))
  kv(rows, pal, "UIBOX      ", sf("%d", sl.uibox))
  kv(rows, pal, "NODE       ", sf("%d", sl.node))
  kv(rows, pal, "lua heap   ", sf("%d KB", math.floor(sl.lua_kb)), rate_col(pal, sl.gc_rate))
end

local function page_force(rows, pal)
  local n = gn()
  if not n then kv(rows, pal, "state      ", "n/a") return end
  kv(rows, pal, "state      ", tostring(n.state or "?"), pal.D_SKYBLUE)
  kv(rows, pal, "serial     ", sf("%d", n.state_enter_serial or 0))
  if n.force_inflight then
    kv(rows, pal, "force      ", tostring(n.force_state or "?"), pal.D_SKYBLUE)
    kv(rows, pal, "  inflight ", "yes", pal.D_ORANGE)
    if n.force_sent_at then
      local rtt = game_now() - n.force_sent_at
      kv(rows, pal, "  rtt      ", sf("%.2f s", rtt), pal.D_ORANGE)
      local to = M._force_stall - rtt
      kv(rows, pal, "  stall    ", sf("%.0f s", to), to < 5 and pal.D_RED or pal.D_WHITE)
    else
      kv(rows, pal, "  sent_at  ", "missing", pal.D_RED)
    end
  else
    kv(rows, pal, "force      ", "idle", pal.D_DIM)
  end
  if n.force_dirty and n.force_dirty_at then
    kv(rows, pal, "  debounce ", sf("%.2f s", game_now() - n.force_dirty_at), pal.D_DIM)
  end
  kv(rows, pal, "reforce    ", sf("%d", n.reforce_count or 0))
end

local function page_actions(rows, pal)
  local n = gn()
  local te = M._timings.action_exec
  kv(rows, pal, "phase      ", n and tostring(n.action_phase or "-") or "-", pal.D_SKYBLUE)
  if n and n.action_phase_at then
    kv(rows, pal, "  age      ", sf("%.2f s", game_now() - n.action_phase_at))
  end
  kv(rows, pal, "last       ", n and tostring(n.last_action_name or "-") or "-")
  local failed = n and n.last_failed_action
  kv(rows, pal, "failed     ", failed and tostring(failed) or "-", failed and pal.D_MAROON or pal.D_DIM)
  local ok_c = M._counters.action_ok or 0
  local fail_c = M._counters.action_fail or 0
  kv(rows, pal, "ok / fail  ", sf("%d / %d", ok_c, fail_c), fail_c > 0 and pal.D_ORANGE or pal.D_GREEN)
  if te then
    kv(rows, pal, "exec ms    ", sf("%.1f / %.1f / %.1f", te.last, te.ema, te.max), pal.D_ORANGE)
  end
  kv(rows, pal, "throttle r ", sf("%d", M._gauges.throttle_repeat or 0))
  kv(rows, pal, "cooldown   ", sf("%.1f s", M._gauges.throttle_cooldown or 0))
  if n and n.recent_actions then
    local t = n.recent_actions
    local tail = {}
    for i = math.max(1, #t - 3), #t do tail[#tail + 1] = tostring(t[i]) end
    if #tail > 0 then kv(rows, pal, "recent     ", table.concat(tail, ",")) end
  end
end

local function page_ctxipc(rows, pal)
  local tb = M._timings.ctx_build
  local rate = M._slow.rate
  local hit = M._counters.ctx_cache_hit or 0
  local miss = M._counters.ctx_cache_miss or 0
  local total = hit + miss
  if tb then kv(rows, pal, "ctx ms     ", sf("%.1f / %.1f / %.1f", tb.last, tb.ema, tb.max), pal.D_ORANGE) end
  kv(rows, pal, "builds/s   ", sf("%.1f", rate.ctx_build_calls or 0))
  kv(rows, pal, "hit/miss   ", sf("%d / %d", hit, miss))
  kv(rows, pal, "hit ratio  ", total > 0 and sf("%.0f%%", hit / total * 100) or "-", pal.D_GREEN)
  kv(rows, pal, "ipc send/s ", sf("%.1f", rate.ipc_send or 0))
  kv(rows, pal, "state wr/s ", sf("%.1f", rate.ipc_state_write or 0))
  kv(rows, pal, "inbox msgs ", sf("%d", M._counters.ipc_inbox_msg or 0))
  kv(rows, pal, "ipc seq    ", sf("%d", M._gauges.ipc_seq or 0))
end

local function expanded_rows(pal)
  local rows = {}
  rows[#rows + 1] = { seg(sf("NEURO DBG  %d/%d %s", M._page, NPAGES, PAGES[M._page]), pal.ACCENT), seg("  F9/F10", pal.D_DIM) }
  local p = M._page
  if p == 1 then page_perf(rows, pal)
  elseif p == 2 then page_engine(rows, pal)
  elseif p == 3 then page_force(rows, pal)
  elseif p == 4 then page_actions(rows, pal)
  else page_ctxipc(rows, pal) end
  return rows
end

function M.draw()
  if not (love and love.graphics) then return end
  local now = wall()
  local fade_d = Motion.dur(Motion.FAST)
  local eff_mode = M._mode
  local ga
  if M.visible() then
    ga = Motion.anim01(now - (M._show_at or 0), fade_d)
  else
    if not (M._hide_at and M._rows and (now - M._hide_at) < fade_d) then return end
    ga = 1 - Motion.anim01(now - M._hide_at, fade_d)
    eff_mode = M._hide_mode or MODE_COMPACT
  end
  local pal = Palette.pal()
  local font, small = fonts()
  local use_font = (eff_mode == MODE_EXPANDED) and small or font
  if M.visible() and (not M._rows or now >= (M._rows_at or 0)) then
    M._rows = (eff_mode == MODE_COMPACT) and compact_rows(pal) or expanded_rows(pal)
    M._rows_at = now + 0.1
  end
  local rows = M._rows
  if not rows then return end

  local prev_font = love.graphics.getFont()
  love.graphics.setFont(use_font)
  local lh = use_font:getHeight() + 2
  local pad = 8
  local w = 308
  local h = pad * 2 + #rows * lh
  local x, y = 8, 8

  local bgc = pal.PANEL_BG or pal.BG
  local frc = pal.FRAME or pal.PRIMARY
  local acc = pal.ACCENT
  love.graphics.setColor(0, 0, 0, 0.55 * ga)
  love.graphics.rectangle("fill", x + 2, y + 2, w, h)
  love.graphics.setColor(bgc[1], bgc[2], bgc[3], 0.90 * ga)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(frc[1], frc[2], frc[3], 0.90 * ga)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setColor(acc[1], acc[2], acc[3], 0.85 * ga)
  love.graphics.rectangle("fill", x, y + pad + lh - 3, w, 2)

  local ty = y + pad
  for i = 1, #rows do
    local segs = rows[i]
    local tx = x + pad
    for j = 1, #segs do
      local s = segs[j]
      local c = s.c or pal.D_WHITE
      love.graphics.setColor(0, 0, 0, 0.35 * ga)
      love.graphics.print(s.t, tx + 1, ty + 1)
      love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * ga)
      love.graphics.print(s.t, tx, ty)
      tx = tx + use_font:getWidth(s.t)
    end
    ty = ty + lh
  end

  love.graphics.setColor(1, 1, 1, 1)
  if prev_font then love.graphics.setFont(prev_font) end
end

return M
