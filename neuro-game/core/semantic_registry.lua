local M = {}

local function summary(card, opts)
  return require("facts.card_semantics").summary(card, opts)
end

local function row(edition_in_flags)
  return function(card) return summary(card, { edition_in_flags = edition_in_flags }) end
end

local RENDER = {
  card_effect_summary = summary,
  card_description_full = function(card) return require("facts.card_semantics").full_description(card) end,
  owned_joker_row = row(true),
  shop_card_row = row(false),
  pack_card_row = row(false),
  consumable_row = row(false),
}

function M.render(name, ...)
  local render = RENDER[name]
  assert(render, "unknown semantic projection: " .. tostring(name))
  return render(...)
end

return M
