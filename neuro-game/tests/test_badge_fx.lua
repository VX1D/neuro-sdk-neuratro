_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { STATES = {}, GAME = {} }

local check, done = require("tests.helpers").harness("badge-fx")

local CardUtil = require("facts.card_util")
local Badges = require("render.modifier_badges")

local function find_kind(list, kind)
  for _, b in ipairs(list) do if b.kind == kind then return b end end
  return nil
end

check("edition_fx_short Foil", CardUtil.edition_fx_short({ foil = true }) == "+50c")
check("edition_fx_short Holo", CardUtil.edition_fx_short({ holo = true }) == "+10m")
check("edition_fx_short Poly", CardUtil.edition_fx_short({ polychrome = true }) == "x1.5m")
check("edition_fx_short Negative empty", CardUtil.edition_fx_short({ negative = true }) == "")
check("edition_fx_short non-table empty", CardUtil.edition_fx_short(nil) == "")
check("enhancement_fx_short Gold", CardUtil.enhancement_fx_short("m_gold") == "+$3")
check("enhancement_fx_short unknown empty", CardUtil.enhancement_fx_short("m_nope") == "")

do
  local card = { config = { center = { key = "j_joker", set = "Joker" } }, ability = { set = "Joker" },
    edition = { foil = true } }
  local out = Badges.collect(card)
  local ed = find_kind(out, "edition")
  check("collect: Foil badge carries name and effect apart",
    ed and ed.text == "Foil" and ed.fx == "+50c", ed and (tostring(ed.text) .. "/" .. tostring(ed.fx)))
  check("collect: Foil pill carries color key = short label", ed and ed.key == "Foil", ed and ed.key)
end

