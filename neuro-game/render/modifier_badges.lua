local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local gfx = require("render.gfx")
local shadow_text, round = gfx.shadow_text, gfx.round
local Prims = require("hud.prims")
local RectMesh = require("render.rect_mesh")

local M = {}

local EDITION_LABELS = {
  Negative = "Neg",
  Polychrome = "Poly",
  Holographic = "Holo",
  Foil = "Foil",
}

local COLLECT_REVALIDATE_S = 0.75
local _collect_cache = setmetatable({}, { __mode = "k" })
local _badge_version = 0

local function versioned(badges)
  _badge_version = _badge_version + 1
  badges._v = _badge_version
  return badges
end

local EMPTY_BADGES = versioned({})

if _G.NEURO_TEST then M.stamp = versioned end

local function text_value(value)
  if type(value) == "table" then value = Utils.flatten_description(value) end
  if type(value) ~= "string" or value == "" then return nil end
  return value
end

local function custom_enhancement_name(card)
  local center = card and card.config and card.config.center or {}
  local ability = card and card.ability or {}
  if center.set ~= "Enhanced" and ability.set ~= "Enhanced" and not ability.enhancement then return nil end
  return text_value(center.loc_txt and center.loc_txt.name)
    or text_value(center.name)
    or ((center.key or ability.enhancement) and Utils.humanize_identifier(center.key or ability.enhancement) or nil)
end

local function add(out, kind, text, key, fx)
  if type(text) == "string" and text ~= "" then
    out[#out + 1] = { kind = kind, text = text, key = key,
      fx = (type(fx) == "string" and fx ~= "") and fx or nil }
  end
end

local function build_badges(card, enhancement)
  local out = {}
  local ability = card.ability or {}

  if ability.eternal then
    add(out, "sticker", "Eternal", "eternal", nil)
  end
  if ability.rental then
    add(out, "sticker", "Rental", "rental", (CardUtil.sticker_fx_short("rental"):gsub("/rd$", "")))
  end
  if ability.perishable then
    local rounds = tonumber(ability.perish_tally)
    add(out, "sticker", rounds and ("Perish " .. tostring(rounds)) or "Perish", "perishable", nil)
  end

  local edition = CardUtil.edition_name(card.edition)
  if edition then
    local label = EDITION_LABELS[edition] or edition
    add(out, "edition", label, label, CardUtil.edition_fx_short(card.edition))
  end

  local seal = CardUtil.seal_name(card.seal)
  add(out, "seal", seal and (seal .. " Seal") or nil, seal, CardUtil.seal_fx_short(card.seal))

  local enh_name = enhancement and CardUtil.enhancement_name(enhancement) or custom_enhancement_name(card)
  local enh_fx = enhancement and CardUtil.enhancement_fx_short(enhancement) or ""
  add(out, "enhancement", enh_name, enhancement, enh_fx)

  return out
end

