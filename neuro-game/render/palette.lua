local Palette = {}

local dotenv = require("util.dotenv")

local NEURO_PERSONA = dotenv.normalize_persona(dotenv.get("NEURO_PERSONA"))

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
    FRAME      = { 0.30, 0.30, 0.33 },
    FRAME_DIM  = { 0.17, 0.17, 0.19 },
    MOTION     = { pulse_hz = 2.1 },
  },
  neuro = {
    PRIMARY    = { 0.120, 0.500, 0.480 },
    DEEP       = { 0.040, 0.090, 0.085 },
    GLOW       = { 1.000, 0.420, 0.541 }, -- hair-clip pink, pulse/glow only
    BG         = { 0.045, 0.095, 0.090 },
    ACCENT     = { 0.275, 0.847, 0.812, 1 }, -- bow teal
    NAME       = "NEURO-SAMA",
    D_MONEY    = { 0.925, 0.706, 0.129 },
    D_GOLD     = { 0.925, 0.706, 0.129 },
    D_CYAN     = { 0.275, 0.847, 0.812 }, -- bow teal
    D_SKYBLUE  = { 0.529, 0.729, 0.788 }, -- eyes
    D_GREEN    = { 0.376, 0.686, 0.412 },
    D_RED      = { 0.899, 0.205, 0.261 },
    D_MAROON   = { 0.639, 0.421, 0.466 }, -- hair ribbon, lifted for contrast
    D_WHITE    = { 0.965, 0.975, 0.992 },
    D_DIM      = { 0.635, 0.795, 0.825 }, -- pastel teal secondary, warm grey reads dead on the teal body
    D_ORANGE   = { 0.929, 0.443, 0.204 },
    D_YELLOW   = { 0.796, 0.816, 0.239 },
    D_PURPLE   = { 0.584, 0.410, 0.703 },
    FLASH_L    = { 0.996, 0.949, 0.882 }, -- skin highlight
    FLASH_D    = { 0.831, 0.694, 0.616 }, -- skin shade
    PANEL_BG   = { 0.030, 0.086, 0.098 },
    FRAME      = { 0.16, 0.42, 0.45 },
    FRAME_DIM  = { 0.085, 0.235, 0.255 },
    MOTION     = { pulse_hz = 2.7 },
  },
  evil = {
    PRIMARY    = { 0.431, 0.063, 0.098 }, -- deep blood-red base tint
    GLOW       = { 0.710, 0.157, 0.212 }, -- crimson ember glow, pulse/effects only
    BG         = { 0.031, 0.012, 0.020 }, -- obsidian
    ACCENT     = { 0.902, 0.224, 0.271, 1 }, -- hot crimson, the one loud color / interactive cue
    NAME       = "EVIL NEURO",
    D_MONEY    = { 0.663, 0.514, 0.169 }, -- muted brass (money value only)
    D_GOLD     = { 0.663, 0.514, 0.169 },
    D_CYAN     = { 0.231, 0.639, 0.894 }, -- cold azure (CHIP) -- deliberate contrast pop
    D_SKYBLUE  = { 0.353, 0.690, 0.933 },
    D_GREEN    = { 0.275, 0.698, 0.416 }, -- venom green (+gain)
    D_RED      = { 0.839, 0.227, 0.278 }, -- crimson (MULT)
    D_MAROON   = { 0.886, 0.282, 0.408 }, -- hot rose (Xmult), distinct from MULT
    D_WHITE    = { 0.941, 0.902, 0.894 }, -- bone text
    D_DIM      = { 0.525, 0.447, 0.478 }, -- cool ash secondary
    D_ORANGE   = { 0.851, 0.439, 0.180 }, -- ember (default word)
    D_PURPLE   = { 0.522, 0.322, 0.800 }, -- violet (spectral)
    PANEL_BG   = { 0.059, 0.020, 0.031 }, -- obsidian panel fill, faint red
    FRAME      = { 0.208, 0.078, 0.102 }, -- oxblood border
    FRAME_DIM  = { 0.125, 0.047, 0.067 },
    MOTION     = { pulse_hz = 0.7 },
  },
}

local function is_color(v)
  return type(v) == "table"
    and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
end

local KEY_ORDER = {
  "ACCENT", "PANEL_BG", "FRAME", "FRAME_DIM", "GLOW", "FLASH_L", "FLASH_D",
  "D_RED", "D_MAROON", "D_SKYBLUE", "D_CYAN", "D_GREEN", "D_YELLOW",
  "D_ORANGE", "D_PURPLE", "D_GOLD", "D_MONEY", "D_DIM", "D_WHITE",
}

local _color_keys = {}
local _defaults = {}
local _overrides = {}

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
  _overrides[persona] = _overrides[persona] or {}
  _overrides[persona][key] = to_hex(c)
  return true
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
  if _overrides[persona] then _overrides[persona][key] = nil end
  return true
end

function Palette.reset_all_colors(persona)
  for _, k in ipairs(_color_keys[persona] or {}) do
    Palette.reset_color(persona, k)
  end
  _overrides[persona] = nil
end

function Palette.apply_overrides(vars)
  local applied = 0
  for k, v in pairs(vars or {}) do
    local pk, key = k:match("^NEURO_COLOR_([^_]+)_(.+)$")
    if pk and key then
      pk = pk:lower()
      local hex = tostring(v):match("^(%x%x%x%x%x%x)$")
      if hex and _defaults[pk] and _defaults[pk][key] then
        local r = tonumber(hex:sub(1, 2), 16) / 255
        local g = tonumber(hex:sub(3, 4), 16) / 255
        local b = tonumber(hex:sub(5, 6), 16) / 255
        if Palette.set_override(pk, key, r, g, b) then applied = applied + 1 end
      end
    end
  end
  return applied
end

function Palette.serialize_overrides()
  local personas = {}
  for pk in pairs(_overrides) do personas[#personas + 1] = pk end
  table.sort(personas)
  local lines = {}
  for _, pk in ipairs(personas) do
    local keys = {}
    for k in pairs(_overrides[pk]) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      lines[#lines + 1] = "NEURO_COLOR_" .. pk:upper() .. "_" .. k .. "=" .. _overrides[pk][k]
    end
  end
  if #lines == 0 then return "" end
  return table.concat(lines, "\n") .. "\n"
end

-- don't parse neuro_tuning.env here: core.tuning is the sole parse owner (dispatches via apply_overrides)

function Palette.persona()
  local p = (G and G.NEURO and G.NEURO.persona) or NEURO_PERSONA
  if Palette.PALETTES[p] then return p end
  return NEURO_PERSONA
end

function Palette.pal()
  return Palette.PALETTES[Palette.persona()] or Palette.PALETTES.neuro
end

return Palette