do
  local card = { config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker", enhancement = "m_gold" } }
  local out = Badges.collect(card)
  local enh = find_kind(out, "enhancement")
  check("collect: Gold enhancement carries its effect", enh and enh.text == "Gold" and enh.fx == "+$3",
    enh and (tostring(enh.text) .. "/" .. tostring(enh.fx)))
end

do
  local card = { config = { center = { key = "j_joker", set = "Joker" } }, ability = { set = "Joker" },
    edition = { negative = true } }
  local ed = find_kind(Badges.collect(card), "edition")
  check("collect: Negative badge is a bare label with no effect",
    ed and ed.text == "Neg" and ed.fx == nil, ed and (tostring(ed.text) .. "/" .. tostring(ed.fx)))
end

do
  local card = { config = { center = { key = "c_jack", set = "Default" } }, ability = {}, seal = "Gold" }
  local sl = find_kind(Badges.collect(card), "seal")
  check("collect: Gold seal is distinguishable from the Gold enhancement",
    sl and sl.text == "Gold Seal" and sl.fx == "+$3",
    sl and (tostring(sl.text) .. "/" .. tostring(sl.fx)))
end
do
  local card = { config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker", eternal = true, rental = true } }
  local out = Badges.collect(card)
  local et, rt
  for _, b in ipairs(out) do
    if b.key == "eternal" then et = b elseif b.key == "rental" then rt = b end
  end
  check("collect: Eternal adds no effect -- the name is the effect", et and et.fx == nil, et and et.fx)
  check("facts still spell out what Eternal blocks",
    CardUtil.sticker_fx_short("eternal") == "no-sell", CardUtil.sticker_fx_short("eternal"))
  check("collect: Rental says what it costs", rt and rt.fx == "-$3", rt and rt.fx)
end

do
  local old_rate, old_timers = G.GAME.rental_rate, G.TIMERS
  G.GAME.rental_rate = 3
  G.TIMERS = { REAL = 0 }
  local card = {
    config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker", rental = true },
    edition = { foil = true },
  }
  local first = Badges.collect(card)
  local unchanged = Badges.collect(card)
  check("collect cache: unchanged card returns the same versioned list",
    unchanged == first and unchanged._v == first._v)

  G.GAME.rental_rate = 7
  local rental_changed = Badges.collect(card)
  local rental = find_kind(rental_changed, "sticker")
  check("collect cache: rental rate invalidates fx",
    rental_changed ~= first and rental_changed._v > first._v
      and rental and rental.fx == "-$7", rental and rental.fx)

  card.edition.foil = nil
  card.edition.polychrome = true
  local fx_changed = Badges.collect(card)
  local edition = find_kind(fx_changed, "edition")
  check("collect cache: edition fx invalidates version",
    fx_changed ~= rental_changed and fx_changed._v > rental_changed._v
      and edition and edition.text == "Poly" and edition.fx == "x1.5m")

  local custom = {
    config = { center = {
      key = "m_modded", set = "Enhanced", loc_txt = { name = "Localized One" },
    } },
    ability = { set = "Enhanced" },
  }
  local custom_one = Badges.collect(custom)
  custom.config.center.loc_txt.name = "Localized Two"
  local custom_two = Badges.collect(custom)
  check("collect cache: custom localized name invalidates immediately",
    custom_two ~= custom_one and custom_two._v > custom_one._v
      and custom_two[1].text == "Localized Two")

  local dynamic_name = { "Dynamic One" }
  custom.config.center.loc_txt.name = dynamic_name
  local dynamic_one = Badges.collect(custom)
  dynamic_name[1] = "Dynamic Two"
  G.TIMERS.REAL = 0.74
  local dynamic_early = Badges.collect(custom)
  G.TIMERS.REAL = 0.75
  local dynamic_two = Badges.collect(custom)
  check("collect cache: in-place custom name revalidates by 0.75 seconds",
    dynamic_early == dynamic_one and dynamic_two ~= dynamic_one
      and dynamic_two._v > dynamic_one._v and dynamic_two[1].text == "Dynamic Two")

  G.GAME.rental_rate, G.TIMERS = old_rate, old_timers
end

do
  local font = {
    getHeight = function() return 8 end,
    getWidth = function(_, s) return #tostring(s) * 4 end,
  }
  local card = { config = { center = { key = "j_joker", set = "Joker" } }, ability = { set = "Joker" },
    edition = { foil = true } }
  local badges = Badges.collect(card)
  local wide = Badges.layout(badges, font, 200, 1, 1)
  local tight = Badges.layout(badges, font, 40, 1, 1)
  local narrow = Badges.layout(badges, font, 14, 1, 1)
  local w1, t1, n1 = wide.items[1], tight.items[1], narrow.items[1]

  check("layout: a wide row says everything", w1 and w1.text == "Foil +50c", w1 and w1.text)
  check("layout: a tight row keeps the VALUE and lets the mark carry the name",
    t1 and t1.text == "+50c", t1 and t1.text)
  check("layout: the narrowest row is the mark alone -- still an identity, never a wrong one",
    n1 and n1.text == "", n1 and ("'" .. tostring(n1.text) .. "'"))

  for _, lay in ipairs({ wide, tight, narrow }) do
    for _, it in ipairs(lay.items) do
      if it.kind ~= "overflow" and it.text ~= "" then
        local whole = (it.text == "Foil +50c") or (it.text == "Foil") or (it.text == "+50c")
        check("layout: '" .. it.text .. "' is a whole label, not a fragment", whole)
      end
    end
  end
  check("layout: the identity never disappears -- every rung still draws a mark",
    w1.mark_w > 0 and t1.mark_w > 0 and n1.mark_w > 0)
end

do
  local font = {
    getHeight = function() return 8 end,
    getWidth = function(_, s) return #tostring(s) * 4 end,
  }
  local card = { config = { center = { key = "j_joker", set = "Joker" } }, ability = { set = "Joker" },
    edition = { foil = true } }
  local layout = Badges.layout(Badges.collect(card), font, 200, 1, 2)
  local item = layout.items and layout.items[1]
  check("layout: a wide row shows name and effect together",
    item and item.text == "Foil +50c", item and item.text)
  check("layout: item keeps color key 'Foil'", item and item.key == "Foil", item and item.key)
end

local FONT = {
  getHeight = function() return 8 end,
  getWidth = function(_, s) return #tostring(s) * 4 end,
}
local function has_overflow_chip(items)
  for _, it in ipairs(items) do
    if type(it.text) == "string" and it.text:sub(1, 1) == "+" then return true end
  end
  return false
end

do
  local heavy = {
    { kind = "edition", text = "Foil +50c", key = "Foil" },
    { kind = "enhancement", text = "Gold +$3" },
    { kind = "seal", text = "Gold Seal" },
    { kind = "sticker", text = "Eternal" },
    { kind = "sticker", text = "Perish 3" },
    { kind = "sticker", text = "Rental" },
  }
  local MAX_ROWS = 3
  local all_ok, detail = true, nil
  for _, mw in ipairs({ 32, 60, 90, 140, 240, 480 }) do
    local L = Badges.layout(heavy, FONT, mw, 1, MAX_ROWS)
    for _, it in ipairs(L.items) do
      if it.x < 0 or it.w <= 0 or it.x + it.w > mw + 0.5 then
        all_ok = false; detail = string.format("overflow @w=%d: item x=%.1f w=%.1f (max %d)", mw, it.x, it.w, mw)
      end
    end
    if L.rows > MAX_ROWS then all_ok = false; detail = "rows " .. L.rows .. " > " .. MAX_ROWS .. " @w=" .. mw end
    if L.height < 0 then all_ok = false; detail = "negative height @w=" .. mw end
  end
  check("scaling: even 6 pills stay bounded (no overflow, rows<=3)", all_ok, detail)
end

do
  local real4 = {
    { kind = "edition", text = "Foil +50c", key = "Foil" },
    { kind = "enhancement", text = "Gold +$3" },
    { kind = "seal", text = "Red Seal" },
    { kind = "sticker", text = "Eternal" },
  }
  local all_ok, detail = true, nil
  for _, mw in ipairs({ 120, 160, 240, 480 }) do
    local L = Badges.layout(real4, FONT, mw, 1, 3)
    if #L.items ~= #real4 then all_ok = false; detail = "dropped a badge @w=" .. mw .. " (items=" .. #L.items .. ")" end
    if has_overflow_chip(L.items) then all_ok = false; detail = "collapsed to +N @w=" .. mw end
  end
  check("all-visible: 4 real modifiers never collapse to +N at real widths", all_ok, detail)
end

do
  local glass_tip = Badges.tip({ kind = "enhancement", key = "m_glass" })
  check("tip: Glass odds fall back to the headless config when G.P_CENTERS is absent",
    glass_tip == "x2 mult, 1/4 it shatters", glass_tip)

  local lucky_tip = Badges.tip({ kind = "enhancement", key = "m_lucky" })
  check("tip: Lucky odds fall back to the headless config when G.P_CENTERS is absent",
    lucky_tip == "1/5: +20 mult, 1/15: $20", lucky_tip)

  local prior_centers = G.P_CENTERS
  G.P_CENTERS = {
    m_glass = { config = { Xmult = 3, extra = 6 } },
    m_lucky = { config = { mult = 30, p_dollars = 40 } },
  }
  local glass_live = Badges.tip({ kind = "enhancement", key = "m_glass" })
  check("tip: Glass odds read live from G.P_CENTERS when present",
    glass_live == "x3 mult, 1/6 it shatters", glass_live)
  local lucky_live = Badges.tip({ kind = "enhancement", key = "m_lucky" })
  check("tip: Lucky odds read live from G.P_CENTERS when present",
    lucky_live == "1/5: +30 mult, 1/15: $40", lucky_live)
  G.P_CENTERS = prior_centers
end

done()
