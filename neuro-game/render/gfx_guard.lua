local M = {}

function M.drain()
  pcall(love.graphics.setScissor)
  for _ = 1, 16 do
    if not pcall(love.graphics.pop) then break end
  end
  pcall(love.graphics.origin)
  pcall(love.graphics.setColor, 1, 1, 1, 1)
  pcall(love.graphics.setLineWidth, 1)
  pcall(love.graphics.setBlendMode, "alpha")
  pcall(love.graphics.setShader)
end

return M
