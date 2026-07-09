local Assets = {}

local S = require("hud.state")
local Utils = require "util.utils"

local neuro_log = Utils.neuro_log

function Assets.get_neuro_logo()
  -- mod assets miss on early frames; bounded retry, don't negative-cache
  if S.neuro_logo or S.neuro_logo_attempts >= 60 then
    return S.neuro_logo
  end
  S.neuro_logo_attempts = S.neuro_logo_attempts + 1

  local neuratro_path = nil
  if SMODS and SMODS.Mods then
    for _, mod in pairs(SMODS.Mods) do
      local id = mod and (mod.id or mod.mod_id)
      if id == "Neurocards" then
        neuratro_path = mod.path
        break
      end
    end
  end
  if not neuratro_path and SMODS and SMODS.findModByID then
    local mod = SMODS.findModByID("Neurocards")
    if mod and mod.path then
      neuratro_path = mod.path
    end
  end

  if neuratro_path then
    local logo_file = neuratro_path .. "assets/1x/neuratro.png"
    local ok, img = pcall(love.graphics.newImage, logo_file)
    if ok and img then
      S.neuro_logo = img
      neuro_log("Loaded Neuratro logo from:", logo_file)
    end
  end
  return S.neuro_logo
end

local PANEL_FONT_PATH = "resources/fonts/m6x11plus.ttf"
local PANEL_FONT_PX, PANEL_FONT_SMALL_PX = 14, 12

function Assets.get_panel_fonts(scale)
  if not S.panel_font then
    local f_small, f_big = Utils.load_font_pair(PANEL_FONT_PATH, PANEL_FONT_SMALL_PX, PANEL_FONT_PX)
    S.panel_font = f_big or love.graphics.getFont()
    S.panel_font_small = f_small or S.panel_font
  end
  if not scale or scale == 1 then
    return S.panel_font, S.panel_font_small
  end
  local f_small, f_big = Utils.load_font_pair(PANEL_FONT_PATH, PANEL_FONT_SMALL_PX, PANEL_FONT_PX, scale)
  return f_big or S.panel_font, f_small or S.panel_font_small
end

local _font_ids = setmetatable({}, { __mode = "k" })
local _font_id_n = 0
function Assets.font_cache_id(f)
  local id = _font_ids[f]
  if not id then
    _font_id_n = _font_id_n + 1
    id = "f" .. _font_id_n .. ":"
    _font_ids[f] = id
  end
  return id
end

return Assets
