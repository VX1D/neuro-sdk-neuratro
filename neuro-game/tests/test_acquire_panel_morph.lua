
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 7 end,
  getHeight = function() return 13 end,
}
local function noop() end
local RECTS, PRINTED = {}, {}
local COL = { 1, 1, 1, 1 }
local function record_rect(mode, x, y, w, h, rad)
  RECTS[#RECTS + 1] = { mode = mode, x = x, y = y, w = w, h = h, rad = rad or 0, a = COL[4] or 1 }
end
local IMG = { getWidth = function() return 71 end, getHeight = function() return 95 end,
  getDimensions = function() return 71, 95 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1280 end,
  getHeight = function() return 720 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  setColor = function(r, g, b, a)
    if type(r) == "table" then COL = { r[1], r[2], r[3], r[4] or g or 1 }
    else COL = { r, g, b, a or 1 } end
  end,
  getColor = function() return COL[1], COL[2], COL[3], COL[4] end,
  print = function(t, x, y) PRINTED[#PRINTED + 1] = { text = tostring(t), x = x, y = y, a = COL[4] or 1 } end,
  rectangle = record_rect,
  circle = noop,
  getScissor = function() return nil end,
  setScissor = noop,
  intersectScissor = noop,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true, purchase_showcase_queue = {},
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("acquire panel morph")

local Prims = require("hud.prims")
local Motion = Prims.Motion
local S = require("hud.state")
local Showcase = require("hud.showcase")
local Acquire = require("render.panels.acquire")
check("the acquire panel owns both receipt drawing and card pairing",
  type(Acquire.draw) == "function" and type(Acquire.pair) == "function")
local TL = Acquire.TL
G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }
G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95 }

local DT = 1 / 60

local function card_of(name, key, set)
  return {
    config = { center = { key = key or "j_blueprint", set = set or "Joker", atlas = "FIX71",
      pos = { x = 0, y = 0 }, name = name or "Blueprint", rarity = 3 } },
    ability = { name = name or "Blueprint", set = set or "Joker" }, cost = 10,
  }
end
local CARD_A, CARD_B = card_of("Blueprint", "j_blueprint"), card_of("Baron", "j_baron")
local CARD_V = card_of("Grabber", "v_grabber", "Voucher")

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = { 1, 1, 1, 1 }, CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
  cfont = FONT, cfont_title = FONT, cfont_small = FONT, cfont_micro = FONT,
}