local function same_badges(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if x.kind ~= y.kind or x.text ~= y.text or x.key ~= y.key or x.fx ~= y.fx then
      return false
    end
  end
  return true
end

function M.collect(card)
  if type(card) ~= "table" then return EMPTY_BADGES end

  local center = card.config and card.config.center or nil
  local ability = card.ability
  local edition = card.edition
  local edition_data = type(edition) == "table" and edition or nil
  local seal = card.seal
  local enhancement = CardUtil.enhancement_key(card)
  local custom = not enhancement and (
    (center and center.set == "Enhanced")
    or (ability and ability.set == "Enhanced")
    or (ability and ability.enhancement)
  ) or false
  local loc_txt = custom and center and center.loc_txt or nil
  local loc_name = loc_txt and loc_txt.name or nil
  local custom_name = custom and center and center.name or nil
  local custom_key = custom and ((center and center.key) or (ability and ability.enhancement)) or nil
  local seal_value = type(seal) == "table" and (seal.name or seal.key) or seal
  local perish_tally = ability and ability.perishable and tonumber(ability.perish_tally) or nil
  local rental_rate = ability and ability.rental
    and ((G and G.GAME and tonumber(G.GAME.rental_rate)) or 3) or nil
  local now = Utils.now()
  local cached = _collect_cache[card]

  local inputs_match = cached
    and cached.center == center
    and cached.ability == ability
    and cached.edition == edition
    and cached.ed_negative == (edition_data and edition_data.negative)
    and cached.ed_key == (edition_data and edition_data.key)
    and cached.ed_polychrome == (edition_data and edition_data.polychrome)
    and cached.ed_holo == (edition_data and edition_data.holo)
    and cached.ed_foil == (edition_data and edition_data.foil)
    and cached.ed_filtered == (edition_data and edition_data.filtered)
    and cached.ed_name == (edition_data and edition_data.name)
    and cached.ed_type == (edition_data and edition_data.type)
    and cached.enhancement == enhancement
    and cached.custom == custom
    and cached.loc_txt == loc_txt
    and cached.loc_name == loc_name
    and cached.custom_name == custom_name
    and cached.custom_key == custom_key
    and cached.seal == seal
    and cached.seal_value == seal_value
    and cached.eternal == (ability and ability.eternal)
    and cached.perishable == (ability and ability.perishable)
    and cached.perish_tally == perish_tally
    and cached.rental == (ability and ability.rental)
    and cached.rental_rate == rental_rate
  local due = not cached or now < cached.checked_at
    or now - cached.checked_at >= COLLECT_REVALIDATE_S
  if inputs_match and not due then return cached.badges end

  local badges = build_badges(card, enhancement)
  if inputs_match and same_badges(cached.badges, badges) then
    cached.checked_at = now
    return cached.badges
  end

  badges = versioned(badges)
  cached = cached or {}
  cached.center = center
  cached.ability = ability
  cached.edition = edition
  cached.ed_negative = edition_data and edition_data.negative
  cached.ed_key = edition_data and edition_data.key
  cached.ed_polychrome = edition_data and edition_data.polychrome
  cached.ed_holo = edition_data and edition_data.holo
  cached.ed_foil = edition_data and edition_data.foil
  cached.ed_filtered = edition_data and edition_data.filtered
  cached.ed_name = edition_data and edition_data.name
  cached.ed_type = edition_data and edition_data.type
  cached.enhancement = enhancement
  cached.custom = custom
  cached.loc_txt = loc_txt
  cached.loc_name = loc_name
  cached.custom_name = custom_name
  cached.custom_key = custom_key
  cached.seal = seal
  cached.seal_value = seal_value
  cached.eternal = ability and ability.eternal
  cached.perishable = ability and ability.perishable
  cached.perish_tally = perish_tally
  cached.rental = ability and ability.rental
  cached.rental_rate = rental_rate
  cached.checked_at = now
  cached.badges = badges
  _collect_cache[card] = cached
  return badges
end

local TILE_U = 12          -- tile side; identical on every surface and every persona
local GLYPH_U = 8
local TPAD_U = 3
local SEP_U = 2
local ROWGAP_U = 2

local function pin_tail(b, tier)
  local name = tostring(b.text or "")
  local fx = b.fx and tostring(b.fx) or nil
  if tier == 3 then return fx and (name .. " " .. fx) or name end
  if tier == 2 then return fx or name:match("(%d+)") end
  return name:match("(%d+)")
end

local function pin_width(b, font, unit, tier)
  local tile, tpad = TILE_U * unit, TPAD_U * unit
  local tail = pin_tail(b, tier)
  if not tail or tail == "" then return tile end
  local pad = (tier == 1) and unit or tpad
  return tile + pad + font:getWidth(tail) + pad
end

local function tier_widths(badges, font, unit)
  local sep = SEP_U * unit
  local n = #badges
  local w3, w2, w1 = 0, 0, 0
  for _, b in ipairs(badges) do
    w3 = w3 + pin_width(b, font, unit, 3)
    w2 = w2 + pin_width(b, font, unit, 2)
    w1 = w1 + pin_width(b, font, unit, 1)
  end
  local gaps = sep * math.max(0, n - 1)
  return w3 + gaps, w2 + gaps, w1 + gaps
end

function M.layout(badges, font, max_width, unit, max_rows)
  unit = unit or 1
  max_width = math.max(0, max_width or 0)
  max_rows = math.max(1, math.floor(max_rows or 1))
  badges = badges or {}
  local n = #badges
  local tile, tpad, sep = TILE_U * unit, TPAD_U * unit, SEP_U * unit
  local row_gap = ROWGAP_U * unit
  local text_h = font:getHeight()

  local w3, w2, w1 = tier_widths(badges, font, unit)

  local function rows_needed(tier)
    local rows_, x_ = 1, 0
    for _, b in ipairs(badges) do
      local w = pin_width(b, font, unit, tier)
      if x_ > 0 and x_ + sep + w > max_width then rows_ = rows_ + 1; x_ = w
      else x_ = (x_ > 0) and (x_ + sep + w) or w end
    end
    return rows_
  end

  local t2_worth_it = (w2 ~= w1) and w2 <= max_width * max_rows
  local tier = 1
  if n == 0 or (w3 <= max_width * max_rows and rows_needed(3) <= max_rows) then tier = 3
  elseif t2_worth_it and rows_needed(2) <= max_rows then tier = 2 end

  local h = (tier == 1) and (TILE_U * unit) or math.max(text_h, TILE_U * unit)

  local items = {}
  local rows = n > 0 and 1 or 0
  local x, row = 0, 1
  local hidden = 0

  for i = 1, n do
    local b = badges[i]
    local label = pin_tail(b, tier)
    local has = label and label ~= ""
    local tail_pad = (tier == 1) and unit or tpad
    local lead = tile + (has and tail_pad or 0)
    local pad = has and tail_pad or 0
    local w = pin_width(b, font, unit, tier)

    if x > 0 and x + sep + w > max_width then
      if row >= max_rows then hidden = n - i + 1; break end
      row = row + 1
      rows = row
      x = 0
    end
    local ix = x > 0 and (x + sep) or 0
    items[#items + 1] = {
      x = ix, y = (row - 1) * (h + row_gap), w = w, h = h,
      kind = b.kind, key = b.key, text = has and label or "", tier = tier,
      lead = lead, pad = pad, mark_w = GLYPH_U * unit, cap = tile, mark = GLYPH_U * unit,
      row = row, first = ix == 0,
    }
    x = ix + w
  end

  if hidden > 0 then
    if hidden == 1 and #items > 0 then
      items[#items] = nil
      hidden = 2
    end
    local pips = (tier == 1)
    while #items > 0 do
      local label = "+" .. tostring(hidden)
      local w = pips and tile or font:getWidth(label)
      local last = items[#items]
      local ix = last.x + last.w + sep
      if ix + w <= max_width then
        items[#items + 1] = { x = ix, y = last.y, w = w, h = h, kind = "overflow",
          key = nil, text = label, tier = tier, lead = 0, pad = 0, mark_w = 0, cap = 0, mark = 0,
          row = last.row, first = false, pips = pips and hidden or nil }
        break
      end
      items[#items] = nil
      hidden = hidden + 1
    end
  end

  local row_widths = {}
  for _, item in ipairs(items) do
    row_widths[item.row] = math.max(row_widths[item.row] or 0, item.x + item.w)
  end

  return {
    items = items,
    rows = rows,
    tier = tier,
    height = rows > 0 and (rows * h + (rows - 1) * row_gap) or 0,
    unit = unit,
    font = font,
    row_widths = row_widths,
  }
end

local EDITION_COLORS = {
  Foil = { 0.72, 0.86, 0.95 },
  Holo = { 0.34, 0.64, 1.00 },
  Poly = { 0.98, 0.45, 0.80 },
  Neg  = { 0.70, 0.56, 1.00 },
}
local STICKER_COLORS = {
  eternal    = { 0.78, 0.35, 0.52 },
  perishable = { 0.31, 0.36, 0.63 },
  rental     = { 0.69, 0.56, 0.26 },
}
local STICKER_GC = { eternal = "ETERNAL", perishable = "PERISHABLE", rental = "RENTAL" }
local STICKER_ORDER = { "eternal", "perishable", "rental" }

local ENHANCEMENT_COLORS = {
  m_bonus = { 0.24, 0.52, 0.90 },   -- chips: the blue the engine prints a chip total in
  m_mult  = { 0.98, 0.38, 0.22 },   -- mult, pushed off the Red seal's crimson
  m_wild  = { 0.72, 0.42, 0.92 },   -- every suit at once, so none of the four suit colours
  m_glass = { 0.58, 0.94, 0.92 },   -- pane: pale, but turned cyan off Foil's silver
  m_steel = { 0.60, 0.66, 0.74 },   -- cold rolled
  m_gold  = { 0.98, 0.88, 0.52 },   -- leaf, not coin -- the seal owns the coin gold
  m_lucky = { 0.34, 0.80, 0.42 },   -- clover
  m_stone = { 0.55, 0.50, 0.46 },   -- quarried grey, warm where steel is cold
}

local SEAL_GC = { Gold = "GOLD", Red = "RED", Blue = "BLUE", Purple = "PURPLE" }
local SEAL_COLORS = {
  Gold   = { 0.93, 0.71, 0.13 },
  Red    = { 0.93, 0.24, 0.29 },
  Blue   = { 0.27, 0.85, 0.81 },
  Purple = { 0.55, 0.37, 0.66 },
}

local _lift = { 0, 0, 0 }
local SEP_CHROMA = 0.12
local SEP_LUMA = 0.10
local CAP_LUMA = 0.36
local function luma_of(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
local function separable(a, b)
  local d = math.abs(a[1] - b[1])
  local d2 = math.abs(a[2] - b[2])
  local d3 = math.abs(a[3] - b[3])
  if d2 > d then d = d2 end
  if d3 > d then d = d3 end
  if d >= SEP_CHROMA then return true end
  return math.abs(luma_of(a) - luma_of(b)) >= SEP_LUMA
end
if _G.NEURO_TEST then
  M.separable = separable
end

local function lift_into(dst, c)
  local luma = luma_of(c)
  local k = (luma >= CAP_LUMA) and 1 or (CAP_LUMA / (luma > 0.02 and luma or 0.02))
  dst[1] = math.min(1, c[1] * k)
  dst[2] = math.min(1, c[2] * k)
  dst[3] = math.min(1, c[3] * k)
  return dst
end

local function make_group_palette(order, gc_map, fallback)
  local n = #order
  local sig, lifted, resolved = {}, {}, nil
  for i = 1, n * 3 do sig[i] = -2 end
  for i = 1, n do lifted[i] = { 0, 0, 0 } end

  local function live_rgb(key)
    local c = G and G.C and G.C[gc_map[key]]
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number"
      and type(c[3]) == "number" then
      return c
    end
    return nil
  end

  return function()
    local changed, complete = false, true
    for i = 1, n do
      local c = live_rgb(order[i])
      local r = c and c[1] or -1
      local g = c and c[2] or -1
      local b = c and c[3] or -1
      if not c then complete = false end
      local o = (i - 1) * 3
      if sig[o + 1] ~= r or sig[o + 2] ~= g or sig[o + 3] ~= b then
        changed = true
        sig[o + 1], sig[o + 2], sig[o + 3] = r, g, b
      end
    end
    if resolved and not changed then return resolved end

    local take = complete
    if take then
      for i = 1, n do lift_into(lifted[i], live_rgb(order[i])) end
      for i = 1, n do
        for j = i + 1, n do
          if not separable(lifted[i], lifted[j]) then take = false end
        end
      end
    end

    resolved = resolved or {}
    for i = 1, n do
      local key = order[i]
      resolved[key] = take and lifted[i] or fallback[key]
    end
    return resolved
  end
end

local sticker_palette = make_group_palette(STICKER_ORDER, STICKER_GC, STICKER_COLORS)
local SEAL_ORDER = { "Gold", "Red", "Blue", "Purple" }
local seal_palette = make_group_palette(SEAL_ORDER, SEAL_GC, SEAL_COLORS)

local function sticker_color(key, theme)
  local c = key and sticker_palette()[key]
  return c or STICKER_COLORS[key] or theme.DIM or theme.WHITE
end

local function seal_color(key, theme)
  if not key then return theme.GOLD end
  if not SEAL_COLORS[key] then return theme.GOLD end   -- a modded seal keeps the old behaviour
  return seal_palette()[key] or SEAL_COLORS[key]
end

local function badge_color(item, theme)
  local kind = item.kind
  if kind == "edition" then
    return EDITION_COLORS[item.key or item.text] or (theme._pal and theme._pal.EDITION) or theme.ACC
  end
  if kind == "enhancement" then
    return ENHANCEMENT_COLORS[item.key] or theme.GREEN or theme.CYAN
  end
  if kind == "seal" then return seal_color(item.key, theme) end
  if kind == "sticker" then return sticker_color(item.key, theme) end
  return theme.DIM or theme.WHITE
end

M.badge_color = badge_color

local PLATE_INK = 0.22
local KIND_HUE = { sticker = 0.28, edition = 0.28, seal = 0.20, enhancement = 0.20 }
M.PLATE = { ink = PLATE_INK, hue = KIND_HUE }

local CAP_A = 0.94
local LABEL_LIFT = 0.62
local GLYPH_INK = { 0.05, 0.045, 0.07 }

local _cap = { 0, 0, 0 }
local function cap_color(c)
  if luma_of(c) >= CAP_LUMA then return c end
  return lift_into(_cap, c)
end

local _txt = { 0, 0, 0 }
local function label_color(c)
  _txt[1] = c[1] + (1 - c[1]) * LABEL_LIFT
  _txt[2] = c[2] + (1 - c[2]) * LABEL_LIFT
  _txt[3] = c[3] + (1 - c[3]) * LABEL_LIFT
  return _txt
end

local POLY_BANDS = { { 0.98, 0.45, 0.72 }, { 1.00, 0.80, 0.36 }, { 0.42, 0.88, 0.96 } }
local NEG_INK = { 0.05, 0.04, 0.09 }

local function draw_cap(lg, item, ix, iy, cw, c, a, rad)
  local h = item.h
  local edition = item.kind == "edition"
  local key = item.key
  local neg = edition and key == "Neg"
  local base = neg and NEG_INK or cap_color(c)
  lg.setColor(base[1], base[2], base[3], CAP_A * a)
  lg.rectangle("fill", ix, iy, cw, h, rad, rad)
  if rad > 0 then lg.rectangle("fill", ix + cw - rad, iy, rad, h) end

  if not edition then return end
  if key == "Poly" then
    local band = math.max(1, math.floor(h / 3))
    for i = 1, 3 do
      local b = POLY_BANDS[i]
      lg.setColor(b[1], b[2], b[3], CAP_A * a)
      lg.rectangle("fill", ix, iy + (i - 1) * band, cw, (i == 3) and (h - 2 * band) or band)
    end
  elseif key == "Holo" then
    lg.setColor(1, 1, 1, 0.36 * a)
    lg.rectangle("fill", ix, iy + math.floor(h * 0.40), cw, math.max(1, math.floor(h * 0.20)))
  elseif key == "Foil" then
    lg.setColor(0, 0, 0, 0.26 * a)
    lg.rectangle("fill", ix, iy, math.max(1, math.floor(cw * 0.28)), h)
    lg.setColor(1, 1, 1, 0.42 * a)
    lg.rectangle("fill", ix + math.floor(cw * 0.55), iy, math.max(1, math.floor(cw * 0.20)), h)
  elseif neg then
    local f = cap_color(c)
    lg.setColor(f[1], f[2], f[3], 0.95 * a)
    lg.setLineWidth(1)
    lg.rectangle("line", ix + 0.5, iy + 0.5, cw - 1, h - 1, rad, rad)
  end
end

local function draw_finish(lg, theme, item, ix, iy, cw, c, a, rad, mo)
  local w, h = item.w, item.h
  if theme.persona_evil then
    local E = Prims.EVIL
    local gold = theme.GOLD
    lg.setColor(0, 0, 0, 0.34 * a)
    lg.rectangle("fill", ix, iy + h - 1, w, 1)
    lg.setColor(gold[1], gold[2], gold[3], E.A_HAIR * 2.3 * a)
    lg.setLineWidth(1)
    lg.rectangle("line", ix + 0.5, iy + 0.5, w - 1, h - 1)
    lg.setColor(gold[1], gold[2], gold[3], (E.A_ACCENT + E.PULSE_AMP * (mo.pulse or 0.5)) * a)
    lg.rectangle("fill", ix + cw, iy, 1, h)
    lg.setColor(gold[1], gold[2], gold[3], E.A_STRUCT * a)
    lg.rectangle("fill", ix + 1, iy + 1, 2, 1)
    lg.rectangle("fill", ix + w - 3, iy + h - 2, 2, 1)
  elseif theme.persona_neuro then
    local sr = mo.shimr or c[1]
    local sg = mo.shimg or c[2]
    local sb = mo.shimb or c[3]
    local br = c[1] * 0.35 + sr * 0.65
    local bg = c[2] * 0.35 + sg * 0.65
    local bb = c[3] * 0.35 + sb * 0.65
    lg.setColor(br, bg, bb, 0.80 * a)
    lg.rectangle("fill", ix + cw, iy, 1, h)
    lg.setColor(1, 1, 1, 0.17 * a)
    lg.rectangle("fill", ix + rad, iy + 1, math.max(0, w - rad * 2), 1)
    lg.setColor(br, bg, bb, 0.26 * a)
    lg.rectangle("fill", ix + rad, iy + h - 1, math.max(0, w - rad * 2), 1)
    lg.setColor(1, 1, 1, 0.34 * a)
    lg.setLineWidth(1)
    lg.rectangle("line", ix + 0.5, iy + 0.5, w - 1, h - 1, rad, rad)
  else
    local seam = RectMesh.get("badge_seam_plain", cw, w, h)
    if not seam and RectMesh.available() then
      local v, i = {}, {}
      RectMesh.add(v, i, cw, 0, 1, h, 0, 0, 0, 0.34)
      RectMesh.add(v, i, 0, 0, w, 1, 1, 1, 1, 0.10)
      RectMesh.add(v, i, 0, h - 1, w, 1, 0, 0, 0, 0.26)
      seam = RectMesh.build(v, i)
      if seam then RectMesh.put("badge_seam_plain", cw, w, h, nil, nil, nil, seam) end
    end
    if seam then
      lg.setColor(1, 1, 1, a)
      lg.draw(seam, ix, iy)
    else
      lg.setColor(0, 0, 0, 0.34 * a)
      lg.rectangle("fill", ix + cw, iy, 1, h)
      lg.setColor(1, 1, 1, 0.10 * a)
      lg.rectangle("fill", ix, iy, w, 1)
      lg.setColor(0, 0, 0, 0.26 * a)
      lg.rectangle("fill", ix, iy + h - 1, w, 1)
    end
  end
end

local NO_MO = { pulse = 0.5 }

local W_NEURO = { ink = 0.16, rad = 3,          -- sticker sheet: bright, die-cut
  hue = { sticker = 0.34, edition = 0.34, seal = 0.26, enhancement = 0.26 } }
local W_EVIL  = { ink = 0.34, rad = 0,          -- brass plate under lacquer
  hue = { sticker = 0.22, edition = 0.22, seal = 0.16, enhancement = 0.16 } }
local W_PLAIN = { ink = PLATE_INK, rad = 0, hue = KIND_HUE }

local function persona_weights(theme)
  if theme.persona_neuro then return W_NEURO end
  if theme.persona_evil then return W_EVIL end
  return W_PLAIN
end

function M.draw(layout, x, y, alpha, theme, mo)
  if not (layout and layout.items and #layout.items > 0) then return end
  local lg = love.graphics
  local old_font = lg.getFont()
  local old_r, old_g, old_b, old_a = lg.getColor()
  local old_width = lg.getLineWidth()
  alpha = alpha or 1
  mo = mo or NO_MO
  local unit = layout.unit or 1
  local W = persona_weights(theme)
  lg.setFont(layout.font)

  for _, item in ipairs(layout.items) do
    local c = badge_color(item, theme)
    local ix, iy = round(x + item.x), round(y + item.y)
    local hue = W.hue[item.kind]
    local tile = item.cap or 0
    local text_col, text_a = c, 0.70
    local rad = (W.rad > 0) and math.min(W.rad * unit, math.floor(item.h / 4)) or 0

    if hue then
      local ab = (W.ink * alpha >= 0.03) and (W.ink * alpha) or 0
      local ah = (hue * alpha >= 0.03) and (hue * alpha) or 0
      local pa = ah + ab * (1 - ah)
      if pa > 0 and item.w > tile then
        local k = ah / pa
        lg.setColor(c[1] * k, c[2] * k, c[3] * k, pa)
        lg.rectangle("fill", ix, iy, item.w, item.h, rad, rad)
      end

      if tile > 0 then draw_cap(lg, item, ix, iy, tile, c, alpha, rad) end
      Prims.pin_silhouette(item.kind, ix, iy, tile, item.h, theme.bg or GLYPH_INK, alpha)
      draw_finish(lg, theme, item, ix, iy, tile, c, alpha, rad, mo)
      text_col, text_a = label_color(c), 1.0
    end

    if tile > 0 then
      local mark_col = (item.kind == "edition" and item.key == "Neg") and c or GLYPH_INK
      Prims.pin_glyph(item.kind, item.key, ix + tile / 2, iy + math.floor(item.h / 2),
        GLYPH_U * unit, mark_col, alpha)
    end

    if item.pips then
      Prims.pin_pips(item.pips, ix, iy, item.w, item.h, text_col, text_a * alpha)
    elseif item.text and item.text ~= "" then
      local tx = ix + (item.lead or 0)
      local ty = iy + math.floor((item.h - layout.font:getHeight()) / 2)
      shadow_text(item.text, tx, ty, text_col, text_a * alpha, ((hue and 0.22) or 0.35) * alpha)
    end
  end
  lg.setLineWidth(old_width)
  lg.setFont(old_font)
  lg.setColor(old_r, old_g, old_b, old_a)
end

local TIPS = {
  sticker = {
    eternal    = "cannot be sold or destroyed",
    perishable = "debuffed after a few rounds",
  },
  edition = {
    Foil = "+50 chips when it scores",
    Holo = "+10 mult when it scores",
    Poly = "x1.5 mult when it scores",
    Neg  = "costs no joker slot",
  },
  seal = {
    Gold   = "pays $3 when it scores",
    Red    = "scores a second time",
    Blue   = "held to end: free Planet",
    Purple = "discard it: free Tarot",
  },
  enhancement = {
    m_bonus = "+30 chips when it scores",
    m_mult  = "+4 mult when it scores",
    m_wild  = "counts as any suit",
    m_steel = "x1.5 mult while held in hand",
    m_stone = "+50 chips, no rank or suit",
    m_gold  = "pays $3 if held at round end",
  },
}

local ENHANCEMENT_CONFIG_FALLBACK = {
  m_glass = { Xmult = 2, extra = 4 },
  m_lucky = { mult = 20, p_dollars = 20 },
}

local function enhancement_cfg_num(key, field)
  local center = G and G.P_CENTERS and G.P_CENTERS[key]
  local cfg = (type(center) == "table") and center.config or nil
  local v = type(cfg) == "table" and tonumber(cfg[field]) or nil
  if v == nil then v = tonumber((ENHANCEMENT_CONFIG_FALLBACK[key] or {})[field]) end
  return v or 0
end

local function dynamic_tip(kind, key, text)
  if kind == "sticker" and key == "rental" then
    local rate = tostring(CardUtil.sticker_fx_short("rental")):match("%-%$(%d+)") or "3"
    return "costs $" .. rate .. " at end of every round"
  end
  if kind == "sticker" and key == "perishable" then
    local n = tostring(text or ""):match("(%d+)")
    if n then return "debuffed after " .. n .. " more rounds" end
  end
  if kind == "enhancement" and key == "m_glass" then
    return "x" .. Utils.fmt_num(enhancement_cfg_num("m_glass", "Xmult")) .. " mult, "
      .. CardUtil.odds_frac(enhancement_cfg_num("m_glass", "extra")) .. " it shatters"
  end
  if kind == "enhancement" and key == "m_lucky" then
    return CardUtil.odds_frac(5) .. ": +" .. Utils.fmt_num(enhancement_cfg_num("m_lucky", "mult")) .. " mult, "
      .. CardUtil.odds_frac(15) .. ": $" .. Utils.fmt_num(enhancement_cfg_num("m_lucky", "p_dollars"))
  end
  return nil
end

function M.tip(badge)
  if type(badge) ~= "table" then return nil end
  local kind, key = badge.kind, badge.key
  if kind == "overflow" then
    local n = tostring(badge.text or ""):match("(%d+)")
    return n and (n .. " more pins, no room to show") or nil
  end
  local dyn = dynamic_tip(kind, key, badge.text)
  if dyn then return dyn end
  local per_kind = kind and TIPS[kind]
  return per_kind and key and per_kind[key] or nil
end

local DECK_MAX = 8

local function scan_area(cards, seen, deck)
  if type(cards) ~= "table" then return end
  for i = 1, #cards do
    local card = cards[i]
    if type(card) == "table" then
      local badges = M.collect(card)
      for b = 1, #badges do
        local badge = badges[b]
        local id = tostring(badge.kind) .. "|" .. tostring(badge.key)
        local prev = seen[id]
        if not prev then
          local entry = { kind = badge.kind, text = badge.text, key = badge.key, fx = badge.fx }
          entry.tip = M.tip(entry)
          if entry.tip then
            seen[id] = entry
            deck[#deck + 1] = entry
          end
        elseif badge.kind == "sticker" and badge.key == "perishable" then
          local a = tonumber(tostring(prev.text or ""):match("(%d+)")) or 0
          local b2 = tonumber(tostring(badge.text or ""):match("(%d+)")) or 0
          if b2 > a then
            prev.text = badge.text
            prev.tip = M.tip(prev)
          end
        end
      end
    end
  end
end

function M.legend_deck()
  local seen, deck = {}, {}
  if G then
    scan_area(G.jokers and G.jokers.cards, seen, deck)
    scan_area(G.consumeables and G.consumeables.cards, seen, deck)
    scan_area(G.playing_cards, seen, deck)
  end
  while #deck > DECK_MAX do deck[#deck] = nil end
  return deck
end

local _legend_memo = { deck = nil, idx = -1 }
function M.legend(i, deck)
  deck = (type(deck) == "table" and #deck > 0) and deck or M.legend_deck()
  local n = #deck
  if n == 0 then return nil, nil end
  local idx = (math.floor(i or 0) % n) + 1
  if _legend_memo.deck == deck and _legend_memo.idx == idx then
    return _legend_memo.list, _legend_memo.entry
  end
  local e = deck[idx]
  _legend_memo.deck, _legend_memo.idx = deck, idx
  _legend_memo.list = { { kind = e.kind, text = e.text, key = e.key, fx = e.fx } }
  _legend_memo.entry = e
  return _legend_memo.list, e
end

return M
