rawset(_G, "NEURO_TEST", true)

local function stub_table()
  return setmetatable({}, { __index = function() return function() return nil end end })
end
love = setmetatable({ timer = { getTime = function() return 0 end }, graphics = stub_table() },
  { __index = function() return function() return nil end end })
_G.G = { NEURO = { persona = "evil" }, C = nil, SETTINGS = {} }
_G.SMODS = { current_mod = { config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end, Mods = {} }

local check, done = require("tests.helpers").harness("palette contrast")
local Col = require("tests.colorimetry")
local Palette = require("render.palette")
local PersonaPalette = require("render.persona_palette")
local Cards = require("hud.cards")
local Prims = require("hud.prims")
local PC = PersonaPalette._test.colors

local CARD_W = 2.4 * 35 / 41
local CARD_H = 2.4 * 47 / 41
local TILESIZE, TILESCALE = 20, 3.65
local RESOLUTIONS = {
  { "1280x720", 1.0 },
  { "1920x1080", 1.5 },
}

local function card_px(scale) return CARD_W * TILESCALE * TILESIZE * scale end
local function card_h_px(scale) return CARD_H * TILESCALE * TILESIZE * scale end

local function red_fields(pk)
  local c = PC[pk]
  return {
    { "BACKGROUND.L", c.BACKGROUND.L },
    { "BLIND.Boss", c.BLIND.Boss },
    { "DYN_UI.BOSS_MAIN", c.DYN_UI.BOSS_MAIN },
  }
end

local function worst_after_transport(bg, colour, line_w)
  local W, base = 40, 16
  local worst_t, worst_i, worst_c = math.huge, math.huge, math.huge
  for phase = 0, 3 do
    local at = base + phase
    local img = {}
    for y = 0, 1 do
      for x = 0, W - 1 do
        local c = (x >= at and x < at + line_w) and colour or bg
        img[y * W + x + 1] = { c[1], c[2], c[3] }
      end
    end
    local out = Col.chroma_subsample(img, W, 2)
    for x = at, at + line_w - 1 do
      local t, i, ch = Col.delta_itp(out[x + 1], bg)
      if t < worst_t then worst_t = t end
      if i < worst_i then worst_i = i end
      if ch < worst_c then worst_c = ch end
    end
  end
  return worst_t, worst_i, worst_c
end

local P = Palette.PALETTES.evil
local NP = Palette.PALETTES.neuro
local A = Cards.evil_alphas

local DE_MIN = Col.delta_itp(P.PANEL_BG, P.ROW_BG)
print(string.format("      note  threshold derived from panel row bands: dE_ITP >= %.1f", DE_MIN))

local NEURO_WASH_MAX = 12.6
local HUE_MIN_SEPARATION = 30
local SCRIM_INTENSITY_SHARE = 0.85
local SCRIM_BLACK = { 0, 0, 0 }
local SCRIM = Cards.evil_scrim

local function scrim_over(bg)
  return Col.over_alpha(SCRIM_BLACK, SCRIM[1][3], bg)
end

local function blend(mode, colour, alpha, bg)
  if mode == "add" then return Col.over_add(colour, alpha, bg) end
  return Col.over_alpha(colour, alpha, bg)
end

local function px(v, cap)
  local n = math.max(1, math.floor(v + 0.5))
  if cap and n > cap then n = cap end
  return n
end

local function hue_deg(c)
  local r, g, b = c[1], c[2], c[3]
  local mx = math.max(r, g, b)
  local mn = math.min(r, g, b)
  local d = mx - mn
  if d <= 0 then return 0 end
  local h
  if mx == r then h = ((g - b) / d) % 6
  elseif mx == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  return (h * 60) % 360
end

local function hue_gap(a, b)
  local d = math.abs(hue_deg(a) - hue_deg(b)) % 360
  if d > 180 then d = 360 - d end
  return d
end

local function evil_elements(w)
  local bw = px(w * 0.030 * 0.5)
  return {
    { "border gold", P.D_GOLD, "alpha", A.border, bw, true },
    { "border shimmer end", P.D_ORANGE, "alpha", A.border, bw, true },
    { "corner arms", P.D_GOLD, "alpha", A.arms, px(w * 0.028 * 0.5), true },
    { "mark commit", P.D_GOLD, "add", A.mark + A.mark_commit, px(w * 0.13, 20), false },
  }
end

local function evil_details(w, h)
  local uu = w * 0.028
  local rise = Prims.ease_out_cubic01(0.5)
  local spark = { 1, 0.62 - 0.40 * rise, 0.16 }
  return {
    { "mark core", P.D_WHITE, "add", A.mark_core_commit, px(w * 0.13 * 0.46, 20) },
    { "pool spark", spark, "add", 0.5 * 0.85, math.max(1, math.floor(uu * 0.75)) },
    { "hot bar commit", P.D_WHITE, "add", A.bar_commit, px(h * 0.05) },
  }
end

local function evil_washes()
  return {
    { "identity wash", P.GLOW, "alpha", A.wash },
    { "ember pool", P.D_ORANGE, "add", A.pool },
  }
end

for _, res in ipairs(RESOLUTIONS) do
  local label, scale = res[1], res[2]
  local w = card_px(scale)
  for _, el in ipairs(evil_elements(w)) do
    local name, colour, mode, alpha, lw, on_scrim = el[1], el[2], el[3], el[4], el[5], el[6]
    for _, field in ipairs(red_fields("evil")) do
      local fname, bg = field[1], field[2]
      local seat = fname
      if on_scrim then
        bg = scrim_over(bg)
        seat = "the densest scrim band over " .. fname .. ", stroke half that clears the card"
      end
      local t = worst_after_transport(bg, blend(mode, colour, alpha, bg), lw)
      check(string.format("evil %s survives 4:2:0 on %s at %s (%dpx, dE %.1f >= %.1f)",
        name, seat, label, lw, t, DE_MIN), t >= DE_MIN)
    end
  end
end

do
  local w = card_px(1.0)
  for _, el in ipairs(evil_details(w, card_h_px(1.0))) do
    local name, colour, mode, alpha, lw = el[1], el[2], el[3], el[4], el[5]
    for _, field in ipairs(red_fields("evil")) do
      local fname, bg = field[1], field[2]
      local t = worst_after_transport(bg, blend(mode, colour, alpha, bg), lw)
      check(string.format("evil detail %s survives 4:2:0 on %s (%dpx, dE %.1f >= %.1f)",
        name, fname, lw, t, DE_MIN), t >= DE_MIN)
    end
  end
end

do
  for _, el in ipairs(evil_washes()) do
    local name, colour, mode, alpha = el[1], el[2], el[3], el[4]
    for _, field in ipairs(red_fields("evil")) do
      local fname, bg = field[1], field[2]
      local d = Col.delta_itp(blend(mode, colour, alpha, bg), bg)
      check(string.format("evil %s stays below the signal floor on %s (dE %.1f < %.1f)",
        name, fname, d, DE_MIN), d < DE_MIN)
      check(string.format("evil %s stays inside neuro's wash envelope on %s (dE %.1f <= %.1f)",
        name, fname, d, NEURO_WASH_MAX), d <= NEURO_WASH_MAX)
    end
  end
end

do
  check(string.format("the scrim starts at the card outline and never reaches inside it (inner %.2fuu)",
    SCRIM[1][1]), SCRIM[1][1] == 0)
  for i = 1, #SCRIM do
    local band = SCRIM[i]
    check(string.format("scrim band %d has positive width (%.2fuu -> %.2fuu)", i, band[1], band[2]),
      band[2] > band[1])
    if i > 1 then
      check(string.format("scrim band %d starts where band %d ends (%.2fuu vs %.2fuu)",
        i, i - 1, band[1], SCRIM[i - 1][2]), band[1] == SCRIM[i - 1][2])
      check(string.format("scrim band %d is lighter than the band inside it (%.4f < %.4f)",
        i, band[3], SCRIM[i - 1][3]), band[3] < SCRIM[i - 1][3])
    end
  end

  local GW, GH = 150, 200
  local gpad = GW * 0.05
  local GX0, GY0 = -gpad, -gpad
  local GBW, GBH = GW + gpad * 2, GH + gpad * 2
  local shots = {}
  local cur, curw = { 0, 0, 0, 1 }, 1
  local recorder = setmetatable({
    setColor = function(r, g, b, al) cur = { r, g, b, al or 1 } end,
    setLineWidth = function(v) curw = v end,
    rectangle = function(mode, x, y, rw, rh)
      shots[#shots + 1] = { mode = mode, x = x, y = y, w = rw, h = rh, lw = curw,
        r = cur[1], g = cur[2], b = cur[3], a = cur[4] }
    end,
  }, { __index = function() return function() return nil end end })
  local saved = love.graphics
  love.graphics = recorder
  local painted = pcall(Cards.glow_painters.evil, P, 1, GW, GH, GX0, GY0, GBW, GBH, 0.5, 1, 0)
  love.graphics = saved
  check("the evil glow paints a full commit frame without error", painted)

  local blacks = {}
  for _, sh in ipairs(shots) do
    if sh.r == 0 and sh.g == 0 and sh.b == 0 and (sh.a or 0) > 0 then
      blacks[#blacks + 1] = sh
    end
  end
  check(string.format("the glow paints one black band per scrim entry (%d of %d)", #blacks, #SCRIM),
    #blacks == #SCRIM)
  for i, sh in ipairs(blacks) do
    check(string.format("scrim band %d is a stroke, never a fill over the card (%s)", i, tostring(sh.mode)),
      sh.mode == "line")
    check(string.format("scrim band %d carries the tuned alpha (%.4f)", i, sh.a),
      SCRIM[i] ~= nil and math.abs(sh.a - SCRIM[i][3]) < 1e-9)
    local half = (sh.mode == "line") and sh.lw * 0.5 or 0
    local clears = sh.mode == "line"
      and (sh.x + half) <= GX0 + 1e-9 and (sh.y + half) <= GY0 + 1e-9
      and (sh.x + sh.w - half) >= GX0 + GBW - 1e-9
      and (sh.y + sh.h - half) >= GY0 + GBH - 1e-9
    check(string.format("scrim band %d leaves the whole card outline unpainted (hole %.2f..%.2f vs card %.2f..%.2f)",
      i, sh.x + half, sh.x + sh.w - half, GX0, GX0 + GBW), clears)
  end

  local w = card_px(1.0)
  local bw = px(w * 0.030 * 0.5)
  for _, field in ipairs(red_fields("evil")) do
    local fname, bg = field[1], field[2]
    local sb = scrim_over(bg)
    check(string.format("the evil scrim takes energy out of every channel of %s (%.3f/%.3f/%.3f -> %.3f/%.3f/%.3f)",
      fname, bg[1], bg[2], bg[3], sb[1], sb[2], sb[3]),
      sb[1] < bg[1] and sb[2] < bg[2] and sb[3] < bg[3])
    local total, intensity = Col.delta_itp(sb, bg)
    check(string.format("the evil scrim moves %s through intensity, not chroma (dI/dE %.3f >= %.2f)",
      fname, intensity / total, SCRIM_INTENSITY_SHARE), intensity / total >= SCRIM_INTENSITY_SHARE)
    local bare = worst_after_transport(bg, Col.over_alpha(P.D_GOLD, A.border, bg), bw)
    local over = worst_after_transport(sb, Col.over_alpha(P.D_GOLD, A.border, sb), bw)
    check(string.format("the band beside the gold border lifts it on %s (dE %.1f -> %.1f)",
      fname, bare, over), over > bare)
  end
end

do
  local edge = {
    { "D_GOLD", P.D_GOLD },
    { "D_ORANGE shimmer end", P.D_ORANGE },
  }
  for _, e in ipairs(edge) do
    for _, field in ipairs(red_fields("evil")) do
      local gap = hue_gap(e[2], field[2])
      check(string.format("the evil border hue %s clears the red fields on %s (%.0f deg >= %d)",
        e[1], field[1], gap, HUE_MIN_SEPARATION), gap >= HUE_MIN_SEPARATION)
    end
  end
  for _, field in ipairs(red_fields("evil")) do
    local gap = hue_gap(P.ACCENT, field[2])
    print(string.format("      note  crimson ACCENT sits %.1f deg from %s: identity only, never the edge",
      gap, field[1]))
  end
end

do
  local bg = PC.evil.BACKGROUND.L
  local w = card_px(1.0)
  local border_w = px(w * 0.030)
  local border = Col.over_alpha(P.D_GOLD, A.border, bg)
  local _, border_ref_i, border_ref_c = Col.delta_itp(border, bg)
  local _, border_after_i, border_after_c = worst_after_transport(bg, border, border_w)
  local drift = math.abs(border_after_i - border_ref_i) / border_ref_i
  check(string.format("4:2:0 leaves the gold border intensity intact (%.1f -> %.1f, drift %.2f%%)",
    border_ref_i, border_after_i, drift * 100), drift < 0.02)
  local chroma_loss = 1 - border_after_c / border_ref_c
  check(string.format("intensity survives transport far better than chroma (%.2f%% vs %.0f%% lost)",
    drift * 100, chroma_loss * 100), drift < chroma_loss / 10)
  check(string.format("the thin border loses chroma in transport (%.1f -> %.1f)",
    border_ref_c, border_after_c), border_after_c < border_ref_c)
end

do
  local worst_commit, worst_base = math.huge, math.huge
  for _, field in ipairs(red_fields("evil")) do
    local bg = field[2]
    local _, ci = Col.delta_itp(Col.over_add(P.D_WHITE, A.mark_core_commit, bg), bg)
    local _, bi = Col.delta_itp(Col.over_add(P.D_GOLD, A.mark, bg), bg)
    if ci < worst_commit then worst_commit = ci end
    if ci - bi < worst_base then worst_base = ci - bi end
  end
  check(string.format("the commit strike reads through intensity on every field (dI %.1f >= %.1f)",
    worst_commit, DE_MIN), worst_commit >= DE_MIN)
  check(string.format("the commit strike raises intensity above the resting mark (min gain %.1f)",
    worst_base), worst_base > 0)

  local bg = PC.evil.BACKGROUND.L
  local mark_a = A.mark + A.mark_commit
  local _, gold_i = Col.delta_itp(Col.over_add(P.D_GOLD, mark_a, bg), bg)
  local _, glow_i = Col.delta_itp(Col.over_add(P.GLOW, mark_a, bg), bg)
  check(string.format("gold carries more intensity than crimson on the bright field (dI %.1f vs %.1f)",
    gold_i, glow_i), gold_i > glow_i)

  check("candle flicker feeding the pulse has energy above 1 Hz",
    math.abs(Prims.candle01(0.0) - Prims.candle01(0.135)) > 0.05)
end

do
  local w = card_px(1.0)
  local function worst_over(pk, colours, mode, alpha, lw, on_scrim)
    local worst = math.huge
    for _, colour in ipairs(colours) do
      for _, field in ipairs(red_fields(pk)) do
        local bg = on_scrim and scrim_over(field[2]) or field[2]
        local t = worst_after_transport(bg, blend(mode, colour, alpha, bg), lw)
        if t < worst then worst = t end
      end
    end
    return worst
  end
  local function parity(name, ev, nv)
    local ratio = ev / nv
    check(string.format("evil %s is never less readable than neuro (%.1f vs %.1f, ratio %.3f)",
      name, ev, nv, ratio), ratio >= 1.0)
  end
  local border_w = px(w * 0.030 * 0.5)
  parity("border at commit",
    worst_over("evil", { P.D_GOLD, P.D_ORANGE }, "alpha", A.border + A.border_commit, border_w, true),
    worst_over("neuro", { NP.ACCENT, NP.GLOW }, "alpha", 0.48, border_w))
  local rest_w = px(w * 0.13 * 0.72, 20)
  local commit_w = px(w * 0.13, 20)
  parity("mark at rest",
    worst_over("evil", { P.D_GOLD }, "add", A.mark, rest_w),
    worst_over("neuro", { NP.ACCENT }, "alpha", 0.30, rest_w))
  parity("mark at commit",
    worst_over("evil", { P.D_GOLD }, "add", A.mark + A.mark_commit, commit_w),
    worst_over("neuro", { NP.ACCENT }, "alpha", 0.95, commit_w))
end

local DE_INVISIBLE = 5.0

local function drawn_elements(pk)
  local p = Palette.PALETTES[pk]
  if pk == "evil" then
    return evil_elements(card_px(1.0))
  elseif pk == "neuro" then
    return {
      { "accent border", p.ACCENT, "alpha", 0.48 },
      { "glow border", p.GLOW, "alpha", 0.48 },
    }
  end
  return {
    { "glow border", p.GLOW, "alpha", 0.90 },
    { "primary wash", p.PRIMARY, "alpha", 0.18 },
  }
end

for _, pk in ipairs({ "hiyori", "neuro", "evil" }) do
  for _, field in ipairs(red_fields(pk)) do
    local name, bg = field[1], field[2]
    local best, best_name = 0, "?"
    for _, el in ipairs(drawn_elements(pk)) do
      local d = Col.delta_itp(blend(el[3], el[2], el[4], bg), bg)
      if d > best then best, best_name = d, el[1] end
    end
    check(string.format("%s: the glow is not invisible on %s (%s, dE_ITP %.1f)",
      pk, name, best_name, best), best > DE_INVISIBLE)
    if pk ~= "evil" then
      print(string.format("      note  %s on %s: best drawn element dE_ITP %.1f (%s)",
        pk, name, best, best_name))
    end
  end
end

do
  local floor_y = 0.0513
  local function lum(c)
    local function f(v)
      if v <= 0.04045 then return v / 12.92 end
      return ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
  end
  check(string.format("the evil background floor is no darker than Balatro's own (C %.4f, D %.4f, stock %.4f)",
    lum(PC.evil.BACKGROUND.C), lum(PC.evil.BACKGROUND.D), floor_y),
    lum(PC.evil.BACKGROUND.C) >= floor_y * 0.95 and lum(PC.evil.BACKGROUND.D) >= floor_y * 0.6)
  check(string.format("the evil background stays darker than neuro's (evil C %.4f < neuro C %.4f)",
    lum(PC.evil.BACKGROUND.C), lum(PC.neuro.BACKGROUND.C)),
    lum(PC.evil.BACKGROUND.C) < lum(PC.neuro.BACKGROUND.C))
end

done()
