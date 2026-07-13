local H = require("render.hud_shared")
local Prims, S, Motion = H.Prims, H.S, H.Motion
local round = Prims.round
local clamp, clamp01 = Prims.clamp, Prims.clamp01
local set_col, shadow_text = H.set_col, H.shadow_text
local caps_label, tracked_width = H.caps_label, H.tracked_width
local draw_card_mini = H.draw_card_mini
local PACK_CARD_APPEAR_D = H.PACK_CARD_APPEAR_D

local function by_pack_index(a, b) return a.index < b.index end

local _prev_pool, _disp_pool = {}, {}
local function pooled(pool, n)
  local t = pool[n]
  if not t then t = {}; pool[n] = t end
  return t
end

local function draw_pack_panel(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local pg, ACC, FRD, ORANGE, WHITE, CYAN, GOLD = th.pg, th.ACC, th.FRD, th.ORANGE, th.WHITE, th.CYAN, th.GOLD
  local bg = th.bg
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font, panel_font_small = th.font, th.panel_font_small
  local rn, sw, U, GUT, TRACK_SM, line_h, small_line_h, text_h = me.rn, me.sw, me.U, me.GUT, me.TRACK_SM, me.line_h, me.small_line_h, me.text_h
  local pack_rows, sn = da.pack_rows, da.sn
  local trunc, wrapped_lines, draw_colored_desc = dr.trunc, dr.wrapped_lines, dr.draw_colored_desc
  local pack_has_cards = pack_rows.cards and #pack_rows.cards > 0
  local is_pack_state = sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED"
  local PACK_LEAVE_DUR = 0.40

  if is_pack_state and S.pack_last_sn ~= sn then
    S.pack_appear_t = 0
    S.pack_picked = {}
    S.pack_prev_cards = {}
    S.pack_card_indices = {}
    S.pack_initial_count = 0
    S.pack_leave_t = nil
    S.pack_leave_snap = nil
  elseif not is_pack_state and S.pack_last_sn ~= nil then
    S.pack_leave_t = now
    S.pack_prev_cards = {}
    S.pack_card_indices = {}
  end
  S.pack_last_sn = is_pack_state and sn or nil

  local PICK_FADE_DUR = 1.2
  local PICK_FADE_FAST = 1.05

  -- computed BEFORE pick-detection so a card taken during a highlight locks in the fast fade
  local any_highlighted = false
  if pack_has_cards then
    for _, cd in ipairs(pack_rows.cards) do
      if G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card] then
        any_highlighted = true
        break
      end
    end
  end

  if pack_has_cards then
    local cur_set = {}
    for _, cd in ipairs(pack_rows.cards) do cur_set[cd.card] = true end
    for _, prev_c in ipairs(S.pack_prev_cards) do
      if not cur_set[prev_c.card] and not S.pack_picked[prev_c.card] then
        S.pack_picked[prev_c.card] = {
          at = now, name = prev_c.name, desc = prev_c.desc,
          rc = prev_c.rc, index = prev_c.index,
          fade_dur = any_highlighted and PICK_FADE_FAST or PICK_FADE_DUR,
        }
      end
    end
    local prev = S.pack_prev_cards
    if not prev then prev = {}; S.pack_prev_cards = prev end
    local pn = 0
    for _, cd in ipairs(pack_rows.cards) do
      pn = pn + 1
      local t = pooled(_prev_pool, pn)
      t.card, t.name, t.desc, t.rc, t.index = cd.card, cd.name, cd.desc, cd.rc, cd.index
      prev[pn] = t
    end
    for i = #prev, pn + 1, -1 do prev[i] = nil end
  end

  for k, v in pairs(S.pack_picked) do
    if now - v.at > (v.fade_dur or PICK_FADE_DUR) then S.pack_picked[k] = nil end
  end

  local leaving = (not is_pack_state) and S.pack_leave_t and (now - S.pack_leave_t) < PACK_LEAVE_DUR
  local leave01 = 1
  if leaving then leave01 = 1 - Motion.anim01(now - S.pack_leave_t, PACK_LEAVE_DUR) end

  if (is_pack_state and (pack_has_cards or next(S.pack_picked))) or leaving then
    local pk_pad = 10
    local slot_gap = 6
    local slot_h = 190
    local small_f = panel_font_small or font

    local display_cards = S.pack_disp or {}
    S.pack_disp = display_cards
    local dn = 0
    if pack_has_cards then
      for _, cd in ipairs(pack_rows.cards) do
        local is_hl = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card]
        dn = dn + 1
        local t = pooled(_disp_pool, dn)
        t.card, t.name, t.desc, t.rc, t.index = cd.card, cd.name, cd.desc, cd.rc, cd.index
        t.state, t.alpha, t.pick_elapsed = is_hl and "highlighted" or "normal", 1.0, nil
        display_cards[dn] = t
      end
    end
    for _, pv in pairs(S.pack_picked) do
      local elapsed = now - pv.at
      local fade = math.max(0, 1 - elapsed / (pv.fade_dur or PICK_FADE_DUR))
      if fade > 0 then
        dn = dn + 1
        local t = pooled(_disp_pool, dn)
        t.card, t.name, t.desc, t.rc, t.index = nil, pv.name, pv.desc, pv.rc, pv.index
        t.state, t.alpha, t.pick_elapsed = "picked", fade, elapsed
        display_cards[dn] = t
      end
    end
    if leaving then
      for _, ls in ipairs(S.pack_leave_snap or {}) do
        dn = dn + 1
        local t = pooled(_disp_pool, dn)
        t.card, t.name, t.desc, t.rc, t.index = nil, ls.name, nil, ls.rc, ls.index
        t.state, t.alpha, t.pick_elapsed = "normal", 1.0, nil
        display_cards[dn] = t
      end
    end
    for i = #display_cards, dn + 1, -1 do display_cards[i] = nil end
    table.sort(display_cards, by_pack_index)

    if not leaving and S.pack_initial_count == 0 and #display_cards > 0 then
      S.pack_initial_count = #display_cards
      S.pack_appear_t = now
    end
    local n_cards = math.max(#display_cards, leaving and (S.pack_leave_n or 0) or S.pack_initial_count)

    if not leaving then
      S.pack_leave_snap = {}
      for _, dc in ipairs(display_cards) do
        if dc.state ~= "picked" then
          S.pack_leave_snap[#S.pack_leave_snap + 1] = { name = dc.name, rc = dc.rc, index = dc.index }
        end
      end
      S.pack_leave_n = n_cards
    end
    local pk_w = clamp(n_cards * 155 + 20, 500, sw - 40)
    local pk_x = math.floor((sw - pk_w) / 2)
    local pk_content_w = pk_w - pk_pad * 2
    local slot_w = (n_cards > 0) and math.max(1, math.floor((pk_content_w - (n_cards - 1) * slot_gap) / n_cards)) or pk_content_w
    local title_h2 = line_h + 6
    local pk_total_h = title_h2 + slot_h + 10

    local pk_in = Motion.anim01(now - S.pack_appear_t, Motion.dur(Motion.MED)) * leave01

    local pk_base_top = ctx.center_top_y
    if leaving then ctx.center_top_y = pk_base_top + math.floor((1 - leave01) * 16) end

    local pk_rad = H.persona_frame(th, mo, pk_x, ctx.center_top_y, pk_w, pk_total_h, rn(1),
      { a = pk_in, rad = 9, title_h = title_h2, skip_body = true })
    if persona_evil then
      local pft = now - S.pack_appear_t
      local flare = clamp01(pft / 0.45)
      local cy0 = ctx.center_top_y
      H.evil_frame(pk_x, cy0, pk_w, pk_total_h, rn(1), title_h2, GOLD, pg, bg, pulse, now, pk_in, flare, 0.5)
      Prims.embers(pk_x + math.floor(pk_w / 2), cy0 + title_h2, math.floor(pk_w * 0.82), slot_h, rn(1),
        now, Motion.reduced, 0.55 * pk_in)
      if not Motion.reduced and flare < 1 then
        Prims.ember_bloom(pk_x + math.floor(pk_w / 2), cy0 + title_h2, rn(30), rn(1), flare, GOLD, pk_in, false)
      end
    elseif persona_neuro then
      Prims.draw_bow(pk_x + pk_w - rn(20), ctx.center_top_y + rn(5), rn(2), ACC, 0.95 * pk_in, pg)
      if not Motion.reduced then
        for si = 1, 3 do
          local sxr = 0.5 + 0.5 * math.sin(si * 78.233 + 0.9)
          local tw3 = Prims.twinkle01(now, si)
          Prims.draw_sparkle(pk_x + pk_w * 0.40 + sxr * pk_w * 0.35,
            ctx.center_top_y + rn(6) + (0.5 + 0.5 * math.sin(si * 39.425)) * rn(9),
            rn(2) + tw3 * rn(2), (si % 2 == 0) and pg or ACC, 0.5 * tw3 * pk_in)
        end
      end
    end

    local pk_title_color = (pack_rows.pg or ACC)
    local pk_title_ty = ctx.center_top_y + math.floor((title_h2 - text_h) / 2)
    local pk_title_tx = pk_x + GUT
    if persona_evil then
      Prims.evil_divider(pk_x, ctx.center_top_y + title_h2 - 1, pk_w, rn(1), pk_title_color, GOLD, pk_in, pulse,
        nil, nil, pk_in)
    elseif persona_neuro then
      Prims.tag_string(pk_x + pk_rad, ctx.center_top_y + title_h2 - 2, pk_w - pk_rad * 2, 1, shimr, shimg, shimb, pk_in)
      Prims.draw_heart(pk_x + rn(8), ctx.center_top_y + title_h2 - 2, rn(3), pg, 0.55 * pk_in)
      Prims.draw_heart(pk_x + pk_w - rn(8), ctx.center_top_y + title_h2 - 2, rn(3), pg, 0.55 * pk_in)
    else
      set_col(pk_title_color, (0.85 + 0.10 * pulse) * pk_in)
      love.graphics.rectangle("fill", pk_x, ctx.center_top_y + title_h2 - 2, pk_w, 2)
    end
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.30 * pk_in)
    love.graphics.print(trunc(pack_rows.title or "Pack", pk_content_w - 22), pk_title_tx + 1, pk_title_ty + 1)
    set_col(pk_title_color, 1.0 * pk_in)
    love.graphics.print(trunc(pack_rows.title or "Pack", pk_content_w - 22), pk_title_tx, pk_title_ty)

    local function draw_pack_slot(dc, slot_x, sy_slot, ca, appear_ef, scan)
      local st = dc.state
      local u = rn(2)
      local pe = dc.pick_elapsed or 0
      local mcx = slot_x + math.floor(slot_w / 2)
      local mcy = sy_slot + math.floor(slot_h / 2)
      if st == "normal" and any_highlighted then ca = ca * 0.5 end

      if st == "picked" then
        if persona_evil then
          Prims.niche(slot_x, sy_slot, slot_w, slot_h, u, GOLD, pg, pulse, 0.5 * ca, true)
        elseif persona_neuro then
          Prims.card_sleeve(slot_x, sy_slot, slot_w, slot_h, u, ACC, pg, shimr, shimg, shimb, ca)
          love.graphics.setColor(shimr, shimg, shimb, 0.16 * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, rn(6), rn(6))
        else
          set_col(GOLD, 0.18 * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h)
          set_col(GOLD, (0.70 + 0.12 * scan) * ca)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", slot_x, sy_slot, slot_w, slot_h)
        end

      elseif st == "highlighted" then
        local hr, hg2, hb3
        if persona_evil then hr, hg2, hb3 = ACC[1], ACC[2], ACC[3]
        elseif persona_neuro then hr, hg2, hb3 = shimr, shimg, shimb
        else hr, hg2, hb3 = CYAN[1], CYAN[2], CYAN[3] end

        if persona_evil then
          Prims.niche(slot_x, sy_slot, slot_w, slot_h, u, GOLD, pg, 0.5 + 0.5 * pulse, ca, true)
          love.graphics.setColor(hr, hg2, hb3, (0.10 + 0.06 * scan) * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h)
          set_col(GOLD, (0.80 + 0.15 * scan) * ca)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", slot_x, sy_slot, slot_w, slot_h)
          Prims.photo_corners(slot_x - 1, sy_slot - 1, slot_w + 2, slot_h + 2, GOLD, (0.85 + 0.15 * scan) * ca, rn(9))
        elseif persona_neuro then
          Prims.card_sleeve(slot_x, sy_slot, slot_w, slot_h, u, ACC, pg, shimr, shimg, shimb, ca)
          love.graphics.setColor(hr, hg2, hb3, (0.12 + 0.06 * scan) * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, rn(6), rn(6))
          love.graphics.setColor(hr, hg2, hb3, (0.65 + 0.20 * scan) * ca)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", slot_x, sy_slot, slot_w, slot_h, rn(6), rn(6))
        else
          love.graphics.setColor(hr, hg2, hb3, (0.12 + 0.05 * scan) * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h)
          love.graphics.setColor(hr, hg2, hb3, (0.75 + 0.15 * scan) * ca)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", slot_x, sy_slot, slot_w, slot_h)
          set_col(WHITE, (0.18 + 0.10 * scan) * ca)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", slot_x + 2, sy_slot + 2, slot_w - 4, slot_h - 4)
          Prims.photo_corners(slot_x, sy_slot, slot_w, slot_h, {hr, hg2, hb3}, (0.80 + 0.15 * scan) * ca, 11)
        end

      else
        if persona_evil then
          Prims.niche(slot_x, sy_slot, slot_w, slot_h, u, GOLD, pg, pulse, ca, true)
        elseif persona_neuro then
          Prims.card_sleeve(slot_x, sy_slot, slot_w, slot_h, u, ACC, pg, shimr, shimg, shimb, ca)
        else
          set_col(FRD, 0.45 * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, rn(3), rn(3))
        end
        local rr = persona_evil and 0 or rn(3)
        set_col(dc.rc, (0.30 + 0.10 * pulse) * ca)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", slot_x, sy_slot, slot_w, slot_h, rr, rr)
      end

      if appear_ef < 1 and not Motion.reduced then
        if persona_evil then
          Prims.ember_bloom(mcx, sy_slot + slot_h - rn(6), slot_w * 0.30, u, appear_ef, GOLD, ca, false)
        elseif persona_neuro then
          Prims.draw_sparkle(slot_x + slot_w - 6, sy_slot + 6, 3 + (1 - appear_ef) * 3, pg, (1 - appear_ef) * 0.9)
        end
      end

      if dc.card then
        local sprite_w2 = math.min(slot_w - 16, 90)
        local sprite_h2 = math.floor(sprite_w2 / 0.747)
        local sprite_x2 = slot_x + math.floor((slot_w - sprite_w2) / 2)
        local sprite_y2 = sy_slot + 6

        love.graphics.setColor(0, 0, 0, 0.30 * ca)
        love.graphics.ellipse("fill", sprite_x2 + sprite_w2 / 2, sprite_y2 + sprite_h2 + 3, sprite_w2 * 0.48, 3)
        love.graphics.setColor(0, 0, 0, 0.55 * ca)
        love.graphics.rectangle("fill", sprite_x2 - 1, sprite_y2 - 1, sprite_w2 + 2, sprite_h2 + 2)
        local sb_col = dc.rc
        if st == "picked" then sb_col = persona_neuro and {shimr, shimg, shimb} or GOLD
        elseif st == "highlighted" then sb_col = persona_evil and GOLD or (persona_neuro and {shimr, shimg, shimb} or CYAN) end
        set_col(sb_col, (0.45 + 0.15 * (st == "normal" and pulse or scan)) * ca)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", sprite_x2 - 1, sprite_y2 - 1, sprite_w2 + 2, sprite_h2 + 2)
        if persona_evil then
          Prims.photo_corners(sprite_x2 - 2, sprite_y2 - 2, sprite_w2 + 4, sprite_h2 + 4, GOLD, 0.60 * ca, rn(4))
        elseif persona_neuro and (st == "picked" or st == "highlighted") then
          love.graphics.setColor(shimr, shimg, shimb, 0.45 * ca)
          love.graphics.rectangle("line", sprite_x2 - 3, sprite_y2 - 3, sprite_w2 + 6, sprite_h2 + 6, 3, 3)
        end

        draw_card_mini(dc.card, sprite_x2, sprite_y2, sprite_h2, ca)
        love.graphics.setColor(1, 1, 1, 0.06 * ca)
        love.graphics.rectangle("fill", sprite_x2, sprite_y2, sprite_w2, math.max(2, sprite_h2 * 0.10))

        if st == "picked" and not Motion.reduced then
          if persona_evil then
            local char = math.min(1, pe / 0.26)
            if char > 0 and char < 1 then
              local ch = math.floor(sprite_h2 * char)
              set_col(ORANGE, (0.7 + 0.3 * pulse) * ca)
              love.graphics.rectangle("fill", sprite_x2, sprite_y2 + sprite_h2 - ch - 2, sprite_w2, 2)
            end
          elseif persona_neuro then
            local fl = math.sin(math.pi * math.min(1, pe / 0.24))
            if fl > 0 then
              love.graphics.setColor(shimr, shimg, shimb, 0.35 * fl * ca)
              love.graphics.rectangle("fill", sprite_x2, sprite_y2, sprite_w2, sprite_h2, 3, 3)
              love.graphics.setColor(1, 1, 1, 0.25 * fl * ca)
              love.graphics.rectangle("fill", sprite_x2, sprite_y2, sprite_w2, math.max(2, sprite_h2 * 0.14))
            end
          end
        end

        local name_y = sprite_y2 + sprite_h2 + 4
        local rc2 = (st == "picked" and GOLD) or (st == "highlighted" and CYAN) or dc.rc
        local name_str = trunc(dc.name, slot_w - 8)
        local name_x = slot_x + math.floor((slot_w - font:getWidth(name_str)) / 2)
        shadow_text(name_str, name_x, name_y, rc2, 0.97 * ca, 0.35 * ca)

        if dc.desc and dc.desc ~= "" then
          if panel_font_small then love.graphics.setFont(panel_font_small) end
          local desc_lines = wrapped_lines(dc.desc, slot_w - 8, small_f)
          local dy = name_y + text_h + 2
          for li = 1, math.min(#desc_lines, 2) do
            draw_colored_desc(desc_lines[li], slot_x + 4, dy, ca, small_f)
            dy = dy + small_line_h
          end
          if panel_font_small then love.graphics.setFont(font) end
        end
      elseif not (persona_evil and st == "picked") then
        local name_str = trunc(dc.name, slot_w - 16)
        local name_x = slot_x + math.floor((slot_w - font:getWidth(name_str)) / 2)
        local name_y = sy_slot + math.floor((slot_h - text_h) / 2)
        shadow_text(name_str, name_x, name_y, GOLD, 0.97 * ca, 0.35 * ca)
      end

      if st == "highlighted" then
        local mk_bob = Motion.reduced and 0 or math.sin(now * 2.2) * 2
        if persona_evil then
          Prims.draw_knife(mcx, sy_slot - rn(9) + mk_bob, rn(1), GOLD, WHITE, (0.85 + 0.15 * scan) * ca, true)
          Prims.draw_glint(slot_x + 4, sy_slot + 4, rn(2), ACC, (0.5 + 0.3 * scan) * ca, GOLD, true)
          Prims.draw_glint(slot_x + slot_w - 4, sy_slot + slot_h - 4, rn(2), ACC, (0.5 + 0.3 * scan) * ca, GOLD, true)
        elseif persona_neuro then
          Prims.draw_bow(mcx, sy_slot - rn(9) + mk_bob, rn(2), ACC, 0.95 * ca, pg)
          Prims.draw_sparkle(slot_x + 4, sy_slot + 4, rn(2), pg, (0.5 + 0.3 * scan) * ca)
          Prims.draw_sparkle(slot_x + slot_w - 4, sy_slot + slot_h - 4, rn(2), pg, (0.5 + 0.3 * scan) * ca)
        else
          local dpy = sy_slot - rn(7) + mk_bob
          set_col(CYAN, (0.85 + 0.15 * scan) * ca)
          love.graphics.polygon("fill", mcx - rn(3), dpy, mcx, dpy - rn(3), mcx + rn(3), dpy, mcx, dpy + rn(3))
        end
      end

      if persona_evil and st == "picked" then
        if not Motion.reduced then
          if pe < 0.35 then
            local veil = (pe < 0.20) and (0.35 * pe / 0.20) or (0.35 * math.max(0, 1 - (pe - 0.20) / 0.15))
            set_col(ACC, veil * ca)
            love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h)
          end
          local brand_p = Prims.smoothstep01((pe - 0.15) / 0.30)
          if brand_p > 0 then
            local ease = 1 - (1 - brand_p) * (1 - brand_p)
            local ring_p = math.min(1, brand_p * 1.6)
            if ring_p < 1 then
              local rr = round(rn(9) * (2.3 - 1.3 * ring_p))
              local ra = (1 - ring_p) * 0.9 * ca
              local bar = math.max(2, round(rr * 0.7))
              set_col(GOLD, ra)
              love.graphics.rectangle("fill", mcx - math.floor(bar / 2), mcy - rr, bar, 1)
              love.graphics.rectangle("fill", mcx - math.floor(bar / 2), mcy + rr - 1, bar, 1)
              love.graphics.rectangle("fill", mcx - rr, mcy - math.floor(bar / 2), 1, bar)
              love.graphics.rectangle("fill", mcx + rr - 1, mcy - math.floor(bar / 2), 1, bar)
              local dk = round(rr * 0.7071)
              love.graphics.rectangle("fill", mcx - dk - 1, mcy - dk - 1, 2, 2)
              love.graphics.rectangle("fill", mcx + dk - 1, mcy - dk - 1, 2, 2)
              love.graphics.rectangle("fill", mcx - dk - 1, mcy + dk - 1, 2, 2)
              love.graphics.rectangle("fill", mcx + dk - 1, mcy + dk - 1, 2, 2)
            end
            local press = 1 + 0.35 * math.max(0, 1 - brand_p * 3)
            love.graphics.push()
            love.graphics.translate(mcx, mcy)
            love.graphics.scale(press, press)
            Prims.wax_seal(0, 0, rn(9), U, GOLD, ease * ca, pulse, true)
            Prims.draw_skull(0, 0, rn(6), WHITE, ease * ca, GOLD, true)
            love.graphics.pop()
          end
          Prims.ember_bloom(mcx, mcy, slot_w * 0.45, u, (pe - 0.35) / 0.50, GOLD, ca, false)
          if pe >= 0.28 and pe < 0.52 then
            local fl = math.sin(math.pi * (pe - 0.28) / 0.24)
            love.graphics.setColor(1, 0.95, 0.85, 0.40 * fl * ca)
            love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h)
            set_col(ACC, 0.28 * fl * ca)
            love.graphics.rectangle("fill", slot_x - rn(2), sy_slot - rn(2), slot_w + rn(4), slot_h + rn(4))
            local burst = (pe - 0.28) / 0.24
            Prims.confetti_burst(mcx, mcy, burst, slot_w, rn(2), 0.6, GOLD, ACC, ca)
            Prims.confetti_burst(mcx, mcy, burst, slot_w * 0.75, rn(2), 1.7, GOLD, ACC, 0.9 * ca)
          end
        else
          Prims.wax_seal(mcx, mcy, rn(9), U, GOLD, math.min(1, pe / 0.30) * ca, pulse)
        end
      end

      if persona_neuro and st == "picked" then
        if not Motion.reduced then
          if pe < 0.5 then
            local ov = math.min(1, pe / 0.32)
            local veil = (pe < 0.32) and (0.5 * ov) or math.max(0, 0.5 * (1 - (pe - 0.32) / 0.18))
            set_col(ACC, veil * ca)
            love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, 3, 3)
            love.graphics.setColor(shimr, shimg, shimb, veil * 0.6 * ca)
            love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, math.max(2, slot_h * 0.5))
          end
          local ov = math.min(1, pe / 0.32)
          local rmax = slot_w * 0.5
          Prims.confetti_burst(mcx, mcy, ov, rmax, U * 1.7, 0.2, pg, ACC, ca)
          Prims.confetti_burst(mcx, mcy, ov, rmax * 0.66, U * 1.5, 1.1, pg, ACC, 0.9 * ca)
          Prims.confetti_burst(mcx, mcy, ov, rmax * 0.4, U * 1.3, 2.0, pg, ACC, 0.85 * ca)
          if pe < 0.42 then
            local sca = (1 - pe / 0.42) * ca
            for i = 1, 7 do
              local sxp = slot_x + (0.5 + 0.5 * math.sin(i * 12.9898)) * slot_w
              local syp = sy_slot + (0.5 + 0.5 * math.sin(i * 78.233)) * slot_h
              if i % 2 == 0 then Prims.draw_sparkle(sxp, syp, U * 1.4, pg, 0.9 * sca)
              else Prims.draw_heart(sxp, syp, U * 1.2, ACC, 0.85 * sca) end
            end
          end
          if pe >= 0.30 and pe < 0.52 then
            local fl = math.sin(math.pi * (pe - 0.30) / 0.22)
            love.graphics.setColor(1, 1, 1, 0.5 * fl * ca)
            love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, 3, 3)
            set_col(pg, 0.35 * fl * ca)
            love.graphics.rectangle("fill", slot_x - rn(2), sy_slot - rn(2), slot_w + rn(4), slot_h + rn(4), 4, 4)
            local burst = (pe - 0.30) / 0.22
            Prims.confetti_burst(mcx, mcy, burst, slot_w, U * 1.8, 0.6, pg, ACC, ca)
            Prims.confetti_burst(mcx, mcy, burst, slot_w * 0.8, U * 1.5, 1.7, pg, ACC, 0.9 * ca)
          end
          local pop = clamp01((pe - 0.30) / 0.22)
          local bsc = 1 + 0.6 * math.sin(math.pi * pop)
          Prims.draw_bow(mcx, mcy, rn(2) * bsc, ACC, 0.95 * ca, pg)
        else
          love.graphics.setColor(1, 1, 1, 0.4 * math.max(0, 1 - pe / 0.4) * ca)
          love.graphics.rectangle("fill", slot_x, sy_slot, slot_w, slot_h, 3, 3)
        end
      end

      if st == "picked" then
        local pick_label = persona_evil and "CLAIMED" or (persona_neuro and "MINE!" or "SELECTED")
        local lbl_col = persona_neuro and pg or GOLD
        local plw = tracked_width(pick_label, TRACK_SM, font)
        local plx = slot_x + math.floor((slot_w - plw) / 2)
        local ply = sy_slot + slot_h - text_h - 4
        caps_label(pick_label, plx, ply, lbl_col, 0.95 * ca, TRACK_SM, font, 0.32 * ca)
        if persona_neuro then
          Prims.draw_heart(plx - U * 3, ply + math.floor(text_h / 2), U * 2, pg, 0.9 * ca)
          Prims.draw_heart(plx + plw + U * 3, ply + math.floor(text_h / 2), U * 2, pg, 0.9 * ca)
        elseif persona_evil then
          local scy = ply + math.floor(text_h / 2)
          local sk_sc = Motion.reduced and 1 or (1 + 0.12 * pulse)
          local burn = Motion.reduced and 0.55 or (0.35 + 0.65 * Prims.candle01(now))
          local sl = plx - U * 3
          local sr = plx + plw + U * 3
          Prims.draw_diamond(sl, scy, U * 3, ACC, 0.22 * burn * ca)
          Prims.draw_diamond(sr, scy, U * 3, ACC, 0.22 * burn * ca)
          Prims.draw_skull(sl, scy, U * 2.5 * sk_sc, WHITE, 0.92 * ca, GOLD, true)
          Prims.draw_skull(sr, scy, U * 2.5 * sk_sc, WHITE, 0.92 * ca, GOLD, true)
        end
      end
    end

    local slot_y = ctx.center_top_y + title_h2 + 4
    for ci, dc in ipairs(display_cards) do
      local ca = dc.alpha
      if leaving then ca = ca * leave01 end
      local stagger_delay = (ci - 1) * Motion.dur(Motion.STAGGER_WIDE)
      local appear_elapsed = now - S.pack_appear_t - stagger_delay
      local slide_y = 0
      local appear_ef = 1
      if appear_elapsed < PACK_CARD_APPEAR_D and dc.state ~= "picked" then
        appear_ef = Motion.anim01(appear_elapsed, PACK_CARD_APPEAR_D)
        ca = ca * appear_ef
        if persona_neuro and not Motion.reduced then
          local bt3 = appear_ef - 1
          slide_y = math.floor((1 - (1 + bt3 * bt3 * (2.7 * bt3 + 1.7))) * 44)
        elseif persona_evil and not Motion.reduced then
          local bt3 = appear_ef - 1
          slide_y = math.floor((1 - (1 + bt3 * bt3 * (1.9 * bt3 + 0.9))) * 40)
        else
          slide_y = math.floor((1 - appear_ef) * 40)
        end
      end
      local slot_x = pk_x + pk_pad + (dc.index - 1) * (slot_w + slot_gap)
      local scan = Motion.reduced and 0.75 or (0.5 + 0.5 * math.sin(now * 2.4))
      draw_pack_slot(dc, slot_x, slot_y + slide_y, ca, appear_ef, scan)
    end

    ctx.center_top_y = pk_base_top + pk_total_h + 4
  end
end

return { draw = draw_pack_panel }
