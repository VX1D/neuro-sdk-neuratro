local M = {}

function M.compute(hands, snap)
  local cur, ups = {}, {}
  if type(hands) == "table" then
    for name, hd in pairs(hands) do
      if type(hd) == "table" then
        local lv = tonumber(hd.level) or 1
        cur[name] = lv
        if snap and snap[name] and lv > snap[name] and hd.visible ~= false then
          ups[#ups + 1] = string.format("%s L%d->L%d", tostring(name), snap[name], lv)
        end
      end
    end
  end
  if snap and #ups > 0 then
    table.sort(ups)
    return "Hand level-up: " .. table.concat(ups, ", ") .. ".", cur
  end
  return nil, cur
end

return M
