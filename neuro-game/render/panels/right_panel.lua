local H = require("render.hud_shared")
local Prims, S, Motion, Utils = H.Prims, H.S, H.Motion, H.Utils
local round = Prims.round
local clamp = Prims.clamp
local set_col, shadow_text = H.set_col, H.shadow_text
local smoothstep01 = H.smoothstep01
local draw_card_mini, rarity_color, joker_fx = H.draw_card_mini, H.rarity_color, H.joker_fx
local card_display_name, card_description = H.card_display_name, H.card_description
local print_tracked, tracked_width, caps_label = H.print_tracked, H.tracked_width, H.caps_label
local buy_showcase_alpha = H.buy_showcase_alpha
local DESC_FADE_D, DESC_SHOW_D = H.DESC_FADE_D, H.DESC_SHOW_D
local carousel_clock, buy_flare01 = H.carousel_clock, H.buy_flare01

local HORN_BLACK = { 0.09, 0.07, 0.08 }   -- her horns are glossy black with red tops

local function draw_rp_frame(ctx)
  local th, mo, me = H.bind(ctx)
  local pg, bg, ACC, GOLD, WHITE = th.pg, th.bg, th.ACC, th.GOLD, th.WHITE
  local now, pulse = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local rfont, boss, is_round_eval = th.rfont, th.boss, th.is_round_eval
  local rn, rp_sh, p_x, p_y, pw_total, total_h, title_h = me.rn, me.rp_sh, me.p_x, me.p_y, me.pw_total, me.total_h, me.title_h
  love.graphics.setFont(rfont)
  H.persona_frame(th, mo, p_x, p_y, pw_total, total_h, rn(1), { sh = rp_sh, rad = rn(9), title_h = title_h })
  if persona_neuro then
    -- sparkles live only in the empty right half of the title band, never over body text
    if not Motion.reduced then
      for si = 1, 5 do
        local sxr = 0.5 + 0.5 * math.sin(si * 78.233)
        local syr = 0.5 + 0.5 * math.sin(si * 39.425 + 1.7)
        local tw2 = Prims.twinkle01(now, si)
        local sx3 = p_x + math.floor(pw_total * 0.52) + sxr * (pw_total * 0.34)
        local sy3 = p_y + rn(7) + syr * (title_h - rn(16))
        Prims.draw_sparkle(sx3, sy3, rn(2) + tw2 * rn(2), (si % 2 == 0) and pg or ACC, 0.55 * tw2)
      end
    end
    local bob2 = (not Motion.reduced) and math.sin(now * 1.4) * rn(1) or 0
    local bsc2 = 1
    local bs = S.buy_showcase
    if bs and bs.started and not Motion.reduced then
      local bage = now - bs.started
      if bage >= 0 and bage < 0.35 then bsc2 = 1 + 0.08 * math.sin(math.pi * bage / 0.35) end
      if bage >= 0 and bage < 0.5 then
        local pk2 = math.sin(math.pi * (bage / 0.5))
        Prims.draw_sparkle(p_x + pw_total - rn(38), p_y + rn(10), rn(2) + pk2 * rn(3), pg, 0.8 * pk2)
      end
    end
    Prims.draw_bow(p_x + pw_total - rn(20), p_y + rn(5) + bob2, rn(2) * bsc2, ACC, 0.95, pg)
  end
  if persona_evil then
    local flare = buy_flare01(now)
    H.evil_frame(p_x, p_y, pw_total, total_h, rn(1), title_h, GOLD, pg, bg, pulse, now, 1, flare)
    Prims.ash_motes(p_x + math.floor(pw_total * 0.55), p_y + math.floor(total_h * 0.58),
      math.floor(pw_total * 0.34), math.floor(total_h * 0.30), rn(1), now, Motion.reduced, 0.6, 3)
    local sig_pop = 1 + 0.20 * flare + (is_round_eval and 0.12 or 0)
    local sig_a = math.min(1, 0.9 + 0.10 * flare + (is_round_eval and 0.10 or 0))
    local bob = (not Motion.reduced) and math.sin(now * 1.4) * rn(1) or 0
    Prims.corner_brand(p_x + pw_total - rn(20), p_y + rn(5) + bob, rn(2) * sig_pop, ACC, WHITE, 0.95 * sig_a, false)
    if boss then
      set_col(ACC, 0.42 + 0.35 * pulse)
      love.graphics.rectangle("fill", p_x + rn(4), p_y, pw_total - rn(8), math.max(1, rn(1)))
    end
  end
