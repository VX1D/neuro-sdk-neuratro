rawset(_G, "NEURO_TEST", true)

local function noop() end
local current_font
local function font(width)
  return {
    getWidth = function(_, text) return #tostring(text or "") * (width or 7) end,
    getHeight = function() return 12 end,
    getWrap = function(_, text, limit) return limit, { tostring(text or "") } end,
  }
end
current_font = font(7)

love = {
  graphics = setmetatable({
    getFont = function() return current_font end,
    setFont = function(value) current_font = value or current_font end,
    newFont = function() return font(7) end,
    setColor = noop,
    rectangle = noop,
    line = noop,
    setLineWidth = noop,
    print = noop,
    setScissor = noop,
    getScissor = function() return nil end,
    intersectScissor = noop,
    newQuad = function() return {} end,
    draw = noop,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return G.TIMERS.REAL end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
  math = { random = math.random, noise = function() return 0 end },
}

_G.G = {
  NEURO = { persona = "hiyori", state = "SELECTING_HAND" },
  TIMERS = { REAL = 0 }, GAME = {}, P_CENTERS = {}, localization = {},
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  SETTINGS = { paused = false }, FUNCS = {},
}
_G.SMODS = {
  current_mod = { path = "./", config = { settings = {}, colours = {} } },
  Mods = {}, findModByID = function() return nil end,
}
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("carousel memo")
local H = require("render.hud_shared")
local S = H.S

local raw_name, raw_desc = H.card_display_name, H.card_description
local name_calls, desc_calls, wrap_calls, ui_calls = 0, 0, 0, 0
local last_name, last_desc
H.card_display_name = function(card)
  name_calls = name_calls + 1
  last_name = raw_name(card)
  return last_name
end
H.card_description = function(card)
  desc_calls = desc_calls + 1
  last_desc = raw_desc(card)
  return last_desc
end

local badges = { _v = 1 }
local rarity = { 0.4, 0.6, 0.8 }
local fx = "+4 Mult"
H.modifier_badges = function() return badges end
H.layout_modifier_badges = function() return { items = {}, rows = 0, height = 0, row_widths = {} } end
H.draw_modifier_badges = noop
H.rarity_color = function() return rarity end
H.joker_fx = function() return fx end
H.card_dimensions = function() return 12, 18 end
H.draw_card_mini = function() return 12 end

package.loaded["render.panels.right_panel"] = nil
local RightPanel = require("render.panels.right_panel")

local ui_value = "Alpha"
local card = {
  config = { center = { key = "j_carousel_memo", set = "Joker", rarity = 1 } },
  ability = { set = "Joker" },
  T = { w = 1, h = 1.4 },
}
card.generate_UIBox_ability_table = function()
  ui_calls = ui_calls + 1
  return {
    name = ui_value,
    main = { { config = { text = "Description " .. ui_value } } },
    info = {},
  }
end

local small_font, title_font = font(7), font(8)
local ctx = {
  theme = {
    pg = { 1, 1, 1 }, ACC = { 1, 1, 1 }, FR = { 1, 1, 1 }, FRD = { 0.2, 0.2, 0.2 },
    GOLD = { 1, 0.8, 0.2 }, ROW = { 0, 0, 0 }, SEL = { 0, 0, 0 },
    font = title_font, rfont_small = small_font, rp_font = title_font, rfont_title = title_font,
    persona_evil = false, persona_neuro = false,
  },
  motion = { now = 0, pulse = 0, shimr = 1, shimg = 1, shimb = 1 },
  metrics = {
    rn = function(value) return value end,
    sh = 720, p_x = 0, p_y = 0, p_w = 300, p_pad_x = 8,
    r_U = 1, r_accw = 2, pw_total = 300, total_h = 300, content_w = 280,
    n_cols = 1, n_cols_used = 1, title_h = 10, footer_h = 0,
    rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 14, rp_card_line_h = 28,
    rp_sep_h = 4, rp_hdr_line_h = 16, r_small_text_h = 12,
  },
  data = { panel_rows = { { kind = "carousel", cards = { card }, which = "joker" } }, showcase_alpha = 0 },
  draw = {
    trunc = function(text) return text end,
    wrapped_lines = function(text, limit, used_font)
      wrap_calls = wrap_calls + 1
      local _, lines = used_font:getWrap(text, limit)
      return lines
    end,
    draw_colored_desc = noop,
    draw_desc_lines = noop, print_colored_desc = noop,
    row_h = function() return 100 end,
  },
}

S.desc_slot, S.desc_epoch, S.desc_cache, S.desc_cache_n = 0, false, {}, -1
S.desc_anchor, S.desc_slot_ref = nil, nil
S.right_panel_slide_frac, S.state_changed_at, S.buy_showcase = 0, 0, nil

local function draw_at(t)
  G.TIMERS.REAL = t
  ctx.motion.now = t
  RightPanel.rows(ctx)
end

draw_at(0)
check("first carousel frame extracts UI text and wraps once",
  name_calls == 1 and desc_calls == 1 and wrap_calls == 1 and ui_calls == 1
    and last_name == "Alpha" and last_desc == "Description Alpha",
  string.format("name=%d desc=%d wrap=%d ui=%d", name_calls, desc_calls, wrap_calls, ui_calls))

draw_at(0.01)
check("unchanged second frame performs no expensive carousel calls",
  name_calls == 1 and desc_calls == 1 and wrap_calls == 1 and ui_calls == 1,
  string.format("name=%d desc=%d wrap=%d ui=%d", name_calls, desc_calls, wrap_calls, ui_calls))

badges._v = 2
draw_at(0.02)
check("badge _v participates in the cheap stamp without regenerating fresh UI text",
  name_calls == 2 and desc_calls == 2 and wrap_calls == 2 and ui_calls == 1,
  string.format("name=%d desc=%d wrap=%d ui=%d", name_calls, desc_calls, wrap_calls, ui_calls))
draw_at(0.03)
check("final tokens saved after a stamp rebuild prevent a next-frame rebuild",
  name_calls == 2 and desc_calls == 2 and wrap_calls == 2 and ui_calls == 1)

ui_value = "Beta"
draw_at(0.75)
check("UI text TTL invalidates the carousel and exposes fresh text in one rebuild",
  name_calls == 3 and desc_calls == 3 and wrap_calls == 3 and ui_calls == 2
    and last_name == "Beta" and last_desc == "Description Beta",
  string.format("name=%s desc=%s ui=%d", tostring(last_name), tostring(last_desc), ui_calls))

draw_at(0.76)
check("TTL rebuild does not repeat on the following frame",
  name_calls == 3 and desc_calls == 3 and wrap_calls == 3 and ui_calls == 2,
  string.format("name=%d desc=%d wrap=%d ui=%d", name_calls, desc_calls, wrap_calls, ui_calls))

done()
