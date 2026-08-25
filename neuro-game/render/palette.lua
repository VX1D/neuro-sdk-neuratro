local Palette = {}

local Config = require("core.config")

Palette.PALETTES = {
  hiyori = {
    PRIMARY    = { 0.20, 0.20, 0.22 },
    DEEP       = { 0.10, 0.10, 0.12 },
    GLOW       = { 0.40, 0.40, 0.42 },
    BG         = { 0.05, 0.05, 0.06 },
    ACCENT     = { 0.30, 0.30, 0.32, 1 },
    NAME       = "H-I-Y-O-R-I",
    D_MONEY    = { 0.50, 0.50, 0.45 },
    D_GOLD     = { 0.45, 0.45, 0.40 },
    D_CYAN     = { 0.35, 0.38, 0.40 },
    D_SKYBLUE  = { 0.40, 0.42, 0.44 },
    D_GREEN    = { 0.35, 0.40, 0.35 },
    D_RED      = { 0.50, 0.30, 0.30 },
    D_MAROON   = { 0.42, 0.34, 0.36 },
    D_WHITE    = { 0.60, 0.60, 0.60 },
    D_DIM      = { 0.30, 0.30, 0.30 },
    D_ORANGE   = { 0.45, 0.38, 0.25 },
    D_YELLOW   = { 0.55, 0.55, 0.50 },
    D_PURPLE   = { 0.40, 0.38, 0.42 },
    FLASH_L    = { 0.78, 0.78, 0.78 },
    FLASH_D    = { 0.58, 0.58, 0.58 },
    PANEL_BG   = { 0.055, 0.055, 0.065 },
    ROW_BG     = { 0.085, 0.085, 0.100 },
    SEL_BG     = { 0.140, 0.140, 0.160 },
    FRAME      = { 0.30, 0.30, 0.33 },
    FRAME_DIM  = { 0.17, 0.17, 0.19 },
    MOTION     = { pulse_hz = 2.1 },
  },
  neuro = {
    PRIMARY    = { 0.120, 0.500, 0.480 },
    DEEP       = { 0.040, 0.090, 0.085 },
    GLOW       = { 1.000, 0.420, 0.541 },
    BG         = { 0.045, 0.095, 0.090 },
    ACCENT     = { 0.275, 0.847, 0.812, 1 },
    NAME       = "NEURO-SAMA",
    D_MONEY    = { 0.925, 0.706, 0.129 },
    D_GOLD     = { 0.925, 0.706, 0.129 },
    D_CYAN     = { 0.353, 0.651, 0.941 },
    D_SKYBLUE  = { 0.529, 0.729, 0.788 },
    D_GREEN    = { 0.376, 0.686, 0.412 },
    D_RED      = { 0.899, 0.205, 0.261 },
    D_MAROON   = { 0.917, 0.437, 0.827 },  -- rose-magenta despite the MAROON name; distinct from BOOSTER pink for CVD separation
    D_WHITE    = { 0.965, 0.975, 0.992 },
    D_DIM      = { 0.780, 0.830, 0.850 },
    D_ORANGE   = { 0.929, 0.443, 0.204 },
    D_YELLOW   = { 0.796, 0.816, 0.239 },
    D_PURPLE   = { 0.584, 0.410, 0.703 },
    FLASH_L    = { 0.996, 0.949, 0.882 },
    FLASH_D    = { 0.831, 0.694, 0.616 },
    PANEL_BG   = { 0.055, 0.135, 0.140 },
    ROW_BG     = { 0.075, 0.175, 0.180 },
    SEL_BG     = { 0.110, 0.240, 0.245 },
    FRAME      = { 0.16, 0.42, 0.45 },
    FRAME_DIM  = { 0.085, 0.235, 0.255 },
    MOTION     = { pulse_hz = 2.7 },
  },
  evil = {
    PRIMARY    = { 1.000, 0.150, 0.220 },
    GLOW       = { 1.000, 0.300, 0.350 },
    BG         = { 0.100, 0.030, 0.060 },
    ACCENT     = { 1.000, 0.150, 0.220, 1 },
    NAME       = "EVIL NEURO",
    D_MONEY    = { 0.784, 0.604, 0.227 },
    D_GOLD     = { 0.880, 0.620, 0.200 },
    D_CYAN     = { 0.549, 0.710, 0.871 },
    D_SKYBLUE  = { 0.651, 0.784, 0.902 },
    D_GREEN    = { 0.373, 0.722, 0.416 },
    D_RED      = { 0.950, 0.340, 0.360 },
    D_MAROON   = { 0.941, 0.341, 0.478 },
    D_WHITE    = { 0.941, 0.902, 0.894 },
    D_DIM      = { 0.720, 0.640, 0.660 },
    D_ORANGE   = { 1.000, 0.580, 0.200 },
    D_PURPLE   = { 0.680, 0.520, 0.950 },
    PANEL_BG   = { 0.082, 0.028, 0.044 },
    ROW_BG     = { 0.125, 0.046, 0.066 },
    SEL_BG     = { 0.170, 0.065, 0.090 },
    FRAME      = { 0.208, 0.078, 0.102 },
    FRAME_DIM  = { 0.125, 0.047, 0.067 },
    MOTION     = { pulse_hz = 2.0 },
  },
}

