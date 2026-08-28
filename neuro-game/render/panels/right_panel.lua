local H = require("render.hud_shared")
local RectMesh = require("render.rect_mesh")
local Prims, S, Motion, Utils = H.Prims, H.S, H.Motion, H.Utils
local round = Prims.round
local clamp = Prims.clamp
local quant_alpha = Prims.quant_alpha
local set_col, shadow_text = H.set_col, H.shadow_text
local push_clip, pop_clip = H.push_clip, H.pop_clip
local smoothstep01 = H.smoothstep01
local draw_card_mini, card_dimensions, rarity_color, joker_fx = H.draw_card_mini, H.card_dimensions, H.rarity_color, H.joker_fx
local card_display_name, card_description = H.card_display_name, H.card_description
local modifier_badges, layout_modifier_badges, draw_modifier_badges =
  H.modifier_badges, H.layout_modifier_badges, H.draw_modifier_badges
local badge_family_color = H.badge_family_color
local tracked_width, caps_label = H.tracked_width, H.caps_label
local buy_showcase_alpha = H.buy_showcase_alpha
local DESC_FADE_D, DESC_SHOW_D = H.DESC_FADE_D, H.DESC_SHOW_D
local carousel_clock, carousel_restart = H.carousel_clock, H.carousel_restart
local buy_flare01, buy_pop01 = H.buy_flare01, H.buy_pop01

local CY_JOKER = { slot = "desc_slot", epoch = "desc_epoch", cache = "desc_cache",
  cache_n = "desc_cache_n", ref = "desc_slot_ref" }
local CY_CONS = { slot = "cons_slot", epoch = "cons_epoch", cache = "cons_cache",
  cache_n = "cons_cache_n", ref = "cons_slot_ref" }

local PIN_MO = { pulse = 0.5 }
local function pin_mo(mo)
  PIN_MO.pulse = (mo and mo.pulse) or 0.5
  return PIN_MO
end

local BAND_G = {}
local HORN_BLACK = { 0.09, 0.07, 0.08 }
local CAROUSEL_WHITE = { 1, 1, 1 }
local FLASH_C = { 0, 0, 0 }
local GLITCH_R = { 0.95, 0.10, 0.16 }
local GLITCH_C = { 0.12, 0.80, 0.90 }
local PLAIN_WHITE = { 1, 1, 1 }

local _ctr_txt = {}
local function counter_text(i, n)
  local per = _ctr_txt[n]
  if not per then per = {}; _ctr_txt[n] = per end
  local t = per[i]
  if not t then t = tostring(i) .. "/" .. tostring(n); per[i] = t end
  return t
end

local CTR_W_MAX = 64
local _ctr_w, _ctr_w_font, _ctr_w_n = {}, nil, 0
local function counter_w(text, font)
  if font ~= _ctr_w_font then _ctr_w, _ctr_w_n, _ctr_w_font = {}, 0, font end
  local w = _ctr_w[text]
  if w then return w end
  w = font:getWidth(text)
  if _ctr_w_n >= CTR_W_MAX then _ctr_w, _ctr_w_n = {}, 0 end
  _ctr_w[text] = w
  _ctr_w_n = _ctr_w_n + 1
  return w
end

local function round_eval_flash(now)
  return S.ov.re_seen
    and math.max(0, 1 - (now - (S.ov.round_eval_at or now)) / 0.6) or 0
end

local function draw_rp_frame(ctx)
  local th, mo, me, da = H.bind(ctx)
  local pg, bg, ACC, GOLD, WHITE = th.pg, th.bg, th.ACC, th.GOLD, th.WHITE
  local now, pulse = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local rfont, boss, is_round_eval = th.rfont, th.boss, th.is_round_eval
  local sn = da.sn
  local rn, rp_sh, p_x, p_y, pw_total, total_h, title_h = me.rn, me.rp_sh, me.p_x, me.p_y, me.pw_total, me.total_h, me.title_h
  if is_round_eval then
    if not S.ov.re_seen then S.ov.re_seen = true; S.ov.round_eval_at = now end
  else
    S.ov.re_seen = false
  end
  local re01 = round_eval_flash(now)
  love.graphics.setFont(rfont)
  H.persona_frame(th, mo, p_x, p_y, pw_total, total_h, rn(1), { sh = rp_sh, rad = rn(9), title_h = title_h, quiet = true })
  if persona_neuro then
    Prims.valance(p_x, p_y + rn(1), pw_total, rn(1), ACC, pg, 0.9, true)
    for si = 1, 5 do
      local sxr = 0.5 + 0.5 * math.sin(si * 78.233)
      local syr = 0.5 + 0.5 * math.sin(si * 39.425 + 1.7)
      local tw2 = Prims.twinkle01(now, si)
      local sx3 = p_x + math.floor(pw_total * 0.52) + sxr * (pw_total * 0.34)
      local sy3 = p_y + rn(7) + syr * (title_h - rn(16))
      Prims.draw_sparkle(sx3, sy3, rn(2) + tw2 * rn(2), (si % 2 == 0) and pg or ACC, 0.55 * tw2)
    end
    Prims.petals(p_x + math.floor(pw_total * 0.52), p_y + rn(6),
      math.floor(pw_total * 0.34), title_h - rn(16), rn(1), now, 0.8, 4)
    local blind_sel = (sn == "BLIND_SELECT")
    local bob2 = math.sin(now * (blind_sel and 5.5 or 1.4)) * rn(1) * (blind_sel and 1.6 or 1)
    local bsc2 = 1
    local bs = S.buy_showcase
    if bs and bs.started then
      local bage = now - bs.started
      bsc2 = 1 + 0.08 * buy_pop01(now)
      if bage >= 0 and bage < 0.5 then
        local pk2 = math.sin(math.pi * (bage / 0.5))
        Prims.draw_sparkle(p_x + pw_total - rn(38), p_y + rn(10), rn(2) + pk2 * rn(3), pg, 0.8 * pk2)
      end
    end
    if blind_sel then
      set_col(ACC, 0.05 + 0.05 * pulse)
      love.graphics.rectangle("fill", p_x + rn(2), p_y + rn(1), pw_total - rn(4), title_h)
    end
    Prims.draw_bow(p_x + pw_total - rn(20), p_y + rn(5) + bob2, rn(2) * bsc2, ACC, 0.95, pg)
    if re01 > 0 then
      Prims.confetti_burst(p_x + pw_total - rn(20), p_y + rn(5), 1 - re01, rn(28), rn(2), 0.5, pg, ACC, re01)
    end
  end
  if persona_evil then
    local flare = buy_flare01(now)
    H.evil_frame(p_x, p_y, pw_total, total_h, rn(1), title_h, GOLD, pg, bg, pulse, now, 1, flare)
    local sig_pop = 1 + 0.20 * flare + (is_round_eval and 0.12 or 0)
    local sig_a = math.min(1, 0.9 + 0.10 * flare + (is_round_eval and 0.10 or 0))
    local bob = math.sin(now * 1.4) * rn(1)
    Prims.corner_brand(p_x + pw_total - rn(20), p_y + rn(5) + bob, rn(2) * sig_pop, ACC, WHITE, 0.95 * sig_a, false)
    if boss then
      set_col(ACC, 0.42 + 0.35 * pulse)
      love.graphics.rectangle("fill", p_x + rn(4), p_y, pw_total - rn(8), math.max(1, rn(1)))
    end
  end
