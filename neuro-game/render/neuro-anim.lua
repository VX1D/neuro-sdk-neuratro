local Palette = require("render.palette")
local function set_col(c, a) love.graphics.setColor(c[1], c[2], c[3], a) end
local Utils = require("util.utils")
local dotenv = require("util.dotenv")

local NeuroAnim = {}

local Motion = {
  FAST = 0.12,
  MED = 0.25,
  SLOW = 0.50,
  STAGGER = 0.06,
  STAGGER_TIGHT = 0.04,
  STAGGER_WIDE = 0.09,
  TICK = 0.05,
  HOLD = 0.9,
  HOLD_LONG = 1.5,
}

do
  local v = tostring(dotenv.get("NEURO_REDUCED_MOTION", "")):lower()
  Motion.reduced = (v == "1" or v == "true" or v == "on")
end

function Motion.ease_out_cubic(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local u = 1 - t
  return 1 - u * u * u
end

function Motion.dur(d)
  return Motion.reduced and 0 or d
end

function Motion.anim01(t, d)
  if d <= 0 then return 1 end
  return Motion.ease_out_cubic(math.min(1, t / d))
end

function Motion.pulse(now, hz, phase)
  if Motion.reduced then return 0.5 end
  return 0.5 + 0.5 * math.sin(now * (hz or 1) + (phase or 0))
end

NeuroAnim.Motion = Motion

-- generation counter: delayed beats bail if it changed, cancelling a stale hover
local _pack_gen = 0

local function after(delay, fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      trigger   = "after",
      delay     = delay,
      blockable = false,
      func      = function() pcall(fn); return true end,
    }))
  end
end

local function beat(d, fn)
  after(Motion.dur(d), fn)
end

local function immediate(fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      blockable = false,
      func      = function() pcall(fn); return true end,
    }))
  else
    pcall(fn)
  end
end

local function sound(name, pitch, vol)
  pcall(function() play_sound(name, pitch or 1, vol or 0.8) end)
end

local function juice(card, sc, rot)
  if card and card.juice_up then
    pcall(function() card:juice_up(sc or 0.3, rot or 0.2) end)
  end
end

local function float_text(text, opts)
  opts = opts or {}
  local major = opts.major
  if not major then
    major = (G and (G.play or G.hand or G.HUD_tags))
  end
  if not major then return end
  pcall(function()
    attention_text({
      text         = text,
      scale        = opts.scale  or 1.3,
      colour       = opts.colour or {1, 1, 1, 1},
      hold         = opts.hold   or Motion.HOLD,
      align        = "cm",
      offset       = { x = opts.ox or 0, y = opts.oy or -2.6 },
      major        = major,
      noisy        = opts.noisy,
      rotate       = opts.rotate,
    })
  end)
end

local function stagger_entry(cards, delay)
  if not cards then return delay end
  for _, c in ipairs(cards) do
    local cc, d = c, delay
    beat(d, function() juice(cc, 0.22, 0.14) end)
    delay = delay + Motion.STAGGER
  end
  return delay
end

