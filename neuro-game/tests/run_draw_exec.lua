package.path = "./?.lua;;" .. package.path

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
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
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local function area(cards) return { cards = cards or {}, config = { card_limit = 5 } } end
local FAKECARD = { config = { center = { key = "j_x", set = "Joker", rarity = 1 } }, ability = {},
  cost = 3, sell_cost = 2, VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 } }
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 10, round = 2, round_resets = { ante = 3, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({ FAKECARD }), consumeables = area({}), hand = area({}),
  shop_jokers = area({ FAKECARD }), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, colourblind_option = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local Rows = require("hud.rows")

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end

local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ORANGE = CLR(), GREEN = CLR(), DIM = CLR(), WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
  _pal = PAL, persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  boss = false, is_round_eval = false,
  font = FONT, panel_font_small = FONT, rfont = FONT, rfont_small = FONT,
  lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local MOTION = { now = 0, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
local METRICS = {
  rn = id, ln = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
  total_h = 800, content_w = 356, n_cols = 1, title_h = 40, action_row_h = 24, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
}
local function make_data()
  return {
    panel_rows = {
      Rows.header(CLR(), "HEADER"), Rows.line(CLR(), "line"), Rows.sub(CLR(), "sub"),
      Rows.sep(), Rows.carousel({ {} }, "cons"),
    },
    shop_rows = { Rows.shopcard(CLR(), "card", {}, 3, true), Rows.note(CLR(), "note"),
      Rows.descwrap(CLR(), "desc"), Rows.sep() },
    pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
      cards = { { card = {}, name = "c", desc = "d", rc = CLR(), index = 1 } } },
    sn = "SHOP", state_name = "SHOP",
    showcase_card = {}, showcase_name = "Card", showcase_label = "Tarot", showcase_fx = "fx",
    showcase_desc = "desc", showcase_alpha = 1, showcase_slide = 0,
    quip_display = "hi", footer_emote = { img = IMG, quads = { {} }, fps = 10, n_frames = 1 },
    footer_is_emote = false, jokers_on_screen = {},
    state_label = "SHOP", is_thinking = false, action_text = "act",
    logo = IMG, logo_w = 100, logo_h = 40, logo_scale = 1,
    booster_active = false, pack_state_active = false,
  }
end
local function DRAW()
  return {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = noop,
    row_h = function() return 16 end,
    showcase_type_colors = function() return CLR(), CLR() end,
  }
end
local function build_ctx(evil, neuro)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  return {
    theme = theme, motion = MOTION, metrics = METRICS, data = make_data(), draw = DRAW(),
    center_top_y = 8,
  }
end

local RP = require("render.panels.right_panel")
local PANELS = {
  { "shop",            require("render.panels.shop").draw },
  { "buy_toast",       require("render.panels.buy_toast").draw },
  { "center_showcase", require("render.panels.center_showcase").draw },
  { "pack",            require("render.panels.pack").draw },
  { "rp_frame",        RP.frame },
  { "rp_header",       RP.header },
  { "rp_rows",         RP.rows },
  { "rp_footer",       RP.footer },
}

print("====================================================")
print("[draw-exec] functional-stub draw execution (" .. #PANELS .. " panels x 3 personas)")
print("====================================================")

local fails = {}
local checks = 0
for _, combo in ipairs({ { "hiyori", false, false }, { "evil", true, false }, { "neuro", false, true } }) do
  G.NEURO.persona = combo[1]
  for _, pan in ipairs(PANELS) do
    local ctx = build_ctx(combo[2], combo[3])
    checks = checks + 1
    local ok, err = xpcall(function() pan[2](ctx) end, debug.traceback)
    if not ok then
      fails[#fails + 1] = pan[1] .. " [" .. combo[1] .. "]  ->  " .. tostring(err):gsub("\n.*", "")
    end
  end
end

local HUD = require("render.hud_overlay")
for _, persona in ipairs({ "hiyori", "evil", "neuro" }) do
  for _, st in ipairs({ "SHOP", "SELECTING_HAND", "BLIND_SELECT", "MENU", "ROUND_EVAL", "TAROT_PACK" }) do
    G.NEURO.persona, G.NEURO.state = persona, st
    checks = checks + 1
    local ok, err = xpcall(HUD.draw_indicator, debug.traceback)
    if not ok then
      fails[#fails + 1] = "indicator[" .. persona .. "/" .. st .. "]  ->  " .. tostring(err):gsub("\n.*", "")
    end
  end
end

print(string.format("[draw-exec] %d panel draws executed", checks))
print("====================================================")
if #fails == 0 then
  print(string.format("==== draw_exec: %d checks, 0 FAIL ====", checks))
else
  print(string.format("==== draw_exec: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("DRAW_EXEC_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
