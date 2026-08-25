local H = require("render.hud_shared")
local Prims, S = H.Prims, H.S
local Motion = Prims.Motion
local round = Prims.round
local clamp01 = Prims.clamp01
local smoothstep01 = H.smoothstep01
local set_col = H.set_col
local shadow_text = H.shadow_text
local caps_label, tracked_width = H.caps_label, H.tracked_width
local draw_card_mini, card_dimensions, card_sprite = H.draw_card_mini, H.card_dimensions, H.card_sprite
local rarity_color, card_display_name, card_description =
  H.rarity_color, H.card_display_name, H.card_description
local modifier_badges, layout_modifier_badges, draw_modifier_badges =
  H.modifier_badges, H.layout_modifier_badges, H.draw_modifier_badges
local Showcase = require("hud.showcase")
local CardUtil = require("facts.card_util")
local StateKinds = require("core.state_kinds")
local Vouchers = require("hud.vouchers")
local Utils = H.Utils

local PIN_MO = { pulse = 0.5 }
local function pin_mo(mo)
  PIN_MO.pulse = (mo and mo.pulse) or 0.5
  return PIN_MO
end

local function voucher_key(card)
  local c = card and card.config and card.config.center
  return (c and c.set == "Voucher" and c.key) or nil
end

local TL = {
  soft    = { IN = 0.25, HOLD = 0.45, MORPH = 0.28, FX_LEAD = 0.10, OUT = 0.40 },
  LATCH = 1.15,
  FULL_MIN = Showcase.JOKER_SHOWCASE_MIN,
  FULL_SPAN = Showcase.JOKER_SHOWCASE_DURATION,
  IN_FADE = Showcase.JOKER_SHOWCASE_FADE_IN,
  OUT_FADE = Showcase.JOKER_SHOWCASE_FADE_OUT,
}

-- A verb morph-pairs only when the same card table survives from buy_showcase into joker_showcase.
-- shop_use/use route through use_card (button_callbacks.lua:2238 removes, :2262 consumes) and
-- booster_pick's card never reaches the acquire screen (pack cinematic owns that beat instead,
-- see PACK_CINEMATIC_AREAS) -- none of the three ever pair.
local MORPH_AREAS = {
  shop_jokers = true, shop_vouchers = true,
}
local RECEIPT_ONLY = {
  refused = true, lost = true, sell = true, shop_booster = true, shop = true,
  shop_use = true, use = true, booster_pick = true,
}

local AREA_LABEL = {
  booster_pick = "PICKED",
  shop_vouchers = "REDEEMED",
  shop_booster = "OPENED",
  shop_use = "BOUGHT & USED",
  use = "USED",
  sell = "SOLD",
  lost = "LOST",
}

local REFUSAL_LABEL = {
  INSUFFICIENT_FUNDS = "CAN'T AFFORD",
  NO_SLOT = "NO SLOT",
}

local NEGATIVE_AREA = { refused = true, lost = true }

local function receipt_label(sc, area_tag)
  if area_tag == "refused" then
    return REFUSAL_LABEL[tostring(sc.code or "")] or "REFUSED"
  end
  return AREA_LABEL[area_tag] or "BOUGHT"
end

local _deco = {}
local function deco_for(pk)
  local d = _deco[tostring(pk)]
  if d == nil then
    local ok, mod = pcall(require, "render.panels.acquire_" .. tostring(pk))
    d = (ok and type(mod) == "table") and mod or false
    _deco[tostring(pk)] = d
  end
  return d or nil
end

local function timeline(deco)
  return (deco and deco.TL) or TL.soft
end

local MORPH_INK_OUT = 0.4

local function receipt_ends_at(sc, tl, morph_at)
  local at = Showcase.receipt_ends_at(sc)
  local m = sc._morph_at or morph_at
  if m then
    local ink_out = m + (sc._morph_d or tl.MORPH) * MORPH_INK_OUT
    if ink_out < at then at = ink_out end
  end
  return at
end

local function timer_frac(sc, now, ends_at)
  if sc._bar_born ~= sc.born_at then
    sc._bar_born, sc._bar_frac, sc._bar_ends = sc.born_at, 1, nil
    sc._bar_undo_ends, sc._bar_undo_frac = nil, nil
  end
  local frac = sc._bar_frac or 1
  if sc._bar_ends ~= ends_at then
    if sc._bar_undo_ends == ends_at then
      frac, sc._bar_undo_ends = sc._bar_undo_frac or frac, nil
    else
      sc._bar_undo_ends, sc._bar_undo_frac = sc._bar_ends, frac
    end
    sc._bar_ends, sc._bar_from = ends_at, frac
    sc._bar_span = math.max(1e-6, ends_at - now)
  end
  frac = math.min(frac, clamp01((sc._bar_from or 1) * (ends_at - now) / sc._bar_span))
  sc._bar_frac = frac
  return frac
