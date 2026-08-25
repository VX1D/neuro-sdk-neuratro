
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local DRAWS = {}
local CIRCLES = {}
local CURRENT_R, CURRENT_G, CURRENT_B, CURRENT_ALPHA, CURRENT_COLOR_ID = 1, 1, 1, 1, 0
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local function record_draw(...)
  local args = { ... }
  DRAWS[#DRAWS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4], sx = args[6], sy = args[7] }
end
local function record_rect(mode, x, y, w, h)
  RECTS[#RECTS + 1] = {
    mode = mode, x = x, y = y, w = w, h = h,
    r = CURRENT_R, g = CURRENT_G, b = CURRENT_B, a = CURRENT_ALPHA, color_id = CURRENT_COLOR_ID,
  }
end
local function record_color(r, g, b, a)
  CURRENT_COLOR_ID = CURRENT_COLOR_ID + 1
  if type(r) == "table" then
    CURRENT_R, CURRENT_G, CURRENT_B, CURRENT_ALPHA = r[1], r[2], r[3], r[4] or 1
  else
    CURRENT_R, CURRENT_G, CURRENT_B, CURRENT_ALPHA = r, g, b, a or 1
  end
end
local function record_circle(mode, x, y, r)
  CIRCLES[#CIRCLES + 1] = { mode = mode, x = x, y = y, r = r }
end
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  print = record_print,
  draw = record_draw,
  rectangle = record_rect,
  setColor = record_color,
  circle = record_circle,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("acquire compact layout bounds")

local Cards = require("hud.cards")
local HudState = require("hud.state")
local Acquire = require("render.panels.acquire")

G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }
G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95 }

local LONG_NAME = "Supercalifragilistic Expialidocious Enchanted Joker of the Deep"
local long_card = {
  config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 },
    name = LONG_NAME, loc_txt = { name = LONG_NAME, text = "A very long description of the deep" } } },
  ability = { eternal = true, perishable = true, rental = true },
  edition = { holo = true },
  seal = "Gold",
  cost = 20,
}

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = CLR(), CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local function panel_ctx(evil, neuro, sw)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  theme.pk = (neuro and "neuro") or (evil and "evil") or "hiyori"
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = {
      rn = id, ln = id, rp_sh = 1, lp_sh = 1, sw = sw, sh = 540, U = 4,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      text_h = 12,
    },
    data = {
      sn = "SHOP", state_name = "SHOP",
      showcase_card = long_card, showcase_name = LONG_NAME, showcase_label = "NEW CARD",
      showcase_desc = LONG_NAME,
      showcase_alpha = 1, showcase_slide = 0,
    },
    draw = {
      trunc = function(s) return s end,
      wrapped_lines = function(s, maxw) return maxw and maxw > 0 and { "a", "b" } or { s } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end,
    },
    center_top_y = 8,
  }
end

local function receipt_state()
  HudState.buy_showcase = { card = long_card, name = LONG_NAME, area = "shop", cost = 20, started = -0.5 }
  HudState.joker_showcase = nil
end

local function showcase_state(label, started)
  HudState.buy_showcase = nil
  HudState.joker_showcase = { card = long_card, label = label or "NEW JOKER", started = started or -0.5 }
end

local function printed_text()
  return table.concat(PRINTED, "")
end

local function rects_valid(sw, sh)
  sh = sh or 540
  for _, r in ipairs(RECTS) do
    if r.w <= 0 or r.h < 1 then return false, "dim " .. r.w .. "x" .. r.h end
    if r.x < -6 or r.x + r.w > sw + 6 then return false, "x " .. r.x .. "+" .. r.w .. ">" .. sw end
    if r.y < -6 or r.y + r.h > sh + 6 then return false, "y " .. r.y .. "+" .. r.h .. ">" .. sh end
    if r.mode == "fill" and r.h == 20 and (r.w < 2 or r.x < 0 or r.x + r.w > sw) then
      return false, "badge " .. r.w .. " at " .. r.x
    end
  end
  for _, c in ipairs(CIRCLES) do
    if c.x - c.r < -6 or c.x + c.r > sw + 6 or c.y - c.r < -6 or c.y + c.r > sh + 6 then
      return false, "circle " .. c.x .. "/" .. c.y .. " r" .. c.r
    end
  end
  return true
