local M = {}

local function collect(hands, snap)
  local cur, ups = {}, {}
  if type(hands) == "table" then
    for name, hd in pairs(hands) do
      if type(hd) == "table" then
        local lv = tonumber(hd.level) or 1
        cur[name] = lv
        if snap and snap[name] and lv > snap[name] and hd.visible ~= false then
          ups[#ups + 1] = { name = tostring(name), from = snap[name], to = lv }
        end
      end
    end
  end
  return cur, ups
end

local function phrase(u)
  return string.format("%s leveled up from %d to %d", u.name, u.from, u.to)
end

function M.snapshot(hands)
  local cur = collect(hands, nil)
  return cur
end

function M.brief(hands, snap)
  if not snap then return nil end
  local _, ups = collect(hands, snap)
  if #ups == 0 then return nil end
  if #ups == 1 then return phrase(ups[1]) end
  return string.format("%d hands leveled up", #ups)
end

return M
