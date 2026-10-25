local M = {}

local function phrase(u)
  return string.format("%s leveled up from %d to %d", u.name, u.from, u.to)
end

function M.snapshot(hands)
  local cur = {}
  for name, hd in pairs(type(hands) == "table" and hands or {}) do
    if type(hd) == "table" then cur[name] = tonumber(hd.level) or 1 end
  end
  return cur
end

function M.brief(hands, snap)
  if not snap then return nil end
  local ups = {}
  for name, hd in pairs(type(hands) == "table" and hands or {}) do
    local lv = type(hd) == "table" and (tonumber(hd.level) or 1)
    if lv and snap[name] and lv > snap[name] and hd.visible ~= false then
      ups[#ups + 1] = { name = tostring(name), from = snap[name], to = lv }
    end
  end
  if #ups == 0 then return nil end
  if #ups == 1 then return phrase(ups[1]) end
  return string.format("%d hands leveled up", #ups)
end

return M
