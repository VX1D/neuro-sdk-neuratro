local M = {}

function M.install(get_printed, get_draws, get_rects)
  local FONT = {
    getWidth = function(_, s) return #tostring(s or "") * 8 end,
    getHeight = function() return 12 end,
  }
  local function noop() end
  local record_print = require("tests.helpers").print_recorder(get_printed)
  local function record_draw(...)
    local args = { ... }
    local DRAWS = get_draws()
    DRAWS[#DRAWS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4], sx = args[6], sy = args[7] }
  end
  local record_rect = require("tests.helpers").rect_recorder(get_rects)
  local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
    getDimensions = function() return 64, 64 end }
  local gfxstub = setmetatable({
    getFont = function() return FONT end,
    newFont = function() return FONT end,
    getWidth = function() return 1920 end,
    getHeight = function() return 1080 end,
    getShader = function() return nil end,
    getBlendMode = function() return "alpha", "alphamultiply" end,
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
    newImage = function() return IMG end,
    newMesh = function() return {} end,
    print = record_print,
    draw = record_draw,
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
    FUNCS = {}, TIMERS = { REAL = 1 }, STATES = require("tests.engine_cards").states(),
    SETTINGS = { paused = false, GAMESPEED = 1 },
    C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
    ARGS = {}, P_CENTERS = require("tests.engine_centers").centers(), P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
    ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
    I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  }
  require("tests.engine_cards").install_smods({ current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end })
  _G.NFS = setmetatable({}, { __index = function() return noop end })
  return { FONT = FONT, IMG = IMG, noop = noop }
end

function M.atlas(IMG)
  local atlas_entry = function(px, py) return { image = IMG, px = px, py = py } end
  G.ASSET_ATLAS.FIX71 = atlas_entry(71, 95)
  G.ASSET_ATLAS.FIX95 = atlas_entry(95, 95)
  G.ASSET_ATLAS.FIX50 = atlas_entry(50, 100)
  G.ASSET_ATLAS.FIX120 = atlas_entry(120, 80)
  G.ASSET_ATLAS.centers = atlas_entry(71, 95)
end

local function make_card(key, atlas_key)
  return {
    config = { center = { key = key or "j_fixture", set = "Joker", atlas = atlas_key or "FIX71", pos = { x = 0, y = 0 }, name = key } },
    ability = {},
    cost = 5,
  }
end
M.make_card = make_card

function M.new_img(id)
  return { id = id, getWidth = function() return 512 end, getHeight = function() return 512 end,
    getDimensions = function() return 512, 512 end }
end

return M