end

local function count_degenerate_pills()
  local n = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.h == 20 and r.w >= 0 and r.w <= 1 then n = n + 1 end
  end
  return n
end
local function semantic_rect_count()
  local per_colour, seen, n = {}, {}, 0
  for _, r in ipairs(RECTS) do
    per_colour[r.color_id] = (per_colour[r.color_id] or 0) + 1
  end
  for _, r in ipairs(RECTS) do
    local a = r.a or 0
    local ring_shadow = r.r == 0 and r.g == 0 and r.b == 0
      and (math.abs(a - 0.11) < 1e-9 or math.abs(a - 0.154) < 1e-9)
      and per_colour[r.color_id] > 1
    if not ring_shadow or not seen[r.color_id] then n = n + 1 end
    seen[r.color_id] = true
  end
  return n
end

local personas = {
  { label = "evil", evil = true, neuro = false },
  { label = "neuro", evil = false, neuro = true },
}
local viewports = { 320, 640, 960, 1280, 1920 }

for _, p in ipairs(personas) do
  for _, sw in ipairs(viewports) do
    receipt_state()
    RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
    local tag = p.label .. "@" .. sw
    local ok, err = xpcall(function() Acquire.draw(panel_ctx(p.evil, p.neuro, sw)) end, debug.traceback)
    check("receipt " .. tag .. " executes", ok, err)
    local vok, vwhy = rects_valid(sw)
    check("receipt " .. tag .. " rects positive and inside viewport", vok, vwhy)
    local text = printed_text()
    check("receipt " .. tag .. " shows label and name", text:find("BOUGHT", 1, true) ~= nil and text:find("Joker", 1, true) ~= nil)
    if sw >= 1280 then
      check("receipt " .. tag .. " keeps the thumbnail at full width", #DRAWS >= 1, #DRAWS)
    end
    showcase_state()
    RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
    local ok2, err2 = xpcall(function() Acquire.draw(panel_ctx(p.evil, p.neuro, sw)) end, debug.traceback)
    check("showcase " .. tag .. " executes", ok2, err2)
    local vok2, vwhy2 = rects_valid(sw)
    check("showcase " .. tag .. " rects positive and inside viewport", vok2, vwhy2)
    local text2 = printed_text()
    check("showcase " .. tag .. " shows label and name", text2:find("NEW JOKER", 1, true) ~= nil and text2:find("Joker", 1, true) ~= nil)
    if sw >= 1280 then
      check("showcase " .. tag .. " keeps full layout with mini", #DRAWS >= 1, #DRAWS)
    end
  end
end

local evil_label = "SACRIFICIAL RITE OF THE BLOOD MOON ETERNAL"
for _, sw in ipairs({ 320, 640 }) do
  showcase_state(evil_label)
  local ctx = panel_ctx(true, false, sw)
  RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
  local ok, err = xpcall(function() Acquire.draw(ctx) end, debug.traceback)
  check("evil long label showcase @" .. sw .. " executes", ok, err)
  local vok, vwhy = rects_valid(sw)
  check("evil long label showcase @" .. sw .. " keeps ornaments in viewport", vok, vwhy)
end

for _, p in ipairs(personas) do
  for sw = 1280, 100, -10 do
    receipt_state()
    RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
    local ok, err = xpcall(function() Acquire.draw(panel_ctx(p.evil, p.neuro, sw)) end, debug.traceback)
    check("receipt sweep " .. p.label .. "@" .. sw .. " executes", ok, err)
    local vok, vwhy = rects_valid(sw)
    check("receipt sweep " .. p.label .. "@" .. sw .. " has no degenerate widths", vok, vwhy)
    local text = printed_text()
    if sw >= 320 then
      check("receipt sweep " .. p.label .. "@" .. sw .. " keeps label and name", text:find("BOUGHT", 1, true) ~= nil and text:find("Joker", 1, true) ~= nil)
    else
      check("receipt sweep " .. p.label .. "@" .. sw .. " keeps label", text:find("BOUGHT", 1, true) ~= nil)
    end
    check("receipt sweep " .. p.label .. "@" .. sw .. " has no 0-1px badge", count_degenerate_pills() == 0, count_degenerate_pills())
    local pr
    for _, r in ipairs(RECTS) do
      if r.mode == "line" and r.w >= 60 then pr = r break end
    end
    check("receipt sweep " .. p.label .. "@" .. sw .. " box respects the narrow clamp",
      pr ~= nil and pr.w <= math.max(80, sw - 16) and pr.w >= math.min(80, sw - 16),
      pr and pr.w or "no panel rect")
  end
end

for _, p in ipairs(personas) do
  for _, sw in ipairs({ 320, 640 }) do
    showcase_state(nil, -2.0)
    RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
    local ok_steady, _ = xpcall(function() Acquire.draw(panel_ctx(p.evil, p.neuro, sw)) end, debug.traceback)
    local steady_rects = semantic_rect_count()
    showcase_state(nil, 0.5)
    local ctx = panel_ctx(p.evil, p.neuro, sw)
    ctx.motion.now = 0.6
    RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
    local ok, err = xpcall(function() Acquire.draw(ctx) end, debug.traceback)
    check("showcase animated frame " .. p.label .. "@" .. sw .. " executes", ok, err)
    local vok, vwhy = rects_valid(sw)
    check("showcase animated frame " .. p.label .. "@" .. sw .. " keeps ornaments in viewport", vok, vwhy)
    if p.neuro then
      check("showcase appear " .. p.label .. "@" .. sw .. " adds ornament geometry",
        ok_steady and semantic_rect_count() > steady_rects,
        semantic_rect_count() .. " vs " .. steady_rects)
    else
      check("showcase appear " .. p.label .. "@" .. sw .. " stays on the neutral spine",
        ok_steady and semantic_rect_count() >= steady_rects,
        semantic_rect_count() .. " vs " .. steady_rects)
    end
  end
end

local function showcase_frame(sw, n_lines, desc)
  local ctx = panel_ctx(false, false, sw)
  ctx.draw.wrapped_lines = function(str, maxw)
    if not (maxw and maxw > 0) then return { str } end
    local out = {}
    for i = 1, n_lines do out[i] = "line " .. i end
    return out
  end
  showcase_state()
  RECTS, PRINTED, DRAWS, CIRCLES = {}, {}, {}, {}
  local ok, err = xpcall(function() Acquire.draw(ctx) end, debug.traceback)
  if not ok then return nil, err end
  local best
  for _, r in ipairs(RECTS) do
    if r.w and r.h and (not best or r.w * r.h > best.w * best.h) then best = r end
  end
  return best
end
for _, sw in ipairs({ 640, 960, 1920 }) do
  local small, err_s = showcase_frame(sw, 1, "short")
  local big, err_b = showcase_frame(sw, 6, LONG_NAME)
  check("showcase frame @" .. sw .. " renders both extremes", small ~= nil and big ~= nil,
    tostring(err_s or err_b))
  if small and big then
    check("showcase frame @" .. sw .. " grows with description length",
      big.h > small.h, small.h .. " vs " .. big.h)
    check("showcase frame @" .. sw .. " never shrinks below the card mini",
      small.h >= 110 + 8, small.h)
    check("showcase frame @" .. sw .. " width stays within the clamp",
      big.w <= 500 + 8 and small.w <= 500 + 8, small.w .. "/" .. big.w)
  end
end

done()
