_G.NEURO_TEST = true

local function noop() end
local function px_font(px)
  return {
    getWidth = function(_, s) return math.floor(0.5 * px * #tostring(s or "") + 0.5) end,
    getHeight = function() return math.floor(1.3 * px + 0.5) end,
  }
end
local FONT = px_font(24)
local REC = { on = false, amax = 0, cur = 1 }
local function rec_draw()
  if REC.on and REC.cur > REC.amax then REC.amax = REC.cur end
end
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getScissor = function() return nil end,
  setColor = function(r, g, b, a)
    if type(r) == "table" then REC.cur = r[4] or g or 1 else REC.cur = a or 1 end
  end,
  rectangle = rec_draw, print = rec_draw, printf = rec_draw, line = rec_draw,
  circle = rec_draw, polygon = rec_draw, ellipse = rec_draw, arc = rec_draw, draw = rec_draw,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end },
  mouse = { getPosition = function() return -1, -1 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = { persona = "neuro" }, FUNCS = {}, TIMERS = { REAL = 0 },
  GAME = { dollars = 10, current_round = { reroll_cost = 5 } },
  STATES = {}, SETTINGS = { paused = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("shop rows layout")

local ModifierBadges = require("render.modifier_badges")
local Rows = require("hud.rows")
local Shop = require("render.panels.shop")
local HS = require("hud.state")
local H = require("render.hud_shared")

do
  local m = { line_h = 20, small_line_h = 10, card_line_h = 30, sep_h = 6, header_line_h = 22,
    content_w = 300, carousel_pad = 0,
    wrap = function() local t = {} for i = 1, 10 do t[i] = "l" .. i end return t end,
    small_font = FONT }
  local h = Rows.height(Rows.descwrap({ 1, 1, 1 }, "long"), m)
  check("descwrap height caps at DESC_MAX_LINES",
    h == m.small_line_h * Rows.DESC_MAX_LINES + 2, h)
  m.wrap = function() return { "one" } end
  local h1 = Rows.height(Rows.descwrap({ 1, 1, 1 }, "short"), m)
  check("descwrap height still measures short text", h1 == m.small_line_h + 2, h1)
end

do
  check("want_compact trips above pref", Rows.want_compact(false, 500, 400) == true)
  check("want_compact holds inside hysteresis band", Rows.want_compact(true, 390, 400) == true)
  check("want_compact releases below pref minus hysteresis",
    Rows.want_compact(true, 400 - Rows.COMPACT_HYST - 1, 400) == false)
  check("want_compact stays off when under pref", Rows.want_compact(false, 100, 400) == false)
end

do
  local function n(v) return v end
  local m = { content_w = 300, carousel_pad = 0 }
  Rows.compact_metrics(m, 10, n)
  check("compact_metrics writes the shrunk row heights",
    m.line_h == 13 and m.small_line_h == 11 and m.card_line_h == 26
    and m.sep_h == 6 and m.header_line_h == 13)
  local rows = {}
  for i = 1, 6 do rows[i] = Rows.line({ 1, 1, 1 }, "r" .. i) end
  local cols, used = Rows.pack_columns(rows, m, 26, 3)
  check("pack_columns splits rows across columns", cols == 3, cols)
  check("pack_columns reports the used height", used == 26, used)
  local cols2, used2 = Rows.pack_columns(rows, m, 1000, 3)
  check("pack_columns keeps one column when everything fits",
    cols2 == 1 and used2 == 6 * m.line_h, cols2 .. "/" .. used2)
  local cols3 = Rows.pack_columns(rows, m, 13, 3)
  check("pack_columns caps at max_cols", cols3 == 3, cols3)
end

local function stamped_badges(items)
  return ModifierBadges.stamp(items)
end

do
  local card = { config = { center = { key = "j_x" } } }
  local function badges()
    return { { kind = "seal", text = "Gold Seal", key = "Gold" },
      { kind = "sticker", text = "Eternal", key = "eternal" } }
  end
  local current = stamped_badges(badges())
  local l1 = Rows.badge_layout(card, current, FONT, 200, 1, 3, nil)
  local l2 = Rows.badge_layout(card, current, FONT, 200, 1, 3, nil)
  check("badge_layout caches an unchanged producer version for a card", l1 == l2)
  local l3 = Rows.badge_layout(card, current, FONT, 120, 1, 3, nil)
  check("badge_layout keys on width", l3 ~= l1)
  local l1b = Rows.badge_layout(card, current, FONT, 200, 1, 3, nil)
  check("badge_layout keeps both widths cached", l1b == l1)
  local changed = badges()
  changed[2].text = "Rental"
  changed = stamped_badges(changed)
  local l4 = Rows.badge_layout(card, changed, FONT, 200, 1, 3, nil)
  check("badge_layout invalidates when producer version changes", l4 ~= l1)
  local l5 = Rows.badge_layout(nil, stamped_badges(badges()), FONT, 200, 1, 3, nil)
  check("badge_layout without a key still lays out", type(l5) == "table" and l5.rows ~= nil)
end

do
  local card = { config = { center = { key = "j_scaled" } } }
  local badges = stamped_badges({
    { kind = "seal", text = "Gold Seal", key = "Gold" },
    { kind = "sticker", text = "Eternal", key = "eternal" },
    { kind = "edition", text = "Foil", key = "Foil" },
  })
  local W = 482   -- the width both sides measured at 2560x1620
  local m = { line_h = 20, small_line_h = 10, card_line_h = 30, sep_h = 6, header_line_h = 22,
    content_w = 600, badge_w = W, carousel_pad = 0, badge_gap = 2,
    wrap = function() return { "l" } end }
  local row = Rows.shopcard({ 0.6, 0.6, 0.6, 1 }, "card", card, 3, true, 0, badges)

  for _, f in ipairs({ px_font(16), px_font(24) }) do
    m.small_font = f
    for _, unit in ipairs({ 1, 2, 3 }) do
      m.badge_unit = unit
      local drawn = ModifierBadges.layout(badges, f, W, unit, 1)
      local reserved = Rows.height(row, m) - m.card_line_h - m.badge_gap
      local tag = string.format("unit %d, text_h %d", unit, f:getHeight())
      check("a shopcard row reserves the strip it draws at " .. tag,
        reserved >= drawn.height,
        string.format("reserved %d, drawn %d", reserved, drawn.height))
      check("the reservation measures that same strip, not a wider one, at " .. tag,
        reserved == drawn.height,
        string.format("reserved %d, drawn %d", reserved, drawn.height))
    end
  end

  m.small_font, m.badge_unit = FONT, nil
  local d1 = ModifierBadges.layout(badges, FONT, W, 1, 1)
  check("a metrics table with no badge_unit still measures at unit 1",
    Rows.height(row, m) - m.card_line_h - m.badge_gap == d1.height)
end

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local function id(v) return v or 0 end
local stub_font = px_font(24)
local function shop_ctx(o)
  local theme = {
    p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
    ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
    WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
    persona_evil = o.evil or false, persona_neuro = o.neuro or false,
    persona_name = "Neuro", pk = o.evil and "evil" or "neuro",
    font = stub_font, panel_font_small = stub_font, lfont = stub_font,
    lfont_small = stub_font, lfont_title = stub_font,
  }
  local metrics = {
    ln = id, lp_sh = 1, sw = 1920, sh = 1080, U = 6, GUT = 12, ACCENT_W = 3, TRACK = 1,
    p_x = 1920 - 320 - 8, p_y = 120, pw_total = 320,
    card_line_h = 28, sep_h = 6,
    main_side = "right", anchor = o.anchor or "bottom-right", offset_y = 0,
    shop_anchor = "auto", shop_offset_x = 0, shop_offset_y = 0,
  }
  local data = { shop_rows = o.rows, sn = o.sn or (#o.rows > 0 and "SHOP" or "BLIND_SELECT") }
  local draw = {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = noop,
    draw_desc_lines = noop, print_colored_desc = noop,
  }
  return { theme = theme, motion = { now = o.now or 0, pulse = 0.5, dt = o.dt or 0.016,
    shimr = 0.5, shimg = 0.5, shimb = 0.5 }, metrics = metrics, data = data, draw = draw }
end

local function measure(o)
  HS.shop_x_current, HS.shop_y_current = nil, nil
  Shop.draw(shop_ctx(o))
  if HS.shop_y_current == nil then return nil end
  return 1080 - 8 - HS.shop_y_current
end

do
  local scale = 2
  local function ln2(v) local r = math.floor((tonumber(v) or 0) * scale + 0.5); return r < 1 and 1 or r end
  local badges = stamped_badges({
    { kind = "seal", text = "Gold Seal", key = "Gold" },
    { kind = "sticker", text = "Eternal", key = "eternal" },
  })
  local rows = { Rows.shopcard(CLR(), "card", { config = { center = { key = "j_u" } } },
    3, true, nil, badges) }

  local seen_unit, seen_gap, calls = nil, nil, 0
  local real_height, real_layout = Rows.height, Rows.badge_layout
  Rows.height = function(r, m)
    if r.kind == "shopcard" and r.badges and #r.badges > 0 then
      calls = calls + 1
      seen_unit = m.badge_unit
    end
    return real_height(r, m)
  end
  Rows.badge_layout = function(key, b, font, w, gap, max_rows, tr)
    if b and #b > 0 then seen_gap = gap end
    return real_layout(key, b, font, w, gap, max_rows, tr)
  end

  HS.shop_last_visible, HS.shop_h_current, HS.lp_compact = false, nil, false
  local ctx = shop_ctx({ rows = rows, now = 0 })
  ctx.metrics.ln = ln2
  HS.shop_x_current, HS.shop_y_current = nil, nil
  Shop.draw(ctx)

  Rows.height, Rows.badge_layout = real_height, real_layout

  check("the shop panel measures its shopcard rows at all", calls > 0, calls)
  check("the shop panel publishes its own scaled unit to the height reservation",
    seen_unit == ln2(1), string.format("badge_unit=%s, ln(1)=%d", tostring(seen_unit), ln2(1)))
  check("the last strip laid out during the draw used that same unit as its gap",
    seen_gap == ln2(1), string.format("gap=%s, ln(1)=%d", tostring(seen_gap), ln2(1)))
  HS.shop_last_visible, HS.shop_h_current = false, nil
end

do
  local small = {
    Rows.header(CLR(), "Shop: Jokers"),
    Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}),
  }
  local tall = {
    Rows.header(CLR(), "Shop: Jokers"),
    Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}),
    Rows.shopcard(CLR(), "card2", {}, 3, true, nil, {}),
    Rows.shopcard(CLR(), "card3", {}, 3, true, nil, {}),
    Rows.note(CLR(), "note"),
    Rows.sep(),
  }
  HS.shop_last_visible = false
  HS.shop_h_current = nil
  HS.lp_compact = false
  local h0 = measure({ rows = small, now = 0 })
  check("first visible frame snaps to full height", h0 ~= nil and h0 > 0, h0)
  check("snap leaves no residual easing", HS.shop_h_current == nil or math.abs(HS.shop_h_current - (h0 or 0)) < 1)

  local h1 = measure({ rows = tall, now = 0.1, dt = 0.016 })
  local h_target
  do
    local probe = HS.shop_h_current
    HS.shop_h_current = nil
    HS.shop_last_visible = false
    h_target = measure({ rows = tall, now = 0.2 })
    HS.shop_h_current, HS.shop_last_visible = probe, true
  end
  check("height change eases instead of snapping",
    h1 ~= nil and h_target ~= nil and h1 > h0 and h1 < h_target,
    tostring(h0) .. " -> " .. tostring(h1) .. " (target " .. tostring(h_target) .. ")")

  local hc = h1
  for i = 1, 200 do
    hc = measure({ rows = tall, now = 0.2 + i * 0.016, dt = 0.016 })
  end
  check("height converges on the target", hc ~= nil and math.abs(hc - h_target) <= 1,
    tostring(hc) .. " vs " .. tostring(h_target))

  measure({ rows = {}, now = 4 })
  local h2 = measure({ rows = small, now = 5, dt = 0.016 })
  check("a shop that finished leaving snaps to its own height, it does not ease from a stale one",
    h2 ~= nil and math.abs(h2 - h0) <= 1, tostring(h2) .. " vs " .. tostring(h0))
