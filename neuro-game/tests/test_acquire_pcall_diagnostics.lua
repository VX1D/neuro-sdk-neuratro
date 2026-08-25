
local QUAD_THROW = false
local MESH_THROW = false
local DRAW_THROW_IMG = nil
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local DRAWS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
local function record_draw(...)
  local args = { ... }
  DRAWS[#DRAWS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4] }
end
local function new_img(id)
  return { id = id, getWidth = function() return 512 end, getHeight = function() return 512 end,
    getDimensions = function() return 512, 512 end }
end
local IMG = new_img("normal")
local THROW_IMG = new_img("throw")
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function(...)
    if QUAD_THROW then error("forced quad failure") end
    return { x = 0, y = 0 }
  end,
  newImage = function() return IMG end,
  newMesh = function()
    if MESH_THROW then error("forced mesh failure") end
    return {}
  end,
  print = record_print,
  draw = function(...)
    local args = { ... }
    if args[1] == DRAW_THROW_IMG then error("forced mini draw failure") end
    record_draw(...)
  end,
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

local check, done = require("tests.helpers").harness("acquire local pcall diagnostics")

local Cards = require("hud.cards")
local HudState = require("hud.state")
local Pack = require("render.panels.pack")

G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }
G.ASSET_ATLAS.cards_1 = { image = IMG, px = 71, py = 95 }

local function joker_card(atlas_key)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = atlas_key or "FIX71",
      pos = { x = 0, y = 0 }, name = "DiagJoker" } },
    ability = {},
    cost = 3,
  }
end

local function diag_lines()
  local n = 0
  for _, line in ipairs(PRINTED) do
    if line:find("[neuro-game]", 1, true) then n = n + 1 end
  end
  return n
end

