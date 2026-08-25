local Palette = require("render.palette")
local NeuroState = require("core.state")
local neuro_log = require("util.utils").neuro_log

local M = {}
local _persona_colors_applied = nil
local _palette_baseline = nil
local _palette_selftest_done = false

local REPALETTE_KEYS = {
  "RED", "BLUE", "PURPLE", "GREEN", "GOLD", "ORANGE", "YELLOW",
  "BLACK", "L_BLACK", "GREY", "WHITE", "JOKER_GREY",
  "MULT", "CHIPS", "XMULT", "UI_MULT", "UI_CHIPS",
  "MONEY", "BOOSTER", "EDITION", "DARK_EDITION",
  "IMPORTANT", "FILTER", "VOUCHER", "CHANCE", "PALE_GREEN",
  "ETERNAL", "PERISHABLE", "RENTAL",
}

local NESTED_KEYS = {
  BACKGROUND    = { "L", "D", "C" },
  BLIND         = { "Small", "Big", "Boss", "won" },
  DYN_UI        = { "MAIN", "DARK", "BOSS_MAIN", "BOSS_DARK", "BOSS_PALE" },
  UI            = { "TEXT_LIGHT", "TEXT_DARK", "TEXT_INACTIVE",
                    "BACKGROUND_LIGHT", "BACKGROUND_WHITE", "BACKGROUND_DARK",
                    "BACKGROUND_INACTIVE", "OUTLINE_LIGHT", "OUTLINE_LIGHT_TRANS",
                    "OUTLINE_DARK", "TRANSPARENT_LIGHT", "TRANSPARENT_DARK", "HOVER" },
  SET           = { "Default", "Enhanced", "Joker", "Tarot", "Planet", "Spectral", "Voucher" },
  SECONDARY_SET = { "Default", "Enhanced", "Joker", "Tarot", "Planet", "Spectral", "Voucher", "Edition" },
}

local function cc(c) return { c[1], c[2], c[3], c[4] } end

local function apply_color_inplace(target, source)
  if not target or not source or type(target) ~= "table" or type(source) ~= "table" then return end
  target[1] = source[1]
  target[2] = source[2]
  target[3] = source[3]
  if source[4] ~= nil then target[4] = source[4] end
end

local function snapshot_palette_baseline()
  if _palette_baseline or not (G and G.C) then return end
  local snap = { flat = {}, nested = {} }

  for _, k in ipairs(REPALETTE_KEYS) do
    if type(G.C[k]) == "table" then
      snap.flat[k] = cc(G.C[k])
    end
  end

  for tbl, subs in pairs(NESTED_KEYS) do
    if type(G.C[tbl]) == "table" then
      snap.nested[tbl] = {}
      for _, sk in ipairs(subs) do
        if type(G.C[tbl][sk]) == "table" then
          snap.nested[tbl][sk] = cc(G.C[tbl][sk])
        end
      end
    end
  end

  _palette_baseline = snap
end

local function active_palette_key()
  local pk = Palette.displayed_persona()
  local state_name = NeuroState and NeuroState.get_state_name and NeuroState.get_state_name() or "MENU"
  local menuish = (state_name == "SPLASH" or state_name == "MENU" or state_name == "RUN_SETUP")

  if pk == "hiyori" and not menuish then
    pk = "neuro"
  end
  return pk
end

