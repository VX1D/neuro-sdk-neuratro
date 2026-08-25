
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local DRAWS = {}
local RECTS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local function record_draw(...)
  local args = { ... }
  DRAWS[#DRAWS + 1] = { image = args[1], quad = args[2], x = args[3], y = args[4] }
end
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
  NEURO = { persona = "hiyori", state = "TAROT_PACK", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 1, round = 1, round_resets = { ante = 1, blind_choices = {} },
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

local check, done = require("tests.helpers").harness("acquire atlas fallback")

local Cards = require("hud.cards")
local HudState = require("hud.state")
local Showcase = require("hud.showcase")
local ModifierBadges = require("render.modifier_badges")

local function reset_gfx()
  PRINTED, DRAWS, RECTS = {}, {}, {}
  Cards.reset_mini_counters()
  HudState.quad_cache = {}
end

local function joker_card(atlas_key, pos, name, soul_pos)
  return {
    config = { center = { key = "j_fixture", set = "Joker", atlas = atlas_key,
      pos = pos, soul_pos = soul_pos,
      loc_txt = { name = name }, name = name, rarity = 1 } },
    ability = {},
    cost = 1,
  }
end

local function atlas_entry(px, py, image)
  return { image = image or IMG, px = px, py = py }
end

local function fallback_fill_count()
  local n = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w > 0 and r.h > 0 and math.abs(r.w - 2) > 0.01 then
      local dark = true
      n = n + 1
    end
  end
  return n
end

G.ASSET_ATLAS = {}

local v71 = atlas_entry(71, 95)
G.ASSET_ATLAS.FIX71 = v71
local v95 = atlas_entry(95, 95)
G.ASSET_ATLAS.FIX95 = v95
local v50 = atlas_entry(50, 100)
G.ASSET_ATLAS.FIX50 = v50
local v120 = atlas_entry(120, 80)
G.ASSET_ATLAS.FIX120 = v120
G.ASSET_ATLAS.NOIMAGE = { px = 71, py = 95 }
G.ASSET_ATLAS.cards_1 = atlas_entry(71, 95)
G.ASSET_ATLAS.centers = atlas_entry(71, 95)

reset_gfx()
local w71 = Cards.draw_card_mini(joker_card("FIX71", { x = 1, y = 2 }, "SeventyOne"), 0, 0, 95, 1)
check("present 71x95 atlas draws one quad from its own image", #DRAWS == 1 and DRAWS[1].image == v71.image,
  tostring(#DRAWS))
check("present 71x95 atlas returns width 71", math.abs(w71 - 71) < 0.001, w71)
check("present 71x95 atlas does not fall back", Cards._mini_fallback == 0, Cards._mini_fallback)

reset_gfx()
local w95 = Cards.draw_card_mini(joker_card("FIX95", { x = 1, y = 2 }, "NinetyFive"), 0, 0, 95, 1)
check("present 95x95 atlas draws from its own image", #DRAWS == 1 and DRAWS[1].image == v95.image)
check("present 95x95 atlas returns width 95", math.abs(w95 - 95) < 0.001, w95)

reset_gfx()
local w50 = Cards.draw_card_mini(joker_card("FIX50", { x = 1, y = 2 }, "FiftyHundred"), 0, 0, 100, 1)
check("present 50x100 atlas returns width 50", math.abs(w50 - 50) < 0.001, w50)

reset_gfx()
local w120 = Cards.draw_card_mini(joker_card("FIX120", { x = 1, y = 2 }, "WideTall"), 0, 0, 80, 1)
check("present 120x80 atlas returns width 120", math.abs(w120 - 120) < 0.001, w120)

reset_gfx()
local fb = Cards.draw_card_mini(joker_card("MISSING_KEY", { x = 1, y = 2 }, "Ghost"), 0, 0, 95, 1)
check("missing key draws zero quads (no foreign sprite)", #DRAWS == 0, tostring(#DRAWS))
check("missing key draws a fallback box", #RECTS > 0)
check("missing key prints the card name", table.concat(PRINTED, ""):find("Ghost", 1, true) ~= nil)
check("missing key increments the fallback counter", Cards._mini_fallback == 1, Cards._mini_fallback)
check("missing key still returns a positive width", fb > 0, fb)

reset_gfx()
Cards.draw_card_mini(joker_card("NOIMAGE", { x = 1, y = 2 }, "NoImage"), 0, 0, 95, 1)
check("atlas entry without image draws zero quads", #DRAWS == 0, tostring(#DRAWS))
check("atlas entry without image falls back", Cards._mini_fallback == 1, Cards._mini_fallback)
check("atlas entry without image prints the card name",
  table.concat(PRINTED, ""):find("NoImage", 1, true) ~= nil)

reset_gfx()
Cards.draw_card_mini(joker_card("MISSING_SOUL", { x = 1, y = 2 }, "SoulGhost", { x = 0, y = 0 }), 0, 0, 95, 1)
check("missing atlas with soul_pos draws no soul quad (no foreign draw)", #DRAWS == 0, tostring(#DRAWS))
check("missing atlas with soul_pos falls back", Cards._mini_fallback == 1)

reset_gfx()
Cards.draw_card_mini(joker_card("FIX71", { x = 1, y = 2 }, "SoulReal", { x = 0, y = 0 }), 0, 0, 95, 1)
check("valid atlas with soul_pos draws center and soul quads from same image", #DRAWS == 2,
  tostring(#DRAWS))

local sprite_ak, sprite_pos = Cards.card_sprite(joker_card("FIX71", { x = 1, y = 2 }, "Ok"))
check("card_sprite returns a present atlas key", sprite_ak == "FIX71")
check("card_sprite exposes the resolved position", sprite_pos
  and sprite_pos.x == 1 and sprite_pos.y == 2)
local bad_ak, bad_pos = Cards.card_sprite(joker_card("MISSING_KEY", { x = 1, y = 2 }, "Bad"))
check("card_sprite rejects a missing atlas", bad_ak == nil and bad_pos == nil)
local nopos_ak, nopos_pos = Cards.card_sprite({
  config = { center = { key = "j_none", set = "Joker" } }, ability = {},
})
check("card_sprite returns nil when no position exists at all", nopos_ak == nil and nopos_pos == nil)

local NeuroAnim = require("render.neuro-anim")
local bad_card = joker_card("MISSING_KEY", { x = 3, y = 3 }, "LostCard")
local good_card = joker_card("FIX71", { x = 0, y = 0 }, "FoundCard")
local bp = { cards = { good_card, bad_card }, config = { card_limit = 2 } }
G.GAME.pack_choices = 1
Showcase.reset_run_state()
HudState.pack_card_indices = { [bad_card] = 2, [good_card] = 1 }
NeuroAnim.pick_pack_card(bad_card, bp)
check("pack winner with missing atlas stays in S.pack_winners", #HudState.pack_winners == 1,
  tostring(#HudState.pack_winners))
check("pack winner with missing atlas keeps the card reference",
  HudState.pack_winners[1] and HudState.pack_winners[1].card == bad_card)
check("pack winner with missing atlas has no ak", HudState.pack_winners[1] and HudState.pack_winners[1].ak == nil)
check("pack winner with missing atlas keeps the name",
  HudState.pack_winners[1] and HudState.pack_winners[1].name == "LostCard",
  HudState.pack_winners[1] and HudState.pack_winners[1].name)
check("pack loser keeps the card reference", HudState.pack_losers and HudState.pack_losers[1]
  and HudState.pack_losers[1].card == good_card)
check("pack loser keeps the name for fallback rendering", HudState.pack_losers and HudState.pack_losers[1]
  and HudState.pack_losers[1].name == "FoundCard")
check("pack loser with valid atlas has ak", HudState.pack_losers and HudState.pack_losers[1]
  and HudState.pack_losers[1].ak == "FIX71")

Showcase.reset_run_state()
HudState.pack_winners = {}
HudState.pack_losers = nil
HudState.pack_card_indices = { [bad_card] = 2, [good_card] = 1 }
NeuroAnim.pick_pack_card(good_card, bp)
check("winner with valid atlas records ak", HudState.pack_winners[1]
  and HudState.pack_winners[1].ak == "FIX71")
check("loser with missing atlas stays recorded", HudState.pack_losers and HudState.pack_losers[1]
  and HudState.pack_losers[1].card == bad_card)
check("loser with missing atlas keeps the name", HudState.pack_losers and HudState.pack_losers[1]
  and HudState.pack_losers[1].name == "LostCard")

local PackDraw = require("render.panels.pack").draw
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
local MOTION = { now = 1.0, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
local METRICS = {
  rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 4,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 4, r_accw = 3, pw_total = 380,
  total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10,
  c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
  rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
}
local function pack_ctx(rows)
  return {
    theme = THEME, motion = MOTION, metrics = METRICS,
    data = { sn = "TAROT_PACK", state_name = "TAROT_PACK",
      pack_rows = { title = "Pack", picks_left = 0, pg = CLR(), cards = rows } },
    draw = { trunc = function(s) return s end,
      wrapped_lines = function() return { "a" } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end },
    center_top_y = 8,
  }
end

local bad_winner = joker_card("MISSING_WIN", { x = 3, y = 3 }, "LostCard")
local bad_loser = joker_card("MISSING_LOSER", { x = 1, y = 1 }, "LostLoser")
local function reset_pack_state()
  Showcase.reset_run_state()
  HudState.pack_last_sn = "TAROT_PACK"
  HudState.pack_losers = nil
  HudState.pack_disp = nil
  HudState.pack_card_indices = { [bad_winner] = 1, [bad_loser] = 2 }
  HudState.pack_initial_count = 2
  HudState.pack_appear_t = 0
  HudState.pack_hl = false
  HudState.pack_hl_t = 0
  HudState.pack_leave_t = nil
end

reset_pack_state()
HudState.pack_winners = { { slot = 1, card = bad_winner, name = "LostCard", badges = {} } }
HudState.pack_collapse_t = 1.0
HudState.pack_collapse_snap = {
  pk_x = 100, pk_w = 500, pk_content_w = 460, slot_w = 100, slot_gap = 8, pk_pad = 12,
  slot_h = 140, losers = { { index = 2, card = bad_loser, name = "LostLoser", hidden = false } },
  sp_w = 60, sp_h = 80, sp_dy = 6,
}
G.GAME.pack_choices = 0
reset_gfx()
local ctx = pack_ctx({
  { card = bad_winner, name = "LostCard", badges = {}, desc = "", rc = CLR(), index = 1 },
  { card = bad_loser, name = "LostLoser", badges = {}, desc = "", rc = CLR(), index = 2 },
})
local ok_pack, pack_err = xpcall(function() PackDraw(ctx) end, debug.traceback)
check("pack collapse with missing-atlas winner/loser draws without error", ok_pack, pack_err)
check("pack collapse draws zero foreign quads", #DRAWS == 0, tostring(#DRAWS))
check("pack winner fallback renders the card name",
  table.concat(PRINTED, ""):find("LostCard", 1, true) ~= nil)
check("pack loser fallback renders the card name",
  table.concat(PRINTED, ""):find("LostLoser", 1, true) ~= nil)
check("pack fallbacks increment the diagnostic counter twice", Cards._mini_fallback >= 2,
  Cards._mini_fallback)

reset_pack_state()
HudState.pack_winners = { { slot = 1, card = good_card, name = "FoundCard", badges = {} } }
HudState.pack_collapse_t = 1.0
HudState.pack_collapse_snap = {
  pk_x = 100, pk_w = 500, pk_content_w = 460, slot_w = 100, slot_gap = 8, pk_pad = 12,
  slot_h = 140, losers = { { index = 2, card = bad_loser, name = "LostLoser", hidden = false } },
  sp_w = 60, sp_h = 80, sp_dy = 6,
}
reset_gfx()
local ctx2 = pack_ctx({
  { card = good_card, name = "FoundCard", badges = {}, desc = "", rc = CLR(), index = 1 },
  { card = bad_loser, name = "LostLoser", badges = {}, desc = "", rc = CLR(), index = 2 },
})
local ok_pack2, pack_err2 = xpcall(function() PackDraw(ctx2) end, debug.traceback)
check("pack collapse with valid winner draws without error", ok_pack2, pack_err2)
check("valid winner renders from its own atlas", #DRAWS >= 1 and DRAWS[1].image == v71.image,
  tostring(#DRAWS))
check("valid winner does not count as fallback", Cards._mini_fallback == 1,
  Cards._mini_fallback)

local sprite_ak2, sprite_pos2 = Cards.card_sprite(joker_card("FIX95", { x = 0, y = 0 }, "Wide"))
check("card_sprite reports another valid atlas", sprite_ak2 == "FIX95" and sprite_pos2 ~= nil)

local front_ak, front_pos = Cards.card_sprite({
  config = { center = { key = "j_nopos", set = "Joker" },
    card = { pos = { x = 2, y = 3 } } },
  ability = {},
})
check("card_sprite resolves a center without pos to cards_1 front",
  front_ak == "cards_1" and front_pos and front_pos.x == 2 and front_pos.y == 3,
  front_ak)

local vanilla_base_card = {
  config = {
    center = { key = "c_base", set = "Default", pos = { x = 0, y = 0 }, name = "Base Card" },
    card = { pos = { x = 3, y = 1 }, value = "4", suit = "Spades" },
  },
  ability = {},
}
reset_gfx()
Cards.draw_card_mini(vanilla_base_card, 0, 0, 95, 1)
check("vanilla base playing card draws without falling back", Cards._mini_fallback == 0, Cards._mini_fallback)
check("vanilla base playing card draws 2 quads (center + face)", #DRAWS == 2, tostring(#DRAWS))

local vanilla_enhanced_card = {
  config = {
    center = { key = "m_bonus", set = "Enhanced", pos = { x = 1, y = 0 }, name = "Bonus Card" },
    card = { pos = { x = 3, y = 1 }, value = "4", suit = "Spades" },
  },
  ability = {},
}
reset_gfx()
Cards.draw_card_mini(vanilla_enhanced_card, 0, 0, 95, 1)
check("vanilla m_bonus playing card draws without falling back", Cards._mini_fallback == 0, Cards._mini_fallback)
check("vanilla m_bonus playing card draws 2 quads from centers and cards_1", #DRAWS == 2 and DRAWS[1].image == G.ASSET_ATLAS.centers.image, tostring(#DRAWS))

local custom_valid_enhanced_card = {
  config = {
    center = { key = "m_custom_ok", set = "Enhanced", atlas = "FIX71", pos = { x = 1, y = 2 }, name = "CustomOkCard" },
    card = { pos = { x = 3, y = 1 }, value = "4", suit = "Spades" },
  },
  ability = {},
}
reset_gfx()
Cards.draw_card_mini(custom_valid_enhanced_card, 0, 0, 95, 1)
check("custom valid atlas enhanced playing card draws center from FIX71 and face from cards_1", #DRAWS == 2 and DRAWS[1].image == v71.image, tostring(#DRAWS))
check("custom valid atlas enhanced playing card does not fall back", Cards._mini_fallback == 0, Cards._mini_fallback)

local enhanced_playing_card = {
  config = {
    center = { key = "m_custom", set = "Enhanced", atlas = "MISSING_KEY", pos = { x = 0, y = 0 }, name = "ModdedEnhanced" },
    card = { pos = { x = 3, y = 1 }, value = "4", suit = "Spades" },
  },
  ability = {},
}
reset_gfx()
Cards.draw_card_mini(enhanced_playing_card, 0, 0, 95, 1)
check("enhanced playing card with missing center atlas draws zero quads from centers", #DRAWS == 0, tostring(#DRAWS))
check("enhanced playing card with missing center atlas falls back", Cards._mini_fallback == 1, Cards._mini_fallback)

done()
