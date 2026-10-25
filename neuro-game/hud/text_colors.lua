local M = {}

local CACHE_MAX = 256

local function classify_rest(word)
  if word:match("^%$") then return "D_MONEY"
  elseif word:match("^[Xx]%d") then return "D_MAROON"
  elseif word:match("^%+%d") then return "D_GREEN"
  else return "D_WHITE" end
end

local function classify_uncached(word)
  local wu = word:upper()
  if wu:find("MULT") then return "D_RED"
  elseif wu:find("CHIP") then return "D_CYAN"
  else return classify_rest(word) end
end

local function classify_whole_uncached(word)
  local core = word:upper():match("^%p*(.-)%p*$")
  if core == "MULT" then return "D_RED"
  elseif core == "CHIP" or core == "CHIPS" then return "D_CYAN"
  else return classify_rest(word) end
end

local function new_ring(classify)
  local map, keys, slot = {}, {}, 1
  return {
    lookup = function(word)
      local result = map[word]
      if result ~= nil then return result end
      result = classify(word)
      local old = keys[slot]
      if old ~= nil then map[old] = nil end
      keys[slot], map[word] = word, result
      slot = slot % CACHE_MAX + 1
      return result
    end,
  }
end

local sub_ring, word_ring

function M.invalidate()
  sub_ring, word_ring = new_ring(classify_uncached), new_ring(classify_whole_uncached)
end
M.invalidate()

function M.classify(word)
  return sub_ring.lookup(word)
end

function M.classify_word(word)
  return word_ring.lookup(word)
end

return M
