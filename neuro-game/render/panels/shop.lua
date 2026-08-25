local H = require("render.hud_shared")
local RectMesh = require("render.rect_mesh")
local Prims, S, Motion = H.Prims, H.S, H.Motion
local round, clamp = Prims.round, Prims.clamp
local set_col, shadow_text = H.set_col, H.shadow_text
local tracked_width, caps_label = H.tracked_width, H.caps_label
local rarity_color = H.rarity_color
local draw_card_mini = H.draw_card_mini
local card_dimensions = H.card_dimensions
local draw_modifier_badges = H.draw_modifier_badges
local buy_flare01 = H.buy_flare01
local Rows = require("hud.rows")

local SHOP_OVERHANG = 8

local SHIM_C = { 0, 0, 0 }
local PRICE_WHITE = { 1, 1, 1 }

local PIN_MO = { pulse = 0.5 }
local function pin_mo(mo)
  PIN_MO.pulse = (mo and mo.pulse) or 0.5
  return PIN_MO
end
local CardUtil = require("facts.card_util")
local StateKinds = require("core.state_kinds")

local _rr_cur, _rr_seen = {}, {}

local function joker_refs(out)
  local area = G and G.shop_jokers
  local cards = area and area.cards
  local n = 0
  if cards then
    for i = 1, #cards do n = n + 1; out[n] = cards[i] end
  end
  for i = #out, n + 1, -1 do out[i] = nil end
  return out
end

local function all_replaced(prev, cur)
  if #prev == 0 or #cur == 0 then return false end
  for i = 1, #cur do
    for j = 1, #prev do
      if cur[i] == prev[j] then return false end
    end
  end
  return true
end

local function anim01_inv(a)
  if a <= 0 then return 0 end
  if a >= 1 then return 1 end
  return 1 - (1 - a) ^ (1 / 3)
end

local SET_NAME_COLOR = {
  Tarot = { 0.70, 0.52, 0.88 }, Planet = { 0.45, 0.70, 1.0 }, Spectral = { 0.60, 0.58, 0.95 },
}

local _lp_metrics = { carousel_pad = 0 }

local _row_hs = {}
local function measure_rows(rows)
  local total = 0
  for i = 1, #rows do
    local h = Rows.height(rows[i], _lp_metrics)
    _row_hs[i] = h
    total = total + h
  end
  return total
end

local CACHE_MAX = 128

local _slot_w, _slot_w_n, _slot_w_font = {}, 0, nil
local function price_slot_w(price_txt, font)
  if font ~= _slot_w_font then _slot_w, _slot_w_n, _slot_w_font = {}, 0, font end
  local w = _slot_w[price_txt]
  if w then return w end
  local tpl = price_txt:gsub("%d", "0")
  if #tpl < 3 then tpl = "$00" end   -- reserve >= 2 digits so $1..$99 never pops the plate
  w = font:getWidth(tpl)
  if _slot_w_n >= CACHE_MAX then _slot_w, _slot_w_n = {}, 0 end
  _slot_w[price_txt] = w
  _slot_w_n = _slot_w_n + 1
  return w
end

local _money_txt, _money_txt_n = {}, 0
local function money_text(prefix, n)
  local per = _money_txt[prefix]
  if not per then per = {}; _money_txt[prefix] = per end
  local t = per[n]
  if t then return t end
  t = prefix .. tostring(n)
  if _money_txt_n >= CACHE_MAX then _money_txt, _money_txt_n = {}, 0; _money_txt[prefix] = { [n] = t } end
  per[n] = t
  _money_txt_n = _money_txt_n + 1
  return t
end

local _hdr_keys = {}
local function hdr_key(i)
  local k = _hdr_keys[i]
  if not k then k = "shop_hdr" .. i; _hdr_keys[i] = k end
  return k
end

local _hdr_label, _hdr_label_n = {}, 0
local function header_label(text)
  local label = _hdr_label[text]
  if label then return label end
  label = ((text):gsub("^Shop:%s*", "")):upper()
  if _hdr_label_n >= CACHE_MAX then _hdr_label, _hdr_label_n = {}, 0 end
  _hdr_label[text] = label
  _hdr_label_n = _hdr_label_n + 1
  return label
end

local _sig_a, _sig_b, _sig_c, _sig_d, _sig_e, _sig_s
local _sig_parts = {}
local function layout_sig(a, b, c, d, e)
  if a ~= _sig_a or b ~= _sig_b or c ~= _sig_c or d ~= _sig_d or e ~= _sig_e or not _sig_s then
    _sig_a, _sig_b, _sig_c, _sig_d, _sig_e = a, b, c, d, e
    _sig_parts[1], _sig_parts[2], _sig_parts[3], _sig_parts[4], _sig_parts[5] = a, b, c, d, e
    _sig_s = table.concat(_sig_parts, ":")
  end
  return _sig_s
