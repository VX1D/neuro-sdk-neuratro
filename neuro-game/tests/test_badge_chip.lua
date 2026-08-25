
_G.NEURO_TEST = true

local RECTS = {}
local COL = { 1, 1, 1, 1 }
local function record_rect(mode, x, y, w, h, rad)
  RECTS[#RECTS + 1] = { mode = mode, x = x, y = y, w = w, h = h, rad = rad,
    col = { COL[1], COL[2], COL[3], COL[4] } }
end
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 7 end,
  getHeight = function() return 14 end,
}
local function noop() end
love = {
  graphics = setmetatable({
    rectangle = record_rect,
    setColor = function(r, g, b, a) COL[1], COL[2], COL[3], COL[4] = r, g, b, a end,
    getColor = function() return COL[1], COL[2], COL[3], COL[4] end,
    getFont = function() return FONT end,
    setFont = noop,
    getLineWidth = function() return 1 end,
    print = noop,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end },
}
_G.G = { STATES = {}, GAME = {},
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }

local check, done = require("tests.helpers").harness("badge chip")
local Badges = require("render.modifier_badges")

local function CLR(r, g, b) return { r or 0.6, g or 0.6, b or 0.6 } end
local function theme_for(which)
  return {
    pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(0.3, 0.3, 0.33), FRD = CLR(),
    ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(0.37, 0.69, 0.41), DIM = CLR(0.5, 0.5, 0.5),
    WHITE = CLR(1, 1, 1), CYAN = CLR(0.35, 0.65, 0.94), GOLD = CLR(0.93, 0.71, 0.13),
    persona_evil = which == "evil" or nil,
    persona_neuro = which == "neuro" or nil,
    _pal = setmetatable({}, { __index = function() return CLR() end }),
  }
end
local MO = { pulse = 0.5, shimr = 0.9, shimg = 0.5, shimb = 0.8 }

local function card_with(t)
  local c = { config = { center = { key = "j_joker", set = "Joker" } }, ability = {} }
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function render(badges, which)
  RECTS = {}
  local layout = Badges.layout(badges, FONT, 400, 1, 3)
  Badges.draw(layout, 0, 0, 1, theme_for(which), MO)
  return layout
end

local function plates(item)
  local out = {}
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w and r.h and math.abs(r.w - item.w) <= 1
      and math.abs(r.h - item.h) <= 1 and math.abs((r.x or 0) - item.x) <= 1 then
      out[#out + 1] = r
    end
  end
  return out
end

local KINDS = {
  { kind = "edition",     card = card_with({ edition = { holo = true } }) },
  { kind = "seal",        card = card_with({ seal = "Gold" }) },
  { kind = "sticker",     card = card_with({ ability = { eternal = true } }) },
  { kind = "enhancement", card = { base = { value = "7", suit = "Hearts" },
      config = { center = { key = "m_steel", set = "Enhanced" } }, ability = { set = "Enhanced" } } },
}

for _, case in ipairs(KINDS) do
  local layout = render(Badges.collect(case.card), "hiyori")
  local item
  for _, it in ipairs(layout.items) do if it.kind == case.kind then item = it end end
  check(case.kind .. ": the badge exists", item ~= nil)
  if item then
    check(case.kind .. ": gets one composited ink+hue plate", #plates(item) == 1, #plates(item))
    check(case.kind .. ": the label starts inside its own chip",
      item.lead >= (item.pad or 0) and item.lead + (item.pad or 0) <= item.w,
      item.lead .. "/" .. tostring(item.pad) .. " in " .. item.w)
  end

end

do
  local layout = render(Badges.collect(card_with({ ability = { eternal = true } })), "hiyori")
  local item = layout.items[1]
  local plate = item and plates(item)[1]
  local ab, ah = Badges.PLATE.ink, Badges.PLATE.hue.sticker
  local expected_a = ah + ab * (1 - ah)
  local expected_k = ah / expected_a
  local tint = { 0.78, 0.35, 0.52 }
  local eps = 1e-9
  check("composited plate keeps source-over alpha",
    plate and math.abs(plate.col[4] - expected_a) <= eps,
    plate and plate.col[4])
  check("composited plate keeps source-over premultiplied colour",
    plate and math.abs(plate.col[1] - tint[1] * expected_k) <= eps
      and math.abs(plate.col[2] - tint[2] * expected_k) <= eps
      and math.abs(plate.col[3] - tint[3] * expected_k) <= eps,
    plate and table.concat(plate.col, ",", 1, 3))
  local bg = { 0.17, 0.43, 0.81 }
  local max_lsb = 0
  if plate then
    for i = 1, 3 do
      local old_px = tint[i] * ah + bg[i] * (1 - ab) * (1 - ah)
      local new_px = plate.col[i] * plate.col[4] + bg[i] * (1 - plate.col[4])
      local old_q = math.floor(old_px * 255 + 0.5)
      local new_q = math.floor(new_px * 255 + 0.5)
      max_lsb = math.max(max_lsb, math.abs(old_q - new_q))
    end
  end
  check("composited plate raster differs by at most one LSB", plate and max_lsb <= 1, max_lsb)
end

do
  local many = {}
  for i = 1, 7 do many[i] = { kind = "sticker", text = "Sticker " .. i, key = "eternal" } end
  RECTS = {}
  local layout = Badges.layout(many, FONT, 60, 1, 1)
  Badges.draw(layout, 0, 0, 1, theme_for("hiyori"), MO)
  local ov
  for _, it in ipairs(layout.items) do if it.kind == "overflow" then ov = it end end
  check("the overflow count appears", ov ~= nil)
  if ov then
    check("the +N count gets no plate -- it is a count, not a property", #plates(ov) == 0,
      #plates(ov))
    check("the T1 counter is a tile, not a text width", layout.tier == 1 and ov.w == 12,
      layout.tier .. "/" .. ov.w)
    check("the T1 counter carries its count as pips", ov.pips == 5, tostring(ov.pips))
    check("the T1 counter still fits the row height", ov.h == 12, ov.h)
    local pips = 0
    for _, r in ipairs(RECTS) do
      if r.mode == "fill" and r.x and r.x >= ov.x and r.x < ov.x + ov.w
        and (r.w or 0) <= 3 and (r.h or 0) <= 3 then
        pips = pips + 1
      end
    end
    check("five hidden pins are drawn as five pips", pips == 5, pips)
  end

  do
    local few = {}
    for i = 1, 7 do few[i] = { kind = "sticker", text = "Sticker " .. i, key = "eternal" } end
    local ok, detail = true, nil
    for w = 20, 700, 3 do
      for rows = 1, 3 do
        local L = Badges.layout(few, FONT, w, 1, rows)
        for _, it in ipairs(L.items) do
          if it.kind == "overflow" and (L.tier ~= 1 or it.pips == nil) then
            ok = false; detail = "w=" .. w .. " rows=" .. rows .. " tier=" .. L.tier
          end
        end
      end
    end
    check("the counter is never reached above T1", ok, detail)
  end
end

do
  local badges = Badges.collect(card_with({ edition = { holo = true } }))
  local geo, shape = {}, {}
  for _, which in ipairs({ "hiyori", "neuro", "evil" }) do
    local layout = render(badges, which)
    local it = layout.items[1]
    geo[which] = string.format("%d/%d/%d/%s/%s", it.x, it.w, it.h, tostring(it.lead),
      tostring(it.cap))
    local sig = {}
    for _, r in ipairs(RECTS) do
      sig[#sig + 1] = string.format("%s %.1f %.1f %.1f %.1f %.2f %.2f %.2f %.2f %.1f", r.mode,
        r.x or 0, r.y or 0, r.w or 0, r.h or 0, r.col[1], r.col[2], r.col[3], r.col[4], r.rad or 0)
    end
    shape[which] = table.concat(sig, "|")
  end

  check("chip geometry is identical across personas -- the cache has no persona in its key",
    geo.hiyori == geo.neuro and geo.neuro == geo.evil,
    geo.hiyori .. " | " .. geo.neuro .. " | " .. geo.evil)

  check("evil draws a different chip from hiyori", shape.evil ~= shape.hiyori)
  check("neuro draws a different chip from evil", shape.neuro ~= shape.evil)
  check("neuro draws a different chip from hiyori", shape.neuro ~= shape.hiyori)

  local function any_rounded(which)
    render(badges, which)
    for _, r in ipairs(RECTS) do if (r.rad or 0) > 0 then return true end end
    return false
  end
  check("neuro rounds its chip", any_rounded("neuro"))
  check("evil does not", not any_rounded("evil"))
  check("hiyori does not", not any_rounded("hiyori"))
end

do
  local function sticker_tint(flag)
    local layout = render(Badges.collect(card_with({ ability = { [flag] = true } })), "hiyori")
    local it = layout.items[1]
    for _, r in ipairs(plates(it)) do
      local ah = Badges.PLATE.hue.sticker
      if r.col[4] > 0 and r.col[1] + r.col[2] + r.col[3] > 0.01 then
        return {
          r.col[1] * r.col[4] / ah,
          r.col[2] * r.col[4] / ah,
          r.col[3] * r.col[4] / ah,
        }
      end
    end
  end

  G.C = setmetatable({
    ETERNAL = { 0.30, 0.30, 0.30, 1 },
    PERISHABLE = { 0.32, 0.32, 0.32, 1 },
    RENTAL = { 0.38, 0.38, 0.38, 1 },
  }, { __index = function() return { 1, 1, 1, 1 } end })

  local e, p, r = sticker_tint("eternal"), sticker_tint("perishable"), sticker_tint("rental")
  local function differs(a, b)
    return a and b and (math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])) > 0.15
  end
  check("a hue-less repaint does not collapse the three stickers into one colour",
    differs(e, p) and differs(p, r) and differs(e, r),
    table.concat({ tostring(e and e[1]), tostring(p and p[1]), tostring(r and r[1]) }, " / "))

  G.C = setmetatable({
    ETERNAL = { 0.365, 0.173, 0.220, 1 },
    PERISHABLE = { 0.170, 0.220, 0.400, 1 },
    RENTAL = { 0.400, 0.330, 0.140, 1 },
  }, { __index = function() return { 1, 1, 1, 1 } end })
  local lifted = sticker_tint("eternal")
  check("a dark repaint is lifted, not replaced", lifted and lifted[1] > 0.365
    and lifted[1] > lifted[2] and lifted[1] > lifted[3],
    lifted and table.concat(lifted, ",", 1, 3))

  G.C = setmetatable({
    ETERNAL = { 0.365, 0.173, 0.220, 1 },
    PERISHABLE = { 0.170, 0.220, 0.400, 1 },
    RENTAL = { 0.172, 0.222, 0.402, 1 },     -- a hair off Perishable: the pair that fails
  }, { __index = function() return { 1, 1, 1, 1 } end })
  local e2 = sticker_tint("eternal")
  local authored = { 0.78, 0.35, 0.52 }
  check("one unseparable pair sends all three back to the authored tints",
    e2 and math.abs(e2[1] - authored[1]) < 0.01 and math.abs(e2[2] - authored[2]) < 0.01
      and math.abs(e2[3] - authored[3]) < 0.01,
    e2 and table.concat(e2, ",", 1, 3))

  check("separable: a chroma gap alone is enough",
    Badges.separable({ 0.50, 0.50, 0.50 }, { 0.50, 0.50, 0.63 }))
  check("separable: a luminance gap alone is enough",
    Badges.separable({ 0.30, 0.30, 0.30 }, { 0.42, 0.42, 0.42 }))
  check("separable: neither gap is not enough",
    not Badges.separable({ 0.50, 0.50, 0.50 }, { 0.55, 0.52, 0.53 }))

  G.C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end })
