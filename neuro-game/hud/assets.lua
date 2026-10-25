local Assets = {}

local S = require("hud.state")
local Utils = require("util.utils")

local neuro_log = Utils.neuro_log

function Assets.get_neuro_logo()
  if S.neuro_logo or S.neuro_logo_attempts >= 60 then
    return S.neuro_logo
  end
  S.neuro_logo_attempts = S.neuro_logo_attempts + 1

  local mod = SMODS and SMODS.Mods and SMODS.Mods.Neurocards
  if not (mod and mod.path and NFS) then return nil end
  local logo_file = mod.path .. "assets/1x/neuratro.png"
  local ok, img = pcall(function()
    return love.graphics.newImage(love.image.newImageData(NFS.newFileData(logo_file)))
  end)
  if ok and img then
    S.neuro_logo = img
    neuro_log("Loaded Neuratro logo from:", logo_file)
  end
  return S.neuro_logo
end

local PANEL_FONT_PATH = "resources/fonts/m6x11plus.ttf"
local PANEL_FONT_PX, PANEL_FONT_SMALL_PX = 14, 12

Assets.ROLE_PX = { display = 22, title = 18, body = 14, caption = 12, micro = 10 }
Assets.ROLE_MIN = { display = 16, title = 14, body = 12, caption = 10, micro = 8 }

function Assets.font_px(px)
  return Utils.font_at(PANEL_FONT_PATH, px, 1)
end

function Assets.role_font(role, scale)
  local px = math.floor((Assets.ROLE_PX[role] or PANEL_FONT_PX) * (scale or 1) + 0.5)
  local floor_px = Assets.ROLE_MIN[role]
  if floor_px and px < floor_px then px = floor_px end
  return Assets.font_px(px)
end

function Assets.hud_scale(sh)
  return math.max(0.5, math.floor((sh / 1080) / 0.05 + 0.5) * 0.05)
end

function Assets.get_panel_fonts(scale)
  if not S.panel_font then
    S.panel_font_small = Assets.font_px(PANEL_FONT_SMALL_PX)
    S.panel_font = Assets.font_px(PANEL_FONT_PX)
  end
  if not scale or scale == 1 then
    return S.panel_font, S.panel_font_small
  end
  local f_small = Assets.font_px(math.max(Assets.ROLE_MIN.caption, math.floor(PANEL_FONT_SMALL_PX * scale + 0.5)))
  return Assets.font_px(math.max(Assets.ROLE_MIN.body, math.floor(PANEL_FONT_PX * scale + 0.5))), f_small
end

Assets.font_cache_id = require("render.gfx").font_id

return Assets