end

local function draw_rp_header(ctx)
  local th, mo, me, da = H.bind(ctx)
  local pg, ACC, GOLD = th.pg, th.ACC, th.GOLD
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local persona_name, boss, is_round_eval = th.persona_name, th.boss, th.is_round_eval
  local rfont, rfont_small = th.rfont, th.rfont_small
  local rn, PAD_TOP, TRACK, TRACK_SM = me.rn, me.PAD_TOP, me.TRACK, me.TRACK_SM
  local p_x, p_y, p_pad_x, r_U, pw_total, title_h = me.p_x, me.p_y, me.p_pad_x, me.r_U, me.pw_total, me.title_h
  local r_text_h, r_small_text_h = me.r_text_h, me.r_small_text_h
  local state_label, is_thinking, logo, logo_w, logo_h, logo_scale = da.state_label, da.is_thinking, da.logo, da.logo_w, da.logo_h, da.logo_scale
  local tx = p_x + p_pad_x
  local ty = p_y + rn(PAD_TOP)
  local sl_font = rfont_small
  local sl_y = ty + r_text_h + r_U
  if logo then
    local logo_y = ty + math.floor((r_text_h + r_U + r_small_text_h - logo_h) / 2)
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
  if persona_evil and not Motion.reduced then
    local gwin = 4.3
    local gseg = math.floor(now / gwin)
    local gstart = 0.45 + 0.4 * (0.5 + 0.5 * math.sin(gseg * 12.9898))
    local gt = now / gwin - gseg
    if gt > gstart and gt < gstart + 0.05 then
      local jit = rn(2)
      love.graphics.setColor(0.95, 0.10, 0.16, 0.55)
      print_tracked(persona_name, tx - jit, ty, TRACK, rfont)
      love.graphics.setColor(0.12, 0.80, 0.90, 0.42)
      print_tracked(persona_name, tx + jit, ty - 1, TRACK, rfont)
    end
  end
  local name_end = caps_label(persona_name, tx, ty, ACC, 0.97, TRACK, rfont, 0.30, rn(1))
  if persona_evil and name_end then
    local oy2 = ty + math.floor(r_text_h / 2)
    local cur_slot = (S.desc_slot or 0) * 131 + (S.cons_slot or 0)
    if S.ov.eye_slot ~= cur_slot then
      S.ov.eye_slot = cur_slot; S.ov.eye_at = now
      S.ov.eye_look_dir = (S.ov.eye_look_dir == 1) and -1 or 1
    end
    local look, hold = 0, false
    if boss and not Motion.reduced then
      look = (math.sin(now * 4.2) > 0) and 1 or -1
    elseif is_round_eval then
      hold = true
    elseif S.ov.eye_at and (now - S.ov.eye_at) < 0.5 then
      look = S.ov.eye_look_dir or 1
    elseif not Motion.reduced then
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
    Prims.draw_evil_eye(name_end + rn(12), oy2, eye_u, ACC, eye_a, now, Motion.reduced, true, look, hold)
  elseif persona_neuro and name_end then
    love.graphics.setColor(shimr, shimg, shimb, 0.55)
    love.graphics.rectangle("fill", tx, ty + r_text_h + rn(1), name_end - tx, 1)
    local bob = (not Motion.reduced) and math.sin(now * 1.4) * rn(1) or 0
    Prims.draw_heart(name_end + rn(9), ty + math.floor(r_text_h / 2) + bob, rn(3), pg, 0.85)
  end

  love.graphics.setFont(rfont_small)
  if state_label ~= S.ov.sl_text then S.ov.sl_text = state_label; S.ov.sl_at = now end
  local sl_in = math.min(1, (now - (S.ov.sl_at or now)) / 0.20)
  sl_in = sl_in * sl_in * (3 - 2 * sl_in)
  if is_thinking then
    local breathe = Motion.pulse(now, 3.2)
    local lw = tracked_width(state_label, TRACK_SM, sl_font)
    local dot_x = tx + lw + r_U + 2
    local dot_gap, dot_r = 6, 1.6
    caps_label(state_label, tx, sl_y, ACC, (0.82 + 0.12 * breathe) * sl_in, TRACK_SM, sl_font, 0.32 * sl_in, rn(1))
    if persona_evil then
      for di = 0, 2 do
        local et = Motion.reduced and 0.5 or ((now * 1.2 + di * 0.33) % 1)
        local ey3 = round(sl_y + r_small_text_h / 2 - 1 - (Motion.reduced and 0 or et * 3))
        local fa = Motion.reduced and 0.6 or ((1 - et) * (0.35 + 0.55 * Prims.candle01(now + di * 1.7)))
        love.graphics.setColor(1, 0.62 - 0.35 * et, 0.16, fa * sl_in)
        love.graphics.rectangle("fill", round(dot_x + di * dot_gap - 1), ey3, 3, 3)
      end
    else
      for di = 0, 2 do
        local db = Motion.pulse(now, 3.2, -di * 0.6)
        set_col(ACC, (0.30 + 0.60 * db) * sl_in)
        love.graphics.rectangle("fill", dot_x + di * dot_gap - dot_r, sl_y + r_small_text_h / 2 - dot_r, dot_r * 2, dot_r * 2)
      end
    end
  else
    caps_label(state_label, tx, sl_y, {1, 1, 1}, 0.42 * sl_in, TRACK_SM, sl_font, 0)
  end
  love.graphics.setFont(rfont)

  local cy = p_y + title_h
  if persona_evil then
    Prims.evil_divider(p_x, cy, pw_total, rn(1), ACC, GOLD, 1, pulse, nil, true)
  elseif persona_neuro then
    love.graphics.setColor(shimr, shimg, shimb, 0.85 + 0.10 * pulse)
    love.graphics.rectangle("fill", p_x, cy - 2, pw_total, 2)
    local mx2 = p_x + math.floor(pw_total / 2)
    local bscale = 1
    local bs = S.buy_showcase
    if bs and bs.started and not Motion.reduced then
      local bage = now - bs.started
      if bage >= 0 and bage < 0.35 then bscale = 1 + 0.10 * math.sin(math.pi * bage / 0.35) end
    end
    Prims.draw_bow_mini(mx2, cy - 1, rn(1) * 0.9 * bscale, ACC, 0.9, pg)
    Prims.draw_heart(p_x + rn(8), cy - 1, rn(3), pg, 0.55)
    Prims.draw_heart(p_x + pw_total - rn(8), cy - 1, rn(3), pg, 0.55)
  else
    set_col(ACC, 0.85 + 0.10 * pulse)
    love.graphics.rectangle("fill", p_x, cy - 2, pw_total, 2)
  end
  cy = cy + r_U