local HIYORI_COLORS = {
  RED         = { 0.35, 0.35, 0.35, 1 },
  BLUE        = { 0.40, 0.40, 0.40, 1 },
  PURPLE      = { 0.32, 0.32, 0.32, 1 },
  GREEN       = { 0.42, 0.42, 0.42, 1 },
  GOLD        = { 0.55, 0.55, 0.55, 1 },
  ORANGE      = { 0.45, 0.45, 0.45, 1 },
  YELLOW      = { 0.60, 0.60, 0.60, 1 },
  BLACK       = { 0.04, 0.04, 0.04, 1 },
  L_BLACK     = { 0.10, 0.10, 0.10, 1 },
  GREY        = { 0.35, 0.35, 0.35, 1 },
  WHITE       = { 0.80, 0.80, 0.80, 1 },
  JOKER_GREY  = { 0.50, 0.50, 0.50, 1 },
  MULT        = { 0.35, 0.35, 0.35, 1 },
  CHIPS       = { 0.40, 0.40, 0.40, 1 },
  XMULT       = { 0.30, 0.30, 0.30, 1 },
  UI_MULT     = { 0.35, 0.35, 0.35, 1 },
  UI_CHIPS    = { 0.40, 0.40, 0.40, 1 },
  MONEY       = { 0.55, 0.55, 0.55, 1 },
  BOOSTER     = { 0.30, 0.30, 0.30, 1 },
  EDITION     = { 0.65, 0.65, 0.65, 1 },
  DARK_EDITION= { 0.38, 0.38, 0.38, 1 },
  IMPORTANT   = { 0.50, 0.50, 0.50, 1 },
  FILTER      = { 0.50, 0.50, 0.50, 1 },
  VOUCHER     = { 0.35, 0.35, 0.35, 1 },
  CHANCE      = { 0.42, 0.42, 0.42, 1 },
  PALE_GREEN  = { 0.42, 0.42, 0.42, 1 },
  ETERNAL     = { 0.30, 0.30, 0.30, 1 },
  PERISHABLE  = { 0.32, 0.32, 0.32, 1 },
  RENTAL      = { 0.38, 0.38, 0.38, 1 },
  BACKGROUND  = {
    L = { 0.25, 0.25, 0.25, 1 },
    D = { 0.05, 0.05, 0.05, 1 },
    C = { 0.07, 0.07, 0.07, 1 },
  },
  BLIND = {
    Small = { 0.30, 0.30, 0.30, 1 },
    Big   = { 0.30, 0.30, 0.30, 1 },
    Boss  = { 0.25, 0.25, 0.25, 1 },
    won   = { 0.40, 0.40, 0.40, 1 },
  },
  DYN_UI = {
    MAIN      = { 0.08, 0.08, 0.08, 1 },
    DARK      = { 0.04, 0.04, 0.04, 1 },
    BOSS_MAIN = { 0.15, 0.15, 0.15, 1 },
    BOSS_DARK = { 0.10, 0.10, 0.10, 1 },
    BOSS_PALE = { 0.25, 0.25, 0.25, 1 },
  },
  UI = {
    TEXT_LIGHT       = { 0.80, 0.80, 0.80, 1 },
    TEXT_DARK        = { 0.20, 0.20, 0.20, 1 },
    TEXT_INACTIVE    = { 0.35, 0.35, 0.35, 0.60 },
    BACKGROUND_LIGHT = { 0.45, 0.45, 0.45, 1 },
    BACKGROUND_WHITE = { 0.70, 0.70, 0.70, 1 },
    BACKGROUND_DARK  = { 0.22, 0.22, 0.22, 1 },
    BACKGROUND_INACTIVE = { 0.18, 0.18, 0.18, 1 },
    OUTLINE_LIGHT    = { 0.50, 0.50, 0.50, 1 },
    OUTLINE_LIGHT_TRANS = { 0.50, 0.50, 0.50, 0.40 },
    OUTLINE_DARK     = { 0.22, 0.22, 0.22, 1 },
    TRANSPARENT_LIGHT = { 0.40, 0.40, 0.40, 0.13 },
    TRANSPARENT_DARK  = { 0.08, 0.08, 0.08, 0.13 },
    HOVER            = { 0.10, 0.10, 0.10, 0.33 },
  },
  SET = {
    Default  = { 0.50, 0.50, 0.50, 1 },
    Enhanced = { 0.50, 0.50, 0.50, 1 },
    Joker    = { 0.18, 0.18, 0.18, 1 },
    Tarot    = { 0.18, 0.18, 0.18, 1 },
    Planet   = { 0.18, 0.18, 0.18, 1 },
    Spectral = { 0.18, 0.18, 0.18, 1 },
    Voucher  = { 0.18, 0.18, 0.18, 1 },
  },
  SECONDARY_SET = {
    Default  = { 0.40, 0.40, 0.40, 1 },
    Enhanced = { 0.35, 0.35, 0.35, 1 },
    Joker    = { 0.35, 0.35, 0.35, 1 },
    Tarot    = { 0.32, 0.32, 0.32, 1 },
    Planet   = { 0.38, 0.38, 0.38, 1 },
    Spectral = { 0.35, 0.35, 0.35, 1 },
    Voucher  = { 0.40, 0.40, 0.40, 1 },
    Edition  = { 0.38, 0.38, 0.38, 1 },
  },
}

