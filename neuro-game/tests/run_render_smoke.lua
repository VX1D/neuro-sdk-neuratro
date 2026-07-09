-- Render ctx-contract smoke test.
--
-- The per-frame panel context (render/hud_overlay.lua) is a set of grouped sub-tables --
-- theme / motion / metrics / data / draw -- built by the assembly block and consumed by each panel's
-- top-of-function unpack. Every panel reads its whole field set unconditionally in that prologue before
-- any drawing, so a single call exercises the complete field contract. This test builds a ctx whose
-- sub-tables carry EXACTLY the keys the assembly provides and error on any absent key, then invokes each
-- panel under a love/G stub. If a panel reads a field name the assembly never sets (a rename/typo drift
-- between assembly and consumer), the guard throws NEURO_MISSING_FIELD and the suite fails.
--
-- Scope: this validates the field contract, NOT pixel output -- panels crash deep in the graphics stub
-- and those errors are intentionally swallowed; only NEURO_MISSING_FIELD is treated as a failure.
--
-- luajit tests/run_render_smoke.lua   (exit 0 = contract intact)

package.path = "./?.lua;;" .. package.path

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
_G.SMODS = { current_mod = { path = "./" }, Mods = {} }
_G.NFS = stub_table()

local Rows = require "hud.rows"

-- sentinel factories: every field must be present (non-nil) so only a genuinely-absent key throws;
-- runtime-nullable fields (showcase_card, logo, action_text) still get a placeholder here.
local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local FONT = { getWidth = function() return 8 end, getHeight = function() return 10 end }
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end

-- exact key sets, mirrored from the assembly in render/hud_overlay.lua
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
    pack_rows = { Rows.line(CLR(), "pack") },
    sn = 1, state_name = "SHOP",
    showcase_card = {}, showcase_name = "Card", showcase_label = "Tarot", showcase_fx = "fx",
    showcase_desc = "desc", showcase_alpha = 0, showcase_slide = 0,
    quip_display = "hi", footer_emote = "", footer_is_emote = false, jokers_on_screen = {},
    state_label = "SHOP", is_thinking = false, action_text = "act",
    logo = nil, logo_w = 100, logo_h = 40, logo_scale = 1,
    booster_active = false, pack_state_active = false,
  }
end
-- logo is nullable at runtime, but the guard cannot tell absent from nil; carry a placeholder key so a
-- real missing-field bug (a panel reading data.logo_missing) still surfaces.
local function DRAW()
  return {
    trunc = function(s) return s end,
    wrapped_lines = function() return { "a" } end,
    draw_colored_desc = function() end,
    row_h = function() return 16 end,
    showcase_type_colors = function() return CLR(), CLR() end,
  }
end

local function guarded(name, t)
  return setmetatable(t, { __index = function(_, k)
    error("NEURO_MISSING_FIELD:" .. name .. "." .. tostring(k), 2)
  end })
end

local function build_ctx(evil, neuro)
  local theme = {}
  for k, v in pairs(THEME) do theme[k] = v end
  theme.persona_evil, theme.persona_neuro = evil, neuro
  local data = make_data()
  data.logo = FONT  -- non-nil placeholder so the guard treats data.logo as a provided key
  local ctx = {
    theme = guarded("theme", theme),
    motion = guarded("motion", MOTION),
    metrics = guarded("metrics", METRICS),
    data = guarded("data", data),
    draw = guarded("draw", DRAW()),
    center_top_y = 8,
  }
  -- guard the top-level bag too: a leftover flat read (ctx.pg) must surface, but the 5 groups +
  -- center_top_y are present and panels may write new cursor values back onto ctx.
  return setmetatable(ctx, { __index = function(_, k)
    error("NEURO_MISSING_FIELD:ctx." .. tostring(k), 2)
  end })
end

local PANELS = {
  { "shop",           require("render.panels.shop").draw },
  { "buy_toast",      require("render.panels.buy_toast").draw },
  { "center_showcase",require("render.panels.center_showcase").draw },
  { "pack",           require("render.panels.pack").draw },
  { "rp_frame",       require("render.panels.right_panel").frame },
  { "rp_header",      require("render.panels.right_panel").header },
  { "rp_rows",        require("render.panels.right_panel").rows },
  { "rp_footer",      require("render.panels.right_panel").footer },
}

print("====================================================")
print("[render] ctx field-contract smoke (" .. #PANELS .. " panels x 3 personas)")
print("====================================================")

local fails = {}
local checks = 0
for _, combo in ipairs({ { false, false }, { true, false }, { false, true } }) do
  for _, pan in ipairs(PANELS) do
    local label, fn = pan[1], pan[2]
    local ctx = build_ctx(combo[1], combo[2])
    checks = checks + 1
    local ok, err = pcall(fn, ctx)
    if not ok and type(err) == "string" and err:find("NEURO_MISSING_FIELD") then
      fails[#fails + 1] = label .. " [evil=" .. tostring(combo[1]) .. ",neuro=" .. tostring(combo[2])
        .. "]  ->  " .. err:gsub("^.-NEURO_MISSING_FIELD", "NEURO_MISSING_FIELD"):gsub("\n.*", "")
    end
    -- any non-tagged error is a deep graphics-stub crash, not a field-contract failure: ignored.
  end
end

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