local function is_color(v)
  return type(v) == "table"
    and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
end

local KEY_ORDER = {
  "ACCENT", "PANEL_BG", "ROW_BG", "SEL_BG", "FRAME", "FRAME_DIM", "GLOW", "FLASH_L", "FLASH_D",
  "D_RED", "D_MAROON", "D_SKYBLUE", "D_CYAN", "D_GREEN", "D_YELLOW",
  "D_ORANGE", "D_PURPLE", "D_GOLD", "D_MONEY", "D_DIM", "D_WHITE",
}

local _color_keys = {}
local _defaults = {}

for pk, pal in pairs(Palette.PALETTES) do
  local seen_tbl, listed = {}, {}
  local keys = {}
  local function take(k)
    local v = pal[k]
    if is_color(v) and not listed[k] and not seen_tbl[v] then
      listed[k] = true
      seen_tbl[v] = true
      keys[#keys + 1] = k
    end
  end
  for _, k in ipairs(KEY_ORDER) do take(k) end
  local rest = {}
  for k, v in pairs(pal) do
    if is_color(v) and not listed[k] then rest[#rest + 1] = k end
  end
  table.sort(rest)
  for _, k in ipairs(rest) do take(k) end
  _color_keys[pk] = keys
  local defs = {}
  for _, k in ipairs(keys) do
    local c = pal[k]
    defs[k] = { c[1], c[2], c[3] }
  end
  _defaults[pk] = defs
end

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function to_hex(c)
  return string.format("%02X%02X%02X",
    math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Palette.color_keys(persona)
  return _color_keys[persona] or {}
end

function Palette.default_color(persona, key)
  return _defaults[persona] and _defaults[persona][key]
end

function Palette.get_color(persona, key)
  local pal = Palette.PALETTES[persona]
  return pal and pal[key]
end

function Palette.set_override(persona, key, r, g, b)
  local pal = Palette.PALETTES[persona]
  local dft = _defaults[persona] and _defaults[persona][key]
  if not (pal and dft and is_color(pal[key])) then return false end
  local c = pal[key]
  c[1], c[2], c[3] = clamp01(r), clamp01(g), clamp01(b)
  return Config.set_colour(persona, key, to_hex(c))
end

function Palette.set_override_hex(persona, key, hex)
  hex = tostring(hex or ""):gsub("^#", "")
  if not hex:match("^%x%x%x%x%x%x$") then return false end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  return Palette.set_override(persona, key, r, g, b)
end

function Palette.reset_color(persona, key)
  local pal = Palette.PALETTES[persona]
  local dft = _defaults[persona] and _defaults[persona][key]
  if not (pal and dft and is_color(pal[key])) then return false end
  local c = pal[key]
  c[1], c[2], c[3] = dft[1], dft[2], dft[3]
  Config.reset_colour(persona, key)
  return true
end

function Palette.reset_all_colors(persona)
  for _, k in ipairs(_color_keys[persona] or {}) do
    Palette.reset_color(persona, k)
  end
  Config.reset_colours(persona)
end

function Palette.persona()
  local fallback = Config.get_raw("NEURO_PERSONA")
  local persona = (G and G.NEURO and G.NEURO.persona) or fallback
  if Palette.PALETTES[persona] then return persona end
  return fallback
end

function Palette.pal()
  return Palette.PALETTES[Palette.persona()] or Palette.PALETTES.neuro
end

function Palette.displayed_persona()
  local anim = G and G.NEURO and G.NEURO.login_anim
  if anim and not anim.palette_ready then
    local from = anim.from
    if from and Palette.PALETTES[from] then return from end
  end
  return Palette.persona()
end

function Palette.displayed_pal()
  return Palette.PALETTES[Palette.displayed_persona()] or Palette.PALETTES.neuro
end

for persona, values in pairs(Config.get_colours()) do
  for key, hex in pairs(values) do
    Palette.set_override_hex(persona, key, hex)
  end
end

return Palette