end

local function pair(now, tl)
  local sc = S.buy_showcase
  if not sc then return false, nil end
  if sc._morph_at then return true, sc._morph_at end
  tl = tl or TL.soft
  local js = S.joker_showcase
  local ok = sc.card ~= nil and js ~= nil and js.card == sc.card
    and MORPH_AREAS[tostring(sc.area or "")] == true
    and not sc.swap_started
  if not ok then
    sc._pair_at = nil
    return false, nil
  end
  local started = sc.started or now
  if not sc._born then sc._born = started end
  if not sc._pair_at then
    if (now - sc._born) >= TL.LATCH then return false, nil end
    sc._pair_at = now
  end
  return true, math.max(started + tl.HOLD, sc._pair_at)
end

local function layout_receipt(cnf, name_h, eyebrow_h)
  local box_h = math.max(cnf(64), name_h + eyebrow_h + cnf(20))
  return {
    box_h = box_h,
    thumb_h = box_h - cnf(12),
    accent_w = math.max(2, cnf(4)),
    pad_l = cnf(10),
    pad_r = cnf(14),
    gap = cnf(10),
    lead = cnf(2),
    timer_h = 2,
    quant = cnf(8),
    min_w = cnf(220),
    max_w = cnf(560),
  }
end

local function receipt_fonts(th)
  local font = th.cfont or th.font
  return font,
    th.cfont_title or th.font_title or font,
    th.cfont_micro or th.cfont_small or th.panel_font_small or font,
    th.cfont_small or th.panel_font_small or font
end

local function stage_cx(ctx, sw)
  return S.ov.stage_cx or ctx.center_cx or math.floor(sw / 2)
end

local function merged_money(sc)
  local spend = tonumber(sc.merged_spend) or 0
  local gain = tonumber(sc.merged_gain) or 0
  if spend > 0 and gain > 0 then return "-$" .. spend .. " +$" .. gain end
  if spend > 0 then return "-$" .. spend end
  if gain > 0 then return "+$" .. gain end
  return nil
end

local function measure_receipt(ctx, sc)
  local th, _, me = H.bind(ctx)
  local font, nfont, efont = receipt_fonts(th)
  local cn = me.cn or function(v) return v end
  local sw = me.sw
  local TRACK = me.TRACK or 2
  local GUT = cn(me.GUT)
  local nfh, efh, pfh = nfont:getHeight(), efont:getHeight(), font:getHeight()
  local L = layout_receipt(cn, nfh, efh)
  local area_tag = tostring(sc.area or "shop")
  local card = sc.card
  local name = card and card_display_name(card) or sc.name or "Card"
  local value = (type(sc.effect) == "string" and sc.effect ~= "") and sc.effect or name
  local cost = tonumber(sc.cost) or 0
  local is_gain = Showcase.money_direction(area_tag) == "gain"
  local price_str = (cost > 0) and ((is_gain and "+$" or "$") .. cost) or nil
  local chip_str = (tonumber(sc.merged) or 0) > 0 and ("+" .. sc.merged) or nil
  local chip_money = merged_money(sc)

  local ak, pos
  if card and card_sprite then ak, pos = card_sprite(card) end
  local has_thumb = ak ~= nil and pos ~= nil
  local thumb_w, thumb_h = 0, 0
  if has_thumb then thumb_w, thumb_h = card_dimensions(card, L.thumb_h) end

  local label = receipt_label(sc, area_tag)
  local eyebrow_w = tracked_width(label, TRACK, efont)
  if chip_str then eyebrow_w = eyebrow_w + cn(6) + efont:getWidth(chip_str) end
  if chip_money then eyebrow_w = eyebrow_w + cn(4) + efont:getWidth(chip_money) end
  local price_w = price_str and font:getWidth(price_str) or 0
  local fixed_l = L.accent_w + L.pad_l + (has_thumb and (thumb_w + L.gap) or 0)
  local fixed_r = (price_str and (GUT + price_w) or 0) + L.pad_r
  local content_w = math.max(eyebrow_w, nfont:getWidth(value))
  local max_w = math.min(L.max_w, ctx.center_max_w or (sw - 40))
  max_w = math.max(80, math.min(max_w, sw - 16))
  local min_w = math.min(L.min_w, max_w)
  local w = math.min(max_w,
    math.max(min_w, math.ceil((fixed_l + content_w + fixed_r) / L.quant) * L.quant))
  local stack_h = efh + L.lead + nfh
  local eyebrow_dy = math.floor((L.box_h - stack_h) / 2)
  local name_dy = eyebrow_dy + efh + L.lead
  return {
    w = w, h = L.box_h, L = L,
    area = area_tag,
    negative = NEGATIVE_AREA[area_tag] == true,
    label = label, value = value,
    price_str = price_str, chip_str = chip_str, chip_money = chip_money, price_w = price_w,
    has_thumb = has_thumb,
    card_w = thumb_w, card_h = thumb_h,
    card_dx = L.accent_w + L.pad_l,
    text_dx = fixed_l,
    text_w = w - fixed_l - fixed_r,
    eyebrow_dy = eyebrow_dy,
    name_dy = name_dy,
    badges_dy = name_dy + nfh + L.lead,
    desc_dy = name_dy + nfh + L.lead,
    price_dy = math.floor((L.box_h - pfh) / 2),
    crest_dx = cn(14), crest_dy = cn(10),
    timer_h = L.timer_h,
    efh = efh, nfh = nfh, pfh = pfh,
  }