local function ctx_for(persona, now, dt, sn)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = persona == "evil", persona == "neuro"
  theme.pk = persona
  return {
    theme = theme,
    motion = { now = now, pulse = 0.5, dt = dt, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = { rn = function(v) return v end, ln = function(v) return v end,
      cn = function(v) return v end, rp_sh = 1, lp_sh = 1,
      sw = 1280, sh = 720, U = 4, GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 2, TRACK_SM = 1,
      text_h = 13 },
    data = { sn = sn or "SHOP", state_name = sn or "SHOP", pack_rows = {} },
    draw = {
      trunc = function(s) return s end,
      wrapped_lines = function(s) return { tostring(s) } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end,
    },
    center_max_w = 640, center_cx = 400, center_top_y = 8,
  }
end

local function panel_cluster(rects)
  local lines = {}
  for _, r in ipairs(rects) do
    if r.mode == "line" and r.w and r.w > 100 and r.h and r.h > 25 then lines[#lines + 1] = r end
  end
  if #lines == 0 then return 0, nil end
  local clusters = 0
  local main
  for _, r in ipairs(lines) do
    local cxr, cyr = r.x + r.w / 2, r.y + r.h / 2
    local matched = false
    if main then
      local mcx, mcy = main.x + main.w / 2, main.y + main.h / 2
      if math.abs(cxr - mcx) <= 6 and math.abs(cyr - mcy) <= 6 then matched = true end
    end
    if not matched then
      clusters = clusters + 1
      if not main or r.a > main.a then main = r end
    end
  end
  local n = 0
  local seen = {}
  for _, r in ipairs(lines) do
    local mcx, mcy = main.x + main.w / 2, main.y + main.h / 2
    local key = (math.abs(r.x + r.w / 2 - mcx) <= 6 and math.abs(r.y + r.h / 2 - mcy) <= 6)
      and "main" or string.format("%.0f_%.0f", r.x, r.y)
    if not seen[key] then seen[key] = true; n = n + 1 end
  end
  return n, main
end

local function name_prints(name)
  local n = 0
  for _, p in ipairs(PRINTED) do
    if p.text == name then n = n + 1 end
  end
  return n
end

local function reset_world()
  Showcase.reset_run_state()
  G.NEURO.purchase_showcase_queue = {}
end

local function sim(opts)
  opts = opts or {}
  reset_world()
  Showcase.enqueue_purchase({ card = opts.card or CARD_A, name = "Blueprint", cost = 10,
    area = opts.area or "shop_jokers" })
  Showcase.update_buy(0)
  local frames = {}
  local now, i = 0, 0
  local t_end = opts.t_end or 2.2
  while now <= t_end + 1e-9 do
    G.TIMERS.REAL = now
    if opts.showcase_at and not S.joker_showcase and now >= opts.showcase_at - 1e-9 then
      S.joker_showcase = { card = opts.showcase_card or opts.card or CARD_A,
        label = "NEW JOKER", started = now }
    end
    if opts.at then opts.at(now, i) end
    Showcase.update_joker(now)
    Showcase.update_buy(now)
    if opts.repin and S.buy_showcase then S.buy_showcase.started = now - opts.repin end
    RECTS, PRINTED = {}, {}
    local ctx = ctx_for(opts.persona or "hiyori", now, i == 0 and 0 or DT, opts.sn)
    Acquire.draw(ctx)
    local n_panels, main = panel_cluster(RECTS)
    local sc = S.buy_showcase
    frames[#frames + 1] = {
      t = now,
      n_panels = n_panels,
      panel = main,
      names = name_prints("Blueprint") + name_prints("Baron") + name_prints("Grabber"),
      morph_at = sc and sc._morph_at or nil,
      Lf = sc and sc._Lf or nil,
      sc_live = sc ~= nil,
      sc_card = sc and sc.card or nil,
      js_live = S.joker_showcase ~= nil,
      js_morphed = S.joker_showcase and S.joker_showcase._morphed or false,
      advance = ctx.center_top_y - 8,
    }
    now = now + DT
    i = i + 1
  end
  reset_world()
  return frames
end

local function at(frames, t)
  local best
  for _, f in ipairs(frames) do
    if not best or math.abs(f.t - t) < math.abs(best.t - t) then best = f end
  end
  return best
end

check("1a soft timeline", TL.soft.IN == 0.25 and TL.soft.HOLD == 0.45 and TL.soft.MORPH == 0.28
  and TL.soft.FX_LEAD == 0.10 and TL.soft.OUT == 0.40)
do
  local ok, neuro = pcall(require, "render.panels.acquire_neuro")
  check("1f neuro persona file loads", ok and type(neuro) == "table")
  local ok_e, evil = pcall(require, "render.panels.acquire_evil")
  check("1f2 evil persona file loads", ok_e and type(evil) == "table")
  if ok and ok_e then
    reset_world()
    Showcase.enqueue_purchase({ card = CARD_A, name = "x", area = "shop_jokers", cost = 1, at = 0 })
    Showcase.update_buy(0)
    check("1g a filed receipt reads as in flight regardless of which persona's timeline is active",
      Showcase.card_in_flight(CARD_A) == true)
    S.buy_showcase = { card = CARD_B, name = "x", area = "shop_jokers", cost = 1, started = 0 }
    check("1g2 occupying the live slot by hand is not a claim", Showcase.card_in_flight(CARD_B) == false)
    S.buy_showcase = nil
    check("1g3 and dropping the live slot by hand is not a retirement",
      Showcase.card_in_flight(CARD_A) == true)
    reset_world()
    Showcase.enqueue_purchase({ card = CARD_A, name = "x", area = "shop_jokers", cost = 1, at = 0 })
    Showcase.update_buy(0)
    Showcase.retire_receipt(0)
    check("1i the receipt lane's own retirement (what the morph's cleanup calls) clears in-flight" ..
      " immediately, on no persona's clock",
      Showcase.card_in_flight(CARD_A) == false)
    reset_world()

    local WEYL_STEP = 0.6180339887498949
    local function sample_monotonic(fn, n)
      local ts = { 0, 1 }
      for i = 1, n do ts[#ts + 1] = (i * WEYL_STEP) % 1 end
      table.sort(ts)
      local mono = true
      local prev = fn(ts[1])
      for i = 2, #ts do
        local v = fn(ts[i])
        if v < prev - 1e-9 then mono = false end
        prev = v
      end
      return mono
    end
    check("1h the evil ease is monotonic across the whole morph",
      sample_monotonic(evil.ease, 400) and evil.ease(0) <= 1e-9 and evil.ease(1) >= 1 - 1e-9)
    check("1h2 the hiyori ease (smoothstep01) is monotonic across the whole morph",
      sample_monotonic(Prims.smoothstep01, 400)
      and Prims.smoothstep01(0) <= 1e-9 and Prims.smoothstep01(1) >= 1 - 1e-9)
    check("1h3 the neuro ease (ease_out_cubic) is monotonic across the whole morph",
      type(neuro.ease) == "function" and sample_monotonic(neuro.ease, 400)
      and neuro.ease(0) <= 1e-9 and neuro.ease(1) >= 1 - 1e-9)
  end
end

do
  reset_world()
  check("2a no receipt means no pair", Acquire.pair(0) == false)
  S.buy_showcase = { card = CARD_A, name = "x", area = "shop_jokers", cost = 1, started = 0 }
  check("2b a receipt with no showcase never pairs", Acquire.pair(0.2) == false)
  S.joker_showcase = { card = CARD_B, label = "NEW JOKER", started = 0.1 }
  check("2c a showcase for a different card never pairs", Acquire.pair(0.2) == false)
  S.joker_showcase = { card = CARD_A, label = "NEW JOKER", started = 0.1 }
  local paired, morph_at = Acquire.pair(0.2)
  check("2d the same card table pairs", paired == true)
  check("2e morph_at = max(started + HOLD, pair_at)", morph_at == 0.45, tostring(morph_at))
  local p2, m2 = Acquire.pair(1.4)
  check("2f an acquired pair survives past the latch", p2 == true and m2 == 0.45)

  S.buy_showcase = { card = CARD_A, name = "x", area = "shop_jokers", cost = 1, started = 0 }
  check("2g a showcase first seen after the latch never pairs",
    Acquire.pair(TL.LATCH + 0.05) == false)
  S.buy_showcase = { card = CARD_A, name = "x", area = "shop_jokers", cost = 1, started = 0 }
  local pl = Acquire.pair(TL.LATCH - 0.10)
  check("2h a showcase inside the latch still pairs", pl == true)

  S.buy_showcase = { card = CARD_A, name = "x", area = "shop_jokers", cost = 1, started = 0,
    swap_started = 0.1 }
  check("2i a pending swap blocks the pair", Acquire.pair(0.2) == false)
  S.buy_showcase = { card = CARD_A, name = "x", area = "shop_jokers", cost = 1, started = 0 }
  G.NEURO.purchase_showcase_queue = { { name = "q" } }
  check("2j a pending queue no longer blocks the pair", Acquire.pair(0.2) == true)
  G.NEURO.purchase_showcase_queue = {}

  for tag in pairs(Acquire.RECEIPT_ONLY) do
    S.buy_showcase = { card = CARD_A, name = "x", area = tag, cost = 1, started = 0 }
    check("2k receipt-only verb " .. tag .. " never pairs", Acquire.pair(0.2) == false)
  end
  S.buy_showcase = { card = CARD_V, name = "Grabber", area = "shop_vouchers", cost = 10, started = 0 }
  S.joker_showcase = { card = CARD_V, label = "VOUCHER", started = 0.1 }
  check("2l a redeemed voucher pairs by the very card table", Acquire.pair(0.2) == true)
  S.joker_showcase = { card = card_of("Clearance Sale", "v_clearance", "Voucher"),
    label = "VOUCHER", started = 0.1 }
  check("2m a showcase for a different voucher never pairs", Acquire.pair(0.2) == false)
  reset_world()
end

for _, p in ipairs({ "hiyori", "neuro", "evil" }) do
  local tl = (p == "neuro") and require("render.panels.acquire_neuro").TL
    or (p == "evil") and require("render.panels.acquire_evil").TL
    or TL.soft
  local fr = sim({ persona = p, showcase_at = 0.10 })
  local morph_at = at(fr, 1.0).morph_at or at(fr, tl.HOLD + 0.05).morph_at
  check(p .. " 3a the morph commits at started + HOLD",
    morph_at ~= nil and math.abs(morph_at - tl.HOLD) <= DT + 1e-9, tostring(morph_at))
  local m_end = (morph_at or tl.HOLD) + tl.MORPH
  local bad_panels, bad_names, bad_top = 0, 0, 0
  local prev_w, prev_h, nonmono = nil, nil, 0
  local Lf0
  for _, f in ipairs(fr) do
    if f.panel then
      if f.n_panels > 1 then bad_panels = bad_panels + 1 end
      if f.names > 2 then bad_names = bad_names + 1 end
      if math.abs((f.panel.y + 1) - 8) > 1.5 then bad_top = bad_top + 1 end
    end
    if f.t >= (morph_at or 0) and f.t <= m_end and f.panel then
      if prev_w and (f.panel.w < prev_w - 0.01 or f.panel.h < prev_h - 0.01) then
        nonmono = nonmono + 1
      end
      prev_w, prev_h = f.panel.w, f.panel.h
      if f.Lf then
        Lf0 = Lf0 or f.Lf
        if f.Lf ~= Lf0 then nonmono = nonmono + 1000 end
      end
    end
  end
  check(p .. " 3b exactly one panel outline in every frame", bad_panels == 0, bad_panels)
  check(p .. " 3c the card name is printed once per frame", bad_names == 0, bad_names)
  check(p .. " 3d the top edge never moves", bad_top == 0, bad_top)
  check(p .. " 3e width and height grow monotonically through the morph", nonmono == 0, nonmono)
  check(p .. " 3f the full layout is measured once and frozen", Lf0 ~= nil)
  local before = at(fr, morph_at and morph_at - DT * 2 or 0.4)
  local after = at(fr, m_end + DT * 2)
  check(p .. " 3g the panel is wider and taller after the morph",
    before.panel and after.panel and after.panel.w > before.panel.w + 40
    and after.panel.h > before.panel.h + 20,
    before.panel and after.panel and (before.panel.w .. "->" .. after.panel.w))
  check(p .. " 3h the receipt object is gone once the morph completes",
    after.sc_live == false and after.js_live == true and after.js_morphed == true)
  check(p .. " 3i the showcase keeps the column after the receipt life would have ended",
    at(fr, 2.1).js_live == true and at(fr, 2.1).panel ~= nil)
end

local LAND = 0.05
for _, gap in ipairs({ 0.05, 0.20, 0.40, 0.60 }) do
  reset_world()
  G.jokers.cards = {}
  S.known_joker_refs = nil
  Showcase.update_joker(0)
  Showcase.enqueue_purchase({ card = CARD_A, name = "Blueprint", cost = 10, area = "shop_jokers" })
  Showcase.update_buy(0)

  local a_landed, b_bought, b_landed = false, false, false
  local episodes, morphed, prev = {}, {}, nil
  local now, i = 0, 0
  while now <= 12.0 + 1e-9 do
    G.TIMERS.REAL = now
    if not a_landed and now >= LAND - 1e-9 then
      a_landed = true
      G.jokers.cards[#G.jokers.cards + 1] = CARD_A
    end
    if not b_bought and now >= gap - 1e-9 then
      b_bought = true
      Showcase.enqueue_purchase({ card = CARD_B, name = "Baron", cost = 4, area = "shop_jokers" })
    end
    if b_bought and not b_landed and now >= gap + LAND - 1e-9 then
      b_landed = true
      G.jokers.cards[#G.jokers.cards + 1] = CARD_B
    end
    Showcase.update_joker(now)
    Showcase.update_buy(now)
    RECTS, PRINTED = {}, {}
    Acquire.draw(ctx_for("hiyori", now, i == 0 and 0 or DT))
    local sc = S.buy_showcase
    local key = sc and sc.card or nil
    if key ~= prev then
      if key then episodes[key] = (episodes[key] or 0) + 1 end
      prev = key
    end
    if sc and sc._morph_at and key then morphed[key] = true end
    now = now + DT
    i = i + 1
  end
  reset_world()

  check(("10a gap=%.2f the first receipt runs exactly once"):format(gap),
    (episodes[CARD_A] or 0) == 1, episodes[CARD_A])
  check(("10b gap=%.2f the second receipt runs exactly once"):format(gap),
    (episodes[CARD_B] or 0) == 1, episodes[CARD_B])
  check(("10c gap=%.2f both purchases reach the morph"):format(gap),
    morphed[CARD_A] == true and morphed[CARD_B] == true,
    tostring(morphed[CARD_A]) .. "/" .. tostring(morphed[CARD_B]))
end

for tag in pairs(Acquire.RECEIPT_ONLY) do
  local fr = sim({ area = tag, showcase_at = 0.10, t_end = 2.0 })
  local morphs = 0
  for _, f in ipairs(fr) do if f.morph_at then morphs = morphs + 1 end end
  check("4a " .. tag .. " never morphs even with a same-card showcase", morphs == 0, morphs)
end
do
  local fr = sim({ t_end = 2.0 })
  local morphs = 0
  for _, f in ipairs(fr) do if f.morph_at then morphs = morphs + 1 end end
  check("4b a receipt with no showcase never morphs and lives its receipt life",
    morphs == 0 and at(fr, 1.7).sc_live == true and at(fr, 1.9).sc_live == false)
  local late = sim({ showcase_at = TL.LATCH + 0.05, t_end = 2.0 })
  morphs = 0
  for _, f in ipairs(late) do if f.morph_at then morphs = morphs + 1 end end
  check("4c a showcase arriving after the latch never morphs", morphs == 0, morphs)
end

do
  local fired = false
  local fr = sim({
    showcase_at = 0.10, t_end = 4.5,
    at = function(now)
      if not fired and now >= 1.0 then
        fired = true
        Showcase.enqueue_purchase({ card = CARD_B, name = "Baron", cost = 4, area = "shop_jokers" })
      end
    end,
  })
  local m_end = TL.soft.HOLD + TL.soft.MORPH
  check("5a a purchase landing mid-FULL does not resurrect a second panel",
    (function()
      for _, f in ipairs(fr) do if f.n_panels > 1 then return false end end
      return true
    end)())
  local out_by
  for _, f in ipairs(fr) do
    if f.t > 1.0 and not f.js_live and not out_by then out_by = f.t end
  end
  check("5b a pending queue shortens FULL to its floor",
    out_by ~= nil and out_by <= m_end + Acquire.TL.FULL_MIN + TL.soft.OUT + 0.35,
    tostring(out_by))
  check("5c the queued receipt reaches the screen after the showcase leaves",
    (function()
      for _, f in ipairs(fr) do
        if out_by and f.t > out_by and f.sc_live and f.panel then return true end
      end
      return false
    end)())
end
do
  local fired = false
  local fr = sim({
    t_end = 2.0,
    at = function(now)
      if not fired and now >= 0.2 then
        fired = true
        Showcase.enqueue_purchase({ card = CARD_B, name = "Baron", cost = 4, area = "shop_jokers" })
      end
    end,
  })
  local morphs = 0
  for _, f in ipairs(fr) do if f.morph_at then morphs = morphs + 1 end end
  check("5d a receipt with a queued successor cross-cuts instead of morphing", morphs == 0)
  check("5e the cross-cut swap still happens on the receipt clock",
    at(fr, 1.3).sc_live == true and at(fr, 1.3).panel ~= nil)
end

do
  reset_world()
  S.joker_showcase = { card = CARD_A, label = "NEW JOKER", started = 0 }
  Showcase.enqueue_purchase({ card = CARD_B, name = "Baron", cost = 0, area = "sell" })
  local two = 0
  local receipt_after
  for i = 0, 240 do
    local now = 0.5 + i * DT
    G.TIMERS.REAL = now
    Showcase.update_joker(now)
    Showcase.update_buy(now)
    RECTS, PRINTED = {}, {}
    local ctx = ctx_for("hiyori", now, DT)
    Acquire.draw(ctx)
    local n = panel_cluster(RECTS)
    if n > 1 then two = two + 1 end
    if not S.joker_showcase and S.buy_showcase and n == 1 then receipt_after = true end
  end
  check("6a a sell receipt and a live showcase never stack two panels", two == 0, two)
  check("6b the deferred receipt plays once the showcase leaves", receipt_after == true)
  reset_world()
end

do
  local ok_n, neuro = pcall(require, "render.panels.acquire_neuro")
  local PTL = (ok_n and neuro.TL) or TL.soft
  local fr = sim({ persona = "neuro", showcase_at = 0.10 })
  local morph_at = at(fr, PTL.HOLD + 0.05).morph_at
  check("7a the persona timeline still morphs", morph_at ~= nil)
  check("7b it commits on the persona hold",
    morph_at and math.abs(morph_at - PTL.HOLD) <= DT + 1e-9, tostring(morph_at))
  check("7c it finishes on the persona span",
    at(fr, PTL.HOLD + PTL.MORPH + DT * 2).sc_live == false)
  local bad = 0
  for _, f in ipairs(fr) do if f.n_panels > 1 then bad = bad + 1 end end
  check("7d it keeps one outline", bad == 0, bad)
  local m_end = (morph_at or PTL.HOLD) + PTL.MORPH
  local prev_w, prev_h, nonmono = nil, nil, 0
  for _, f in ipairs(fr) do
    if f.t >= (morph_at or 0) and f.t <= m_end and f.panel then
      if prev_w and (f.panel.w < prev_w - 0.01 or f.panel.h < prev_h - 0.01) then
        nonmono = nonmono + 1
      end
      prev_w, prev_h = f.panel.w, f.panel.h
    end
  end
  check("7e width and height grow monotonically through the morph", nonmono == 0, nonmono)
end

do
  local fr = sim({ persona = "neuro", showcase_at = 0.05, t_end = 1.6, repin = 0.30 })
  local morphs = 0
  for _, f in ipairs(fr) do if f.morph_at then morphs = morphs + 1 end end
  check("8a a pinned receipt never morphs", morphs == 0, morphs)
  check("8b a pinned receipt keeps its receipt box",
    at(fr, 1.5).panel ~= nil and at(fr, 1.5).panel.h < 70, at(fr, 1.5).panel and at(fr, 1.5).panel.h)
end

do
  reset_world()
  S.joker_showcase = { card = CARD_A, label = "NEW JOKER", started = 0 }
  local ctx = ctx_for("hiyori", 6.0, DT, "TAROT_PACK")
  ctx.data.pack_rows = { cards = { { card = CARD_B } } }
  G.TIMERS.REAL = 6.0
  RECTS, PRINTED = {}, {}
  Acquire.draw(ctx)
  Showcase.update_joker(6.0)
  check("9a a pack in progress holds the showcase alive far past its span",
    S.joker_showcase ~= nil and S.joker_showcase.hold_elapsed ~= nil)
  local released_at
  for i = 1, 200 do
    local t = 6.0 + i * DT
    Showcase.update_joker(t)
    if not released_at and S.joker_showcase == nil then released_at = t end
  end
  check("9b a stale freeze note releases the corridor instead of holding it forever",
    released_at ~= nil and released_at <= 6.0 + 0.25 + Showcase.JOKER_SHOWCASE_FADE_OUT + DT * 2,
    tostring(released_at))
  reset_world()
end

done()
