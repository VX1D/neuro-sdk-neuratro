
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("gate-pressure-agreement")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local DecisionWindow = require("core.decision_window")
local ForceHelpers = require("force.force_helpers")
local TD = require("tests.test_deadlock")

local real_pressure = Enforce.repeat_pressure
local real_would_reject = DecisionWindow.would_reject

local function with(pressure, gated, fn)
  Enforce.repeat_pressure = pressure
  DecisionWindow.would_reject = function(name) return gated[name] == true end
  local ok, a, b = pcall(fn)
  Enforce.repeat_pressure = real_pressure
  DecisionWindow.would_reject = real_would_reject
  if not ok then error(a) end
  return a, b
end

local OFFERED = { "sell_card", "use_card", "buy_from_shop" }
local NO_PRESSURE = function() return nil end

local base = with(NO_PRESSURE, { sell_card = true, use_card = true }, function()
  return ForceHelpers.pending_gate_note(OFFERED)
end)
check("the gate note names every armed action when nothing is under pressure",
  base:find("sell_card", 1, true) ~= nil and base:find("use_card", 1, true) ~= nil
    and base:find("an identical repeat carries it out", 1, true) ~= nil, base)
check("the gate note leaves an unarmed action out", base:find("buy_from_shop", 1, true) == nil, base)

local gate, press = with(function() return "sell_card", 4 end, { sell_card = true, use_card = true },
  function()
    return ForceHelpers.pending_gate_note(OFFERED), ForceHelpers.repeat_pressure_note()
  end)
check("the pressure note still names the action at the cap",
  press:find("sell_card", 1, true) ~= nil
    and press:find("another identical send is refused", 1, true) ~= nil, press)
check("the gate note drops the action the cap will refuse",
  gate:find("sell_card", 1, true) == nil, gate)
check("the gate note keeps the other armed action", gate:find("use_card", 1, true) ~= nil, gate)

local solo_gate, solo_press = with(function() return "sell_card", 4 end, { sell_card = true },
  function()
    return ForceHelpers.pending_gate_note(OFFERED), ForceHelpers.repeat_pressure_note()
  end)
check("with nothing else armed the gate note falls silent", solo_gate == "", solo_gate)
check("and the pressure note still speaks", solo_press ~= "", solo_press)

local function contradiction(query)
  for _, name in ipairs(Actions.get_action_names_for_state("SHOP") or OFFERED) do
    local in_gate = query:find(name .. " returns a confirmation", 1, true)
      or query:find(name .. " and ", 1, true)
    local in_press = query:find("You have sent " .. name .. " with the same parameters", 1, true)
    if in_gate and in_press then return name end
  end
  return nil
end

for _, case in ipairs({
  { gated = { sell_card = true }, pressed = "sell_card" },
  { gated = { sell_card = true, use_card = true }, pressed = "use_card" },
  { gated = { buy_from_shop = true }, pressed = "buy_from_shop" },
}) do
  local query = with(function() return case.pressed, 5 end, case.gated, function()
    return ForceHelpers.pending_gate_note(OFFERED) .. ForceHelpers.repeat_pressure_note()
  end)
  check("no action is both promised a carrying repeat and told its repeat is refused ("
    .. case.pressed .. ")", contradiction(query) == nil, query)
end

local WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster",
  "shop", "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU" }

local STATE_ID, next_id = {}, 0
local function enter_state(name)
  if not STATE_ID[name] then next_id = next_id + 1; STATE_ID[name] = next_id end
  G.STATES = G.STATES or {}
  G.STATES[name] = STATE_ID[name]
  G.STATE = STATE_ID[name]
end

local function force_query(state_name, pressure, gated)
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro",
    reserved_dollars = 0, shop_reroll_count = 0, _decision_windows = {}, state_enter_serial = 1 }
  local target
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state_name and not sc.no_force then target = sc break end
  end
  if not target then return nil end
  TD.apply_mock(target.mock())
  enter_state(state_name)
  return with(pressure, gated, function()
    local ok, force = pcall(Dispatcher.get_force_for_state, state_name)
    if not ok or type(force) ~= "table" then return nil end
    return tostring(force.query or "")
  end)
end

for _, state_name in ipairs({ "SHOP", "TAROT_PACK" }) do
  local names = Actions.get_action_names_for_state(state_name) or {}
  local pressed = names[1]
  if pressed then
    local gated = {}
    for _, n in ipairs(names) do gated[n] = true end
    local query = force_query(state_name, function() return pressed, 9 end, gated)
    check(state_name .. ": a force query was built with both notes primed",
      type(query) == "string" and query ~= "", tostring(query))
    if type(query) == "string" then
      check(state_name .. ": the built query never contradicts itself about one action",
        contradiction(query) == nil, query)
      check(state_name .. ": the pressure note survives into the built query",
        query:find("with the same parameters", 1, true) ~= nil, query)
    end
  end
end

done()