end

do
  local KEYS = { "m_bonus", "m_mult", "m_wild", "m_glass",
    "m_steel", "m_gold", "m_lucky", "m_stone" }
  local function enh_tint(key)
    local layout = render({ { kind = "enhancement", text = "X", key = key } }, "hiyori")
    local it = layout.items[1]
    local ah = Badges.PLATE.hue.enhancement
    for _, r in ipairs(plates(it)) do
      if r.col[4] > 0 and r.col[1] + r.col[2] + r.col[3] > 0.01 then
        return { r.col[1] * r.col[4] / ah, r.col[2] * r.col[4] / ah, r.col[3] * r.col[4] / ah }
      end
    end
  end
  local tints = {}
  for _, k in ipairs(KEYS) do tints[k] = enh_tint(k) end
  local pairs_ok, detail = true, nil
  for i = 1, #KEYS do
    for j = i + 1, #KEYS do
      local a, b = tints[KEYS[i]], tints[KEYS[j]]
      if not (a and b and Badges.separable(a, b)) then
        pairs_ok = false; detail = KEYS[i] .. " vs " .. KEYS[j]
      end
    end
  end
  check("all 28 enhancement pairs separate", pairs_ok, detail)

  local function seal_tint()
    local layout = render(Badges.collect(card_with({ seal = "Gold" })), "hiyori")
    local it = layout.items[1]
    local ah = Badges.PLATE.hue.seal
    for _, r in ipairs(plates(it)) do
      if r.col[4] > 0 and r.col[1] + r.col[2] + r.col[3] > 0.01 then
        return { r.col[1] * r.col[4] / ah, r.col[2] * r.col[4] / ah, r.col[3] * r.col[4] / ah }
      end
    end
  end
  local gs = seal_tint()
  check("the Gold seal and the Gold enhancement are two different golds",
    gs and tints.m_gold and Badges.separable(gs, tints.m_gold),
    gs and tints.m_gold and (table.concat(gs, ",", 1, 3) .. " vs "
      .. table.concat(tints.m_gold, ",", 1, 3)))

  local moved = theme_for("hiyori")
  moved.GREEN = { 0.9, 0.1, 0.9 }
  RECTS = {}
  local lay = Badges.layout({ { kind = "enhancement", text = "X", key = "m_steel" } }, FONT, 400, 1, 3)
  Badges.draw(lay, 0, 0, 1, moved, MO)
  local ah = Badges.PLATE.hue.enhancement
  local after
  for _, r in ipairs(plates(lay.items[1])) do
    if r.col[4] > 0 then
      after = { r.col[1] * r.col[4] / ah, r.col[2] * r.col[4] / ah, r.col[3] * r.col[4] / ah }
    end
  end
  check("a repainted GREEN does not reach the enhancement tiles",
    after and math.abs(after[1] - tints.m_steel[1]) < 0.01,
    after and table.concat(after, ",", 1, 3))
