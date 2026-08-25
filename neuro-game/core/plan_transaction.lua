local M = {}

local ActionResult = require("core.action_result")
local Metrics = require("util.metrics")
local PlanGate = require("core.plan_gate")
local PlanHandlers = require("handlers.plan_handlers")
local ActionReceipt = require("core.action_receipt")
local Utils = require("util.utils")

local COVERED = {
  buy_from_shop = true,
  sell_card = true,
  use_card = true,
  use_directional_card = true,
  reroll_shop = true,
  toggle_shop = true,
  select_blind = true,
  play_hand = true,
  discard_hand = true,
}

local SHOP_MUTATIONS = {
  buy_from_shop = true,
  sell_card = true,
  use_card = true,
  use_directional_card = true,
  reroll_shop = true,
}

local PLAN_KEYS = {
  hand = "hand_plan", build = "build_plan", money = "money_plan", boss = "boss_plan",
  focus = "hand_focus",
}

local pending_message

local _stale_drops = 0
local _stale_log_next = 1

local function neuro()
  return G and G.NEURO
end

function M.take_message()
  local message = pending_message
  pending_message = nil
  return message
end

local function field_scopes()
  return {
    hand = PlanGate.current_blind_scope(),
    build = PlanGate.current_build_scope(),
    money = PlanGate.current_economy_scope(),
    boss = PlanGate.current_boss_scope(),
    focus = PlanGate.current_blind_scope(),
  }
end

local function current_plan_value(field)
  local n = neuro()
  local plan = n and n.plan
  if field == "hand" and PlanGate.hand_plan_is_current(plan) then return plan.hand, plan.hand_scope end
  if field == "build" and PlanGate.build_plan_is_current(plan) then return plan.build, plan.build_scope end
  if field == "money" and PlanGate.money_plan_is_current(plan) then return plan.money, plan.money_scope end
  if field == "boss" and PlanGate.boss_plan_is_current(plan) then return plan.boss, plan.boss_scope end
  if field == "focus" and PlanGate.hand_focus_is_current(plan) then
    return plan.hand_focus, plan.hand_focus_scope
  end
  return nil
end

local function has_fields(fields)
  return type(fields) == "table" and next(fields) ~= nil
end

local function blank_text(value)
  return type(value) == "string" and Utils.normalize_ws(value) == ""
end

local function reject(message)
  Metrics.incr("plan_tx_rejected")
  return nil, ActionResult.error("PRECONDITION_FAILED", message)
end

function M.release()
  local n = neuro()
  if n then n.held_plan_write = nil end
  pending_message = nil
end

function M.release_fields(written)
  local n = neuro()
  local held = n and n.held_plan_write
  if not held or type(written) ~= "table" then return false end
  local left = false
  for _, key in pairs(PLAN_KEYS) do
    if written[key] ~= nil then
      held.values[key] = nil
    elseif held.values[key] ~= nil then
      left = true
    end
  end
  if not left then n.held_plan_write = nil end
  return true
end

function M.hold(tx)
  local n = neuro()
  if not n or type(tx) ~= "table" or not has_fields(tx.plan_values) then return false end
  n.held_plan_write = {
    run_generation = n.run_generation,
    values = tx.plan_values,
    scopes = tx.plan_scopes or field_scopes(),
  }
  Metrics.incr("plan_tx_held")
  return true
end

local function held_values(scopes)
  local n = neuro()
  local held = n and n.held_plan_write
  if not held then return nil end
  if held.run_generation ~= n.run_generation then
    n.held_plan_write = nil
    return nil
  end
  local out
  for field, key in pairs(PLAN_KEYS) do
    if held.values[key] ~= nil and held.scopes[field] == scopes[field] then
      out = out or {}
      out[key] = held.values[key]
    end
  end
  return out
end

