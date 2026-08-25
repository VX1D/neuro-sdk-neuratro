local M = {}

local CACHE_MAX = 256
local cache, keys = {}, {}
local next_slot, cache_n = 1, 0

local function classify_uncached(word)
  local wu = word:upper()
  if wu:find("MULT") then return "D_RED"
  elseif wu:find("CHIP") then return "D_CYAN"
  elseif word:match("^%$") then return "D_MONEY"
  elseif word:match("^[Xx]%d") then return "D_MAROON"
  elseif word:match("^%+%d") then return "D_GREEN"
  else return "D_WHITE" end
end

function M.classify(word)
  local result = cache[word]
  if result ~= nil then return result end
  result = classify_uncached(word)
  local old = keys[next_slot]
  if old ~= nil then
    cache[old] = nil
  else
    cache_n = cache_n + 1
  end
  keys[next_slot], cache[word] = word, result
  next_slot = next_slot % CACHE_MAX + 1
  return result
end

function M.invalidate()
  cache, keys = {}, {}
  next_slot, cache_n = 1, 0
end

if rawget(_G, "NEURO_TEST") then
  M._test = {
    cache_size = function() return cache_n end,
    cache_max = CACHE_MAX,
  }
end

return M