end

local function draw_rp_header(ctx)
  local th, mo, me, da = H.bind(ctx)
  local pg, ACC, GOLD, WHITE = th.pg, th.ACC, th.GOLD, th.WHITE
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local persona_name, boss, is_round_eval = th.persona_name, th.boss, th.is_round_eval
  local rfont = th.rfont_display
  local rn, PAD_TOP, TRACK, TRACK_SM = me.rn, me.PAD_TOP, me.TRACK, me.TRACK_SM
  TRACK, TRACK_SM = rn(TRACK), rn(TRACK_SM)
  local p_x, p_y, p_pad_x, r_U, pw_total, title_h = me.p_x, me.p_y, me.p_pad_x, me.r_U, me.pw_total, me.title_h
  local r_text_h = me.rp_display_text_h
  local state_label, is_thinking, logo, logo_w, logo_h, logo_scale = da.state_label, da.is_thinking, da.logo, da.logo_w, da.logo_h, da.logo_scale
  local tx = p_x + p_pad_x
  local ty = p_y + rn(PAD_TOP)
  local sl_font = th.rfont_title
  local sl_text_h = me.rp_title_text_h
  local sl_y = ty + r_text_h + r_U
  love.graphics.setFont(rfont)
  if logo then
    local logo_y = ty + math.floor((r_text_h + r_U + sl_text_h - logo_h) / 2)
    love.graphics.setColor(1, 1, 1, 0.94 + 0.06 * pulse)
    love.graphics.draw(logo, tx, logo_y, 0, logo_scale, logo_scale)
    tx = tx + logo_w + r_U * 2
  end

  if persona_evil then
    local nw2 = tracked_width(persona_name, TRACK, rfont)
    love.graphics.setColor(0, 0, 0, 0.32)
    love.graphics.rectangle("fill", tx - rn(5), ty - rn(3), nw2 + rn(10), r_text_h + rn(6))
    local horn_scale = rn(5) * ((is_round_eval or boss) and 1.2 or 1)
    Prims.draw_horns(tx + math.floor(nw2 / 2), ty - rn(2), horn_scale, HORN_BLACK,
      0.92 + 0.08 * pulse + (is_round_eval and 0.08 or 0), ACC, true)
  elseif persona_neuro then
    local nw2 = tracked_width(persona_name, TRACK, rfont)
    set_col(ACC, 0.08)
    love.graphics.rectangle("fill", tx - rn(5), ty - rn(3), nw2 + rn(10), r_text_h + rn(6), rn(8), rn(8))
  end
  if persona_evil then
    local gwin = 4.3
    local gseg = math.floor(now / gwin)
    local gstart = 0.45 + 0.4 * (0.5 + 0.5 * math.sin(gseg * 12.9898))
    local gt = now / gwin - gseg
    if gt > gstart and gt < gstart + 0.05 then
      local jit = rn(2)
      caps_label(persona_name, tx - jit, ty, GLITCH_R, 0.55, TRACK, rfont, 0, nil, nil,
        S, "rp_glitch_r")
      caps_label(persona_name, tx + jit, ty - 1, GLITCH_C, 0.42, TRACK, rfont, 0, nil, nil,
        S, "rp_glitch_c")
    end
  end
  local name_end = caps_label(persona_name, tx, ty, WHITE, 0.97, TRACK, rfont, 0.30, rn(1),
    nil, S, "rp_persona_name")
  if persona_evil and name_end then
    local oy2 = ty + math.floor(r_text_h / 2)
    local cur_slot = (S.desc_slot or 0) * 131 + (S.cons_slot or 0)
    if S.ov.eye_slot ~= cur_slot then
      S.ov.eye_slot = cur_slot; S.ov.eye_at = now
      S.ov.eye_look_dir = (S.ov.eye_look_dir == 1) and -1 or 1
    end
    local look, hold = 0, false
    if boss then
      look = (math.sin(now * 4.2) > 0) and 1 or -1
    elseif is_round_eval then
      hold = true
    elseif S.ov.eye_at and (now - S.ov.eye_at) < 0.5 then
      look = S.ov.eye_look_dir or 1
    else
      local swin = 3.7
      local sseg = math.floor(now / swin)
      local sstart = 0.3 + 0.55 * (0.5 + 0.5 * math.sin(sseg * 45.113))
      local st = now / swin - sseg
      if st > sstart and st < sstart + 0.11 then
        look = (math.sin(sseg * 12.9898) > 0) and 1 or -1
      end
    end
    local eye_u = rn(1) * (boss and 1.3 or (is_round_eval and 1.15 or 1))
    local eye_a = 0.9 + (boss and 0.08 or 0) + (is_round_eval and 0.10 or 0)
    Prims.draw_evil_eye(name_end + rn(12), oy2, eye_u, ACC, eye_a, now, true, look, hold)
  elseif persona_neuro and name_end then
    love.graphics.setColor(shimr, shimg, shimb, 0.55)
    love.graphics.rectangle("fill", tx, ty + r_text_h + rn(1), name_end - tx, 1)
    local bob = math.sin(now * 1.4) * rn(1)
    local re01 = round_eval_flash(now)
    local beat = (now % 4.7) < 0.12   -- must match the evil-eye blink cadence (now%4.7<0.12) in hud/prims.lua
    Prims.draw_heart(name_end + rn(9), ty + math.floor(r_text_h / 2) + bob - math.floor(re01 * rn(3)),
      (beat or re01 > 0) and rn(4) or rn(3), pg, (beat or re01 > 0) and 1.0 or 0.85)
  end

  love.graphics.setFont(sl_font)
  if state_label ~= S.ov.sl_text then S.ov.sl_text = state_label; S.ov.sl_at = now end
  local sl_in = math.min(1, (now - (S.ov.sl_at or now)) / 0.20)
  sl_in = sl_in * sl_in * (3 - 2 * sl_in)
  if is_thinking then
    local breathe = Motion.pulse(now, 3.2)
    local lw = tracked_width(state_label, TRACK_SM, sl_font)
    local dot_x = tx + lw + r_U + rn(2)
    local dot_gap, dot_r = rn(6), rn(3) / 2
    caps_label(state_label, tx, sl_y, ACC, 0.82 + 0.12 * quant_alpha(breathe), TRACK_SM, sl_font, 0.32, rn(1),
      nil, S, "rp_state_label", sl_in)
    if persona_evil then
      local fsz = rn(3)
      for di = 0, 2 do
        local et = (now * 1.2 + di * 0.33) % 1
        local ey3 = round(sl_y + sl_text_h / 2 - rn(1) - et * rn(3))
        local fa = (1 - et) * (0.35 + 0.55 * Prims.candle01(now + di * 1.7))
        love.graphics.setColor(1, 0.62 - 0.35 * et, 0.16, fa * sl_in)
        love.graphics.rectangle("fill", round(dot_x + di * dot_gap - rn(1)), ey3, fsz, fsz)
      end
    else
      for di = 0, 2 do
        local db = Motion.pulse(now, 3.2, -di * 0.6)
        set_col(ACC, (0.30 + 0.60 * db) * sl_in)
        love.graphics.rectangle("fill", dot_x + di * dot_gap - dot_r, sl_y + sl_text_h / 2 - dot_r, dot_r * 2, dot_r * 2)
      end
    end
  else
    local rest = 0.34 + 0.14 * Motion.pulse(now, 0.6)
    local lw = tracked_width(state_label, TRACK_SM, sl_font)
    caps_label(state_label, tx, sl_y, PLAIN_WHITE, 1, TRACK_SM, sl_font, 0,
      nil, nil, S, "rp_state_label", rest * sl_in)
    set_col(th.DIM or {1, 1, 1}, 0.35 * sl_in)
    love.graphics.rectangle("fill", tx + lw + r_U + rn(2), sl_y + sl_text_h / 2 - rn(1), rn(3), rn(3))
  end
  love.graphics.setFont(rfont)

  local cy = p_y + title_h
  if persona_evil then
    Prims.evil_divider(p_x, cy, pw_total, rn(1), ACC, GOLD, 1, pulse, nil, true)
  elseif persona_neuro then
    local re01 = round_eval_flash(now)
    love.graphics.setColor(shimr, shimg, shimb, 0.85 + 0.10 * pulse + 0.5 * re01)
    love.graphics.rectangle("fill", p_x, cy - 2, pw_total, 2)
    local mx2 = p_x + math.floor(pw_total / 2)
    local bscale = 1 + 0.4 * re01
    local bs = S.buy_showcase
    if bs and bs.started then
      bscale = 1 + 0.10 * buy_pop01(now)
    end
    Prims.draw_bow_mini(mx2, cy - 1, rn(1) * 0.9 * bscale, ACC, 0.9, pg)
    Prims.draw_heart(p_x + rn(8), cy - 1, rn(3), pg, 0.55)
    Prims.draw_heart(p_x + pw_total - rn(8), cy - 1, rn(3), pg, 0.55)
  else
    set_col(ACC, 0.85 + 0.10 * pulse)
    love.graphics.rectangle("fill", p_x, cy - 2, pw_total, 2)
  end
