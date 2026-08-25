
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
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
  rectangle = record_rect,
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

local check, done = require("tests.helpers").harness("acquire mini scale and badges")

local HudState = require("hud.state")
local Cards = require("hud.cards")
local Acquire = require("render.panels.acquire")

local atlas_entry = function(px, py) return { image = IMG, px = px, py = py } end
G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
G.ASSET_ATLAS.centers = atlas_entry(71, 95)
G.ASSET_ATLAS.cards_1 = atlas_entry(71, 95)

local function joker_with(ed, debuff)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = "FIX71", pos = { x = 0, y = 0 }, name = "Hologram" } },
    ability = {},
    edition = ed,
    debuff = debuff,
    cost = 6,
  }
end

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
local function receipt_ctx(evil, neuro, sw)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = {
      rn = id, ln = id, rp_sh = 1, lp_sh = 1, sw = sw or 960, sh = 1080, U = 4,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      text_h = 12,
    },
    data = { sn = "SHOP", state_name = "SHOP" },
    draw = { trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end },
    center_top_y = 8,
  }
end

RECTS, PRINTED = {}, {}
local holo_joker = joker_with({ holo = true })
local w_mini = Cards.draw_card_mini(holo_joker, 0, 0, 40, 1, true)
check("joker miniature width at h=40 is at least 30px", w_mini >= 30, w_mini)

local function edition_badge_printed()
  for _, p in ipairs(PRINTED) do
    if p == "HOLO" or p == "FOIL" or p == "POLY" or p == "NEG" then return true end
  end
  return false
end
check("skip_art_badge=true omits art text badge", not edition_badge_printed())

RECTS, PRINTED = {}, {}
Cards.draw_card_mini(joker_with({ holo = true }), 0, 0, 40, 1, false)
check("skip_art_badge=false still prints the art text badge (control for the check above)",
  edition_badge_printed(), table.concat(PRINTED, "|"))

RECTS, PRINTED = {}, {}
local debuffed_joker = joker_with(nil, true)
Cards.draw_card_mini(debuffed_joker, 0, 0, 40, 1)
check("debuff overlay DB printed", table.concat(PRINTED, ""):find("DB", 1, true) ~= nil)

local personas = {
  { label = "hiyori", evil = false, neuro = false },
  { label = "evil", evil = true, neuro = false },
  { label = "neuro", evil = false, neuro = true },
}
local viewports = { 960, 1280, 1920 }

for _, p in ipairs(personas) do
  for _, sw in ipairs(viewports) do
    RECTS, PRINTED = {}, {}
    HudState.joker_showcase = nil
    HudState.buy_showcase = { card = holo_joker, name = "Hologram", area = "shop", cost = 6, started = 0.9 }
    local tag = p.label .. "@" .. sw .. "px"
    local ok, err = xpcall(function() Acquire.draw(receipt_ctx(p.evil, p.neuro, sw)) end, debug.traceback)
    check("acquire panel renders at " .. tag .. " without error", ok, err)
  end
end

done()
