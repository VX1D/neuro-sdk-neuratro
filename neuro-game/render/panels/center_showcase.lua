local H = require("render.hud_shared")
local Prims, S, Motion = H.Prims, H.S, H.Motion
local round = Prims.round
local clamp01 = Prims.clamp01
local set_col = H.set_col
local shadow_text = H.shadow_text
local smoothstep01 = H.smoothstep01
local draw_card_mini = H.draw_card_mini
local caps_label, print_tracked = H.caps_label, H.print_tracked
local card_edition_tag, draw_animated_edition = H.card_edition_tag, H.draw_animated_edition

local function draw_center_showcase(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local pg, bg, ACC, FRD, GOLD, WHITE = th.pg, th.bg, th.ACC, th.FRD, th.GOLD, th.WHITE
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local pk, font, panel_font_small = th.pk, th.font, th.panel_font_small
  local sw, U, TRACK_SM = me.sw, me.U, me.TRACK_SM
  local showcase_card, showcase_name, showcase_label, showcase_fx, showcase_desc = da.showcase_card, da.showcase_name, da.showcase_label, da.showcase_fx, da.showcase_desc
  local showcase_alpha, showcase_slide = da.showcase_alpha, da.showcase_slide
  local trunc, wrapped_lines, draw_colored_desc, showcase_type_colors = dr.trunc, dr.wrapped_lines, dr.draw_colored_desc, dr.showcase_type_colors
  if showcase_card and showcase_alpha > 0 then
    local sc_w = math.min(sw - 40, 500)
    local sc_x = math.floor((sw - sc_w) / 2)
    local a = showcase_alpha
    local sx = sc_x
    local small_f = panel_font_small or font
    local sfh = small_f:getHeight()
    local fh = font:getHeight()
    local sc_p, sc_pg = showcase_type_colors(showcase_label, showcase_card, persona_evil)

    local mini_h = 110
    local text_x = sx + 8 + math.floor(mini_h * 0.75) + 14
    local tw2 = sc_w - (text_x - sx) - 8

    local fx_lines = {}
    if showcase_fx and showcase_fx ~= "" then
      fx_lines = wrapped_lines(showcase_fx, tw2, small_f)
    end
    local desc_lines = {}
    if showcase_desc and showcase_desc ~= "" then
      desc_lines = wrapped_lines(showcase_desc, tw2, small_f)
    end
    local max_desc = 6
    local n_fx = math.min(#fx_lines, 2)
    local n_desc = math.min(#desc_lines, max_desc)
    local text_h2 = fh + 2 + fh + 4
    if n_fx > 0 then text_h2 = text_h2 + n_fx * (sfh + 1) + 2 end
    if n_desc > 0 then text_h2 = text_h2 + n_desc * (sfh + 1) + 2 end
    local sh2 = math.max(mini_h + 8, text_h2 + 8)
    local sc_st = (S.joker_showcase and S.joker_showcase.started) or now
    local sc_appear = smoothstep01(math.min(1, (now - sc_st) / 0.4))
    local sc_slide = showcase_slide
    if persona_neuro and not Motion.reduced and (now - sc_st) < 0.6 then
      local bt2 = sc_appear - 1
      sc_slide = (1 - (1 + bt2 * bt2 * (2.7 * bt2 + 1.7))) * 14
    elseif persona_evil and not Motion.reduced and (now - sc_st) < 0.6 then
      local bt2 = sc_appear - 1
      sc_slide = (1 - (1 + bt2 * bt2 * (1.9 * bt2 + 0.9))) * 12
    end
    local sy = ctx.center_top_y + sc_slide

    local scrad = persona_neuro and 10 or 0
    Prims.panel_shell(sx, sy, sc_w, sh2, scrad, 2, 2, 0.55 * a, bg, 0.94 * a)
    set_col(sc_p, 0.16 * a)
    love.graphics.rectangle("fill", sx, sy, sc_w, sh2, scrad, scrad)
    local sc_th = math.min(sh2, fh + U * 3)
    if persona_evil then
      local sc_flare = clamp01((now - sc_st) / 0.45)
      Prims.gothic_frame(sx, sy, sc_w, sh2, U, GOLD, FRD, a, 0, pulse)
      Prims.evil_frame_deco(sx, sy, sc_w, sh2, U, sc_th, GOLD, pg, pulse, now, Motion.reduced, 0.32, a, sc_flare)
      Prims.ember_bloom(sx + 6 + math.floor(mini_h * 0.375), sy + math.floor(sh2 / 2), mini_h * 0.7, U,
        (now - sc_st) / 0.45, GOLD, a, Motion.reduced)
      if not Motion.reduced and sc_flare < 1 then
        set_col(ACC, 0.20 * math.sin(math.pi * sc_flare) * a)
        love.graphics.rectangle("fill", sx, sy, sc_w, sh2)
      end
      Prims.corner_brand(sx + sc_w - U * 5, sy + U * 2, U * 0.9, ACC, WHITE, 0.95 * a, false)
    else
      set_col(sc_pg, (0.66 + 0.10 * pulse) * a)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", sx, sy, sc_w, sh2, scrad, scrad)
    end
    if persona_neuro then
      Prims.neuro_frame_deco(sx, sy, sc_w, sh2, scrad, U, sc_th, ACC, pg, shimr, shimg, shimb, a)
      if not Motion.reduced and sc_appear < 1 then
        local pk3 = math.sin(math.pi * sc_appear)
        Prims.draw_sparkle(sx + sc_w - U * 9, sy + U * 3, U + pk3 * U * 2, pg, 0.85 * pk3 * a)
        Prims.confetti_burst(sx + sc_w - U * 5, sy + U * 2, sc_appear, U * 14, U * 1.5, 0.4, pg, ACC, a)
      end
      Prims.draw_bow(sx + sc_w - U * 5, sy + U * 2, U * 0.9, ACC, 0.95 * a, pg)
    end

    local mini_x = sx + 6
    local mini_y = sy + math.floor((sh2 - mini_h) / 2)
    draw_card_mini(showcase_card, mini_x, mini_y, mini_h, a)
    do
      local mw3 = math.floor(mini_h * 0.75)
      love.graphics.setLineWidth(1)
      if persona_evil then
        Prims.photo_corners(mini_x - 2, mini_y - 2, mw3 + 4, mini_h + 4, GOLD, 0.55 * a, U * 2)
        Prims.draw_glint(mini_x - 1, mini_y - 1, U * 2, ACC, 0.85 * a, GOLD, true)
        Prims.draw_glint(mini_x + mw3 + 1, mini_y + mini_h + 1, U * 2, ACC, 0.85 * a, GOLD, true)
      elseif persona_neuro then
        love.graphics.setColor(shimr, shimg, shimb, 0.40 * a)
        love.graphics.rectangle("line", mini_x - 2, mini_y - 2, mw3 + 4, mini_h + 4, 3, 3)
        Prims.draw_heart(mini_x - 1, mini_y - 1, U * 2, pg, 0.85 * a)
        Prims.draw_heart(mini_x + mw3 + 1, mini_y + mini_h + 1, U * 2, pg, 0.85 * a)
      end
    end

    local yy = sy + U
    if persona_evil and not Motion.reduced and sc_appear < 1 then
      love.graphics.setFont(font)
      local gj = math.max(1, round(U * (1 - sc_appear)))
      love.graphics.setColor(0.95, 0.10, 0.16, 0.5 * a)
      print_tracked(showcase_label or "NEW CARD", text_x - gj, yy, TRACK_SM, font)
      love.graphics.setColor(0.12, 0.80, 0.90, 0.4 * a)
      print_tracked(showcase_label or "NEW CARD", text_x + gj, yy - 1, TRACK_SM, font)
    end
    local sc_lbl_end = caps_label(showcase_label or "NEW CARD", text_x, yy, sc_pg, (0.92 + 0.08 * pulse) * a, TRACK_SM, font, 0.30 * a)
    if persona_evil and sc_lbl_end then
      local seal_cy = yy + math.floor(fh / 2)
      local seal_cx = sc_lbl_end + U * 5
      local stamp = Motion.reduced and 1 or (1 + (1 - sc_appear) * (1 - sc_appear) * 0.9)
      Prims.wax_seal(seal_cx, seal_cy, U * 3 * stamp, U, GOLD, a, pulse, true)
      Prims.ember_bloom(seal_cx, seal_cy, U * 7, U, (now - sc_st) / 0.5, GOLD, 0.9 * a, Motion.reduced)
    elseif persona_neuro and sc_lbl_end then
      love.graphics.setColor(shimr, shimg, shimb, 0.55 * a)
      love.graphics.rectangle("fill", text_x, yy + fh + 1, sc_lbl_end - text_x, 1)
      Prims.draw_heart(sc_lbl_end + U * 3, yy + math.floor(fh / 2), U * 2, pg, 0.75 * a)
    end
    yy = yy + fh + 2

    local nline = trunc(showcase_name or "Card", tw2)
    love.graphics.setColor(0, 0, 0, 0.35 * a)
    love.graphics.print(nline, text_x + 1, yy + 1)
    love.graphics.setColor(1, 1, 1, 0.98 * a)
    love.graphics.print(nline, text_x, yy)
    local sc_ed = card_edition_tag(showcase_card)
    if sc_ed ~= "" then
      draw_animated_edition(sc_ed, text_x + font:getWidth(nline), yy, a, font, now, pk)
    end
    yy = yy + fh + 4

    if n_fx > 0 then
      if panel_font_small then love.graphics.setFont(panel_font_small) end
      for i = 1, n_fx do
        shadow_text(fx_lines[i], text_x, yy, sc_pg, 0.92 * a, 0.30 * a)
        yy = yy + sfh + 1
      end
      yy = yy + 2
      if panel_font_small then love.graphics.setFont(font) end
    end

    if n_desc > 0 then
      if panel_font_small then love.graphics.setFont(panel_font_small) end
      if persona_evil then
        love.graphics.setColor(0, 0, 0, 0.22 * a)
        love.graphics.rectangle("fill", text_x - U, yy - 1, tw2 + U * 2, n_desc * (sfh + 1) + 2)
      end
      for i = 1, n_desc do
        draw_colored_desc(desc_lines[i], text_x, yy, a, small_f)
        yy = yy + sfh + 1
      end
      if panel_font_small then love.graphics.setFont(font) end
    end

    ctx.center_top_y = ctx.center_top_y + sh2 + 12
  end
end

return { draw = draw_center_showcase }
