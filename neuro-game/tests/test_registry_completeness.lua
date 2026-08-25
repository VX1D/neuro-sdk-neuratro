_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("registry completeness")

_G.G = {
  STATE = 1, STATES = { SHOP = 1 }, GAME = { dollars = 0, current_round = {}, round_resets = {} },
  NEURO = { run_generation = 1, _decision_windows = {} }, FUNCS = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
}

local Actions = require("core.actions")
require("core.dispatcher")
local ActionRegistry = require("core.action_registry")
local DecisionRegistry = require("core.decision_registry")
require("core.decision_window")
local SemanticRegistry = require("core.semantic_registry")
local LifecycleRegistry = require("core.neuro_lifecycle").registry

check("registry completeness: action registry populated", #ActionRegistry.names() >= 26,
  tostring(#ActionRegistry.names()))
check("registry completeness: decision registry populated", #DecisionRegistry.ordered() >= 4,
  tostring(#DecisionRegistry.ordered()))
do
  local d = LifecycleRegistry.describe()
  check("registry completeness: lifecycle run scope populated",
    d.run and #(d.run.fields or {}) >= 85 and #(d.run.hooks or {}) >= 9,
    tostring(d.run and #(d.run.fields or {})) .. " fields / " .. tostring(d.run and #(d.run.hooks or {})) .. " hooks")
end

local action_ok, action_errors = ActionRegistry.validate({ require_preflights = true })
check("registry completeness: action contracts are complete",
  action_ok, table.concat(action_errors or {}, "; "))
local missing_actions = {}
for _, state in ipairs(Actions.get_known_states()) do
  for _, name in ipairs(Actions.get_action_names_for_state(state)) do
    local contract = ActionRegistry.get(name)
    if not contract then
      missing_actions[#missing_actions + 1] = state .. ":" .. name
    elseif not contract.states[state] then
      missing_actions[#missing_actions + 1] = state .. ":" .. name .. ":scope"
    end
  end
end
check("registry completeness: every state action maps to its canonical contract",
  #missing_actions == 0, table.concat(missing_actions, ", "))

local unreachable = {}
for _, contract in ipairs(ActionRegistry.all()) do
  if not next(contract.states or {}) then unreachable[#unreachable + 1] = contract.name end
end
check("registry completeness: no action contract is unreachable",
  #unreachable == 0, table.concat(unreachable, ", "))

local decision_ok, decision_errors = DecisionRegistry.validate()
check("registry completeness: every decision window has a live dependency scope",
  decision_ok, table.concat(decision_errors or {}, "; "))
local semantic_ok, semantic_errors = SemanticRegistry.validate()
check("registry completeness: every semantic output has a projection contract",
  semantic_ok, table.concat(semantic_errors or {}, "; "))
local lifecycle_ok, lifecycle_errors = LifecycleRegistry.validate()
check("registry completeness: lifecycle fields have one owner scope",
  lifecycle_ok, table.concat(lifecycle_errors or {}, "; "))

local described = LifecycleRegistry.describe()
local reset_hooks = {}
for _, name in ipairs(described.run.hooks or {}) do reset_hooks[name] = true end
local missing_hooks = {}
for _, name in ipairs({ "dispatcher", "enforce", "orchestrator", "staging", "transition_guard" }) do
  if not reset_hooks[name] then missing_hooks[#missing_hooks + 1] = name end
end
check("registry completeness: all run-owned runtime modules reset centrally",
  #missing_hooks == 0, table.concat(missing_hooks, ", "))

check("registry completeness: session scope is removed from describe",
  LifecycleRegistry.describe().session == nil)
check("registry completeness: reset(session) rejects unknown scope",
  select(1, pcall(LifecycleRegistry.reset, "session", {})) == false
    and tostring(select(2, pcall(LifecycleRegistry.reset, "session", {}))):find("unknown lifecycle scope: session", 1, true) ~= nil)

done()
