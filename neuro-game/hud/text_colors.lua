local M = {}

function M.classify(word)
  local wu = word:upper()
  if wu:find("MULT") then return "D_RED"
  elseif wu:find("CHIP") then return "D_CYAN"
  elseif word:match("^%$") then return "D_MONEY"
  elseif word:match("^[Xx]%d") then return "D_MAROON"
  elseif word:match("^%+%d") then return "D_GREEN"
  else return "D_ORANGE" end
end

return M
