local M = {}
local CONTRACTS = {
  c_death = { mode = "ordered_pair", left_role = "apply_to", right_role = "copy_from" },
}

function M.get(card) return CONTRACTS[require("facts.card_util").center_key(card)] end
return M
