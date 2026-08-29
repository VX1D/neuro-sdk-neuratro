local Tuning = require("core.config")
local Palette = require("render.palette")
local S = require("hud.state")
local DebugStats = require("render.debug_stats")
local SelfTest = require("core.selftest")
local Motion = require("render.neuro-anim").Motion
local Prims = require("hud.prims")
local set_col = Prims.set_col
local round = Prims.round
local clamp = Prims.clamp
local invalidate_force = require("force.force_helpers").invalidate

local Panel = {}





local SCALE = 1
local SCALE_MAX = 1.0
local SCALE_REF_W, SCALE_REF_H = 1280, 720

local function u(v)
  if v == 0 then return 0 end
  local r = round(v * SCALE)
  return r < 1 and 1 or r
end

local LAYOUT_COUNT = {
  MAX_COLS = true, MAX_COLS_COLOUR = true, MAX_COLS_FIT = true,
}

local LAYOUT_BASE = {
  PANEL_W = 940,
  PANEL_H = 560,
  MARGIN_X = 24,
  MARGIN_Y = 20,
  OPEN_SLIDE = 6,
  RADIUS = 0,
  PAD = 16,
  HEADER_H = 48,
  TABS_H = 46,
  DESC_H = 98,
  FOOTER_H = 34,
  ROW_H = 27,
  ROW_R = 0,
  SEG_H = 30,
  COL_GAP = 28,
  CELL_PAD = 14,
  TOGGLE_W = 36,
  TOGGLE_H = 20,
  SLIDER_W = 104,
  VALUE_W = 74,
  STEP_W = 18,
  SWATCH = 20,
  SWATCH_GAP = 6,
  HEX_GAP = 3,
  CHIP_H = 24,
  TRACK = 1.0,
  MAX_COLS = 2,
  MAX_COLS_COLOUR = 3,
  MAX_COLS_FIT = 3,
  BASICS_INTRO_H = 22,
  BASICS_INTRO_GAP = 14,
  BASICS_ROW_H = 30,
  RAIL_W = 210,
  RAIL_GAP = 28,
  PLACEMENT_H = 154,
  PLACEMENT_GAP = 12,
  PLACE_PAD = 10,
  PLACE_HEAD_H = 22,
  PLACE_WELL_GAP = 20,
  PLACE_WELL_MIN = 120,
  PLACE_WELL_MAX = 320,
  PLACE_COL_GAP = 24,
  PLACE_COL_MIN = 264,
  PLACE_RAIL_GUT = 8,
  PLACE_CAP_H = 16,
  PLACE_ROW_H = 26,
  PLACE_LABEL_W = 92,
  PLACE_STEP_W = 20,
  PLACE_VALUE_W = 52,
  PLACE_TRACK_MIN = 24,
  PLACE_NODE_W = 24,
  PLACE_NODE_H = 16,
  PLACE_BTN_H = 22,}

local LAYOUT = {}

local function resolve_layout()
  for k, v in pairs(LAYOUT_BASE) do
    LAYOUT[k] = LAYOUT_COUNT[k] and v or u(v)
  end
  LAYOUT.TRACK = LAYOUT_BASE.TRACK * SCALE
end

resolve_layout()



local STYLE = {
  scrim       = { 0.000, 0.000, 0.000 },
  panel       = { 0.063, 0.063, 0.067 },
  header      = { 0.078, 0.078, 0.086 },
  surface     = { 0.090, 0.090, 0.102 },
  surface_alt = { 0.118, 0.118, 0.133 },
  selected    = { 0.102, 0.098, 0.133 },
  border      = { 0.149, 0.149, 0.169 },
  accent      = { 0.557, 0.525, 0.769 },
  accent_dim  = { 0.227, 0.212, 0.322 },
  off         = { 0.227, 0.227, 0.259 },
  text        = { 0.949, 0.949, 0.953 },
  muted       = { 0.604, 0.604, 0.635 },
  faint       = { 0.384, 0.384, 0.416 },
}

local ACCENT_FALLBACK = { 0.557, 0.525, 0.769 }
local ACCENT_MIN_CONTRAST = 4.5

local function srgb_channel(v)
  if v <= 0.04045 then return v / 12.92 end
  return ((v + 0.055) / 1.055) ^ 2.4
end

local function rel_luminance(r, g, b)
  return 0.2126 * srgb_channel(r) + 0.7152 * srgb_channel(g) + 0.0722 * srgb_channel(b)
end

local function contrast_on_panel(r, g, b)
  local la = rel_luminance(r, g, b)
  local lb = rel_luminance(STYLE.panel[1], STYLE.panel[2], STYLE.panel[3])
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

local function resolve_accent()
  local src = Palette.pal().ACCENT or ACCENT_FALLBACK
  local r, g, b = src[1], src[2], src[3]
  for _ = 1, 24 do
    if contrast_on_panel(r, g, b) >= ACCENT_MIN_CONTRAST then break end
    r, g, b = r + (1 - r) / 12, g + (1 - g) / 12, b + (1 - b) / 12
  end
  local acc, dim, sel_bg, srf = STYLE.accent, STYLE.accent_dim, STYLE.selected, STYLE.surface
  acc[1], acc[2], acc[3] = r, g, b
  dim[1], dim[2], dim[3] = r * 0.42, g * 0.42, b * 0.42
  sel_bg[1] = srf[1] + (r - srf[1]) * 0.05
  sel_bg[2] = srf[2] + (g - srf[2]) * 0.05
  sel_bg[3] = srf[3] + (b - srf[3]) * 0.05
end





local FONT_PX_BASE = { title = 19, label = 15, tab = 14, desc = 15, section = 13, micro = 12 }
local FONT_PX = {}
local _font_cache = {}
local FONT_PX_MIN = 8

local function resolve_fonts()
  for role, px in pairs(FONT_PX_BASE) do
    FONT_PX[role] = math.max(FONT_PX_MIN, round(px * SCALE))
  end
end

resolve_fonts()

local function font(role)
  local px = FONT_PX[role] or FONT_PX.label
  local f = _font_cache[px]
  if f then return f end
  if love and love.graphics and love.graphics.newFont then
    local ok, nf = pcall(love.graphics.newFont, px)
    if ok and nf then
      _font_cache[px] = nf
      return nf
    end
  end
  f = S.panel_font or (love and love.graphics and love.graphics.getFont and love.graphics.getFont())
  _font_cache[px] = f
  return f
end




local ACRONYMS = {
  AI = true, CD = true, CTX = true, FPS = true, HUD = true, ID = true,
  IPC = true, LLM = true, SDK = true, SMODS = true, TTL = true, UI = true,
}

local _label_cache = {}
local function nice_label(s)
  s = tostring(s or "")
  local hit = _label_cache[s]
  if hit then return hit end
  local lead = true
  local out = s:gsub("%a[%w']*", function(word)
    if ACRONYMS[word:upper()] then
      lead = false
      return word:upper()
    end
    local low = word:lower()
    if lead then
      lead = false
      return low:sub(1, 1):upper() .. low:sub(2)
    end
    return low
  end)
  _label_cache[s] = out
  return out
end


local function nice_value(s)
  s = tostring(s or "")
  if s:find("%d") then return s:lower() end
  return nice_label(s)
end


local open = false
local page = 1
local sel = 1
local rows = nil
local rows_dirty = true
local crows = nil
local crows_dirty = true
local crows_persona = nil
local edit_mode = false
local edit_ch = 1
local edit_hex = ""
local flash_text = nil
local flash_at = 0
local open_at = 0
local close_at = 0
local vflash_at = 0
local vflash_row = 0
local st_done = nil
local st_was_running = false
local mouse_seen = false
local placement_drag = nil
local hover_id = nil
local hover_at = 0

-- Reloading this chunk would replace the exported functions with closures over a new
-- `open=false` while leaving the operator pause in G.NEURO. Defer the edit until close.
Panel._hot_reload_locked = function() return open end

local function hover_t(id, hovered, now)
  if not hovered then
    if hover_id == id then hover_id = nil end
    return 0
  end
  if hover_id ~= id then hover_id, hover_at = id, now end
  return Motion.anim01(now - hover_at, Motion.FAST)
end

local SAVED_HOLD = Motion.SLOW * 2

local HIT = {
  valid = false,
  px = 0, py = 0, pw = 0, ph = 0,
  cx = 0, cy = 0, cw = 0, ch = 0,
  n = 0,
  rows = {}, row_x = {}, row_w = {}, itemh = {}, vis = {},
  dec_x = {}, inc_x = {}, ctl_x = {}, ctl_w = {},
  step_w = 0,
  hex_x = {}, hexw = 0, hgap = 3,
  tab_y = 0, tab_h = 0, tab_x = {}, tab_w = {},
  cl_x = 0, cl_y = 0, cl_w = 0, cl_h = 0,
  pr_x = 0, pr_y = 0, pr_w = 0, pr_h = 0,
  sw_n = 0, sw_rects = {},
  ra_x = 0, ra_y = 0, ra_w = 0, ra_h = 0,
  cols = 1, rows_per = 1, col_w = 0, capacity = 0,
  place_x = 0, place_y = 0, place_w = 0, place_h = 0,
  place_anchors = {}, place_tabs = {},
  place_slider_x = {}, place_slider_y = {}, place_slider_w = {}, place_slider_h = {},
  place_dec = {}, place_inc = {},
  place_reset = nil,
}

local PERSONA_ORDER = { "evil", "neuro", "hiyori" }
local place_target = "main"
local PLACE_KEY = {
  [-5] = "NEURO_OVERLAY_SCALE_RIGHT",
  [-4] = "NEURO_OVERLAY_SCALE_LEFT",
  [-7] = "NEURO_CENTER_SCALE",
  [-3] = { main = "NEURO_OVERLAY_ANCHOR", shop = "NEURO_SHOP_ANCHOR" },
  [-2] = { main = "NEURO_OVERLAY_OFFSET_X", shop = "NEURO_SHOP_OFFSET_X" },
  [-1] = { main = "NEURO_OVERLAY_OFFSET_Y", shop = "NEURO_SHOP_OFFSET_Y" },
}
local PLACE_SEL, POSITION_KEYS, PLACE_TARGET_OF = {}, {}, {}
for s, k in pairs(PLACE_KEY) do
  if type(k) == "table" then
    for t, key in pairs(k) do
      PLACE_SEL[key] = s
      POSITION_KEYS[key] = true
      PLACE_TARGET_OF[key] = t
    end
  else
    PLACE_SEL[k] = s
    POSITION_KEYS[k] = true
  end
end

local function place_key(s)
  local k = PLACE_KEY[s]
  if type(k) == "table" then return k[place_target] end
  return k
end

