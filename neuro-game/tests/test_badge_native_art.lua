
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local DRAWS, PRIMS = {}, {}
local COLOR
local function record_draw(image, quad, x, y, _, sx, sy)
  DRAWS[#DRAWS + 1] = { image = image, quad = quad, x = x, y = y, sx = sx, sy = sy }
end
local function record_prim(kind)
  return function(...)
    PRIMS[#PRIMS + 1] = { kind = kind, args = { ... }, col = COLOR }
  end
end
local IMG = { getWidth = function() return 497 end, getHeight = function() return 475 end,
  getDimensions = function() return 497, 475 end }
local QUADS = {}
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getColor = function() return 1, 1, 1, 1 end,
  getLineWidth = function() return 1 end,
  newQuad = function(sx, sy, w, h)
    local q = { sx = sx, sy = sy, w = w, h = h }
    QUADS[#QUADS + 1] = q
    return q
  end,
  newImage = function() return IMG end,
  draw = record_draw,
  circle = record_prim("circle"),
  polygon = record_prim("polygon"),
  rectangle = record_prim("rectangle"),
  setColor = function(r, g, b, a) COLOR = { r, g, b, a } end,
  print = noop,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end },
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local ATLAS = { image = IMG, px = 71, py = 95 }
_G.G = {
  ASSET_ATLAS = { centers = ATLAS, stickers = ATLAS },
  P_CENTERS = { m_steel = { pos = { x = 6, y = 1 }, set = "Enhanced", name = "Steel Card" } },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  SETTINGS = {}, TIMERS = { REAL = 0 },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {} }

local check, done = require("tests.helpers").harness("badge glyph marks")

local Cards = require("hud.cards")
local Badges = require("render.modifier_badges")

local THEME = setmetatable({ persona_evil = true, _pal = {} },
  { __index = function() return { 1, 1, 1 } end })

local function reset()
  DRAWS, PRIMS, QUADS = {}, {}, {}
  Cards.clear_quad_cache()
  Cards._badge_icon_missing = 0
end

local function render(badges)
  reset()
  local layout = Badges.layout(badges, FONT, 400, 2, 3, nil)
  Badges.draw(layout, 0, 0, 1, THEME)
  return layout
end

local function card_with(fields)
  local c = { config = { center = { key = "j_joker", set = "Joker" } }, ability = { set = "Joker" } }
  for k, v in pairs(fields) do
    if k == "ability" then for ak, av in pairs(v) do c.ability[ak] = av end else c[k] = v end
  end
  return c
end

local KINDS = {
  { kind = "edition", card = card_with({ edition = { holo = true } }) },
  { kind = "seal", card = card_with({ seal = "Gold" }) },
  { kind = "sticker", card = card_with({ ability = { eternal = true } }) },
  { kind = "enhancement", card = { base = { value = "7", suit = "Hearts" },
      config = { center = { key = "m_steel", set = "Enhanced" } }, ability = { set = "Enhanced" } } },
}

local function glyph_rects(item)
  local out = {}
  local lo = ((item.cap or 0) - (item.mark_w or 0)) / 2
  local hi = lo + (item.mark_w or 0)
  for _, p in ipairs(PRIMS) do
    if p.kind == "rectangle" then
      local mode, px, py, pw, ph = p.args[1], p.args[2], p.args[3], p.args[4], p.args[5]
      if px and mode == "fill" and ph and ph <= (item.mark or item.h)
        and px >= lo - 1 and (px + (pw or 0)) <= hi + 1 then
        out[#out + 1] = { x = px, y = py, w = pw, h = ph, col = p.col }
      end
    end
  end
  return out
end

local function glyph_bbox(item)
  local x0, y0, x1, y1
  for _, r in ipairs(glyph_rects(item)) do
    x0 = math.min(x0 or r.x, r.x); y0 = math.min(y0 or r.y, r.y)
    x1 = math.max(x1 or (r.x + r.w), r.x + r.w); y1 = math.max(y1 or (r.y + r.h), r.y + r.h)
  end
  if not x0 then return nil end
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

for _, case in ipairs(KINDS) do
  local badges = Badges.collect(case.card)
  local layout = render(badges)
  local item
  for _, it in ipairs(layout.items) do if it.kind == case.kind then item = it end end

  check(case.kind .. ": collect produces the badge", item ~= nil)
  if item then
    check(case.kind .. ": layout reserves room for a mark", (item.lead or 0) > 0 and (item.mark_w or 0) > 0,
      tostring(item.lead) .. "/" .. tostring(item.mark_w))
    check(case.kind .. ": the label starts after the mark, never on top of it",
      item.lead >= item.mark_w, tostring(item.lead) .. " vs " .. tostring(item.mark_w))
    check(case.kind .. ": the mark is drawn", #PRIMS > 0, #PRIMS)
    check(case.kind .. ": no atlas sprite is pulled for a 7px mark", #DRAWS == 0 and #QUADS == 0,
      tostring(#DRAWS) .. " draws / " .. tostring(#QUADS) .. " quads")

    local bb = glyph_bbox(item)
    check(case.kind .. ": the drawn mark matches the width layout reserved",
      bb and math.abs(bb.w - item.mark_w) <= 1, bb and (bb.w .. " vs " .. item.mark_w))
    check(case.kind .. ": the mark stays inside the row height",
      bb and bb.h <= item.h, bb and (bb.h .. " vs " .. item.h))
  end
end

do
  local layout = render(Badges.collect(card_with({ edition = { holo = true } })))
  local ed = layout.items[1]
  check("edition now leads with a mark like every other kind", ed and ed.kind == "edition"
    and (ed.mark_w or 0) > 0 and #PRIMS > 0, ed and ed.mark_w)
end

do
  local function head(card)
    local layout = render(Badges.collect(card))
    local item = layout.items[1]
    if not item then return nil end
    local sig, cap = {}, nil
    for _, p in ipairs(PRIMS) do
      local mode, px, pw = p.args[1], p.args[2], p.args[4]
      if p.kind == "rectangle" and mode == "fill" and p.col and (px or 0) < (item.cap or 0) then
        sig[#sig + 1] = string.format("%.3f/%.3f/%.3f/%.3f@%s:%s",
          p.col[1], p.col[2], p.col[3], p.col[4] or 1, tostring(px), tostring(pw))
        if (px or 0) == 0 and pw == item.cap and p.args[5] == item.h then cap = p.col end
      end
    end
    return table.concat(sig, "|"), cap, item
  end

  local holo = head(card_with({ edition = { holo = true } }))
  local foil = head(card_with({ edition = { foil = true } }))
  check("a Foil chip head and a Holo chip head are not the same pixels",
    holo and foil and holo ~= foil)

  local function luma(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
  local _, cap, item = head(card_with({ ability = { eternal = true } }))
  local mark = item and glyph_rects(item)[1] and glyph_rects(item)[1].col or nil
  check("the mark is knocked out of its cap, not lost in it",
    cap and mark and (luma(cap) - luma(mark)) > 0.25,
    cap and mark and string.format("%.3f vs %.3f", luma(cap), luma(mark)))
end

do
  local many = {}
  for i = 1, 8 do many[i] = { kind = "sticker", text = "Sticker " .. i, key = "eternal" } end
  reset()
  local layout = Badges.layout(many, FONT, 90, 2, 1, nil)
  local last = layout.items[#layout.items]
  check("the overflow chip carries no mark", last and last.kind == "overflow"
    and (last.mark_w or 0) == 0 and (last.lead or 0) == 0, last and last.kind)
end

do
  local card = { base = { value = "7", suit = "Hearts" },
    config = { center = { key = "m_steel", set = "Enhanced" } },
    ability = { set = "Enhanced", eternal = true }, edition = { holo = true }, seal = "Gold" }
  local layout = render(Badges.collect(card))
  local marked = 0
  for _, it in ipairs(layout.items) do if (it.mark_w or 0) > 0 then marked = marked + 1 end end
  check("every badge in a mixed row gets its own mark", #layout.items == 4 and marked == 4,
    tostring(marked) .. "/" .. tostring(#layout.items))
  check("a mixed row still pulls no atlas art", #DRAWS == 0 and #QUADS == 0, #DRAWS)
end

done()
