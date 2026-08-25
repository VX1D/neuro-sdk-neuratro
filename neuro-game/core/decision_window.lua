local State = require("core.state")
local TransitionGuard = require("core.transition_guard")
local DecisionRegistry = require("core.decision_registry")
local StateKinds = require("core.state_kinds")

local M = {}

local INTEREST_GATE_ENTRY = 12   -- two full interest steps: below this there was little to lose
local definition_order = DecisionRegistry.ordered()

local function neuro()
  if not (G and G.NEURO) then return nil end
  if type(G.NEURO._decision_windows) ~= "table" then
    G.NEURO._decision_windows = {}
  end
  return G.NEURO
end

local function window_state(id)
  local n = neuro()
  if not n then return nil end
  local state = n._decision_windows[id]
  if type(state) ~= "table" then
    state = { armed_at = nil, acknowledged = false, reject_count = 0 }
    n._decision_windows[id] = state
  end
  return state
end

local function contains(values, value)
  for i = 1, #(values or {}) do
    if values[i] == value then return true end
  end
  return false
end

local function state_matches(expected, actual)
  if expected == nil then return true end
  if type(expected) == "string" then return expected == actual end
  if type(expected) == "table" then return contains(expected, actual) end
  return false
end

local function arm_key(definition)
  return DecisionRegistry.scope_key(definition)
end

local function trigger_matches(definition, current_state)
  local trigger = definition.trigger or {}
  if not state_matches(trigger.state, current_state) then return false end
  return trigger.condition == nil or trigger.condition()
end

function M.define(definition)
  return DecisionRegistry.register(definition)
end

local function reject_prose(definition, state)
  if type(definition.reject_prose) == "function" then
    return definition.reject_prose(state)
  end
  return definition.reject_prose
end

local function is_latched(definition, state)
  if definition.latch == false then return false end
  return (state and state.acknowledged) and true or false
end