local NEURO_COLORS = {
  RED          = { 0.932, 0.243, 0.291, 1 },
  BLUE         = { 0.275, 0.847, 0.812, 1 },
  PURPLE       = { 0.545, 0.373, 0.663, 1 },
  GREEN        = { 0.376, 0.686, 0.412, 1 },
  GOLD         = { 0.925, 0.706, 0.129, 1 },
  ORANGE       = { 0.929, 0.443, 0.204, 1 },
  YELLOW       = { 0.796, 0.816, 0.239, 1 },
  BLACK        = { 0.098, 0.086, 0.118, 1 },
  L_BLACK      = { 0.157, 0.141, 0.184, 1 },
  GREY         = { 0.490, 0.467, 0.557, 1 },
  WHITE        = { 0.984, 0.984, 1.000, 1 },
  JOKER_GREY   = { 0.745, 0.725, 0.800, 1 },

  MULT         = { 1.000, 0.651, 0.788, 1 },
  CHIPS        = { 0.275, 0.847, 0.812, 1 },
  XMULT        = { 0.932, 0.243, 0.291, 1 },

  UI_MULT      = { 1.000, 0.651, 0.788, 1 },
  UI_CHIPS     = { 0.275, 0.847, 0.812, 1 },
  MONEY        = { 0.925, 0.706, 0.129, 1 },
  BOOSTER      = { 1.000, 0.420, 0.540, 1 },

  EDITION      = { 0.855, 0.835, 0.925, 1 },
  DARK_EDITION = { 0.530, 0.490, 0.680, 1 },
  IMPORTANT    = { 0.932, 0.243, 0.291, 1 },
  FILTER       = { 0.932, 0.243, 0.291, 1 },
  VOUCHER      = { 0.925, 0.706, 0.129, 1 },
  CHANCE       = { 1.000, 0.420, 0.540, 1 },

  PALE_GREEN   = { 0.580, 0.820, 0.630, 1 },
  ETERNAL      = { 0.365, 0.173, 0.220, 1 },
  PERISHABLE   = { 0.590, 0.565, 0.690, 1 },
  RENTAL       = { 0.780, 0.750, 0.620, 1 },

  BACKGROUND = {
    L = { 1.000, 0.780, 0.855, 1 },
    D = { 0.980, 0.650, 0.780, 1 },
    C = { 0.960, 0.580, 0.720, 1 },
  },

  BLIND = {
    Small = { 0.960, 0.580, 0.720, 1 },
    Big   = { 1.000, 0.780, 0.855, 1 },
    Boss  = { 0.867, 0.169, 0.239, 1 },
    won   = { 1.000, 0.420, 0.540, 1 },
  },

  DYN_UI = {
    MAIN      = { 0.118, 0.106, 0.145, 1 },
    DARK      = { 0.082, 0.075, 0.110, 1 },
    BOSS_MAIN = { 0.180, 0.160, 0.210, 1 },
    BOSS_DARK = { 0.120, 0.108, 0.155, 1 },
    BOSS_PALE = { 0.310, 0.290, 0.380, 1 },
  },

  UI = {
    TEXT_LIGHT          = { 0.984, 0.984, 1.000, 1 },
    TEXT_DARK           = { 0.098, 0.086, 0.118, 1 },
    TEXT_INACTIVE       = { 0.600, 0.575, 0.690, 0.66 },
    BACKGROUND_LIGHT    = { 1.000, 0.780, 0.855, 1 },
    BACKGROUND_WHITE    = { 0.984, 0.984, 1.000, 1 },
    BACKGROUND_DARK     = { 0.098, 0.086, 0.118, 1 },
    BACKGROUND_INACTIVE = { 0.170, 0.155, 0.200, 1 },
    OUTLINE_LIGHT       = { 0.275, 0.847, 0.812, 1 },
    OUTLINE_LIGHT_TRANS = { 0.275, 0.847, 0.812, 0.45 },
    OUTLINE_DARK        = { 0.098, 0.086, 0.118, 1 },
    TRANSPARENT_LIGHT   = { 0.984, 0.984, 1.000, 0.18 },
    TRANSPARENT_DARK    = { 0.098, 0.086, 0.118, 0.16 },
    HOVER               = { 0.275, 0.847, 0.812, 0.28 },
  },

  SET = {
    Default  = { 0.975, 0.960, 0.975, 1 },
    Enhanced = { 0.975, 0.960, 0.975, 1 },
    Joker    = { 0.140, 0.125, 0.165, 1 },
    Tarot    = { 0.140, 0.125, 0.165, 1 },
    Planet   = { 0.140, 0.125, 0.165, 1 },
    Spectral = { 0.140, 0.125, 0.165, 1 },
    Voucher  = { 0.140, 0.125, 0.165, 1 },
  },

  SECONDARY_SET = {
    Default  = { 1.000, 0.780, 0.855, 1 },
    Enhanced = { 1.000, 0.651, 0.788, 1 },
    Joker    = { 1.000, 0.302, 0.580, 1 },
    Tarot    = { 0.545, 0.373, 0.663, 1 },
    Planet   = { 0.275, 0.847, 0.812, 1 },
    Spectral = { 0.545, 0.373, 0.663, 1 },
    Voucher  = { 0.925, 0.706, 0.129, 1 },
    Edition  = { 0.275, 0.847, 0.812, 1 },
  },
}