end

local _hud
local function hud_layout()
  if not _hud then _hud = require("render.hud_overlay") end
  return _hud
end

local function draw_shop_panel(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local pg, bg, ACC, FR, FRD, DIM, WHITE, GOLD = th.pg, th.bg, th.ACC, th.FR, th.FRD, th.DIM, th.WHITE, th.GOLD
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font, lfont, lfont_small = th.font, th.lfont, th.lfont_small
  local ln, lp_sh, sw, sh, U, GUT, ACCENT_W, TRACK =
    me.ln, me.lp_sh, me.sw, me.sh, me.U, me.GUT, me.ACCENT_W, me.TRACK
  TRACK = ln(TRACK)
  local p_x, p_y, pw_total, card_line_h, sep_h =
    me.p_x, me.p_y, me.pw_total, me.card_line_h, me.sep_h
  local shop_rows = da.shop_rows
  local trunc, wrapped_lines, draw_colored_desc = dr.trunc, dr.wrapped_lines, dr.draw_colored_desc
  local draw_desc_lines = dr.draw_desc_lines
  local shop_visible = #shop_rows > 0

  local game_ref = G and G.GAME
  if S.shop_leave_game ~= game_ref then
    S.shop_leave_t, S.shop_leave_snap, S.shop_leave_game = nil, nil, nil
  end

  local snap_n = S.shop_leave_snap and #S.shop_leave_snap or 0
  local leave_stag = math.min(Motion.STAGGER_TIGHT, Motion.MED / math.max(1, snap_n - 1))
  local leave_span = Motion.MED + math.max(0, snap_n - 1) * leave_stag

  local sn = da.sn or ""
  local parked = (not shop_visible) and snap_n > 0
    and StateKinds.is_shop_interlude(sn) and not StateKinds.is_pack_state(sn)
  local on_stage = shop_visible or parked

  if on_stage then
    if not S.shop_last_visible then
      if S.shop_leave_t and (now - S.shop_leave_t) < leave_span and (S.shop_alpha_last or 0) > 0 then
        S.shop_appear_t = now - Motion.MED * anim01_inv(S.shop_alpha_last)
      else
        S.shop_appear_t = now
        S.shop_h_current = nil
      end
      S.shop_leave_t = nil
    end
    if shop_visible then
      local snap = S.shop_leave_snap
      if not snap then snap = {}; S.shop_leave_snap = snap end
      for i = #snap, 1, -1 do snap[i] = nil end
      for i = 1, #shop_rows do snap[i] = shop_rows[i] end
      S.shop_leave_game = game_ref
    end
  elseif S.shop_last_visible then
    S.shop_leave_t = now
  end
  S.shop_last_visible = on_stage

  local n_leave = (not on_stage) and snap_n or 0
  local leaving = n_leave > 0 and S.shop_leave_t ~= nil
    and (now - S.shop_leave_t) >= 0 and (now - S.shop_leave_t) < leave_span
  local leave01 = 1
  if leaving then
    local lt = ((now - S.shop_leave_t) - Motion.STAGGER_WIDE)
      / math.max(0.01, leave_span - Motion.STAGGER_WIDE)
    leave01 = 1 - Prims.smoothstep01(lt < 0 and 0 or (lt > 1 and 1 or lt))
  end

  local drawn = (on_stage or leaving) and (S.left_panel_slide_frac or 0) < 1
  do
    local gr = G and G.GAME
    local money = (gr and gr.dollars) or 0
    local rr = gr and gr.current_round and gr.current_round.reroll_cost
    if drawn and S.sz_money_last ~= nil and money ~= S.sz_money_last then S.sz_money_at = now end
    S.sz_money_last = money
    if drawn and S.rr_last ~= nil and rr ~= S.rr_last then S.rr_stab_at = now end
    S.rr_last = rr

    local cur = joker_refs(_rr_cur)
    if drawn and S.shop_reroll_seen and all_replaced(S.shop_reroll_seen, cur) then
      S.shop_reroll_t = now
      S.shop_ignite_t = now + Motion.STAGGER
    end
    if drawn then
      for i = 1, #cur do _rr_seen[i] = cur[i] end
      for i = #_rr_seen, #cur + 1, -1 do _rr_seen[i] = nil end
      S.shop_reroll_seen = _rr_seen
    else
      S.shop_reroll_seen = nil
    end
  end

  if on_stage or leaving then
    if not shop_visible then shop_rows = S.shop_leave_snap end
    local lp_w = ln(380)
    local lp_x
    local lp_y = p_y
    local lp_pad_x = ln(GUT)
    local l_U = ln(U)
    local l_accw = ln(ACCENT_W)
    local lp_content_w = lp_w - lp_pad_x * 2

    local shop_in = Motion.anim01(now - S.shop_appear_t, Motion.MED)
    local sa = shop_in * leave01
    S.shop_alpha_last = sa

    local reroll_dip = 1
    if S.shop_reroll_t then
      local rd = (now - S.shop_reroll_t) / 0.26
      if rd >= 0 and rd < 1 then
        reroll_dip = 1 - 0.28 * math.sin(math.pi * rd)
      else
        S.shop_reroll_t = nil
      end
    end
    local sa_rows = sa * reroll_dip

    local l_text_h = lfont:getHeight()
    local l_small_text_h = lfont_small and lfont_small:getHeight() or l_text_h
    local l_title_text_h = th.lfont_title:getHeight()
    local lp_hdr_line_h = l_title_text_h + ln(4)
    local lp_small_font = lfont_small
    local lp_font, lp_text_h = lfont, l_text_h
    local lp_line_h, lp_small_line_h = l_text_h + ln(4), l_small_text_h + ln(2)
    local lp_card_line_h, lp_sep_h = ln(card_line_h), ln(sep_h)

    local lp_metrics = _lp_metrics
    lp_metrics.line_h, lp_metrics.small_line_h, lp_metrics.card_line_h = lp_line_h, lp_small_line_h, lp_card_line_h
    lp_metrics.header_line_h = lp_hdr_line_h
    lp_metrics.sep_h, lp_metrics.content_w = lp_sep_h, lp_content_w
    lp_metrics.small_font, lp_metrics.wrap = lp_small_font, wrapped_lines
    lp_metrics.badge_gap = ln(2)
    lp_metrics.badge_unit = ln(1)
    lp_metrics.badge_w = math.max(20, lp_content_w - math.ceil(71 * ((lp_card_line_h - ln(4)) / 95)) - ln(8))
    local lp_data_h = ln(8) + measure_rows(shop_rows)
    local lp_title_h = ln(44)
    local lp_total_h = lp_title_h + lp_data_h
    local anchor = me.anchor or "auto"
    local shop_anchor = me.shop_anchor or "auto"
    local shop_free = shop_anchor ~= "auto"
    local lp_avail_h
    if shop_free then
      lp_avail_h = hud_layout().panel_available_height(shop_anchor, me.shop_offset_y, sh, 0)
    else
      local anchored_full_height = anchor:sub(1, 6) == "middle" or anchor:sub(1, 6) == "bottom"
      lp_avail_h = anchored_full_height and math.max(1, sh - 16) or math.max(1, sh - lp_y - 10)
    end
    local lp_pref_h = math.min(lp_avail_h, math.floor(sh * 0.72))
    S.lp_compact = Rows.want_compact(S.lp_compact, lp_total_h, lp_pref_h)
    local lp_cols = 1
    if S.lp_compact then
      lp_font, lp_text_h = lp_small_font, l_small_text_h
      Rows.compact_metrics(lp_metrics, l_small_text_h, ln)
      lp_small_line_h = lp_metrics.small_line_h
      lp_card_line_h, lp_sep_h = lp_metrics.card_line_h, lp_metrics.sep_h
      lp_hdr_line_h = lp_metrics.header_line_h
      lp_data_h = ln(8) + measure_rows(shop_rows)
      lp_total_h = lp_title_h + lp_data_h
      if lp_total_h > lp_avail_h then
        local avail_data = math.max(lp_card_line_h, lp_avail_h - lp_title_h - ln(8))
        local used_h
        lp_cols, used_h = Rows.pack_columns(shop_rows, lp_metrics, avail_data, 3, _row_hs)
        lp_total_h = lp_title_h + ln(8) + used_h
        if lp_total_h > lp_avail_h then lp_total_h = lp_avail_h end
      end
    end
    local dt = mo.dt or 0.016
    if S.shop_h_current == nil then
      S.shop_h_current = lp_total_h
    elseif not leaving then
      S.shop_h_current = Rows.ease_height(S.shop_h_current, lp_total_h, dt)
    end
    local lp_total_h_target = lp_total_h
    lp_total_h = round(S.shop_h_current)
    local lp_cols_used = lp_cols
    local lp_sig = layout_sig(sw, sh, shop_anchor, me.shop_offset_x or 0, lp_w)
    local lp_hard_cap = math.max(1, math.floor((sw - 16) / math.max(1, lp_w)))
    S.lp_cols_latch, lp_cols =
      Rows.latch_columns(S.lp_cols_latch, lp_cols, lp_sig, math.min(3, lp_hard_cap))
    local lp_w_total = lp_w * lp_cols
    local shop_side, lp_x_target, lp_y_target
    if shop_free then
      lp_x_target, lp_y_target, shop_side = hud_layout().panel_layout(
        shop_anchor, me.shop_offset_x, me.shop_offset_y, sw, sh, lp_w_total, lp_total_h, 0)
    else
      shop_side = me.main_side == "left" and "right" or "left"
      local auto_inset = sw * (tonumber(me.shop_offset_x or me.offset_x) or 0) / 100
      lp_x_target = shop_side == "left"
        and (8 + auto_inset)
        or (sw - lp_w_total - 8 - auto_inset)
      if shop_side == "left" then
        lp_x_target = math.min(lp_x_target, p_x - lp_w_total - 8)
      else
        lp_x_target = math.max(lp_x_target, p_x + pw_total + 8)
      end
      lp_x_target = clamp(round(lp_x_target), 8, math.max(8, sw - lp_w_total - 8))
      local dy = sh * (tonumber(me.shop_offset_y or me.offset_y) or 0) / 100
      if anchor:sub(1, 6) == "middle" then
        lp_y_target = (sh - lp_total_h) / 2 + dy
      elseif anchor:sub(1, 6) == "bottom" then
        lp_y_target = sh - lp_total_h - 8 + dy
      else
        lp_y_target = p_y + (sh * (tonumber(me.shop_offset_y) or 0) / 100)
      end
      lp_y_target = clamp(round(lp_y_target), 8, math.max(8, sh - lp_total_h - 8))
    end
    Motion.snap(S, "shop_x", lp_x_target)
    Motion.approach(S, "shop_y", lp_y_target, dt, Motion.MED / 4)
    lp_x, lp_y = round(S.shop_x_current), round(S.shop_y_current)

    local shop_slide_dir = shop_side == "left" and -1 or 1
    local lp_dx = round(shop_slide_dir * (lp_w_total + 20) * S.left_panel_slide_frac)
    local lp_pushed = S.left_panel_slide_frac > 0

    -- Off-screen skip (like right panel's rp_on_screen, hud_overlay.lua:834): now reachable because
    -- the exit keeps this panel alive and translated off-frame for Motion.MED.
    local lp_span0, lp_span1 = lp_x + lp_dx, lp_x + lp_dx + lp_w_total
    local lp_on_screen = (lp_span0 - SHOP_OVERHANG) < sw and (lp_span1 + SHOP_OVERHANG) > 0
    if lp_on_screen then
    if lp_pushed then
      love.graphics.push()
      love.graphics.translate(lp_dx, 0)
    end

    local lprad, lp_tiled = H.persona_frame(th, mo, lp_x, lp_y, lp_w_total, lp_total_h, ln(1),
      { a = sa, sh = lp_sh, rad = ln(9), title_h = lp_title_h, skip_body = true,
        glow = true, quiet = true, body_wash_a = 0.014 })
    local ev_flare = persona_evil and buy_flare01(now) or 0
    if persona_evil then
      if not lp_tiled then
        set_col(pg, 0.014 * sa)
        love.graphics.rectangle("fill", lp_x + 1, lp_y + lp_title_h,
          lp_w_total - 2, lp_total_h - lp_title_h - 1)
      end
      Prims.embers(lp_x + ln(10), lp_y + lp_title_h, lp_w_total - ln(20),
        lp_total_h - lp_title_h - ln(6), ln(1), now, 0.5 * sa, 3,
        lp_total_h_target - lp_title_h - ln(6))
      H.evil_frame(lp_x, lp_y, lp_w_total, lp_total_h, ln(1), lp_title_h, GOLD, pg, bg, pulse, now, sa, ev_flare, 0.5)
      Prims.candle_finial(lp_x + math.floor(lp_w_total / 2), lp_y + lp_title_h - ln(3), ln(1), GOLD, sa, now, ev_flare)
    elseif persona_neuro then
      Prims.counter_glow(lp_x, lp_y, lp_w_total, lp_total_h, pg, sa, pulse, lprad)
      Prims.awning(lp_x + lprad, lp_y + 1, lp_w_total - lprad * 2, ln(1), ACC, pg, sa, true)
      local bsc = 1
      local bs = S.buy_showcase
      if bs and bs.started then
        local bage = now - bs.started
        bsc = 1 + 0.10 * H.buy_pop01(now)
        if bage >= 0 and bage < 0.5 then
          local pk = math.sin(math.pi * (bage / 0.5))
          Prims.draw_sparkle(lp_x + lp_w_total - ln(26), lp_y + ln(9), ln(2) + pk * ln(3), pg, 0.8 * pk * sa)
        end
      end
      Prims.draw_bow_mini(lp_x + math.floor(lp_w_total / 2), lp_y + ln(3), ln(1) * 0.9 * bsc, ACC, 0.9 * sa, pg)
      for si = 1, 3 do
        local sxr = 0.5 + 0.5 * math.sin(si * 78.233 + 0.4)
        local tw2 = Prims.twinkle01(now, si)
        local sx3 = lp_x + math.floor(lp_w_total * 0.5) + sxr * (lp_w_total * 0.34)
        local sy3 = lp_y + math.floor(lp_title_h * 0.55) + (0.5 + 0.5 * math.sin(si * 39.425 + 1.7)) * ln(8)
        Prims.draw_sparkle(sx3, sy3, ln(2) + tw2 * ln(2), (si % 2 == 0) and pg or ACC, 0.45 * tw2 * sa)
      end
    end

    love.graphics.setFont(th.lfont_title)
    local sh_tx = lp_x + lp_pad_x
    local sh_ty = lp_y + math.floor((lp_title_h - l_title_text_h) / 2)
    local sh_nw = tracked_width("SHOP", TRACK, th.lfont_title)
    if persona_evil then
      love.graphics.setColor(0, 0, 0, 0.32 * sa)
      love.graphics.rectangle("fill", sh_tx - ln(6), sh_ty - ln(3), sh_nw + ln(12), l_title_text_h + ln(6))
    end
    caps_label("SHOP", sh_tx, sh_ty, WHITE, 0.97, TRACK, th.lfont_title, 0.30, ln(1),
      nil, S, "shop_title", sa)
    if persona_neuro then
      love.graphics.setColor(shimr, shimg, shimb, 0.55 * sa)
      love.graphics.rectangle("fill", sh_tx, sh_ty + l_title_text_h + ln(1), sh_nw, 1)
      Prims.draw_heart(sh_tx + sh_nw + ln(9), sh_ty + math.floor(l_title_text_h / 2), ln(3), pg, 0.85 * sa)
    end

    do
      local money = (G.GAME and G.GAME.dollars) or 0
      local rr = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost
      local pf = th.lfont_title or lfont
      local pfh = pf:getHeight()
      local iy = lp_y + math.floor((lp_title_h - pfh) / 2)
      love.graphics.setFont(pf)
      local m_txt = money_text("$", money)
      local m_w = pf:getWidth(m_txt)
      local m_x = lp_x + lp_w_total - lp_pad_x - m_w
      local r_txt, r_w
      if type(rr) == "number" then
        r_txt = money_text("RR $", rr)
        r_w = pf:getWidth(r_txt)
      end
      if persona_evil then
        local ext = r_w and (r_w + ln(21)) or 0
        love.graphics.setColor(0, 0, 0, 0.32 * sa)
        love.graphics.rectangle("fill", m_x - ln(5) - ext, iy - ln(2), m_w + ln(10) + ext, pfh + ln(4))
      end
      local m_ox = ln(1)  -- 4-way outline keeps the number legible over ember/glow washes
      local m_col = GOLD
      if persona_neuro or persona_evil then
        SHIM_C[1], SHIM_C[2], SHIM_C[3] = shimr, shimg, shimb
        m_col = SHIM_C
      end
      shadow_text(m_txt, m_x, iy, m_col, 0.97 * sa, 0.55 * sa, m_ox, true)
      if persona_neuro and S.sz_money_at then
        local mk = math.min(1, 1 - (now - S.sz_money_at) / 0.5)
        if mk > 0 then
          Prims.draw_sparkle(m_x + m_w + ln(5), iy + math.floor(pfh / 2), ln(2) + mk * ln(2), pg, 0.9 * mk * sa)
        end
      end
      if r_txt then
        local r_x = m_x - ln(persona_evil and 14 or 10) - r_w
        shadow_text(r_txt, r_x, iy, ACC, 0.92 * sa, 0.30 * sa, ln(1))
        local r_cy = iy + math.floor(pfh / 2)
        if persona_evil then
          local stab = 0
          if S.rr_stab_at then
            local st2 = (now - S.rr_stab_at) / 0.25
            if st2 >= 0 and st2 < 1 then stab = round(math.sin(math.pi * st2) * ln(3)) end
          end
          Prims.draw_knife(r_x - ln(7), r_cy + stab, ln(1), GOLD, WHITE, 0.9 * sa, true)
        elseif persona_neuro then
          local rpop = 0
          if S.rr_stab_at then
            local rt2 = (now - S.rr_stab_at) / 0.35
            if rt2 >= 0 and rt2 < 1 then rpop = math.sin(math.pi * rt2) end
          end
          Prims.draw_sparkle(r_x - ln(7), r_cy, ln(2) + rpop * ln(2), pg, (0.7 + 0.25 * rpop) * sa)
        end
      end
      love.graphics.setFont(lfont)
    end

    local lcy = lp_y + lp_title_h
    if persona_evil then
      local ignite_from = S.shop_appear_t
      if S.shop_ignite_t and S.shop_ignite_t > (S.shop_appear_t or 0) then
        ignite_from = S.shop_ignite_t
      end
      Prims.evil_divider(lp_x, lcy, lp_w_total, ln(1), ACC, GOLD, sa, pulse, nil, false,
        math.min(1, math.max(0, (now - (ignite_from or 0)) / 0.6)))
    elseif persona_neuro then
      love.graphics.setColor(shimr, shimg, shimb, (0.85 + 0.10 * pulse) * sa)
      love.graphics.rectangle("fill", lp_x, lcy - 2, lp_w_total, 2)
      Prims.draw_heart(lp_x + ln(8), lcy - 1, ln(3), pg, 0.55 * sa)
      Prims.draw_heart(lp_x + lp_w_total - ln(8), lcy - 1, ln(3), pg, 0.55 * sa)
    else
      set_col(ACC, (0.85 + 0.10 * pulse) * sa)
      love.graphics.rectangle("fill", lp_x, lcy - 2, lp_w_total, 2)
    end
    for c = 2, lp_cols_used do
      set_col(FRD, 0.90 * sa)
      love.graphics.rectangle("fill", lp_x + (c - 1) * lp_w, lcy, 1, lp_total_h - lp_title_h)
    end
    lcy = lcy + l_U + 2

    local lp_clip_y = lp_y + lp_total_h
    local lp_col = 1
    local lx = lp_x
    local lp_rows_y0 = lcy
    love.graphics.setFont(lp_font)
    for ri, r in ipairs(shop_rows) do
      local cur_h = _row_hs[ri]
      if lcy + cur_h > lp_clip_y then
        if lp_col < lp_cols then
          lp_col = lp_col + 1
          lx = lx + lp_w
          lcy = lp_rows_y0
        else
          break
        end
      end

      local row_a = 1
      if leaving then
        local lead = (n_leave - ri) * leave_stag
        local rt = ((now - S.shop_leave_t) - lead) / Motion.MED
        row_a = 1 - Prims.smoothstep01(rt < 0 and 0 or (rt > 1 and 1 or rt))
      end
      local row_sa = leaving and (shop_in * row_a) or sa_rows
      love.graphics.push()
      love.graphics.translate(0, math.floor((1 - row_a) * ln(10)))

      if r.kind == "sep" then
        lcy = lcy + l_U
        local sepx1 = lx + lp_pad_x
        local sepx2 = lx + lp_w - lp_pad_x
        if persona_evil then
          Prims.evil_divider(sepx1, lcy + 1, sepx2 - sepx1, ln(1), ACC, GOLD, 0.7 * row_sa, pulse, 1, true)
          Prims.draw_glint(sepx1 + ln(2), lcy, ln(2), ACC, 0.7 * row_sa, GOLD, true)
          Prims.draw_glint(sepx2 - ln(2), lcy, ln(2), ACC, 0.7 * row_sa, GOLD, true)
        elseif persona_neuro then
          Prims.tag_string(sepx1, lcy, sepx2 - sepx1, ln(1), shimr, shimg, shimb, row_sa, true)
          Prims.draw_heart(sepx1 + ln(2), lcy, ln(2), pg, 0.55 * row_sa)
          Prims.draw_heart(sepx2 - ln(2), lcy, ln(2), pg, 0.55 * row_sa)
        else
          set_col(FRD, 0.90 * row_sa)
          love.graphics.setLineWidth(ln(1))
          love.graphics.line(sepx1, lcy, sepx2, lcy)
        end
        lcy = lcy + lp_sep_h - l_U
      elseif r.kind == "descwrap" then
        local txt = r.text or ""
        local indent = r.indent or 0
        set_col(FR, 0.60 * row_sa)
        love.graphics.rectangle("fill", lx + lp_pad_x + indent - ln(6), lcy + 1, l_accw, cur_h - 3)
        love.graphics.setFont(lp_small_font)
        local sf = lp_small_font
        local lines = wrapped_lines(txt, math.max(20, lp_content_w - indent), sf)
        draw_desc_lines(lines, math.min(#lines, Rows.DESC_MAX_LINES),
          lx + lp_pad_x + indent, lcy, lp_small_line_h, 0.92 * row_sa, sf)
        love.graphics.setFont(lp_font)
        lcy = lcy + cur_h
      elseif r.kind == "shopcard" then
        local name = r.text or ""
        local indent = r.indent or 0
        local card_obj = r.card
        local cost = r.cost or 0
        local afford = r.afford
        local name_col = r.color or WHITE
        local row_cy = lcy + math.floor((lp_card_line_h - lp_text_h) / 2)

        local row_x = lx + lp_pad_x + indent
        local row_x2 = lx + lp_w - lp_pad_x
        if afford and not persona_neuro then
          set_col(GOLD, 0.045 * row_sa)
          love.graphics.rectangle("fill", lx + 2, lcy, lp_w - 4, lp_card_line_h - 1)
        elseif not afford and persona_evil then
          love.graphics.setColor(0, 0, 0, 0.16 * row_sa)
          love.graphics.rectangle("fill", lx + 2, lcy, lp_w - 4, lp_card_line_h - 1)
        end

        local sprite_h = lp_card_line_h - ln(4)
        local sprite_x = row_x
        local est_w, est_h = card_dimensions(card_obj, sprite_h)
        local sprite_y = lcy + math.floor((lp_card_line_h - est_h) / 2)
        local mini_w = draw_card_mini(card_obj, sprite_x, sprite_y, sprite_h, (afford and 1 or 0.6) * row_sa)
        love.graphics.setLineWidth(ln(1))
        if persona_neuro then
          love.graphics.setColor(shimr, shimg, shimb, (afford and 0.40 or 0.18) * row_sa)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, est_h + 2)
        elseif persona_evil then
          Prims.photo_corners(sprite_x - 1, sprite_y - 1, est_w + 2, est_h + 2, GOLD, (afford and 0.60 or 0.25) * row_sa, ln(3))
        else
          set_col(GOLD, (afford and 0.35 or 0.16) * row_sa)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, est_h + 2)
        end
        local name_x = sprite_x + (mini_w > 0 and mini_w or est_w) + ln(8)

        local price_txt = money_text("$", cost)
        local pfont2 = lp_small_font or lp_font
        love.graphics.setFont(pfont2)
        local pw2 = pfont2:getWidth(price_txt)
        local pfh2 = pfont2:getHeight()
        local pty = lcy + math.floor((lp_card_line_h - pfh2) / 2)
        local slot_w = price_slot_w(price_txt, pfont2)
        local ptx = row_x2 - pw2
        local slot_x = row_x2 - slot_w                   -- plate geometry anchors to the reserved slot, not live width
        local price_left
        if persona_neuro then
          local tx0 = slot_x - ln(4)
          local ty0 = pty - ln(1)
          local tw3 = slot_w + ln(8)
          local th3 = pfh2 + ln(2)
          local tmy = ty0 + math.floor(th3 / 2)
          love.graphics.setColor(shimr, shimg, shimb, (afford and 0.55 or 0.25) * row_sa)
          love.graphics.rectangle("line", tx0, ty0, tw3, th3, ln(2), ln(2))
          love.graphics.line(tx0 - ln(4), tmy, tx0, tmy)
          love.graphics.circle("fill", tx0 - ln(4), tmy, 1.2)
          price_left = tx0 - ln(6)
        elseif persona_evil then
          local seal_cx = slot_x - ln(8)
          local pl_x = seal_cx - ln(5)
          local pl_h = pfh2 + ln(4)
          Prims.plate_label(pl_x, pty - ln(2), row_x2 - pl_x + ln(1), pl_h, GOLD, (afford and 0.9 or 0.5) * row_sa, false, 0.42)
          Prims.wax_seal(seal_cx, lcy + math.floor(lp_card_line_h / 2), ln(4), ln(1), GOLD,
            (afford and 0.95 or 0.40) * row_sa, pulse, afford)
          if afford and S.sz_money_at then
            local glint_t = (now - S.sz_money_at) - (ri - 1) * Motion.STAGGER_TIGHT
            local mk3 = glint_t >= 0 and math.min(1, 1 - glint_t / 0.35) or 0
            if mk3 > 0 then
              Prims.draw_glint(seal_cx, lcy + math.floor(lp_card_line_h / 2), ln(2), ACC, 0.9 * mk3 * row_sa, GOLD, true)
            end
          end
          price_left = pl_x - ln(3)
        else
          price_left = slot_x - ln(4)
        end
        local lock_w = 0
        if not afford then
          lock_w = ln(12)
          local lu = ln(2)
          local body_w = ln(5)
          local body_h = ln(4)
          local bx = price_left - lock_w + ln(2)
          local by = lcy + math.floor((lp_card_line_h - body_h) / 2)
          local bcx = bx + body_w / 2
          love.graphics.setColor(0, 0, 0, 0.85 * row_sa)
          love.graphics.circle("line", bcx, by + lu * 0.6, lu * 0.8)
          love.graphics.rectangle("fill", bx, by + lu * 0.6, body_w, body_h - lu * 0.6)
          love.graphics.setColor(0.90, 0.91, 0.93, 0.95 * row_sa)
          love.graphics.rectangle("fill", bx + lu * 0.35, by + lu * 0.9, body_w - lu * 0.7, lu * 0.6)
          love.graphics.setColor(1, 1, 1, 1)
        end
        price_left = price_left - lock_w
        local price_col, price_a
        if afford then
          price_col, price_a = persona_neuro and PRICE_WHITE or GOLD, 0.96 * row_sa
        else
          price_col, price_a = DIM, 0.70 * row_sa
        end
        shadow_text(price_txt, ptx, pty, price_col, price_a, 0.35 * row_sa, ln(1))
        love.graphics.setFont(lp_font)

        local name_max = price_left - ln(4) - name_x
        local lp_txt = trunc(name, name_max, lp_font)
        local name_rc = name_col
        if r.card then
          name_rc = rarity_color(r.card)
          if not name_rc then
            local cs = CardUtil.card_set(r.card)
            name_rc = SET_NAME_COLOR[cs]
              or (cs == "Voucher" and GOLD)
              or (cs == "Booster" and ACC)
              or name_col
          end
        end
        shadow_text(lp_txt, name_x, row_cy, name_rc, (afford and 0.98 or 0.72) * row_sa, 0.42 * row_sa, ln(1))
        if r.badges and #r.badges > 0 then
          local badge_layout = Rows.badge_layout(
            r.card, r.badges, lp_small_font, math.max(1, row_x2 - name_x), ln(1), 1)
          draw_modifier_badges(badge_layout, name_x, lcy + lp_card_line_h,
            (afford and 1 or 0.6) * row_sa, th, pin_mo(mo))
        end
        lcy = lcy + cur_h
      elseif r.kind == "header" then
        love.graphics.setFont(th.lfont_title)
        local label = header_label(r.text or "")
        local htxt = trunc(label, lp_content_w - 10, th.lfont_title)
        set_col(th.ROW, 0.90 * row_sa)
        love.graphics.rectangle("fill", lx + 2, lcy - 1, lp_w - 4, lp_hdr_line_h + 2)
        set_col(r.color or pg, 0.9 * row_sa)
        love.graphics.rectangle("fill", lx + l_U, lcy, l_accw, lp_hdr_line_h)
        local htx = lx + lp_pad_x
        caps_label(htxt, htx, lcy + 1, r.color or WHITE, 0.96, TRACK, th.lfont_title, 0.40, ln(1),
          nil, S, hdr_key(ri), row_sa)
        local hw = tracked_width(htxt, TRACK, th.lfont_title)
        local hbx = htx + hw + ln(7)
        local hby = lcy + 1 + math.floor(l_title_text_h / 2)
        if persona_evil then
          Prims.wax_seal(hbx, hby, ln(3), ln(1), GOLD, row_sa, pulse)
        elseif persona_neuro then
          Prims.draw_sparkle(hbx, hby, ln(3), pg, 0.9 * row_sa)
        end
        local rl_x = hbx + ln(6)
        local rl_x2 = lx + lp_w - lp_pad_x
        if rl_x2 > rl_x + ln(8) then
          local segs = 3
          local segw = (rl_x2 - rl_x) / segs
          local rule = RectMesh.get("shop_hdr_rule", segw)
          if not rule and RectMesh.available() then
            local v, i = {}, {}
            for k = 0, segs - 1 do
              RectMesh.add(v, i, k * segw, 0, math.ceil(segw), 1, 1, 1, 1, 0.34 - k * 0.09)
            end
            rule = RectMesh.build(v, i)
            if rule then RectMesh.put("shop_hdr_rule", segw, nil, nil, nil, nil, nil, rule) end
          end
          if rule then
            if persona_evil then
              set_col(ACC, row_sa)
            elseif persona_neuro then
              love.graphics.setColor(shimr, shimg, shimb, row_sa)
            else
              set_col(FRD, row_sa)
            end
            love.graphics.draw(rule, rl_x, hby)
          else
            for i = 0, segs - 1 do
              local aa = (0.34 - i * 0.09) * row_sa
              if persona_evil then
                set_col(ACC, aa)
              elseif persona_neuro then
                love.graphics.setColor(shimr, shimg, shimb, aa)
              else
                set_col(FRD, aa)
              end
              love.graphics.rectangle("fill", rl_x + i * segw, hby, math.ceil(segw), 1)
            end
          end
        end
        love.graphics.setFont(lp_font)
        lcy = lcy + lp_hdr_line_h
      else
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        love.graphics.setFont(lp_small_font)
        local sf = lp_small_font
        set_col(col, 0.20 * row_sa)
        love.graphics.rectangle("fill", lx + lp_pad_x + indent - 4, lcy, l_accw, lp_small_line_h - 2)
        draw_colored_desc(trunc(txt, lp_content_w - indent, sf), lx + lp_pad_x + indent, lcy, 0.88 * row_sa, sf)
        love.graphics.setFont(lp_font)
        lcy = lcy + lp_small_line_h + 2
      end
      love.graphics.pop()
    end
    love.graphics.setFont(font)

    if lp_pushed then love.graphics.pop() end
    end  -- lp_on_screen; the occupancy below is published either way

    local pushed_out = (S.lp_slide_target or 0) > 0
    if not pushed_out and not leaving then
      if shop_side == "left" then
        ctx.occ_left = lp_x_target + lp_w_total
      else
        ctx.occ_right = lp_x_target
      end
    end
  end
end

return { draw = draw_shop_panel, PANEL_BASE_W = 380 }
