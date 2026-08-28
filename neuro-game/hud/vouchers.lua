local S = require("hud.state")
local Prims = require("hud.prims")
local round = Prims.round
local Cards = require("hud.cards")
local Utils = require("util.utils")
local Palette = require("render.palette")
local StateKinds = require("core.state_kinds")
local DebuffFacts = require("facts.debuff_facts")
local HudShared = require("render.hud_shared")
local set_col = HudShared.set_col
local shadow_text = HudShared.shadow_text

local Motion = Prims.Motion
local smoothstep01 = Prims.smoothstep01
local print_tracked = Prims.print_tracked
local tracked_width = Prims.tracked_width
local CAROUSEL_PERIOD = HudShared.CAROUSEL_PERIOD
local draw_cached_tracked_text = HudShared.draw_cached_tracked_text

local Vouchers = {}

local BASE_W = 320
local PAD = 10
local HEADER_H = 26
local ROW_H = 46
local VIS = 1
local GAP_TOP = 20
local IN_D = 0.35
local GLOW_D = 1.8
local TRACK_SM = 1
local SWEEP_DELAY, SWEEP_D = 0.05, 0.45
local SWEEP_W, SWEEP_SLANT = 18, 10
local ANIM_LIFE = math.max(IN_D, GLOW_D, SWEEP_DELAY + SWEEP_D)
local COUNT_PULSE_D = 0.4
local ROT_SLIDE_D = 0.35
local ROT_ACQ_HOLD = 2.5
local MAX_SEG_PAIRS = 12

local _GOLD, _ACC, _BG, _FR, _FRD, _WHITE, _DIM, _MONEY, _GLOW
local _SLIDE, _BADGE_W, _PULSE = 0, 0, 0
local _TH, _MO, _FRAME_OPTS = {}, {}, {}
local _CNT_C = { 0, 0, 0 }

local _cnt_str, _cnt_w, _cnt_n, _cnt_idx, _cnt_font = "0", 0, nil, nil, nil
local function count_label(n, rot_idx, fs)
  if n == _cnt_n and rot_idx == _cnt_idx and fs == _cnt_font then
    return _cnt_str, _cnt_w
  end
  local s = n > VIS and (tostring(rot_idx) .. "/" .. n) or tostring(n)
  local w = fs:getWidth(s)
  _cnt_str, _cnt_w, _cnt_n, _cnt_idx, _cnt_font = s, w, n, rot_idx, fs
  return s, w
end
local _TITLE_BLOCK = {
  shadow_color = { 0, 0, 0 },
  main_color = false,
  shadow_alpha = 0.5,
  main_alpha = 0.95,
  shadow_dx = 1,
  shadow_dy = 1,
}

local _name_cache = {}

local function voucher_name(key)
  local cached = _name_cache[key]
  if cached ~= nil then return cached end
  local name
  local c = G and G.P_CENTERS and G.P_CENTERS[key]
  if c and c.loc_txt and c.loc_txt.name and c.loc_txt.name ~= "" then
    name = tostring(c.loc_txt.name)
  elseif c and c.name and c.name ~= "" then
    name = tostring(c.name)
  elseif Utils.humanize_identifier then
    name = Utils.humanize_identifier(key)
  else
    name = (tostring(key):gsub("^v_", ""))
  end
  _name_cache[key] = name
  return name
end

local function voucher_effect(key)
  local fx = S.voucher_fx[key]
  if fx ~= nil then return fx end
  if not (G and G.P_CENTERS and G.P_CENTERS[key]) then return "" end
  local ok, txt = pcall(DebuffFacts.voucher_effect_text, key)
  fx = (ok and type(txt) == "string") and txt:gsub("%s+", " ") or ""
  S.voucher_fx[key] = fx
  return fx
end

