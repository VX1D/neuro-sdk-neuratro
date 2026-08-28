rawset(_G, "NEURO_TEST", true)

local function stub_table()
  return setmetatable({}, { __index = function(_, _) return function(...) return nil end end })
end
love = setmetatable({
  timer = { getTime = function() return 0 end },
  graphics = stub_table(), audio = stub_table(), system = stub_table(),
  window = stub_table(), filesystem = stub_table(),
  math = { random = math.random, noise = function() return 0 end },
  keyboard = stub_table(), mouse = stub_table(), event = stub_table(), thread = stub_table(),
}, { __index = function(_, _) return function(...) return nil end end })

_G.G = {
  NEURO = { persona = "hiyori" }, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 },
  STATES = {}, SETTINGS = { paused = false }, C = stub_table(),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
}
_G.SMODS = {
  current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end,
  Mods = {},
}
_G.NFS = stub_table()

local Rows = require "hud.rows"

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local FONT = { getWidth = function() return 8 end, getHeight = function() return 10 end }
local screen_w, screen_h = 1920, 1080
love.graphics.getWidth = function() return screen_w end
love.graphics.getHeight = function() return screen_h end
local _px_fonts = {}
love.graphics.newFont = function(px)
  px = tonumber(px) or 12
  local f = _px_fonts[px]
  if not f then
    f = {
      getWidth = function(_, str) return math.floor(0.5 * px * #tostring(str) + 0.5) end,
      getHeight = function() return math.floor(1.3 * px + 0.5) end,
    }
    _px_fonts[px] = f
  end
  return f
end
love.graphics.getFont = function() return FONT end
love.graphics.getScissor = function() return nil end
love.mouse.getPosition = function() return 0, 0 end
love.keyboard.isDown = function() return false end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end

local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(),
  ORANGE = CLR(), GREEN = CLR(), DIM = CLR(), WHITE = CLR(), CYAN = CLR(), GOLD = CLR(),
  _pal = PAL, persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  boss = false, is_round_eval = false,
  font = FONT, panel_font_small = FONT, rfont = FONT, rfont_small = FONT,
  lfont = FONT, lfont_small = FONT, rp_font = FONT,
  cfont = FONT, cfont_small = FONT, cfont_title = FONT, cfont_micro = FONT,
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT, font_display = FONT,
}
local MOTION = { now = 0, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
local METRICS = {
  rn = id, ln = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
  cn = id,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_y_target_stable = 100, p_w = 380, p_pad_x = 12, r_U = 6, r_accw = 3, pw_total = 380,
  total_h = 800, panel_h_target = 800, row_hs = {}, content_w = 356, n_cols = 1, n_cols_used = 1, title_h = 40, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10,
  c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
  rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
  main_side = "right", main_slide_dir = 1, offset_x_px = 0,
  anchor = "auto", offset_y = 0,
  shop_anchor = "auto", shop_offset_x = 0, shop_offset_y = 0,
}
local function make_data()
  return {
    panel_rows = {
      Rows.header(CLR(), "HEADER"), Rows.line(CLR(), "line"), Rows.sub(CLR(), "sub"),
      Rows.sep(), Rows.carousel({ {} }, "cons"), Rows.deckback({}, "Deck", "desc", CLR()),
    },
    shop_rows = { Rows.shopcard(CLR(), "card", {}, 3, true, nil, {
      { kind = "edition", text = "Holo" }, { kind = "seal", text = "Gold Seal" },
    }), Rows.note(CLR(), "note"), Rows.descwrap(CLR(), "desc"), Rows.sep() },
    pack_rows = { Rows.line(CLR(), "pack") },
    sn = "SHOP", state_name = "SHOP",
    showcase_card = {}, showcase_name = "Card", showcase_label = "Tarot",
    showcase_desc = "desc", showcase_alpha = 0, showcase_slide = 0,
    quip_display = "hi", footer_emote = "", footer_is_emote = false, footer_fade = 1,
    footer_prev_emote = false, footer_prev_quip = "", footer_legend = false,
    footer_prev_legend = false,
      footer_legend_meta = false,
      footer_prev_legend_meta = false,
    jokers_on_screen = {},
    state_label = "SHOP", is_thinking = false, action_text = "act",
    logo = nil, logo_w = 100, logo_h = 40, logo_scale = 1,
    booster_active = false, pack_state_active = false,
  }
end
local function DRAW()
  return {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = function() end,
    draw_desc_lines = function() end, print_colored_desc = function() end,
    row_h = function() return 16 end,
    showcase_type_colors = function() return CLR(), CLR() end,
  }
end

local function guarded(name, t)
  return setmetatable(t, { __index = function(_, k)
    error("NEURO_MISSING_FIELD:" .. name .. "." .. tostring(k), 2)
  end })
end

local function build_ctx(evil, neuro, side)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  local metrics = {}
  for k, v in pairs(METRICS) do metrics[k] = v end
  metrics.main_side = side
  metrics.main_slide_dir = side == "left" and -1 or 1
  metrics.p_x = side == "left" and 8 or 1500
  local data = make_data()
  data.logo = FONT
  local ctx = {
    theme = guarded("theme", theme),
    motion = guarded("motion", MOTION),
    metrics = guarded("metrics", metrics),
    data = guarded("data", data),
    draw = guarded("draw", DRAW()),
    center_top_y = 8,
  }
  return setmetatable(ctx, { __index = function(_, k)
    error("NEURO_MISSING_FIELD:ctx." .. tostring(k), 2)
  end })
end

local PANELS = {
  { "shop",           require("render.panels.shop").draw },
  { "acquire",        require("render.panels.acquire").draw },
  { "pack",           require("render.panels.pack").draw },
  { "rp_frame",       require("render.panels.right_panel").frame },
  { "rp_header",      require("render.panels.right_panel").header },
  { "rp_rows",        require("render.panels.right_panel").rows },
  { "rp_footer",      require("render.panels.right_panel").footer },
}

print("====================================================")
print("[render] ctx field-contract smoke (" .. #PANELS .. " panels x 3 personas x 2 sides)")
print("====================================================")

local fails = {}
local checks = 0
local HUDState = require("hud.state")
for _, combo in ipairs({ { false, false }, { true, false }, { false, true } }) do
  for _, side in ipairs({ "left", "right" }) do
    for _, pan in ipairs(PANELS) do
      local label, fn = pan[1], pan[2]
      HUDState.shop_x_current, HUDState.shop_y_current = nil, nil
      local ctx = build_ctx(combo[1], combo[2], side)
      checks = checks + 1
      local ok, err = pcall(fn, ctx)
      if not ok then
        local msg = tostring(err):gsub("\n.*", "")
        if msg:find("NEURO_MISSING_FIELD") then
          msg = msg:gsub("^.-NEURO_MISSING_FIELD", "NEURO_MISSING_FIELD")
        end
        fails[#fails + 1] = label .. " [side=" .. side .. ",evil=" .. tostring(combo[1])
          .. ",neuro=" .. tostring(combo[2]) .. "]  -> " .. msg
      end
    end
  end
end

local function record(label, ok, err)
  checks = checks + 1
  if not ok then fails[#fails + 1] = label .. " -> " .. tostring(err or "contract failed") end
end

local TuningPanel = require("hud.tuning_panel")
if not TuningPanel.is_open() then TuningPanel.toggle() end
for _, size in ipairs({ { 1280, 720 }, { 1920, 1080 }, { 2560, 1080 },
  { 1024, 768 }, { 3840, 1080 }, { 1280, 700 } }) do
  screen_w, screen_h = size[1], size[2]
  local ok, err = pcall(TuningPanel.draw)
  local hit = TuningPanel._test.hit
  record("tuning position card [" .. screen_w .. "x" .. screen_h .. "]",
    ok and hit.place_w > 0 and hit.place_h > 0
      and hit.place_x >= hit.cx and hit.place_x + hit.place_w <= hit.cx + hit.cw
      and hit.place_y >= hit.cy and hit.place_y + hit.place_h <= hit.cy + hit.ch
      and #hit.place_anchors == 7
      and #hit.place_tabs == 2
      and hit.place_tabs[2].x + hit.place_tabs[2].w <= hit.place_x + hit.place_w
      and hit.place_slider_w[1] > 0 and hit.place_slider_w[2] > 0
      and hit.place_slider_w[3] > 0 and hit.place_slider_w[4] > 0
      and hit.place_slider_x[4] + hit.place_slider_w[4] <= hit.place_x + hit.place_w
      and hit.place_reset ~= nil,
    err)
  local tabs_fit = true
  for t = 1, 5 do
    local tx, tw = hit.tab_x[t], hit.tab_w[t]
    if not (tx and tw and tw > 0 and tx >= hit.px and tx + tw <= hit.px + hit.pw) then
      tabs_fit = false
    end
  end
  record("tuning tab track fits the panel [" .. screen_w .. "x" .. screen_h .. "]", tabs_fit)
  local rows_fit = true
  for i = 1, 4 do
    local lx = hit.place_slider_x[i]
    local lw = hit.place_slider_w[i]
    if not (lx and lw and lw > 0 and lx > hit.place_x
      and lx + lw <= hit.place_x + hit.place_w) then
      rows_fit = false
    end
  end
  record("tuning slider tracks stay inside the card [" .. screen_w .. "x" .. screen_h .. "]",
    rows_fit)
  local reset_fit = hit.place_reset.x >= hit.place_x
    and hit.place_reset.x + hit.place_reset.w <= hit.place_x + hit.place_w
    and hit.place_reset.y + hit.place_reset.h <= hit.place_y + hit.place_h
  record("tuning reset button stays inside the card [" .. screen_w .. "x" .. screen_h .. "]",
    reset_fit)
end
TuningPanel.toggle()

print(string.format("[render] %d panel invocations exercised", checks))
print("====================================================")
if #fails == 0 then
  print(string.format("==== render_ctx: %d checks, 0 FAIL ====", checks))
else
  print(string.format("==== render_ctx: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("====================================================")
print("RENDER_CTX_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
