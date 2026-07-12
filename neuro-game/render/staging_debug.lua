local H = require("render.hud_shared")
local Palette = require("render.palette")
local Staging = require("core.staging")
local DebugStats = require("render.debug_stats")
local set_col, shadow_text = H.set_col, H.shadow_text

local M = {}

function M.draw()
  if not (DebugStats.visible and DebugStats.visible()) then return end
  if not (love and love.graphics) then return end
  local lines = Staging.get_debug_lines()
  if type(lines) ~= "table" or #lines == 0 then return end
  local pal = Palette.pal()
  local font = love.graphics.getFont()
  if not font then return end
  local wc = pal.D_WHITE or { 1, 1, 1, 1 }
  local bgc = pal.PANEL_BG or pal.BG
  local frc = pal.FRAME or pal.PRIMARY
  local lh = font:getHeight() + 2
  local pad = 8
  local w = 320
  local h = pad * 2 + #lines * lh
  local x = 8
  local y = love.graphics.getHeight() - h - 8
  set_col(bgc, 0.90)
  love.graphics.rectangle("fill", x, y, w, h)
  set_col(frc, 0.90)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, w, h)
  local ty = y + pad
  for i = 1, #lines do
    local s = tostring(lines[i])
    shadow_text(s, x + pad, ty, wc, wc[4] or 1, 0.35)
    ty = ty + lh
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return M