function M.prepare(action_name, data)
  if not COVERED[action_name] then return nil end
  data = type(data) == "table" and data or {}
  local state = require("core.state").get_state_name()
  local requirements = PlanGate.action_requirements(state, action_name)
  local explicit = type(data.plan) == "table" and data.plan or nil
  local plan_data = {}
  local explicitly_written = {}
  local blanked = {}
  local inherited, resumed = false, false

  if explicit then
    for field, key in pairs(PLAN_KEYS) do
      local per_hand = action_name == "play_hand" or action_name == "discard_hand"
      local in_scope = (not per_hand) or key == "boss_plan"
      if explicit[key] ~= nil and in_scope then
        if blank_text(explicit[key]) then
          blanked[field] = true
        else
          plan_data[key] = explicit[key]
          explicitly_written[field] = true
        end
      end
    end
  end

  for field, required in pairs(requirements.plan or {}) do
    if required and blanked[field] then
      return reject("Provide plan." .. PLAN_KEYS[field]
        .. " with this action: an empty value is not a plan.")
    end
  end

  local scopes = field_scopes()
  local held = held_values(scopes)
  if held then
    for _, key in pairs(PLAN_KEYS) do
      if plan_data[key] == nil and held[key] ~= nil then
        plan_data[key] = held[key]
        resumed = true
      end
    end
  end

  local scope_pins = nil
  for field, required in pairs(requirements.plan or {}) do
    if required and plan_data[PLAN_KEYS[field]] == nil then
      local value, pinned = current_plan_value(field)
      if value == nil then
        return reject("Provide plan." .. PLAN_KEYS[field] .. " with this action.")
      end
      plan_data[PLAN_KEYS[field]] = value
      if pinned ~= nil then
        scope_pins = scope_pins or {}
        scope_pins[field] = pinned
      end
      inherited = true
    end
  end

  if requirements.joker_order then
    if data.joker_order_confirmed ~= true then return reject(PlanGate.joker_order_prose()) end
    PlanGate.ack_joker_order()
  end

  local plan_commit, plan_err
  if has_fields(plan_data) or resumed or has_fields(requirements.plan) then
    local scope_snapshot
    if action_name == "select_blind" or action_name == "toggle_shop" then
      scope_snapshot = {}
      for k, v in pairs(scopes) do scope_snapshot[k] = v end
    end
    if scope_pins then
      scope_snapshot = scope_snapshot or {}
      for field, pinned in pairs(scope_pins) do scope_snapshot[field] = pinned end
    end
    plan_commit, plan_err = PlanHandlers.prepare_plan(plan_data, requirements.plan, scope_snapshot,
      explicitly_written)
    if not plan_commit then
      Metrics.incr("plan_tx_rejected")
      return nil, plan_err
    end
  end

  if not plan_commit then return nil end
  if inherited then Metrics.incr("plan_tx_inherited") end
  if resumed then Metrics.incr("plan_tx_resumed") end

  local n = neuro() or {}
  return {
    plan_commit = plan_commit,
    plan_values = plan_data,
    plan_scopes = scopes,
    requirements = requirements,
    token = {
      run_generation = n.run_generation,
      shop_visit_epoch = state == "SHOP" and n.shop_visit_epoch or nil,
      plan_revision = tonumber(n.plan_revision) or 0,
    },
    shop_origin = state == "SHOP",
  }
end

local function apply_commits(tx)
  local messages = {}
  if tx.plan_commit then messages[#messages + 1] = tx.plan_commit() end
  return table.concat(messages, " ")
end

local function finish_commit(tx)
  PlanGate.complete_requirements(tx.requirements, tx.token.shop_visit_epoch)
  Metrics.incr("plan_tx_committed")
end

local function commit(tx)
  local message = apply_commits(tx)
  finish_commit(tx)
  return message
end

local function token_is_current(tx)
  local n = neuro()
  local token = tx and tx.token or {}
  return n ~= nil
    and token.run_generation == n.run_generation
    and (token.shop_visit_epoch == nil or token.shop_visit_epoch == n.shop_visit_epoch)
    and (tonumber(token.plan_revision) or 0) == (tonumber(n.plan_revision) or 0)
end

local function stale_reason(tx)
  local n = neuro()
  if not n then return "no_bridge" end
  local token = tx and tx.token or {}
  if token.run_generation ~= n.run_generation then return "run_generation" end
  if token.shop_visit_epoch ~= nil and token.shop_visit_epoch ~= n.shop_visit_epoch then
    return "shop_visit_epoch"
  end
  if (tonumber(token.plan_revision) or 0) ~= (tonumber(n.plan_revision) or 0) then
    return "plan_revision"
  end
  return "unknown"
end

local function dropped_fields(tx)
  local names = {}
  for _, key in pairs(PLAN_KEYS) do
    if tx and tx.plan_values and tx.plan_values[key] ~= nil then names[#names + 1] = key end
  end
  table.sort(names)
  return #names > 0 and table.concat(names, ",") or "-"
end

local function note_stale_drop(action_name, tx)
  _stale_drops = _stale_drops + 1
  Metrics.incr("plan_tx_stale")
  if _stale_drops < _stale_log_next then return end
  _stale_log_next = _stale_drops * 10
  print(string.format("[neuro-game] plan_tx: dropped plan write on %s, token stale (%s), fields %s (x%d)",
    tostring(action_name), stale_reason(tx), dropped_fields(tx), _stale_drops))
end

local function commit_receipt_transaction(action_name, tx)
  if not token_is_current(tx) then
    note_stale_drop(action_name, tx)
    local dropped = dropped_fields(tx)
    if dropped ~= "-" then
      pending_message = "Plan not saved (" .. dropped
        .. "): the state it described changed before it landed."
    end
    return
  end
  if tx.shop_origin and SHOP_MUTATIONS[action_name] then PlanGate.mark_shop_changed(action_name) end
  M.release()
  local message = commit(tx)
  pending_message = message ~= "" and message or nil
end

function M.wrap(action_name, _data, exec, tx)
  if type(exec) ~= "function" or not tx then return exec end
  return function()
    local result = exec()
    if ActionReceipt.is_receipt(result) then
      ActionReceipt.chain_callbacks(result, function()
        commit_receipt_transaction(action_name, tx)
      end)
      return result
    end
    if ActionReceipt.is_outcome(result) and result.status == "applied" then
      commit_receipt_transaction(action_name, tx)
    end
    return result
  end
end

if rawget(_G, "NEURO_TEST") then
  M._test = {
    stale_drops = function() return _stale_drops end,
  }
end

return M
