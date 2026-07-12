local gfx = {}

local floor = math.floor

function gfx.round(x) return floor(x + 0.5) end

function gfx.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function gfx.clamp01(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

function gfx.set_col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a)
end

function gfx.shadow_text(txt, x, y, col, a, sh_a, off)
  off = off or 1
  love.graphics.setColor(0, 0, 0, sh_a)
  love.graphics.print(txt, x + off, y + off)
  love.graphics.setColor(col[1], col[2], col[3], a)
  love.graphics.print(txt, x, y)
end

return gfx