end

do
  local empty = Badges.legend_deck()
  check("a run owning no effects yields an empty legend deck", #empty == 0, #empty)
  local none_list, none_entry = Badges.legend(0, empty)
  check("legend() on an empty deck has nothing to draw",
    none_list == nil and none_entry == nil)

  G.jokers = { cards = {
    card_with({ ability = { eternal = true } }),
    card_with({ edition = { holo = true } }),
  } }
  G.consumeables = { cards = { card_with({ edition = { foil = true } }) } }
  G.playing_cards = {
    card_with({ seal = "Gold" }),
    { base = { value = "7", suit = "Hearts" }, ability = { set = "Enhanced" },
      config = { center = { key = "m_glass", set = "Enhanced" } } },
  }
  G.shop_jokers = { cards = { card_with({ ability = { rental = true } }) } }

  local deck = Badges.legend_deck()
  check("owning effects fills the legend deck", #deck > 0, #deck)

  local held = {}
  for _, e in ipairs(deck) do held[e.kind .. "|" .. tostring(e.key)] = true end
  for _, want in ipairs({ "sticker|eternal", "edition|Holo", "edition|Foil",
    "seal|Gold", "enhancement|m_glass" }) do
    check("an owned " .. want .. " reaches the legend deck", held[want] == true)
  end
  check("an effect sitting in the shop never reaches the legend deck",
    held["sticker|rental"] ~= true)

  local kinds = {}
  for _, e in ipairs(deck) do
    kinds[e.kind] = true
    check("deck entry " .. tostring(e.text) .. " carries a tip",
      type(e.tip) == "string" and #e.tip > 0, tostring(e.tip))
    check("tip for " .. tostring(e.text) .. " fits the footer budget", #e.tip <= 34, #e.tip)
    check("deck entry " .. tostring(e.text) .. " is a real badge shape",
      e.kind ~= nil and e.key ~= nil and type(e.text) == "string" and #e.text > 0)
  end

  local produced = {}
  local probes = {
    card_with({ ability = { eternal = true } }),
    card_with({ ability = { rental = true } }),
    card_with({ ability = { perishable = true, perish_tally = 2 } }),
    card_with({ edition = { holo = true } }),
    card_with({ edition = { foil = true } }),
    card_with({ seal = "Gold" }),
    { base = { value = "7", suit = "Hearts" }, ability = { set = "Enhanced" },
      config = { center = { key = "m_glass", set = "Enhanced" } } },
  }
  for _, c in ipairs(probes) do
    for _, b in ipairs(Badges.collect(c)) do produced[b.kind .. "|" .. tostring(b.key)] = true end
  end
  for _, e in ipairs(deck) do
    check("deck entry " .. e.kind .. "|" .. tostring(e.key) .. " is one a card can wear",
      produced[e.kind .. "|" .. tostring(e.key)] == true)
  end

  local n = #deck
  for i = 0, n + 2 do
    local list, entry = Badges.legend(i, deck)
    check("legend(" .. i .. ") yields exactly one badge", list and #list == 1, list and #list)
    check("legend(" .. i .. ") returns its entry", entry ~= nil and entry.tip ~= nil)
    check("legend(" .. i .. ") wraps instead of running out",
      entry == deck[(i % n) + 1])
  end

  for i = 0, math.min(3, n - 1) do
    local list = Badges.legend(i, deck)
    local layout = render(list, "neuro")
    local it = layout.items[1]
    check("legend entry " .. i .. " lays out as a real chip",
      it and it.w > 0 and #plates(it) == 1,
      it and (it.w .. "px, " .. #plates(it) .. " plate"))
  end
end

do
  local function extent(layout)
    local w, h = 0, 0
    for _, it in ipairs(layout.items) do
      if it.x + it.w > w then w = it.x + it.w end
      if it.y + it.h > h then h = it.y + it.h end
    end
    return w, h
  end

  local multi = {
    card_with({ ability = { eternal = true }, edition = { holo = true }, seal = "Gold" }),
    card_with({ ability = { eternal = true, rental = true }, edition = { foil = true } }),
    { base = { value = "7", suit = "Hearts" }, ability = { set = "Enhanced", eternal = true },
      config = { center = { key = "m_glass", set = "Enhanced" } }, seal = "Red" },
  }

  for ci, card in ipairs(multi) do
    local badges = Badges.collect(card)
    for _, which in ipairs({ "neuro", "evil", "hiyori" }) do
      local layout = render(badges, which)
      local w, h = extent(layout)
      check(string.format("card %d draws two or more pins for %s (the case the ornaments gated on)",
        ci, which), #badges >= 2 and #layout.items >= 2, #layout.items)
      local worst, n_out = nil, 0
      for _, r in ipairs(RECTS) do
        local x0, y0 = r.x or 0, r.y or 0
        local x1, y1 = x0 + (r.w or 0), y0 + (r.h or 0)
        local over = math.max(-x0, -y0, x1 - w, y1 - h)
        if over > 0.51 then
          n_out = n_out + 1
          if not worst or over > worst.over then
            worst = { over = over, s = string.format("%s %.1f,%.1f %.0fx%.0f",
              r.mode, x0, y0, r.w or 0, r.h or 0) }
          end
        end
      end
      check(string.format("card %d paints nothing outside its own %.0fx%.0f block for %s",
        ci, w, h, which), n_out == 0,
        worst and string.format("%d ops outside, worst %s by %.1fpx", n_out, worst.s, worst.over))
    end
  end
end

do
  local Rows = require("hud.rows")
  local TARGETS = {
    ["ModifierBadges.layout"] = Badges.layout,
    ["Badges.layout"] = Badges.layout,
    ["layout_modifier_badges"] = Badges.layout,
    ["Rows.badge_layout"] = Rows.badge_layout,
  }
  local arity = {}
  for name, fn in pairs(TARGETS) do
    local info = debug.getinfo(fn, "u")
    arity[name] = (not info.isvararg) and info.nparams or math.huge
  end
  check("the scan knows the real arities and neither callee is vararg",
    arity["ModifierBadges.layout"] == 5 and arity["Rows.badge_layout"] == 6,
    string.format("layout=%s badge_layout=%s",
      tostring(arity["ModifierBadges.layout"]), tostring(arity["Rows.badge_layout"])))

  local function call_args(src, open_at)
    local depth, i, cur, out = 1, open_at + 1, {}, {}
    while i <= #src and depth > 0 do
      local c = src:sub(i, i)
      if c == "(" or c == "{" or c == "[" then depth = depth + 1; cur[#cur + 1] = c
      elseif c == ")" or c == "}" or c == "]" then
        depth = depth - 1
        if depth > 0 then cur[#cur + 1] = c end
      elseif c == '"' or c == "'" then
        local q = c; cur[#cur + 1] = c; i = i + 1
        while i <= #src do
          local d = src:sub(i, i)
          cur[#cur + 1] = d
          if d == "\\" then i = i + 1; cur[#cur + 1] = src:sub(i, i)
          elseif d == q then break end
          i = i + 1
        end
      elseif depth == 1 and c == "," then
        out[#out + 1] = table.concat(cur); cur = {}
      else
        cur[#cur + 1] = c
      end
      i = i + 1
    end
    local tail = table.concat(cur)
    if tail:find("%S") or #out > 0 then out[#out + 1] = tail end
    return out
  end

  local function scan_source(src, path)
    local seen, bad = 0, {}
    src = src:gsub("%-%-[^\n]*", "")
    for name, limit in pairs(arity) do
      local pattern = name:gsub("%.", "%%.") .. "%s*%("
      local pos = 1
      while true do
        local a, b = src:find(pattern, pos)
        if not a then break end
        if not src:sub(math.max(1, a - 10), a - 1):find("function%s*$") then
          seen = seen + 1
          local args = call_args(src, b)
          if #args > limit then
            bad[#bad + 1] = string.format("%s: %s passes %d args, callee takes %d",
              path, name, #args, limit)
          end
          for ix, text in ipairs(args) do
            if text:find("%f[%w_]trunc%f[%W]") then
              bad[#bad + 1] = string.format("%s: %s passes a truncator as argument %d (%s)",
                path, name, ix, (text:gsub("^%s+", "")))
            end
          end
        end
        pos = b + 1
      end
    end
    return seen, bad
  end

  local _, planted = scan_source(
    "local lay = layout_modifier_badges(cached.badges, sf, badge_w, rn(1), trunc)\n"
      .. "local two = Rows.badge_layout(k, b, f, w, g, 1, 2, 3, 4, 5, 6, 7)\n", "<planted>")
  check("the scan catches both shapes when they are present",
    #planted == 2, table.concat(planted, " | "))

  local FILES = {}
  local ls = io.popen("find render hud -name '*.lua' 2>/dev/null")
  for line in ls:lines() do FILES[#FILES + 1] = line end
  ls:close()

  local scanned, offenders = 0, {}
  for _, path in ipairs(FILES) do
    local fh = io.open(path, "r")
    if fh then
      local src = fh:read("*all"); fh:close()
      local n, bad = scan_source(src, path)
      scanned = scanned + n
      for _, v in ipairs(bad) do offenders[#offenders + 1] = v end
    end
  end

  check("the scan actually reached the badge-layout call sites",
    scanned >= 7, "call sites scanned: " .. scanned)
  check("no render/ or hud/ call site hands the badge layout a truncator or a stray argument",
    #offenders == 0, table.concat(offenders, " | "))
end

done()
