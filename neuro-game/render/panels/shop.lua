local H = require "render.hud_shared"
local Prims, S, Motion = H.Prims, H.S, H.Motion
local set_col, shadow_text = H.set_col, H.shadow_text
local tracked_width, caps_label = H.tracked_width, H.caps_label
local draw_card_mini = H.draw_card_mini
local card_edition_tag, draw_animated_edition = H.card_edition_tag, H.draw_animated_edition
local SHOP_SLIDE_IN_PX = H.SHOP_SLIDE_IN_PX
local buy_flare01 = H.buy_flare01
local Rows = require "hud.rows"

-- Reused per-frame so the shop draw path doesn't allocate a metrics table + row_h closure
-- every frame. Single-threaded; all fields are rewritten at draw entry before use.
local _lp_metrics = { carousel_pad = 0 }
local function lp_row_h(r) return Rows.height(r, _lp_metrics) end

local function draw_shop_panel(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local pg, bg, ACC, FR, FRD, DIM, WHITE, GOLD = th.pg, th.bg, th.ACC, th.FR, th.FRD, th.DIM, th.WHITE, th.GOLD
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local pk, font, lfont, lfont_small = th.pk, th.font, th.lfont, th.lfont_small
  local ln, lp_sh, sh, U, GUT, ACCENT_W, TRACK = me.ln, me.lp_sh, me.sh, me.U, me.GUT, me.ACCENT_W, me.TRACK
  local p_y, _content_w, _line_h, _small_line_h, card_line_h, sep_h = me.p_y, me.content_w, me.line_h, me.small_line_h, me.card_line_h, me.sep_h
  local shop_rows = da.shop_rows
  local trunc, wrapped_lines, draw_colored_desc = dr.trunc, dr.wrapped_lines, dr.draw_colored_desc
  local shop_visible = #shop_rows > 0
  if shop_visible and not S.shop_last_visible then S.shop_appear_t = now end
  S.shop_last_visible = shop_visible

  if shop_visible then
    local lp_w = ln(380)
    local lp_x = 8
    local lp_y = p_y
    local lp_pad_x = ln(GUT)
    local l_U = ln(U)
    local l_accw = ln(ACCENT_W)
    local lp_content_w = lp_w - lp_pad_x * 2

    local shop_in = Motion.anim01(now - S.shop_appear_t, Motion.dur(Motion.MED))
    local sa = shop_in

    local l_text_h = lfont:getHeight()
    local l_small_text_h = lfont_small and lfont_small:getHeight() or l_text_h
    local lp_small_font = lfont_small
    local lp_font, lp_text_h = lfont, l_text_h
    local lp_line_h, lp_small_line_h = l_text_h + ln(4), l_small_text_h + ln(2)
    local lp_card_line_h, lp_sep_h = ln(card_line_h), ln(sep_h)

    local lp_metrics = _lp_metrics
    lp_metrics.line_h, lp_metrics.small_line_h, lp_metrics.card_line_h = lp_line_h, lp_small_line_h, lp_card_line_h
    lp_metrics.sep_h, lp_metrics.content_w = lp_sep_h, lp_content_w
    lp_metrics.small_font, lp_metrics.wrap = lp_small_font, wrapped_lines
    local lp_data_h = ln(8)
    for _, r in ipairs(shop_rows) do lp_data_h = lp_data_h + lp_row_h(r) end
    local lp_title_h = ln(44)
    local lp_total_h = lp_title_h + lp_data_h
    local lp_avail_h = sh - lp_y - 10
    local lp_pref_h = math.min(lp_avail_h, math.floor(sh * 0.72))
    if S.lp_compact and lp_total_h < lp_pref_h - 24 then S.lp_compact = false end
    if lp_total_h > lp_pref_h then S.lp_compact = true end
    local lp_cols = 1
    if S.lp_compact then
      lp_font, lp_text_h = lp_small_font, l_small_text_h
      lp_line_h = l_small_text_h + ln(3)
      lp_small_line_h = l_small_text_h + ln(1)
      lp_card_line_h = ln(26)
      lp_sep_h = ln(6)
      lp_metrics.line_h, lp_metrics.small_line_h = lp_line_h, lp_small_line_h
      lp_metrics.card_line_h, lp_metrics.sep_h = lp_card_line_h, lp_sep_h
      lp_data_h = ln(8)
      for _, r in ipairs(shop_rows) do lp_data_h = lp_data_h + lp_row_h(r) end
      lp_total_h = lp_title_h + lp_data_h
      if lp_total_h > lp_avail_h then
        local avail_data = math.max(lp_card_line_h, lp_avail_h - lp_title_h - ln(8))
        local col_h, max_col = 0, 0
        for _, r in ipairs(shop_rows) do
          local hh = lp_row_h(r)
          if col_h > 0 and col_h + hh > avail_data then
            lp_cols = lp_cols + 1
            col_h = 0
          end
          col_h = col_h + hh
          if col_h > max_col then max_col = col_h end
        end
        if lp_cols > 3 then lp_cols = 3 end
        lp_total_h = lp_title_h + ln(8) + math.min(max_col, avail_data)
        if lp_total_h > lp_avail_h then lp_total_h = lp_avail_h end
      end
    end
    local lp_w_total = lp_w * lp_cols

    local lp_dx = -math.floor((lp_w_total + 20) * S.left_panel_slide_frac + (1 - shop_in) * SHOP_SLIDE_IN_PX + 0.5)
    local lp_pushed = S.left_panel_slide_frac > 0 or shop_in < 1
    if lp_pushed then
      love.graphics.push()
      love.graphics.translate(lp_dx, 0)
    end

    local lprad = H.persona_frame(th, mo, lp_x, lp_y, lp_w_total, lp_total_h, ln(1),
      { a = sa, sh = lp_sh, rad = ln(9), title_h = lp_title_h, skip_body = true, glow = true })
    local ev_flare = persona_evil and buy_flare01(now) or 0
    if persona_evil then
      set_col(pg, 0.014 * sa)
      love.graphics.rectangle("fill", lp_x + 1, lp_y + lp_title_h, lp_w_total - 2, lp_total_h - lp_title_h - 1)
      Prims.embers(lp_x + ln(10), lp_y + lp_title_h, lp_w_total - ln(20), lp_total_h - lp_title_h - ln(6),
        ln(1), now, Motion.reduced, 0.5 * sa, 4)
      H.evil_frame(lp_x, lp_y, lp_w_total, lp_total_h, ln(1), lp_title_h, GOLD, pg, bg, pulse, now, sa, ev_flare, 0.5)
      Prims.ash_motes(lp_x + math.floor(lp_w_total * 0.52), lp_y + ln(4), math.floor(lp_w_total * 0.34), lp_title_h - ln(8), ln(1), now, Motion.reduced, 0.7 * sa, 5)
      Prims.candle_finial(lp_x + math.floor(lp_w_total / 2), lp_y + lp_title_h - ln(3), ln(1), GOLD, sa, now, Motion.reduced, ev_flare)
    elseif persona_neuro then
      Prims.counter_glow(lp_x, lp_y, lp_w_total, lp_total_h, pg, sa, 0.5, lprad)
      Prims.awning(lp_x + lprad, lp_y + 1, lp_w_total - lprad * 2, ln(1), ACC, pg, sa)
      Prims.draw_bow_mini(lp_x + math.floor(lp_w_total / 2), lp_y + ln(3), ln(1) * 0.9, ACC, 0.9 * sa, pg)
      if not Motion.reduced then
        for si = 1, 3 do
          local sxr = 0.5 + 0.5 * math.sin(si * 78.233 + 0.4)
          local tw2 = Prims.twinkle01(now, si)
          local sx3 = lp_x + math.floor(lp_w_total * 0.5) + sxr * (lp_w_total * 0.34)
          local sy3 = lp_y + math.floor(lp_title_h * 0.55) + (0.5 + 0.5 * math.sin(si * 39.425 + 1.7)) * ln(8)
          Prims.draw_sparkle(sx3, sy3, ln(2) + tw2 * ln(2), (si % 2 == 0) and pg or ACC, 0.45 * tw2 * sa)
        end
      end
    end

    love.graphics.setFont(lfont)
    local sh_tx = lp_x + lp_pad_x
    local sh_ty = lp_y + math.floor((lp_title_h - l_text_h) / 2)
    local sh_nw = tracked_width("SHOP", TRACK, lfont)
    if persona_evil then
      love.graphics.setColor(0, 0, 0, 0.32 * sa)
      love.graphics.rectangle("fill", sh_tx - ln(6), sh_ty - ln(3), sh_nw + ln(12), l_text_h + ln(6))
    end
    caps_label("SHOP", sh_tx, sh_ty, ACC, 0.97 * sa, TRACK, lfont, 0.30 * sa)
    if persona_neuro then
      love.graphics.setColor(shimr, shimg, shimb, 0.55 * sa)
      love.graphics.rectangle("fill", sh_tx, sh_ty + l_text_h + ln(1), sh_nw, 1)
      Prims.draw_heart(sh_tx + sh_nw + ln(9), sh_ty + math.floor(l_text_h / 2), ln(3), pg, 0.85 * sa)
    end

    do
      local money = (G.GAME and G.GAME.dollars) or 0
      local rr = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost
      if persona_evil then
        if S.sz_money_last ~= nil and money ~= S.sz_money_last then S.sz_money_at = now end
        S.sz_money_last = money
      end
      local pf = lp_small_font or lfont
      local pfh = pf:getHeight()
      local iy = lp_y + math.floor((lp_title_h - pfh) / 2)
      love.graphics.setFont(pf)
      local m_txt = "$" .. tostring(money)
      local m_w = pf:getWidth(m_txt)
      local m_x = lp_x + lp_w_total - lp_pad_x - m_w
      local r_txt, r_w
      if type(rr) == "number" then
        r_txt = "RR $" .. tostring(rr)
        r_w = pf:getWidth(r_txt)
      end
      if persona_evil then
        local ext = r_w and (r_w + ln(21)) or 0
        love.graphics.setColor(0, 0, 0, 0.32 * sa)
        love.graphics.rectangle("fill", m_x - ln(5) - ext, iy - ln(2), m_w + ln(10) + ext, pfh + ln(4))
      end
      love.graphics.setColor(0, 0, 0, 0.40 * sa)
      love.graphics.print(m_txt, m_x + 1, iy + 1)
      if persona_neuro or persona_evil then
        love.graphics.setColor(shimr, shimg, shimb, 0.97 * sa)
      else
        set_col(GOLD, 0.97 * sa)
      end
      love.graphics.print(m_txt, m_x, iy)
      if r_txt then
        local r_x = m_x - ln(persona_evil and 14 or 10) - r_w
        shadow_text(r_txt, r_x, iy, ACC, 0.72 * sa, 0.30 * sa)
        local r_cy = iy + math.floor(pfh / 2)
        if persona_evil then
          if S.rr_last ~= nil and rr ~= S.rr_last then S.rr_stab_at = now end
          S.rr_last = rr
          local stab = 0
          if S.rr_stab_at and not Motion.reduced then
            local st2 = (now - S.rr_stab_at) / 0.25
            if st2 >= 0 and st2 < 1 then stab = math.floor(math.sin(math.pi * st2) * 3 + 0.5) end
          end
          Prims.draw_knife(r_x - ln(7), r_cy + stab, ln(1), GOLD, WHITE, 0.9 * sa, true)
        elseif persona_neuro then
          Prims.draw_sparkle(r_x - ln(7), r_cy, ln(2), pg, 0.7 * sa)
        end
      end
      love.graphics.setFont(lfont)
    end

    local lcy = lp_y + lp_title_h
    if persona_evil then
      Prims.evil_divider(lp_x, lcy, lp_w_total, ln(1), ACC, GOLD, sa, pulse, nil, false,
        math.min(1, (now - S.shop_appear_t) / 0.6))
    elseif persona_neuro then
      Prims.tag_string(lp_x, lcy - 1, lp_w_total, ln(1), shimr, shimg, shimb, sa)
      Prims.draw_heart(lp_x + ln(8), lcy - 1, ln(3), pg, 0.55 * sa)
      Prims.draw_heart(lp_x + lp_w_total - ln(8), lcy - 1, ln(3), pg, 0.55 * sa)
    else
      set_col(ACC, (0.85 + 0.10 * pulse) * sa)
      love.graphics.rectangle("fill", lp_x, lcy - 2, lp_w_total, 2)
    end
    for c = 2, lp_cols do
      set_col(FRD, 0.90 * sa)
      love.graphics.rectangle("fill", lp_x + (c - 1) * lp_w, lcy, 1, lp_total_h - lp_title_h)
    end
    lcy = lcy + l_U + 2

    local lp_clip_y = lp_y + lp_total_h
    local lp_col = 1
    local lx = lp_x
    local lp_rows_y0 = lcy
    love.graphics.setFont(lp_font)
    for _, r in ipairs(shop_rows) do
      local cur_h = lp_row_h(r)
      if lcy + cur_h > lp_clip_y then
        if lp_col < lp_cols then
          lp_col = lp_col + 1
          lx = lx + lp_w
          lcy = lp_rows_y0
        else
          break
        end
      end

      if r.kind == "sep" then
        lcy = lcy + l_U
        local sepx1 = lx + lp_pad_x
        local sepx2 = lx + lp_w - lp_pad_x
        if persona_evil then
          Prims.evil_divider(sepx1, lcy + 1, sepx2 - sepx1, ln(1), ACC, GOLD, 0.7 * sa, pulse, 1, true)
          Prims.draw_glint(sepx1 + ln(2), lcy, ln(2), ACC, 0.7 * sa, GOLD, true)
          Prims.draw_glint(sepx2 - ln(2), lcy, ln(2), ACC, 0.7 * sa, GOLD, true)
        elseif persona_neuro then
          Prims.tag_string(sepx1, lcy, sepx2 - sepx1, ln(1), shimr, shimg, shimb, sa)
          Prims.draw_heart(sepx1 + ln(2), lcy, ln(2), pg, 0.55 * sa)
          Prims.draw_heart(sepx2 - ln(2), lcy, ln(2), pg, 0.55 * sa)
        else
          set_col(FRD, 0.90 * sa)
          love.graphics.setLineWidth(1)
          love.graphics.line(sepx1, lcy, sepx2, lcy)
        end
        lcy = lcy + lp_sep_h - l_U
      elseif r.kind == "descwrap" then
        local txt = r.text or ""
        local indent = r.indent or 0
        set_col(FR, 0.60 * sa)
        love.graphics.rectangle("fill", lx + lp_pad_x + indent - ln(6), lcy + 1, l_accw, cur_h - 3)
        love.graphics.setFont(lp_small_font)
        local sf = lp_small_font
        local lines = wrapped_lines(txt, math.max(20, lp_content_w - indent), sf)
        local ly = lcy
        for i = 1, #lines do
          draw_colored_desc(lines[i], lx + lp_pad_x + indent, ly, 0.92 * sa, sf)
          ly = ly + lp_small_line_h
        end
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
          set_col(GOLD, 0.045 * sa)
          love.graphics.rectangle("fill", lx + 2, lcy, lp_w - 4, lp_card_line_h - 1)
        elseif not afford and persona_evil then
          love.graphics.setColor(0, 0, 0, 0.16 * sa)
          love.graphics.rectangle("fill", lx + 2, lcy, lp_w - 4, lp_card_line_h - 1)
        end

        local sprite_h = lp_card_line_h - ln(4)
        local sprite_x = row_x
        local sprite_y = lcy + math.floor((lp_card_line_h - sprite_h) / 2)
        local est_w = sprite_h * 0.75
        local mini_w = draw_card_mini(card_obj, sprite_x, sprite_y, sprite_h, (afford and 1 or 0.6) * sa)
        love.graphics.setLineWidth(1)
        if persona_neuro then
          love.graphics.setColor(shimr, shimg, shimb, (afford and 0.40 or 0.18) * sa)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2)
        elseif persona_evil then
          Prims.photo_corners(sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, GOLD, (afford and 0.60 or 0.25) * sa, ln(3))
        else
          set_col(GOLD, (afford and 0.35 or 0.16) * sa)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2)
        end
        local name_x = sprite_x + (mini_w > 0 and mini_w or est_w) + ln(8)

        local price_txt = "$" .. tostring(cost)
        local pfont2 = lp_small_font or lp_font
        love.graphics.setFont(pfont2)
        local pw2 = pfont2:getWidth(price_txt)
        local pfh2 = pfont2:getHeight()
        local pty = lcy + math.floor((lp_card_line_h - pfh2) / 2)
        local ptx = row_x2 - pw2
        local price_left
        if persona_neuro then
          local tx0 = ptx - ln(4)
          local ty0 = pty - ln(1)
          local tw3 = pw2 + ln(8)
          local th3 = pfh2 + ln(2)
          local tmy = ty0 + math.floor(th3 / 2)
          love.graphics.setColor(shimr, shimg, shimb, (afford and 0.55 or 0.25) * sa)
          love.graphics.rectangle("line", tx0, ty0, tw3, th3, ln(2), ln(2))
          love.graphics.line(tx0 - ln(4), tmy, tx0, tmy)
          love.graphics.circle("fill", tx0 - ln(4), tmy, 1.2)
          price_left = tx0 - ln(6)
        elseif persona_evil then
          local seal_cx = ptx - ln(8)
          local pl_x = seal_cx - ln(5)
          local pl_h = pfh2 + ln(4)
          Prims.plate_label(pl_x, pty - ln(2), row_x2 - pl_x + ln(1), pl_h, GOLD, (afford and 0.9 or 0.5) * sa, false, 0.42)
          Prims.wax_seal(seal_cx, lcy + math.floor(lp_card_line_h / 2), ln(4), ln(1), GOLD,
            (afford and 0.95 or 0.40) * sa, pulse, afford)
          if afford and S.sz_money_at and not Motion.reduced then
            local mk3 = 1 - (now - S.sz_money_at) / 0.35
            if mk3 > 0 then
              Prims.draw_glint(seal_cx, lcy + math.floor(lp_card_line_h / 2), ln(2), ACC, 0.9 * mk3 * sa, GOLD, true)
            end
          end
          price_left = pl_x - ln(3)
        else
          price_left = ptx - ln(4)
        end
        love.graphics.setColor(0, 0, 0, 0.35 * sa)
        love.graphics.print(price_txt, ptx + 1, pty + 1)
        if afford then
          if persona_neuro then
            love.graphics.setColor(1, 1, 1, 0.96 * sa)
          else
            set_col(GOLD, 0.96 * sa)
          end
        else
          set_col(DIM, 0.70 * sa)
        end
        love.graphics.print(price_txt, ptx, pty)
        love.graphics.setFont(lp_font)

        local name_max = price_left - ln(4) - name_x
        local lp_txt = trunc(name, name_max, lp_font)
        shadow_text(lp_txt, name_x, row_cy, name_col, (afford and 0.98 or 0.72) * sa, 0.42 * sa)
        local lp_ed_tag = card_edition_tag(card_obj)
        if lp_ed_tag ~= "" then
          draw_animated_edition(lp_ed_tag, name_x + lp_font:getWidth(lp_txt), row_cy, sa, lp_font, now, pk)
        end
        lcy = lcy + lp_card_line_h
      elseif r.kind == "header" then
        local col = r.color
        local htxt = trunc(r.text or "", lp_content_w - 10, lp_font)
        set_col(col, 0.07 * sa)
        love.graphics.rectangle("fill", lx + 2, lcy - 1, lp_w - 4, lp_line_h + 2)
        local htx = lx + lp_pad_x
        love.graphics.setColor(0, 0, 0, 0.40 * sa)
        love.graphics.print(htxt, htx + 1, lcy + 2)
        love.graphics.setColor(1, 1, 1, 0.96 * sa)
        love.graphics.print(htxt, htx, lcy + 1)
        local hw = lp_font:getWidth(htxt)
        local hbx = htx + hw + ln(7)
        local hby = lcy + 1 + math.floor(lp_text_h / 2)
        if persona_evil then
          Prims.wax_seal(hbx, hby, ln(3), ln(1), GOLD, sa, pulse)
        elseif persona_neuro then
          Prims.draw_sparkle(hbx, hby, ln(3), pg, 0.9 * sa)
        end
        local rl_x = hbx + ln(6)
        local rl_x2 = lx + lp_w - lp_pad_x
        if rl_x2 > rl_x + ln(8) then
          local segs = 3
          local segw = (rl_x2 - rl_x) / segs
          for i = 0, segs - 1 do
            local aa = (0.34 - i * 0.09) * sa
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
        lcy = lcy + lp_line_h
      else -- note
        local col = r.color
        local txt = r.text or ""
        local indent = r.indent or 0
        love.graphics.setFont(lp_small_font)
        local sf = lp_small_font
        set_col(col, 0.20 * sa)
        love.graphics.rectangle("fill", lx + lp_pad_x + indent - 4, lcy, l_accw, lp_small_line_h - 2)
        love.graphics.setColor(0, 0, 0, 0.25 * sa)
        love.graphics.print(trunc(txt, lp_content_w - indent, sf), lx + lp_pad_x + indent + 1, lcy + 1)
        set_col(col, 0.82 * sa)
        love.graphics.print(trunc(txt, lp_content_w - indent, sf), lx + lp_pad_x + indent, lcy)
        love.graphics.setFont(lp_font)
        lcy = lcy + lp_small_line_h + 2
      end
    end
    love.graphics.setFont(font)

    if lp_pushed then love.graphics.pop() end
  end
end

return { draw = draw_shop_panel }