function M.evaluate(action_name, bridge)
  if not neuro() then return false end
  if bridge and bridge.is_transition_cooldown and bridge:is_transition_cooldown() then
    return false
  end
  if TransitionGuard.reject_reason(action_name) then return false end

  local current_state = State.get_state_name()
  local rejection, blocking = false, {}
  for i = 1, #definition_order do
    local definition = definition_order[i]
    if contains(definition.blocks, action_name) and trigger_matches(definition, current_state) then
      local state = window_state(definition.id)
      local current_arm_key = arm_key(definition)
      local is_new_arm = state.armed_at ~= current_arm_key
      if is_new_arm then
        state.armed_at = current_arm_key
        state.acknowledged = false
        state.reject_count = 0
      end
      if not is_latched(definition, state) then
        local is_hard = definition.policy == "hard"
        if is_hard or state.reject_count == 0 then
          blocking[#blocking + 1] = { definition = definition, state = state, hard = is_hard }
          if is_hard then
            rejection = "hard_reject"
          elseif rejection ~= "hard_reject" then
            rejection = "soft_reject"
          end
        end
      end
    end
  end
  if not rejection then return false end
  local hard_present = rejection == "hard_reject"
  local messages = {}
  for i = 1, #blocking do
    local entry = blocking[i]
    if entry.hard or not hard_present then
      entry.state.reject_count = entry.state.reject_count + 1
    end
    messages[#messages + 1] = reject_prose(entry.definition, entry.state)
  end
  return rejection, table.concat(messages, "\n\n")
end

function M.snapshot(action_name)
  if not neuro() then return nil end
  local snapshot = {}
  for i = 1, #definition_order do
    local definition = definition_order[i]
    if definition.latch ~= false and contains(definition.acknowledged_by, action_name) then
      local ok, key = pcall(arm_key, definition)
      if ok then snapshot[#snapshot + 1] = { definition = definition, arm_key = key } end
    end
  end
  return snapshot
end

function M.acknowledge(action_name, snapshot)
  if not neuro() then return false end
  local entries = snapshot
  if type(entries) ~= "table" then entries = M.snapshot(action_name) or {} end
  local acknowledged = false
  for i = 1, #entries do
    local definition = entries[i].definition
    if definition and definition.latch ~= false
        and contains(definition.acknowledged_by, action_name)
        and (not definition.acknowledge_condition
          or definition.acknowledge_condition(action_name)) then
      local state = window_state(definition.id)
      local armed_key = entries[i].arm_key
      if armed_key ~= nil and state.armed_at ~= armed_key then
        state.armed_at = armed_key
        state.reject_count = 0
      end
      if armed_key ~= nil then
        state.acknowledged = true
        acknowledged = true
        if definition.on_acknowledged then definition.on_acknowledged(action_name, state) end
      end
    end
  end
  return acknowledged
end

function M.reset_field(id)
  local n = neuro()
  if not n then return end
  n._decision_windows[id] = nil
end

function M.would_reject(action_name)
  local n = neuro()
  if not n then return false end
  local current_state = State.get_state_name()
  for i = 1, #definition_order do
    local definition = definition_order[i]
    if contains(definition.blocks, action_name) and trigger_matches(definition, current_state) then
      local state = n._decision_windows[definition.id]
      local current_arm_key = arm_key(definition)
      if not state or state.armed_at ~= current_arm_key then return true end
      if not is_latched(definition, state)
          and (definition.policy == "hard" or state.reject_count == 0) then
        return true
      end
    end
  end
  return false
end

local function get_definitions()
  return DecisionRegistry.ordered()
end
local function validate_registry()
  return DecisionRegistry.validate()
end

M.define{
  id = "setup_think",
  policy = "soft",
  scope = {
    kind = "setup_visit",
    key = function()
      return "setup:" .. tostring(G and G.NEURO and G.NEURO.state_enter_serial or 0)
    end,
  },
  trigger = {
    state = "RUN_SETUP",
    condition = function()
      return not G.NEURO.setup_acknowledged
    end,
  },
  blocks = { "start_setup_run" },
  reject_prose = "Run setup is still open: change_selected_back sets the deck (a key from the Decks you can select list), toggle_seeded_run then paste_seed sets a specific seed, change_stake sets the stake. Red Deck is the default selection; each deck changes the run's starting rules. Send start_setup_run again to begin with your current choices.",
  acknowledged_by = {
    "start_setup_run", "change_selected_back", "change_stake",
    "toggle_seeded_run", "paste_seed",
  },
  on_acknowledged = function()
    G.NEURO.setup_acknowledged = true
  end,
}

M.define{
  id = "interest_engine_off",
  policy = "soft",
  scope = {
    kind = "shop_visit",
    key = function()
      local n = (G and G.NEURO) or {}
      return "interest:" .. tostring(n.run_generation or 0) .. ":" .. tostring(n.shop_visit_epoch or 0)
    end,
  },
  trigger = {
    state = "SHOP",
    condition = function()
      if not require("facts.economy_facts").below_first_interest_step() then return false end
      return (tonumber(G and G.NEURO and G.NEURO.shop_entry_dollars) or 0) >= INTEREST_GATE_ENTRY
    end,
  },
  blocks = { "toggle_shop" },
  reject_prose = function()
    local Econ = require("facts.economy_facts")
    local money = math.floor(tonumber(G and G.GAME and G.GAME.dollars or 0) or 0)
    local entry = math.floor(tonumber(G and G.NEURO and G.NEURO.shop_entry_dollars or money) or money)
    return string.format(
      "You are leaving the shop with $%d; you entered it with $%d. The next cash-out pays interest on the money you carry into the blind: +$%d per full $5 held, up to +$%d at $%d held. $%d held pays $0 -- under $5 there is no partial step, and dollars carry to the next shop either way. Send toggle_shop again to leave with $%d.",
      money, entry, Econ.interest_amount(), Econ.max_interest(), Econ.interest_cap(), money, money)
  end,
  acknowledged_by = { "toggle_shop", "set_plan" },
}

M.define{
  id = "order_think",
  policy = "soft",
  trigger = {
    state = "SHOP",
    condition = function()
      if not (G.jokers and G.jokers.cards and #G.jokers.cards >= 2) then return false end
      if not require("facts.card_util").order_matters() then return false end
      return require("core.plan_gate").joker_order_gap() == nil
    end,
  },
  scope = {
    kind = "joker_roster",
    key = function()
      return require("facts.card_util").joker_composition_signature()
    end,
  },
  blocks = { "toggle_shop" },
  reject_prose = function()
    return "Your joker lineup changed. Jokers trigger left to right, so their order changes the score."
      .. " set_joker_order changes the order; toggle_shop again leaves the shop with the current order."
  end,
  acknowledged_by = { "set_joker_order", "toggle_shop" },
}

M.define{
  id = "pack_review",
  policy = "soft",
  scope = {
    kind = "pack_opening",
    key = function()
      return table.concat({
        State.get_state_name(),
        tostring(G and G.NEURO and G.NEURO.state_enter_serial or 0),
      }, "|")
    end,
  },
  trigger = {
    condition = function()
      return StateKinds.is_pack_state(State.get_state_name())
    end,
  },
  blocks = { "use_card", "use_directional_card", "skip_booster" },
  reject_prose = "This is a booster pack: use_card takes an ordinary card, use_directional_card takes a card with ordered target roles, and skip_booster closes the pack without taking one. Your jokers and hand levels are listed above. Review the pack, then choose again; your next pack action may confirm this choice or select a different option.",
  acknowledged_by = { "use_card", "use_directional_card", "skip_booster" },
}
if rawget(_G, "NEURO_TEST") then
  M._test = {
    get_definitions = get_definitions,
    validate_registry = validate_registry,
  }
end
return M
