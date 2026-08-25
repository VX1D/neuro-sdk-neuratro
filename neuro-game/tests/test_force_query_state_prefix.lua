_G.NEURO_TEST = true
love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {} }

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TD = require("tests.test_deadlock")
local check, done = require("tests.helpers").harness("force-query-state-prefix")
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local total_force_scenarios = 103
local checked, prefixed = 0, 0
local bad, threw = {}, {}
for _, scenario in ipairs(TD.SCENARIOS) do
  local snapshot
  local ok, err = pcall(function()
    local save_keys = { "GAME", "hand", "jokers", "consumeables",
      "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards",
      "booster_pack", "shop", "blind_select_opts", "blind_select",
      "OVERLAY_MENU", "challenge_tab", "CHALLENGES", "P_CENTER_POOLS",
      "P_TAGS", "P_BLINDS", "SETTINGS" }
    snapshot = {}
    for _, key in ipairs(save_keys) do snapshot[key] = G[key] end
    snapshot._persona = G.NEURO.persona

    TD.apply_mock(scenario.mock())
    local force = Dispatcher.get_force_for_state(scenario.state)
    if type(force) == "table" and type(force.query) == "string" then
      checked = checked + 1
      if force.query:sub(1, 7) == "State: " then
        prefixed = prefixed + 1
      else
        bad[#bad + 1] = string.format("[%s] %s -> %q", scenario.state,
          scenario.desc, force.query:sub(1, 40))
      end
    end

    for _, key in ipairs(save_keys) do G[key] = snapshot[key] end
    G.NEURO.persona = snapshot._persona
  end)
  if not ok then
    threw[#threw + 1] = string.format("[%s] %s: %s", scenario.state,
      scenario.desc, tostring(err))
    if snapshot then
      for key, value in pairs(snapshot) do
        if key ~= "_persona" then G[key] = value end
      end
      G.NEURO.persona = snapshot._persona
    end
  end
end

check("force-builder scenario sweep completes without throwing",
  #threw == 0, table.concat(threw, " | "))
check("force-builder scenario sweep covers the expected query corpus",
  checked >= total_force_scenarios, "checked=" .. checked .. " of " .. #TD.SCENARIOS)
check("every force query begins with its State segment",
  prefixed == checked, table.concat(bad, " | "))

local shop_scenario
for _, scenario in ipairs(TD.SCENARIOS) do
  if scenario.state == "SHOP" and scenario.desc:find("Normal: affordable joker", 1, true) then
    shop_scenario = scenario
  end
end
assert(shop_scenario, "SHOP fixture scenario not found in test_deadlock")

TD.apply_mock(shop_scenario.mock())
G.CONTROLLER = { locks = { shop_reroll = true } }
local shop_force = Dispatcher.get_force_for_state("SHOP")
G.CONTROLLER = nil

check("a guard-pruned SHOP force still starts with its State segment",
  type(shop_force) == "table" and type(shop_force.query) == "string"
    and shop_force.query:sub(1, 12) == "State: SHOP.", shop_force and shop_force.query)
check("the guard-prune note follows the State segment",
  type(shop_force) == "table" and type(shop_force.query) == "string"
    and shop_force.query:find("^State: SHOP%. NOTE: only these actions") ~= nil,
  shop_force and shop_force.query)

done()