end

local function receipt_key_stale(sc, sw, font, nfont, efont)
  local k = sc._Lr_key
  return k == nil
    or k[1] ~= sc.area or k[2] ~= sc.name or k[3] ~= sc.cost or k[4] ~= sc.merged
    or k[5] ~= sc.merged_spend or k[6] ~= sc.merged_gain
    or k[7] ~= sc.effect or k[8] ~= sc.card or k[9] ~= sc.code
    or k[10] ~= sw or k[11] ~= font or k[12] ~= nfont or k[13] ~= efont
end

local function receipt_key_store(sc, sw, font, nfont, efont)
  local k = sc._Lr_key
  if not k then k = {}; sc._Lr_key = k end
  k[1], k[2], k[3], k[4] = sc.area, sc.name, sc.cost, sc.merged
  k[5], k[6] = sc.merged_spend, sc.merged_gain
  k[7], k[8], k[9] = sc.effect, sc.card, sc.code
  k[10], k[11], k[12], k[13] = sw, font, nfont, efont
end

local function build_desc(card)
  if not card then return "" end
  local badges = modifier_badges(card)
  if (Utils.is_playing_card(card) or CardUtil.enhancement_key(card)) and #badges > 0 then
    return ""
  end
  if Utils.is_playing_card(card) or CardUtil.enhancement_key(card) then
    return CardUtil.card_modifier_desc(card) or ""
  end
  local d = card_description(card)
  if (not d or d == "") and card.config and card.config.center then
    local ok, sd = pcall(Utils.safe_description, card.config.center.loc_txt, card)
    if ok and type(sd) == "string" then d = sd end
  end
  return d or ""
end

local MAX_DESC = 6