end

-- reads/returns the cursor via P.cy, but carousel slot/phase state lives on module-scope S, not P.
-- The arg table is reused across frames (draw_desc_carousel destructures every field upfront and
-- never retains P) so the hot path allocates no ~28-field literal per frame. Single-threaded.
local _carousel_P = {}
local function draw_desc_carousel(P)
  local r, rx, cy = P.r, P.rx, P.cy
  local now, cur_card_a, pulse = P.now, P.cur_card_a, P.pulse
  local rn, content_w, p_w, p_pad_x = P.rn, P.content_w, P.p_w, P.p_pad_x
  local rp_card_line_h, rp_small_line_h, rp_text_h, r_small_text_h = P.rp_card_line_h, P.rp_small_line_h, P.rp_text_h, P.r_small_text_h
  local rp_font, rfont_small = P.rp_font, P.rfont_small
  local persona_evil, persona_neuro = P.persona_evil, P.persona_neuro
  local pg, ACC, FR, FRD, GOLD = P.pg, P.ACC, P.FR, P.FRD, P.GOLD
  local shimr, shimg, shimb = P.shimr, P.shimg, P.shimb
  local trunc, wrapped_lines, draw_colored_desc = P.trunc, P.wrapped_lines, P.draw_colored_desc
  local jokers = r.cards
  local n = #jokers
  if n > 0 then
    local D_FADE = DESC_FADE_D
    local D_SHOW = DESC_SHOW_D

    local is_cons = r.which == "cons"
    local cy_slot = is_cons and S.cons_slot or S.desc_slot
    local cy_epoch = is_cons and S.cons_epoch or S.desc_epoch
    local cy_cache = is_cons and S.cons_cache or S.desc_cache
    local cy_cache_n = is_cons and S.cons_cache_n or S.desc_cache_n

    local epoch, phase = carousel_clock(now)
    -- slot out of range (card removed): reset without advancing
    if cy_slot >= n then cy_slot = 0; cy_epoch = epoch end

    local fade_a, show_progress
    local entering_f = 1
    if n == 1 then
      cy_slot = 0
      cy_epoch = epoch
      fade_a = cur_card_a
      show_progress = 1.0
    else
      if not cy_epoch then
        cy_epoch = epoch                       -- first sync, no advance
      elseif epoch ~= cy_epoch then
        cy_slot = (cy_slot + 1) % n
        cy_epoch = epoch
      end
      if phase < D_FADE then
        fade_a = Motion.anim01(phase, D_FADE)
        entering_f = fade_a
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
    local cy_dx = Motion.reduced and 0 or math.floor((1 - entering_f) * 8)

    if cy_cache_n ~= n then cy_cache = {}; cy_cache_n = n end
    local cur_jc = jokers[cy_slot + 1]
    local cached = cy_cache[cy_slot]
    if cached and cached.jc ~= cur_jc then cached = nil end
    if not cached then
      local jc2 = cur_jc
      if jc2 then
        local fx   = joker_fx(jc2) or ""
        local desc = card_description(jc2) or ""
        if desc == "" and jc2.config and jc2.config.center then
          local ok, d = pcall(Utils.safe_description, jc2.config.center.loc_txt, jc2)
          if ok and type(d) == "string" then desc = d end
        end
        local show = desc
        if show == "" then show = fx end
        local sf2   = rfont_small
        local lns   = show ~= "" and wrapped_lines(show, content_w - rn(36), sf2) or {}
        local rc2   = rarity_color(jc2)
        if not rc2 or type(rc2) ~= "table" then rc2 = {1,1,1} end
        local dname = card_display_name(jc2) or "?"
        if fx ~= "" and desc ~= "" then dname = dname .. "  " .. fx end
        cached = { name = dname, show = show,
                   lines = lns, rc = rc2, jc = jc2 }
        cy_cache[cy_slot] = cached
      end
    end
    if is_cons then
      S.cons_slot, S.cons_epoch, S.cons_cache, S.cons_cache_n = cy_slot, cy_epoch, cy_cache, cy_cache_n
    else
      S.desc_slot, S.desc_epoch, S.desc_cache, S.desc_cache_n = cy_slot, cy_epoch, cy_cache, cy_cache_n
    end

    local jc = cached and cached.jc
    if jc then
      local rc = cached.rc
      local jname = cached.name
      local lns   = cached.lines
      local sf = rfont_small

      set_col(rc, 0.06)
      love.graphics.rectangle("fill", rx + 3, cy, p_w - 6, rp_card_line_h + rp_small_line_h * 3 + 4)

      local sprite_h = rp_card_line_h - 4
      local sprite_x = rx + p_pad_x + cy_dx
      local sprite_y = cy + 2
      local est_w    = sprite_h * 0.75
      love.graphics.setColor(0, 0, 0, 0.55 * fade_a)
      love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2)
      set_col(rc, 0.60 * fade_a)
      love.graphics.setLineWidth(rn(1))
      love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2)
      if persona_evil then
        set_col(GOLD, 0.30 * fade_a)
        love.graphics.rectangle("line", sprite_x - 2, sprite_y - 2, est_w + 4, sprite_h + 4)
      elseif persona_neuro then
        love.graphics.setColor(shimr, shimg, shimb, 0.40 * fade_a)
        love.graphics.rectangle("line", sprite_x - 2, sprite_y - 2, est_w + 4, sprite_h + 4, rn(2), rn(2))
      end
      local mini_w  = draw_card_mini(jc, sprite_x, sprite_y, sprite_h, fade_a)
      local text_off = math.max(est_w, mini_w > 0 and mini_w or 0) + rn(7)

      love.graphics.setColor(0, 0, 0, 0.30 * fade_a)
      love.graphics.print(trunc(jname, content_w - text_off - rn(28), rp_font), rx + p_pad_x + cy_dx + text_off + rn(1), cy + (rp_card_line_h - rp_text_h) / 2 + rn(1))
      set_col(rc, 0.97 * fade_a)
      love.graphics.print(trunc(jname, content_w - text_off - rn(28), rp_font), rx + p_pad_x + cy_dx + text_off, cy + (rp_card_line_h - rp_text_h) / 2)

      love.graphics.setFont(rfont_small)
      local slot_txt = tostring(cy_slot + 1) .. "/" .. tostring(n)
      local stw = sf:getWidth(slot_txt)
      shadow_text(slot_txt, rx + p_w - p_pad_x - stw, cy + (rp_card_line_h - r_small_text_h) / 2, ACC, 0.60 + 0.15 * pulse, 0.20, rn(1))

      if #lns > 0 then
        local desc_y = cy + rp_card_line_h
        for li = 1, math.min(#lns, 3) do
          draw_colored_desc(lns[li], rx + p_pad_x + cy_dx + text_off, desc_y, fade_a, sf)
          desc_y = desc_y + rp_small_line_h
        end
      end
      love.graphics.setFont(rp_font)

      if n > 1 then
        local bar_y = cy + rp_card_line_h + rp_small_line_h * 3 + 2
        local bar_x = rx + p_pad_x
        local bar_h = rn(3)
        set_col(FRD, 0.90)
        love.graphics.rectangle("fill", bar_x + 1, bar_y + 1, content_w - 2, bar_h)
        set_col(FR, 0.90)
        love.graphics.setLineWidth(rn(1))
        love.graphics.rectangle("line", bar_x + 0.5, bar_y + 0.5, content_w - 1, bar_h + 1)
        local prog_w = math.max(1, (content_w - 2) * show_progress)
        if persona_neuro then
          Prims.tag_string(bar_x + 1, bar_y + 1, prog_w, 1, shimr, shimg, shimb, 1)
          Prims.draw_heart(bar_x + 1 + prog_w, bar_y + 1 + math.floor(bar_h / 2), rn(3), pg, 0.9)
        elseif persona_evil then
          set_col(ACC, 0.85)
          love.graphics.rectangle("fill", bar_x + 1, bar_y + 1, prog_w, bar_h)
          local hy = bar_y + 1 + bar_h / 2
          local hx = bar_x + 1 + prog_w
          Prims.draw_evil_heart(hx, hy, rn(3), ACC, 0.9, GOLD, true)
        else
          set_col(ACC, 0.85)
          love.graphics.rectangle("fill", bar_x + 1, bar_y + 1, prog_w, bar_h)
        end

        local mk_pop = (not Motion.reduced and n > 1 and phase < 0.15) and 1.3 or 1
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
              local ds2 = round(2 * mk_pop)
              set_col(ACC, 0.90)
              love.graphics.rectangle("fill", dx - ds2, dot_y - ds2, ds2 * 2, ds2 * 2)
            end
          else
            set_col(FR, 0.60)
            love.graphics.rectangle("fill", dx - 1, dot_y - 1, 2, 2)
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
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font, rfont, rfont_small, rp_font = th.font, th.rfont, th.rfont_small, th.rp_font
  local rn, sh, p_x, p_y, p_w, p_pad_x = me.rn, me.sh, me.p_x, me.p_y, me.p_w, me.p_pad_x
  local r_U, r_accw, pw_total, total_h, content_w, n_cols = me.r_U, me.r_accw, me.pw_total, me.total_h, me.content_w, me.n_cols
  local title_h, action_row_h, footer_h = me.title_h, me.action_row_h, me.footer_h
  local rp_text_h, rp_line_h, rp_small_line_h, rp_card_line_h, rp_sep_h = me.rp_text_h, me.rp_line_h, me.rp_small_line_h, me.rp_card_line_h, me.rp_sep_h
  local r_text_h, r_small_text_h = me.r_text_h, me.r_small_text_h
  local panel_rows, showcase_alpha, action_text = da.panel_rows, da.showcase_alpha, da.action_text
  local trunc, wrapped_lines, draw_colored_desc, row_h = dr.trunc, dr.wrapped_lines, dr.draw_colored_desc, dr.row_h
  local cy = p_y + title_h + r_U
  do
    local has_act = action_text ~= nil
    if action_text ~= S.ov.act_text then S.ov.act_text = action_text; S.ov.act_at = now end
    local act_in = math.min(1, (now - (S.ov.act_at or now)) / 0.22)
    act_in = act_in * act_in * (3 - 2 * act_in)
    local act_dx = math.floor((1 - act_in) * 8)
    local act_hi = persona_neuro and 0.30 or 0.60
    set_col(FRD, has_act and (0.40 + act_hi * act_in) or 0.30)
    love.graphics.rectangle("fill", p_x + 2, cy + 1, pw_total - 4, action_row_h - 3)
    set_col(ACC, has_act and act_in * 0.90 or 0.25)
    love.graphics.rectangle("fill", p_x + r_U, cy + r_U, r_accw, action_row_h - r_U * 2 - 1)

    if has_act then
      local act_ty = cy + math.floor((action_row_h - r_text_h) / 2)
      local act_pulse = Motion.reduced and 0.6 or math.abs(math.sin(now * 3.4))
      local caret_x = p_x + p_pad_x
      set_col(ACC, (0.55 + 0.45 * act_pulse) * act_in)
      love.graphics.print(">", caret_x, act_ty)
      local act_tx = caret_x + rfont:getWidth("> ")
      local action_draw = trunc(action_text, p_x + pw_total - p_pad_x - act_tx, rfont)
      love.graphics.setColor(0, 0, 0, 0.45 * act_in)
      love.graphics.print(action_draw, act_tx + rn(1) + act_dx, act_ty + rn(1))
      love.graphics.setColor(1, 1, 1, 0.98 * act_in)
      love.graphics.print(action_draw, act_tx + act_dx, act_ty)
    end
    cy = cy + action_row_h
    set_col(FRD, 0.90)
    love.graphics.setLineWidth(rn(1))
    love.graphics.line(p_x + p_pad_x, cy, p_x + pw_total - p_pad_x, cy)
    cy = cy + r_U
  end

  if #panel_rows > 0 then
    cy = cy + r_U
    local clip_y = p_y + total_h - footer_h
    local rp_col = 1
    local rx = p_x
    local rows_y0 = cy
    local row_sdx = S.right_panel_slide_frac > 0
      and round((pw_total + 20) * S.right_panel_slide_frac) or 0
    love.graphics.setScissor(p_x + row_sdx - 2, p_y,
      pw_total + 4, math.max(0, math.min(clip_y, sh) - p_y))
    for c = 2, n_cols do
      set_col(FRD, 0.90)
      love.graphics.rectangle("fill", p_x + (c - 1) * p_w, cy - r_U, 1, clip_y - cy + r_U)
    end
    love.graphics.setFont(rp_font)
    local buy_prominence = 0
    if S.buy_showcase and tostring(S.buy_showcase.area or "shop") ~= "booster_choice" then
      buy_prominence = buy_showcase_alpha(S.buy_showcase, now)
    end
    local spotlight = math.max(showcase_alpha or 0, buy_prominence)
    local spotlight_dim = 1 - 0.35 * spotlight
    -- rows swap to the new state same frame, reads as a crossfade, never delays the reset above
    local transition_recency = 1 - smoothstep01((now - S.state_changed_at) / 0.18)
    local transition_dip = 1 - 0.55 * transition_recency
    local row_dim = spotlight_dim * transition_dip
    local cur_card_a = row_dim
    for _, r in ipairs(panel_rows) do
      local cur_h = row_h(r)
      if cy + cur_h > clip_y and rp_col < n_cols then
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
        P.persona_evil, P.persona_neuro = persona_evil, persona_neuro
        P.pg, P.ACC, P.FR, P.FRD, P.GOLD = pg, ACC, FR, FRD, GOLD
        P.shimr, P.shimg, P.shimb = shimr, shimg, shimb
        P.trunc, P.wrapped_lines, P.draw_colored_desc = trunc, wrapped_lines, draw_colored_desc
        cy = draw_desc_carousel(P)

      elseif kind == "header" then
        local col = r.color
        local txt = r.text or ""
        set_col(col, 0.14)
        love.graphics.rectangle("fill", rx + 2, cy - 1, p_w - 4, rp_line_h + 2)
        set_col(col, 0.90)
        love.graphics.rectangle("fill", rx + r_U, cy + 2, r_accw, rp_line_h - 4)
        if persona_evil then
          set_col(GOLD, 0.16)
          love.graphics.rectangle("fill", rx + 2, cy + rp_line_h, p_w - 4, 1)
          local hd_cy = cy + math.floor(rp_line_h / 2)
          local hd_x = rx + p_w - p_pad_x
          Prims.draw_diamond(hd_x - rn(3), hd_cy, rn(1), GOLD, 0.40 + 0.20 * pulse)
        end
        love.graphics.setColor(0, 0, 0, 0.30)
        love.graphics.print(trunc(txt, content_w - 10, rp_font), rx + p_pad_x + rn(1), cy + 1 + rn(1))
        set_col(col, 1.0)
        love.graphics.print(trunc(txt, content_w - 10, rp_font), rx + p_pad_x, cy + 1)
        cy = cy + rp_line_h

      elseif kind == "sub" then
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        local sub_lines = wrapped_lines(txt, content_w - indent, rp_font)
        local n_sub = #sub_lines > 0 and #sub_lines or 1
        local block_w = math.max(28, content_w - indent + 4)
        local block_h = rp_line_h * n_sub - 2
        set_col(col, 0.06)
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

      else -- line
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        local draw_txt = trunc(txt, content_w - indent, rp_font)
        shadow_text(draw_txt, rx + p_pad_x + indent, cy, col, 0.90, 0.22, rn(1))
        cy = cy + rp_line_h
      end
    end
    love.graphics.setFont(font)
    love.graphics.setScissor()
  end
end

local function draw_rp_footer(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local FRD, DIM, GOLD = th.FRD, th.DIM, th.GOLD
  local now, pulse = H.motion(mo)
  local persona_evil = H.persona(th)
  local font, rfont_small = th.font, th.rfont_small
  local rn, p_x, p_y, p_pad_x, pw_total, total_h, footer_h = me.rn, me.p_x, me.p_y, me.p_pad_x, me.pw_total, me.total_h, me.footer_h
  local r_small_text_h = me.r_small_text_h
  local quip_display, footer_emote, footer_is_emote = da.quip_display, da.footer_emote, da.footer_is_emote
  local trunc = dr.trunc
  if footer_h > 0 then
    local fy = p_y + total_h - footer_h
    set_col(FRD, 0.90)
    love.graphics.setLineWidth(rn(1))
    love.graphics.line(p_x + p_pad_x, fy, p_x + pw_total - p_pad_x, fy)

    if footer_is_emote and footer_emote and footer_emote.img then
      local efw, efh = footer_emote.fw, footer_emote.fh
      if efw > 0 and efh > 0 then
        local emote_area_h = footer_h - rn(6)
        local max_w = pw_total - rn(20)
        local scale = math.min(max_w / efw, emote_area_h / efh)
        local dw, dh = efw * scale, efh * scale
        local ix = p_x + (pw_total - dw) / 2
        local iy = fy + (emote_area_h - dh) / 2 + 3
        love.graphics.setColor(1, 1, 1, 0.97)
        if footer_emote.quads and footer_emote.n_frames > 1 then
          local frame_idx = math.floor(now * footer_emote.fps) % footer_emote.n_frames + 1
          love.graphics.draw(footer_emote.img, footer_emote.quads[frame_idx], ix, iy, 0, scale, scale)
        else
          love.graphics.draw(footer_emote.img, ix, iy, 0, scale, scale)
        end
      end
    elseif quip_display and quip_display ~= "" then
      love.graphics.setFont(rfont_small)
      local qf = rfont_small
      local qt = trunc(quip_display, pw_total - rn(24), qf)
      local qw = qf:getWidth(qt)
      local qx = p_x + (pw_total - qw) / 2
      local qy = fy + (footer_h - r_small_text_h) / 2
      shadow_text(qt, qx, qy, DIM, 0.62 + 0.10 * pulse, 0.25, rn(1))
      if persona_evil then
        local fl_y = qy + math.floor(r_small_text_h / 2)
        local fl_in_l = qx - rn(8)
        local fl_in_r = qx + qw + rn(8)
        local fl_out_l = p_x + p_pad_x + rn(6)
        local fl_out_r = p_x + pw_total - p_pad_x - rn(6)
        if fl_in_l - fl_out_l > rn(12) then
          local seg = (fl_in_l - fl_out_l) / 3
          for i = 0, 2 do
            set_col(GOLD, (0.24 - i * 0.07))
            love.graphics.rectangle("fill", fl_in_l - (i + 1) * seg, fl_y, seg, 1)
            love.graphics.rectangle("fill", fl_in_r + i * seg, fl_y, seg, 1)
          end
          Prims.draw_glint(fl_out_l, fl_y, rn(2), th.ACC, 0.9, GOLD, true)
          if #qt % 2 == 0 then
            Prims.wax_seal(fl_out_r, fl_y, rn(2), rn(1), GOLD, 0.9, pulse)
          else
            Prims.draw_glint(fl_out_r, fl_y, rn(2), th.ACC, 0.9, GOLD, true)
          end
        end
      end
      love.graphics.setFont(font)
    end
  end
end

return { frame = draw_rp_frame, header = draw_rp_header, rows = draw_rp_rows, footer = draw_rp_footer }
