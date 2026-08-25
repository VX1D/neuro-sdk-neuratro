local M = {}

local EXPECTED = {
  "card_effect_summary",
  "card_description_full",
  "joker_aggregate",
  "owned_has_xmult",
  "owned_joker_row",
  "shop_card_row",
  "pack_card_row",
  "consumable_row",
  "readable_joker",
  "scoring_advice",
}

local definitions = {}

function M.register(name, definition)
  assert(type(name) == "string" and name ~= "", "semantic projection name required")
  assert(type(definition) == "table", "semantic projection definition required")
  assert(type(definition.render) == "function", "semantic projection renderer required")
  assert(type(definition.source) == "string" and definition.source ~= "", "semantic source required")
  assert(definition.conditional_policy == "preserve" or definition.conditional_policy == "structured",
    "semantic projection must preserve or structure conditions")
  assert(not definitions[name], "semantic projection already registered: " .. name)
  definition.name = name
  definitions[name] = definition
  return definition
end

function M.get(name) return definitions[name] end

function M.render(name, ...)
  local definition = definitions[name]
  assert(definition, "unknown semantic projection: " .. tostring(name))
  return definition.render(...)
end

function M.all()
  local out = {}
  for _, name in ipairs(EXPECTED) do
    if definitions[name] then out[#out + 1] = definitions[name] end
  end
  return out
end

function M.validate()
  local errors = {}
  for _, name in ipairs(EXPECTED) do
    local definition = definitions[name]
    if not definition then
      errors[#errors + 1] = name .. ": not registered"
    elseif not definition.test_contract then
      errors[#errors + 1] = name .. ": no semantic test contract"
    end
  end
  for name in pairs(definitions) do
    local known = false
    for _, expected in ipairs(EXPECTED) do if expected == name then known = true break end end
    if not known then errors[#errors + 1] = name .. ": untracked projection" end
  end
  return #errors == 0, errors
end

local function summary(card, opts)
  return require("facts.card_semantics").summary(card, opts)
end

M.register("card_effect_summary", {
  source = "semantic card description/effect model",
  conditional_policy = "preserve",
  test_contract = "trigger,target,condition,value,unit",
  render = summary,
})
M.register("card_description_full", {
  source = "localized card description",
  conditional_policy = "preserve",
  test_contract = "localized full rule",
  render = function(card) return require("facts.card_semantics").full_description(card) end,
})
M.register("joker_aggregate", {
  source = "structured effect model",
  conditional_policy = "structured",
  test_contract = "guaranteed separated from conditional",
  render = function() return require("util.scoring").joker_summary() end,
})
M.register("owned_has_xmult", {
  source = "structured effect model",
  conditional_policy = "structured",
  test_contract = "only guaranteed xMult satisfies capability",
  render = function() return require("util.scoring").owned_has_xmult() end,
})
local EDITION_IN_FLAGS = { owned_joker_row = true, readable_joker = true }
for _, name in ipairs({ "owned_joker_row", "shop_card_row", "pack_card_row", "consumable_row", "readable_joker" }) do
  local edition_in_flags = EDITION_IN_FLAGS[name] or false
  M.register(name, {
    source = "card_effect_summary",
    conditional_policy = "preserve",
    test_contract = "same card rule across projections",
    render = function(card) return summary(card, { edition_in_flags = edition_in_flags }) end,
  })
end
M.register("scoring_advice", {
  source = "structured effect model",
  conditional_policy = "structured",
  test_contract = "advice distinguishes guaranteed and conditional effects",
  render = function() return require("util.scoring").joker_summary() end,
})

return M
