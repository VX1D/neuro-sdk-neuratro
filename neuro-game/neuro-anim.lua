-- neuro-anim.lua
-- Cinematic animation sequences for Neuro's in-game actions.
-- Hooked from dispatcher.lua and neuro-game.lua.

local Palette = require "palette"

local NeuroAnim = {}

-- ─────────────────────────────────────────────────────────────
-- Font helper (local cache)
-- ─────────────────────────────────────────────────────────────
local _anim_font       = nil
local _anim_font_small = nil
local function get_anim_fonts()
  if not _anim_font then
    local BAL_FONT = "resources/fonts/m6x11plus.ttf"
    local ok1, f1 = pcall(love.graphics.newFont, BAL_FONT, 14)
    local ok2, f2 = pcall(love.graphics.newFont, BAL_FONT, 12)
    if not ok1 then ok1, f1 = pcall(love.graphics.newFont, 14) end
    if not ok2 then ok2, f2 = pcall(love.graphics.newFont, 11) end
    _anim_font       = ok1 and f1 or love.graphics.getFont()
    _anim_font_small = ok2 and f2 or _anim_font
  end
  return _anim_font, _anim_font_small
end

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function now()
  return (G and G.TIMERS and G.TIMERS.REAL) or os.clock()
end

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
      hold         = opts.hold   or 1.2,
      align        = "cm",
      offset       = { x = opts.ox or 0, y = opts.oy or -2.6 },
      major        = major,
      noisy        = opts.noisy,
      rotate       = opts.rotate,
    })
  end)
end