end

local function reset_shop()
  HS.shop_last_visible, HS.shop_h_current = false, nil
  HS.shop_leave_t, HS.shop_leave_snap, HS.shop_leave_game = nil, nil, nil
  HS.shop_appear_t, HS.shop_alpha_last = 0, nil
  HS.shop_reroll_t, HS.shop_reroll_seen, HS.shop_ignite_t = nil, nil, nil
  HS.sz_money_last, HS.sz_money_at = nil, nil
  HS.rr_last, HS.rr_stab_at = nil, nil
  HS.lp_compact = false
  HS.shop_x_current, HS.shop_y_current = nil, nil
end

local function alpha_at(o)
  REC.amax, REC.cur, REC.on = 0, 1, true
  Shop.draw(shop_ctx(o))
  REC.on = false
  return REC.amax
end

do
  local rows = { Rows.header(CLR(), "Shop: Jokers"),
    Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}) }
  local FR = 1 / 60

  local function trace(steps)
    local out, t = {}, 0
    for _, st in ipairs(steps) do
      for _ = 1, st.n do
        local a = alpha_at({ rows = st.rows, sn = st.sn, now = t, dt = FR })
        out[#out + 1] = { t = t, a = a, leave_t = HS.shop_leave_t }
        t = t + FR
      end
    end
    return out
  end

  local function worst_drop(tr, from)
    local worst, at, prev = 0, nil, nil
    for _, s in ipairs(tr) do
      if s.t >= (from or 0) then
        if prev and prev - s.a > worst then worst, at = prev - s.a, s.t end
        prev = s.a
      end
    end
    return worst, at
  end

  reset_shop()
  local parked = trace({
    { n = 30, rows = rows, sn = "SHOP" },
    { n = 18, rows = {}, sn = "PLAY_TAROT" },
    { n = 20, rows = rows, sn = "SHOP" },
  })
  check("the shop settles before the consumable is used", parked[30].a > 0.9, parked[30].a)
  local armed_while_parked = nil
  for i = 31, 48 do
    if parked[i].leave_t then armed_while_parked = parked[i].t end
  end
  check("a consumable used in the shop does not start an exit",
    armed_while_parked == nil, tostring(armed_while_parked))
  local pdrop, pat = worst_drop(parked, 30 * FR)
  check("and nothing on the shop panel dims while the state is parked",
    pdrop <= 0.02, string.format("%.3f at t=%s", pdrop, tostring(pat)))

  reset_shop()
  local rejoin = trace({
    { n = 30, rows = rows, sn = "SHOP" },
    { n = 6, rows = {}, sn = "BLIND_SELECT" },
    { n = 24, rows = rows, sn = "SHOP" },
  })
  local rdrop, rat = worst_drop(rejoin, 30 * FR)
  check("a shop re-entered mid-exit never cuts to a blank frame",
    rdrop <= 0.25, string.format("%.3f at t=%s", rdrop, tostring(rat)))
  check("and it is back at full brightness by the end", rejoin[#rejoin].a > 0.9,
    rejoin[#rejoin].a)
end

do
  local function card(k) return { config = { center = { key = k } } } end
  local function rows_for(cs)
    local out = { Rows.header(CLR(), "Shop: Jokers") }
    for i, c in ipairs(cs) do out[#out + 1] = Rows.shopcard(CLR(), "j" .. i, c, 3, true, nil, {}) end
    return out
  end
  local a, b, c = card("j_a"), card("j_b"), card("j_c")
  local d, e, f = card("j_d"), card("j_e"), card("j_f")

  G.GAME.current_round.reroll_cost_increase = 2
  G.GAME.current_round.free_rerolls = 1
  G.GAME.dollars = 10

  reset_shop()
  _G.G.shop_jokers = { cards = { a, b, c } }
  local rows = rows_for({ a, b, c })
  for i = 0, 20 do measure({ rows = rows, now = i / 60, dt = 1 / 60 }) end
  check("the shop is settled and its jokers are tracked", HS.shop_reroll_seen ~= nil)
  check("no beat has been armed just by sitting there", HS.shop_reroll_t == nil,
    tostring(HS.shop_reroll_t))

  _G.G.shop_jokers.cards = { a, c }
  measure({ rows = rows_for({ a, c }), now = 21 / 60, dt = 1 / 60 })
  check("buying a card is not a reroll", HS.shop_reroll_t == nil, tostring(HS.shop_reroll_t))

  local before_inc = G.GAME.current_round.reroll_cost_increase
  local before_money = G.GAME.dollars
  _G.G.shop_jokers.cards = { d, e, f }
  measure({ rows = rows_for({ d, e, f }), now = 22 / 60, dt = 1 / 60 })
  check("the free reroll really moved no counter",
    G.GAME.current_round.reroll_cost_increase == before_inc and G.GAME.dollars == before_money)
  check("a free reroll still arms the beat", HS.shop_reroll_t == 22 / 60,
    tostring(HS.shop_reroll_t))
  check("and the divider re-lights a beat behind it", HS.shop_ignite_t ~= nil,
    tostring(HS.shop_ignite_t))

  _G.G.shop_jokers = nil
  G.GAME.current_round.free_rerolls = nil
  G.GAME.current_round.reroll_cost_increase = nil
end

do
  local rows = { Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}) }
  reset_shop()
  G.GAME.dollars = 25
  G.GAME.current_round.reroll_cost = 7
  for i = 0, 20 do measure({ rows = rows, now = i / 60, dt = 1 / 60, neuro = true }) end
  check("the shop tracked its opening money and price",
    HS.sz_money_last == 25 and HS.rr_last == 7,
    tostring(HS.sz_money_last) .. "/" .. tostring(HS.rr_last))

  for i = 21, 80 do
    if i == 50 then
      G.GAME.dollars = 40
      G.GAME.current_round.reroll_cost = 5
    end
    measure({ rows = {}, now = i / 60, dt = 1 / 60, neuro = true })
  end
  check("the trackers followed the change while nothing was drawn",
    HS.sz_money_last == 40 and HS.rr_last == 5,
    tostring(HS.sz_money_last) .. "/" .. tostring(HS.rr_last))

  local money_at, rr_at = HS.sz_money_at, HS.rr_stab_at
  measure({ rows = rows, now = 81 / 60, dt = 1 / 60, neuro = true })
  check("and the next shop's first frame announces neither",
    HS.sz_money_at == money_at and HS.rr_stab_at == rr_at,
    string.format("money %s->%s, price %s->%s", tostring(money_at), tostring(HS.sz_money_at),
      tostring(rr_at), tostring(HS.rr_stab_at)))

  G.GAME.dollars = 33
  measure({ rows = rows, now = 82 / 60, dt = 1 / 60, neuro = true })
  check("a change made in front of the player still speaks", HS.sz_money_at == 82 / 60,
    tostring(HS.sz_money_at))
  G.GAME.current_round.reroll_cost = 5
end

do
  HS.shop_last_visible = false
  HS.shop_h_current = nil
  HS.sz_money_last, HS.sz_money_at = nil, nil
  HS.rr_last, HS.rr_stab_at = nil, nil
  local rows = { Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}) }
  G.GAME.dollars = 10
  G.GAME.current_round.reroll_cost = 5
  measure({ rows = rows, now = 0, neuro = true })
  check("money baseline is tracked for neuro", HS.sz_money_last == 10)
  G.GAME.dollars = 4
  measure({ rows = rows, now = 1, neuro = true })
  check("neuro shop registers a money change", HS.sz_money_at == 1, HS.sz_money_at)
  G.GAME.current_round.reroll_cost = 8
  measure({ rows = rows, now = 2, neuro = true })
  check("neuro shop registers a reroll price change", HS.rr_stab_at == 2, HS.rr_stab_at)

  HS.sz_money_last, HS.sz_money_at = nil, nil
  HS.rr_last, HS.rr_stab_at = nil, nil
  HS.shop_last_visible, HS.shop_h_current = false, nil
  G.GAME.dollars = 9
  measure({ rows = rows, now = 3, evil = true })
  G.GAME.dollars = 2
  measure({ rows = rows, now = 4, evil = true })
  check("evil shop still registers a money change", HS.sz_money_at == 4, HS.sz_money_at)
end

do
  local RP = require("render.panels.right_panel")
  local IMGF = px_font(20)
  local function rp_ctx(evil, neuro)
    local theme = {
      p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
      ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
      WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
      persona_evil = evil, persona_neuro = neuro, persona_name = "Neuro", pk = "neuro",
      boss = true, is_round_eval = false,
      font = IMGF, panel_font_small = IMGF, rfont = IMGF, rfont_small = IMGF,
      lfont = IMGF, lfont_small = IMGF, rp_font = IMGF,
      rfont_title = IMGF, rfont_display = IMGF, lfont_title = IMGF,
      font_title = IMGF, font_display = IMGF,
    }
    local metrics = {
      rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
      total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
      rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
      r_text_h = 12, r_small_text_h = 10,
      c_text_h = 12, c_small_text_h = 10,
      rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
      main_slide_dir = 1,
    }
    local data = {
      panel_rows = { Rows.header(CLR(), "H"), Rows.line(CLR(), "l"), Rows.sep() },
      sn = "BLIND_SELECT", state_label = "THINKING", is_thinking = true,
      logo = nil, logo_w = 0, logo_h = 0, logo_scale = 1,
      quip_display = "hi", footer_emote = nil, footer_is_emote = false, footer_fade = 1,
      footer_prev_emote = false, footer_prev_quip = "", footer_legend = false,
      footer_prev_legend = false,
      footer_legend_meta = false,
      footer_prev_legend_meta = false,
      showcase_alpha = 0,
    }
    local draw = {
      trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop,
      draw_desc_lines = noop, print_colored_desc = noop,
      row_h = function() return 16 end,
    }
    return { theme = theme, motion = { now = 2.5, pulse = 0.5, dt = 0.016,
      shimr = 0.5, shimg = 0.5, shimb = 0.5 }, metrics = metrics, data = data, draw = draw }
  end
  local ok_all = true
  local err_first
  for _, combo in ipairs({ { false, false }, { true, false }, { false, true } }) do
    for _, fn in ipairs({ RP.frame, RP.header, RP.rows, RP.footer }) do
      local ok, err = pcall(fn, rp_ctx(combo[1], combo[2]))
      if not ok then ok_all = false; err_first = err_first or err end
    end
    HS.shop_last_visible, HS.shop_h_current = false, nil
    local ok2, err2 = pcall(Shop.draw, shop_ctx({
      rows = { Rows.shopcard(CLR(), "card", {}, 3, true, nil, {}) },
      now = 2.5, evil = combo[1], neuro = combo[2] }))
    if not ok2 then ok_all = false; err_first = err_first or err2 end
  end
  check("every panel entry point draws cleanly for every persona combo", ok_all, err_first)
end

do
  local latch, cols = Rows.latch_columns(nil, 2, "1920x1080", 3)
  check("latch: a fresh signature takes the measured count", cols == 2, cols)

  latch, cols = Rows.latch_columns(latch, 1, "1920x1080", 3)
  check("latch: losing rows does not narrow the panel", cols == 2, cols)

  latch, cols = Rows.latch_columns(latch, 3, "1920x1080", 3)
  check("latch: content that genuinely outgrew the panel still widens it", cols == 3, cols)

  latch, cols = Rows.latch_columns(latch, 4, "1920x1080", 3)
  check("latch: the cap still holds", cols == 3, cols)

  latch, cols = Rows.latch_columns(latch, 1, "1280x720", 3)
  check("latch: a new viewport signature starts over", cols == 1, cols)

  local _, capped = Rows.latch_columns(nil, 3, "narrow", 1)
  check("latch: a viewport that fits one column can never latch two", capped == 1, capped)
end

done()
