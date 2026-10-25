local M = {}

function M.count(list, pred)
  local n = 0
  if type(list) ~= "table" then return 0 end
  for _, v in ipairs(list) do
    if pred(v) then n = n + 1 end
  end
  return n
end

function M.plural(n, word)
  return tostring(n) .. " " .. word .. (tostring(n) == "1" and "" or "s")
end

return M