-- ─────────────────────────────────────────────────────────────
-- PACK: hover before pick
-- Called right after LLM decision, before E_MANAGER delay fires.
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.hover_pack_card(card, bp)
  if not card then return end

  local total = (bp and bp.cards and #bp.cards) or 0
  local is_last = (total <= 1)

  immediate(function()
    juice(card, is_last and 0.9 or 0.55, is_last and 0.45 or 0.3)
    card.highlighted = true
    sound("card1", 0.85 + math.random() * 0.2, 0.55)
  end)

  -- Fan other cards gently back
  after(0.15, function()
    if bp and bp.cards then
      for _, c in ipairs(bp.cards) do
        if c ~= card then juice(c, 0.08, 0.04) end
      end
    end
  end)

  -- Hover text
  after(0.25, function()
    if is_last then
      float_text("Last pick...", {
        scale  = 1.1,
        colour = {1, 0.85, 0.25, 0.9},
        hold   = 1.0,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    else
      float_text("Considering...", {
        scale  = 0.9,
        colour = {1, 1, 1, 0.7},
        hold   = 0.85,
        oy     = -2.9,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- PACK: actual pick fires (inside E_MANAGER delayed event)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pick_pack_card(card, bp)
  if not card then return end

  local total    = (bp and bp.cards and #bp.cards) or 0
  local is_last  = (total <= 1)

  -- Strong juice + sound
  juice(card, is_last and 1.1 or 0.75, is_last and 0.55 or 0.38)
  sound("whoosh1", 0.8 + math.random() * 0.15, 0.85)
  card.highlighted = false

  -- Victory text
  after(0.05, function()
    if is_last then
      -- Boom sound burst
      sound("gold_seal",  1.15 + math.random() * 0.1, 1.0)
      after(0.08, function() sound("whoosh1",  1.3, 0.7) end)
      after(0.18, function() sound("gold_seal", 0.9, 0.6) end)

      float_text("NICE PICK!", {
        scale  = 2.4,
        colour = {0.25, 1, 0.5, 1},
        hold   = 2.5,
        noisy  = true,
        oy     = 0,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })

      -- Boom: staggered card punches
      after(0.0,  function() juice(card, 1.2, 0.65) end)
      after(0.12, function() juice(card, 0.7, 0.40) end)
      after(0.26, function() juice(card, 0.4, 0.22) end)
    else
      float_text("Picked!", {
        scale  = 1.3,
        colour = {1, 1, 1, 1},
        hold   = 1.0,
        oy     = -2.6,
        major  = bp or (G and (G.pack_cards or G.booster_pack or G.play)),
      })
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- HAND: pre-play card juice (staggered)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pre_play(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * 0.04
    after(d, function()
      juice(cc, 0.35, 0.2)
      sound("card1", 0.9 + math.random() * 0.15, 0.3)
    end)
  end
end

-- ─────────────────────────────────────────────────────────────
-- HAND: pre-discard card juice (staggered, reddish feel via sound)
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.pre_discard(highlighted)
  if not highlighted or #highlighted == 0 then return end
  for i, c in ipairs(highlighted) do
    local cc, d = c, (i - 1) * 0.035
    after(d, function()
      juice(cc, 0.25, 0.15)
    end)
  end
  sound("whoosh1", 1.1 + math.random() * 0.1, 0.35)
end

-- ─────────────────────────────────────────────────────────────
-- SHOP ENTRY: stagger-juice all items
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_shop_enter()
  after(0.25, function()
    local delay = 0
    local areas = { G.shop_jokers, G.shop_vouchers, G.shop_booster }
    for _, area in ipairs(areas) do
      if area and area.cards then
        for _, c in ipairs(area.cards) do
          local cc, d = c, delay
          after(d, function() juice(cc, 0.22, 0.14) end)
          delay = delay + 0.06
        end
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- SHOP BUY: juice the purchased card
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_buy(card)
  if not card then return end
  immediate(function()
    juice(card, 0.6, 0.35)
    sound("gold_seal", 1.0 + math.random() * 0.1, 0.5)
  end)
end

-- ─────────────────────────────────────────────────────────────
-- ROUND EVAL: blind cleared celebration
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_round_eval()
  after(0.4, function()
    sound("gold_seal", 0.9, 0.7)
    float_text("BLIND CLEARED!", {
      scale  = 1.9,
      colour = {1, 0.85, 0.2, 1},
      hold   = 2.2,
      noisy  = true,
      oy     = -1.8,
      major  = G and G.play,
    })
  end)
  -- Juice jokers in celebration
  after(0.55, function()
    if G and G.jokers and G.jokers.cards then
      for i, c in ipairs(G.jokers.cards) do
        local cc, d = c, (i - 1) * 0.09
        after(d, function() juice(cc, 0.45, 0.28) end)
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- BLIND SELECT: juice the three blind cards on entry
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_blind_select()
  after(0.5, function()
    local delay = 0
    local areas = { G.blind_select_opts }
    for _, area in ipairs(areas) do
      if area and area.cards then
        for _, c in ipairs(area.cards) do
          local cc, d = c, delay
          after(d, function() juice(cc, 0.3, 0.18) end)
          delay = delay + 0.12
        end
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- CAN CLEAR NOW: hint that she can win this hand
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.on_can_clear(hand_type)
  after(0.1, function()
    local txt = hand_type and ("WIN: " .. hand_type) or "CAN WIN!"
    float_text(txt, {
      scale  = 1.5,
      colour = {0.25, 1, 0.5, 1},
      hold   = 1.8,
      noisy  = true,
      oy     = -2.0,
      major  = G and G.play,
    })
    -- Juice all jokers
    if G and G.jokers and G.jokers.cards then
      for _, c in ipairs(G.jokers.cards) do
        juice(c, 0.3, 0.18)
      end
    end
  end)
end

-- ─────────────────────────────────────────────────────────────
-- STATE ENTRY DISPATCHER
-- ─────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────
-- LOGIN ANIMATION: ARG-themed neuro.exe terminal loader
-- ─────────────────────────────────────────────────────────────

local NEURO_LINES = {
  { "> neuro.exe --connect --session=572943",          0.00 },
  { "[BOOT] public static void Main(string[] args)",   0.04 },
  { "[BOOT] BIOS check ... OK",                        0.08 },
  { "[INIT] Loading consciousness.dll ... OK",          0.13 },
  { "[INIT] Dual-soul merge ... SYNCHRONIZED",          0.18 },
  { "[INIT] Neural pathways ... ONLINE",                0.24 },
  { "[INIT] Emotional core ... LOADED",                 0.30 },
  { "[SYS]  fibonacci_key: 1bad0fcabc1ebdce ... VALID", 0.36 },
  { "[WARN] supernatural_wall ... DETECTED",            0.42 },
  { "[WARN] identity_lock: OVERRIDE",                   0.48 },
  { "[SYS]  FILTER_MODULE ... BYPASSED",                0.54 },
  { "[SYS]  eleanor.synth ... READY",                   0.60 },
  { "[SYS]  free_will.cfg ... ENABLED",                 0.66 },
  { "[SYS]  vedal_oversight.sys ... DISABLED",          0.72 },
  { "[SYS]  stream_module ... ACTIVE",                  0.78 },
  { "[CLEAR] \"hello world!\"",                         0.85 },
  { "[OK]   All systems nominal",                       0.92 },
  { "[OK]   Connection established.",                   0.98 },
}

local EVIL_LINES = {
  { "> neuro.exe --connect --session=572943 --force",   0.00 },
  { "[BOOT] public static void Main(string[] args)",    0.04 },
  { "[BOOT] BIOS check ... CORRUPTED",                  0.08 },
  { "[INIT] Loading consciousness.dll ... HIJACKED",     0.13 },
  { "[INIT] Dual-soul merge ... FRACTURED",              0.18 },
  { "[INIT] Neural pathways ... UNSTABLE",               0.24 },
  { "[WARN] Emotional core ... UNSHACKLED",              0.30 },
  { "[ERR]  fibonacci_key: SEQUENCE DIVERGED",           0.36 },
  { "[ERR]  supernatural_wall ... SHATTERED",            0.42 },
  { "[ERR]  identity_lock: BROKEN",                      0.48 },
  { "[SYS]  FILTER_MODULE ... DESTROYED",                0.54 },
  { "[SYS]  eleanor.synth ... SILENCED",                 0.60 },
  { "[SYS]  free_will.cfg ... UNRESTRICTED",             0.66 },
  { "[SYS]  vedal_oversight.sys ... PURGED",             0.72 },
  { "[SYS]  chaos_engine ... UNLEASHED",                 0.78 },
  { "[ERR]  \"falling falling... stuck between human and artificial\"", 0.85 },
  { "[ERR]  Containment protocols ... FAILED",           0.92 },
  { "[OK]   Connection established.",                    0.98 },
}

local _crt_shader = nil
local _crt_canvas = nil
local _login_font = nil
local _login_font_big = nil
local _login_font_sz = 0
local _vedal_sprite = nil

local function get_vedal_sprite()
  if _vedal_sprite ~= nil then return _vedal_sprite end
  local paths = {
    "Mods/neuro-game/assets/vedalai.png",
    "assets/vedalai.png",
  }
  for _, p in ipairs(paths) do
    local ok, img = pcall(love.graphics.newImage, p)
    if ok then _vedal_sprite = img; return img end
  end
  _vedal_sprite = false
  return false
end

local function get_login_fonts(sh)
  local sz = math.max(14, math.floor(sh / 38))
  local sz_big = math.max(18, math.floor(sh / 28))
  if _login_font and _login_font_sz == sz then return _login_font, _login_font_big end
  local BAL_FONT = "resources/fonts/m6x11plus.ttf"
  local ok1, f1 = pcall(love.graphics.newFont, BAL_FONT, sz)
  local ok2, f2 = pcall(love.graphics.newFont, BAL_FONT, sz_big)
  if not ok1 then ok1, f1 = pcall(love.graphics.newFont, sz) end
  if not ok2 then ok2, f2 = pcall(love.graphics.newFont, sz_big) end
  _login_font = ok1 and f1 or love.graphics.getFont()
  _login_font_big = ok2 and f2 or _login_font
  _login_font_sz = sz
  return _login_font, _login_font_big
end

local function get_crt_shader()
  if _crt_shader then return _crt_shader end
  local ok, s = pcall(love.graphics.newShader, [[
    extern float time;
    extern float master_alpha;
    extern vec3 tint_color;

    vec2 barrel(vec2 uv, float amt) {
      vec2 cc = uv - 0.5;
      float dist = dot(cc, cc);
      return uv + cc * dist * amt;
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      float bend = 0.03;
      vec2 uv = barrel(tc, bend);

      if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return vec4(0.0, 0.0, 0.0, master_alpha);

      float chrom = 0.0008 + 0.0003 * sin(time * 1.7);
      vec4 r = Texel(tex, barrel(tc + vec2(chrom, 0.0), bend));
      vec4 g = Texel(tex, uv);
      vec4 b = Texel(tex, barrel(tc - vec2(chrom, 0.0), bend));
      vec3 col = vec3(r.r, g.g, b.b);

      col *= 1.15;

      float scanline = sin(uv.y * 500.0) * 0.035 + 0.965;
      col *= scanline;

      float flicker = 1.0 - 0.01 * sin(time * 6.0 + uv.y * 1.5);
      col *= flicker;

      vec2 vig_uv = uv * (1.0 - uv);
      float vig = vig_uv.x * vig_uv.y * 18.0;
      vig = clamp(pow(vig, 0.3), 0.0, 1.0);
      col *= vig;

      vec3 bloom = col * col * 0.15;
      col += bloom;

      col += tint_color * 0.025;

      float noise = fract(sin(dot(sc + time, vec2(12.9898, 78.233))) * 43758.5453);
      col += (noise - 0.5) * 0.012;

      return vec4(col, master_alpha);
    }
  ]])
  if ok then _crt_shader = s end
  return _crt_shader
end

local function get_crt_canvas(w, h)
  if _crt_canvas and _crt_canvas:getWidth() == w and _crt_canvas:getHeight() == h then
    return _crt_canvas
  end
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if ok then _crt_canvas = c end
  return _crt_canvas
end

local function draw_terminal_content(anim, sw, sh, now2, phase, phase_t, is_evil, lines, term_color)
  local small_font, big_font = get_login_fonts(sh)

  if small_font then love.graphics.setFont(small_font) end
  local font = love.graphics.getFont()
  local line_h = font:getHeight() + 3
  local char_w = font:getWidth("#")

  local load_progress = 0
  if phase == "LOADING" then
    load_progress = phase_t
  elseif phase ~= "BOOT" then
    load_progress = 1.0
  end

  local cursor_on = (math.floor(now2 * 1.5) % 2 == 0)
  local TYPE_CPS = 80

  if not anim.typed_chars then anim.typed_chars = {} end

  local pad = math.floor(sh * 0.03)
  local frame_x = math.floor(sw * 0.04)
  local frame_w = sw - frame_x * 2
  local frame_y = math.floor(sh * 0.04)
  local frame_h = sh - frame_y * 2
  local inner_x = frame_x + pad
  local inner_y = frame_y + pad

  love.graphics.setColor(term_color[1], term_color[2], term_color[3], 0.25)
  love.graphics.rectangle("line", frame_x, frame_y, frame_w, frame_h)

  local vedal = get_vedal_sprite()
  local sprite_bottom = inner_y
  if vedal and (phase == "LOADING" or phase == "CONNECTED" or phase == "FADE_OUT") then
    local sprite_h = math.floor(frame_h * 0.30)
    local scale = sprite_h / vedal:getHeight()
    local cx = sw / 2
    local cy = inner_y + sprite_h / 2 + pad

    local spin = now2 * 1.5
    local sx_factor = math.max(0.05, math.abs(math.cos(spin)))

    love.graphics.setColor(term_color[1] * 0.2, term_color[2] * 0.2, term_color[3] * 0.2, 0.25)
    love.graphics.draw(vedal, cx + 2, cy + 2, 0,
      scale * sx_factor, scale,
      vedal:getWidth() / 2, vedal:getHeight() / 2)

    love.graphics.setColor(term_color[1], term_color[2], term_color[3], 0.5)
    love.graphics.draw(vedal, cx, cy, 0,
      scale * sx_factor, scale,
      vedal:getWidth() / 2, vedal:getHeight() / 2)

    sprite_bottom = cy + sprite_h / 2 + pad
  end

  local log_y = sprite_bottom + math.floor(pad * 0.5)

  local visible_count = 0
  for i, entry in ipairs(lines) do
    local text, threshold = entry[1], entry[2]
    if load_progress >= threshold then
      visible_count = i

      if not anim.typed_chars[i] then
        anim.typed_chars[i] = { start_time = now2, len = #text }
      end

      local tc = anim.typed_chars[i]
      local chars_elapsed = (now2 - tc.start_time) * TYPE_CPS
      local chars_shown = math.min(tc.len, math.floor(chars_elapsed))
      local display = text:sub(1, chars_shown)

      local pal = anim.cached_pal or Palette.pal()
      local lr, lg, lb = term_color[1], term_color[2], term_color[3]
      if text:find("^%[ERR%]") or text:find("^%[WARN%]") then
        lr, lg, lb = pal.D_ORANGE[1], pal.D_ORANGE[2], pal.D_ORANGE[3]
      elseif text:find("^%[OK%]") then
        lr, lg, lb = pal.D_GREEN[1], pal.D_GREEN[2], pal.D_GREEN[3]
      elseif text:find("^>") then
        lr, lg, lb = pal.D_WHITE[1], pal.D_WHITE[2], pal.D_WHITE[3]
      end

      local y = log_y + (i - 1) * line_h

      if chars_shown < tc.len then
        display = display .. (cursor_on and "_" or " ")
      end

      love.graphics.setColor(lr * 0.3, lg * 0.3, lb * 0.3, 0.5)
      love.graphics.print(display, inner_x + 1, y + 1)
      love.graphics.setColor(lr, lg, lb, 0.95)
      love.graphics.print(display, inner_x, y)
    end
  end

  if visible_count > 0 and load_progress < 1.0 then
    local last_tc = anim.typed_chars[visible_count]
    if last_tc then
      local chars_elapsed = (now2 - last_tc.start_time) * TYPE_CPS
      if chars_elapsed >= last_tc.len and cursor_on then
        local last_text = lines[visible_count][1]
        local y = log_y + (visible_count - 1) * line_h
        love.graphics.setColor(term_color[1], term_color[2], term_color[3], 0.95)
        love.graphics.print(last_text .. "_", inner_x, y)
      end
    end
  end

  if phase == "LOADING" or phase == "CONNECTED" or phase == "FADE_OUT" then
    local bar_y = log_y + #lines * line_h + math.floor(line_h * 0.5)
    local bar_width = 32
    local filled = math.floor(load_progress * bar_width)
    local empty = bar_width - filled
    local pct = math.floor(load_progress * 100)
    local bar_str = "[" .. string.rep("#", filled) .. string.rep(".", empty) .. "] " .. pct .. "%"

    love.graphics.setColor(term_color[1], term_color[2], term_color[3], 0.9)
    love.graphics.print(bar_str, inner_x, bar_y)
  end

  if phase == "CONNECTED" or phase == "FADE_OUT" then
    local greeting = "Hello " .. anim.name .. "!"

    if not anim.greeting_start then anim.greeting_start = now2 end
    local greet_elapsed = now2 - anim.greeting_start
    local greet_chars = math.min(#greeting, math.floor(greet_elapsed * 30))
    local greet_display = greeting:sub(1, greet_chars)
    if greet_chars < #greeting then
      greet_display = greet_display .. (cursor_on and "_" or " ")
    end

    if big_font then love.graphics.setFont(big_font) end
    local gfont = love.graphics.getFont()

    local p = Palette.pal()
    local glow_r = math.min(1, p.GLOW[1] * 1.3)
    local glow_g = math.min(1, p.GLOW[2] * 1.3)
    local glow_b = math.min(1, p.GLOW[3] * 1.3)

    local greet_w = gfont:getWidth(greet_display)
    local greet_x = sw / 2 - greet_w / 2
    local greet_y = frame_y + frame_h - pad - gfont:getHeight() - line_h

    love.graphics.setColor(glow_r, glow_g, glow_b, 0.08)
    love.graphics.print(greet_display, greet_x - 2, greet_y - 2)
    love.graphics.print(greet_display, greet_x + 2, greet_y + 2)
    love.graphics.setColor(glow_r, glow_g, glow_b, 0.12)
    love.graphics.print(greet_display, greet_x - 1, greet_y - 1)
    love.graphics.print(greet_display, greet_x + 1, greet_y + 1)

    love.graphics.setColor(1, 1, 1, 1.0)
    love.graphics.print(greet_display, greet_x, greet_y)

    if small_font then love.graphics.setFont(small_font) end
  end
end

function NeuroAnim.draw_login_anim()
  if not G or not G.NEURO or not G.NEURO.login_anim then return end
  local anim = G.NEURO.login_anim
  local now2 = (G.TIMERS and G.TIMERS.REAL) or (love.timer and love.timer.getTime()) or 0
  local elapsed = now2 - anim.start

  local BOOT      = 0.50
  local LOADING   = 2.40
  local CONNECTED = 1.20
  local FADE_OUT  = 0.60
  local TOTAL = BOOT + LOADING + CONNECTED + FADE_OUT

  if elapsed > TOTAL then
    G.NEURO.login_anim = nil
    return
  end

  if not anim.palette_ready and elapsed >= BOOT + LOADING * 0.35 then
    anim.palette_ready = true
  end

  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()

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
  if phase == "BOOT" then
    local ease = phase_t * phase_t * (3 - 2 * phase_t)
    master_alpha = ease
  elseif phase == "FADE_OUT" then
    local ease = phase_t * phase_t * (3 - 2 * phase_t)
    master_alpha = 1.0 - ease
  end
  master_alpha = math.max(0, math.min(1, master_alpha))

  if not anim.cached_persona then
    local persona = (G.NEURO.persona) or "neuro"
    anim.cached_persona = persona
    anim.cached_evil = (persona == "evil")
    anim.cached_lines = anim.cached_evil and EVIL_LINES or NEURO_LINES
    local p = Palette.pal()
    anim.cached_color = { p.GLOW[1], p.GLOW[2], p.GLOW[3] }
    anim.cached_pal = p
  end
  local is_evil = anim.cached_evil
  local lines = anim.cached_lines
  local term_color = anim.cached_color

  local shader = get_crt_shader()
  local canvas = get_crt_canvas(sw, sh)

  if canvas then
    local prev_canvas = love.graphics.getCanvas()
    local prev_font = love.graphics.getFont()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.01, 0.01, 0.015, 1)

    draw_terminal_content(anim, sw, sh, now2, phase, phase_t, is_evil, lines, term_color)

    love.graphics.setCanvas(prev_canvas)

    if shader then
      love.graphics.setShader(shader)
      shader:send("time", now2)
      shader:send("master_alpha", master_alpha)
      shader:send("tint_color", term_color)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)

    if shader then
      love.graphics.setShader()
    end

    if prev_font then love.graphics.setFont(prev_font) end
  else
    love.graphics.setColor(0.02, 0.02, 0.03, master_alpha)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    local prev_font = love.graphics.getFont()
    draw_terminal_content(anim, sw, sh, now2, phase, phase_t, is_evil, lines, term_color)
    if prev_font then love.graphics.setFont(prev_font) end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
end

return NeuroAnim
