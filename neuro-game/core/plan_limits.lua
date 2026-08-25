local DEFAULT_HAND_SELECT_MAX = 5

local M = {
  DEFAULT_HAND_SELECT_MAX = DEFAULT_HAND_SELECT_MAX,
}

local function int(v)
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return math.floor(n)
end

local function highlight_ceiling()
  local g = rawget(_G, "G")
  local cfg = g and g.hand and g.hand.config
  return cfg and int(cfg.highlighted_limit) or nil
end

local function starting_param(name)
  local g = rawget(_G, "G")
  local sp = g and g.GAME and g.GAME.starting_params
  return sp and int(sp[name]) or nil
end

local function bounded(param, floor)
  local limit = starting_param(param)
  local ceiling = highlight_ceiling()
  if not limit and not ceiling then return DEFAULT_HAND_SELECT_MAX end
  local n = limit and math.max(limit, floor) or ceiling
  if ceiling then n = math.min(n, ceiling) end
  return math.max(n, floor)
end

M.play_select_max = function() return bounded("play_limit", 1) end
M.discard_select_max = function() return bounded("discard_limit", 0) end
M.hand_select_max = function()
  return math.max(M.play_select_max(), M.discard_select_max(), 1)
end

return setmetatable(M, {
  __index = function(_, k)
    if k == "HAND_SELECT_MAX" then return M.hand_select_max() end
    return nil
  end,
})
