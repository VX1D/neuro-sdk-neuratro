local Tuning = require("core.tuning")
local Palette = require("render.palette")
local S = require("hud.state")
local DebugStats = require("render.debug_stats")
local SelfTest = require("core.selftest")
local Motion = require("render.neuro-anim").Motion
local Prims = require("hud.prims")
local set_col = Prims.set_col
local round = Prims.round
local clear_force_state = require("force.force_helpers").clear_force_state

local Panel = {}

local open = false
local page = 1
local sel = 1
local rows = nil
local rows_dirty = true
local crows = nil
local crows_dirty = true
local crows_persona = nil
local csuffix = "// LLM PAUSED"
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

local SAVED_HOLD = Motion.SLOW * 2

local HIT = {
  valid = false,
  px = 0, py = 0, pw = 0, ph = 0,
  row_h = 0, n = 0, rows = {}, itemh = {},
  val_x = 0, def_x = 0,
  arrow_w = 12, la_x = 0, ra_x = 0,
  hex_x = 0, hexw = 0, hgap = 2,
  tab_y = 0, tab_h = 0,
  t1_x = 0, t1_w = 0, t2_x = 0, t2_w = 0, t3_x = 0, t3_w = 0,
  cl_x = 0, cl_y = 0, cl_w = 0, cl_h = 0,
  pr_x = 0, pr_w = 0,
  sw_y = 0, sw_h = 0, sw = 0, sw_gap = 0, sw_x = 0, sw_n = 0,
}

local PERSONA_ORDER = { "evil", "neuro", "hiyori" }

local SWATCHES = {
  "FFFFFF", "C8C8C8", "808080", "202028", "000000",
  "FF4D94", "E5202B", "F97316", "FFD700", "3CB371",
  "00E5FF", "5AA0FF", "9B72E6", "B87333",
}

-- pages 1/3 share the row machinery; page 2 (COLOURS) has its own path
local function active_defs()
  if page == 3 then return Tuning.runtime_entries() end
  return Tuning.entries()
end

local collapsed = {}
local function group_collapsed(g)
  if page == 3 then return false end
  local v = collapsed[g]
  if v == nil then return g ~= "MASTER" end
  return v
end
local function set_all_collapsed(state)
  local defs = active_defs()
  for i = 1, #defs do
    local g = defs[i].group
    if g then collapsed[g] = state end
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
  elseif d.key == "NEURO_REDUCED_MOTION" then
    Motion.reduced = Tuning.bool(d.key)  -- hot-path field: sync now, not lazily via Tuning.get
  elseif d.key == "NEURO_PERSONA" then
    if G and G.NEURO then G.NEURO.persona = Tuning.get_raw(d.key) end
  end
end