end

local _carousel_P = {}
local function draw_desc_carousel(P)
  local r, rx, cy = P.r, P.rx, P.cy
  local now, cur_card_a, pulse = P.now, P.cur_card_a, P.pulse
  local rn, content_w, p_w, p_pad_x = P.rn, P.content_w, P.p_w, P.p_pad_x
  local rp_card_line_h, rp_small_line_h, rp_text_h, r_small_text_h = P.rp_card_line_h, P.rp_small_line_h, P.rp_text_h, P.r_small_text_h
  local rp_font, rfont_small = P.rp_font, P.rfont_small
  local persona_evil, persona_neuro = P.persona_evil, P.persona_neuro
  local pg, ACC, FR, FRD, GOLD = P.pg, P.ACC, P.FR, P.FRD, P.GOLD
  local SEL = P.SEL
  local shimr, shimg, shimb = P.shimr, P.shimg, P.shimb
  local trunc, wrapped_lines = P.trunc, P.wrapped_lines
  local draw_desc_lines = P.draw_desc_lines
  local theme = P.theme
  local jokers = r.cards
  local n = #jokers
  if n > 0 then
    local D_FADE = DESC_FADE_D
    local D_SHOW = DESC_SHOW_D

    local K = (r.which == "cons") and CY_CONS or CY_JOKER
    local cy_slot = S[K.slot]
    local cy_epoch = S[K.epoch]
    local cy_cache = S[K.cache]
    local cy_cache_n = S[K.cache_n]

    local cy_ref = S[K.ref]
    local pre_ref = jokers[cy_slot + 1]
    if cy_ref ~= nil and pre_ref ~= nil and pre_ref ~= cy_ref then carousel_restart(now) end

    local epoch, phase = carousel_clock(now)
    if cy_slot >= n then cy_slot = 0; cy_epoch = epoch end

    local fade_a, show_progress
    if n == 1 then
      cy_slot = 0
      cy_epoch = epoch
      fade_a = cur_card_a
      show_progress = 1.0
    else
      if not cy_epoch then
        cy_epoch = epoch
      elseif epoch ~= cy_epoch then
        cy_slot = (cy_slot + 1) % n
        cy_epoch = epoch
      end
      if phase < D_FADE then
        fade_a = Motion.anim01(phase, D_FADE)
        show_progress = 0.0
      elseif phase < D_FADE + D_SHOW then
        fade_a = 1.0
        show_progress = (phase - D_FADE) / D_SHOW
      else
        local t = phase - D_FADE - D_SHOW
        fade_a = 1.0 - Motion.anim01(t, D_FADE)
        show_progress = 1.0
      end
      fade_a = fade_a * cur_card_a
    end

    if cy_cache_n ~= n then cy_cache = {}; cy_cache_n = n end
    local cur_jc = jokers[cy_slot + 1]
    local cached = cy_cache[cy_slot]
    if cur_jc then
      local sf2 = rfont_small
      local wrap_w = content_w - rn(36)
      local badges = modifier_badges(cur_jc)
      local badges_v = badges._v
      local rc2 = rarity_color(cur_jc)
      if not rc2 or type(rc2) ~= "table" then rc2 = CAROUSEL_WHITE end
      local r1, r2, r3 = rc2[1], rc2[2], rc2[3]
      local placeholder_revision = Utils.placeholder_revision(cur_jc)
      local ui_text_revision = Utils.ui_text_revision(cur_jc)
      -- Scaling jokers mutate `extra` in place, so a table-typed `extra` can't be fingerprinted by
      -- reference: re-run joker_fx() for it, but gate the rebuild below on the returned string.
      local ab = cur_jc.ability or {}
      local fx_extra = ab.extra
      local fx_extra_is_table = type(fx_extra) == "table"
      local fx_inputs_stale = not cached or cached.jc ~= cur_jc
        or cached.fx_xm ~= ab.x_mult or cached.fx_hm ~= ab.h_mult or cached.fx_hc ~= ab.h_chips
        or cached.fx_tm ~= ab.t_mult or cached.fx_tc ~= ab.t_chips
        or (not fx_extra_is_table and cached.fx_extra ~= fx_extra)
      local fx
      if fx_inputs_stale or fx_extra_is_table then
        fx = joker_fx(cur_jc) or ""
      else
        fx = cached.fx
      end
      local fx_stale = not cached or fx ~= cached.fx
      local changed = not cached or cached.jc ~= cur_jc
        or cached.wrap_w ~= wrap_w or cached.font ~= sf2 or cached.badges_v ~= badges_v
        or cached.r1 ~= r1 or cached.r2 ~= r2 or cached.r3 ~= r3
        or cached.placeholder_revision ~= placeholder_revision
        or cached.ui_text_revision ~= ui_text_revision
        or fx_stale
      if changed then
        local desc = card_description(cur_jc) or ""
        if desc == "" and cur_jc.config and cur_jc.config.center then
          local ok, d = pcall(Utils.safe_description, cur_jc.config.center.loc_txt, cur_jc)
          if ok and type(d) == "string" then desc = d end
        end
        local show = desc ~= "" and desc or fx
        local dname = card_display_name(cur_jc) or "Unknown"
        local lns = show ~= "" and wrapped_lines(show, wrap_w, sf2) or {}
        cached = {
          name = dname, show = show, fx = fx, badges = badges, badges_v = badges_v, lines = lns,
          rc = rc2, r1 = r1, r2 = r2, r3 = r3, jc = cur_jc, wrap_w = wrap_w, font = sf2,
          placeholder_revision = Utils.placeholder_revision(cur_jc),
          ui_text_revision = Utils.ui_text_revision(cur_jc),
          fx_xm = ab.x_mult, fx_hm = ab.h_mult, fx_hc = ab.h_chips, fx_tm = ab.t_mult, fx_tc = ab.t_chips,
          fx_extra = fx_extra,
        }
        cy_cache[cy_slot] = cached
      end
    else
      cached = nil
      cy_cache[cy_slot] = nil
    end
    S[K.slot], S[K.epoch], S[K.cache], S[K.cache_n] = cy_slot, cy_epoch, cy_cache, cy_cache_n
    S[K.ref] = jokers[cy_slot + 1]

    local jc = cached and cached.jc
    if jc then
      local rc = cached.rc
      local jname = cached.name
      local lns   = cached.lines
      local sf = rfont_small

      set_col(SEL, 0.80)
      love.graphics.rectangle("fill", rx + 3, cy, p_w - 6, rp_card_line_h + rp_small_line_h * 3 + 4)

      local sprite_h = rp_card_line_h - 4
      local sprite_x = rx + p_pad_x
      local est_w, est_h = card_dimensions(jc, sprite_h)
      local sprite_y = cy + math.floor((rp_card_line_h - est_h) / 2)
      love.graphics.setColor(0, 0, 0, 0.55 * fade_a)
      love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, est_w + 2, est_h + 2)
      set_col(rc, 0.60 * fade_a)
      love.graphics.setLineWidth(rn(1))
      love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, est_h + 2)
      if persona_evil then
        set_col(GOLD, 0.30 * fade_a)
        love.graphics.rectangle("line", sprite_x - 2, sprite_y - 2, est_w + 4, est_h + 4)
      elseif persona_neuro then
        love.graphics.setColor(shimr, shimg, shimb, 0.40 * fade_a)
        love.graphics.rectangle("line", sprite_x - 2, sprite_y - 2, est_w + 4, est_h + 4, rn(2), rn(2))
      end
      local mini_w  = draw_card_mini(jc, sprite_x, sprite_y, sprite_h, fade_a)
      local text_off = math.max(est_w, mini_w > 0 and mini_w or 0) + rn(7)
      local name_w = content_w - text_off - rn(28)
      local badge_w = math.max(1, name_w)
      local stack_h = rp_small_line_h * 3
      if not cached.badge_layout or cached.badge_width ~= badge_w
        or cached.badge_line_h ~= rp_small_line_h then
        local lay = layout_modifier_badges(cached.badges, sf, badge_w, rn(1), 1)
        if lay.tier == 1 and lay.rows > 0 then
          local two = layout_modifier_badges(cached.badges, sf, badge_w, rn(1), 2)
          if two.tier > lay.tier and (stack_h - two.height) >= rp_small_line_h then lay = two end
        end
        cached.badge_layout = lay
        cached.badge_width = badge_w
        cached.badge_line_h = rp_small_line_h
      end
      local badge_layout = cached.badge_layout

      local name_txt = trunc(jname, name_w, rp_font)
      local name_x = rx + p_pad_x + text_off
      local name_y = cy + (rp_card_line_h - rp_text_h) / 2
      shadow_text(name_txt, name_x, name_y, rc, 0.97 * fade_a, 0.30 * fade_a, rn(1))

      love.graphics.setFont(rfont_small)
      local slot_txt = counter_text(cy_slot + 1, n)
      local stw = counter_w(slot_txt, sf)
      shadow_text(slot_txt, rx + p_w - p_pad_x - stw, cy + (rp_card_line_h - r_small_text_h) / 2, ACC, 0.78 + 0.10 * quant_alpha(pulse), 0.30, rn(1))

      local strip_h = badge_layout.height
      local desc_lines = (#lns > 0)
        and math.min(#lns, math.max(0, math.floor((stack_h - strip_h) / rp_small_line_h)))
        or 0
      local desc_y = cy + rp_card_line_h
      if strip_h > 0 then
        local lead = rn(2)
        local slack = math.max(0, stack_h - strip_h - desc_lines * rp_small_line_h)
        local lead_top = math.min(lead, math.ceil(slack / 2))
        local lead_bot = math.min(lead, slack - lead_top)
        draw_modifier_badges(badge_layout, rx + p_pad_x + text_off, desc_y + lead_top,
          fade_a, theme, pin_mo(P))
        desc_y = desc_y + lead_top + strip_h + lead_bot
      end
      if desc_lines > 0 then
        draw_desc_lines(lns, desc_lines, rx + p_pad_x + text_off, desc_y, rp_small_line_h, fade_a, sf)
      end
      love.graphics.setFont(rp_font)

      if n > 1 then
        local bar_y = cy + rp_card_line_h + rp_small_line_h * 3 + 2
        local bar_x = rx + p_pad_x
        local bar_h = rn(3)
        local b1 = rn(1)
        set_col(FRD, 0.90)
        love.graphics.rectangle("fill", bar_x + b1, bar_y + b1, content_w - b1 * 2, bar_h)
        set_col(FR, 0.90)
        love.graphics.setLineWidth(rn(1))
        love.graphics.rectangle("line", bar_x + 0.5, bar_y + 0.5, content_w - 1, bar_h + b1)
        local prog_w = math.max(1, (content_w - b1 * 2) * show_progress)
        if persona_neuro then
          Prims.tag_string(bar_x + b1, bar_y + b1, prog_w, 1, shimr, shimg, shimb, 1)
          Prims.draw_heart(bar_x + b1 + prog_w, bar_y + b1 + math.floor(bar_h / 2), rn(3), pg, 0.9)
        elseif persona_evil then
          set_col(ACC, 0.85)
          love.graphics.rectangle("fill", bar_x + b1, bar_y + b1, prog_w, bar_h)
          local hy = bar_y + b1 + bar_h / 2
          local hx = bar_x + b1 + prog_w
          Prims.draw_evil_heart(hx, hy, rn(3), ACC, 0.9, GOLD, true)
        else
          set_col(ACC, 0.85)
          love.graphics.rectangle("fill", bar_x + b1, bar_y + b1, prog_w, bar_h)
        end

        local mk_pop = (n > 1 and phase < 0.15) and 1.3 or 1
        local dot_y  = bar_y + rn(10)
        local dot_sp = clamp(math.floor((content_w - 4) / math.max(1, n)), 2, 10)
        local total_dots_w = (n - 1) * dot_sp
        local dot_x0 = rx + p_w / 2 - total_dots_w / 2
        for di = 0, n - 1 do
          local dx = dot_x0 + di * dot_sp
          if di == cy_slot then
            if persona_neuro then
              Prims.draw_heart(dx, dot_y, rn(3) * mk_pop, pg, 0.95)
            elseif persona_evil then
              Prims.draw_evil_heart(dx, dot_y, rn(3) * mk_pop, ACC, 0.95, GOLD, true)
            else
              local ds2 = round(rn(2) * mk_pop)
              set_col(ACC, 0.90)
              love.graphics.rectangle("fill", dx - ds2, dot_y - ds2, ds2 * 2, ds2 * 2)
            end
          else
            local d1 = rn(1)
            set_col(FR, 0.60)
            love.graphics.rectangle("fill", dx - d1, dot_y - d1, d1 * 2, d1 * 2)
          end
        end
      end
    end
  end
  cy = cy + rp_card_line_h + rp_small_line_h * 3 + rn(18)
  return cy
end

local function draw_rp_rows(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local pg, ACC, FR, FRD, GOLD = th.pg, th.ACC, th.FR, th.FRD, th.GOLD
  local ROW, SEL = th.ROW, th.SEL
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font, rfont_small, rp_font = th.font, th.rfont_small, th.rp_font
  local rn, sh, p_x, p_y, p_w, p_pad_x = me.rn, me.sh, me.p_x, me.p_y, me.p_w, me.p_pad_x
  local r_U, r_accw, pw_total, total_h, content_w, n_cols = me.r_U, me.r_accw, me.pw_total, me.total_h, me.content_w, me.n_cols
  local title_h, footer_h = me.title_h, me.footer_h
  local rp_text_h, rp_line_h, rp_small_line_h, rp_card_line_h, rp_sep_h = me.rp_text_h, me.rp_line_h, me.rp_small_line_h, me.rp_card_line_h, me.rp_sep_h
  local rfont_title, rp_hdr_line_h = th.rfont_title, me.rp_hdr_line_h
  local r_small_text_h = me.r_small_text_h
  local panel_rows, showcase_alpha = da.panel_rows, da.showcase_alpha
  local trunc, wrapped_lines, row_h = dr.trunc, dr.wrapped_lines, dr.row_h
  local draw_desc_lines = dr.draw_desc_lines
  local cy = p_y + title_h + r_U

  if #panel_rows > 0 then
    cy = cy + r_U
    local clip_y = p_y + total_h - footer_h
    local wrap_y = p_y + (me.panel_h_target or total_h) - footer_h
    local rp_col = 1
    local rx = p_x
    local rows_y0 = cy
    local row_sdx = S.right_panel_slide_frac > 0
      and round((me.main_slide_dir or 1) * (pw_total + 20) * S.right_panel_slide_frac) or 0
    local rows_clip = push_clip(p_x + row_sdx - 2, p_y,
      pw_total + 4, math.max(0, math.min(clip_y, sh) - p_y))
    for c = 2, (me.n_cols_used or n_cols) do
      set_col(FRD, 0.90)
      love.graphics.rectangle("fill", p_x + (c - 1) * p_w, cy - r_U, 1, clip_y - cy + r_U)
    end
    love.graphics.setFont(rp_font)
    local buy_prominence = 0
    if S.buy_showcase then
      buy_prominence = buy_showcase_alpha(S.buy_showcase, now)
    end
    local spotlight = math.max(showcase_alpha or 0, buy_prominence)
    local spotlight_dim = 1 - 0.35 * spotlight
    local transition_recency = 1 - smoothstep01((now - S.state_changed_at) / 0.18)
    local transition_dip = 1 - 0.55 * transition_recency
    local row_dim = spotlight_dim * transition_dip
    local cur_card_a = row_dim
    local row_hs = me.row_hs
    for ri, r in ipairs(panel_rows) do
      local cur_h = row_hs and row_hs[ri] or row_h(r)
      if cy + cur_h > wrap_y and rp_col < n_cols then
        rp_col = rp_col + 1
        rx = rx + p_w
        cy = rows_y0
      end

      local kind = r.kind
      if kind == "sep" or kind == "header" then
        cur_card_a = row_dim
      end

      if kind == "sep" then
        cy = cy + r_U
        set_col(FRD, 0.90)
        love.graphics.setLineWidth(rn(1))
        love.graphics.line(rx + p_pad_x, cy, rx + p_w - p_pad_x, cy)
        cy = cy + rp_sep_h - r_U

      elseif kind == "carousel" then
        local P = _carousel_P
        P.r, P.rx, P.cy, P.now, P.cur_card_a, P.pulse = r, rx, cy, now, cur_card_a, pulse
        P.rn, P.content_w, P.p_w, P.p_pad_x = rn, content_w, p_w, p_pad_x
        P.rp_card_line_h, P.rp_small_line_h = rp_card_line_h, rp_small_line_h
        P.rp_text_h, P.r_small_text_h = rp_text_h, r_small_text_h
        P.rp_font, P.rfont_small = rp_font, rfont_small
        P.theme = th
        P.persona_evil, P.persona_neuro = persona_evil, persona_neuro
        P.pg, P.ACC, P.FR, P.FRD, P.GOLD = pg, ACC, FR, FRD, GOLD
        P.SEL = SEL
        P.shimr, P.shimg, P.shimb = shimr, shimg, shimb
        P.trunc, P.wrapped_lines, P.draw_desc_lines = trunc, wrapped_lines, draw_desc_lines
        cy = draw_desc_carousel(P)

      elseif kind == "header" then
        local col = r.color
        local txt = r.text or ""
        love.graphics.setFont(rfont_title)
        set_col(ROW, 0.90)
        love.graphics.rectangle("fill", rx + 2, cy - 1, p_w - 4, rp_hdr_line_h + 2)
        if r.flash then
          set_col(ACC, 0.18 * r.flash)
          love.graphics.rectangle("fill", rx + 2, cy - 1, p_w - 4, rp_hdr_line_h + 2)
        end
        set_col(col, 0.90)
        love.graphics.rectangle("fill", rx + r_U, cy + 2, r_accw, rp_hdr_line_h - 4)
        if persona_evil then
          set_col(GOLD, 0.16)
          love.graphics.rectangle("fill", rx + 2, cy + rp_hdr_line_h, p_w - 4, 1)
          local hd_cy = cy + math.floor(rp_hdr_line_h / 2)
          local hd_x = rx + p_w - p_pad_x
          Prims.draw_diamond(hd_x - rn(3), hd_cy, rn(1), GOLD, 0.40 + 0.20 * pulse)
        end
        local hdr_txt = trunc(txt, content_w - 10, rfont_title)
        local hdr_col = col
        if r.flash then
          local f = r.flash
          FLASH_C[1] = col[1] + (1 - col[1]) * f
          FLASH_C[2] = col[2] + (1 - col[2]) * f
          FLASH_C[3] = col[3] + (1 - col[3]) * f
          hdr_col = FLASH_C
        end
        shadow_text(hdr_txt, rx + p_pad_x, cy + 1, hdr_col, 1.0, 0.30, rn(1))
        love.graphics.setFont(rp_font)
        cy = cy + rp_hdr_line_h

      elseif kind == "sub" then
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        local sub_lines = wrapped_lines(txt, content_w - indent, rp_font)
        local n_sub = #sub_lines > 0 and #sub_lines or 1
        local block_w = math.max(28, content_w - indent + 4)
        local block_h = rp_line_h * n_sub - 2
        set_col(ROW, 0.55)
        love.graphics.rectangle("fill", rx + p_pad_x + indent - 3, cy, block_w, block_h)
        set_col(col, 0.18)
        love.graphics.rectangle("fill", rx + p_pad_x + indent - 4, cy, r_accw, block_h)
        for li = 1, n_sub do
          local lyc = cy + (li - 1) * rp_line_h
          love.graphics.setColor(0, 0, 0, 0.25)
          love.graphics.print(sub_lines[li], rx + p_pad_x + indent + rn(1), lyc + rn(1))
          set_col(col, 0.97)
          love.graphics.print(sub_lines[li], rx + p_pad_x + indent, lyc)
        end
        cy = cy + rp_line_h * n_sub

      elseif kind == "emptyslots" then
        local nslot = math.min(r.limit or 5, 6)
        local gap = rn(4)
        local sw2 = (content_w - gap * (nslot - 1)) / nslot
        local sh2 = rp_card_line_h - rn(6)
        local sy2 = cy + rn(2)
        local dash = rn(3)
        set_col(FRD, 0.40)
        local slots = RectMesh.get("rp_emptyslots", nslot, sw2, sh2, dash, gap)
        if not slots and RectMesh.available() then
          local v, i = {}, {}
          for si = 1, nslot do
            local ox = (si - 1) * (sw2 + gap)
            local dx = ox
            while dx < ox + sw2 do
              local seg = math.min(dash, ox + sw2 - dx)
              RectMesh.add(v, i, dx, 0, seg, 1, 1, 1, 1, 1)
              RectMesh.add(v, i, dx, sh2, seg, 1, 1, 1, 1, 1)
              dx = dx + dash * 2
            end
            local dy = 0
            while dy < sh2 do
              local seg = math.min(dash, sh2 - dy)
              RectMesh.add(v, i, ox, dy, 1, seg, 1, 1, 1, 1)
              RectMesh.add(v, i, ox + sw2, dy, 1, seg, 1, 1, 1, 1)
              dy = dy + dash * 2
            end
          end
          slots = RectMesh.build(v, i)
          if slots then RectMesh.put("rp_emptyslots", nslot, sw2, sh2, dash, gap, nil, slots) end
        end
        if slots then
          love.graphics.draw(slots, rx + p_pad_x, sy2)
        else
          for si = 1, nslot do
            local sx2 = rx + p_pad_x + (si - 1) * (sw2 + gap)
            local dx = sx2
            while dx < sx2 + sw2 do
              local seg = math.min(dash, sx2 + sw2 - dx)
              love.graphics.rectangle("fill", dx, sy2, seg, 1)
              love.graphics.rectangle("fill", dx, sy2 + sh2, seg, 1)
              dx = dx + dash * 2
            end
            local dy = sy2
            while dy < sy2 + sh2 do
              local seg = math.min(dash, sy2 + sh2 - dy)
              love.graphics.rectangle("fill", sx2, dy, 1, seg)
              love.graphics.rectangle("fill", sx2 + sw2, dy, 1, seg)
              dy = dy + dash * 2
            end
          end
        end
        cy = cy + rp_card_line_h

      elseif kind == "deckback" then
        local col = r.color or th.GOLD
        local sprite_h = rp_card_line_h - rn(6)
        set_col(ROW, 0.90)
        love.graphics.rectangle("fill", rx + 2, cy - 1, p_w - 4, rp_card_line_h + 2)
        set_col(col, 0.90)
        love.graphics.rectangle("fill", rx + r_U, cy + 2, r_accw, rp_card_line_h - 4)

        local sx = rx + p_pad_x
        local sy = cy + rn(2)
        local mini_w = 0
        if r.center then
          local wcard = { config = { center = r.center } }
          love.graphics.setColor(0, 0, 0, 0.45)
          love.graphics.rectangle("fill", sx - 1, sy - 1, sprite_h * 0.72 + 2, sprite_h + 2)
          mini_w = draw_card_mini(wcard, sx, sy, sprite_h) or 0
        end
        local text_off = mini_w > 0 and (mini_w + rn(8)) or 0
        local tx2 = rx + p_pad_x + text_off
        local name_y = cy + math.floor((rp_card_line_h - rp_text_h) / 2)
        shadow_text(trunc(r.text or "", content_w - text_off, rp_font), tx2, name_y,
          col, 0.98, 0.50, rn(1))
        if persona_evil then
          set_col(GOLD, 0.16)
          love.graphics.rectangle("fill", rx + 2, cy + rp_card_line_h, p_w - 4, 1)
        end
        cy = cy + rp_card_line_h
        if r.desc and r.desc ~= "" then
          love.graphics.setFont(rfont_small)
          local dlines = wrapped_lines(r.desc, content_w, rfont_small)
          local n_d = #dlines > 0 and #dlines or 1
          local block_h = rp_small_line_h * n_d + rn(4)
          local bx, bw = rx + p_pad_x - 3, math.max(28, content_w + 4)
          set_col(ROW, 0.55)
          love.graphics.rectangle("fill", bx, cy, bw, block_h)
          set_col(col, 0.18)
          love.graphics.rectangle("fill", rx + p_pad_x - 4, cy, r_accw, block_h)
          for li = 1, n_d do
            local lyc = cy + rn(2) + (li - 1) * rp_small_line_h
            love.graphics.setColor(0, 0, 0, 0.50)
            love.graphics.print(dlines[li], rx + p_pad_x + rn(1), lyc + rn(1))
            set_col(th.WHITE, 0.98)
            love.graphics.print(dlines[li], rx + p_pad_x, lyc)
          end
          cy = cy + block_h
          love.graphics.setFont(rp_font)
        end

      else
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        local draw_txt = trunc(txt, content_w - indent, rp_font)
        if r.flash then
          set_col(ACC, 0.14 * r.flash)
          love.graphics.rectangle("fill", rx + 2, cy - 1, p_w - 4, rp_line_h)
        end
        shadow_text(draw_txt, rx + p_pad_x + indent, cy, col, 0.90 + 0.08 * (r.flash or 0), 0.30, rn(1))
        cy = cy + rp_line_h
      end
    end
    love.graphics.setFont(font)
    pop_clip(rows_clip)
  end
end

local function draw_footer_emote(em, p_x, pw_total, fy, footer_h, rn, now, a)
  local efw, efh = em.fw, em.fh
  if not (efw and efh) or efw <= 0 or efh <= 0 then return end
  local emote_area_h = footer_h - rn(6)
  local scale = math.min((pw_total - rn(20)) / efw, emote_area_h / efh)
  local dw, dh = efw * scale, efh * scale
  local ix = p_x + (pw_total - dw) / 2
  local iy = fy + (emote_area_h - dh) / 2 + 3
  love.graphics.setColor(1, 1, 1, a)
  if em.quads and em.n_frames > 1 then
    love.graphics.draw(em.img, em.quads[math.floor(now * em.fps) % em.n_frames + 1], ix, iy, 0, scale, scale)
  else
    love.graphics.draw(em.img, ix, iy, 0, scale, scale)
  end
end

local function draw_band_flanks(g, th, mid_y, in_l, in_r, a, col_r, col_g, col_b, alt)
  local rn = g.rn
  local out_l = g.p_x + g.p_pad_x + rn(6)
  local out_r = g.p_x + g.pw_total - g.p_pad_x - rn(6)
  if in_l - out_l <= rn(12) then return end
  local seg = (in_l - out_l) / 3
  local base, step = (g.evil and 0.24 or 0.22), (g.evil and 0.07 or 0.06)
  local flank = RectMesh.get("rp_flank", base, step)
  if not flank and RectMesh.available() then
    local v, i = {}, {}
    for k = 0, 2 do RectMesh.add(v, i, -(k + 1), 0, 1, 1, 1, 1, 1, base - k * step) end
    flank = RectMesh.build(v, i)
    if flank then RectMesh.put("rp_flank", base, step, nil, nil, nil, nil, flank) end
  end
  local flank_r = flank and RectMesh.get("rp_flank_r", base, step)
  if flank and not flank_r then
    local v, i = {}, {}
    for k = 0, 2 do RectMesh.add(v, i, k, 0, 1, 1, 1, 1, 1, base - k * step) end
    flank_r = RectMesh.build(v, i)
    if flank_r then RectMesh.put("rp_flank_r", base, step, nil, nil, nil, nil, flank_r) end
  end
  if flank and flank_r then
    love.graphics.setColor(col_r, col_g, col_b, a)
    love.graphics.draw(flank, in_l, mid_y, 0, seg, 1)
    love.graphics.draw(flank_r, in_r, mid_y, 0, seg, 1)
  else
    for i = 0, 2 do
      love.graphics.setColor(col_r, col_g, col_b, (base - i * step) * a)
      love.graphics.rectangle("fill", in_l - (i + 1) * seg, mid_y, seg, 1)
      love.graphics.rectangle("fill", in_r + i * seg, mid_y, seg, 1)
    end
  end
  if g.evil then
    Prims.draw_glint(out_l, mid_y, rn(2), th.ACC, 0.90 * a, th.GOLD, true)
    if alt then Prims.wax_seal(out_r, mid_y, rn(2), rn(1), th.GOLD, 0.90 * a, g.pulse)
    else Prims.draw_glint(out_r, mid_y, rn(2), th.ACC, 0.90 * a, th.GOLD, true) end
  else
    Prims.draw_sparkle(out_l, mid_y, rn(2), th.pg, 0.85 * a)
    if alt then Prims.heart_seal(out_r, mid_y, rn(2), th.pg, th.ACC, 0.90 * a)
    else Prims.draw_bow_mini(out_r, mid_y, rn(1), th.ACC, 0.90 * a, th.pg) end
  end
end

local LEGEND_MO = { pulse = 0.5 }

local _lay_memo = setmetatable({}, { __mode = "k" })

local function has_room(g, out_l, w)
  local rn = g.rn
  return (g.p_x + math.floor((g.pw_total - w) / 2) - rn(8)) - out_l > rn(12)
end

local function draw_footer_legend(list, meta, g, th, a)
  if a <= 0.01 then return end
  local rn, font = g.rn, g.font
  local u = rn(1)
  local fh = font:getHeight()
  local entry = meta and meta.entry
  local inner = (g.pw_total - 2 * g.p_pad_x) - 2 * rn(6)
  local budget = math.max(1, inner - 2 * rn(20))

  local n = meta and meta.n or 0
  local ct = n > 1 and counter_text(meta.i or 1, n) or nil
  local ct_w = ct and counter_w(ct, font) or 0
  local gap = ct and rn(6) or 0

  local lay_w = math.max(1, budget - ct_w - gap)
  local memo = _lay_memo[list]
  if not memo or memo.w ~= lay_w or memo.font ~= font then
    memo = { w = lay_w, font = font,
      lay = layout_modifier_badges(list, font, lay_w, u, 1) }
    _lay_memo[list] = memo
  end
  local lay = memo.lay
  local pin_w = (lay.row_widths and lay.row_widths[1]) or 0

  local gloss = entry and (entry.tip or entry.fx)
  if gloss and font:getWidth(gloss) > budget then gloss = entry and entry.fx or nil end
  if gloss and font:getWidth(gloss) > budget then gloss = nil end
  if gloss == "" then gloss = nil end
  local gloss_w = gloss and font:getWidth(gloss) or 0

  local drop = gloss and (math.floor(fh * 0.5) + u) or 0

  local out_l = g.p_x + g.p_pad_x + rn(6)
  if ct and not has_room(g, out_l, math.max(ct_w + gap + pin_w, gloss_w))
    and has_room(g, out_l, pin_w) then
    ct, ct_w, gap = nil, 0, 0
  end

  local run_w = ct_w + gap + pin_w
  local run_x = g.p_x + math.floor((g.pw_total - run_w) / 2)
  local blk = math.max(run_w, gloss_w)

  local ta = a * a
  local old_font = love.graphics.getFont()
  love.graphics.setFont(font)

  local fam = (entry and badge_family_color(entry, th)) or th.DIM
  draw_band_flanks(g, th, g.mid,
    g.p_x + math.floor((g.pw_total - blk) / 2) - rn(8),
    g.p_x + math.floor((g.pw_total - blk) / 2) + blk + rn(8),
    a, fam[1], fam[2], fam[3], ((meta and meta.i or 1) % 2) == 0)

  if ct then
    shadow_text(ct, run_x, g.mid - drop - math.floor(fh / 2),
      th.DIM, 0.72 * ta, 0.50 * ta, u)
  end
  draw_modifier_badges(lay, run_x + ct_w + gap,
    g.mid - drop - math.floor(lay.height / 2), a, th, LEGEND_MO)

  if gloss then
    local gloss_x, gloss_y = g.p_x + math.floor((g.pw_total - gloss_w) / 2), g.mid + drop - math.floor(fh / 2)
    shadow_text(gloss, gloss_x, gloss_y, th.DIM, 0, 0.50, u, nil, ta, "sh")
    shadow_text(gloss, gloss_x, gloss_y, th.DIM, 1, 0, u, nil, (0.90 + 0.06 * g.pulse) * ta, "mn")
  end
  love.graphics.setFont(old_font)
end

local function draw_rp_footer(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local FRD, DIM, GOLD = th.FRD, th.DIM, th.GOLD
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font, rfont_small = th.font, th.rfont_small
  local rn, p_x, p_y, p_pad_x, pw_total, total_h, footer_h = me.rn, me.p_x, me.p_y, me.p_pad_x, me.pw_total, me.total_h, me.footer_h
  local r_small_text_h = me.r_small_text_h
  local quip_display, footer_emote, footer_is_emote = da.quip_display, da.footer_emote, da.footer_is_emote
  local ffade = da.footer_fade or 1
  local trunc = dr.trunc
  if footer_h > 0 then
    local fy = p_y + total_h - footer_h
    local bandg = BAND_G
    bandg.rn, bandg.font = rn, rfont_small
    bandg.p_x, bandg.p_pad_x, bandg.pw_total = p_x, p_pad_x, pw_total
    bandg.fy, bandg.footer_h = fy, footer_h
    bandg.mid = fy + math.floor(footer_h / 2)
    bandg.evil, bandg.pulse = persona_evil, pulse
    local lg = (da.footer_legend or da.footer_prev_legend) and bandg or nil
    set_col(FRD, 0.90)
    love.graphics.setLineWidth(rn(1))
    love.graphics.line(p_x + p_pad_x, fy, p_x + pw_total - p_pad_x, fy)

    local prev_emote, prev_quip = da.footer_prev_emote, da.footer_prev_quip
    local now_emote = footer_is_emote and true or false

    local had_prev_footer = prev_emote ~= nil or da.footer_prev_legend ~= nil
      or (prev_quip and prev_quip ~= "")
    local fading = ffade < 1 and had_prev_footer

    if fading then
      local oa = 1 - ffade
      if prev_emote and prev_emote.img then
        if not now_emote then
          draw_footer_emote(prev_emote, p_x, pw_total, fy, footer_h, rn, now, 0.97 * oa)
        end
      elseif (not prev_emote) and da.footer_prev_legend and lg then
        draw_footer_legend(da.footer_prev_legend, da.footer_prev_legend_meta, lg, th, oa)
      elseif (not prev_emote) and prev_quip and prev_quip ~= "" then
        love.graphics.setFont(rfont_small)
        local ot = trunc(prev_quip, pw_total - rn(24), rfont_small)
        local ox = p_x + (pw_total - rfont_small:getWidth(ot)) / 2
        local oy = fy + (footer_h - r_small_text_h) / 2
        shadow_text(ot, ox, oy, DIM, 0, 0.50, rn(1), nil, oa, "sh")
        shadow_text(ot, ox, oy, DIM, 1, 0, rn(1), nil, (0.90 + 0.06 * pulse) * oa, "mn")
      end
    end

    if footer_is_emote and footer_emote and footer_emote.img then
      local efw, efh = footer_emote.fw, footer_emote.fh
      if efw > 0 and efh > 0 then
        local emote_area_h = footer_h - rn(6)
        local max_w = pw_total - rn(20)
        local scale = math.min(max_w / efw, emote_area_h / efh)
        local dw, dh = efw * scale, efh * scale
        local ix = p_x + (pw_total - dw) / 2
        local iy = fy + (emote_area_h - dh) / 2 + 3
        love.graphics.setColor(1, 1, 1, 0.97 * ffade)
        if footer_emote.quads and footer_emote.n_frames > 1 then
          local frame_idx = math.floor(now * footer_emote.fps) % footer_emote.n_frames + 1
          love.graphics.draw(footer_emote.img, footer_emote.quads[frame_idx], ix, iy, 0, scale, scale)
        else
          love.graphics.draw(footer_emote.img, ix, iy, 0, scale, scale)
        end
      end
    elseif da.footer_legend and lg then
      draw_footer_legend(da.footer_legend, da.footer_legend_meta, lg, th, ffade)
    elseif quip_display and quip_display ~= "" then
      love.graphics.setFont(rfont_small)
      local qf = rfont_small
      local qt = trunc(quip_display, pw_total - rn(24), qf)
      local qw = qf:getWidth(qt)
      local qx = p_x + (pw_total - qw) / 2
      local qy = fy + (footer_h - r_small_text_h) / 2
      shadow_text(qt, qx, qy, DIM, 0, 0.50, rn(1), nil, ffade, "sh")
      shadow_text(qt, qx, qy, DIM, 1, 0, rn(1), nil, (0.90 + 0.06 * pulse) * ffade, "mn")
      if persona_evil then
        draw_band_flanks(bandg, th, bandg.mid, qx - rn(8), qx + qw + rn(8), ffade,
          GOLD[1], GOLD[2], GOLD[3], #qt % 2 == 0)
      elseif persona_neuro then
        draw_band_flanks(bandg, th, bandg.mid, qx - rn(8), qx + qw + rn(8), ffade,
          shimr, shimg, shimb, #qt % 2 == 0)
      end
      love.graphics.setFont(font)
    end
  end
end

return { frame = draw_rp_frame, header = draw_rp_header, rows = draw_rp_rows, footer = draw_rp_footer }