local function layout_full(ctx, sc)
  local th, _, me, _, dr = H.bind(ctx)
  local font, nfont, efont, small_f = receipt_fonts(th)
  small_f = small_f or font
  local cn = me.cn or function(v) return v end
  local sw = me.sw
  local TRACK_SM = me.TRACK_SM or 1
  local U = cn(me.U)
  local wrapped_lines = dr.wrapped_lines
  local card = sc.card
  local label = sc.label or Showcase.card_set_label(card)
  local sfh, nfh, efh = small_f:getHeight(), nfont:getHeight(), efont:getHeight()
  local lead = cn(4)   -- EYEBROW_LEAD

  local max_w = math.min(sw, math.max(140, math.min(ctx.center_max_w or (sw - 40), cn(500))))
  local mini_h = cn(110)
  local mw3, mh3 = 0, 0
  if card then mw3, mh3 = card_dimensions(card, mini_h) end
  local compact = (max_w - 30 - mw3) < 28
  if compact then mw3, mh3 = 0, 0 end
  local text_off = 8 + (mw3 > 0 and (mw3 + 14) or 0)
  local tw_max = max_w - text_off - 8

  local name = card and card_display_name(card) or "Card"
  local desc = build_desc(card)
  local desc_lines = {}
  if desc and desc ~= "" then desc_lines = wrapped_lines(desc, tw_max, small_f) end
  local badge_layout = layout_modifier_badges(modifier_badges(card), small_f, tw_max, cn(1), 2)
  local n_desc = math.min(#desc_lines, MAX_DESC)

  local chip_str = (tonumber(sc.merged) or 0) > 0 and ("+" .. sc.merged) or nil
  local content_w = tracked_width(label, TRACK_SM, efont) + U * 8
  if chip_str then content_w = content_w + cn(6) + efont:getWidth(chip_str) end
  content_w = math.max(content_w, nfont:getWidth(name))
  for _, it in ipairs(badge_layout.items or {}) do
    content_w = math.max(content_w, it.x + it.w)
  end
  for i = 1, n_desc do content_w = math.max(content_w, small_f:getWidth(desc_lines[i])) end
  content_w = math.min(content_w, tw_max)
  local quant = cn(8)
  local w = math.min(max_w,
    math.max(math.min(cn(300), max_w),
      math.ceil((text_off + content_w + 8) / quant) * quant))
  local text_w = w - text_off - 8

  local pin_lead = lead
  local desc_lead = cn(2)
  local text_h = efh + lead + nfh + pin_lead + badge_layout.height
  if n_desc > 0 then text_h = text_h + n_desc * (sfh + 1) + desc_lead end
  local h = math.max((compact and 0 or mini_h) + 8, text_h + 8)

  local col_h = efh + lead + nfh + pin_lead + badge_layout.height
  if n_desc > 0 then
    col_h = col_h + (badge_layout.height > 0 and desc_lead or 0) + n_desc * (sfh + 1)
  end
  local eyebrow_dy = math.max(U, round((h - col_h) / 2))
  local name_dy = eyebrow_dy + efh + lead
  local badges_dy = name_dy + nfh + pin_lead
  local desc_dy = badges_dy + badge_layout.height + (badge_layout.height > 0 and desc_lead or 0)
  return {
    w = w, h = h, compact = compact,
    label = label, name = name, chip_str = chip_str,
    desc_lines = desc_lines, n_desc = n_desc, badge_layout = badge_layout,
    card_w = mw3, card_h = mh3, mini_h = mini_h,
    card_dx = 6,
    text_dx = text_off, text_w = text_w,
    eyebrow_dy = eyebrow_dy, name_dy = name_dy,
    badges_dy = badges_dy, desc_dy = desc_dy,
    crest_dx = cn(14), crest_dy = cn(10),
    lead = lead, sfh = sfh, nfh = nfh, efh = efh,
  }
end

local function lp(u, v, m) return u + ((v or u) - u) * m end

local function geom_at(Lr, Lf, m, cx, top_y, out)
  local a, b = Lr or Lf, Lf or Lr
  local w = round(lp(a.w, b.w, m))
  local h = round(lp(a.h, b.h, m))
  local x = round(cx - w / 2)
  local y = top_y
  local g = out or {}
  g.x, g.y, g.w, g.h, g.m, g.a = x, y, w, h, m, 1
  g.rad = 0
  g.card_x = x + round(lp(a.card_dx, b.card_dx, m))
  g.card_y = y + round(lp((a.h - a.card_h) / 2, (b.h - b.card_h) / 2, m))
  g.card_w = round(lp(a.card_w, b.card_w, m))
  g.card_h = round(lp(a.card_h, b.card_h, m))
  g.text_x = x + round(lp(a.text_dx, b.text_dx, m))
  g.text_w = round(lp(a.text_w, b.text_w, m))
  g.eyebrow_y = y + round(lp(a.eyebrow_dy, b.eyebrow_dy, m))
  g.name_y = y + round(lp(a.name_dy, b.name_dy, m))
  g.badges_y = y + round(lp(a.badges_dy, b.badges_dy, m))
  g.desc_y = y + round(lp(a.desc_dy, b.desc_dy, m))
  g.price_x = x + w - ((a.L and a.L.pad_r) or 8) - (a.price_w or 0)
  g.price_y = y + (a.price_dy or 0)
  g.crest_cx = x + w - (b.crest_dx or a.crest_dx or 14)
  g.crest_cy = y + (b.crest_dy or a.crest_dy or 10)
  g.timer_y = y + h - ((a.L and a.L.timer_h) or 2)
  g.content_a_receipt = 1
  g.content_a_full = 0
  return g
end

local _geom_out = {}

local function premix(dst, base, wash, aw)
  local inv = 1 - aw
  dst[1] = base[1] * inv + wash[1] * aw
  dst[2] = base[2] * inv + wash[2] * aw
  dst[3] = base[3] * inv + wash[3] * aw
  return dst
end

local function wash_plate(dst, plate, wash, aw, a)
  local plate_a = 0.97 * a * (1 - aw)
  local bg_a = aw + plate_a
  local wk, pk = aw / bg_a, plate_a / bg_a
  dst[1] = wash[1] * wk + plate[1] * pk
  dst[2] = wash[2] * wk + plate[2] * pk
  dst[3] = wash[3] * wk + plate[3] * pk
  return dst, bg_a
end

local _neutral_bands, _neutral_frame_col = { { 0, 0, false, 0 } }, { 0, 0, 0 }
local _neutral_wash_plate, _neutral_outline = { 0, 0, 0 }, { 0, 0, 0 }
local _eyebrow_col = { 0, 0, 0 }
local _swap_layout, _flight, _flight_probe = {}, {}, {}

local function neutral_frame(ctx, g)
  local th, mo = H.bind(ctx)
  local wash_a = g.wash and g.content_a_full > 0 and (0.16 * g.a * g.content_a_full) or 0
  local bands, frame = nil, th.FR
  if wash_a > 0 and g.rad == 0 then
    local band = _neutral_bands[1]
    band[2], band[3], band[4] = g.h, g.wash, wash_a
    bands = _neutral_bands
    frame = premix(_neutral_frame_col, th.FR, g.wash, wash_a)
  end
  local bg, bg_a
  if wash_a > 0 and g.rad ~= 0 then
    bg, bg_a = wash_plate(_neutral_wash_plate, th.bg, g.wash, wash_a, g.a)
    frame = premix(_neutral_frame_col, th.FR, g.wash, wash_a)
    Prims.panel_shell(g.x, g.y, g.w, g.h, g.rad, 1, 1, 0.55 * g.a, bg, bg_a, g.a)
    love.graphics.setColor(frame[1], frame[2], frame[3], 0.90 * g.a)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", g.x, g.y, g.w, g.h, g.rad, g.rad)
    wash_a = 0
  else
    Prims.panel_base(g.x, g.y, g.w, g.h, g.rad, 1, g.a, th.bg, frame, bands)
  end
  local rc, fc = g._col_receipt or th.pg, g._col_full or th.pg
  local col = _neutral_outline
  col[1] = rc[1] + (fc[1] - rc[1]) * g.m
  col[2] = rc[2] + (fc[2] - rc[2]) * g.m
  col[3] = rc[3] + (fc[3] - rc[3]) * g.m
  if wash_a > 0 and not bands then
    set_col(g.wash, wash_a)
    love.graphics.rectangle("fill", g.x, g.y, g.w, g.h, g.rad, g.rad)
  end
  set_col(col, (0.66 + 0.10 * mo.pulse) * g.a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", g.x, g.y, g.w, g.h, g.rad, g.rad)
end

local function neutral_accent(_, g)
  if not g.accent or g.content_a_receipt <= 0 then return end
  local cap = math.min((g.rad > 0) and math.floor(g.rad / 2) or 0, math.floor((g.h - 1) / 2))
  local aw = g.accent_w or 3
  local brad = (cap > 0) and math.floor(aw / 2) or 0
  set_col(g.accent, 0.90 * g.a * g.content_a_receipt)
  love.graphics.rectangle("fill", g.x, g.y + cap, aw, g.h - cap * 2, brad, brad)
end

local function neutral_timer(ctx, g, _frac)
  local a = g.a * g.content_a_receipt
  if a <= 0 then return end
  set_col(g.accent or ctx.theme.ACC, 0.55 * a)
  love.graphics.rectangle("fill", g.x + g.rad, g.timer_y, g.timer_w, 2)
end

local function showcase_queued(card)
  if not card then return false end
  for _, it in ipairs(S.joker_showcase_q or {}) do
    if it.card == card then return true end
  end
  return false
end

local function draw_acquire(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local now = mo.now
  local persona_evil = th.persona_evil
  local cn = me.cn or function(v) return v end
  local sw = me.sw
  local deco = deco_for(th.pk)
  local tl = timeline(deco)
  local trunc = dr.trunc

  local sn = tostring(da.sn or "")

  local sc = S.buy_showcase
  local js = S.joker_showcase

  if sc == nil and js == nil then
    S.ov.stage_cx, S.ov.stage_max_w = nil, nil
    S.ov.stage_sw, S.ov.stage_sh = nil, nil
  elseif S.ov.stage_cx == nil or S.ov.stage_sw ~= sw or S.ov.stage_sh ~= me.sh then
    S.ov.stage_cx = ctx.center_cx or math.floor(sw / 2)
    S.ov.stage_max_w = ctx.center_max_w or (sw - 40)
    S.ov.stage_sw, S.ov.stage_sh = sw, me.sh
  else
    local live_max = ctx.center_max_w or (sw - 40)
    if live_max < (S.ov.stage_max_w or live_max) then
      S.ov.stage_max_w = live_max
      S.ov.stage_cx = ctx.center_cx or S.ov.stage_cx
    end
  end

  local paired, morph_at = pair(now, tl)
  if paired and sc and js and not sc._morph_at and morph_at and now >= morph_at then
    sc._morph_at = morph_at
    sc._morph_d = tl.MORPH
    sc._Lf = layout_full(ctx, { card = sc.card, label = js.label })
    js._Lf = sc._Lf
    js._morphed = true
    js._fout = tl.OUT
    js._out_at, js._exiting = nil, nil
    js.started = morph_at + tl.MORPH
  end
  if sc and sc._morph_at and now >= sc._morph_at + (sc._morph_d or tl.MORPH) then
    Showcase.retire_receipt(now)
    sc = nil
  end

  local morphing = sc and sc._morph_at and js and js.card == sc.card
  local pair_clock = sc and (sc._born or sc.started)
  local still_pairable = pair_clock ~= nil and (now - pair_clock) < TL.LATCH
  local defer_receipt = sc and js and js.card and not morphing and not paired
    and (still_pairable or showcase_queued(sc.card))
  if defer_receipt then
    Showcase.hold_receipt(sc, now)
    if not sc._defer_seen then
      sc._Lr, sc._Lr_key = nil, nil
      sc._w_from, sc._w_from_at = nil, nil
      sc._defer_seen = true
    end
  elseif sc then
    sc._defer_seen = nil
    Showcase.release_receipt(sc)
  end

  if js and js.card and not morphing
    and StateKinds.is_pack_state(tostring((G and G.NEURO and G.NEURO.force_state) or sn))
    and da.pack_rows and da.pack_rows.cards and #da.pack_rows.cards > 0 then
    Showcase.note_stage_frozen(now)
  end

  sc = S.buy_showcase
  defer_receipt = defer_receipt and S.joker_showcase ~= nil

  local mode, m01
  if morphing and S.buy_showcase then
    mode = "morph"
    m01 = clamp01((now - sc._morph_at) / (sc._morph_d or tl.MORPH))
  elseif sc and not defer_receipt then
    mode = "receipt"
    m01 = 0
  elseif js and js.card then
    mode = "full"
    m01 = 1
  else
    return
  end

  local font, nfont, efont, small_f = receipt_fonts(th)
  small_f = small_f or font

  local card, Lr, Lf
  if mode == "full" then
    card = js.card
    if not js._Lf then js._Lf = layout_full(ctx, js) end
    Lf = js._Lf
  else
    card = sc.card
    local stale = receipt_key_stale(sc, me.sw, font, nfont, efont)
    if not sc._Lr or (not sc._morph_at and stale) then
      if sc._w_draw and stale then
        sc._w_from, sc._w_from_at = sc._w_draw, now
      end
      sc._Lr = measure_receipt(ctx, sc)
      receipt_key_store(sc, me.sw, font, nfont, efont)
    end
    Lr = sc._Lr
    Lf = sc._Lf
    if mode == "receipt" and sc._w_from and sc._w_from_at then
      local k = clamp01((now - sc._w_from_at) / Showcase.BUY_SWAP_IN)
      if k >= 1 then
        sc._w_from, sc._w_from_at = nil, nil
      else
        local w2 = round(sc._w_from + (Lr.w - sc._w_from) * smoothstep01(k))
        local Ld = _swap_layout
        for lk, lv in pairs(Lr) do Ld[lk] = lv end
        Ld.text_w = Lr.text_w + (w2 - Lr.w)
        Ld.w = w2
        Lr = Ld
      end
    end
    sc._w_draw = Lr.w
  end

  local ease = (deco and deco.ease) or smoothstep01
  local m = (mode == "morph") and ease(m01) or m01

  local a
  local slide_y = 0
  local ca = 1
  local flight
  local elapsed_r = sc and (now - (sc.started or now)) or 0
  if mode == "receipt" then
    local frame_in = smoothstep01(clamp01(elapsed_r / tl.IN))
    if frame_in >= 1 then sc._frame_up = true end
    if sc._frame_up then frame_in = 1 end
    a = math.min(frame_in, Showcase.buy_alpha(sc, now))
    ca = Showcase.buy_content_alpha(sc, now)
  elseif mode == "morph" then
    a = 1
    ca = 1
  else
    local elapsed = now - (js.started or now)
    if elapsed < 0 then return end
    local fout = js._morphed and tl.OUT or TL.OUT_FADE
    local out_at = js._out_at or (TL.FULL_SPAN - fout)
    if js._morphed then
      a = 1
    else
      a = (elapsed < TL.IN_FADE) and smoothstep01(elapsed / TL.IN_FADE) or 1
      slide_y = round((1 - a) * cn(10))
    end
    if elapsed > out_at then
      local o01 = smoothstep01(clamp01((elapsed - out_at) / fout))
      a = math.min(a, 1 - o01)
      do
        slide_y = slide_y + round(o01 * cn(10))
        local vkey = voucher_key(card)
        local ft = _flight_probe
        ft.p_x, ft.p_y, ft.panel_h, ft.pw = me.p_x, me.p_y, me.total_h, me.pw_total
        ft.sw, ft.sh, ft.rn = sw, me.sh, me.rn
        local target = vkey and Vouchers.flight_target(ft)
        if target then
          flight = _flight
          flight.t01 = clamp01((elapsed - out_at) / fout)
          flight.target = target
          flight.tail = Motion.MED / math.max(0.01, fout)
        end
      end
    end
  end
  if a <= 0 and not flight then return end

  local cx = stage_cx(ctx, sw)
  local top_y = ctx.center_top_y + slide_y
  local g = geom_at(Lr, Lf, m, cx, top_y, _geom_out)
  g.a = a
  g.rad = (deco and deco.rad) and deco.rad(cn) or 0
  g.content_a_receipt = (mode == "receipt") and 1
    or ((mode == "morph") and (1 - clamp01(m01 / MORPH_INK_OUT)) or 0)
  g.content_a_full = (mode == "full") and 1 or clamp01((m01 - 0.5) / 0.5)

  local sc_p, sc_pg
  if Lf then
    sc_p, sc_pg = dr.showcase_type_colors(Lf.label, card, persona_evil)
  end
  local accent
  if Lr then
    local cr = (not Lr.negative) and card and rarity_color(card) or nil
    accent = cr or (Lr.negative and th._pal.D_RED) or th.ACC
  else
    accent = sc_pg or th.ACC
  end
  g.accent = accent
  g.accent_w = Lr and Lr.L.accent_w or math.max(2, cn(4))
  g.text_h = (Lr and Lr.efh) or (Lf and Lf.efh) or cn(10)
  g.shimr, g.shimg, g.shimb = mo.shimr, mo.shimg, mo.shimb
  g._col_receipt = th.pg
  g._col_full = sc_pg or th.pg
  g.wash = sc_p
  g.cn = cn
  g.now = now
  g.pulse = mo.pulse
  g.flight = flight

  da.showcase_alpha = math.max(da.showcase_alpha or 0, a * m01)

  local prev_font = love.graphics.getFont()
  love.graphics.setFont(font)

  local frame_fn = (deco and deco.frame) or neutral_frame
  frame_fn(ctx, g)
  local accent_fn = (deco and deco.accent) or neutral_accent
  accent_fn(ctx, g)

  if deco and deco.burst then
    if mode == "receipt" and elapsed_r >= 0 and elapsed_r < 0.35 then
      deco.burst(ctx, g, "in", clamp01(elapsed_r / 0.35))
    end
    if sc and sc._morph_at then
      local fx_at = sc._morph_at + (sc._morph_d or tl.MORPH) - (tl.FX_LEAD or 0)
      if now >= fx_at and now < fx_at + 0.45 then
        deco.burst(ctx, g, "morph_end", clamp01((now - fx_at) / 0.45))
      end
    elseif mode == "full" then
      local elapsed = now - (js.started or now)
      if js._morphed then
        local fx_at = (js.started or now) - (tl.FX_LEAD or 0)
        if now >= fx_at and now < fx_at + 0.45 then
          deco.burst(ctx, g, "morph_end", clamp01((now - fx_at) / 0.45))
        end
      elseif elapsed >= 0 and elapsed < 0.35 then
        deco.burst(ctx, g, "in", clamp01(elapsed / 0.35))
      end
    end
  end

  local content_a = a * ca

  local show_card = card and ((mode == "receipt" and Lr.has_thumb)
    or (mode ~= "receipt" and not (Lf and Lf.compact)))
  if show_card and g.card_h > 0 then
    local mini_x, mini_y, mini_h, mini_a = g.card_x, g.card_y, g.card_h, content_a
    if g.flight then
      local fe = smoothstep01(g.flight.t01)
      local t = g.flight.target
      local scx = g.card_x + g.card_w / 2
      local scy = g.card_y + g.card_h / 2
      local ecx = t.art_x + t.art_w / 2
      local ecy = t.art_y + t.art_h / 2
      local ccx = scx + (ecx - scx) * fe
      local ccy = scy + (ecy - scy) * fe
      local _, probe_h = card_dimensions(card, 1000)
      local ratio = (probe_h and probe_h > 0) and (probe_h / 1000) or 1
      if ratio <= 0 then ratio = 1 end
      local from_nom, to_nom = g.card_h / ratio, t.art_h / ratio
      mini_h = round(from_nom + (to_nom - from_nom) * fe)
      local fw, fh = card_dimensions(card, mini_h)
      mini_x = round(ccx - fw / 2)
      mini_y = round(ccy - fh / 2)
      local tail = g.flight.tail or 1
      local h01 = clamp01((g.flight.t01 - (1 - tail)) / math.max(0.001, tail))
      mini_a = 1 - smoothstep01(h01)
      g.card_x, g.card_y, g.card_w, g.card_h = mini_x, mini_y, fw, fh
    end
    local ok_mini = pcall(draw_card_mini, card, mini_x, mini_y, mini_h, mini_a)
    if not ok_mini then
      print("[neuro-game] acquire panel: draw_card_mini failed for " ..
        tostring(card and card.ability and card.ability.name))
    end
    if deco and deco.card_frame then deco.card_frame(ctx, g) end
  end

  local car = g.content_a_receipt
  local caf = g.content_a_full
  local cf01 = clamp01((m01 - 0.35) / 0.30)
  local cf_out = 1 - clamp01(cf01 / 0.5)
  local cf_in = clamp01((cf01 - 0.45) / 0.55)
  local eyebrow_col
  if Lr then
    local WHITE = th.WHITE
    eyebrow_col = _eyebrow_col
    eyebrow_col[1] = accent[1] + (WHITE[1] - accent[1]) * 0.55
    eyebrow_col[2] = accent[2] + (WHITE[2] - accent[2]) * 0.55
    eyebrow_col[3] = accent[3] + (WHITE[3] - accent[3]) * 0.55
  end

  love.graphics.setFont(efont)
  local TRACK = (mode == "full" or mode == "morph") and (me.TRACK_SM or 1) or (me.TRACK or 2)
  local lbl_end
  if Lr and cf_out > 0 then
    local eb_a = content_a * cf_out
    lbl_end = caps_label(Lr.label, g.text_x, g.eyebrow_y, eyebrow_col,
      0.97, TRACK, efont, 0.35, nil, nil, S, "acq_receipt_eyebrow", eb_a)
    if Lr.chip_str and car > 0 then
      shadow_text(Lr.chip_str, lbl_end + cn(6), g.eyebrow_y, th.WHITE,
        0.70 * content_a * car, 0.30 * content_a * car)
      if Lr.chip_money then
        shadow_text(Lr.chip_money,
          lbl_end + cn(6) + efont:getWidth(Lr.chip_str) + cn(4), g.eyebrow_y, th._pal.D_MONEY,
          0.70 * content_a * car, 0.30 * content_a * car)
      end
    end
  end
  if Lf and cf_in > 0 then
    local fw_a = content_a * cf_in
    local e2 = caps_label(Lf.label, g.text_x, g.eyebrow_y, sc_pg or th.pg,
      0.92 + 0.08 * mo.pulse, me.TRACK_SM or 1, efont,
      0.30, nil, nil, S, "acq_forward_eyebrow", fw_a)
    if Lf.chip_str then
      shadow_text(Lf.chip_str, e2 + cn(6), g.eyebrow_y, th.WHITE,
        0.70 * content_a * cf_in, 0.30 * content_a * cf_in)
    end
    lbl_end = math.max(lbl_end or 0, e2)
  end
  if deco and deco.label_deco and lbl_end then
    deco.label_deco(ctx, g, math.min(lbl_end, g.x + g.w - cn(4)))
  end

  love.graphics.setFont(nfont)
  local name_txt = (mode == "receipt") and Lr.value or Lf.name
  if g.text_w > 0 then
    shadow_text(trunc(name_txt, g.text_w, nfont), g.text_x, g.name_y,
      th.WHITE, 0.96 * content_a, 0.40 * content_a)
  end

  if Lr and Lr.price_str and car > 0 then
    love.graphics.setFont(font)
    shadow_text(Lr.price_str, g.price_x, g.price_y, th._pal.D_MONEY,
      0.95 * content_a * car, 0.30 * content_a * car)
  end

  if Lf and caf > 0 then
    local rise = round((1 - caf) * cn(6))
    local clip = H.push_clip(g.x, g.y, g.w, g.h)
    if Lf.badge_layout and Lf.badge_layout.height > 0 then
      draw_modifier_badges(Lf.badge_layout, g.text_x, g.badges_y + rise, a * caf, th, pin_mo(mo))
    end
    if Lf.n_desc > 0 then
      love.graphics.setFont(small_f)
      dr.draw_desc_lines(Lf.desc_lines, Lf.n_desc, g.text_x, g.desc_y + rise,
        Lf.sfh + 1, a * caf, small_f)
    end
    H.pop_clip(clip)
  end

  if sc and car > 0 then
    local frac = timer_frac(sc, now, receipt_ends_at(sc, tl, morph_at))
    g.timer_w = round(math.max(2, (g.w - g.rad * 2) * frac))
    local timer_fn = (deco and deco.timer) or neutral_timer
    timer_fn(ctx, g, frac)
  end

  if deco and deco.crest then deco.crest(ctx, g) end

  if prev_font then love.graphics.setFont(prev_font) end
  ctx.center_top_y = ctx.center_top_y + round((g.h + cn(10)) * a)
end

local M = {}
M.draw = draw_acquire
M.pair = pair
M.TL = TL
M.MORPH_AREAS = MORPH_AREAS
M.RECEIPT_ONLY = RECEIPT_ONLY
M.premix = premix
M.wash_plate = wash_plate

if _G.NEURO_TEST then
  M._layout_receipt = layout_receipt
  M._layout_full = layout_full
  M._geom = geom_at
end

return M
