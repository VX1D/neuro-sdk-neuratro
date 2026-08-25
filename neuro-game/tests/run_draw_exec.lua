
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local PIN_KEYS = {}
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
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
local FAKECARD = { config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint",
  loc_txt = { name = "Blueprint" }, rarity = 1 } },
  ability = { eternal = true, rental = true }, edition = { holo = true }, seal = "Gold",
  cost = 3, sell_cost = 2, VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 } }
local PLAINCARD = { config = { center = { key = "j_joker", set = "Joker", name = "Joker",
  loc_txt = { name = "Joker" }, rarity = 1 } }, ability = {}, cost = 3, sell_cost = 2,
  VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 } }
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
local ModifierBadges = require("render.modifier_badges")
do
  local Prims = require("hud.prims")
  local real_glyph = Prims.pin_glyph
  Prims.pin_glyph = function(kind, key, ...)
    if key then PIN_KEYS[#PIN_KEYS + 1] = tostring(key) end
    return real_glyph(kind, key, ...)
  end
end
local raw_badge_layout = ModifierBadges.layout
local badge_layout_calls = 0
ModifierBadges.layout = function(...)
  badge_layout_calls = badge_layout_calls + 1
  return raw_badge_layout(...)
end

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end

local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(),
  ORANGE = CLR(), GREEN = CLR(), DIM = CLR(), WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
  _pal = PAL, persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  boss = false, is_round_eval = false,
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT, font_display = FONT,
  font = FONT, panel_font_small = FONT, rfont = FONT, rfont_small = FONT,
  lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local MOTION = { now = 0, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
local METRICS = {
  rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
  total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10,
  c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
  rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
}
local function make_data()
  return {
    panel_rows = {
      Rows.header(CLR(), "HEADER"), Rows.line(CLR(), "line"), Rows.sub(CLR(), "sub"),
      Rows.sep(), Rows.carousel({ FAKECARD }, "cons"),
    },
    shop_rows = { Rows.shopcard(CLR(), "Blueprint", FAKECARD, 3, true, nil, {
      { kind = "edition", text = "Holo +10m", key = "Holo" },
      { kind = "seal", text = "Gold Seal", key = "Gold" },
      { kind = "sticker", text = "Eternal", key = "eternal" },
      { kind = "sticker", text = "Rental", key = "rental" },
    }), Rows.note(CLR(), "note"), Rows.descwrap(CLR(), "desc"), Rows.sep() },
    pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
      cards = { { card = FAKECARD, name = "Blueprint", desc = "", rc = CLR(), index = 1,
        badges = require("render.modifier_badges").collect(FAKECARD) } } },
    sn = "SHOP", state_name = "SHOP",
    showcase_card = FAKECARD, showcase_name = "Blueprint", showcase_label = "Joker",
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
    draw_desc_lines = noop, print_colored_desc = noop,
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
local Acquire = require("render.panels.acquire")
local Pack = require("render.panels.pack")
local PANELS = {
  { "shop",            require("render.panels.shop").draw },
  { "acquire",         Acquire.draw },
  { "pack",            Pack.draw },
  { "rp_frame",        RP.frame },
  { "rp_header",       RP.header },
  { "rp_rows",         RP.rows },
  { "rp_footer",       RP.footer },
}

require("hud.state").buy_showcase = {
  card = FAKECARD, name = "Not Discovered", area = "shop", cost = 3, started = 0,
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
    if pan[1] == "pack" then
      ctx.data.sn = "TAROT_PACK"
      G.GAME.pack_choices = 1
    end
    checks = checks + 1
    local ok, err = xpcall(function() pan[2](ctx) end, debug.traceback)
    if not ok then
      fails[#fails + 1] = pan[1] .. " [" .. combo[1] .. "]  ->  " .. tostring(err):gsub("\n.*", "")
    end
  end
end

local HudState = require("hud.state")
for _, combo in ipairs({ { "hiyori", false, false }, { "evil", true, false }, { "neuro", false, true } }) do
  G.NEURO.persona = combo[1]
  HudState.buy_showcase = { card = FAKECARD, name = "Blueprint", area = "shop", cost = 3, started = -0.5 }
  HudState.joker_showcase = nil
  local ctx = build_ctx(combo[2], combo[3])
  checks = checks + 1
  local ok, err = xpcall(function()
    Acquire.draw(ctx)
    if ctx.center_top_y <= 8 then error("receipt stack did not advance vertically") end
  end, debug.traceback)
  if not ok then
    fails[#fails + 1] = "receipt-stack[" .. combo[1] .. "] -> "
      .. tostring(err):gsub("\n.*", "")
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

local function visual_check(label, panel, ctx, required)
  PRINTED = {}
  PIN_KEYS = {}
  checks = checks + 1
  local ok, err = xpcall(function() panel(ctx) end, debug.traceback)
  if not ok then
    fails[#fails + 1] = label .. "  ->  " .. tostring(err):gsub("\n.*", "")
    return
  end
  local seen = {}
  for _, text in ipairs(PRINTED) do seen[text] = true end
  local function shown(want)
    if seen[want] then return true end
    for _, text in ipairs(PRINTED) do
      if type(text) == "string" and text:find(want, 1, true) then return true end
    end
    local first = tostring(want):match("^(%S+)")
    for _, key in ipairs(PIN_KEYS) do
      if key == want or (first and key:lower() == first:lower()) then return true end
    end
    return false
  end
  for _, text in ipairs(required) do
    if not shown(text) then fails[#fails + 1] = label .. " missing text: " .. text end
  end
  if seen["Not Discovered"] then fails[#fails + 1] = label .. " leaked masked name" end
end

local State = require("hud.state")
do
  local guard_badges = {
    { kind = "edition", text = "Holo", key = "Holo" },
    _v = 1,
  }
  local guard_ctx = build_ctx(false, false)
  guard_ctx.data.sn = "TAROT_PACK"
  guard_ctx.data.pack_rows.cards = {
    { card = FAKECARD, name = "Blueprint", badges = guard_badges, desc = "", rc = CLR(), index = 1 },
  }
  G.NEURO.persona, G.GAME.pack_choices = "hiyori", 1
  State.pack_last_sn = nil
  State.pack_card_indices, State.pack_winners, State.pack_disp = {}, {}, nil

  local start = badge_layout_calls
  local observed = {}
  local function draw_guard()
    local ok, err = xpcall(function() Pack.draw(guard_ctx) end, debug.traceback)
    if not ok then
      fails[#fails + 1] = "pack badge cache guard draw -> " .. tostring(err):gsub("\n.*", "")
      return false
    end
    observed[#observed + 1] = badge_layout_calls - start
    return true
  end

  if draw_guard() and draw_guard() then
    guard_badges._v = 2
    draw_guard()
    guard_badges = { { kind = "edition", text = "Foil", key = "Foil" } }
    guard_ctx.data.pack_rows.cards[1].badges = guard_badges
    draw_guard()
    guard_ctx.data.pack_rows.cards[1].card = PLAINCARD
    draw_guard()
    PLAINCARD.facing = "back"
    draw_guard()
    guard_ctx.center_max_w = 100
    draw_guard()
    PLAINCARD.facing = nil
  end

  checks = checks + 1
  local expected = { 1, 1, 2, 3, 4, 5, 6 }
  local guard_ok = #observed == #expected
  for i = 1, math.min(#observed, #expected) do
    if observed[i] ~= expected[i] then guard_ok = false end
  end
  if not guard_ok then
    fails[#fails + 1] = "pack badge cache guard expected 1,1,2,3,4,5,6; got "
      .. table.concat(observed, ",")
  end
end

local required_badges = { "Blueprint", "Holo", "Gold Seal", "Eternal", "Rental" }
for _, combo in ipairs({ { "evil", true, false }, { "neuro", false, true } }) do
  G.NEURO.persona = combo[1]
  State.buy_showcase = { card = FAKECARD, name = "Not Discovered", area = "shop", cost = 3, started = -0.5 }

  visual_check("visual/shop[" .. combo[1] .. "]", require("render.panels.shop").draw,
    build_ctx(combo[2], combo[3]), required_badges)
  State.joker_showcase = nil
  visual_check("visual/receipt[" .. combo[1] .. "]", Acquire.draw,
    build_ctx(combo[2], combo[3]), { "Blueprint" })
  State.buy_showcase = nil
  State.joker_showcase = { card = FAKECARD, label = "NEW JOKER", started = -0.5 }
  visual_check("visual/full[" .. combo[1] .. "]", Acquire.draw,
    build_ctx(combo[2], combo[3]), required_badges)
  State.joker_showcase = nil
  State.buy_showcase = { card = FAKECARD, name = "Not Discovered", area = "shop", cost = 3, started = -0.5 }
  visual_check("visual/carousel[" .. combo[1] .. "]", RP.rows,
    build_ctx(combo[2], combo[3]), required_badges)

  State.pack_last_sn = nil
  State.pack_card_indices, State.pack_winners = {}, {}
  local before = build_ctx(combo[2], combo[3])
  before.data.sn = "TAROT_PACK"
  before.data.pack_rows.cards[2] = {
    card = PLAINCARD, name = "Joker", badges = {}, desc = "", rc = CLR(), index = 2,
  }
  G.GAME.pack_choices = 1
  visual_check("visual/pack-before[" .. combo[1] .. "]", require("render.panels.pack").draw,
    before, required_badges)

  local after = build_ctx(combo[2], combo[3])
  after.data.sn = "TAROT_PACK"
  after.data.pack_rows.cards = {
    { card = PLAINCARD, name = "Joker", badges = {}, desc = "", rc = CLR(), index = 2 },
  }
  State.pack_winners = { {
    slot = 1, card = FAKECARD, t0 = -5, owed = 0,
    name = "Blueprint", badges = require("render.modifier_badges").collect(FAKECARD),
  } }
  State.pack_collapse_req = true
  visual_check("visual/pack-after[" .. combo[1] .. "]", require("render.panels.pack").draw,
    after, required_badges)
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
