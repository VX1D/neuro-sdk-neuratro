rawset(_G, "NEURO_TEST", true)

local SW, SH = 1920, 1080
local OPS = {}
local COL, LW = { 1, 1, 1, 1 }, 1
local function noop() end

local _fonts = {}
local function mkfont(px)
  local f = _fonts[px]
  if not f then
    f = { px = px,
      getWidth = function(_, s) return math.floor(0.5 * px * #tostring(s or "") + 0.5) end,
      getHeight = function() return math.floor(1.15 * px + 0.5) end,
      getWrap = function(_, s, w)
        s = tostring(s or "")
        local per = math.max(1, math.floor(w / math.max(1, 0.5 * px)))
        local lines, cur = {}, ""
        for word in s:gmatch("%S+") do
          local cand = (cur == "") and word or (cur .. " " .. word)
          if #cand <= per then cur = cand else lines[#lines + 1] = cur; cur = word end
        end
        if cur ~= "" then lines[#lines + 1] = cur end
        if #lines == 0 then lines = { "" } end
        return w, lines
      end }
    _fonts[px] = f
  end
  return f
end
local CURFONT = mkfont(14)
local IMG = { getWidth = function() return 71 end, getHeight = function() return 95 end,
  getDimensions = function() return 71, 95 end }

local gfx = setmetatable({
  getFont = function() return CURFONT end,
  setFont = function(f) CURFONT = f or CURFONT end,
  newFont = function(a, b) return mkfont(tonumber(b) or tonumber(a) or 12) end,
  getWidth = function() return SW end,
  getHeight = function() return SH end,
  getShader = function() return nil end, setShader = noop,
  getBlendMode = function() return "alpha", "alphamultiply" end, setBlendMode = noop,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newImage = function() return IMG end, newMesh = function() return {} end,
  newCanvas = function() return nil end,
  setColor = function(r, g, b, a)
    if type(r) == "table" then COL = { r[1], r[2], r[3], r[4] or (g or 1) }
    else COL = { r or 1, g or 1, b or 1, a or 1 } end
  end,
  getColor = function() return COL[1], COL[2], COL[3], COL[4] end,
  setLineWidth = function(w) LW = w or 1 end,
  getLineWidth = function() return LW end,
  print = function(t, x, y)
    OPS[#OPS + 1] = { op = "T", text = tostring(t), x = x or 0, y = y or 0, px = CURFONT.px }
  end,
  printf = function(t, x, y)
    OPS[#OPS + 1] = { op = "T", text = tostring(t), x = x or 0, y = y or 0, px = CURFONT.px }
  end,
  rectangle = function(mode, x, y, w, h)
    OPS[#OPS + 1] = { op = "R", mode = mode, x = x or 0, y = y or 0, w = w or 0, h = h or 0 }
  end,
  circle = noop, line = noop, polygon = noop, arc = noop,
  push = noop, pop = noop, origin = noop, scale = noop, rotate = noop, translate = noop,
  draw = noop, setScissor = noop, intersectScissor = noop,
  getScissor = function() return nil end,
}, { __index = function() return noop end })

love = setmetatable({
  graphics = gfx,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
  math = { random = math.random, noise = function() return 0 end },
  keyboard = setmetatable({ isDown = function() return false end }, { __index = function() return noop end }),
  mouse = setmetatable({ getPosition = function() return 0, 0 end }, { __index = function() return noop end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
local function joker(name, key, rarity, cost)
  return { config = { center = { key = key, set = "Joker", name = name, rarity = rarity or 1,
      atlas = "FIX71", pos = { x = 0, y = 0 }, cost = cost or 5, config = {} } },
    ability = { name = name, set = "Joker", extra = {} }, cost = cost or 5,
    sell_cost = 2, T = { w = 1, h = 1 } }
end

_G.G = {
  NEURO = { persona = "hiyori", state = "SELECTING_HAND", enabled = true, purchase_showcase_queue = {},
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 27, pack_choices = 0, round = 3, chips = 0,
    round_resets = { ante = 4, blind_choices = {}, blind_states = {} },
    blind = {}, used_vouchers = {}, modifiers = {},
    current_round = { hands_left = 3, discards_left = 2, discards_used = 0 },
    starting_params = { hands = 4, discards = 3 }, probabilities = { normal = 1 },
    pseudorandom = { seed = "ABCD1234" }, bosses_used = {}, hands = {}, last_blind = {},
    interest_cap = 25, inflation = 0, win_ante = 8, skips = 0 },
  jokers = area({}, 5), consumeables = area({}, 2), hand = area({}, 8), deck = area({}, 52),
  play = area({}), discard = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 }, STATES = { SHOP = 5 },
  STAGE = 2, STAGES = { MAIN_MENU = 1, RUN = 2 },
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  STATE = 5, I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("hud surfaces")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local HUD = require("render.hud_overlay")
local Rows = require("hud.rows")
G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }
G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95 }

local COLORS = { D_GOLD = { 1, 0.8, 0.2 }, D_CYAN = { 0.2, 0.8, 1 }, D_RED = { 1, 0.2, 0.2 },
  D_WHITE = { 1, 1, 1 }, D_DIM = { 0.5, 0.5, 0.5 }, D_ORANGE = { 1, 0.6, 0.2 } }

local function built_rows()
  local rows = {}
  HUD._test.build_panel_rows("SELECTING_HAND", rows, {}, {}, COLORS, { 1, 0.5, 0.7 })
  return rows
end

local function find_carousel(rows)
  local found, n = nil, 0
  for _, r in ipairs(rows) do
    if r.kind == "carousel" then n = n + 1; found = found or r end
  end
  return found, n
end

local function find_line(rows, needle)
  for _, r in ipairs(rows) do
    if r.kind == "line" and type(r.text) == "string" and r.text:find(needle, 1, true) then return r end
  end
  return nil
end

local vis1, vis2 = joker("VisAlpha", "j_visalpha", 2, 5), joker("VisBeta", "j_visbeta", 1, 4)
local hid = joker("HiddenGamma", "j_hiddengamma", 3, 8)
hid.facing = "back"

G.jokers = area({ vis1, hid, vis2 }, 5)
local rows = built_rows()
local car = find_carousel(rows)
check("mixed: carousel survives one face-down card", car ~= nil)
check("mixed: carousel keeps both visible cards", car and #car.cards == 2
  and car.cards[1] == vis1 and car.cards[2] == vis2)
local fd_line = find_line(rows, "face-down (hidden)")
check("mixed: hidden count noted on its own line", fd_line ~= nil and fd_line.text == "1 face-down (hidden)",
  fd_line and fd_line.text)
check("mixed: hidden note uses the dim color", fd_line ~= nil and fd_line.color == COLORS.D_DIM)

G.jokers = area({ vis1, vis2 }, 5)
rows = built_rows()
car = find_carousel(rows)
check("all visible: carousel carries every card", car and #car.cards == 2)
check("all visible: no face-down note", find_line(rows, "face-down") == nil)

local hid2 = joker("HiddenDelta", "j_hiddendelta", 1, 3)
hid2.facing = "back"
G.jokers = area({ hid, hid2 }, 5)
rows = built_rows()
check("all hidden: no carousel", (select(2, find_carousel(rows))) == 0)
check("all hidden: blanket note kept", find_line(rows, "Cards are face-down (hidden)") ~= nil)

local m = { line_h = 17, small_line_h = 14, header_line_h = 20, card_line_h = 26, sep_h = 6, carousel_pad = 18 }
check("carousel height contract: card line + three desc lines + pad",
  Rows.height({ kind = "carousel", cards = {} }, m) == 26 + 14 * 3 + 18)

G.jokers = area({ vis1, hid, vis2 }, 5)
for k = #OPS, 1, -1 do OPS[k] = nil end
local draw_err
for i = 1, 200 do
  G.TIMERS.REAL = i * 0.25
  local ok, err = pcall(HUD.draw_indicator)
  if not ok then draw_err = err; break end
end
check("full draw: no error with a mixed face-down area", draw_err == nil, draw_err)
local saw_vis1, saw_vis2, saw_note, saw_hidden = false, false, false, false
for _, op in ipairs(OPS) do
  if op.op == "T" then
    if op.text:find("VisAlpha", 1, true) then saw_vis1 = true end
    if op.text:find("VisBeta", 1, true) then saw_vis2 = true end
    if op.text:find("face-down (hidden)", 1, true) then saw_note = true end
    if op.text:find("HiddenGamma", 1, true) then saw_hidden = true end
  end
end
check("full draw: both visible jokers still describe themselves", saw_vis1 and saw_vis2,
  string.format("vis1=%s vis2=%s", tostring(saw_vis1), tostring(saw_vis2)))
check("full draw: the hidden note is rendered", saw_note)
check("full draw: the face-down joker's name never leaks", not saw_hidden)

local DS = require("render.debug_stats")
local Staging = require("core.staging")
local real_get_lines = Staging.get_debug_lines
Staging.get_debug_lines = function() return { "stage line one", "stage line two" } end
local StagingDebug = require("render.staging_debug")

DS.set_mode_name("compact")
CURFONT = mkfont(40)
for k = #OPS, 1, -1 do OPS[k] = nil end
StagingDebug.draw()
local text_px, box_w
for _, op in ipairs(OPS) do
  if op.op == "T" then text_px = text_px or op.px end
  if op.op == "R" and op.mode == "fill" and not box_w then box_w = op.w end
end
check("staging_debug: text uses the pinned debug font, not the ambient one", text_px == 14, text_px)
check("staging_debug: box width at 1080p unchanged", box_w == 320, box_w)
check("staging_debug: ambient font restored after draw", CURFONT.px == 40, CURFONT.px)

for k = #OPS, 1, -1 do OPS[k] = nil end
DS.draw()
local ds_w
for _, op in ipairs(OPS) do
  if op.op == "R" and op.mode == "fill" and op.x == 8 and op.y == 8 and not ds_w then ds_w = op.w end
end
check("debug_stats: box width at 1080p unchanged", ds_w == 308, ds_w)

SH = 2160
for k = #OPS, 1, -1 do OPS[k] = nil end
DS._rows = nil
DS.draw()
local ds_w2, ds_px
for _, op in ipairs(OPS) do
  if op.op == "R" and op.mode == "fill" and op.x == 8 and op.y == 8 and not ds_w2 then ds_w2 = op.w end
  if op.op == "T" and not ds_px then ds_px = op.px end
end
check("debug_stats: box width doubles at 4K", ds_w2 == 616, ds_w2)
check("debug_stats: font doubles at 4K", ds_px == 28, ds_px)

for k = #OPS, 1, -1 do OPS[k] = nil end
StagingDebug.draw()
local sd_w2, sd_px
for _, op in ipairs(OPS) do
  if op.op == "R" and op.mode == "fill" and not sd_w2 then sd_w2 = op.w end
  if op.op == "T" and not sd_px then sd_px = op.px end
end
check("staging_debug: box width doubles at 4K", sd_w2 == 640, sd_w2)
check("staging_debug: font follows debug_stats at 4K", sd_px == 28, sd_px)

DS.set_mode_name("off")
Staging.get_debug_lines = real_get_lines
SH = 1080

done()