local EVIL_COLORS = {
  RED         = { 0.730, 0.165, 0.192, 1 },
  BLUE        = { 0.101, 0.585, 0.846, 1 },
  PURPLE      = { 0.500, 0.316, 0.756, 1 },
  GREEN       = { 0.074, 0.602, 0.283, 1 },
  GOLD        = { 0.663, 0.514, 0.169, 1 },
  ORANGE      = { 0.859, 0.446, 0.022, 1 },
  YELLOW      = { 0.891, 0.800, 0.210, 1 },
  BLACK       = { 0.088, 0.011, 0.016, 1 },
  L_BLACK     = { 0.201, 0.080, 0.087, 1 },
  GREY        = { 0.422, 0.280, 0.282, 1 },
  WHITE       = { 0.961, 0.891, 0.879, 1 },
  JOKER_GREY  = { 0.602, 0.462, 0.459, 1 },
  MULT        = { 0.839, 0.278, 0.282, 1 },
  CHIPS       = { 0.101, 0.585, 0.846, 1 },
  XMULT       = { 0.894, 0.288, 0.398, 1 },
  UI_MULT     = { 0.839, 0.278, 0.282, 1 },
  UI_CHIPS    = { 0.101, 0.585, 0.846, 1 },
  MONEY       = { 0.663, 0.514, 0.169, 1 },
  BOOSTER     = { 0.632, 0.193, 0.439, 1 },
  EDITION     = { 0.745, 0.574, 0.784, 1 },
  DARK_EDITION= { 0.455, 0.298, 0.490, 1 },
  IMPORTANT   = { 0.930, 0.380, 0.141, 1 },
  FILTER      = { 0.930, 0.380, 0.141, 1 },
  VOUCHER     = { 0.837, 0.362, 0.076, 1 },
  CHANCE      = { 0.074, 0.602, 0.283, 1 },
  PALE_GREEN  = { 0.186, 0.508, 0.280, 1 },
  ETERNAL     = { 0.745, 0.225, 0.370, 1 },
  PERISHABLE  = { 0.387, 0.335, 0.751, 1 },
  RENTAL      = { 0.723, 0.460, 0.005, 1 },
  BACKGROUND  = {
    L = { 0.809, 0.445, 0.494, 1 },
    D = { 0.276, 0.165, 0.180, 1 },
    C = { 0.323, 0.226, 0.239, 1 },
  },
  BLIND = {
    Small = { 0.657, 0.206, 0.257, 1 },
    Big   = { 0.657, 0.206, 0.257, 1 },
    Boss  = { 0.730, 0.165, 0.192, 1 },
    won   = { 0.232, 0.586, 0.332, 1 },
  },
  DYN_UI = {
    MAIN      = { 0.150, 0.014, 0.029, 1 },
    DARK      = { 0.079, 0.000, 0.006, 1 },
    BOSS_MAIN = { 0.566, 0.058, 0.130, 1 },
    BOSS_DARK = { 0.360, 0.002, 0.071, 1 },
    BOSS_PALE = { 0.840, 0.435, 0.430, 1 },
  },
  UI = {
    TEXT_LIGHT       = { 0.998, 0.932, 0.909, 1 },
    TEXT_DARK        = { 0.076, 0.018, 0.020, 1 },
    TEXT_INACTIVE    = { 0.780, 0.586, 0.611, 0.55 },
    BACKGROUND_LIGHT = { 0.865, 0.457, 0.477, 1 },
    BACKGROUND_WHITE = { 0.961, 0.891, 0.879, 1 },
    BACKGROUND_DARK  = { 0.525, 0.058, 0.153, 1 },
    BACKGROUND_INACTIVE = { 0.473, 0.247, 0.257, 1 },
    OUTLINE_LIGHT    = { 0.783, 0.383, 0.426, 1 },
    OUTLINE_LIGHT_TRANS = { 0.783, 0.383, 0.426, 0.40 },
    OUTLINE_DARK     = { 0.525, 0.058, 0.153, 1 },
    TRANSPARENT_LIGHT = { 0.865, 0.457, 0.477, 0.13 },
    TRANSPARENT_DARK  = { 0.093, 0.000, 0.007, 0.13 },
    HOVER            = { 0.079, 0.000, 0.006, 0.33 },
  },
  SET = {
    Default  = { 0.720, 0.266, 0.352, 1 },
    Enhanced = { 0.720, 0.266, 0.352, 1 },
    Joker    = { 0.359, 0.001, 0.083, 1 },
    Tarot    = { 0.359, 0.001, 0.083, 1 },
    Planet   = { 0.359, 0.001, 0.083, 1 },
    Spectral = { 0.359, 0.001, 0.083, 1 },
    Voucher  = { 0.359, 0.001, 0.083, 1 },
  },
  SECONDARY_SET = {
    Default  = { 0.649, 0.203, 0.324, 1 },
    Enhanced = { 0.515, 0.216, 0.581, 1 },
    Joker    = { 0.626, 0.178, 0.277, 1 },
    Tarot    = { 0.639, 0.282, 0.616, 1 },
    Planet   = { 0.014, 0.512, 0.752, 1 },
    Spectral = { 0.347, 0.268, 0.739, 1 },
    Voucher  = { 0.837, 0.362, 0.076, 1 },
    Edition  = { 0.007, 0.529, 0.344, 1 },
  },
}