local _nheaders = 0
local _nrows = 0
local function rebuild_rows()
  local defs = active_defs()
  rows = {}
  _nheaders = 0
  _nrows = 0
  local counts = {}
  for i = 1, #defs do
    local g = defs[i].group or ""
    counts[g] = (counts[g] or 0) + 1
  end
  local prev_group = nil
  for i = 1, #defs do
    local d = defs[i]
    local g = d.group or ""
    if g ~= prev_group then
      _nheaders = _nheaders + 1
      rows[#rows + 1] = { kind = "header", group = g, count = counts[g], collapsed = group_collapsed(g) }
      prev_group = g
    end
    if not group_collapsed(g) then
      -- get_raw, not get: get applies the cooldown scale; panel edits the base
      local v, unit = fmt_value(d, Tuning.get_raw(d.key))
      _nrows = _nrows + 1
      rows[#rows + 1] = {
        kind = "row",
        di = i,
        d = d,
        label = d.label,
        value = v,
        unit = unit,
        def = d.readonly and "" or ("[" .. fmt_value(d, d.default) .. (d.unit or "") .. "]"),
      }
    end
  end
  rows[#rows + 1] = { kind = "action" }
  rows_dirty = false
end

function Panel.reveal(key)
  local defs = active_defs()
  for i = 1, #defs do
    if defs[i].key == key then
      if defs[i].group then collapsed[defs[i].group] = false end
      rebuild_rows()
      for vi = 1, #rows do
        local it = rows[vi]
        if it.kind == "row" and it.di == i then sel = vi; return true end
      end
      return false
    end
  end
  return false
end

local function hex2(v)
  return string.format("%02X", round(v * 255))
end

local function rebuild_crows()
  local pk = Palette.persona()
  crows_persona = pk
  csuffix = "// " .. pk:upper() .. " // LLM PAUSED"
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

function Panel.toggle()
  open = not open
  if G and G.NEURO then G.NEURO.llm_paused = open or nil end
  if open then
    page = 1
    sel = 1
    edit_mode = false
    rows_dirty = true
    crows_dirty = true
    flash_text = nil
    vflash_at = 0
    open_at = now_s()
  else
    close_at = now_s()
    edit_mode = false
    HIT.valid = false
    Tuning.save()
    if G and G.NEURO then
      -- clear stale inflight: a force rejected during pause never settles and would block resume
      clear_force_state()
      require("core.neuro_lifecycle").mark_force_dirty()
    end
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

local function row_at(x, y)
  if not HIT.valid then return nil end
  if x < HIT.px or x >= HIT.px + HIT.pw then return nil end
  for i = 1, HIT.n do
    local ry = HIT.rows[i]
    local rh = (HIT.itemh and HIT.itemh[i]) or HIT.row_h
    if ry and y >= ry and y < ry + rh then return i end
  end
  return nil
end

local function hex_channel_at(x)
  for ch = 1, 3 do
    local sx = HIT.hex_x + (ch - 1) * (HIT.hexw + HIT.hgap)
    if x >= sx and x < sx + HIT.hexw + HIT.hgap then return ch end
  end
  return nil
end

local function swatch_at(x, y)
  if HIT.sw_n <= 0 or y < HIT.sw_y or y >= HIT.sw_y + HIT.sw_h then return nil end
  for i = 1, HIT.sw_n do
    local sx = HIT.sw_x + (i - 1) * (HIT.sw + HIT.sw_gap)
    if x >= sx and x < sx + HIT.sw then return i end
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

local function draw_checkbox(x, y, size, on, a, ACC)
  love.graphics.setLineWidth(1)
  if on then
    set_col(ACC, 0.95 * a)
    love.graphics.rectangle("fill", x + 2, y + 2, size - 4, size - 4)
  end
  set_col(ACC, 0.90 * a)
  love.graphics.rectangle("line", x, y, size, size)
end

local function page1_adjust(i, dir, mult, now)
  local d = active_defs()[i]
  if not d or d.readonly or d.panel == false then return end
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
    -- round to 1e-6 so repeated float nudges don't write crud (0.30000000000000004) to the saved env
    local nv = Tuning.get_raw(d.key) + d.step * dir * (mult or 1)
    nv = round(nv * 1e6) / 1e6
    Tuning.set(d.key, nv)
  end
  vflash_at = now
  vflash_row = i
  rows_dirty = true
end

local function trigger_selftest(now)
  if not SelfTest.available() then return end
  st_done = nil
  local ok, err = SelfTest.start()
  if not ok then
    flash_text = tostring(err or "SELF-TEST FAILED TO START")
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
  Tuning.save()
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
  Tuning.save()
  flash_text = "RUNTIME RESET"
  flash_at = now
  vflash_at = now
  rows_dirty = true
end

local function set_page(p)
  if edit_mode then
    edit_mode = false
    Tuning.save()
  end
  page = p
  sel = 1
  vflash_at = 0
  rows_dirty = true
end

local PANEL_KEYS = {
  up = true, down = true, left = true, right = true,
  s = true, r = true, c = true, tab = true, ["return"] = true, kpenter = true,
}

local function page1_key(key, now)
  if rows_dirty or not rows then rebuild_rows() end
  local n = #rows
  if sel > n or sel < 1 then sel = 1 end
  local it = rows[sel]
  if key == "up" then
    sel = sel > 1 and sel - 1 or n
  elseif key == "down" then
    sel = sel < n and sel + 1 or 1
  elseif key == "c" then
    set_all_collapsed(not shift_down())
    rebuild_rows()
    if sel > #rows then sel = #rows end
  elseif key == "return" or key == "kpenter" then
    if it and it.kind == "action" then
      if page == 3 then reset_all_runtime(now) else trigger_selftest(now) end
    elseif it and it.kind == "header" then
      collapsed[it.group] = not group_collapsed(it.group)
      rebuild_rows()
    end
  elseif key == "left" or key == "right" then
    if not it then return end
    if it.kind == "header" then
      collapsed[it.group] = (key == "left")
      rebuild_rows()
    elseif it.kind == "row" then
      page1_adjust(it.di, key == "left" and -1 or 1, shift_down() and 5 or 1, now)
    end
  elseif key == "s" then
    local ok = Tuning.save()
    flash_text = ok and "SAVED" or "SAVE FAILED"
    flash_at = now
  elseif key == "r" then
    if it and it.kind == "row" then
      local d = active_defs()[it.di]
      Tuning.reset(d.key)
      apply_live(d)
      vflash_at = now
      vflash_row = it.di
      rows_dirty = true
    end
  end
end

local function page2_key(key, now)
  local pk = Palette.persona()
  local ckeys = Palette.color_keys(pk)
  local nrows = #ckeys + 1
  if sel > nrows then sel = 1 end
  if key == "s" then
    local ok = Tuning.save()
    flash_text = ok and "SAVED" or "SAVE FAILED"
    flash_at = now
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
      Tuning.save()
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
      Tuning.save()
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
    Tuning.save()
    vflash_at = now
    vflash_row = sel
    crows_dirty = true
  end
end

function Panel.keypressed(key)
  if not open then return false end
  local running = SelfTest.running()
  -- swallow hex digits + backspace while editing so they don't leak to the game
  local hex_typing = page == 2 and edit_mode and (is_hex_char(key) or key == "backspace")
  if not (PANEL_KEYS[key] or hex_typing or (key == "escape" and edit_mode) or (key == "a" and running)) then
    return false
  end
  local now = now_s()
  if key == "a" and running and not hex_typing then
    SelfTest.abort()
    return true
  end
  if key == "tab" then
    set_page(page % 3 + 1)
    return true
  end
  if page == 2 then
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
  if in_rect(x, y, HIT.pr_x, HIT.tab_y, HIT.pr_w, HIT.tab_h) then
    local cur = Palette.persona()
    local idx = 1
    for i2, p2 in ipairs(PERSONA_ORDER) do if p2 == cur then idx = i2 end end
    local step = (button == 2) and -1 or 1
    local nxt = PERSONA_ORDER[((idx - 1 + step) % #PERSONA_ORDER) + 1]
    if G and G.NEURO then G.NEURO.persona = nxt end
    return true
  end
  if button == 1 and y >= HIT.tab_y and y < HIT.tab_y + HIT.tab_h then
    if x >= HIT.t1_x and x < HIT.t1_x + HIT.t1_w then
      if page ~= 1 then set_page(1) end
      return true
    end
    if x >= HIT.t2_x and x < HIT.t2_x + HIT.t2_w then
      if page ~= 2 then set_page(2) end
      return true
    end
    if x >= HIT.t3_x and x < HIT.t3_x + HIT.t3_w then
      if page ~= 3 then set_page(3) end
      return true
    end
  end
  if page == 2 and button == 1 then
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
  local i = row_at(x, y)
  if not i then return true end
  if page ~= 2 then
    sel = i
    local it = rows and rows[i]
    if not it then return true end
    if it.kind == "action" then
      if button == 1 then
        if page == 3 then reset_all_runtime(now) else trigger_selftest(now) end
      end
      return true
    end
    if it.kind == "header" then
      if button == 1 then
        collapsed[it.group] = not group_collapsed(it.group)
        rebuild_rows()
        if sel > #rows then sel = #rows end
      end
      return true
    end
    local d = it.d
    local mult = shift_down() and 5 or 1
    if in_rect(x, y, HIT.la_x, HIT.rows[i], HIT.arrow_w, HIT.row_h) then
      page1_adjust(it.di, -1, mult, now)
    elseif in_rect(x, y, HIT.ra_x, HIT.rows[i], HIT.arrow_w, HIT.row_h) then
      page1_adjust(it.di, 1, mult, now)
    elseif x >= HIT.val_x and d.values then
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
  if edit_mode and sel ~= i then Tuning.save() end
  sel = i
  if button == 2 then
    if edit_mode then
      edit_mode = false
      Tuning.save()
    end
    return true
  end
  local ch = hex_channel_at(x)
  edit_mode = true
  edit_hex = ""
  if ch then
    edit_ch = ch
  elseif edit_ch < 1 or edit_ch > 3 then
    edit_ch = 1
  end
  return true
end

function Panel.wheelmoved(_, wy)
  if not open or not HIT.valid or not wy or wy == 0 then return false end
  local x, y = mouse_pos()
  if not in_rect(x, y, HIT.px, HIT.py, HIT.pw, HIT.ph) then return false end
  mouse_seen = true
  local i = row_at(x, y)
  if not i then return true end
  local now = now_s()
  local dir = wy > 0 and 1 or -1
  local mult = shift_down() and 5 or 1
  if page ~= 2 then
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

local BADGE_TEXT = "LLM PAUSED (F8)"
local TAB_1 = "TUNING"
local TAB_2 = "COLOURS"
local TAB_3 = "RUNTIME"
local SUFFIX_1 = "// LLM PAUSED"
local CLOSE_TXT = "[X]"
local ST_LABEL = "RUN SELF-TEST"
local RESET_RUNTIME_LABEL = "RESET ALL RUNTIME"
local RESET_ALL_LABEL = "RESET ALL COLOURS"
local COLOUR_NOTE = "Colour grading aid — tune against your stream capture, values persist per persona."
local DESCS = {
  NEURO_SPEED_MULT = "Scales the AI's hover + post-action delays (higher = slower)",
  NEURO_COOLDOWN_SCALE = "Multiplier applied to every cooldown at once",
  NEURO_AUTO_TUNE = "Auto-scale cooldowns to Balatro's game speed (stream-tuned)",
  NEURO_CD_PRESET = "Pin a speed profile, or 'auto' to follow game speed",
  NEURO_REDUCED_MOTION = "Turn off HUD animations (accessibility / perf)",
  NEURO_CTX_SPLIT = "Send context as stable + volatile channels",
  NEURO_STATE_VERBOSE = "Include verbose state text in the AI's context",
  NEURO_FORCE_ONLY = "AI may only take forced actions (no free actions)",
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
  NEURO_SHOP_BUY_DELAY = "Delay before a shop buy resolves (game clock)",
  NEURO_SHOP_BUY_BLOCK = "Block new actions this long after a buy",
  NEURO_PACK_PICK_DELAY = "Delay before a pack pick resolves (game clock)",
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
  NEURO_FORCE_STALL_SECONDS = "Re-arm a force if it stalls this long (watchdog)",
  NEURO_STAGING_FAILSAFE = "Cancel a stuck staged action after this long",
  NEURO_GAMEOVER_COOLDOWN = "Hold on the game-over screen before acting",
  NEURO_SHOP_BUY_WATCHDOG_GRACE = "Extra grace before the buy watchdog trips",
  NEURO_PACK_PICK_WATCHDOG_GRACE = "Extra grace before the pack-pick watchdog trips",
  NEURO_DEFER_WINDOW_MIN = "Min window protecting a just-failed action",
  NEURO_AUTO_LOGIN_DELAY = "Auto-pick a persona after this long idle at menu",
  NEURO_LOGIN_ANIM_BLOCK = "Don't force actions during the login animation",
  NEURO_STATE_INTERVAL = "How often game state is written to context",
  NEURO_HOVER_PER_CARD = "Hover time per card before a play / discard",
  NEURO_HOVER_SHOP = "Hover time on a shop item before buying",
  NEURO_HOVER_DEFAULT = "Default hover time before executing",
  NEURO_HOLD_ALL_SELECTED = "Hold after all cards selected, before playing",
  NEURO_CTX_CACHE_TTL = "How long a built context is reused before rebuild",
  NEURO_REREGISTER_THROTTLE = "Throttle repeated action re-registration",
  NEURO_JOKER_INFO_WINDOW = "Show full joker detail this long after joker_info",
  NEURO_OVERLAY_SCALE_RIGHT = "Size of the right HUD panel",
  NEURO_OVERLAY_SCALE_LEFT = "Size of the left HUD panel",
  NEURO_DEBUG_OVERLAY = "On-screen debug stats (off / compact / expanded)",
  NEURO_PERSONA = "Character skin -- reload to reskin",
  NEURO_ENABLE = "Whether the SDK bridge is active (read-only)",
  NEURO_IPC_DIR = "IPC folder used to talk to the bridge (read-only)",
  NEURO_DEBUG = "Verbose debug logging to file",
  NEURO_TRACE = "Crash-trace logging (read-only)",
  NEURO_PERF_LOG = "Write FPS / memory samples to disk",
  NEURO_AI_CARD_GLOW = "Glow the card the AI is hovering",
  NEURO_OVERLAY_DEV = "Hot-reload HUD files on change (dev)",
  NEURO_STAGING_DEBUG = "Draw the staging hover/execute debug overlay",
  NEURO_OUTBOX_TRUNCATE_ON_STARTUP = "Clear the outbox file on boot",
  NEURO_INBOX_TRUNCATE_ON_STARTUP = "Clear the inbox file on boot",
  NEURO_SELFTEST_ON_BOOT = "Run the in-engine self-test suite at boot",
  NEURO_SELFTEST_PACK = "Run only the pack-launch self-test scenario",
  NEURO_SELFTEST_FILTER = "Only run self-test cases matching this text",
  NEURO_SMALL_REGRESSION = "Run the fixed LLM task battery at boot (small regression check)",
}

local FOOTER_1 = "UP/DN nav   LT/RT edit   C fold all   S save   R reset   TAB page   F8 exit"
local FOOTER_3 = "UP/DN nav   LT/RT toggle   S save   R reset   TAB page   F8 exit"
local FOOTER_1_RUN = "UP/DN nav   LT/RT edit   A abort   S save   R reset   TAB page   F8 exit"
local FOOTER_2 = "UP/DN nav   ENTER edit   R reset   S save   TAB page   F8 exit"
local FOOTER_2_EDIT = "TYPE 6 HEX   BKSP del   LT/RT nudge   UP/DN channel   ENTER/ESC done"
local MOUSE_HINT = "  //  MOUSE: CLICK ROW  < > STEP  WHEEL (SHIFT X5)  RMB BACK"

local _footer_mouse = {}
local function footer_with_mouse(s)
  local m = _footer_mouse[s]
  if not m then
    m = s .. MOUSE_HINT
    _footer_mouse[s] = m
  end
  return m
end

local print_tracked = Prims.print_tracked
local tracked_width = Prims.tracked_width

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

local function selflash(vr, vg, vb, va, i, now, pa)
  if i == vflash_row and vflash_at > 0 then
    local k = 1 - Motion.anim01(now - vflash_at, Motion.dur(Motion.MED))
    if k > 0 then
      vr, vg, vb = vr + (1 - vr) * k, vg + (1 - vg) * k, vb + (1 - vb) * k
      va = va + (1 - va) * k
    end
  end
  return vr, vg, vb, va * pa
end

function Panel.draw()
  if not (love and love.graphics) then return end
  HIT.valid = false
  local st_running = track_selftest()
  local now = now_s()
  local fade_d = Motion.dur(Motion.FAST)
  local closing = not open and close_at > 0 and (now - close_at) < fade_d
  if not (G and G.NEURO and G.NEURO.llm_paused) and not open and not closing then return end
  local pal = Palette.pal()
  local font = S.panel_font or love.graphics.getFont()
  local font_small = S.panel_font_small or font
  if not font then return end
  local prev_font = love.graphics.getFont()

  local U = 4
  local GUT = 12
  local VAL_W = 168
  local DEF_W = 68
  local bg = pal.PANEL_BG or pal.BG
  local ACC = pal.ACCENT
  local FR = pal.FRAME or pal.PRIMARY
  local FRD = pal.FRAME_DIM or FR
  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()
  local mx, my = mouse_pos()

  local pa
  if open then
    pa = Motion.anim01(now - open_at, fade_d)
  else
    pa = 1 - Motion.anim01(now - close_at, fade_d)
  end
  local ba = open and Motion.anim01(now - open_at - fade_d, fade_d) or pa
  local rise = round((1 - pa) * 2 * U)

  love.graphics.setFont(font)
  local text_h = font:getHeight()

  do
    local bw = tracked_width(BADGE_TEXT, 1, font) + GUT * 2
    local bh = text_h + U * 2
    local bx = math.floor((sw - bw) / 2)
    local by = U * 2
    love.graphics.setColor(0, 0, 0, 0.55 * ba)
    love.graphics.rectangle("fill", bx + 2, by + 2, bw, bh)
    set_col(bg, 0.97 * ba)
    love.graphics.rectangle("fill", bx, by, bw, bh)
    set_col(ACC, 0.95 * ba)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", bx, by, bw, bh)
    print_tracked(BADGE_TEXT, bx + GUT, by + U, 1, font)
  end

  if not open and not closing then
    love.graphics.setFont(prev_font)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if page == 2 and crows_persona ~= Palette.persona() then crows_dirty = true end
  if rows_dirty or not rows then rebuild_rows() end
  if (crows_dirty or not crows) and page == 2 then rebuild_crows() end
  local defs = active_defs()
  local small_h = font_small:getHeight()
  local base_row_h = text_h + U
  local header_h = small_h + U
  local row_h = base_row_h
  local title_h = text_h + U * 3
  local pw = 520

  local st_avail = SelfTest.available()
  local st_value = st_running and SelfTest.status() or st_done or (st_avail and "READY" or "MENU ONLY")
  local st_line = st_running or (st_done ~= nil)

  local nh = (page ~= 2) and (_nheaders or 0) or 0
  local nvr = (page ~= 2) and (_nrows or 0) or 0
  local st_footer_line = st_line and page ~= 3
  local desc_h = (page ~= 2) and (small_h + 2) or 0
  local function page1_body(rh)
    return nvr * rh + nh * header_h + U * 2 + rh + (st_footer_line and (small_h + 2) or 0)
  end
  local body_h
  if page ~= 2 then
    body_h = page1_body(row_h)
    local ph_try = title_h + 2 + U + body_h + U * 2 + desc_h + small_h + U * 2
    if ph_try > sh * 0.96 then
      local fixed = ph_try - (nvr + 1) * row_h
      local avail = sh * 0.96 - fixed
      row_h = math.max(text_h + 1, math.floor(avail / (nvr + 1)))
      body_h = page1_body(row_h)
    end
  else
    body_h = small_h + U * 2 + (text_h + U * 2) + (#crows + 1) * row_h
  end
  local ph = title_h + 2 + U + body_h + U * 2 + desc_h + small_h + U * 2
  local px = math.floor((sw - pw) / 2)
  local py = math.floor((sh - ph) / 2) + rise

  love.graphics.setColor(0, 0, 0, 0.55 * pa)
  love.graphics.rectangle("fill", px + 2, py + 2, pw, ph)
  set_col(bg, 0.97 * pa)
  love.graphics.rectangle("fill", px, py, pw, ph)
  set_col(FR, 0.90 * pa)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px, py, pw, ph)

  local val_x = px + pw - GUT - VAL_W
  local def_x = px + pw - GUT - DEF_W

  HIT.px, HIT.py, HIT.pw, HIT.ph = px, py, pw, ph
  HIT.row_h = row_h
  HIT.val_x, HIT.def_x = val_x, def_x
  HIT.la_x = val_x - 16
  HIT.ra_x = def_x - 16

  do
    local tab_y = py + U * 2
    local tab_h = text_h + U
    HIT.tab_y, HIT.tab_h = tab_y - 2, tab_h
    local tx = px + GUT
    local t1w = tracked_width(TAB_1, 2, font) + U * 2
    local t2w = tracked_width(TAB_2, 2, font) + U * 2
    HIT.t1_x, HIT.t1_w = tx - U, t1w
    local hov1 = open and in_rect(mx, my, HIT.t1_x, HIT.tab_y, t1w, tab_h)
    if hov1 and page ~= 1 then
      set_col(FRD, 0.55 * pa)
      love.graphics.rectangle("fill", HIT.t1_x, HIT.tab_y, t1w, tab_h)
    end
    if page == 1 then
      set_col(ACC, 0.97 * pa)
    else
      love.graphics.setColor(1, 1, 1, (hov1 and 0.85 or 0.55) * pa)
    end
    print_tracked(TAB_1, tx, tab_y, 2, font)
    if page == 1 then
      set_col(ACC, 0.95 * pa)
      love.graphics.rectangle("fill", HIT.t1_x, HIT.tab_y + tab_h, t1w, 2)
    end
    tx = tx + t1w + U
    love.graphics.setColor(1, 1, 1, 0.30 * pa)
    love.graphics.print("|", tx, tab_y)
    tx = tx + font:getWidth("|") + U * 2
    HIT.t2_x, HIT.t2_w = tx - U, t2w
    local hov2 = open and in_rect(mx, my, HIT.t2_x, HIT.tab_y, t2w, tab_h)
    if hov2 and page ~= 2 then
      set_col(FRD, 0.55 * pa)
      love.graphics.rectangle("fill", HIT.t2_x, HIT.tab_y, t2w, tab_h)
    end
    if page == 2 then
      set_col(ACC, 0.97 * pa)
    else
      love.graphics.setColor(1, 1, 1, (hov2 and 0.85 or 0.55) * pa)
    end
    print_tracked(TAB_2, tx, tab_y, 2, font)
    if page == 2 then
      set_col(ACC, 0.95 * pa)
      love.graphics.rectangle("fill", HIT.t2_x, HIT.tab_y + tab_h, t2w, 2)
    end
    tx = tx + t2w + U
    love.graphics.setColor(1, 1, 1, 0.30 * pa)
    love.graphics.print("|", tx, tab_y)
    tx = tx + font:getWidth("|") + U * 2
    local t3w = tracked_width(TAB_3, 2, font) + U * 2
    HIT.t3_x, HIT.t3_w = tx - U, t3w
    local hov3 = open and in_rect(mx, my, HIT.t3_x, HIT.tab_y, t3w, tab_h)
    if hov3 and page ~= 3 then
      set_col(FRD, 0.55 * pa)
      love.graphics.rectangle("fill", HIT.t3_x, HIT.tab_y, t3w, tab_h)
    end
    if page == 3 then
      set_col(ACC, 0.97 * pa)
    else
      love.graphics.setColor(1, 1, 1, (hov3 and 0.85 or 0.55) * pa)
    end
    print_tracked(TAB_3, tx, tab_y, 2, font)
    if page == 3 then
      set_col(ACC, 0.95 * pa)
      love.graphics.rectangle("fill", HIT.t3_x, HIT.tab_y + tab_h, t3w, 2)
    end
    tx = tx + t3w + U * 2
    love.graphics.setColor(1, 1, 1, 0.40 * pa)
    love.graphics.print((page == 2) and csuffix or SUFFIX_1, tx, tab_y)

    local clw = font:getWidth(CLOSE_TXT) + U * 2
    HIT.cl_x, HIT.cl_y, HIT.cl_w, HIT.cl_h = px + pw - GUT - clw + U, HIT.tab_y, clw, tab_h

    local pr_txt = "P: " .. string.upper(Palette.persona())
    local prw = font:getWidth(pr_txt) + U * 2
    HIT.pr_x, HIT.pr_w = HIT.cl_x - prw - U * 3, prw
    local hovp = open and in_rect(mx, my, HIT.pr_x, HIT.tab_y, prw, tab_h)
    if hovp then
      set_col(FRD, 0.55 * pa)
      love.graphics.rectangle("fill", HIT.pr_x, HIT.tab_y, prw, tab_h)
      set_col(ACC, 0.97 * pa)
    else
      love.graphics.setColor(1, 1, 1, 0.55 * pa)
    end
    love.graphics.print(pr_txt, HIT.pr_x + U, tab_y)

    local hovx = open and in_rect(mx, my, HIT.cl_x, HIT.cl_y, clw, tab_h)
    if hovx then
      set_col(FRD, 0.55 * pa)
      love.graphics.rectangle("fill", HIT.cl_x, HIT.cl_y, clw, tab_h)
      set_col(ACC, 0.97 * pa)
    else
      love.graphics.setColor(1, 1, 1, 0.55 * pa)
    end
    love.graphics.print(CLOSE_TXT, HIT.cl_x + U, tab_y)

    if flash_text then
      local age = now - flash_at
      if age < SAVED_HOLD + Motion.SLOW then
        local fa = 0.90
        if age > SAVED_HOLD then
          fa = 0.90 * (1 - Motion.anim01(age - SAVED_HOLD, Motion.dur(Motion.SLOW)))
        end
        set_col(ACC, fa * pa)
        love.graphics.print(flash_text, HIT.cl_x - U * 2 - font:getWidth(flash_text), tab_y)
      else
        flash_text = nil
      end
    end
  end

  set_col(ACC, 0.95 * pa)
  love.graphics.rectangle("fill", px, py + title_h, pw, 2)

  local cy = py + title_h + 2 + U
  local mouse_in_panel = open and in_rect(mx, my, px, py, pw, ph)

  local function row_chrome(i, y)
    HIT.rows[i] = y
    HIT.itemh[i] = row_h
    local hovered = mouse_in_panel and my >= y and my < y + row_h
    if hovered then
      set_col(FRD, 0.45 * pa)
      love.graphics.rectangle("fill", px + 2, y - 1, pw - 4, row_h)
    end
    return hovered
  end

  if page ~= 2 then
    HIT.n = #rows
    for i = 1, #rows do
      local r = rows[i]
      if r.kind == "header" then
        HIT.rows[i] = cy
        HIT.itemh[i] = header_h
        local hovered = mouse_in_panel and my >= cy and my < cy + header_h
        local selected = i == sel
        if hovered or selected then
          set_col(FRD, (selected and 0.55 or 0.40) * pa)
          love.graphics.rectangle("fill", px + 2, cy - 1, pw - 4, header_h)
        end
        love.graphics.setFont(font_small)
        set_col(ACC, (selected and 0.97 or 0.72) * pa)
        local htxt = (r.collapsed and "> " or "v ") .. r.group
        if r.collapsed then htxt = htxt .. "  (" .. r.count .. ")" end
        love.graphics.print(htxt, px + GUT, cy + (header_h - small_h) - 1)
        set_col(FRD, 0.50 * pa)
        love.graphics.rectangle("fill", px + GUT, cy + header_h - 2, pw - GUT * 2, 1)
        love.graphics.setFont(font)
        cy = cy + header_h
      elseif r.kind == "action" then
        cy = cy + U
        set_col(FRD, 0.90 * pa)
        love.graphics.rectangle("fill", px + U, cy, pw - U * 2, 1)
        cy = cy + U
        HIT.rows[i] = cy
        HIT.itemh[i] = row_h
        local st_sel = sel == i
        local hovered = mouse_in_panel and my >= cy and my < cy + row_h
        if hovered then
          set_col(FRD, 0.45 * pa)
          love.graphics.rectangle("fill", px + 2, cy - 1, pw - 4, row_h)
        end
        if st_sel then
          set_col(ACC, 0.90 * pa)
          love.graphics.rectangle("fill", px + U, cy, 2, text_h)
        end
        if page == 3 then
          set_col(ACC, (st_sel and 0.97 or 0.62) * pa)
          love.graphics.print(RESET_RUNTIME_LABEL, px + GUT, cy)
        else
          if st_avail then
            set_col(ACC, (st_sel and 0.97 or 0.85) * pa)
          else
            love.graphics.setColor(1, 1, 1, (st_sel and 0.55 or 0.40) * pa)
          end
          love.graphics.print(ST_LABEL, px + GUT, cy)
          if st_line then
            cy = cy + row_h
            love.graphics.setFont(font_small)
            love.graphics.setColor(1, 1, 1, 0.72 * pa)
            love.graphics.print(st_value, px + GUT, cy)
            love.graphics.setFont(font)
          else
            love.graphics.setColor(1, 1, 1, 0.42 * pa)
            love.graphics.print(st_value, val_x, cy)
          end
        end
        cy = cy + row_h
      else
        local d = r.d
        local hovered = row_chrome(i, cy)
        local selected = i == sel
        if selected then
          set_col(ACC, 0.90 * pa)
          love.graphics.rectangle("fill", px + U, cy, 2, text_h)
          love.graphics.setColor(1, 1, 1, 0.98 * pa)
        else
          love.graphics.setColor(1, 1, 1, 0.62 * pa)
        end
        love.graphics.print(r.label, px + GUT, cy)

        if hovered or selected then
          local la_hov = hovered and mx >= HIT.la_x and mx < HIT.la_x + HIT.arrow_w
          local ra_hov = hovered and mx >= HIT.ra_x and mx < HIT.ra_x + HIT.arrow_w
          if la_hov then
            set_col(ACC, 0.97 * pa)
          else
            love.graphics.setColor(1, 1, 1, 0.45 * pa)
          end
          love.graphics.print("<", HIT.la_x + 2, cy)
          if ra_hov then
            set_col(ACC, 0.97 * pa)
          else
            love.graphics.setColor(1, 1, 1, 0.45 * pa)
          end
          love.graphics.print(">", HIT.ra_x + 2, cy)
        end

        local vr, vg, vb, va
        if selected then
          vr, vg, vb, va = ACC[1], ACC[2], ACC[3], 0.97
        else
          vr, vg, vb, va = 1, 1, 1, 0.82
        end
        vr, vg, vb, va = selflash(vr, vg, vb, va, r.di, now, pa)
        if bool_def(d) then
          draw_checkbox(val_x, cy + 1, text_h - 2, checkbox_on(Tuning.get_raw(d.key)), pa, ACC)
          love.graphics.setColor(vr, vg, vb, va)
          love.graphics.print(r.value, val_x + text_h + U, cy)
        else
          love.graphics.setColor(vr, vg, vb, va)
          love.graphics.print(r.value, val_x, cy)
          if r.unit then
            love.graphics.setColor(1, 1, 1, 0.42 * pa)
            love.graphics.print(r.unit, val_x + font:getWidth(r.value), cy)
          end
        end
        love.graphics.setColor(1, 1, 1, 0.32 * pa)
        love.graphics.print(r.def, def_x, cy)
        cy = cy + row_h
      end
    end
  else
    love.graphics.setFont(font_small)
    love.graphics.setColor(1, 1, 1, 0.42 * pa)
    love.graphics.print(COLOUR_NOTE, px + GUT, cy)
    love.graphics.setFont(font)
    cy = cy + small_h + U * 2

    do
      local sw_sz = text_h
      local sw_gap = 4
      HIT.sw, HIT.sw_gap = sw_sz, sw_gap
      HIT.sw_x, HIT.sw_y, HIT.sw_h = px + GUT, cy, sw_sz
      HIT.sw_n = #SWATCHES
      for si = 1, #SWATCHES do
        local hx = SWATCHES[si]
        local rr = tonumber(hx:sub(1, 2), 16) / 255
        local gg = tonumber(hx:sub(3, 4), 16) / 255
        local bb = tonumber(hx:sub(5, 6), 16) / 255
        local sx = HIT.sw_x + (si - 1) * (sw_sz + sw_gap)
        love.graphics.setColor(rr, gg, bb, 1.0 * pa)
        love.graphics.rectangle("fill", sx, cy, sw_sz, sw_sz)
        local hov = mouse_in_panel and in_rect(mx, my, sx, cy, sw_sz, sw_sz)
        set_col(FR, (hov and 0.97 or 0.55) * pa)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", sx, cy, sw_sz, sw_sz)
      end
      cy = cy + sw_sz + U * 2
    end

    HIT.n = #crows + 1
    local hexw = font:getWidth("CC")
    local hgap = 2
    HIT.hex_x = val_x + font:getWidth("#") + hgap
    HIT.hexw, HIT.hgap = hexw, hgap
    for i = 1, #crows do
      local r = crows[i]
      row_chrome(i, cy)
      local selected = i == sel
      if selected then
        set_col(ACC, 0.90 * pa)
        love.graphics.rectangle("fill", px + U, cy, 2, text_h)
        love.graphics.setColor(1, 1, 1, 0.98 * pa)
      else
        love.graphics.setColor(1, 1, 1, 0.62 * pa)
      end
      love.graphics.print(r.key, px + GUT, cy)

      local hx = val_x
      love.graphics.setColor(1, 1, 1, 0.52 * pa)
      love.graphics.print("#", hx, cy)
      hx = hx + font:getWidth("#") + hgap
      local editing = selected and edit_mode
      local typing = editing and edit_hex ~= ""
      local buf = typing and (edit_hex .. string.rep("_", 6 - #edit_hex)) or nil
      local caret = typing and math.min(3, math.floor(#edit_hex / 2) + 1) or edit_ch
      for ch = 1, 3 do
        local seg
        if typing then seg = buf:sub(ch * 2 - 1, ch * 2)
        else seg = ch == 1 and r.hr or ch == 2 and r.hg or r.hb end
        local vr, vg, vb, va
        if editing and ch == caret then
          vr, vg, vb, va = ACC[1], ACC[2], ACC[3], 0.98
          set_col(ACC, 0.95 * pa)
          love.graphics.rectangle("fill", hx, cy + text_h, hexw, 2)
        elseif typing then
          vr, vg, vb, va = ACC[1], ACC[2], ACC[3], 0.90
        elseif selected then
          vr, vg, vb, va = 1, 1, 1, 0.92
        else
          vr, vg, vb, va = 1, 1, 1, 0.72
        end
        vr, vg, vb, va = selflash(vr, vg, vb, va, i, now, pa)
        love.graphics.setColor(vr, vg, vb, va)
        love.graphics.print(seg, hx, cy)
        hx = hx + hexw + hgap
      end

      local swx = hx + U * 2
      local c = r.color
      set_col(c, 1.0 * pa)
      love.graphics.rectangle("fill", swx, cy + 1, 24, text_h - 2)
      set_col(FR, 0.90 * pa)
      love.graphics.rectangle("line", swx, cy + 1, 24, text_h - 2)

      love.graphics.setColor(1, 1, 1, 0.32 * pa)
      love.graphics.print(r.def, def_x, cy)
      cy = cy + row_h
    end

    local ra_i = #crows + 1
    row_chrome(ra_i, cy)
    local ra_sel = sel == ra_i
    local rr, rg, rb, ra2
    if ra_sel then
      set_col(ACC, 0.90 * pa)
      love.graphics.rectangle("fill", px + U, cy, 2, text_h)
      rr, rg, rb, ra2 = ACC[1], ACC[2], ACC[3], 0.97
    else
      rr, rg, rb, ra2 = 1, 1, 1, 0.62
    end
    rr, rg, rb, ra2 = selflash(rr, rg, rb, ra2, ra_i, now, pa)
    love.graphics.setColor(rr, rg, rb, ra2)
    love.graphics.print(RESET_ALL_LABEL, px + GUT, cy)
  end

  local footer
  if page == 3 then
    footer = FOOTER_3
  elseif page == 1 then
    footer = st_running and FOOTER_1_RUN or FOOTER_1
  else
    footer = edit_mode and FOOTER_2_EDIT or FOOTER_2
  end
  if mouse_seen then footer = footer_with_mouse(footer) end
  love.graphics.setFont(font_small)
  local fit_w = pw - GUT * 2
  if page ~= 2 and desc_h > 0 then
    local it = rows and rows[sel]
    local dtxt
    if it then
      if it.kind == "row" and it.d then dtxt = DESCS[it.d.key]
      elseif it.kind == "header" then dtxt = it.count .. " settings -- Enter to fold/unfold"
      elseif it.kind == "action" then dtxt = (page == 3) and "reset all runtime toggles to defaults" or "run the in-engine self-test suite" end
    end
    if dtxt then
      local w = font_small:getWidth(dtxt)
      local sx = (w > fit_w and w > 0) and (fit_w / w) or 1
      love.graphics.setColor(1, 1, 1, 0.88 * pa)
      love.graphics.print(dtxt, px + GUT, py + ph - small_h - U * 2 - desc_h, 0, sx, sx)
    end
  end
  local fw = font_small:getWidth(footer)
  local fsx = (fw > fit_w and fw > 0) and (fit_w / fw) or 1
  love.graphics.setColor(1, 1, 1, 0.42 * pa)
  love.graphics.print(footer, px + GUT, py + ph - small_h - U * 2, 0, fsx, fsx)

  HIT.valid = open

  love.graphics.setFont(prev_font)
  love.graphics.setColor(1, 1, 1, 1)
end

if rawget(_G, "NEURO_TEST") then
  Panel._test = {
    hit = HIT,
    row_at = row_at,
    hex_channel_at = hex_channel_at,
    swatch_at = swatch_at,
    swatches = SWATCHES,
    bool_def = bool_def,
    checkbox_on = checkbox_on,
    draw_checkbox = draw_checkbox,
    reset_mouse = function() mouse_seen = false end,
    state = function() return page, sel, edit_mode, edit_ch end,
    edit_hex = function() return edit_hex end,
    rows = function() return rows end,
  }
end

return Panel
