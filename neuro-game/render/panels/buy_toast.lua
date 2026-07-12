local H = require("render.hud_shared")
local Prims, S, Motion = H.Prims, H.S, H.Motion
local round = Prims.round
local set_col = H.set_col
local caps_label, print_tracked = H.caps_label, H.print_tracked
local draw_card_mini, rarity_color = H.draw_card_mini, H.rarity_color
local buy_showcase_alpha = H.buy_showcase_alpha
local BUY_SHOWCASE_DURATION = H.BUY_SHOWCASE_DURATION

local function draw_buy_toast(ctx)
  local th, mo, me, _, dr = H.bind(ctx)
  local pg, bg, ACC, GOLD, WHITE, _pal = th.pg, th.bg, th.ACC, th.GOLD, th.WHITE, th._pal
  local now, pulse, shimr, shimg, shimb = H.motion(mo)
  local persona_evil, persona_neuro = H.persona(th)
  local font = th.font
  local sw, U, GUT, ACCENT_W, TRACK_SM, text_h = me.sw, me.U, me.GUT, me.ACCENT_W, me.TRACK_SM, me.text_h
  local trunc = dr.trunc
  if S.buy_showcase then
    local area_tag = tostring(S.buy_showcase.area or "shop")
    if area_tag ~= "booster_choice" then
      local elapsed = now - (S.buy_showcase.started or now)
      local ba = buy_showcase_alpha(S.buy_showcase, now)
      if ba > 0 then
        local bt_label = "BOUGHT"
        if area_tag == "booster_pick" then bt_label = "PICKED"
        elseif area_tag == "joker_gain" then bt_label = "NEW JOKER"
        elseif area_tag == "shop_vouchers" then bt_label = "VOUCHER"
        elseif area_tag == "shop_booster" then bt_label = "OPENED"
        end
        local bt_name = S.buy_showcase.name or "Card"
        local bt_cost = tonumber(S.buy_showcase.cost) or 0
        local is_gain = (area_tag == "joker_gain" or area_tag == "booster_pick")
        local price_str = (bt_cost > 0) and ((is_gain and "+$" or "$") .. bt_cost) or nil

        local card = S.buy_showcase.card
        local cr = card and rarity_color(card)
        local bt_accent = cr or ACC
        local money = _pal.D_MONEY

        local bt_w = math.min(sw - 40, 480)
        local bt_h = 34
        local bt_x = math.floor((sw - bt_w) / 2)
        local bt_y = ctx.center_top_y
        local slide_y_bt = -math.floor((1 - ba) * 10)
        local by = bt_y + slide_y_bt

        local bt_rad = persona_neuro and 8 or 0
        Prims.panel_shell(bt_x, by, bt_w, bt_h, bt_rad, 2, 2, 0.55 * ba, bg, 0.96 * ba)
        if persona_neuro then
          love.graphics.setColor(shimr, shimg, shimb, (0.60 + 0.10 * pulse) * ba)
        elseif persona_evil then
          set_col(ACC, (0.55 + 0.10 * pulse) * ba)
        else
          set_col(bt_accent, (0.60 + 0.10 * pulse) * ba)
        end
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", bt_x, by, bt_w, bt_h, bt_rad, bt_rad)
        if persona_evil then
          if not Motion.reduced and elapsed >= 0 and elapsed < 0.4 then
            set_col(ACC, 0.22 * math.sin(math.pi * (elapsed / 0.4)) * ba)
            love.graphics.rectangle("fill", bt_x, by, bt_w, bt_h)
          end
        end

        set_col(bt_accent, 0.90 * ba)
        love.graphics.rectangle("fill", bt_x + U, by + 6, ACCENT_W, bt_h - 12)
        if persona_neuro and not Motion.reduced and elapsed >= 0 and elapsed < 0.4 then
          local pk4 = elapsed / 0.4
          for si2 = 0, 2 do
            Prims.draw_sparkle(bt_x + U * 2, by + 7 + si2 * math.floor((bt_h - 14) / 2),
              U + pk4 * U, pg, (1 - pk4) * 0.9 * ba)
          end
        end

        local bt_tx = bt_x + GUT
        if card then
          local mini_h = bt_h - 8
          local mini_w = draw_card_mini(card, bt_x + GUT, by + 4, mini_h, ba)
          if mini_w > 0 then bt_tx = bt_x + GUT + mini_w + 8 end
        end

        local bt_ty = by + math.floor((bt_h - text_h) / 2)
        local name_right = bt_x + bt_w - 10
        if price_str then
          local pw = font:getWidth(price_str)
          local px = bt_x + bt_w - 10 - pw
          love.graphics.setColor(0, 0, 0, 0.30 * ba)
          love.graphics.print(price_str, px + 1, bt_ty + 1)
          if persona_evil then
            set_col(money, 0.95 * ba)
            name_right = px - U * 3
          elseif persona_neuro then
            love.graphics.setColor(shimr, shimg, shimb, 0.55 * ba)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", px - U, bt_ty - 2, pw + U * 2, text_h + 4, 3, 3)
            local tmy2 = bt_ty + math.floor(text_h / 2)
            love.graphics.line(px - U * 2, tmy2, px - U, tmy2)
            love.graphics.circle("fill", px - U * 2, tmy2, 1.2)
            love.graphics.setColor(1, 1, 1, 0.95 * ba)
            name_right = px - U * 4
          else
            set_col(money, 0.95 * ba)
            name_right = px - 10
          end
          love.graphics.print(price_str, px, bt_ty)
        end

        local lbl_x = bt_tx
        if persona_evil then
          Prims.draw_skull(bt_tx + U, bt_ty + math.floor(text_h / 2), U * 1.5, WHITE, 0.95 * ba, GOLD, false)
          lbl_x = bt_tx + U * 3
          if not Motion.reduced and elapsed >= 0 and elapsed < 0.4 then
            local gj = math.max(1, round(U * (1 - elapsed / 0.4)))
            love.graphics.setFont(font)
            love.graphics.setColor(0.95, 0.10, 0.16, 0.5 * ba)
            print_tracked(bt_label, lbl_x - gj, bt_ty, TRACK_SM, font)
            love.graphics.setColor(0.12, 0.80, 0.90, 0.4 * ba)
            print_tracked(bt_label, lbl_x + gj, bt_ty - 1, TRACK_SM, font)
          end
        elseif persona_neuro then
          local hb = Motion.reduced and 0 or math.sin(now * 2.2)
          Prims.draw_heart(bt_tx + U, bt_ty + math.floor(text_h / 2) + hb, U * 2, pg, 0.9 * ba)
          lbl_x = bt_tx + U * 4
        end
        local lbl_end = caps_label(bt_label, lbl_x, bt_ty, bt_accent, 0.97 * ba, TRACK_SM, font, 0.30 * ba)
        if persona_evil then Prims.seal_after(lbl_end, bt_ty + math.floor(text_h / 2), U, GOLD, ba, pulse) end
        local name_x = lbl_end + GUT - 2
        local bt_name_str = trunc(bt_name, name_right - name_x)
        love.graphics.setColor(0, 0, 0, 0.30 * ba)
        love.graphics.print(bt_name_str, name_x + 1, bt_ty + 1)
        love.graphics.setColor(1, 1, 1, 0.95 * ba)
        love.graphics.print(bt_name_str, name_x, bt_ty)

        local timer_frac = math.max(0, 1.0 - elapsed / BUY_SHOWCASE_DURATION)
        if persona_neuro then
          local ts_w = math.max(2, (bt_w - bt_rad * 2) * timer_frac)
          Prims.tag_string(bt_x + bt_rad, by + bt_h - 2, ts_w, 1, shimr, shimg, shimb, ba)
          Prims.draw_heart(bt_x + bt_rad + ts_w, by + bt_h - 2, U * 1.5, pg, 0.9 * ba)
        else
          set_col(bt_accent, 0.55 * ba)
          love.graphics.rectangle("fill", bt_x, by + bt_h - 2, math.max(2, bt_w * timer_frac), 2)
        end

        ctx.center_top_y = ctx.center_top_y + math.floor((bt_h + 4) * ba)
      end
    end
  end
end

return { draw = draw_buy_toast }