local PLACE_ORDER = { -6, -3, -2, -1, -5, -4, -7, 0 }
local PLACE_AT = {}
for i, v in ipairs(PLACE_ORDER) do PLACE_AT[v] = i end
local PLACE_FIRST, PLACE_LAST = PLACE_ORDER[1], PLACE_ORDER[#PLACE_ORDER]

local function fmt_pct(v) return string.format("%+d%%", round(v)) end
local function fmt_scale(v) return string.format("%.2fx", v) end

local PLACE_SLIDERS = {
  { key = { main = "NEURO_OVERLAY_OFFSET_X", shop = "NEURO_SHOP_OFFSET_X" },
    sel = -2, label = "X OFFSET", fmt = fmt_pct },
  { key = { main = "NEURO_OVERLAY_OFFSET_Y", shop = "NEURO_SHOP_OFFSET_Y" },
    sel = -1, label = "Y OFFSET", fmt = fmt_pct },
  { key = "NEURO_OVERLAY_SCALE_RIGHT", sel = -5, label = "MAIN HUD", fmt = fmt_scale },
  { key = "NEURO_OVERLAY_SCALE_LEFT", sel = -4, label = "SHOP HUD", fmt = fmt_scale },
  { key = "NEURO_CENTER_SCALE", sel = -7, label = "ACQUIRE HUD", fmt = fmt_scale },
}

local function slider_key(s)
  if type(s.key) == "table" then return s.key[place_target] end
  return s.key
end

local DEF_BY_KEY = {}
for _, d in ipairs(Tuning.entries()) do DEF_BY_KEY[d.key] = d end

local PLACE_SLOT = {}
for i, s in ipairs(PLACE_SLIDERS) do
  local d = DEF_BY_KEY[type(s.key) == "table" and s.key.main or s.key]
  s.min, s.max = d.min, d.max
  s.step, s.default = d.step, d.default
  PLACE_SLOT[s.sel] = i
end

local ANCHORS = {
  "auto", "top-left", "top-right", "middle-left",
  "middle-right", "bottom-left", "bottom-right",
}
local ANCHOR_NAMES = {
  ["top-left"] = "TOP LEFT", ["top-right"] = "TOP RIGHT",
  ["middle-left"] = "MIDDLE LEFT", ["middle-right"] = "MIDDLE RIGHT",
  ["bottom-left"] = "BOTTOM LEFT", ["bottom-right"] = "BOTTOM RIGHT",
}
local ANCHOR_LABELS = {
  ["top-left"] = "TL", ["top-right"] = "TR",
  ["middle-left"] = "ML", ["middle-right"] = "MR",
  ["bottom-left"] = "BL", ["bottom-right"] = "BR",
}

local SWATCHES = {
  "FFFFFF", "C8C8C8", "808080", "202028", "000000",
  "FF4D94", "E5202B", "F97316", "FFD700", "3CB371",
  "00E5FF", "5AA0FF", "9B72E6", "B87333",
}

local SWATCH_RGB = {}
for i = 1, #SWATCHES do
  local hx = SWATCHES[i]
  SWATCH_RGB[i] = {
    tonumber(hx:sub(1, 2), 16) / 255,
    tonumber(hx:sub(3, 4), 16) / 255,
    tonumber(hx:sub(5, 6), 16) / 255,
  }
end

local BASIC_LAYOUT = {
  { "NEURO_AUTO_TUNE", "PACING" },
  { "NEURO_CD_PRESET", "PACING" },
}
local BASIC_DEFS, BASIC_GROUPS = {}, {}
for _, item in ipairs(BASIC_LAYOUT) do
  local d = DEF_BY_KEY[item[1]]
  if d then
    BASIC_DEFS[#BASIC_DEFS + 1] = d
    BASIC_GROUPS[d.key] = item[2]
  end
end

local TIMING_GROUPS = {
  MASTER = true,
  THROTTLES = true,
  ["POST-ACTION"] = true,
  CADENCE = true,
}
local ADVANCED_DEFS, TIMING_DEFS = {}, {}
for _, d in ipairs(Tuning.entries()) do
  if not POSITION_KEYS[d.key] then
    local target = TIMING_GROUPS[d.group] and TIMING_DEFS or ADVANCED_DEFS
    target[#target + 1] = d
  end
end

local function active_defs()
  if page == 1 then return BASIC_DEFS end
  if page == 2 then return ADVANCED_DEFS end
  if page == 3 then return TIMING_DEFS end
  if page == 4 then return {} end
  return Tuning.runtime_entries()
end

local function row_group(d)
  return (page == 1 and BASIC_GROUPS[d.key]) or d.group or ""
end




local function rail_page()
  return page == 2 or page == 3
end

local collapsed = {}
local function default_open_group(g)
  local defs = active_defs()
  for i = 1, #defs do
    local first = row_group(defs[i])
    if first then return g == first end
  end
  return false
end

local function group_collapsed(g)
  if page == 1 or page == 5 then return false end
  local v = collapsed[g]
  if v == nil then return not default_open_group(g) end
  return v
end

local function collapse_all()
  local defs = active_defs()
  for i = 1, #defs do
    local g = row_group(defs[i])
    if g then collapsed[g] = true end
  end
end



local function set_group_open(g)
  local defs = active_defs()
  for i = 1, #defs do
    local gg = row_group(defs[i])
    if gg then collapsed[gg] = (gg ~= g) end
  end
end

local function fmt_value(d, v)
  if d.readonly then
    local rv = os.getenv(d.key)
    return (rv and rv ~= "" and tostring(rv)) or "(unset)", nil
  end
  if d.values then return tostring(v):upper(), nil end
  if d.kind == "string" then
    local s = tostring(v or "")
    return (s ~= "" and s) or "(none)", nil
  end
  local s
  v = tonumber(v) or 0
  if v == math.floor(v) then
    s = string.format("%d", v)
  else
    s = string.format("%.4g", v)
  end
  return s, d.unit
end

local function apply_live(d)
  if d.key == "NEURO_DEBUG_OVERLAY" then
    DebugStats.set_mode_name(Tuning.get(d.key))
  elseif d.key == "NEURO_PERSONA" then
    if G and G.NEURO then G.NEURO.persona = Tuning.get_raw(d.key) end
  end
end

local function rebuild_rows()
  local defs = active_defs()
  rows = {}
  local counts = {}
  for i = 1, #defs do
    local g = row_group(defs[i])
    counts[g] = (counts[g] or 0) + 1
  end
  local prev_group = nil
  for i = 1, #defs do
    local d = defs[i]
    local g = row_group(d)
    if g ~= prev_group then
      rows[#rows + 1] = { kind = "header", group = g, count = counts[g], collapsed = group_collapsed(g) }
      prev_group = g
    end
    if not group_collapsed(g) then
      local v, unit = fmt_value(d, Tuning.get_raw(d.key))
      rows[#rows + 1] = {
        kind = "row",
        di = i,
        d = d,
        label = d.parent and ("  " .. d.label) or d.label,
        value = v,
        unit = unit,
        def = d.readonly and "" or (fmt_value(d, d.default) .. (d.unit or "")),
      }
    end
  end
  if page == 1 then
    rows[#rows + 1] = { kind = "action", action = "advanced", label = "OPEN ADVANCED SETTINGS" }
  elseif page == 2 then
    rows[#rows + 1] = { kind = "action", action = "selftest", label = "RUN SELF-TEST" }
  elseif page == 5 then
    rows[#rows + 1] = { kind = "action", action = "runtime_reset", label = "RESET ALL SYSTEM SETTINGS" }
  end
  rows_dirty = false
end

local function reveal(key)
  if POSITION_KEYS[key] then
    page, rows_dirty = 1, true
    place_target = PLACE_TARGET_OF[key] or place_target
    sel = PLACE_SEL[key] or -3
    return true
  end
  local defs, target_page
  if BASIC_GROUPS[key] then
    defs, target_page = BASIC_DEFS, 1
  else
    for _, d in ipairs(ADVANCED_DEFS) do
      if d.key == key then defs, target_page = ADVANCED_DEFS, 2; break end
    end
    if not defs then
      for _, d in ipairs(TIMING_DEFS) do
        if d.key == key then defs, target_page = TIMING_DEFS, 3; break end
      end
    end
    if not defs then
      for _, d in ipairs(Tuning.runtime_entries()) do
        if d.key == key then defs, target_page = Tuning.runtime_entries(), 5; break end
      end
    end
  end
  if not defs then return false end
  page, sel, rows_dirty = target_page, 1, true
  for i = 1, #defs do
    if defs[i].key == key then
      set_group_open(row_group(defs[i]))
      rebuild_rows()
      for vi = 1, #rows do
        local it = rows[vi]
        if it.kind == "row" and it.di == i then sel = vi; return true end
      end
    end
  end
  return false
end

local drop_last_codepoint = require("util.utils").drop_last_codepoint

local function hex2(v)
  return string.format("%02X", round(v * 255))
end

local function rebuild_crows()
  local pk = Palette.persona()
  crows_persona = pk
  local ckeys = Palette.color_keys(pk)
  crows = {}
  for i = 1, #ckeys do
    local k = ckeys[i]
    local c = Palette.get_color(pk, k)
    local d = Palette.default_color(pk, k)
    crows[i] = {
      key = k,
      color = c,
      hr = hex2(c[1]), hg = hex2(c[2]), hb = hex2(c[3]),
      def = "[" .. hex2(d[1]) .. hex2(d[2]) .. hex2(d[3]) .. "]",
    }
  end
  crows_dirty = false
end

function Panel.is_open()
  return open
end

local now_s = require("util.utils").now

local function save_changes(now)
  local ok, err = Tuning.save()
  flash_text = ok and "SAVED" or "SAVE FAILED"
  flash_at = now or now_s()
  if not ok then
    print("[neuro-game] config save failed: " .. tostring(err))
  end
  return ok
end

function Panel.toggle()
  local now = now_s()
  if open then
    if not save_changes(now) then return true end
    open = false
    close_at = now
    edit_mode = false
    HIT.valid = false
    placement_drag = nil
    if G and G.NEURO then
      G.NEURO.llm_paused = nil
      invalidate_force("superseded")
    end
  else
    open = true
    if G and G.NEURO then G.NEURO.llm_paused = true end
    page = 1
    sel = -3
    place_target = "main"
    edit_mode = false
    rows_dirty = true
    crows_dirty = true
    flash_text = nil
    vflash_at = 0
    open_at = now
  end
  return open
end

local function shift_down()
  local kb = love and love.keyboard
  return kb and kb.isDown and (kb.isDown("lshift") or kb.isDown("rshift")) or false
end

local function mouse_pos()
  local m = love and love.mouse
  if m and m.getPosition then return m.getPosition() end
  return -1, -1
end

local function in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

local function placement_anchor_at(x, y)
  for i = 1, #HIT.place_anchors do
    local r = HIT.place_anchors[i]
    if r and in_rect(x, y, r.x, r.y, r.w, r.h) then return r.value end
  end
  return nil
end

local function placement_slider_at(x, y)
  for i = 1, #PLACE_SLIDERS do
    if HIT.place_slider_x[i]
      and in_rect(x, y, HIT.place_slider_x[i], HIT.place_slider_y[i],
        HIT.place_slider_w[i], HIT.place_slider_h[i])
    then
      return i
    end
  end
  return nil
end

local function set_position_value(key, value, now)
  local applied = Tuning.set(key, value)
  if applied == nil then return false end
  vflash_at = now
  vflash_row = PLACE_SEL[key] or 0
  rows_dirty = true
  return true
end

local function quantize(value, step)
  local snapped = round(value / step) * step
  return round(snapped * 1e6) / 1e6
end

local function reset_position(now)
  for _, key in pairs(PLACE_KEY) do
    if type(key) == "table" then
      Tuning.reset(key.main)
      Tuning.reset(key.shop)
    else
      Tuning.reset(key)
    end
  end
  place_target = "main"
  vflash_at, vflash_row = now, 0
  rows_dirty = true
end

local function set_place_target(t, now)
  if t ~= "main" and t ~= "shop" then return end
  if place_target ~= t then
    place_target = t
    vflash_at = now
  end
  vflash_row = -6
end

local function reset_place_key(which, now)
  local key = place_key(which)
  if not key then return false end
  Tuning.reset(key)
  vflash_at, vflash_row = now, which
  rows_dirty = true
  return true
end

local function adjust_position(which, dir, mult, now)
  if which == -6 then
    set_place_target(dir > 0 and "shop" or "main", now)
    return
  end
  if which == -3 then
    local akey = place_key(-3)
    local current = Tuning.get_raw(akey)
    local idx = 1
    for i = 1, #ANCHORS do if ANCHORS[i] == current then idx = i break end end
    idx = ((idx - 1 + (dir > 0 and 1 or -1)) % #ANCHORS) + 1
    set_position_value(akey, ANCHORS[idx], now)
    return
  end
  local s = PLACE_SLIDERS[PLACE_SLOT[which] or 0]
  if not s then return end
  local key = slider_key(s)
  local current = tonumber(Tuning.get_raw(key)) or s.default
  local value = current + s.step * dir * (mult or 1)
  set_position_value(key, quantize(value, s.step), now)
end

local function set_slider_from_x(index, x, now)
  local s = PLACE_SLIDERS[index]
  local sx, sw = HIT.place_slider_x[index], HIT.place_slider_w[index]
  if not s or not sx or not sw or sw <= 0 then return false end
  local frac = (x - sx) / sw
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local steps = round(frac * (s.max - s.min) / s.step)
  return set_position_value(slider_key(s), quantize(s.min + steps * s.step, s.step), now)
end
local function row_at(x, y)
  if not HIT.valid then return nil end
  for i = 1, HIT.n do
    if HIT.vis[i] then
      local rx, ry, rw = HIT.row_x[i], HIT.rows[i], HIT.row_w[i]
      local rh = HIT.itemh[i] or LAYOUT.ROW_H
      if rx and ry and in_rect(x, y, rx, ry, rw, rh) then return i end
    end
  end
  return nil
end

local function hex_channel_at(x, i)
  local hx = HIT.hex_x[i]
  if not hx then return nil end
  for ch = 1, 3 do
    local sx = hx + (ch - 1) * (HIT.hexw + HIT.hgap)
    if x >= sx and x < sx + HIT.hexw + HIT.hgap then return ch end
  end
  return nil
end

local function swatch_at(x, y)
  for i = 1, HIT.sw_n do
    local r = HIT.sw_rects[i]
    if r and in_rect(x, y, r[1], r[2], r[3], r[4]) then return i end
  end
  return nil
end

local function bool_def(d)
  if not d.values or #d.values ~= 2 then return false end
  local a = tostring(d.values[1]):lower()
  local b = tostring(d.values[2]):lower()
  return (a == "on" and b == "off") or (a == "off" and b == "on")
end

local function checkbox_on(v)
  return v == true or tostring(v):lower() == "on"
end

local function parent_off(d)
  if not (d and d.parent) then return false end
  local raw = Tuning.get_raw(d.parent)
  if raw == nil then return false end
  return not checkbox_on(raw)
end

local function static_value(d)
  return d.readonly or d.panel == false or d.kind == "string" or parent_off(d)
end

local function page1_adjust(i, dir, mult, now)
  local d = active_defs()[i]
  if not d or d.readonly or d.panel == false or parent_off(d) then return end
  if d.values then
    local cur, idx = Tuning.get_raw(d.key), 1
    for k = 1, #d.values do
      if d.values[k] == cur then idx = k break end
    end
    idx = idx + (dir > 0 and 1 or -1)
    if idx < 1 then idx = #d.values elseif idx > #d.values then idx = 1 end
    Tuning.set(d.key, d.values[idx])
    apply_live(d)
  else
    local nv = Tuning.get_raw(d.key) + d.step * dir * (mult or 1)
    nv = round(nv * 1e6) / 1e6
    Tuning.set(d.key, nv)
  end
  vflash_at = now
  vflash_row = i
  rows_dirty = true
end

local function trigger_selftest(now)
  if not SelfTest.available() then
    if G and G.STAGE == (G.STAGES and G.STAGES.RUN) and G.FUNCS and G.FUNCS.go_to_menu then
      pcall(G.FUNCS.go_to_menu)
    else
      flash_text = "SELF-TEST REQUIRES MAIN MENU"
      flash_at = now
      return
    end
  end
  st_done = nil
  local ok, err = SelfTest.start()
  if not ok then
    flash_text = tostring(err or "SELF-TEST FAILED TO START")
    flash_at = now
  else
    flash_text = "SELF-TEST STARTED"
    flash_at = now
  end
end

local function is_hex_char(key)
  return #key == 1 and key:match("^[0-9a-f]$") ~= nil
end

local function apply_hex_to(i, hex, now)
  local pk = Palette.persona()
  local ck = Palette.color_keys(pk)[i]
  if not ck then return false end
  if not Palette.set_override_hex(pk, ck, hex) then return false end
  vflash_at = now
  vflash_row = i
  crows_dirty = true
  return true
end

local function page2_adjust(i, ch, dir, mult, now)
  local pk = Palette.persona()
  local ck = Palette.color_keys(pk)[i]
  if not ck then return end
  edit_hex = ""
  local step = dir * (mult or 1) * 5 / 255
  local c = Palette.get_color(pk, ck)
  local r, g, b = c[1], c[2], c[3]
  if ch == 1 then r = r + step
  elseif ch == 2 then g = g + step
  else b = b + step end
  Palette.set_override(pk, ck, r, g, b)
  vflash_at = now
  vflash_row = i
  crows_dirty = true
end

local function trigger_reset_all(i, now)
  Palette.reset_all_colors(Palette.persona())
  flash_text = "COLOURS RESET"
  flash_at = now
  vflash_at = now
  vflash_row = i
  crows_dirty = true
end

local function reset_all_runtime(now)
  for _, d in ipairs(Tuning.runtime_entries()) do
    if not d.readonly then Tuning.reset(d.key); apply_live(d) end
  end
  flash_text = "SYSTEM SETTINGS RESET"
  flash_at = now
  vflash_at = now
  rows_dirty = true
end

local function set_page(p)
  edit_mode = false
  page = p
  sel = p == 1 and -3 or 1
  vflash_at = 0
  rows_dirty = true
end

local function activate_action(it, now)
  if not it then return end
  if it.action == "advanced" then
    set_page(2)
  elseif it.action == "runtime_reset" then
    reset_all_runtime(now)
  elseif it.action == "selftest" then
    trigger_selftest(now)
  end
end



local function toggle_group(g)
  if rail_page() or group_collapsed(g) then set_group_open(g) else collapsed[g] = true end
end

local PANEL_KEYS = {
  up = true, down = true, left = true, right = true,
  s = true, r = true, c = true, tab = true, ["return"] = true, kpenter = true,
}

local function page1_key(key, now)
  if rows_dirty or not rows then rebuild_rows() end
  local n = #rows
  if page == 1 then
    if sel > n or (sel <= 0 and not PLACE_AT[sel]) then sel = PLACE_FIRST end
  elseif sel > n or sel < 1 then
    sel = 1
  end
  local it = rows[sel]
  if key == "up" then
    if page ~= 1 then
      sel = sel > 1 and sel - 1 or n
    elseif PLACE_AT[sel] then
      sel = PLACE_AT[sel] > 1 and PLACE_ORDER[PLACE_AT[sel] - 1] or n
    else
      sel = sel > 1 and sel - 1 or PLACE_LAST
    end
  elseif key == "down" then
    if page ~= 1 then
      sel = sel < n and sel + 1 or 1
    elseif PLACE_AT[sel] then
      sel = PLACE_AT[sel] < #PLACE_ORDER and PLACE_ORDER[PLACE_AT[sel] + 1] or 1
    else
      sel = sel < n and sel + 1 or PLACE_FIRST
    end
  elseif key == "c" then
    collapse_all()
    rebuild_rows()
    if sel > #rows then sel = #rows end
  elseif key == "return" or key == "kpenter" then
    if page == 1 and sel == 0 then
      reset_position(now)
    elseif page == 1 and sel == -6 then
      set_place_target(place_target == "main" and "shop" or "main", now)
    elseif it and it.kind == "action" then
      activate_action(it, now)
    elseif it and it.kind == "header" then
      toggle_group(it.group)
      rebuild_rows()
      if sel > #rows then sel = #rows end
    end
  elseif key == "left" or key == "right" then
    local dir = key == "left" and -1 or 1
    if page == 1 and sel < 0 then
      adjust_position(sel, dir, shift_down() and 5 or 1, now)
    elseif it and it.kind == "header" then
      if key == "left" then collapsed[it.group] = true else set_group_open(it.group) end
      rebuild_rows()
      if sel > #rows then sel = #rows end
    elseif it and it.kind == "row" then
      page1_adjust(it.di, dir, shift_down() and 5 or 1, now)
    end
  elseif key == "s" then
    save_changes(now)
  elseif key == "r" then
    if page == 1 and sel == 0 then
      reset_position(now)
    elseif page == 1 and sel == -6 then
      set_place_target("main", now)
    elseif page == 1 and PLACE_KEY[sel] then
      reset_place_key(sel, now)
    elseif it and it.kind == "row" then
      local d = active_defs()[it.di]
      if not parent_off(d) then
        Tuning.reset(d.key)
        apply_live(d)
        vflash_at = now
        vflash_row = it.di
        rows_dirty = true
      end
    end
  end
end

local function page2_key(key, now)
  local pk = Palette.persona()
  local ckeys = Palette.color_keys(pk)
  local nrows = #ckeys + 1
  if sel > nrows then sel = 1 end
  if key == "s" then
    save_changes(now)
    return
  end
  if edit_mode then
    local ck = ckeys[sel]
    if not ck then edit_mode = false return end
    if is_hex_char(key) then
      if #edit_hex >= 6 then edit_hex = "" end
      edit_hex = edit_hex .. key
      if #edit_hex == 6 then apply_hex_to(sel, edit_hex, now) end
      return
    elseif key == "backspace" then
      edit_hex = edit_hex:sub(1, -2)
      return
    end
    if key == "return" or key == "kpenter" or key == "escape" then
      if #edit_hex == 6 then apply_hex_to(sel, edit_hex, now) end
      edit_hex = ""
      edit_mode = false
    elseif key == "up" then
      edit_ch = edit_ch > 1 and edit_ch - 1 or 3
    elseif key == "down" then
      edit_ch = edit_ch < 3 and edit_ch + 1 or 1
    elseif key == "left" or key == "right" then
      page2_adjust(sel, edit_ch, key == "left" and -1 or 1, shift_down() and 5 or 1, now)
    elseif key == "r" then
      Palette.reset_color(pk, ck)
      edit_hex = ""
      edit_mode = false
      vflash_at = now
      vflash_row = sel
      crows_dirty = true
    end
    return
  end
  if key == "up" then
    sel = sel > 1 and sel - 1 or nrows
  elseif key == "down" then
    sel = sel < nrows and sel + 1 or 1
  elseif key == "return" or key == "kpenter" then
    if sel == nrows then
      trigger_reset_all(sel, now)
    else
      edit_mode = true
      edit_ch = 1
      edit_hex = ""
    end
  elseif key == "r" then
    if sel > #ckeys then return end
    Palette.reset_color(pk, ckeys[sel])
    vflash_at = now
    vflash_row = sel
    crows_dirty = true
  end
end

function Panel.keypressed(key)
  if not open then return false end
  local running = SelfTest.running()
  local hex_typing = page == 4 and edit_mode and (is_hex_char(key) or key == "backspace")
  local panel_key = PANEL_KEYS[key] and not (key == "c" and page == 4 and not edit_mode)
  if not (panel_key or hex_typing or (key == "escape" and edit_mode) or (key == "a" and running)) then
    return false
  end
  local now = now_s()
  if key == "a" and running and not hex_typing then
    SelfTest.abort()
    return true
  end
  if key == "tab" then
    set_page(page % 5 + 1)
    return true
  end
  if page == 4 then
    page2_key(key, now)
  else
    page1_key(key, now)
  end
  return true
end

function Panel.mousepressed(x, y, button)
  if not open or not HIT.valid then return false end
  if not in_rect(x, y, HIT.px, HIT.py, HIT.pw, HIT.ph) then return false end
  mouse_seen = true
  local now = now_s()
  if in_rect(x, y, HIT.cl_x, HIT.cl_y, HIT.cl_w, HIT.cl_h) then
    if button == 1 then Panel.toggle() end
    return true
  end
  if in_rect(x, y, HIT.pr_x, HIT.pr_y, HIT.pr_w, HIT.pr_h) then
    local cur = Palette.persona()
    local idx = 1
    for i2, p2 in ipairs(PERSONA_ORDER) do if p2 == cur then idx = i2 end end
    local step = (button == 2) and -1 or 1
    local nxt = PERSONA_ORDER[((idx - 1 + step) % #PERSONA_ORDER) + 1]
    Tuning.set("NEURO_PERSONA", nxt)
    apply_live(Tuning.definition("NEURO_PERSONA"))
    rows_dirty = true
    crows_dirty = true
    return true
  end
  if button == 1 and y >= HIT.tab_y and y < HIT.tab_y + HIT.tab_h then
    for tab = 1, 5 do
      local tx, tw = HIT.tab_x[tab], HIT.tab_w[tab]
      if tx and x >= tx and x < tx + tw then
        if page ~= tab then set_page(tab) end
        return true
      end
    end
  end
  if page == 1 and in_rect(x, y, HIT.place_x, HIT.place_y, HIT.place_w, HIT.place_h) then
    for ti = 1, #HIT.place_tabs do
      local r = HIT.place_tabs[ti]
      if in_rect(x, y, r.x, r.y, r.w, r.h) then
        sel = -6
        if button == 1 then set_place_target(r.value, now) end
        return true
      end
    end
    local anchor = placement_anchor_at(x, y)
    if anchor then
      sel = -3
      if button == 1 then set_position_value(place_key(-3), anchor, now) end
      return true
    end
    if HIT.place_reset and in_rect(x, y, HIT.place_reset.x, HIT.place_reset.y,
      HIT.place_reset.w, HIT.place_reset.h)
    then
      sel = 0
      if button == 1 then reset_position(now) end
      return true
    end
    for index = 1, #PLACE_SLIDERS do
      local dec, inc = HIT.place_dec[index], HIT.place_inc[index]
      if dec and in_rect(x, y, dec.x, dec.y, dec.w, dec.h) then
        sel = PLACE_SLIDERS[index].sel
        adjust_position(sel, -1, shift_down() and 5 or 1, now)
        return true
      end
      if inc and in_rect(x, y, inc.x, inc.y, inc.w, inc.h) then
        sel = PLACE_SLIDERS[index].sel
        adjust_position(sel, 1, shift_down() and 5 or 1, now)
        return true
      end
    end
    local slider = placement_slider_at(x, y)
    if slider then
      sel = PLACE_SLIDERS[slider].sel
      if button == 1 then
        placement_drag = slider
        set_slider_from_x(slider, x, now)
      end
      return true
    end
    sel = -3
    return true
  end
  if page == 4 then
    if button == 1 then
      local si = swatch_at(x, y)
      if si then
        local ckeys = Palette.color_keys(Palette.persona())
        local target = (sel <= #ckeys) and sel or 1
        sel = target
        apply_hex_to(target, SWATCHES[si], now)
        edit_hex = ""
        return true
      end
    end
    if in_rect(x, y, HIT.ra_x, HIT.ra_y, HIT.ra_w, HIT.ra_h) then
      sel = #Palette.color_keys(Palette.persona()) + 1
      if button == 1 then trigger_reset_all(sel, now) end
      return true
    end
  end
  local i = row_at(x, y)
  if not i then return true end
  if page ~= 4 then
    sel = i
    local it = rows and rows[i]
    if not it then return true end
    if it.kind == "action" then
      if button == 1 then activate_action(it, now) end
      return true
    end
    if it.kind == "header" then
      if button == 1 then
        toggle_group(it.group)
        rebuild_rows()
        if sel > #rows then sel = #rows end
      end
      return true
    end
    local d = it.d
    local mult = shift_down() and 5 or 1
    local ry, rh = HIT.rows[i], HIT.itemh[i] or LAYOUT.ROW_H
    if HIT.dec_x[i] and in_rect(x, y, HIT.dec_x[i], ry, HIT.step_w, rh) then
      page1_adjust(it.di, -1, mult, now)
    elseif HIT.inc_x[i] and in_rect(x, y, HIT.inc_x[i], ry, HIT.step_w, rh) then
      page1_adjust(it.di, 1, mult, now)
    elseif HIT.ctl_x[i] and d.values and in_rect(x, y, HIT.ctl_x[i], ry, HIT.ctl_w[i], rh) then
      page1_adjust(it.di, button == 2 and -1 or 1, 1, now)
    end
    return true
  end
  local ckeys = Palette.color_keys(Palette.persona())
  if i > #ckeys then
    sel = i
    if button == 1 then trigger_reset_all(i, now) end
    return true
  end
  sel = i
  if button == 2 then
    if edit_mode then edit_mode = false end
    return true
  end
  local ch = hex_channel_at(x, i)
  edit_mode = true
  edit_hex = ""
  if ch then
    edit_ch = ch
  elseif edit_ch < 1 or edit_ch > 3 then
    edit_ch = 1
  end
  return true
end

function Panel.mousemoved(x, _y)
  if not open or not placement_drag then return false end
  set_slider_from_x(placement_drag, x, now_s())
  return true
end

function Panel.mousereleased(_x, _y, button)
  if not placement_drag or button ~= 1 then return false end
  placement_drag = nil
  return true
end

function Panel.wheelmoved(_, wy)
  if not open or not HIT.valid or not wy or wy == 0 then return false end
  local x, y = mouse_pos()
  if not in_rect(x, y, HIT.px, HIT.py, HIT.pw, HIT.ph) then return false end
  mouse_seen = true
  if page == 1 then
    local slider = placement_slider_at(x, y)
    if slider then
      local target = PLACE_SLIDERS[slider].sel
      sel = target
      adjust_position(target, wy > 0 and 1 or -1, shift_down() and 5 or 1, now_s())
      return true
    end
  end
  local i = row_at(x, y)
  if not i then return true end
  local now = now_s()
  local dir = wy > 0 and 1 or -1
  local mult = shift_down() and 5 or 1
  if page ~= 4 then
    local it = rows and rows[i]
    if it and it.kind == "row" then
      sel = i
      page1_adjust(it.di, dir, mult, now)
    end
  else
    if i <= #Palette.color_keys(Palette.persona()) and edit_mode and sel == i then
      page2_adjust(i, edit_ch, dir, mult, now)
    end
  end
  return true
end


local DESCS = {
  BASICS_INTRO = "Start with the choices below. The defaults are the recommended setup.",
  PACING = "Match model delays to the speed at which Balatro is running.",
  MASTER = "Start here: four global controls for the model's pacing.",
  DISPLAY = "Accessibility and on-screen presentation.",
  COOLDOWNS = "Base delays between context updates, actions and state changes.",
  THROTTLES = "State-specific minimum gaps between model actions.",
  ["POST-ACTION"] = "Waits after an action is sent or while the game resolves it.",
  ["ENTRY COOLDOWNS"] = "Grace periods before the model acts in a newly entered state.",
  WATCHDOGS = "Recovery timers for staged actions and the login animation.",
  CADENCE = "Hover, context refresh and action-registration timing.",
  LAYOUT = "HUD position, scale and diagnostic overlay.",
  SYSTEM = "Diagnostics and startup switches; notes identify restart-only changes.",
  NEURO_SPEED_MULT = "Changes hover and post-action waits. Higher is safer but makes play visibly slower.",
  EXAMPLE_NEURO_SPEED_MULT = "Example: 1.25x gives animations more time; 0.5x is faster but can race the UI.",
  NEURO_COOLDOWN_SCALE = "Scales every cooldown together without changing the model's strategy or prompts.",
  EXAMPLE_NEURO_COOLDOWN_SCALE = "Example: use 1.5x after missed clicks; use 0.75x only when play is stable.",
  NEURO_AUTO_TUNE = "Shortens cooldowns at higher Balatro game speeds to preserve reliable timing.",
  EXAMPLE_NEURO_AUTO_TUNE = "Example: at 4x game speed, a normal wait is automatically cut roughly in half.",
  NEURO_CD_PRESET = "Selects the game speed used by auto-tune; AUTO reads Balatro's live setting.",
  EXAMPLE_NEURO_CD_PRESET = "Example: choose 2X when you play at 2x game speed but speed detection is unreliable.",
  NEURO_STATE_COOLDOWN = "Min gap between state-context updates",
  NEURO_ACTION_COOLDOWN = "Min gap between any two actions",
  NEURO_ENFORCE_COOLDOWN = "Cooldown before the same action can repeat",
  NEURO_GLOBAL_COOLDOWN = "Fallback minimum gap between actions",
  NEURO_FORCE_DEBOUNCE = "Wait before re-sending a changed force",
  NEURO_TRANSITION_COOLDOWN = "Settle time right after a state change",
  NEURO_REFRESH_COOLDOWN = "Min gap before refreshing context in a state",
  NEURO_THROTTLE_SHOP = "Per-action cooldown while in the shop",
  NEURO_THROTTLE_PACK = "Per-action cooldown while opening packs",
  NEURO_GLOBAL_THROTTLE_SELECTING_HAND = "Global action gap while selecting a hand",
  NEURO_GLOBAL_THROTTLE_SHOP = "Global action gap in the shop",
  NEURO_GLOBAL_THROTTLE_BLIND_SELECT = "Global action gap at blind select",
  NEURO_GLOBAL_THROTTLE_PACK = "Global action gap while in a pack",
  NEURO_POST_PLAY = "Pause after playing a hand",
  NEURO_POST_DISCARD = "Pause after discarding",
  NEURO_POST_BUY = "Pause after buying from the shop",
  NEURO_SHOP_BUY_DELAY = "Hold on the lifted card before the buy resolves",
  NEURO_SHOP_BUY_BLOCK = "Block new actions this long after a buy",
  NEURO_PACK_PICK_DELAY = "Hold on the lifted card before the pick resolves",
  NEURO_PACK_PICK_BLOCK = "Block new actions this long after a pack pick",
  NEURO_POST_SELL = "Pause after selling a card",
  NEURO_POST_DEFAULT = "Default pause after any staged action",
  NEURO_ENTRY_CD_SHOP = "Grace after entering the shop before acting",
  NEURO_ENTRY_CD_ROUND_EVAL = "Grace after entering round-eval before acting",
  NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED = "Grace after a modded booster opens",
  NEURO_ENTRY_CD_BUFFOON_PACK = "Grace after a Buffoon pack opens",
  NEURO_ENTRY_CD_TAROT_PACK = "Grace after a Tarot pack opens",
  NEURO_ENTRY_CD_PLANET_PACK = "Grace after a Planet pack opens",
  NEURO_ENTRY_CD_SPECTRAL_PACK = "Grace after a Spectral pack opens",
  NEURO_ENTRY_CD_STANDARD_PACK = "Grace after a Standard pack opens",
  NEURO_STAGING_FAILSAFE = "Cancel a stuck staged action after this long",
  NEURO_SHOP_BUY_WATCHDOG_GRACE = "Extra grace before the buy watchdog trips",
  NEURO_DEFER_WINDOW_MIN = "Min window protecting a just-failed action",
  NEURO_LOGIN_ANIM_BLOCK = "Don't force actions during the login animation",
  NEURO_ENGINE_GATE_FAILSAFE = "Allow action routing after an engine lock remains stuck this long",
  NEURO_VOUCHER_DRAWER_SAFETY = "File a redeemed voucher anyway if the centre corridor stops advancing",
  NEURO_ACK_IDLE_REASK = "Ask an acknowledged offer again after this much silence",
  NEURO_FORCE_LIVENESS_TIMEOUT = "Stop waiting on an unanswered force after this long",
  NEURO_FORCE_CANCEL_SETTLE = "Keep a withdrawn offer's actions off the wire this long",
  NEURO_FORCE_CANCEL_IDLE = "Give up on a withdrawn offer's quarantine after this long without a replacement",
  NEURO_FORCE_STALL = "Nudge the mod back into asking after this long with no window and no activity",
  NEURO_HOVER_PER_CARD = "Hover time per card before a play / discard",
  NEURO_HOVER_SHOP = "Hover time on a shop item before buying",
  NEURO_HOVER_USE = "Hover time on a consumable before using it",
  NEURO_HOVER_DEFAULT = "Default hover time before executing",
  NEURO_HOLD_ALL_SELECTED = "Hold after all cards selected, before playing",
  NEURO_CTX_CACHE_TTL = "How long a built context is reused before rebuild",
  NEURO_ROUTER_DEFER_FAILSAFE = "Give up waiting for the engine to settle after this long",
  NEURO_OVERLAY_ANCHOR = "Places the persistent HUD away from the VTuber avatar; AUTO preserves the original layout.",
  EXAMPLE_NEURO_OVERLAY_ANCHOR = "Example: choose MIDDLE-LEFT when the VTuber avatar occupies the right side of the screen.",
  NEURO_OVERLAY_OFFSET_X = "Moves both side panels inward from their anchored screen edges.",
  NEURO_OVERLAY_OFFSET_Y = "Moves both side panels vertically from the selected anchor.",
  NEURO_OVERLAY_SCALE_RIGHT = "Size of the main HUD panel",
  NEURO_OVERLAY_SCALE_LEFT = "Size of the shop HUD panel",
  NEURO_SHOP_ANCHOR = "Places the shop HUD on its own; AUTO keeps it opposite the main HUD.",
  NEURO_SHOP_OFFSET_X = "Moves the shop HUD inward from its anchored screen edge.",
  NEURO_SHOP_OFFSET_Y = "Moves the shop HUD vertically from its anchor.",
  NEURO_CENTER_SCALE = "Size of the buy receipt and the centre card showcase",
  NEURO_DEBUG_OVERLAY = "On-screen debug stats (off / compact / expanded)",
  NEURO_PANEL_SCALE = "Size of this tuning panel; 1.00x is its natural size",
  NEURO_PERSONA = "Character skin used by the HUD and game-over presentation",
  NEURO_DEBUG = "Verbose debug logging to file",
  NEURO_PERF_LOG = "Write FPS / memory samples to disk",
  NEURO_AI_CARD_GLOW = "Glow the card the AI is hovering",
  NEURO_OVERLAY_DEV = "Hot-reload HUD files on change (dev)",
  NEURO_STAGING_DEBUG = "Draw the staging hover/execute debug overlay",
  NEURO_OUTBOX_TRUNCATE_ON_STARTUP = "Clear the outbox file on boot",
  NEURO_INBOX_TRUNCATE_ON_STARTUP = "Clear the inbox file on boot",
  NEURO_SELFTEST_ON_BOOT = "Run the in-engine self-test suite at boot",
  NEURO_CARD_DEX_ON_BOOT = "Sweep every card through the render matrix at boot and write a report",
  NEURO_SELFTEST_PACK = "Run only the pack-launch self-test scenario",
  NEURO_SELFTEST_FILTER = "Only run self-test cases matching this text",
  NEURO_SMALL_REGRESSION = "Run the fixed LLM task battery at boot (small regression check)",
  NEURO_CRASH_GUARDS = "Drop throwing deferred events + guard nil-deref UI callbacks (prevents fast-play hardlocks)",
  NEURO_CONFIRM_HAND = "Require a confirmation before a hand is played; turn off to let play_hand commit on the first send",
  NEURO_CONFIRM_REASON_ALWAYS = "Require a reason on every confirm_play yes, not just when a stronger ready hand is being passed over; turn off for the lighter-friction yes/no-only behavior",
}


local TXT = {
  BADGE = "LLM PAUSED (F8)",
  TITLE = "Neuratro",
  SUBTITLE = "tuning",
  RESET_ALL = "RESET ALL COLOURS",
  NOTE = "Colour grading aid -- tune by eye against how the overlay actually renders, values persist per persona.",
  TABS = { "BASICS", "ADVANCED", "TIMING", "COLOURS", "SYSTEM" },
  FOOTERS = {
    basics = { { "UP/DN", "move" }, { "LT/RT", "change" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
    advanced = { { "UP/DN", "move" }, { "LT/RT", "edit" }, { "ENTER", "fold" }, { "C", "fold all" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
    advanced_run = { { "UP/DN", "move" }, { "LT/RT", "edit" }, { "A", "abort test" }, { "C", "fold all" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
    timing = { { "UP/DN", "move" }, { "LT/RT", "tune" }, { "ENTER", "fold" }, { "C", "fold all" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
    colours = { { "UP/DN", "move" }, { "ENTER", "edit" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
    colours_edit = { { "0-9 A-F", "type hex" }, { "BKSP", "delete" }, { "LT/RT", "nudge" }, { "UP/DN", "channel" }, { "ENTER", "done" } },
    system = { { "UP/DN", "move" }, { "LT/RT", "toggle" }, { "R", "reset" }, { "S", "save" }, { "TAB", "page" }, { "F8", "close" } },
  },
  MOUSE = { { "CLICK", "select" }, { "WHEEL", "change" }, { "SHIFT", "x5" } },
}


local print_tracked = Prims.print_tracked
local tracked_width = Prims.tracked_width

local function fit_text(text, f, max_w)
  if not text or text == "" then return text end
  if f:getWidth(text) <= max_w then return text end
  while #text > 1 and f:getWidth(text .. "...") > max_w do
    text = drop_last_codepoint(text)
  end
  return text .. "..."
end



local _wrap_cache, _wrap_n = {}, 0
local function wrap_lines(text, f, max_w, max_lines)
  if not text or text == "" then return {} end
  local key = max_w .. "\1" .. max_lines .. "\1" .. text
  local hit = _wrap_cache[key]
  if hit then return hit end
  local all, cur = {}, nil
  for word in text:gmatch("%S+") do
    local try = cur and (cur .. " " .. word) or word
    if cur and f:getWidth(try) > max_w then
      all[#all + 1] = cur
      cur = word
    else
      cur = try
    end
  end
  if cur then all[#all + 1] = cur end
  local lines = {}
  for i = 1, math.min(#all, max_lines) do
    lines[i] = fit_text(all[i], f, max_w)
  end
  if #all > max_lines and lines[#lines] then
    local last = lines[#lines]
    while #last > 1 and f:getWidth(last .. "...") > max_w do
      last = drop_last_codepoint(last)
    end
    lines[#lines] = last .. "..."
  end
  if _wrap_n > 256 then _wrap_cache, _wrap_n = {}, 0 end
  _wrap_cache[key] = lines
  _wrap_n = _wrap_n + 1
  return lines
end

local function push_clip(x, y, w, h)
  local g = love.graphics
  if not (g.setScissor and g.getScissor) then return nil end
  local prev = { g.getScissor() }
  g.setScissor(x, y, math.max(0, w), math.max(0, h))
  return prev
end

local function pop_clip(prev)
  local g = love.graphics
  if not (g.setScissor and prev) then return end
  if prev[1] then g.setScissor(prev[1], prev[2], prev[3], prev[4]) else g.setScissor() end
end

local function fill_rect(col, a, x, y, w, h, r)
  set_col(col, a)
  love.graphics.rectangle("fill", x, y, w, h, r or 0, r or 0)
end

local function line_rect(col, a, x, y, w, h, r)
  set_col(col, a)
  love.graphics.setLineWidth(u(1))
  love.graphics.rectangle("line", x, y, w, h, r or 0, r or 0)
end

local function selected_fill(x, y, w, h, pa)
  fill_rect(STYLE.selected, pa, x, y, w, h, LAYOUT.ROW_R)
  fill_rect(STYLE.accent, pa, x, y + u(4), u(2), h - u(4) * 2)
end

local function row_chrome(x, y, w, h, hovered, selected, pa)
  if hovered and not selected then
    fill_rect(STYLE.surface_alt, 0.75 * pa, x, y, w, h, LAYOUT.ROW_R)
  end
  if selected then selected_fill(x, y, w, h, pa) end
end

local function segment_chrome(x, y, w, h, r, active, hot, divider_inset, pa)
  if active then
    fill_rect(STYLE.surface_alt, pa, x + u(2), y + u(2), w - u(2) * 2, h - u(2) * 2, r)
    fill_rect(STYLE.accent, 0.95 * pa, x + u(2), y + h - u(3), w - u(2) * 2, u(2))
  elseif hot then
    fill_rect(STYLE.surface, 0.85 * pa, x + u(2), y + u(2), w - u(2) * 2, h - u(2) * 2, r)
  elseif divider_inset then
    fill_rect(STYLE.border, 0.70 * pa, x, y + divider_inset, u(1), h - divider_inset * 2)
  end
end

local function card_shadow(x, y, w, h, a)
  fill_rect(STYLE.scrim, 0.20 * a, x - u(3), y - u(1), w + u(6), h + u(5))
  fill_rect(STYLE.scrim, 0.38 * a, x - u(1), y + u(1), w + u(2), h + u(2))
end

local function print_at(txt, f, col, a, x, y)
  love.graphics.setFont(f)
  set_col(col, a)
  love.graphics.print(txt, x, y)
end

local function print_rgba(txt, f, r, g, b, a, x, y)
  love.graphics.setFont(f)
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(txt, x, y)
end



local function text_mid(f, y, h)
  return round(y + (h - f:getHeight()) / 2) - u(1)
end



local function chevron(x, y, s, dir, col, a)
  set_col(col, a)
  love.graphics.setLineWidth(u(1.5))
  local h = s / 2
  if dir == "down" then
    love.graphics.line(x, y, x + h, y + h, x + s, y)
  elseif dir == "right" then
    love.graphics.line(x, y, x + h, y + h, x, y + s)
  else
    love.graphics.line(x + h, y, x, y + h, x + h, y + s)
  end
  love.graphics.setLineWidth(u(1))
end

local function draw_caret(x, y, s, expanded, col, a)
  chevron(x, y, s, expanded and "down" or "right", col, a)
end

local function draw_arrow(x, y, s, left, col, a)
  chevron(x, y, s, left and "left" or "right", col, a)
end

local function capsule(col, a, x, y, w, h)
  local r = h / 2
  set_col(col, a)
  love.graphics.rectangle("fill", x + r, y, math.max(0, w - h), h)
  love.graphics.circle("fill", x + r, y + r, r)
  love.graphics.circle("fill", x + w - r, y + r, r)
end






local function draw_toggle(x, y, w, h, on, a, t01, hot)
  t01 = t01 or 1
  local r = h / 2
  local cy = y + r
  local lx, rx = x + r, x + w - r
  local from, to = on and lx or rx, on and rx or lx
  local kx = from + (to - from) * t01

  if hot then capsule(STYLE.surface_alt, 0.90 * a, x - u(3), y - u(3), w + u(6), h + u(6)) end

  local track = on and STYLE.accent or STYLE.off
  local ta = (on and 0.94 or 1.0) * a
  if t01 < 1 then ta = ta * (0.75 + 0.25 * t01) end
  capsule(track, ta, x, y, w, h)
  if not on then
    set_col(STYLE.scrim, 0.30 * a)
    love.graphics.rectangle("fill", x + r, y, w - h, u(1))
  end

  local kr = r - u(2.5) + (hot and u(0.5) or 0)
  set_col(STYLE.scrim, 0.35 * a)
  love.graphics.circle("fill", kx, cy + u(1), kr)
  set_col((on or hot) and STYLE.text or STYLE.muted, (on and 0.99 or 0.92) * a)
  love.graphics.circle("fill", kx, cy, kr)
  return kx
end

local function draw_slider(x, y, w, h, frac, a, active)
  local th = u(3)
  local ty = round(y + (h - th) / 2)
  capsule(STYLE.border, 0.95 * a, x, ty, w, th)
  if frac > 0 then
    capsule(active and STYLE.accent or STYLE.muted, (active and 0.95 or 0.65) * a,
      x, ty, math.max(th, round(w * frac)), th)
  end
  local kx, kcy, kr = round(x + w * frac), round(y + h / 2), u(4.5)
  set_col(STYLE.scrim, 0.35 * a)
  love.graphics.circle("fill", kx, kcy + u(1), kr)
  set_col(active and STYLE.accent or STYLE.muted, a)
  love.graphics.circle("fill", kx, kcy, kr)
end


local function draw_button(x, y, w, h, label, f, active, enabled, a)
  if active then fill_rect(STYLE.surface_alt, 0.95 * a, x, y, w, h, LAYOUT.ROW_R) end
  line_rect(active and STYLE.accent or STYLE.border, (active and 0.85 or 0.70) * a, x, y, w, h, LAYOUT.ROW_R)
  local col = (not enabled and STYLE.faint) or STYLE.text
  print_at(fit_text(label, f, w - u(12) * 2), f, col, 0.96 * a, x + u(12), text_mid(f, y, h))
end

local function button_w(label, f)
  return f:getWidth(label) + u(12) * 2
end



local function draw_eyebrow(text, f, x, y, h, col, a)
  love.graphics.setFont(f)
  set_col(col, a)
  print_tracked(text, x, text_mid(f, y, h), LAYOUT.TRACK, f)
  return x + tracked_width(text, LAYOUT.TRACK, f)
end




local function flow(n, rect, max_cols, row_h, fit_cols)
  row_h = row_h or LAYOUT.ROW_H
  local per = math.max(1, math.floor(rect.h / row_h))
  local need = math.max(1, math.ceil(n / per))
  local cols = math.min(need, max_cols)
  if cols * per < n then
    cols = math.min(need, math.max(max_cols, fit_cols or max_cols))
  end
  local rows_per = math.min(per, math.max(1, math.ceil(n / cols)))
  local col_w = math.floor((rect.w - (cols - 1) * LAYOUT.COL_GAP) / cols)
  return { cols = cols, per = per, rows_per = rows_per, col_w = col_w,
    row_h = row_h, capacity = cols * per, rect = rect }
end





local function plan_columns(items, fl)
  local n = #items
  local blocks, i = {}, 1
  while i <= n do
    local len = 1
    if items[i].kind == "header" then
      local j = i + 1
      while j <= n and items[j].kind == "row" do
        len = len + 1
        j = j + 1
      end
    end
    blocks[#blocks + 1] = { first = i, len = len }
    i = i + len
  end
  local target = math.max(1, math.ceil(n / fl.cols))
  local plan = { ci = {}, ri = {} }
  local ci, ri = 0, 0
  for b = 1, #blocks do
    local blk = blocks[b]
    if ri > 0 and ri + blk.len > target and ci + 1 < fl.cols then
      ci, ri = ci + 1, 0
    end
    for k = 0, blk.len - 1 do
      if ri >= fl.per then
        if ci + 1 >= fl.cols then return nil end
        ci, ri = ci + 1, 0
      end
      plan.ci[blk.first + k] = ci
      plan.ri[blk.first + k] = ri
      ri = ri + 1
    end
  end
  return plan
end




local function rail_cells(items, rail, pane)
  local out = { x = {}, y = {}, w = {} }
  local rail_per = math.max(1, math.floor(rail.h / LAYOUT.ROW_H))
  local pane_per = math.max(1, math.floor(pane.h / LAYOUT.ROW_H))
  local nrows = 0
  for i = 1, #items do
    if items[i].kind == "row" then nrows = nrows + 1 end
  end
  local pane_cols = (nrows > pane_per) and LAYOUT.MAX_COLS or 1
  local pane_rows = math.min(pane_per, math.max(1, math.ceil(nrows / pane_cols)))
  local pane_w = math.floor((pane.w - (pane_cols - 1) * LAYOUT.COL_GAP) / pane_cols)
  local ri, pi = 0, 0
  for i = 1, #items do
    if items[i].kind == "row" then
      local ci = math.floor(pi / pane_rows)
      if ci < pane_cols then
        out.x[i] = pane.x + ci * (pane_w + LAYOUT.COL_GAP)
        out.y[i] = pane.y + (pi % pane_rows) * LAYOUT.ROW_H
        out.w[i] = pane_w
      end
      pi = pi + 1
    else
      if ri < rail_per then
        out.x[i], out.y[i], out.w[i] = rail.x, rail.y + ri * LAYOUT.ROW_H, rail.w
      end
      ri = ri + 1
    end
  end
  out.cols, out.rows_per, out.col_w = 1 + pane_cols, math.max(rail_per, pane_rows), pane_w
  out.capacity = rail_per + pane_cols * pane_rows
  return out
end

local function flow_cell(fl, i)
  local ci, ri
  if fl.plan then
    ci, ri = fl.plan.ci[i], fl.plan.ri[i]
    if not ci then return nil end
  else
    ci = math.floor((i - 1) / fl.rows_per)
    ri = (i - 1) % fl.rows_per
  end
  if ci >= fl.cols then return nil end
  return fl.rect.x + ci * (fl.col_w + LAYOUT.COL_GAP),
    fl.rect.y + ri * fl.row_h,
    fl.col_w
end


local function flow_cells(items, rect, max_cols, row_h, fit_cols)
  local fl = flow(#items, rect, max_cols, row_h, fit_cols)
  fl.plan = plan_columns(items, fl)
  local out = { x = {}, y = {}, w = {}, capacity = fl.capacity,
    cols = fl.cols, rows_per = fl.rows_per, col_w = fl.col_w, row_h = fl.row_h }
  for i = 1, #items do
    out.x[i], out.y[i], out.w[i] = flow_cell(fl, i)
  end
  return out
end

local function clear_hit()
  local lists = { HIT.rows, HIT.row_x, HIT.row_w, HIT.itemh, HIT.vis,
    HIT.dec_x, HIT.inc_x, HIT.ctl_x, HIT.ctl_w, HIT.hex_x, HIT.sw_rects,
    HIT.place_anchors, HIT.place_tabs, HIT.place_slider_x, HIT.place_slider_y,
    HIT.place_slider_w, HIT.place_slider_h, HIT.place_dec, HIT.place_inc }
  for li = 1, #lists do
    local t = lists[li]
    for k in pairs(t) do t[k] = nil end
  end
  HIT.sw_n = 0
  HIT.ra_x, HIT.ra_y, HIT.ra_w, HIT.ra_h = 0, 0, 0, 0
  HIT.place_x, HIT.place_y, HIT.place_w, HIT.place_h = 0, 0, 0, 0
  HIT.place_reset = nil
end

local function track_selftest()
  local running = SelfTest.running()
  if st_was_running and not running then
    local res = SelfTest.results()
    local p, f = 0, 0
    for i = 1, #res do
      if res[i].ok then p = p + 1 else f = f + 1 end
    end
    st_done = string.format("PASS %d/FAIL %d -- report: %s", p, f, tostring(SelfTest.report_path() or "not written"))
  end
  st_was_running = running
  return running
end



local function flash01(di, now, d)
  if di ~= vflash_row or vflash_at <= 0 then return 1 end
  return Motion.anim01(now - vflash_at, d or Motion.FAST)
end

local function selflash(vr, vg, vb, va, i, now, pa)
  if i == vflash_row and vflash_at > 0 then
    local k = 1 - Motion.anim01(now - vflash_at, Motion.MED)
    if k > 0 then
      vr, vg, vb = vr + (1 - vr) * k, vg + (1 - vg) * k, vb + (1 - vb) * k
      va = va + (1 - va) * k
    end
  end
  return vr, vg, vb, va * pa
end

local UI = {
  fit = fit_text, wrap = wrap_lines, push = push_clip, pop = pop_clip,
  fill = fill_rect, line = line_rect, at = print_at, rgba = print_rgba, mid = text_mid,
  caret = draw_caret, arrow = draw_arrow, toggle = draw_toggle,
  slider = draw_slider, button = draw_button, btn_w = button_w, eyebrow = draw_eyebrow,
  cells = flow_cells, rail_cells = rail_cells, flash = selflash, flash01 = flash01,
  capsule = capsule, round = round, hit = in_rect,
  label = nice_label, value = nice_value,
}


local function draw_header(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa = V.pa
  local ty = U.mid(V.ft, V.py, L.HEADER_H)
  U.at(TXT.TITLE, V.ft, ST.text, 0.97 * pa, V.inner_x, ty)


  U.at(TXT.SUBTITLE, V.ftab, ST.faint, 0.95 * pa,
    V.inner_x + V.ft:getWidth(TXT.TITLE) + u(9),
    ty + V.ft:getHeight() - V.ftab:getHeight())

  local ch = L.CHIP_H
  local cy = U.round(V.py + (L.HEADER_H - ch) / 2)
  HIT.cl_x, HIT.cl_y, HIT.cl_w, HIT.cl_h = V.px + V.pw - L.PAD - ch, cy, ch, ch
  local hovx = V.in_panel and U.hit(V.mx, V.my, HIT.cl_x, cy, ch, ch)
  if hovx then U.fill(ST.surface_alt, 0.95 * pa, HIT.cl_x, cy, ch, ch, L.ROW_R) end
  do
    local m = u(5)
    local x0, y0 = HIT.cl_x + ch / 2, cy + ch / 2
    set_col(hovx and ST.text or ST.muted, 0.95 * pa)
    love.graphics.setLineWidth(u(1.4))
    love.graphics.line(x0 - m, y0 - m, x0 + m, y0 + m)
    love.graphics.line(x0 + m, y0 - m, x0 - m, y0 + m)
    love.graphics.setLineWidth(u(1))
  end


  local pr = U.label(Palette.persona())
  local prw = V.fm:getWidth(pr) + u(32)
  HIT.pr_x, HIT.pr_y, HIT.pr_w, HIT.pr_h = HIT.cl_x - prw - u(6), cy, prw, ch
  local hovp = V.in_panel and U.hit(V.mx, V.my, HIT.pr_x, cy, prw, ch)
  if hovp then U.fill(ST.surface_alt, 0.95 * pa, HIT.pr_x, cy, prw, ch, L.ROW_R) end
  U.at(pr, V.fm, hovp and ST.text or ST.muted, 0.95 * pa, HIT.pr_x + u(10), U.mid(V.fm, cy, ch))
  U.caret(HIT.pr_x + prw - u(15), U.round(cy + ch / 2) - u(2), u(6), true,
    hovp and ST.muted or ST.faint, 0.95 * pa)

  if flash_text then
    local age = V.now - flash_at
    if age < SAVED_HOLD + Motion.SLOW then
      local fa = 0.95
      if age > SAVED_HOLD then
        fa = 0.95 * (1 - Motion.anim01(age - SAVED_HOLD, Motion.SLOW))
      end
      local ftw = V.fm:getWidth(flash_text)
      U.at(flash_text, V.fm, ST.muted, fa * pa, HIT.pr_x - u(14) - ftw, U.mid(V.fm, cy, ch))
    else
      flash_text = nil
    end
  end
end



local function draw_tabs(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa = V.pa
  local ty = V.py + L.HEADER_H
  local th = L.SEG_H
  local tby = U.round(ty + (L.TABS_H - th) / 2)
  HIT.tab_y, HIT.tab_h = tby, th

  local n = #TXT.TABS
  local labels, total = {}, 0
  for tab = 1, n do
    labels[tab] = U.label(TXT.TABS[tab])
    total = total + V.ftab:getWidth(labels[tab])
  end
  local track_w = total + n * u(30)
  local tx = V.inner_x

  U.fill(ST.scrim, 0.30 * pa, tx, tby, track_w, th)
  U.line(ST.border, 0.85 * pa, tx, tby, track_w, th)

  for tab = 1, n do
    local lw = V.ftab:getWidth(labels[tab])
    local tw = lw + u(30)
    HIT.tab_x[tab], HIT.tab_w[tab] = tx, tw
    local hovered = V.in_panel and U.hit(V.mx, V.my, tx, tby, tw, th)
    local active = page == tab
    segment_chrome(tx, tby, tw, th, L.ROW_R, active, hovered, tab > 1 and u(7) or nil, pa)
    U.at(labels[tab], V.ftab, (active or hovered) and ST.text or ST.muted, 0.96 * pa,
      U.round(tx + (tw - lw) / 2), U.mid(V.ftab, tby, th))
    tx = tx + tw
  end

  U.fill(ST.border, 0.55 * pa, V.px + L.PAD, ty + L.TABS_H - u(1), V.inner_w, u(1))
  U.fill(ST.scrim, 0.14 * pa, V.px + u(1), ty + L.TABS_H, V.pw - u(2), u(8))
  U.fill(ST.scrim, 0.16 * pa, V.px + u(1), ty + L.TABS_H, V.pw - u(2), u(4))
end

local PREVIEW = {
  sw = 0, sh = 0, side = "right", shop_side = "left",
  main_x = 0, main_y = 0, main_w = 0, main_h = 0,
  shop_x = 0, shop_y = 0, shop_w = 0, shop_h = 0,
}
local PREVIEW_MAIN_H = 420
local PREVIEW_SHOP_H = 330

local function overlay_module()
  return package.loaded["render.hud_overlay"] or require("render.hud_overlay")
end

local function shop_base_w()
  local mod = package.loaded["render.panels.shop"]
  return (mod and tonumber(mod.PANEL_BASE_W)) or 380
end

local function preview_geometry(anchor, ox, oy, main_scale, shop_scale, sw, sh,
  shop_anchor, shop_ox, shop_oy)
  local overlay = overlay_module()
  local g = PREVIEW
  g.sw, g.sh = sw, sh
  local reserve = math.max(0, tonumber(S.drawer_reserve) or 0)
  local margin = tonumber(overlay.PANEL_MARGIN) or 8
  local base_w = tonumber(overlay.PANEL_BASE_W) or 320

  g.main_w = math.max(1, round(base_w * main_scale))
  local avail = overlay.panel_available_height(anchor, oy, sh, reserve)
  g.main_h = clamp(round(PREVIEW_MAIN_H * main_scale), 1,
    math.max(1, math.min(avail, math.floor(sh * 0.58))))
  local px, py, side = overlay.panel_layout(anchor, ox, oy, sw, sh, g.main_w, g.main_h, reserve)
  g.main_x, g.main_y, g.side = px, py, side

  local head = tostring(anchor):sub(1, 6)
  local anchored_full = head == "middle" or head == "bottom"
  g.shop_w = math.max(1, round(shop_base_w() * shop_scale))
  local shop_avail = anchored_full and math.max(1, sh - margin * 2)
    or math.max(1, sh - py - 10)
  g.shop_h = clamp(round(PREVIEW_SHOP_H * shop_scale), 1,
    math.max(1, math.min(shop_avail, math.floor(sh * 0.72))))
  shop_anchor = tostring(shop_anchor or "auto")
  if shop_anchor ~= "auto" then
    local shop_avail_own = overlay.panel_available_height(shop_anchor, shop_oy, sh, 0)
    g.shop_h = clamp(round(PREVIEW_SHOP_H * shop_scale), 1,
      math.max(1, math.min(shop_avail_own, math.floor(sh * 0.72))))
    local qx, qy, qside = overlay.panel_layout(shop_anchor, shop_ox, shop_oy,
      sw, sh, g.shop_w, g.shop_h, 0)
    g.shop_x, g.shop_y, g.shop_side = qx, qy, qside
    return g
  end

  g.shop_side = side == "left" and "right" or "left"

  local inset = sw * (tonumber(shop_ox or ox) or 0) / 100
  local sx
  if g.shop_side == "left" then
    sx = math.min(margin + inset, px - g.shop_w - margin)
  else
    sx = math.max(sw - g.shop_w - margin - inset, px + g.main_w + margin)
  end
  g.shop_x = clamp(round(sx), margin, math.max(margin, sw - g.shop_w - margin))

  local dy = sh * (tonumber(shop_oy or oy) or 0) / 100
  local sy
  if head == "middle" then
    sy = (sh - g.shop_h) / 2 + dy
  elseif head == "bottom" then
    sy = sh - g.shop_h - margin + dy
  else
    sy = py + (sh * (tonumber(shop_oy) or 0) / 100)
  end
  g.shop_y = clamp(round(sy), margin, math.max(margin, sh - g.shop_h - margin))
  return g
end

local function draw_placement(V, rect)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa, mx, my, now = V.pa, V.mx, V.my, V.now
  HIT.place_x, HIT.place_y, HIT.place_w, HIT.place_h = rect.x, rect.y, rect.w, rect.h
  local card_selected = page == 1 and sel <= 0
  card_shadow(rect.x, rect.y, rect.w, rect.h, pa)
  U.fill(card_selected and ST.selected or ST.surface, pa, rect.x, rect.y, rect.w, rect.h, L.ROW_R)
  U.line(card_selected and ST.accent or ST.border, (card_selected and 0.95 or 0.80) * pa,
    rect.x, rect.y, rect.w, rect.h, L.ROW_R)

  local anchor = tostring(Tuning.get_raw("NEURO_OVERLAY_ANCHOR") or "auto")
  local ox = tonumber(Tuning.get_raw("NEURO_OVERLAY_OFFSET_X")) or 0
  local oy = tonumber(Tuning.get_raw("NEURO_OVERLAY_OFFSET_Y")) or 0
  local main_scale = tonumber(Tuning.get_raw("NEURO_OVERLAY_SCALE_RIGHT")) or 1
  local shop_scale = tonumber(Tuning.get_raw("NEURO_OVERLAY_SCALE_LEFT")) or 1
  local shop_anchor = tostring(Tuning.get_raw("NEURO_SHOP_ANCHOR") or "auto")
  local on_shop = place_target == "shop"
  local tgt_anchor = on_shop and shop_anchor or anchor

  local pad = L.PLACE_PAD
  local ix = rect.x + pad
  local iw = rect.w - pad * 2
  local ir = ix + iw

  local g = preview_geometry(anchor, ox, oy, main_scale, shop_scale, V.sw, V.sh,
    shop_anchor,
    tonumber(Tuning.get_raw("NEURO_SHOP_OFFSET_X")) or 0,
    tonumber(Tuning.get_raw("NEURO_SHOP_OFFSET_Y")) or 0)
  local well_h = rect.h - pad * 2
  local ctl_need = L.PLACE_COL_MIN * 2 + L.PLACE_COL_GAP
  local cap = math.min(L.PLACE_WELL_MAX, iw - L.PLACE_WELL_GAP - ctl_need)
  local well_w = math.max(L.PLACE_WELL_MIN,
    math.min(cap, U.round(well_h * g.sw / g.sh)))
  local well_x, well_y = ix, rect.y + pad

  U.fill(ST.scrim, 0.55 * pa, well_x, well_y, well_w, well_h)
  for i = 0, 3 do
    local ring = u(1) * i
    U.line(ST.scrim, (0.24 - i * 0.06) * pa, well_x + u(1) + ring, well_y + u(1) + ring,
      well_w - (u(1) + ring) * 2, well_h - (u(1) + ring) * 2)
  end

  local gut = L.PLACE_NODE_W + u(4)
  local inner_w = math.max(u(24), well_w - gut * 2)
  local inner_h = well_h - u(8)
  local k = math.min(inner_w / g.sw, inner_h / g.sh)
  local view_w, view_h = g.sw * k, g.sh * k
  local view_x = well_x + (well_w - view_w) / 2
  local view_y = well_y + (well_h - view_h) / 2
  local function map(px_, py_, pw_, ph_)
    local rw = math.max(u(6), U.round(pw_ * k))
    local rh = math.max(u(8), U.round(ph_ * k))
    local rx = U.round(view_x + px_ * k)
    local ry = U.round(view_y + py_ * k)
    if rx + rw > view_x + view_w then rx = U.round(view_x + view_w) - rw end
    if ry + rh > view_y + view_h then ry = U.round(view_y + view_h) - rh end
    return rx, ry, rw, rh
  end

  local function label_rect(text, rx, ry, rw, rh, col, alpha)
    if rw < u(26) or rh < u(14) then return end
    U.at(text, V.fm, col, alpha, U.round(rx + (rw - V.fm:getWidth(text)) / 2),
      U.mid(V.fm, ry, rh))
  end

  local function preview_panel(text, px_, py_, pw_, ph_, targeted)
    local rx, ry, rw, rh = map(px_, py_, pw_, ph_)
    if targeted then
      U.fill(ST.accent_dim, 0.95 * pa, rx, ry, rw, rh)
      U.line(ST.accent, pa, rx, ry, rw, rh)
      label_rect(text, rx, ry, rw, rh, ST.text, 0.96 * pa)
    else
      U.fill(ST.muted, 0.32 * pa, rx, ry, rw, rh)
      U.line(ST.muted, 0.72 * pa, rx, ry, rw, rh)
      label_rect(text, rx, ry, rw, rh, ST.faint, 0.95 * pa)
    end
  end
  if on_shop then
    preview_panel("HUD", g.main_x, g.main_y, g.main_w, g.main_h, false)
    preview_panel("SHOP", g.shop_x, g.shop_y, g.shop_w, g.shop_h, true)
  else
    preview_panel("SHOP", g.shop_x, g.shop_y, g.shop_w, g.shop_h, false)
    preview_panel("HUD", g.main_x, g.main_y, g.main_w, g.main_h, true)
  end

  U.line(ST.faint, 0.55 * pa, U.round(view_x), U.round(view_y),
    U.round(view_w), U.round(view_h))
  U.line(ST.border, 0.95 * pa, well_x, well_y, well_w, well_h)

  local node_w, node_h = L.PLACE_NODE_W, L.PLACE_NODE_H
  local node_pos = {
    ["top-left"] = { well_x + u(4), well_y + u(4) },
    ["top-right"] = { well_x + well_w - node_w - u(4), well_y + u(4) },
    ["middle-left"] = { well_x + u(4), well_y + (well_h - node_h) / 2 },
    ["middle-right"] = { well_x + well_w - node_w - u(4), well_y + (well_h - node_h) / 2 },
    ["bottom-left"] = { well_x + u(4), well_y + well_h - node_h - u(4) },
    ["bottom-right"] = { well_x + well_w - node_w - u(4), well_y + well_h - node_h - u(4) },
  }
  for i = 2, #ANCHORS do
    local value = ANCHORS[i]
    local pos = node_pos[value]
    local nx, ny = U.round(pos[1]), U.round(pos[2])
    local active = tgt_anchor == value
    local hovered = V.in_panel and U.hit(mx, my, nx, ny, node_w, node_h)
    local t = hover_t(20 + i, hovered and not active, now)
    if active then
      U.fill(ST.accent, 0.18 * pa, nx - u(2), ny - u(2), node_w + u(2) * 2, node_h + u(2) * 2)
    end
    U.fill(active and ST.accent or ST.surface_alt, (active and 0.95 or (0.72 + 0.22 * t)) * pa,
      nx, ny, node_w, node_h)
    U.line((active or t > 0) and ST.text or ST.border, (0.70 + 0.25 * t) * pa,
      nx, ny, node_w, node_h)
    local label = ANCHOR_LABELS[value]
    U.at(label, V.fm, active and ST.scrim or (t > 0 and ST.text or ST.muted), pa,
      U.round(nx + (node_w - V.fm:getWidth(label)) / 2), U.mid(V.fm, ny, node_h))
    HIT.place_anchors[#HIT.place_anchors + 1] =
      { x = nx, y = ny, w = node_w, h = node_h, value = value }
  end

  local ctl_x = well_x + well_w + L.PLACE_WELL_GAP
  local ctl_w = ir - ctl_x
  local col_w = math.floor((ctl_w - L.PLACE_COL_GAP) / 2)
  local col_a, col_b = ctl_x, ctl_x + col_w + L.PLACE_COL_GAP

  local head_y = rect.y + pad
  local ex = U.eyebrow("HUD LAYOUT", V.fs, ctl_x, head_y, L.PLACE_HEAD_H, ST.text, pa)

  local seg_h = L.PLACE_BTN_H
  local seg_y = U.round(head_y + (L.PLACE_HEAD_H - seg_h) / 2)
  local seg_x = ex + u(14)
  local seg_labels = { "MAIN", "SHOP" }
  local seg_values = { "main", "shop" }
  local seg_w = math.max(V.fm:getWidth("MAIN"), V.fm:getWidth("SHOP")) + u(18)
  local seg_track_w = seg_w * 2
  U.fill(ST.scrim, 0.30 * pa, seg_x, seg_y, seg_track_w, seg_h)
  U.line(sel == -6 and ST.accent or ST.border, (sel == -6 and 0.95 or 0.85) * pa,
    seg_x, seg_y, seg_track_w, seg_h)
  for si = 1, 2 do
    local sx0 = seg_x + (si - 1) * seg_w
    local seg_on = place_target == seg_values[si]
    local seg_hot = V.in_panel and U.hit(mx, my, sx0, seg_y, seg_w, seg_h)
    segment_chrome(sx0, seg_y, seg_w, seg_h, nil, seg_on, seg_hot, si == 2 and u(5) or nil, pa)
    local lw = V.fm:getWidth(seg_labels[si])
    local lc = (seg_on or seg_hot) and ST.text or ST.muted
    local lr, lg, lb, la = lc[1], lc[2], lc[3], 0.96
    if seg_on then lr, lg, lb, la = U.flash(lr, lg, lb, la, -6, now, 1) end
    U.rgba(seg_labels[si], V.fm, lr, lg, lb, la * pa,
      U.round(sx0 + (seg_w - lw) / 2), U.mid(V.fm, seg_y, seg_h))
    HIT.place_tabs[si] = { x = sx0, y = seg_y, w = seg_w, h = seg_h, value = seg_values[si] }
  end

  local auto_w = math.min(u(88), U.btn_w("AUTO", V.fm))
  local auto_x, auto_y, auto_h = ir - auto_w, head_y, L.PLACE_BTN_H
  local auto_active = tgt_anchor == "auto"
  local auto_hot = V.in_panel and U.hit(mx, my, auto_x, auto_y, auto_w, auto_h)
  U.button(auto_x, auto_y, auto_w, auto_h, "AUTO", V.fm, auto_active or auto_hot, true, pa)
  HIT.place_anchors[#HIT.place_anchors + 1] =
    { x = auto_x, y = auto_y, w = auto_w, h = auto_h, value = "auto" }

  local read_x = auto_x
  if tgt_anchor ~= "auto" then
    local read = ANCHOR_NAMES[tgt_anchor] or tgt_anchor:upper()
    read_x = auto_x - u(12) - V.fm:getWidth(read)
    local rc = sel == -3 and ST.text or ST.muted
    local rr, rg, rb, ra = U.flash(rc[1], rc[2], rc[3], sel == -3 and 1.0 or 0.94, -3, now, pa)
    U.rgba(read, V.fm, rr, rg, rb, ra, read_x, U.mid(V.fm, head_y, L.PLACE_HEAD_H))
  end
  local rule_x0, rule_x1 = seg_x + seg_track_w + u(12), read_x - u(12)
  if rule_x1 > rule_x0 then
    U.fill(ST.border, 0.45 * pa, rule_x0, U.round(head_y + L.PLACE_HEAD_H / 2),
      rule_x1 - rule_x0, u(1))
  end

  local cap_y = rect.y + u(40)
  local row_h = L.PLACE_ROW_H
  local row_a, row_b = rect.y + u(60), rect.y + u(90)

  local function caption(text, cx)
    local cex = U.eyebrow(text, V.fs, cx, cap_y, L.PLACE_CAP_H, ST.muted, 0.94 * pa)
    local x1 = cx + col_w
    if x1 > cex + u(12) then
      U.fill(ST.border, 0.35 * pa, cex + u(12), U.round(cap_y + L.PLACE_CAP_H / 2),
        x1 - cex - u(12), u(1))
    end
  end
  caption(on_shop and "POSITION - SHOP" or "POSITION - MAIN", col_a)
  caption("SIZE", col_b)

  local idle_offsets = false
  local function place_row(index, cx, row_y)
    local s = PLACE_SLIDERS[index]
    local raw = tonumber(Tuning.get_raw(slider_key(s))) or s.default
    local selected = sel == s.sel
    local idle = index <= 2 and idle_offsets
    local ia = idle and 0.55 or 1.0
    local bx, bw = cx - L.PLACE_RAIL_GUT, col_w + L.PLACE_RAIL_GUT
    local hovered = V.in_panel and U.hit(mx, my, bx, row_y, bw, row_h)
    local t = hover_t(index, hovered and not selected, now)
    if t > 0 then
      U.fill(ST.surface_alt, 0.70 * t * pa, bx, row_y, bw, row_h, L.ROW_R)
    end
    if selected then selected_fill(bx, row_y, bw, row_h, pa) end

    local dec_x = cx + L.PLACE_LABEL_W
    local track_x = dec_x + L.PLACE_STEP_W + u(8)
    local value_x = cx + col_w - L.PLACE_VALUE_W
    local inc_x = value_x - u(8) - L.PLACE_STEP_W
    local track_w = math.max(L.PLACE_TRACK_MIN, inc_x - u(8) - track_x)

    U.at(U.fit(s.label, V.fl, L.PLACE_LABEL_W - u(8)), V.fl,
      (idle and ST.faint) or (selected and ST.text) or ST.muted, 0.97 * pa,
      cx, U.mid(V.fl, row_y, row_h))

    local span = s.max - s.min
    local frac = clamp((raw - s.min) / span, 0, 1)
    U.slider(track_x, row_y, track_w, row_h, frac, ia * pa, selected and not idle)
    local tick = U.round(track_x + track_w * (s.default - s.min) / span)
    U.fill(ST.faint, 0.75 * ia * pa, tick, row_y + u(7), u(1), row_h - u(7) * 2)

    local ay = U.round(row_y + (row_h - u(8)) / 2)
    local dec_hot = V.in_panel and U.hit(mx, my, dec_x, row_y, L.PLACE_STEP_W, row_h)
    local inc_hot = V.in_panel and U.hit(mx, my, inc_x, row_y, L.PLACE_STEP_W, row_h)
    U.arrow(dec_x + u(6), ay, u(8), true, dec_hot and ST.accent or ST.muted, ia * pa)
    U.arrow(inc_x + u(6), ay, u(8), false, inc_hot and ST.accent or ST.muted, ia * pa)

    local text = s.fmt(raw)
    local vc = (idle and ST.faint) or (selected and ST.text) or ST.muted
    local vr, vg, vb, va = U.flash(vc[1], vc[2], vc[3],
      (selected and not idle) and 1.0 or 0.96, s.sel, now, pa)
    U.rgba(text, V.fl, vr, vg, vb, va,
      value_x + L.PLACE_VALUE_W - V.fl:getWidth(text), U.mid(V.fl, row_y, row_h))

    HIT.place_slider_x[index], HIT.place_slider_y[index] = track_x, row_y
    HIT.place_slider_w[index], HIT.place_slider_h[index] = track_w, row_h
    HIT.place_dec[index] = { x = dec_x, y = row_y, w = L.PLACE_STEP_W, h = row_h }
    HIT.place_inc[index] = { x = inc_x, y = row_y, w = L.PLACE_STEP_W, h = row_h }
  end

  place_row(1, col_a, row_a)
  place_row(2, col_a, row_b)
  place_row(3, col_b, row_a)
  place_row(4, col_b, row_b)

  local reset_w = math.min(u(170), U.btn_w("RESET LAYOUT", V.fm))
  local reset_h = L.PLACE_BTN_H
  local reset_x, reset_y = ir - reset_w, rect.y + rect.h - pad - reset_h
  if reset_x - u(12) > ctl_x then
    U.fill(ST.border, 0.45 * pa, ctl_x, U.round(reset_y + reset_h / 2),
      reset_x - u(12) - ctl_x, u(1))
  end
  local reset_hot = V.in_panel and U.hit(mx, my, reset_x, reset_y, reset_w, reset_h)
  U.button(reset_x, reset_y, reset_w, reset_h, "RESET LAYOUT", V.fm,
    sel == 0 or reset_hot, true, pa)
  HIT.place_reset = { x = reset_x, y = reset_y, w = reset_w, h = reset_h }
end


local function draw_settings(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa, mx, my = V.pa, V.mx, V.my
  local grid = { x = V.content.x, y = V.content.y, w = V.content.w, h = V.content.h }

  local row_h = L.ROW_H
  if page == 1 then
    local ih = L.BASICS_INTRO_H
    local clip = U.push(grid.x, grid.y, grid.w, ih)
    U.at(U.fit(DESCS.BASICS_INTRO, V.fd, grid.w), V.fd, ST.muted, 0.95 * pa,
      grid.x, U.mid(V.fd, grid.y, ih))
    U.pop(clip)
    local band = ih + L.BASICS_INTRO_GAP
    grid.y = grid.y + band
    grid.h = grid.h - band
    draw_placement(V, { x = grid.x, y = grid.y, w = grid.w, h = L.PLACEMENT_H })
    grid.y = grid.y + L.PLACEMENT_H + L.PLACEMENT_GAP
    grid.h = grid.h - L.PLACEMENT_H - L.PLACEMENT_GAP
    row_h = L.BASICS_ROW_H
    if math.ceil(#rows / L.MAX_COLS) * row_h > grid.h then row_h = L.ROW_H end
  end

  HIT.n = #rows
  local rail = rail_page()
  local cells
  if rail then
    local rw = L.RAIL_W
    local pane = { x = grid.x + rw + L.RAIL_GAP, y = grid.y,
      w = grid.w - rw - L.RAIL_GAP, h = grid.h }
    cells = U.rail_cells(rows, { x = grid.x, y = grid.y, w = rw, h = grid.h }, pane)
    U.fill(ST.border, 0.55 * pa, grid.x + rw + U.round(L.RAIL_GAP / 2), grid.y, u(1), grid.h)
    local any_open = false
    for i = 1, #rows do
      if rows[i].kind == "row" and cells.x[i] then any_open = true break end
    end
    if not any_open then
      local ht = U.fit("Select a category to unfold its settings.", V.fd, pane.w - u(8))
      U.at(ht, V.fd, ST.faint, 0.90 * pa,
        U.round(pane.x + (pane.w - V.fd:getWidth(ht)) / 2),
        U.mid(V.fd, pane.y, L.ROW_H))
    end
  else
    cells = U.cells(rows, grid, L.MAX_COLS, row_h, L.MAX_COLS_FIT)
  end
  HIT.cols, HIT.rows_per = cells.cols, cells.rows_per
  HIT.col_w, HIT.capacity = cells.col_w, cells.capacity

  for i = 1, #rows do
    local r = rows[i]
    local cx, cy, cw = cells.x[i], cells.y[i], cells.w[i]
    if not cx then
      HIT.vis[i] = false
    else
      local rh = cells.row_h or L.ROW_H
      HIT.rows[i], HIT.row_x[i], HIT.row_w[i], HIT.itemh[i] = cy, cx, cw, rh
      HIT.vis[i] = true
      local hovered = V.in_panel and U.hit(mx, my, cx, cy, cw, rh)
      local selected = i == sel

      if r.kind == "header" then
        local cnt = tostring(r.count)
        local cntw = V.fs:getWidth(cnt)
        if rail then

          local live = not r.collapsed
          if hovered or selected or live then
            U.fill(ST.surface_alt, (live and 1.0 or 0.6) * pa, cx, cy, cw, rh)
          end
          if live then U.fill(ST.accent, pa, cx, cy, 2, rh) end
          U.eyebrow(r.group, V.fs, cx + L.CELL_PAD, cy, rh,
            (live or selected) and ST.text or ST.muted, 0.94 * pa)
          U.at(cnt, V.fs, live and ST.muted or ST.faint, 0.95 * pa,
            cx + cw - L.CELL_PAD - cntw, U.mid(V.fs, cy, rh))
        else
          if hovered or selected then
            U.fill(ST.surface_alt, (selected and 1.0 or 0.7) * pa, cx, cy, cw, rh)
          end
          U.caret(cx + u(6), U.round(cy + rh / 2) - (r.collapsed and u(4) or u(2)), u(7),
            not r.collapsed, selected and ST.text or ST.muted, 0.95 * pa)
          local ex = U.eyebrow(r.group, V.fs, cx + u(20), cy, rh, ST.text, 0.94 * pa)
          local rule_x, rule_end = ex + u(12), cx + cw - u(10) - cntw - u(12)
          if rule_end > rule_x then
            U.fill(ST.border, 0.50 * pa, rule_x, U.round(cy + rh / 2), rule_end - rule_x, u(1))
          end
          U.at(cnt, V.fs, ST.muted, 0.95 * pa, cx + cw - u(10) - cntw, U.mid(V.fs, cy, rh))
        end

      elseif r.kind == "action" then


        local enabled = (r.action ~= "selftest") or V.st_avail
        if hovered or selected then
          U.fill(ST.surface_alt, (selected and 1.0 or 0.7) * pa, cx, cy, cw, rh)
        end
        if selected then U.fill(ST.accent, pa, cx, cy + u(4), u(2), rh - u(4) * 2) end
        U.fill(ST.border, 0.55 * pa, cx, cy, cw, u(1))
        local blabel = U.label(r.label)
        local lx = cx + L.CELL_PAD
        U.at(U.fit(blabel, V.fl, cw - L.CELL_PAD * 2 - u(14)), V.fl,
          enabled and ST.text or ST.faint, 0.97 * pa, lx, U.mid(V.fl, cy, rh))
        U.caret(cx + cw - L.CELL_PAD - u(7), U.round(cy + rh / 2) - u(3), u(7), false,
          enabled and ST.muted or ST.faint, 0.95 * pa)
        if r.action == "selftest" then
          local room = cw - L.CELL_PAD * 2 - u(20) - V.fl:getWidth(blabel)
          if V.fm:getWidth(V.st_value) <= room then
            U.at(V.st_value, V.fm, ST.faint, 0.95 * pa,
              cx + cw - L.CELL_PAD - u(16) - V.fm:getWidth(V.st_value), U.mid(V.fm, cy, rh))
          end
        end

      else
        local d = r.d
        row_chrome(cx, cy, cw, rh, hovered, selected, pa)

        local plain = static_value(d)
        local ctl_w
        if plain then
          ctl_w = math.min(L.VALUE_W * 2, math.floor(cw * 0.5))
        elseif d.values then
          ctl_w = bool_def(d) and L.TOGGLE_W or L.VALUE_W
        else
          ctl_w = L.SLIDER_W + u(12) + L.VALUE_W
        end
        local inc_x = cx + cw - L.CELL_PAD - L.STEP_W
        local ctl_x = (plain and (cx + cw - L.CELL_PAD) or (inc_x - u(4))) - ctl_w
        local dec_x = ctl_x - u(4) - L.STEP_W
        local ctl_y = U.round(cy + (rh - L.TOGGLE_H) / 2)
        HIT.ctl_x[i], HIT.ctl_w[i] = ctl_x, ctl_w

        local label_left = cx + L.CELL_PAD
        local label_w = math.max(u(24), (plain and ctl_x or dec_x) - label_left - u(10))
        U.at(U.fit(U.label(r.label), V.fl, label_w), V.fl, selected and ST.text or ST.muted, 0.97 * pa,
          label_left, U.mid(V.fl, cy, rh))

        if not plain and (hovered or selected) then
          HIT.dec_x[i], HIT.inc_x[i] = dec_x, inc_x
          local s = u(7)
          local ay = U.round(cy + (rh - s) / 2)
          local dh = V.in_panel and U.hit(mx, my, dec_x, cy, L.STEP_W, rh)
          local ih = V.in_panel and U.hit(mx, my, inc_x, cy, L.STEP_W, rh)
          U.arrow(dec_x + u(6), ay, s, true, dh and ST.accent or ST.faint, 0.95 * pa)
          U.arrow(inc_x + u(6), ay, s, false, ih and ST.accent or ST.faint, 0.95 * pa)
        else
          HIT.dec_x[i], HIT.inc_x[i] = nil, nil
        end

        if plain then
          local vt = U.fit(r.value, V.fm, ctl_w)
          U.at(vt, V.fm, ST.faint, 0.95 * pa, ctl_x + ctl_w - V.fm:getWidth(vt), U.mid(V.fm, cy, rh))
        elseif bool_def(d) then
          U.toggle(ctl_x, ctl_y, L.TOGGLE_W, L.TOGGLE_H, checkbox_on(Tuning.get_raw(d.key)),
            pa, U.flash01(r.di, V.now), hovered or selected)
        else
          local vt
          if d.values then
            vt = U.value(r.value)
          else
            local span = (d.max or 1) - (d.min or 0)
            local frac = 0
            if span > 0 then frac = ((tonumber(Tuning.get_raw(d.key)) or 0) - (d.min or 0)) / span end
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            U.slider(ctl_x, cy, L.SLIDER_W, rh, frac, pa, selected)
            vt = r.value .. (r.unit or "")
          end
          local vr, vg, vb, va
          if selected then
            vr, vg, vb, va = ST.text[1], ST.text[2], ST.text[3], 1.0
          else
            vr, vg, vb, va = ST.muted[1], ST.muted[2], ST.muted[3], 0.96
          end
          vr, vg, vb, va = U.flash(vr, vg, vb, va, r.di, V.now, pa)
          vt = U.fit(vt, V.fl, L.VALUE_W)
          U.rgba(vt, V.fl, vr, vg, vb, va, ctl_x + ctl_w - V.fl:getWidth(vt), U.mid(V.fl, cy, rh))
        end
      end
    end
  end
end

local function draw_colours(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa, mx, my = V.pa, V.mx, V.my
  local band = { x = V.content.x, y = V.content.y, w = V.content.w, h = V.content.h }

  U.at(U.fit(TXT.NOTE, V.fm, band.w), V.fm, ST.muted, 0.95 * pa, band.x, band.y)
  local used = V.fm:getHeight() + u(8)
  band.y, band.h = band.y + used, band.h - used

  local rw = math.min(math.floor(band.w * 0.30), U.btn_w(TXT.RESET_ALL, V.fm))
  local sz, gap = L.SWATCH, L.SWATCH_GAP
  local avail = math.max(sz, band.w - rw - u(24))
  local per_row = math.max(1, math.floor((avail + gap) / (sz + gap)))
  local sw_rows = math.ceil(#SWATCHES / per_row)
  local tool_h = math.max(L.CHIP_H, sw_rows * sz + (sw_rows - 1) * gap)
  HIT.sw_n = #SWATCHES
  for si = 1, #SWATCHES do
    local sx = band.x + ((si - 1) % per_row) * (sz + gap)
    local sy = band.y + math.floor((si - 1) / per_row) * (sz + gap)
    HIT.sw_rects[si] = { sx, sy, sz, sz }
    U.fill(SWATCH_RGB[si], pa, sx, sy, sz, sz, L.ROW_R)
    U.line(ST.border, 0.45 * pa, sx, sy, sz, sz, L.ROW_R)

    local hov = V.in_panel and U.hit(mx, my, sx, sy, sz, sz)
    if hov then
      U.line(ST.panel, 1.0 * pa, sx - u(1), sy - u(1), sz + u(1) * 2, sz + u(1) * 2, L.ROW_R)
      U.line(ST.text, 0.95 * pa, sx - u(3), sy - u(3), sz + u(3) * 2, sz + u(3) * 2)
    end
  end

  local n = #crows
  HIT.ra_x = band.x + band.w - rw
  HIT.ra_y = U.round(band.y + (tool_h - L.CHIP_H) / 2)
  HIT.ra_w, HIT.ra_h = rw, L.CHIP_H
  local ra_act = sel == n + 1 or (V.in_panel and U.hit(mx, my, HIT.ra_x, HIT.ra_y, rw, L.CHIP_H))
  U.button(HIT.ra_x, HIT.ra_y, rw, L.CHIP_H, TXT.RESET_ALL, V.fm, ra_act, true, pa)

  band.y, band.h = band.y + tool_h + u(10), band.h - tool_h - u(10)

  HIT.n = n + 1
  local cells = U.cells(crows, band, L.MAX_COLS_COLOUR)

  HIT.cols, HIT.rows_per = cells.cols, cells.rows_per
  HIT.col_w, HIT.capacity = cells.col_w, cells.capacity + 1
  HIT.hexw = V.fm:getWidth("CC")
  local hgap, hashw = HIT.hgap, V.fm:getWidth("#")

  for i = 1, n do
    local r = crows[i]
    local cx, cy, cw = cells.x[i], cells.y[i], cells.w[i]
    if not cx then
      HIT.vis[i] = false
    else
      local rh = L.ROW_H
      HIT.rows[i], HIT.row_x[i], HIT.row_w[i], HIT.itemh[i] = cy, cx, cw, rh
      HIT.vis[i] = true
      local hovered = V.in_panel and U.hit(mx, my, cx, cy, cw, rh)
      local selected = i == sel
      row_chrome(cx, cy, cw, rh, hovered, selected, pa)

      local ty = U.mid(V.fm, cy, rh)
      local chip_w, chip_h = u(20), u(14)
      local chip_x = cx + cw - L.CELL_PAD - chip_w
      local hash_x = chip_x - u(14) - (hashw + hgap + HIT.hexw * 3 + hgap * 2)
      HIT.hex_x[i] = hash_x + hashw + hgap

      U.at(U.fit(r.key, V.fm, math.max(u(24), hash_x - cx - L.CELL_PAD - u(8))), V.fm,
        selected and ST.text or ST.muted, 0.97 * pa, cx + L.CELL_PAD, ty)
      U.at("#", V.fm, ST.faint, 0.90 * pa, hash_x, ty)

      local editing = selected and edit_mode
      local typing = editing and edit_hex ~= ""
      local buf = typing and (edit_hex .. string.rep("_", 6 - #edit_hex)) or nil
      local caret = typing and math.min(3, math.floor(#edit_hex / 2) + 1) or edit_ch
      local hx = HIT.hex_x[i]
      for ch = 1, 3 do
        local seg
        if typing then seg = buf:sub(ch * 2 - 1, ch * 2)
        else seg = (ch == 1 and r.hr) or (ch == 2 and r.hg) or r.hb end
        local vr, vg, vb, va
        if editing and ch == caret then
          vr, vg, vb, va = ST.text[1], ST.text[2], ST.text[3], 0.98
          U.fill(ST.accent, 0.95 * pa, hx, cy + rh - u(7), HIT.hexw, u(1))
        elseif typing then
          vr, vg, vb, va = ST.text[1], ST.text[2], ST.text[3], 0.90
        elseif selected then
          vr, vg, vb, va = ST.text[1], ST.text[2], ST.text[3], 0.96
        else
          vr, vg, vb, va = ST.muted[1], ST.muted[2], ST.muted[3], 0.92
        end
        vr, vg, vb, va = U.flash(vr, vg, vb, va, i, V.now, pa)
        U.rgba(seg, V.fm, vr, vg, vb, va, hx, ty)
        hx = hx + HIT.hexw + hgap
      end

      local chip_y = U.round(cy + (rh - chip_h) / 2)
      U.fill(r.color, pa, chip_x, chip_y, chip_w, chip_h, L.ROW_R)
      U.line(ST.border, 0.55 * pa, chip_x, chip_y, chip_w, chip_h, L.ROW_R)
    end
  end

  HIT.rows[n + 1], HIT.row_x[n + 1] = HIT.ra_y, HIT.ra_x
  HIT.row_w[n + 1], HIT.itemh[n + 1] = HIT.ra_w, HIT.ra_h
  HIT.vis[n + 1] = true
end

local SIZE_DESC = {
  [-5] = { "Resize the main HUD panel without moving it.", "NEURO_OVERLAY_SCALE_RIGHT" },
  [-4] = { "Resize the shop HUD panel without moving it.", "NEURO_OVERLAY_SCALE_LEFT" },
  [-7] = { "Resize the buy receipt and the centre card showcase.", "NEURO_CENTER_SCALE" },
}

local function draw_desc(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa = V.pa
  local dtxt, hint, meta
  if page ~= 4 then
    if page == 1 and sel <= 0 then
      local on_shop = place_target == "shop"
      local tname = on_shop and "shop HUD" or "main HUD"
      local shop_auto = on_shop
        and tostring(Tuning.get_raw("NEURO_SHOP_ANCHOR") or "auto") == "auto"
      if sel == -6 then
        dtxt = "Choose which panel the anchor and offset controls place: the main HUD or the shop HUD."
        hint = "LEFT/RIGHT or click a segment; the highlighted panel in the preview is the one that moves."
        meta = "Target: " .. (on_shop and "SHOP HUD" or "MAIN HUD")
      elseif sel == -3 then
        if on_shop then
          dtxt = "Choose where the shop HUD is anchored. AUTO keeps it opposite the main HUD."
        else
          dtxt = "Choose where the main HUD is anchored. An AUTO shop panel follows to the opposite side."
        end
        hint = "Click a point in the preview, or use LEFT/RIGHT to cycle through every anchor."
        meta = "Current: " .. tostring(Tuning.get_raw(
          on_shop and "NEURO_SHOP_ANCHOR" or "NEURO_OVERLAY_ANCHOR") or "auto"):upper()
      elseif sel == -2 or sel == -1 then
        local axis = sel == -2 and "X" or "Y"
        dtxt = "Move the " .. tname
          .. (sel == -2 and " horizontally" or " vertically")
          .. " from its anchored position."
        hint = shop_auto
          and "Ignored while the shop anchor is AUTO -- pick a shop anchor first."
          or "Drag or click the slider; SHIFT+LEFT/RIGHT changes the value by 5%."
        meta = string.format("Current: %+d%%  |  Default: 0%%",
          tonumber(Tuning.get_raw(
            (on_shop and "NEURO_SHOP_OFFSET_" or "NEURO_OVERLAY_OFFSET_") .. axis)) or 0)
      elseif SIZE_DESC[sel] then
        dtxt = SIZE_DESC[sel][1]
        hint = "Drag the slider, or LEFT/RIGHT for 0.05x; SHIFT changes it by 0.25x."
        meta = string.format("Current: %.2fx  |  Default: 1.00x",
          tonumber(Tuning.get_raw(SIZE_DESC[sel][2])) or 1)
      else
        dtxt = "Restore the shipped layout for both panels."
        hint = "Sets both anchors to AUTO, every offset to 0% and both sizes to 1.00x."
        meta = "MAIN + SHOP: AUTO  |  X 0%  |  Y 0%  |  SIZE 1.00x"
      end
    else
    local it = rows and rows[sel]
    if it then
      if it.kind == "row" and it.d then
        dtxt = DESCS[it.d.key] or "No description available"
        hint = DESCS["EXAMPLE_" .. it.d.key] or ("Config key: " .. it.d.key)
        local current = tostring(it.value or "") .. tostring(it.unit or "")
        if parent_off(it.d) then
          meta = "Current: " .. current .. "  |  disabled by " .. tostring(it.d.parent)
        elseif it.d.readonly then
          meta = "Current: " .. current .. "  |  read-only"
        else
          meta = "Current: " .. current .. "  |  Default: " .. tostring(it.def)
        end
        if it.d.note then meta = meta .. "  |  " .. it.d.note end
      elseif it.kind == "header" then
        dtxt = DESCS[it.group] or "Settings in this category."
        hint = tostring(it.count) .. " settings  |  Enter or click to fold/unfold"
      elseif it.kind == "action" then
        if it.action == "advanced" then
          dtxt = "Open display and diagnostic settings."
          hint = "Timers and cooldowns live on the separate TIMING page."
        elseif it.action == "runtime_reset" then
          dtxt = "Restore every system setting to its default."
          hint = "Restart-only settings still require a restart after saving."
        else
          dtxt = "Run the in-engine contract and scenario checks."
          hint = "The test result appears here when the run finishes."
          meta = "Status: " .. V.st_value
        end
      end
    end
    end
  else
    local cr = crows and crows[sel]
    if cr then
      dtxt = "Palette entry " .. cr.key .. " for persona " .. string.upper(Palette.persona()) .. "."
      hint = edit_mode and "Type six hex digits, or nudge the highlighted channel with LT/RT."
        or "Enter or click a hex pair to edit; click a preset chip to apply it."
      meta = "Current: #" .. cr.hr .. cr.hg .. cr.hb .. "  |  Default: " .. cr.def
    else
      dtxt = "Restore every colour of this persona to its shipped value."
      hint = "Only this persona is affected; the other skins keep their overrides."
    end
  end

  local dx, dy = V.px + L.PAD, V.desc_top + u(4)
  local dw, dh = V.inner_w, L.DESC_H - u(4) * 2
  card_shadow(dx, dy, dw, dh, pa)
  U.fill(ST.surface, 1.0 * pa, dx, dy, dw, dh, L.ROW_R)
  U.line(ST.border, 0.90 * pa, dx, dy, dw, dh, L.ROW_R)
  U.fill(ST.accent_dim, pa, dx, dy, u(2), dh)

  local lh, mh = V.fd:getHeight(), V.fm:getHeight()
  local tw = dw - u(16) * 2
  local body = dtxt and U.wrap(dtxt, V.fd, tw, 2) or {}


  local total = #body * (lh + u(1))
  if hint then total = total + u(4) + lh end
  if meta then total = total + u(3) + mh end
  local ly = U.round(dy + (dh - total) / 2)
  for _, line in ipairs(body) do
    U.at(line, V.fd, ST.text, 1.0 * pa, dx + u(16), ly)
    ly = ly + lh + u(1)
  end
  if hint then
    ly = ly + u(4)
    U.at(U.fit(hint, V.fd, tw), V.fd, ST.muted, 1.0 * pa, dx + u(16), ly)
    ly = ly + lh
  end
  if meta then
    ly = ly + u(3)
    U.at(U.fit(meta, V.fm, tw), V.fm, ST.faint, 1.0 * pa, dx + u(16), ly)
  end
end

local function draw_footer(V)
  local L, ST, U = LAYOUT, STYLE, UI
  local pa = V.pa
  local keys
  if page == 1 then keys = TXT.FOOTERS.basics
  elseif page == 2 then keys = V.st_running and TXT.FOOTERS.advanced_run or TXT.FOOTERS.advanced
  elseif page == 3 then keys = TXT.FOOTERS.timing
  elseif page == 4 then keys = edit_mode and TXT.FOOTERS.colours_edit or TXT.FOOTERS.colours
  else keys = TXT.FOOTERS.system end

  local fy = V.footer_top
  local fx = V.inner_x
  local limit = V.px + V.pw - L.PAD
  local ty = U.mid(V.fm, fy, L.FOOTER_H)

  local function hint(cap, what)
    local kw = tracked_width(cap, L.TRACK, V.fm)
    local lw = V.fm:getWidth(what)
    if fx + kw + u(7) + lw > limit then return false end
    love.graphics.setFont(V.fm)
    set_col(ST.faint, 0.95 * pa)
    print_tracked(cap, fx, ty, L.TRACK, V.fm)
    U.at(what, V.fm, ST.muted, 0.90 * pa, fx + kw + u(7), ty)
    fx = fx + kw + u(7) + lw + u(18)
    return true
  end

  for i = 1, #keys do
    if not hint(keys[i][1], keys[i][2]) then return end
  end
  if mouse_seen then
    for i = 1, #TXT.MOUSE do
      if not hint(TXT.MOUSE[i][1], TXT.MOUSE[i][2]) then return end
    end
  end
end


local function set_scale(sw, sh)
  local user = tonumber(Tuning.get("NEURO_PANEL_SCALE")) or 1
  local fit = math.min(sw / SCALE_REF_W, sh / SCALE_REF_H)
  local raw = math.min(fit, SCALE_MAX) * user
  local next_scale = math.floor(raw * 20) / 20
  if next_scale > fit then next_scale = math.floor(fit * 20) / 20 end
  if next_scale <= 0 then next_scale = 0.05 end
  if next_scale == SCALE then return end
  SCALE = next_scale
  resolve_layout()
  resolve_fonts()
  _wrap_cache, _wrap_n = {}, 0
end

function Panel.draw()
  if not (love and love.graphics) then return end
  HIT.valid = false
  local st_running = track_selftest()
  local now = now_s()
  local fade_d = Motion.FAST
  local closing = not open and close_at > 0 and (now - close_at) < fade_d
  if not (G and G.NEURO and G.NEURO.llm_paused) and not open and not closing then return end

  local U, L, ST = UI, LAYOUT, STYLE
  local f_label = font("label")
  if not f_label then return end
  local f_micro = font("micro")
  local prev_font = love.graphics.getFont()
  local sw = tonumber(love.graphics.getWidth()) or 0
  local sh = tonumber(love.graphics.getHeight()) or 0
  if sw <= 0 then sw = 1920 end
  if sh <= 0 then sh = 1080 end
  set_scale(sw, sh)
  resolve_accent()

  local pa
  if open then
    pa = Motion.anim01(now - open_at, fade_d)
  else
    pa = 1 - Motion.anim01(now - close_at, fade_d)
  end
  local ba = open and Motion.anim01(now - open_at - fade_d, fade_d) or pa

  if open or closing then
    U.fill(ST.scrim, 0.55 * pa, 0, 0, sw, sh)
  end
  do
    local bw = tracked_width(TXT.BADGE, L.TRACK, f_micro) + u(14) * 2
    local bh = f_micro:getHeight() + u(14)
    local bx = math.floor((sw - bw) / 2)
    local by = u(10)
    U.fill(ST.scrim, 0.55 * ba, bx + u(2), by + u(3), bw, bh)
    U.fill(ST.header, 0.98 * ba, bx, by, bw, bh)
    U.line(ST.border, 0.90 * ba, bx, by, bw, bh)
    love.graphics.setFont(f_micro)
    set_col(ST.muted, 0.96 * ba)
    print_tracked(TXT.BADGE, bx + u(14), U.mid(f_micro, by, bh), L.TRACK, f_micro)
  end

  if not open and not closing then
    love.graphics.setFont(prev_font)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if page == 4 and crows_persona ~= Palette.persona() then crows_dirty = true end
  if rows_dirty or not rows then rebuild_rows() end
  if (crows_dirty or not crows) and page == 4 then rebuild_crows() end

  local pw = math.min(L.PANEL_W, sw - L.MARGIN_X * 2)
  local ph = math.min(L.PANEL_H, sh - L.MARGIN_Y * 2)
  local px = math.floor((sw - pw) / 2)
  local py = math.floor((sh - ph) / 2) + U.round((1 - pa) * L.OPEN_SLIDE)
  local mx, my = mouse_pos()
  local band_top = py + L.HEADER_H + L.TABS_H
  local footer_top = py + ph - L.FOOTER_H
  local desc_top = footer_top - L.DESC_H

  clear_hit()
  HIT.px, HIT.py, HIT.pw, HIT.ph = px, py, pw, ph
  HIT.step_w = L.STEP_W
  HIT.hgap = L.HEX_GAP
  HIT.cx = px + L.PAD
  HIT.cy = band_top + L.PAD
  HIT.cw = pw - L.PAD * 2
  HIT.ch = desc_top - band_top - L.PAD * 2

  local V = {
    px = px, py = py, pw = pw, ph = ph, pa = pa, now = now,
    sw = sw, sh = sh,
    mx = mx, my = my, in_panel = open and in_rect(mx, my, px, py, pw, ph),
    inner_x = px + L.PAD, inner_w = pw - L.PAD * 2,
    band_top = band_top, desc_top = desc_top, footer_top = footer_top,
    content = { x = HIT.cx, y = HIT.cy, w = HIT.cw, h = HIT.ch },
    ft = font("title"), fl = f_label, ftab = font("tab"), fd = font("desc"),
    fs = font("section"), fm = f_micro,
    st_running = st_running,
    st_avail = SelfTest.available(),
  }
  V.st_value = st_running and SelfTest.status() or st_done or (V.st_avail and "READY" or "MENU ONLY")

  U.fill(ST.scrim, 0.18 * pa, px - u(10), py - u(5), pw + u(20), ph + u(24))
  U.fill(ST.scrim, 0.32 * pa, px - u(4), py, pw + u(8), ph + u(12))
  U.fill(ST.scrim, 0.62 * pa, px + u(1), py + u(4), pw - u(2), ph + u(4))
  U.fill(ST.panel, 0.995 * pa, px, py, pw, ph, L.RADIUS)
  U.fill(ST.header, pa, px + u(1), py + u(1), pw - u(1) * 2, L.HEADER_H, L.RADIUS)
  U.fill(ST.border, 0.80 * pa, px + u(1), py + u(1) + L.HEADER_H, pw - u(1) * 2, u(1))
  U.line(ST.border, 0.90 * pa, px, py, pw, ph, L.RADIUS)

  draw_header(V)
  draw_tabs(V)

  local clip = U.push(px + u(1), band_top, pw - u(1) * 2, desc_top - band_top)
  if page == 4 then draw_colours(V) else draw_settings(V) end
  U.pop(clip)

  draw_desc(V)
  draw_footer(V)

  HIT.valid = open

  love.graphics.setFont(prev_font)
  love.graphics.setColor(1, 1, 1, 1)
end

if rawget(_G, "NEURO_TEST") then
  Panel._test = {
    reveal = reveal,
    hit = HIT,
    row_at = row_at,
    scale = function() return SCALE end,
    preview_geometry = preview_geometry,
    place_order = PLACE_ORDER,
    place_target = function() return place_target end,
    hex_channel_at = hex_channel_at,
    swatch_at = swatch_at,
    swatches = SWATCHES,
    bool_def = bool_def,
    checkbox_on = checkbox_on,
    draw_toggle = draw_toggle,
    style = STYLE,
    layout = LAYOUT,
    nice_label = nice_label,
    nice_value = nice_value,
    wrap_lines = wrap_lines,
    flash01 = flash01,
    text_mid = text_mid,
    fonts = function() return FONT_PX end,
    tabs = TXT.TABS,
    content_rect = function() return HIT.cx, HIT.cy, HIT.cw, HIT.ch end,
    item_rect = function(i) return HIT.row_x[i], HIT.rows[i], HIT.row_w[i], HIT.itemh[i] end,
    grid = function() return HIT.cols, HIT.rows_per, HIT.col_w, HIT.capacity end,
    swatch_rect = function(i) return HIT.sw_rects[i] end,
    description = function(key) return DESCS[key] end,
    reset_mouse = function() mouse_seen = false end,
    state = function() return page, sel, edit_mode, edit_ch end,
    edit_hex = function() return edit_hex end,
    rows = function() return rows end,
    crows = function() return crows end,
    collapsed = function() return collapsed end,
  }
end

return Panel