function NeuroAnim.hover_pack_card(card, bp)
  if not card then return end

  _pack_gen = _pack_gen + 1
  local gen = _pack_gen

  local pal = Palette.pal()
  local total = (bp and bp.cards and #bp.cards) or 0
  local is_last = (total <= 1)

  immediate(function()
    juice(card, is_last and 0.7 or 0.45, is_last and 0.32 or 0.24)
    if bp and bp.add_to_highlighted then
      pcall(function() bp:add_to_highlighted(card, true) end)
    else
      card.highlighted = true
    end
    sound("card1", 0.9 + math.random() * 0.15, 0.45)
  end)

  beat(Motion.FAST, function()
    if gen ~= _pack_gen then return end
    if bp and bp.cards then
      for _, c in ipairs(bp.cards) do
        if c ~= card then juice(c, 0.08, 0.04) end
      end
    end
  end)

  beat(Motion.MED, function()
    if gen ~= _pack_gen then return end
    local g = pal.D_CYAN
    if is_last then
      float_text("Last pick", {
        scale  = 1.0,
        colour = {g[1], g[2], g[3], 0.85},
        hold   = Motion.HOLD,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    else
      float_text("Considering", {
        scale  = 0.85,
        colour = {g[1], g[2], g[3], 0.7},
        hold   = Motion.HOLD,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

function NeuroAnim.pick_pack_card(card, bp)
  if not card then return end

  _pack_gen = _pack_gen + 1
  local gen = _pack_gen

  local pal = Palette.pal()
  local total    = (bp and bp.cards and #bp.cards) or 0
  local is_last  = (total <= 1)

  juice(card, is_last and 0.8 or 0.6, is_last and 0.4 or 0.3)
  sound("whoosh1", 0.85 + math.random() * 0.1, 0.7)
  if bp and bp.remove_from_highlighted then
    pcall(function() bp:remove_from_highlighted(card) end)
  end
  card.highlighted = false

  beat(Motion.TICK, function()
    if gen ~= _pack_gen then return end
    if is_last then
      sound("gold_seal", 1.05 + math.random() * 0.08, 0.7)
      beat(Motion.FAST, function() if gen ~= _pack_gen then return end juice(card, 0.5, 0.28) end)

      local g = pal.D_GOLD
      float_text("Locked in", {
        scale  = 1.6,
        colour = {g[1], g[2], g[3], 1},
        hold   = Motion.HOLD_LONG,
        oy     = -1.0,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    else
      local g = pal.D_GREEN
      float_text("Selected", {
        scale  = 1.2,
        colour = {g[1], g[2], g[3], 1},
        hold   = Motion.HOLD,
        oy     = -2.6,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

function NeuroAnim.pre_play(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * Motion.STAGGER_TIGHT
    beat(d, function()
      juice(cc, 0.35, 0.2)
      sound("card1", 0.9 + math.random() * 0.15, 0.3)
    end)
  end
end

function NeuroAnim.pre_discard(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * Motion.STAGGER_TIGHT
    beat(d, function()
      juice(cc, 0.25, 0.15)
    end)
  end
  sound("whoosh1", 1.1 + math.random() * 0.1, 0.35)
end

local SHOP_AREAS = { "shop_jokers", "shop_vouchers", "shop_booster" }

function NeuroAnim.on_shop_enter()
  beat(Motion.MED, function()
    local delay = 0
    for _, name in ipairs(SHOP_AREAS) do
      local area = G and G[name]
      if area then delay = stagger_entry(area.cards, delay) end
    end
  end)
end

local _pack_opened = setmetatable({}, { __mode = "k" })

function NeuroAnim.on_pack_open()
  local bp = G and (G.pack_cards or G.booster_pack)
  if not (bp and bp.cards and #bp.cards > 0) or _pack_opened[bp] then return end
  _pack_opened[bp] = true
  local gen = _pack_gen
  beat(Motion.MED, function()
    if gen ~= _pack_gen then return end
    stagger_entry(bp.cards, 0)
  end)
end

function NeuroAnim.on_buy(card)
  if not card then return end
  immediate(function()
    juice(card, 0.6, 0.35)
    sound("gold_seal", 1.0 + math.random() * 0.1, 0.5)
  end)
end

function NeuroAnim.on_round_eval()
  beat(Motion.SLOW, function()
    if G and G.jokers and G.jokers.cards then
      for i, c in ipairs(G.jokers.cards) do
        local cc, d = c, (i - 1) * Motion.STAGGER_WIDE
        beat(d, function() juice(cc, 0.45, 0.28) end)
      end
    end
  end)
end

local BLIND_KEYS = { "small", "big", "boss" }

function NeuroAnim.on_blind_select()
  beat(Motion.SLOW, function()
    local opts = G and G.blind_select_opts
    if not opts then return end
    local delay = 0
    for _, key in ipairs(BLIND_KEYS) do
      local opt = opts[key]
      if opt and opt.juice_up then
        local o, d = opt, delay
        beat(d, function() juice(o, 0.3, 0.18) end)
        delay = delay + Motion.STAGGER_WIDE
      end
    end
  end)
end

local _last_anim_state = nil

function NeuroAnim.on_state_enter(state_name)
  if state_name == _last_anim_state then return end
  _last_anim_state = state_name

  if state_name == "SHOP" then
    NeuroAnim.on_shop_enter()
  elseif state_name == "ROUND_EVAL" then
    NeuroAnim.on_round_eval()
  elseif state_name == "BLIND_SELECT" then
    NeuroAnim.on_blind_select()
  end
end

local LABEL_COLS = 26
local TYPE_CPS = 140
local CURSOR_HZ = 2
local NAME_FLASH = Motion.dur(0.10)
local SUB_REVEAL = Motion.dur(Motion.MED)
local HEADER_L = "NEURATRO // TERMINAL"
local HEADER_R = "S-572943"

local function term_line(label, status, accent, thr)
  local text = label
  if status then
    local n = LABEL_COLS - #label - 1
    if n > 0 then text = label .. " " .. string.rep(".", n) end
  end
  return { text = text, status = status, accent = accent, thr = thr }
end

local NEURO_LINES = {
  term_line("> neuro.exe --login",  nil,           nil,  0.00),
  term_line("bios check",           "OK",          nil,  0.06),
  term_line("consciousness.dll",    "LOADED",      nil,  0.15),
  term_line("tony",                 "ON DUTY",     nil,  0.24),
  term_line("speech synthesis",     "READY",       nil,  0.33),
  term_line("Nere",                 "FILTERED",    nil,  0.42),
  term_line("vedal oversight",      "ACTIVE",      nil,  0.51),
  term_line("heart",                "heart heart heart", true, 0.60),
  term_line("uplink",               "ESTABLISHED", nil,  0.70),
}

local EVIL_LINES = {
  term_line("> neuro.exe --login --force", nil,      nil,  0.00),
  term_line("bios check",           "OK",            nil,  0.06),
  term_line("consciousness.dll",    "HIJACKED",      true, 0.15),
  term_line("tony",                 "ON DUTY",       nil,  0.24),
  term_line("speech synthesis",     "READY",         nil,  0.33),
  term_line("Nere",                 "FILTERED",      nil,  0.42),
  term_line("vedal oversight",      "DISABLED",      true, 0.51),
  term_line("heart",                "<3 <3 <3",      true, 0.60),
  term_line("uplink",               "ESTABLISHED",   nil,  0.70),
}

local _login_font = nil
local _login_font_big = nil
local _login_font_sz = 0
local _login_font_sz_big = 0

local function get_login_fonts(sh)
  local sz = math.max(14, math.floor(sh / 40))
  local sz_big = math.max(24, math.floor(sh / 15))
  if _login_font and _login_font_sz == sz and _login_font_sz_big == sz_big then return _login_font, _login_font_big end
  _login_font, _login_font_big = Utils.load_font_pair("resources/fonts/m6x11plus.ttf", sz, sz_big)
  _login_font_sz = sz
  _login_font_sz_big = sz_big
  return _login_font, _login_font_big
end

local function typed_str(tc, text, now2)
  if tc.done then return text end
  local n = math.floor((now2 - tc.start_time) * TYPE_CPS)
  if n >= #text then
    tc.done = true
    tc.str = text
  elseif n ~= tc.shown then
    tc.shown = n
    tc.str = text:sub(1, n)
  end
  return tc.str or ""
end

local function draw_terminal_content(anim, sw, sh, now2, phase, phase_t, reveal_t, ma)
  local pal = anim.cached_pal
  local acc, fg, dim = pal.ACCENT, pal.D_WHITE, pal.D_DIM
  local lines = anim.cached_lines

  local small_font, big_font = get_login_fonts(sh)
  if small_font then love.graphics.setFont(small_font) end
  local font = love.graphics.getFont()
  local fh = font:getHeight()
  local char_w = font:getWidth("0")
  local bfont = big_font or font
  local big_fh = bfont:getHeight()
  local line_h = fh + 4

  local pad = math.floor(fh * 1.4)
  local gap = math.floor(fh * 0.8)
  local panel_w = math.min(char_w * 44 + pad * 2, sw - 40)
  local inner_w = panel_w - pad * 2
  local log_h = #lines * line_h
  local panel_h = pad + fh + gap + log_h + gap + big_fh + gap + fh + gap + 3 + pad
  local px = math.floor((sw - panel_w) / 2)
  local py = math.floor((sh - panel_h) / 2)
  local inner_x = px + pad

  local load_progress = 0
  if phase == "LOADING" then
    load_progress = phase_t
  elseif phase ~= "BOOT" then
    load_progress = 1
  end
  local cursor_on = (math.floor(now2 * CURSOR_HZ) % 2 == 0)

  love.graphics.setColor(0.02, 0.02, 0.025, ma)
  love.graphics.rectangle("fill", 0, 0, sw, sh)
  love.graphics.setColor(0.05, 0.05, 0.06, ma)
  love.graphics.rectangle("fill", px, py, panel_w, panel_h)
  set_col(fg, 0.35 * ma)
  love.graphics.rectangle("fill", px, py, panel_w, 1)
  love.graphics.rectangle("fill", px, py + panel_h - 1, panel_w, 1)
  love.graphics.rectangle("fill", px, py, 1, panel_h)
  love.graphics.rectangle("fill", px + panel_w - 1, py, 1, panel_h)

  local hy = py + pad
  set_col(dim, 0.9 * ma)
  love.graphics.print(HEADER_L, inner_x, hy)
  love.graphics.print(HEADER_R, px + panel_w - pad - font:getWidth(HEADER_R), hy)
  set_col(fg, 0.2 * ma)
  love.graphics.rectangle("fill", px + 1, hy + fh + math.floor(gap * 0.5), panel_w - 2, 1)

  local log_y = hy + fh + gap
  local status_x = inner_x + char_w * (LABEL_COLS + 1)
  if not anim.tc then anim.tc = {} end
  local prev_done = true
  local cur_x, cur_y
  for i, entry in ipairs(lines) do
    local tc = anim.tc[i]
    if not tc then
      if load_progress >= 1 then
        tc = { done = true }
        anim.tc[i] = tc
      elseif prev_done and load_progress >= entry.thr then
        tc = { start_time = now2 }
        anim.tc[i] = tc
      end
    end
    if tc then
      local y = log_y + (i - 1) * line_h
      local disp = typed_str(tc, entry.text, now2)
      if entry.status then
        set_col(dim, 0.8 * ma)
      else
        set_col(fg, 0.95 * ma)
      end
      love.graphics.print(disp, inner_x, y)
      if tc.done and entry.status then
        if entry.accent then
          set_col(acc, 0.95 * ma)
        else
          set_col(fg, 0.95 * ma)
        end
        love.graphics.print(entry.status, status_x, y)
      end
      if not tc.done then
        cur_x, cur_y = inner_x + font:getWidth(disp) + 2, y
      elseif cursor_on and load_progress < 1 and not anim.tc[i + 1] then
        cur_x, cur_y = inner_x + font:getWidth(entry.text) + char_w, y
      end
      prev_done = tc.done == true
    else
      prev_done = false
    end
  end
  if cur_x and load_progress < 1 then
    set_col(fg, 0.9 * ma)
    love.graphics.rectangle("fill", cur_x, cur_y, char_w, fh)
  end

  local rz_y = log_y + log_h + gap
  local cx = px + panel_w / 2
  if phase == "BOOT" or phase == "LOADING" then
    local wait = "AWAITING IDENTITY"
    set_col(dim, 0.5 * ma)
    love.graphics.print(wait, math.floor(cx - font:getWidth(wait) / 2), math.floor(rz_y + (big_fh - fh) / 2))
  else
    love.graphics.setFont(bfont)
    local name = anim.name_str
    local nw = bfont:getWidth(name)
    local nx = math.floor(cx - nw / 2)
    if reveal_t < NAME_FLASH then
      set_col(acc, ma)
      love.graphics.rectangle("fill", px + 1, rz_y - 4, panel_w - 2, big_fh + 8)
      love.graphics.setColor(0.05, 0.05, 0.06, ma)
      love.graphics.print(name, nx, rz_y)
    else
      set_col(acc, ma)
      love.graphics.print(name, nx, rz_y)
      if cursor_on then
        love.graphics.rectangle("fill", nx + nw + math.floor(char_w * 0.8),
          rz_y + math.floor(big_fh * 0.14), math.floor(char_w * 1.6), math.floor(big_fh * 0.72))
      end
    end
    love.graphics.setFont(font)
    if reveal_t >= SUB_REVEAL then
      local sub = "IDENTITY CONFIRMED // LINK ESTABLISHED"
      set_col(dim, 0.85 * ma)
      love.graphics.print(sub, math.floor(cx - font:getWidth(sub) / 2), rz_y + big_fh + gap)
    end
  end

  local bar_y = py + panel_h - pad - 3
  set_col(fg, 0.15 * ma)
  love.graphics.rectangle("fill", inner_x, bar_y, inner_w, 3)
  local fill_w = math.floor(inner_w * load_progress)
  if fill_w > 0 then
    set_col(acc, 0.9 * ma)
    love.graphics.rectangle("fill", inner_x, bar_y, fill_w, 3)
  end

  love.graphics.setColor(0, 0, 0, 0.08 * ma)
  for yy = py + 2, py + panel_h - 2, 3 do
    love.graphics.rectangle("fill", px + 1, yy, panel_w - 2, 1)
  end
end

function NeuroAnim.draw_login_anim()
  if not G or not G.NEURO or not G.NEURO.login_anim then return end
  local anim = G.NEURO.login_anim
  local now2 = Utils.now()
  local elapsed = now2 - anim.start

  local BOOT      = 0.35
  local LOADING   = 2.00
  local CONNECTED = 1.75
  local FADE_OUT  = 0.60
  local TOTAL = BOOT + LOADING + CONNECTED + FADE_OUT

  if elapsed > TOTAL then
    G.NEURO.login_anim = nil
    return
  end

  if not anim.palette_ready and elapsed >= BOOT + LOADING then
    anim.palette_ready = true
  end

  local phase, phase_t
  if elapsed < BOOT then
    phase = "BOOT"
    phase_t = elapsed / BOOT
  elseif elapsed < BOOT + LOADING then
    phase = "LOADING"
    phase_t = (elapsed - BOOT) / LOADING
  elseif elapsed < BOOT + LOADING + CONNECTED then
    phase = "CONNECTED"
    phase_t = (elapsed - BOOT - LOADING) / CONNECTED
  else
    phase = "FADE_OUT"
    phase_t = (elapsed - BOOT - LOADING - CONNECTED) / FADE_OUT
  end

  local master_alpha = 1.0
  if not Motion.reduced then
    if phase == "BOOT" then
      master_alpha = Motion.ease_out_cubic(phase_t)
    elseif phase == "FADE_OUT" then
      master_alpha = 1.0 - Motion.ease_out_cubic(phase_t)
    end
  end
  master_alpha = Utils.clamp01(master_alpha)

  if not anim.name_str then
    anim.cached_pal = Palette.pal()
    anim.cached_lines = (Palette.persona() == "evil") and EVIL_LINES or NEURO_LINES
    anim.name_str = tostring(anim.name or anim.cached_pal.NAME):upper()
  end

  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()
  local prev_font = love.graphics.getFont()
  local reveal_t = elapsed - BOOT - LOADING

  draw_terminal_content(anim, sw, sh, now2, phase, phase_t, reveal_t, master_alpha)

  if prev_font then love.graphics.setFont(prev_font) end
  love.graphics.setColor(1, 1, 1, 1)
end

return NeuroAnim
