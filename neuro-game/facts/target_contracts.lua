local M = {}
local CONTRACTS = {
  c_death = { mode = "ordered_pair", left_role = "copy_from", right_role = "apply_to" },
}

local function key(card)
  return card and card.config and card.config.center and card.config.center.key
end

function M.get(card) return CONTRACTS[key(card)] end
function M.register(center_key, contract)
  if type(center_key) ~= "string" or type(contract) ~= "table" then return false end
  CONTRACTS[center_key] = contract
  return true
end
return M
