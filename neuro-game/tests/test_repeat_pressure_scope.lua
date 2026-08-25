
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("repeat-pressure-scope")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local ForceHelpers = require("force.force_helpers")
local TD = require("tests.test_deadlock")

local WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster",
  "shop", "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU" }

local STATE_ID, next_id = {}, 0
local function enter_state(name)
  if not STATE_ID[name] then next_id = next_id + 1; STATE_ID[name] = next_id end
  G.STATES = G.STATES or {}
  G.STATES[name] = STATE_ID[name]
  G.STATE = STATE_ID[name]
end

local function scenario_for(state_name)
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state_name and not sc.no_force then return sc end
  end
  return nil
end

local real_pressure = Enforce.repeat_pressure

local function query_for(state_name, pressure)
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro",
    reserved_dollars = 0, shop_reroll_count = 0, _decision_windows = {}, state_enter_serial = 1 }
  local sc = scenario_for(state_name)
  if not sc then return nil end
  TD.apply_mock(sc.mock())
  enter_state(state_name)
  Enforce.repeat_pressure = pressure
  local ok, force = pcall(Dispatcher.get_force_for_state, state_name)
  Enforce.repeat_pressure = real_pressure
  if not ok or type(force) ~= "table" then return nil end
  return tostring(force.query or "")
end

local CASES = {
  { state = "BLIND_SELECT", action = "select_blind", count = 6 },
  { state = "TAROT_PACK", action = "skip_booster", count = 3 },
  { state = "BUFFOON_PACK", action = "use_card", count = 3 },
  { state = "SHOP", action = "buy_from_shop", count = 20 },
  { state = "SELECTING_HAND", action = "play_hand", count = 30 },
}

for _, case in ipairs(CASES) do
  local under = function() return case.action, case.count end
  local expected
  do
    Enforce.repeat_pressure = under
    expected = ForceHelpers.repeat_pressure_note()
    Enforce.repeat_pressure = real_pressure
  end
  check(case.state .. ": the pressure view renders a note at all",
    type(expected) == "string" and expected ~= "", tostring(expected))

  local pressed = query_for(case.state, under)
  check(case.state .. ": a force is built for the scenario", type(pressed) == "string" and pressed ~= "",
    tostring(pressed))
  check(case.state .. ": the force carries the pressure note verbatim",
    type(pressed) == "string" and pressed:find(expected, 1, true) ~= nil, tostring(pressed))

  local quiet = query_for(case.state, function() return nil end)
  check(case.state .. ": and says nothing about repeats when there is no pressure",
    type(quiet) == "string" and quiet:find("with the same parameters", 1, true) == nil, tostring(quiet))
end

done()
