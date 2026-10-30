_G.NEURO_TEST = true
if not love then love = {} end
love.timer = { getTime = function() return 1000 end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("plan-contract-guard")
local Helpers = require("tests.helpers")
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local PlanRequirements = require("core.plan_requirements")
local PlanTransaction = require("core.plan_transaction")
local SchemaValidate = require("util.schema_validate")

local function minimal(spec)
  if spec.enum then return spec.enum[1] end
  if spec.type == "object" then
    local out = {}
    for _, key in ipairs(spec.required or {}) do out[key] = minimal(spec.properties[key]) end
    return out
  end
  if spec.type == "array" then
    local out = {}
    for i = 1, spec.minItems or 0 do
      out[i] = spec.items.type == "integer" and (spec.items.minimum or 1) + i - 1 or minimal(spec.items)
    end
    return out
  end
  if spec.type == "integer" or spec.type == "number" then return spec.minimum or 1 end
  if spec.type == "boolean" then return false end
  return "x"
end

local function blind_select(on_deck)
  return function()
    G.GAME.blind_on_deck = on_deck
    G.GAME.round_resets.blind_states = on_deck == "Boss"
      and { Small = "Defeated", Big = "Defeated", Boss = "Select" }
      or { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
  end
end

local VARIANTS = {
  BLIND_SELECT = { small = blind_select("Small"), boss = blind_select("Boss") },
  SELECTING_HAND = { plain = function() end, boss = function() G.GAME.blind.boss = true end },
  SHOP = { fresh = function() end, stale = function() G.NEURO.shop_plan_revision_required = true end },
  SMODS_BOOSTER_OPENED = { plain = function() end },
}

for state, variants in pairs(VARIANTS) do
  for variant, setup in pairs(variants) do
    for _, name in ipairs(Actions.get_action_names_for_state(state)) do
      local schema = Registry.get(name).schema
      if schema.properties and schema.properties.plan then
        Helpers.base_G()
        Helpers.in_engine_state(state)
        setup()
        local payload = minimal(schema)
        for field in pairs(PlanRequirements.required(state, name)) do
          payload.plan = payload.plan or {}
          payload.plan[field .. "_plan"] = "x"
        end
        local label = string.format("%s/%s %s", state, variant, name)
        check(label .. ": the generated payload satisfies the registered schema",
          SchemaValidate.validate_value(schema, payload, "parameters"))
        local _, err = PlanTransaction.prepare(name, payload)
        PlanTransaction.release()
        check(label .. ": schema-required plus declared plan fields clear the plan gate",
          err == nil, err and err.message)
      end
    end
  end
end

done()