local PERSONA_COLORS = { hiyori = HIYORI_COLORS, neuro = NEURO_COLORS, evil = EVIL_COLORS }
local PERSONA_ORDER = { "hiyori", "neuro", "evil" }

local function apply_palette(palette)
  if not palette or not G or not G.C or not _palette_baseline then return end
  for _, k in ipairs(REPALETTE_KEYS) do
    local src = palette[k] or (_palette_baseline.flat and _palette_baseline.flat[k])
    if src and G.C[k] then
      apply_color_inplace(G.C[k], src)
    end
  end
  for tbl, subs in pairs(NESTED_KEYS) do
    if G.C[tbl] then
      for _, sk in ipairs(subs) do
        local src = (palette[tbl] and palette[tbl][sk])
          or (_palette_baseline.nested and _palette_baseline.nested[tbl] and _palette_baseline.nested[tbl][sk])
        if src and G.C[tbl][sk] then
          apply_color_inplace(G.C[tbl][sk], src)
        end
      end
    end
  end
end

local function run_palette_selftest_once()
  if _palette_selftest_done or not (G and G.C) then return end
  if not _palette_baseline then return end

  local all_keys = {}
  for _, name in ipairs(PERSONA_ORDER) do
    for k in pairs(PERSONA_COLORS[name]) do all_keys[k] = true end
  end
  for _, name in ipairs(PERSONA_ORDER) do
    for k in pairs(all_keys) do
      if PERSONA_COLORS[name][k] == nil then
        print("[neuro-game] Palette selftest: '" .. name .. "' is missing key " .. tostring(k))
      end
    end
  end

  local ok_count = 0
  for _, name in ipairs(PERSONA_ORDER) do
    local ok, err = pcall(apply_palette, PERSONA_COLORS[name])
    if ok then
      ok_count = ok_count + 1
    else
      print("[neuro-game] Palette selftest failed for " .. name .. ": " .. tostring(err))
    end
  end

  pcall(apply_palette, {})
  _palette_selftest_done = true
  neuro_log("Palette selftest:", ok_count, "/" .. #PERSONA_ORDER .. " personas OK")
end

function M.apply_for_frame()
  if not (G and G.C) then return end
  snapshot_palette_baseline()
  run_palette_selftest_once()
  local pk = active_palette_key()
  if pk ~= _persona_colors_applied then
    neuro_log("Palette ->", pk)
    _persona_colors_applied = pk
    apply_palette(PERSONA_COLORS[pk] or NEURO_COLORS)
  end
end

if rawget(_G, "NEURO_TEST") then M._test = { colors = PERSONA_COLORS } end

return M