Cards.reset_mini_counters()
QUAD_THROW = true
PRINTED, RECTS, DRAWS = {}, {}, {}
local captured_prints = {}
local orig_print = print
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
Cards.draw_card_mini(joker_card(), 0, 0, 95, 1)
print = orig_print
check("forced newQuad failure increments the quad counter", Cards._mini_quad_fail == 1, Cards._mini_quad_fail)
check("forced newQuad failure logs exactly once", #captured_prints == 1, #captured_prints)
check("forced newQuad failure falls back to the name placeholder", Cards._mini_fallback == 1,
  Cards._mini_fallback)
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
Cards.draw_card_mini(joker_card(), 0, 0, 95, 1)
print = orig_print
check("cached quad failure keeps falling back without re-running newQuad",
  Cards._mini_fallback == 2 and Cards._mini_quad_fail == 1, Cards._mini_fallback .. "/" .. Cards._mini_quad_fail)
QUAD_THROW = false
Cards.clear_quad_cache()
Cards.draw_card_mini(joker_card(), 0, 0, 95, 1)
check("recovered newQuad resumes normal sprite draw", #DRAWS >= 1, #DRAWS)
check("quad counter unchanged after recovery", Cards._mini_quad_fail == 1, Cards._mini_quad_fail)

local throwing_send = function(_, name)
  if name == "holo" then error("forced shader send failure") end
end
G.SHADERS.holo = { send = throwing_send }
local playing_card = {
  config = { card = { pos = { x = 0, y = 0 }, value = 10, suit = "Hearts" } },
  ability = {},
  edition = { holo = true },
  ARGS = { send_to_shader = "holo" },
}
Cards.reset_mini_counters()
PRINTED, RECTS, DRAWS = {}, {}, {}
captured_prints = {}
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
for i = 1, 1000 do
  Cards.draw_card_mini(playing_card, 0, 0, 95, 1)
end
print = orig_print
check("1000 throwing shader.send calls increment the shader counter", Cards._mini_shader_fail == 1000,
  Cards._mini_shader_fail)
check("1000 throwing shader.send calls log only once", #captured_prints == 1, #captured_prints)
check("shader.send failure does not break the draw", #DRAWS >= 1000, #DRAWS)
check("shader.send failure does not touch the edition counter", Cards._mini_edition_fail == 0,
  Cards._mini_edition_fail)

Cards.reset_mini_counters()
PRINTED, RECTS, DRAWS = {}, {}, {}
captured_prints = {}
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
MESH_THROW = true
local evil_pal = { D_ORANGE = { 1, 0.5, 0.2 }, D_GOLD = { 1, 0.8, 0.2 },
  D_WHITE = { 1, 1, 1 }, GLOW = { 1, 0.4, 0.2 } }
Cards.glow_painters.evil(evil_pal, 1, 100, 60, 0, 0, 100, 60, 0.5, 1, 0.9)
Cards.glow_painters.evil(evil_pal, 1, 100, 60, 0, 0, 100, 60, 0.5, 1, 0.9)
print = orig_print
check("forced newMesh failure increments the mesh counter", Cards._mini_mesh_fail == 1,
  Cards._mini_mesh_fail)
check("forced newMesh failure logs exactly once", #captured_prints == 1, #captured_prints)
check("mesh failure keeps the glow draw alive", #RECTS > 0, #RECTS)

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
local function pack_ctx(evil, neuro)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  return {
    theme = theme,
    motion = { now = 0.9, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = {
      rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 960, sh = 540, U = 4,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      r_text_h = 12, r_small_text_h = 10,
      c_text_h = 12, c_small_text_h = 10, text_h = 12,
    },
    data = { sn = "TAROT_PACK", state_name = "TAROT_PACK" },
    draw = { trunc = function(s) return s end, wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end },
    center_top_y = 8,
  }
end

local function reset_pack_state()
  HudState.pack_collapse_t, HudState.pack_collapse_snap = nil, nil
  HudState.pack_collapse_req, HudState.pack_collapse_done = nil, nil
  HudState.pack_losers, HudState.pack_disp = nil, nil
  HudState.pack_leave_t, HudState.pack_leave_snap, HudState.pack_leave_n = nil, nil, nil
  HudState.pack_last_sn, HudState.pack_appear_t, HudState.pack_hl_t = nil, nil, nil
  HudState.pack_winners = {}
  HudState.pack_card_indices = {}
  HudState.pack_hidden_indices = {}
  HudState.pack_initial_count = 0
  HudState.pack_hl = false
end

local throw_card = {
  config = { center = { key = "j_bad", set = "Joker", atlas = "FIX71",
    pos = { x = 0, y = 0 }, name = "ThrowCard" } },
  ability = {},
  cost = 3,
}
DRAW_THROW_IMG = THROW_IMG
G.ASSET_ATLAS.FIX71.image = THROW_IMG
Cards.reset_mini_counters()
PRINTED, RECTS, DRAWS = {}, {}, {}
captured_prints = {}
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
for i = 1, 1000 do
  reset_pack_state()
  local ctx = pack_ctx(false, false)
  ctx.data.pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
    cards = { { card = throw_card, name = "ThrowCard", desc = "", rc = CLR(), index = 1, badges = {} } } }
  local ok, err = xpcall(function() Pack.draw(ctx) end, debug.traceback)
  if not ok then error("pack draw crashed: " .. tostring(err)) end
end
print = orig_print
check("1000 forced draw_card_mini failures in pack increment the pack counter",
  Cards._pack_mini_fail == 1000, Cards._pack_mini_fail)
check("1000 forced pack mini failures log only once", #captured_prints == 1, #captured_prints)
check("pack mini failure placeholder prints the card name",
  table.concat(PRINTED, ""):find("ThrowCard", 1, true) ~= nil)

DRAW_THROW_IMG = nil
G.ASSET_ATLAS.FIX71.image = IMG

local function trap_ability()
  return setmetatable({}, {
    __index = function(_, k)
      if k == "effect" then error("forced mini draw failure") end
    end,
  })
end
local function bad_ability_card(key, name)
  return {
    config = { center = { key = key, set = "Joker", atlas = "MISSING_ATLAS",
      pos = { x = 0, y = 0 }, name = name } },
    ability = trap_ability(),
    cost = 1,
  }
end
local loser_bad = bad_ability_card("j_loser_bad", "LoserBad")
local winner_ok = joker_card()
Cards.reset_mini_counters()
PRINTED, RECTS, DRAWS = {}, {}, {}
captured_prints = {}
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
for i = 1, 50 do
  reset_pack_state()
  local ctx = pack_ctx(false, false)
  ctx.data.sn = "SHOP"
  ctx.data.pack_rows = { title = "Pack", picks_left = 1, total = 2, pg = CLR(),
    cards = {
      { card = winner_ok, name = "DiagJoker", desc = "", rc = CLR(), index = 1, badges = {} },
      { card = loser_bad, name = "LoserBad", desc = "", rc = CLR(), index = 2, badges = {} },
    } }
  HudState.pack_winners = { { slot = 1, card = winner_ok, name = "DiagJoker", badges = {} } }
  G.GAME.pack_choices = 0
  local ok, err = xpcall(function() Pack.draw(ctx) end, debug.traceback)
  if not ok then error("loser collapse crashed: " .. tostring(err)) end
end
print = orig_print
check("loser collapse draw_card_mini failures increment the pack counter",
  Cards._pack_mini_fail == 50, Cards._pack_mini_fail)
check("loser collapse failure logs only once", #captured_prints == 1, #captured_prints)
check("loser collapse placeholder prints the loser name",
  table.concat(PRINTED, ""):find("LoserBad", 1, true) ~= nil)

local winner_bad = bad_ability_card("j_winner_bad", "WinnerBad")
local loser_ok = {
  config = { center = { key = "j_loser_ok", set = "Joker", atlas = "MISSING_ATLAS",
    pos = { x = 0, y = 0 }, name = "LoserOk" } },
  ability = {},
  cost = 1,
}
Cards.reset_mini_counters()
PRINTED, RECTS, DRAWS = {}, {}, {}
captured_prints = {}
print = function(...) captured_prints[#captured_prints + 1] = table.concat({ ... }, " ") end
for i = 1, 50 do
  reset_pack_state()
  local ctx = pack_ctx(false, false)
  ctx.data.sn = "SHOP"
  ctx.data.pack_rows = { title = "Pack", picks_left = 1, total = 2, pg = CLR(),
    cards = {
      { card = winner_bad, name = "WinnerBad", desc = "", rc = CLR(), index = 1, badges = {} },
      { card = loser_ok, name = "LoserOk", desc = "", rc = CLR(), index = 2, badges = {} },
    } }
  HudState.pack_winners = { { slot = 1, card = winner_bad, name = "WinnerBad", badges = {} } }
  G.GAME.pack_choices = 0
  local ok, err = xpcall(function() Pack.draw(ctx) end, debug.traceback)
  if not ok then error("winner collapse crashed: " .. tostring(err)) end
end
print = orig_print
check("winner collapse draw_card_mini failures increment the pack counter",
  Cards._pack_mini_fail == 50, Cards._pack_mini_fail)
check("winner collapse failure logs only once", #captured_prints == 1, #captured_prints)
check("winner collapse placeholder prints the winner name",
  table.concat(PRINTED, ""):find("WinnerBad", 1, true) ~= nil)

reset_pack_state()
local ctx = pack_ctx(false, false)
ctx.data.pack_rows = { title = "Pack", picks_left = 1, total = 1, pg = CLR(),
  cards = { { card = joker_card(), name = "DiagJoker", desc = "", rc = CLR(), index = 1, badges = {} } } }
local ok_after, err_after = xpcall(function() Pack.draw(ctx) end, debug.traceback)
check("pack draw continues after instrumented failures", ok_after, err_after)

done()
