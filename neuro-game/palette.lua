local Palette = {}

local NEURO_PERSONA = "neuro"
do
  local env = os.getenv("NEURO_PERSONA")
  if env then
    env = env:lower():gsub("%s+", "")
    if env == "evil" or env == "evil_neuro" or env == "evilneuro" then
      NEURO_PERSONA = "evil"
    end
  end
end

Palette.PALETTES = {
  hiyori = {
    PRIMARY    = { 0.20, 0.20, 0.22 },
    DEEP       = { 0.10, 0.10, 0.12 },
    GLOW       = { 0.40, 0.40, 0.42 },
    BG         = { 0.05, 0.05, 0.06 },
    ACCENT     = { 0.30, 0.30, 0.32, 1 },
    NAME       = "H\xCC\xB6I\xCC\xB6Y\xCC\xB6O\xCC\xB6R\xCC\xB6I\xCC\xB6",
    NAME_SHORT = "???",
    D_MONEY    = { 0.50, 0.50, 0.45 },
    D_GOLD     = { 0.45, 0.45, 0.40 },
    D_CYAN     = { 0.35, 0.38, 0.40 },
    D_GREEN    = { 0.35, 0.40, 0.35 },
    D_RED      = { 0.50, 0.30, 0.30 },
    D_WHITE    = { 0.60, 0.60, 0.60 },
    D_DIM      = { 0.30, 0.30, 0.30 },
    D_ORANGE   = { 0.45, 0.38, 0.25 },
  },
  neuro = {
    PRIMARY    = { 0.120, 0.500, 0.480 },
    DEEP       = { 0.040, 0.090, 0.085 },
    GLOW       = { 1.000, 0.420, 0.540 },
    BG         = { 0.045, 0.095, 0.090 },
    ACCENT     = { 0.878, 0.271, 0.341, 1 },
    NAME       = "NEURO-SAMA",
    NAME_SHORT = "NEURO",
    D_MONEY    = { 0.949, 0.859, 0.682 },
    D_GOLD     = { 0.949, 0.859, 0.682 },
    D_CYAN     = { 0.400, 0.929, 0.894 },
    D_GREEN    = { 0.565, 0.800, 0.592 },
    D_RED      = { 0.878, 0.271, 0.341 },
    D_WHITE    = { 0.965, 0.975, 0.992 },
    D_DIM      = { 0.694, 0.745, 0.800 },
    D_ORANGE   = { 0.945, 0.643, 0.349 },
  },
  evil = {
    PRIMARY    = { 1.0, 0.15, 0.22 },
    DEEP       = { 0.75, 0.08, 0.14 },
    GLOW       = { 1.0, 0.30, 0.35 },
    BG         = { 0.10, 0.03, 0.06 },
    ACCENT     = { 1.0, 0.15, 0.22, 1 },
    NAME       = "EVIL NEURO",
    NAME_SHORT = "EVIL",
    D_MONEY    = { 0.92, 0.68, 0.25 },
    D_GOLD     = { 0.88, 0.62, 0.20 },
    D_CYAN     = { 0.55, 0.70, 0.85 },
    D_GREEN    = { 0.45, 0.85, 0.45 },
    D_RED      = { 1.00, 0.30, 0.28 },
    D_WHITE    = { 0.95, 0.90, 0.88 },
    D_DIM      = { 0.55, 0.48, 0.48 },
    D_ORANGE   = { 1.00, 0.58, 0.20 },
  },
}

function Palette.pal()
  local p = (G and G.NEURO and G.NEURO.persona) or NEURO_PERSONA
  return Palette.PALETTES[p] or Palette.PALETTES.neuro
end

function Palette.PINK()      return Palette.pal().PRIMARY end
function Palette.PINK_GLOW() return Palette.pal().GLOW end
function Palette.DARK_BG()   return Palette.pal().BG end

return Palette