local function is_tier2(key)
  local t2 = S.voucher_tier2[key]
  if t2 ~= nil then return t2 end
  local c = G and G.P_CENTERS and G.P_CENTERS[key]
  t2 = (c and type(c.requires) == "table" and #c.requires > 0) or false
  S.voucher_tier2[key] = t2
  return t2
end

local function effect_segments(key)
  local cached = S.voucher_seg[key]
  if cached ~= nil then return cached end
  if not (G and G.P_CENTERS and G.P_CENTERS[key]) then return false end
  local fx = voucher_effect(key)
  if fx == "" then S.voucher_seg[key] = false; return false end
  local seg = {}
  local pos, golds = 1, 0
  local len = #fx
  while pos <= len do
    local s, e = fx:find("[%+%-]?[%$Xx]?%d[%d%.,]*%%?", pos)
    if not s then break end
    local first = fx:sub(s, s)
    if (first == "X" or first == "x") and s > 1 and fx:sub(s - 1, s - 1):match("%w") then
      s = s + 1
    end
    golds = golds + 1
    if golds > MAX_SEG_PAIRS then S.voucher_seg[key] = false; return false end
    if s > pos then
      seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = fx:sub(pos, s - 1), false, 0
    end
    seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = fx:sub(s, e), true, 0
    pos = e + 1
  end
  if golds == 0 then S.voucher_seg[key] = false; return false end
  if pos <= len then
    seg[#seg + 1], seg[#seg + 2], seg[#seg + 3] = fx:sub(pos), false, 0
  end
  S.voucher_seg[key] = seg
  return seg
end

local _keys_a, _keys_b, _in_order = {}, {}, {}

local drop_last_codepoint = Utils.drop_last_codepoint

local function fit_segments(key, segs, max_px, fs)
  local fit = S.voucher_seg_fit[key]
  if not fit then fit = {}; S.voucher_seg_fit[key] = fit end
  if fit.w == max_px then return fit end
  local n, cum = 0, 0
  for i = 1, #segs, 3 do
    local str = segs[i]
    local w = fs:getWidth(str)
    if cum + w <= max_px then
      fit[n + 1], fit[n + 2], fit[n + 3] = str, segs[i + 1], w
      n = n + 3
      cum = cum + w
    else
      local avail = max_px - cum
      local t = str
      local tw = fs:getWidth(t .. "..")
      while tw > avail and #t > 0 do
        t = drop_last_codepoint(t)
        tw = fs:getWidth(t .. "..")
      end
      if tw <= avail and #t > 0 then
        fit[n + 1], fit[n + 2], fit[n + 3] = t .. "..", segs[i + 1], tw
        n = n + 3
      end
      break
    end
  end
  local old = fit.n or 0
  fit.n = n
  fit.w = max_px
  for i = n + 1, old do fit[i] = nil end
  return fit
end

local function draw_effect_segments(fit, tx, ey, a)
  local cx = tx
  for i = 1, fit.n, 3 do
    local str, gold, w = fit[i], fit[i + 1], fit[i + 2]
    shadow_text(str, cx, ey, gold and _MONEY or _DIM, (gold and 0.95 or 0.92) * a, 0.4 * a)
    cx = cx + w
  end
end

local function tray_height(n, rn)
  if n <= 0 then return 0 end
  return rn(HEADER_H) + math.min(n, VIS) * rn(ROW_H) + rn(8)
end

local function tray_frame(ctx)
  if not (ctx and ctx.p_x and ctx.p_y and ctx.pw and ctx.panel_h) then return nil end
  if not (G and G.GAME and G.NEURO) then return nil end
  local sn = G.NEURO.state or ""
  if StateKinds.is_menu_state(sn) or G.OVERLAY_MENU then
    if not G.NEURO.dev_preview_active then return nil end
  end
  local frac = S.drawer_slide_current or 0
  if frac <= 0.004 then return nil end
  local n = #(S.voucher_order or {})
  if n == 0 then return nil end
  local body_h = S.drawer_h_current or 0
  if body_h <= 1 then return nil end

  local rn = ctx.rn or function(v) return v end
  local pad = rn(PAD)
  local gap = rn(GAP_TOP)
  local tray_w = math.min(rn(BASE_W), ctx.pw)
  local tray_x = ctx.p_x + ctx.pw - tray_w
  local y0 = ctx.p_y + ctx.panel_h
  if ctx.sh then
    local clip_h = math.min(gap + body_h + rn(4), ctx.sh - y0)
    if clip_h <= 1 then return nil end
  end

  local ease = smoothstep01(frac)
  local slide = (1 - ease) * (body_h + gap)
  local ty = y0 + gap - slide
  local header_h = rn(HEADER_H)
  local gy = ty + header_h
  local row_h = rn(ROW_H)
  local cell_w = tray_w - pad * 2

  return { tray_x = tray_x, tray_w = tray_w, pad = pad, gy = gy, row_h = row_h,
    cell_w = cell_w, rn = rn }
end

function Vouchers.flight_target(ctx)
  local fr = tray_frame(ctx)
  if not fr then return nil end
  local rn = fr.rn
  local inset = rn(5)
  local art_h = fr.row_h - inset * 2
  local art_w = round(art_h * (71 / 95))
  local rx = fr.tray_x + fr.pad
  return { x = rx, y = fr.gy, w = fr.cell_w, h = fr.row_h,
    art_x = rx, art_y = fr.gy + inset, art_w = art_w, art_h = art_h }
end

function Vouchers.update(now, rn, _sw, _sh)
  rn = rn or function(v) return v end
  if not (G and G.GAME and G.GAME.used_vouchers) then
    S.known_voucher_keys = nil
    S.voucher_game_ref = nil
    S.voucher_order = {}
    S.voucher_count_pulse_at = 0
    S.drawer_reserve = 0
    S.drawer_reserve_target = 0
    return
  end

  if G.GAME ~= S.voucher_game_ref then
    S.voucher_order, S.voucher_anim = {}, {}
    _name_cache = {}
    S.known_voucher_keys = nil
    S.voucher_game_ref = G.GAME
    S.voucher_count_pulse_at = 0
    S.drawer_h_current = 0
  end
  local first_obs = S.known_voucher_keys == nil
  local cur = (S.known_voucher_keys == _keys_a) and _keys_b or _keys_a
  for k in pairs(cur) do cur[k] = nil end
  local gate = S.voucher_drawer_gate
  for k, v in pairs(G.GAME.used_vouchers) do
    if v then
      local gv = gate and gate[k]
      local held = gv ~= nil and gv.release_at == nil and now < (gv.safety_at or 0)
        and not (S.known_voucher_keys and S.known_voucher_keys[k])
      if not held then
        if gv then gate[k] = nil end
        cur[k] = true
      end
    end
  end
  local added = false
  if first_obs then
    local seed = {}
    for k in pairs(cur) do seed[#seed + 1] = k end
    table.sort(seed)
    S.voucher_order = seed
    S.voucher_rot_idx, S.voucher_rot_prev = 1, 1
    S.voucher_rot_hold_until, S.voucher_rot_slide_at = 0, 0
    S.voucher_rot_anchor, S.voucher_rot_epoch = now, 0
  else
    local order = S.voucher_order
    local in_order = _in_order
    for k in pairs(in_order) do in_order[k] = nil end
    for i = 1, #order do in_order[order[i]] = true end
    for k in pairs(cur) do
      if not S.known_voucher_keys[k] and not in_order[k] then
        order[#order + 1] = k
        S.voucher_anim[k] = { at = now }
        added = true
      end
    end
    if added then
      S.voucher_count_pulse_at = now
    end
    for i = #order, 1, -1 do
      local k = order[i]
      if not cur[k] then
        table.remove(order, i)
        S.voucher_anim[k] = nil
      end
    end
  end
  S.known_voucher_keys = cur

  local n = #S.voucher_order
  local epoch = math.floor((now - S.voucher_rot_anchor) / CAROUSEL_PERIOD)
  if n <= VIS then
    S.voucher_rot_idx, S.voucher_rot_prev = 1, 1
    S.voucher_rot_slide_at = 0
    S.voucher_rot_epoch = epoch
  else
    if S.voucher_rot_idx > n then
      S.voucher_rot_idx, S.voucher_rot_prev = 1, 1
      S.voucher_rot_slide_at = 0
    end
    if added then
      S.voucher_rot_idx = n - VIS + 1
      S.voucher_rot_prev = S.voucher_rot_idx
      S.voucher_rot_hold_until = now + ROT_ACQ_HOLD
      S.voucher_rot_epoch = epoch
      S.voucher_rot_slide_at = 0
    elseif now < (S.voucher_rot_hold_until or 0) then
      S.voucher_rot_epoch = epoch
    elseif epoch ~= S.voucher_rot_epoch then
      S.voucher_rot_prev = S.voucher_rot_idx
      S.voucher_rot_idx = (S.voucher_rot_idx % n) + 1
      S.voucher_rot_epoch = epoch
      S.voucher_rot_slide_at = now
    end
  end

  local sn = (G.NEURO and G.NEURO.state) or ""
  local in_run = not StateKinds.is_menu_state(sn) and not G.OVERLAY_MENU
  if not in_run then in_run = (G.NEURO and G.NEURO.dev_preview_active) or false end
  local target = (n > 0 and in_run) and 1 or 0
  Motion.tween(S, "drawer_slide", target, now, Motion.MED)

  local tray_h = tray_height(n, rn)
  S.drawer_h_current = tray_h
  local full_reserve = tray_h + rn(GAP_TOP) + rn(4)
  S.drawer_reserve = smoothstep01(S.drawer_slide_current) * full_reserve
  S.drawer_reserve_target = target * full_reserve
end

local function draw_row(ctx, key, x, y, w, h, ga, now)
  local rn, fs = ctx.rn, ctx.font_small
  local a = ga
  local glow = 0
  local anim = S.voucher_anim[key]
  if anim then
    local age = now - anim.at
    a = ga * Motion.anim01(age, IN_D)
    if age < GLOW_D then
      local r = 1 - age / GLOW_D
      glow = r * r
    end
    if age > ANIM_LIFE then S.voucher_anim[key] = nil end
  end
  if a <= 0.01 then return end
  if glow > 0 then
    set_col(_GOLD, 0.10 * glow * ga)
    love.graphics.rectangle("fill", x - rn(3), y + 1, w + rn(6), h - 2, rn(3), rn(3))
    set_col(_GOLD, 0.55 * glow * ga)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - rn(3), y + 1, w + rn(6), h - 2, rn(3), rn(3))
  end

  local fs_h = fs:getHeight()
  local t2 = is_tier2(key)

  local inset = rn(5)
  local art_h = h - inset * 2
  local art_w = round(art_h * (71 / 95))
  local ay = y + inset
  love.graphics.setColor(0, 0, 0, 0.35 * a)
  love.graphics.rectangle("fill", x - 1, ay - 1, art_w + 2, art_h + 2, 2, 2)
  if a > 0.5 then
    local wcard = S.voucher_wrap[key]
    if not wcard and G.P_CENTERS and G.P_CENTERS[key] then
      wcard = { config = { center = G.P_CENTERS[key] } }
      S.voucher_wrap[key] = wcard
    end
    if wcard then pcall(Cards.draw_card_mini, wcard, x, ay, art_h) end
  end
  if t2 then
    set_col(_GOLD, 0.30 * a)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - 1, ay - 1, art_w + 2, art_h + 2, 2, 2)
  end

  local tx = x + art_w + rn(8)
  local tw = w - art_w - rn(8)
  if t2 then
    local bw = _BADGE_W
    local bh = fs_h + rn(3)
    local bx = x + w - bw
    local by = y + rn(5)
    love.graphics.setColor(0, 0, 0, 0.5 * a)
    love.graphics.rectangle("fill", bx + 1, by + 1, bw, bh)
    set_col(_BG, 0.97 * a)
    love.graphics.rectangle("fill", bx, by, bw, bh)
    set_col(_GOLD, 0.90 * a)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", bx, by, bw, bh)
    love.graphics.setFont(fs)
    print_tracked("II", bx + rn(4), by + math.floor((bh - fs_h) / 2), rn(TRACK_SM), fs)
    tw = tw - bw - rn(4)
  end
  if tw <= rn(10) then return end

  love.graphics.setFont(fs)
  local ny = y + rn(6)
  local name = ctx.trunc(voucher_name(key), tw, fs)
  shadow_text(name, tx, ny, _WHITE, 0.96 * a, 0.5 * a)
  local ey = ny + fs_h + rn(3)
  local segs = effect_segments(key)
  if segs then
    draw_effect_segments(fit_segments(key, segs, tw, fs), tx, ey, a)
  else
    local fx = voucher_effect(key)
    if fx ~= "" then
      local fxt = ctx.trunc(fx, tw, fs)
      shadow_text(fxt, tx, ey, _DIM, 0.92 * a, 0.4 * a)
    end
  end

  if anim then
    local st = (now - anim.at - SWEEP_DELAY) / SWEEP_D
    if st > 0 and st < 1 then
      local sx1, sy1, sw1, sh1 = love.graphics.getScissor()
      love.graphics.intersectScissor(x, y - _SLIDE, w, h)
      local bw2, sl = rn(SWEEP_W), rn(SWEEP_SLANT)
      local bx2 = x - bw2 - sl + (w + 2 * (bw2 + sl)) * st
      set_col(_WHITE, 0.16 * a * math.sin(math.pi * st))
      love.graphics.polygon("fill", bx2, y + h, bx2 + sl, y, bx2 + sl + bw2, y, bx2 + bw2, y + h)
      if sx1 then love.graphics.setScissor(sx1, sy1, sw1, sh1) else love.graphics.setScissor() end
    end
  end
end

local function draw_connection(rn, x, ty, pb_y, ga, evil, neuro)
  local plate_y = ty - rn(2)
  local ph = rn(7)
  local py = plate_y - ph
  local wire = (evil or neuro) and _ACC or _GOLD

  if py - pb_y > rn(2) then
    if evil then
      set_col(wire, 0.60 * ga)
      love.graphics.setLineWidth(math.max(1, rn(2)))
      love.graphics.line(x, pb_y, x, py)
      local my = math.floor((pb_y + py) / 2)
      Prims.draw_diamond(x, my, rn(1), wire, 0.85 * ga)
    elseif neuro then
      set_col(wire, 0.60 * ga)
      love.graphics.setLineWidth(math.max(1, rn(2)))
      love.graphics.line(x, pb_y, x, py)
      local my = math.floor((pb_y + py) / 2)
      Prims.draw_heart(x, my, rn(3), _GLOW, 0.85 * ga)
    else
      set_col(_GOLD, 0.70 * ga)
      love.graphics.setLineWidth(math.max(1, rn(2)))
      love.graphics.line(x, pb_y, x, py)
      love.graphics.setColor(1, 1, 1, 0.12 * ga)
      love.graphics.setLineWidth(1)
      love.graphics.line(x - 1, pb_y, x - 1, py)
    end
  end

  love.graphics.setColor(0, 0, 0, 0.4 * ga)
  love.graphics.rectangle("fill", x - rn(4) + 1, py + 1, rn(8), ph, rn(2), rn(2))
  set_col(wire, (0.80 + 0.10 * _PULSE) * ga)
  love.graphics.rectangle("fill", x - rn(4), py, rn(8), ph, rn(2), rn(2))

  set_col(_BG, 0.97 * ga)
  love.graphics.rectangle("fill", x - rn(6), plate_y, rn(12), rn(5), rn(2), rn(2))
  set_col(_FR, 0.95 * ga)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - rn(6), plate_y, rn(12), rn(5), rn(2), rn(2))
end

function Vouchers.draw(ctx)
  if not (ctx and G and G.GAME and G.NEURO) then return end
  local sn = G.NEURO.state or ""
  if StateKinds.is_menu_state(sn) or G.OVERLAY_MENU then
    if not G.NEURO.dev_preview_active then return end
  end
  local frac = S.drawer_slide_current or 0
  if frac <= 0.004 then return end
  local n = #(S.voucher_order or {})
  if n == 0 then return end

  local now, rn, pal = ctx.now, ctx.rn, ctx.pal
  local row_h = rn(ROW_H)
  local shown = math.min(n, VIS)
  local body_h = S.drawer_h_current or 0
  if body_h <= 1 then return end

  _GOLD = pal.D_GOLD or { 0.92, 0.71, 0.13 }
  _ACC = pal.ACCENT or _GOLD
  _BG = pal.PANEL_BG or pal.BG or { 0.08, 0.08, 0.1 }
  _FR = pal.FRAME or { 0.5, 0.5, 0.5 }
  _FRD = pal.FRAME_DIM or _FR
  _WHITE = pal.D_WHITE or { 1, 1, 1 }
  _DIM = pal.D_DIM or { 0.7, 0.7, 0.7 }
  _MONEY = pal.D_MONEY or _GOLD
  _PULSE = ctx.pulse or 0
  local persona_key = (Palette.displayed_persona and Palette.displayed_persona()) or ""
  local evil = persona_key == "evil"
  local neuro = persona_key == "neuro"
  _GLOW = pal.GLOW or _ACC
  local shr, shg, shb = _ACC[1], _ACC[2], _ACC[3]
  if neuro then
    local st2 = Motion.pulse(now, 1.25)
    shr = _ACC[1] + (_GLOW[1] - _ACC[1]) * st2
    shg = _ACC[2] + (_GLOW[2] - _ACC[2]) * st2
    shb = _ACC[3] + (_GLOW[3] - _ACC[3]) * st2
  elseif evil then
    local st2 = Motion.pulse(now, 1.1)
    local em = pal.ACCENT or _GOLD
    shr = _GOLD[1] + (em[1] - _GOLD[1]) * st2
    shg = _GOLD[2] + (em[2] - _GOLD[2]) * st2
    shb = _GOLD[3] + (em[3] - _GOLD[3]) * st2
  end

  local pad = rn(PAD)
  local gap = rn(GAP_TOP)
  local tray_w = math.min(rn(BASE_W), ctx.pw)
  local tray_x = ctx.p_x + ctx.pw - tray_w
  local y0 = ctx.p_y + ctx.panel_h
  local clip_h = math.min(gap + body_h + rn(4), ctx.sh - y0)
  if clip_h <= 1 then return end

  local ease = smoothstep01(frac)
  local ga = ease
  local slide = (1 - ease) * (body_h + gap)
  _SLIDE = slide
  local prev_font = love.graphics.getFont()

  love.graphics.setScissor(tray_x - rn(3), y0, tray_w + rn(8), clip_h)
  love.graphics.push()
  love.graphics.translate(0, -slide)
  local ty = y0 + gap
  _TH.persona_evil, _TH.persona_neuro = evil, neuro
  _TH.bg, _TH.FR, _TH.FRD, _TH.GOLD, _TH.pg = _BG, _FR, _FRD, _GOLD, _GLOW
  _MO.pulse, _MO.shimr, _MO.shimg, _MO.shimb = _PULSE, shr, shg, shb
  _FRAME_OPTS.a, _FRAME_OPTS.rad, _FRAME_OPTS.title_h, _FRAME_OPTS.quiet =
    ga, rn(9), rn(HEADER_H), true
  local rad = HudShared.persona_frame(_TH, _MO, tray_x, ty, tray_w, body_h, rn(1), _FRAME_OPTS)
  if body_h > rn(12) then
    love.graphics.setColor(0, 0, 0, 0.25 * ga)
    love.graphics.rectangle("fill", tray_x + rn(3), ty + body_h - rn(5), tray_w - rn(6), rn(3))
    love.graphics.setColor(1, 1, 1, 0.05 * ga)
    love.graphics.rectangle("fill", tray_x + rad, ty + 1, tray_w - rad * 2, 1)
  end
  if evil and body_h > rn(20) then
    HudShared.evil_frame(tray_x, ty, tray_w, body_h, rn(1), rn(HEADER_H), _GOLD, _GLOW, _BG, _PULSE, now, ga, 0)
    local chx = tray_x + tray_w - rn(16)
    local k2 = 0
    if S.voucher_count_pulse_at > 0 then
      k2 = math.max(0, 1 - Motion.anim01(now - S.voucher_count_pulse_at, COUNT_PULSE_D))
    end
    local ch_sway = math.sin(now * 1.4) * rn(2) * (1 + 3 * k2)
    Prims.chains(chx, ty + body_h - 1, ty + body_h - 1 + rn(7), rn(1), _ACC, ga, ch_sway)
    Prims.wax_seal(chx + ch_sway, ty + body_h + rn(9), rn(3), rn(1), _GOLD, 0.9 * ga, _PULSE, true, now)
  end
  if neuro and body_h > rn(20) then
    local chx = tray_x + tray_w - rn(16)
    local ch_sway = math.sin(now * 1.6) * rn(2)
    love.graphics.setColor(shr, shg, shb, 0.65 * ga)
    love.graphics.setLineWidth(1)
    love.graphics.line(chx, ty + body_h - 1, chx + ch_sway, ty + body_h + rn(6))
    Prims.draw_heart(chx + ch_sway, ty + body_h + rn(9), rn(3), _GLOW, 0.9 * ga)
  end

  local fs = ctx.font_small
  local fs_h = fs:getHeight()
  love.graphics.setFont(fs)
  _BADGE_W = tracked_width("II", rn(TRACK_SM), fs) + rn(8)
  local header_h = rn(HEADER_H)
  local hy = ty + math.floor((header_h - 2 - fs_h) / 2)
  local title_x = tray_x + pad + rn(12)
  _TITLE_BLOCK.font, _TITLE_BLOCK.track = fs, rn(TRACK_SM)
  _TITLE_BLOCK.main_color, _TITLE_BLOCK.tint_alpha = _ACC, ga
  _TITLE_BLOCK.dynamic_color = false -- alpha is the draw tint; the cached RGB stays fixed
  local title_cached, title_w = draw_cached_tracked_text(
    ctx, "voucher_header_title", "VOUCHERS", title_x, hy, _TITLE_BLOCK)
  local title_end = title_x + (title_w or tracked_width("VOUCHERS", rn(TRACK_SM), fs))
  if not title_cached then
    love.graphics.setColor(0, 0, 0, 0.5 * ga)
    print_tracked("VOUCHERS", title_x + 1, hy + 1, rn(TRACK_SM), fs)
    set_col(_ACC, 0.95 * ga)
    title_end = print_tracked("VOUCHERS", title_x, hy, rn(TRACK_SM), fs)
  end

  local cnt, cw = count_label(n, S.voucher_rot_idx, fs)
  local k = 0
  if S.voucher_count_pulse_at > 0 then
    k = 1 - Motion.anim01(now - S.voucher_count_pulse_at, COUNT_PULSE_D)
  end
  local cx = tray_x + tray_w - pad - cw
  local cy = hy - round(rn(3) * k)
  _CNT_C[1] = _GOLD[1] + (1 - _GOLD[1]) * k
  _CNT_C[2] = _GOLD[2] + (1 - _GOLD[2]) * k
  _CNT_C[3] = _GOLD[3] + (1 - _GOLD[3]) * k
  shadow_text(cnt, cx, cy, _CNT_C, 0.95 * ga, 0.5 * ga, 1)

  local ly = hy + math.floor(fs_h / 2)
  set_col(_GOLD, 0.35 * ga)
  local lw1 = (title_x - rn(5)) - (tray_x + pad)
  if lw1 >= rn(4) then love.graphics.rectangle("fill", tray_x + pad, ly, lw1, 1) end
  local rx1 = title_end + rn(5)
  local lw2 = (cx - rn(6)) - rx1
  if lw2 >= rn(4) then love.graphics.rectangle("fill", rx1, ly, lw2, 1) end

  local ap = _PULSE
  if evil then
    Prims.evil_divider(tray_x + rn(6), ty + header_h, tray_w - rn(12), rn(1), _ACC, _GOLD, ga, ap, nil, true)
  elseif neuro then
    love.graphics.setColor(shr, shg, shb, (0.85 + 0.10 * ap) * ga)
    love.graphics.rectangle("fill", tray_x + rn(6), ty + header_h - 2, tray_w - rn(12), 2)
  else
    set_col(_ACC, (0.80 + 0.15 * ap) * ga)
    love.graphics.rectangle("fill", tray_x + rn(6), ty + header_h - 2, tray_w - rn(12), 2)
  end
  local mx2 = tray_x + math.floor(tray_w / 2)
  if evil then
    Prims.draw_dark_bow_mini(mx2, ty + header_h - 1, rn(1) * 1.1, _GOLD, (0.9 + 0.1 * ap) * ga, _GOLD, true, _ACC)
  elseif neuro then
    Prims.draw_bow_mini(mx2, ty + header_h - 1, rn(1) * 0.9, _ACC, 0.9 * ga, _GLOW)
  end

  local gy = ty + header_h
  local rows_top = math.max(y0, gy - slide)
  local inner_bottom = math.min(ty + body_h - slide - 1, ctx.sh)
  if inner_bottom > rows_top then
    love.graphics.setScissor(tray_x + 1, rows_top, tray_w - 2, inner_bottom - rows_top)

    local cell_w = tray_w - pad * 2
    local order = S.voucher_order
    local rotating = n > VIS
    local rfrac = 1
    if rotating and S.voucher_rot_slide_at > 0 then
      rfrac = Motion.anim01(now - S.voucher_rot_slide_at, ROT_SLIDE_D)
    end
    local base = rotating and (rfrac < 1 and S.voucher_rot_prev or S.voucher_rot_idx) or 1
    local count = shown
    local off = 0
    if rotating and rfrac < 1 then
      off = rfrac * row_h
      count = shown + 1
    end
    for j = 0, count - 1 do
      local idx = ((base - 1 + j) % n) + 1
      local rx = tray_x + pad
      local ry = gy + j * row_h - off
      if j > 0 then
        set_col(_FRD, 0.55 * ga)
        love.graphics.setLineWidth(1)
        love.graphics.line(tray_x + pad, ry, tray_x + tray_w - pad, ry)
      end
      draw_row(ctx, order[idx], rx, ry, cell_w, row_h, ga, now)
    end
  end

  love.graphics.setScissor(tray_x - rn(3), y0, tray_w + rn(8), clip_h)
  local pb_y = y0 + slide  -- already in translated coordinates, not screen space
  draw_connection(rn, tray_x + rn(26), ty, pb_y, ga, evil, neuro)
  draw_connection(rn, tray_x + tray_w - rn(26), ty, pb_y, ga, evil, neuro)

  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
  if prev_font then love.graphics.setFont(prev_font) end
end

return Vouchers
