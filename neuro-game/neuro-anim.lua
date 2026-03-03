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
-- LOGIN ANIMATION: full-screen connection cinematic
-- ─────────────────────────────────────────────────────────────
function NeuroAnim.draw_login_anim()
  if not G or not G.NEURO or not G.NEURO.login_anim then return end
  local anim = G.NEURO.login_anim
  local now2 = (G.TIMERS and G.TIMERS.REAL) or (love.timer and love.timer.getTime()) or 0
  local elapsed = now2 - anim.start

  local PRE       = 0.08
  local CHAOS     = 0.65
  local HOLD      = 0.28
  local REVEAL    = 0.60
  local TEXT_SHOW = 1.80
  local FADE_OUT  = 0.40
  local TOTAL = PRE + CHAOS + HOLD + REVEAL + TEXT_SHOW + FADE_OUT

  if elapsed > TOTAL then G.NEURO.login_anim = nil; return end

  if not anim.palette_ready and elapsed >= PRE + CHAOS * 0.35 then
    anim.palette_ready = true
  end

  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()

  local function gh(a, b)
    local x = math.sin(a * 127.1 + b * 311.7 + 3.14159) * 43758.5453
    return x - math.floor(x)
  end
  local function gh2(a, b)
    local x = math.sin(a * 269.5 + b * 183.3 + 1.61803) * 57832.4391
    return x - math.floor(x)
  end

  local gi
  if elapsed < PRE then
    gi = (elapsed / PRE) * 0.28
  elseif elapsed < PRE + CHAOS then
    local t = (elapsed - PRE) / CHAOS
    if t < 0.08 then
      gi = 0.28 + (t / 0.08) * 0.72
    else
      gi = 1.0
    end
  elseif elapsed < PRE + CHAOS + HOLD then
    gi = (1.0 - (elapsed - PRE - CHAOS) / HOLD) * 0.22
  else
    gi = 0
  end
  gi = math.max(0, math.min(1, gi))

  local ba
  if elapsed < PRE then
    ba = (elapsed / PRE) * 0.45
  elseif elapsed < PRE + CHAOS then
    ba = 0.45 + ((elapsed - PRE) / CHAOS) * 0.55
  elseif elapsed < PRE + CHAOS + HOLD then
    ba = 1.0
  elseif elapsed < PRE + CHAOS + HOLD + REVEAL then
    ba = 1.0 - (elapsed - PRE - CHAOS - HOLD) / REVEAL
  else
    ba = 0
  end
  ba = math.max(0, math.min(1, ba))

  love.graphics.setColor(0, 0, 0, ba)
  love.graphics.rectangle("fill", 0, 0, sw, sh)

  if gi > 0.005 then
    local f20  = math.floor(now2 * 20)
    local f30  = math.floor(now2 * 30)
    local f50  = math.floor(now2 * 50)
    local f80  = math.floor(now2 * 80)
    local f12  = math.floor(now2 * 12)
    local f16  = math.floor(now2 * 16)
    local f22  = math.floor(now2 * 22)

    local step = gi > 0.80 and 2 or (gi > 0.50 and 3 or 5)
    love.graphics.setColor(0, 0, 0, 0.35 * gi)
    for sy = 0, sh - 1, step do
      love.graphics.rectangle("fill", 0, sy, sw, 1)
    end

    love.graphics.setColor(0.04, 0.04, 0.06, 0.18 * gi)
    for sx = 0, sw - 1, step do
      love.graphics.rectangle("fill", sx, 0, 1, sh)
    end

    local col_n = math.floor(gi * gi * 40)
    for i = 1, col_n do
      local cx = math.floor(gh(i,       f50) * sw)
      local cw = math.floor(gh(i + 0.1, f50) * 18) + 1
      local ch = math.floor(gh(i + 0.2, f50) * sh * 0.88) + 8
      local cy = math.floor(gh(i + 0.3, f50) * math.max(1, sh - ch))
      local r4 = gh(i + 0.4, f50)
      local g4 = gh(i + 0.5, f50)
      local b4 = gh(i + 0.6, f50)
      love.graphics.setColor(r4, g4, b4, gi * 0.65)
      love.graphics.rectangle("fill", cx, cy, cw, ch)
    end

    local row_n = math.floor(gi * gi * 45)
    for i = 1, row_n do
      local ry  = math.floor(gh(i,       f20) * sh)
      local rw  = math.floor(gh(i + 0.1, f20) * sw * 0.95) + 40
      local rx  = math.floor(gh(i + 0.2, f20) * math.max(1, sw - rw))
      local rh  = math.max(1, math.floor(gh(i + 0.3, f20) * 12) + 1)
      local br  = 0.35 + gh(i + 0.5, f20) * 0.60
      local hue = gh(i + 0.7, f20)
      love.graphics.setColor(
        math.min(1, br * (0.65 + hue * 0.35)),
        math.min(1, br * (0.65 + gh(i + 0.8, f20) * 0.35)),
        math.min(1, br * (0.85 + gh(i + 0.9, f20) * 0.15)),
        gi * 0.96)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
    end

    if gi > 0.25 then
      local mosh_n = math.floor((gi - 0.25) / 0.75 * 28)
      for i = 1, mosh_n do
        local mx  = math.floor(gh2(i * 2,     f80) * sw)
        local my  = math.floor(gh2(i * 2 + 1, f80) * sh)
        local mw  = math.floor(gh2(i * 2 + 2, f80) * 200) + 12
        local mhh = math.floor(gh2(i * 2 + 3, f80) * 70)  + 5
        local hm  = gh2(i, f80)
        love.graphics.setColor(
          math.abs(math.sin(hm * 6.28318 + 0.000)),
          math.abs(math.sin(hm * 6.28318 + 2.094)),
          math.abs(math.sin(hm * 6.28318 + 4.189)),
          gi * 0.78)
        love.graphics.rectangle("fill", mx, my, mw, mhh)
      end
    end

    local nn = math.floor(gi * 140)
    for i = 1, nn do
      local nx = math.floor(gh(i,       f30 + 1111) * sw)
      local ny = math.floor(gh(i + 0.2, f30 + 1111) * sh)
      local nw = math.floor(gh(i + 0.4, f30 + 1111) * 28) + 1
      local nh = math.floor(gh(i + 0.6, f30 + 1111) * 8)  + 1
      local gr = 0.10 + gh(i + 0.8, f30 + 1111) * 0.88
      love.graphics.setColor(gr, gr * 0.95, gr, gi * 0.65)
      love.graphics.rectangle("fill", nx, ny, nw, nh)
    end

    local fringe = math.floor(gi * gi * 110)
    if fringe > 0 then
      love.graphics.setColor(1.0, 0.0, 0.06, gi * 0.42)
      love.graphics.rectangle("fill", 0, 0, fringe, sh)
      love.graphics.setColor(0.04, 0.12, 1.0, gi * 0.42)
      love.graphics.rectangle("fill", sw - fringe, 0, fringe, sh)
      love.graphics.setColor(0.0, 1.0, 0.08, gi * 0.18)
      love.graphics.rectangle("fill", math.floor(fringe / 2), 0, math.max(1, math.floor(fringe / 3)), sh)
    end

    if gi > 0.40 then
      for bi = 1, 3 do
        local band_y = math.floor(gh(bi * 3, f12) * sh)
        local band_h = math.floor(gi * 80) + 10
        local sep    = math.floor(gi * 22) + bi * 4
        love.graphics.setColor(1.0, 0.02, 0.02, gi * 0.16)
        love.graphics.rectangle("fill", 0, band_y - sep, sw, band_h)
        love.graphics.setColor(0.02, 0.02, 1.0, gi * 0.16)
        love.graphics.rectangle("fill", 0, band_y + sep, sw, band_h)
        love.graphics.setColor(0.02, 1.0, 0.40, gi * 0.07)
        love.graphics.rectangle("fill", 0, band_y,        sw, math.floor(band_h / 3))
      end
    end

    local speeds = { 38, 73, 119, 211 }
    local alphas = { 0.22, 0.15, 0.09, 0.05 }
    for ti = 1, 4 do
      local ty2 = math.floor((now2 * speeds[ti]) % sh)
      love.graphics.setColor(1, 1, 1, gi * alphas[ti])
      love.graphics.rectangle("fill", 0, ty2, sw, 2 + ti)
      love.graphics.setColor(0, 0, 0, gi * alphas[ti] * 0.60)
      love.graphics.rectangle("fill", 0, (ty2 + 7) % sh, sw, ti + 1)
    end

    if gi > 0.45 then
      local drop_n = math.floor((gi - 0.45) / 0.55 * 16)
      for i = 1, drop_n do
        local dx = math.floor(gh2(i * 5,     f80 + 555) * sw)
        local dw = math.floor(gh2(i * 5 + 1, f80 + 555) * 10) + 1
        local dr = gh2(i, f80 + 555)
        love.graphics.setColor(math.min(1, dr * 2), 1, dr * 0.80, gi * 0.60)
        love.graphics.rectangle("fill", dx, 0, dw, sh)
      end
    end

    if gi > 0.60 then
      local flicker = gh(9, f16)
      if flicker > 0.48 then
        local fi = (flicker - 0.48) / 0.52
        love.graphics.setColor(1, 0.85, 1, fi * fi * 0.38 * gi)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.80 then
      local sv = gh(1, f22)
      if sv > 0.68 then
        love.graphics.setColor(1, 1, 1, 0.60 * gi)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.93 then
      local sv2 = gh2(3, math.floor(now2 * 28))
      if sv2 > 0.82 then
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.70 then
      local seg_n = math.floor((gi - 0.70) / 0.30 * 6)
      for i = 1, seg_n do
        local sx2 = math.floor(gh(i * 11, f50 + 777) * sw)
        local sw2 = math.floor(sw / seg_n)
        local off = math.floor((gh(i, f50 + 777) - 0.5) * gi * 30)
        love.graphics.setColor(1, 1, 1, 0.08 * gi)
        love.graphics.rectangle("fill", sx2, off, sw2, sh)
      end
    end
  end

  local text_start = PRE + CHAOS + HOLD
  if elapsed >= text_start then
    local te = elapsed - text_start
    local full_text = "Hello " .. anim.name .. "!"
    local TYPE_DUR = 0.68
    local char_count = math.floor(math.min(1, te / TYPE_DUR) * #full_text)
    local display_text = full_text:sub(1, char_count)
    if char_count < #full_text then
      display_text = display_text .. (math.floor(now2 * 4) % 2 == 0 and "_" or " ")
    end

    local ta = 1.0
    if te < 0.20 then ta = te / 0.20 end
    local text_total = REVEAL + TEXT_SHOW + FADE_OUT
    if te > text_total - FADE_OUT then ta = math.max(0, (text_total - te) / FADE_OUT) end

    local p = Palette.pal()
    local panel_font, _ = get_anim_fonts()
    local prev_font = love.graphics.getFont()
    if panel_font then love.graphics.setFont(panel_font) end
    local f = love.graphics.getFont()
    local tw = f:getWidth(display_text)
    local th = f:getHeight()
    local cx = sw / 2 - tw / 2
    local cy2 = sh / 2 - th / 2

    love.graphics.setColor(0, 0, 0, 0.72 * ta)
    love.graphics.rectangle("fill", 0, sh / 2 - 48, sw, 96)

    love.graphics.setColor(p.PRIMARY[1], p.PRIMARY[2], p.PRIMARY[3], 0.22 * ta)
    love.graphics.rectangle("fill", 0, sh / 2 - 48, sw, 96)

    love.graphics.setColor(p.GLOW[1], p.GLOW[2], p.GLOW[3], 0.55 * ta)
    love.graphics.setLineWidth(2)
    love.graphics.line(0, sh / 2 - 48, sw, sh / 2 - 48)
    love.graphics.line(0, sh / 2 + 48, sw, sh / 2 + 48)

    love.graphics.setColor(p.GLOW[1] * 0.5, p.GLOW[2] * 0.5, p.GLOW[3] * 0.5, 0.20 * ta)
    love.graphics.line(0, sh / 2 - 44, sw, sh / 2 - 44)
    love.graphics.line(0, sh / 2 + 44, sw, sh / 2 + 44)
    love.graphics.setLineWidth(1)

    local pulse = 0.5 + 0.5 * math.sin(now2 * 5.5)
    local glow_r = math.min(1, p.GLOW[1] * 1.1)
    local glow_g = math.min(1, p.GLOW[2] * 1.1)
    local glow_b = math.min(1, p.GLOW[3] * 1.1)

    for radius = 4, 1, -1 do
      local ga = (0.08 - radius * 0.015) * (0.7 + 0.3 * pulse) * ta
      love.graphics.setColor(glow_r, glow_g, glow_b, ga)
      for dx = -radius, radius do
        for dy = -radius, radius do
          if math.abs(dx) == radius or math.abs(dy) == radius then
            love.graphics.print(display_text, cx + dx, cy2 + dy)
          end
        end
      end
    end

    love.graphics.setColor(1, 0.96, 1, 0.98 * ta)
    love.graphics.print(display_text, cx, cy2)

    if prev_font then love.graphics.setFont(prev_font) end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
end

return NeuroAnim
