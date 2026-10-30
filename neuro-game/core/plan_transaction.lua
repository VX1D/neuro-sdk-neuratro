local M = {}

local ActionResult = require("core.action_result")
local Metrics = require("util.metrics")
local Gate = require("core.gate")
local PlanHandlers = require("handlers.plan_handlers")
local Utils = require("util.utils")

local SHOP_MUTATIONS = {
  buy_from_shop = true, sell_card = true, use_consumable = true, use_directional_consumable = true,
  choose_pack_card = true, choose_directional_pack_card = true, reroll_shop = true,
}
local COVERED = { leave_shop = true, select_blind = true, play_hand = true, discard_hand = true, resolve_play = true }
for name in pairs(SHOP_MUTATIONS) do COVERED[name] = true end

local function advertised_plan_keys(action_name)
  local contract = require("core.action_registry").get(action_name)
  local properties = contract and type(contract.schema) == "table" and contract.schema.properties or nil
  local plan = type(properties) == "table" and properties.plan or nil
  local plan_properties = type(plan) == "table" and plan.properties or nil
  if type(plan_properties) ~= "table" then return nil end
  local keys = {}
  for key in pairs(plan_properties) do keys[key] = true end
  return keys
end

local PLAN_KEYS = {
  hand = "hand_plan", build = "build_plan", money = "money_plan", boss = "boss_plan",
  focus = "hand_focus",
}
local PLAN_FIELDS = { "hand", "build", "money", "boss", "focus" }
local FIELD_GATES = {
  hand = { "current_blind_scope", "hand_plan_is_current", "hand" },
  build = { "current_build_scope", "build_plan_is_current", "build" },
  money = { "current_economy_scope", "money_plan_is_current", "money" },
  boss = { "current_boss_scope", "boss_plan_is_current", "boss" },
  focus = { "current_blind_scope", "hand_focus_is_current", "hand_focus" },
}


local CHOICE_FIELDS = { "blind", "area", "index", "name", "use", "indices", "hand_indices", "left_index", "right_index" }

local function choice_of(action_name, data)
  local parts = { action_name }
  for _, field in ipairs(CHOICE_FIELDS) do
    local value = type(data) == "table" and data[field] or nil
    if type(value) == "table" then
      local items = {}
      for i, item in ipairs(value) do items[i] = tostring(item) end
      value = "[" .. table.concat(items, ",") .. "]"
    elseif type(value) == "string" then
      value = Utils.normalize_ws(value):lower()
    end
    parts[#parts + 1] = field .. "=" .. tostring(value)
  end
  return table.concat(parts, "|")
end

local function is_plan_key(key)
  for _, known in pairs(PLAN_KEYS) do
    if known == key then return true end
  end
  return false
end

local function takes(advertised, key)
  return is_plan_key(key) and (advertised == nil or advertised[key] == true)
end

local function describe_key(key, advertised)
  key = tostring(key)
  if key:match("^[%a_][%w_]*$") then return "plan." .. key end
  local ok, quoted = pcall(require("util.neuro_json").encode, key)
  local text = "plan key " .. (ok and quoted or ("'" .. key .. "'"))
  local near = key:lower():gsub("[^%w_]", "")
  if near ~= key and takes(advertised, near) then text = text .. " (did you mean plan." .. near .. "?)" end
  return text
end

local function ignored_plan_note(explicit, advertised)
  local ignored = {}
  for key in pairs(explicit) do
    if not takes(advertised, key) then ignored[#ignored + 1] = describe_key(key, advertised) end
  end
  if #ignored == 0 then return nil end
  table.sort(ignored)
  local note = "Not saved: " .. table.concat(ignored, ", ")
    .. (#ignored == 1 and " is not a plan field of this move" or " are not plan fields of this move")
  if (explicit.primary ~= nil or explicit.fallback ~= nil) and (advertised == nil or advertised.hand_focus) then
    note = note .. "; a hand focus goes inside plan.hand_focus as {\"primary\": ..., \"fallback\": ...}"
  end
  return note .. "."
end

local function with_note(message, note)
  if not note then return message end
  return (message and message ~= "") and (message .. " " .. note) or note
end

local function neuro() return G and G.NEURO end

local function field_scopes()
  local out = {}
  for _, field in ipairs(PLAN_FIELDS) do out[field] = Gate[FIELD_GATES[field][1]]() end
  return out
end

local function current_plan_value(field)
  local n = neuro()
  local plan = n and n.plan
  local gate = FIELD_GATES[field]
  if not Gate[gate[2]](plan) then return nil end
  return plan[gate[3]], plan[gate[3] .. "_scope"]
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

function M.hold(tx, proposal_ref)
  local n = neuro()
  if not n or type(tx) ~= "table" or not has_fields(tx.plan_values) then return false end
  n.held_plan_write = {
    run_generation = n.run_generation,
    values = tx.plan_values,
    scopes = tx.plan_scopes or field_scopes(),
    proposal_ref = proposal_ref,
    choice = tx.choice,
  }
  Metrics.incr("plan_tx_held")
  return true
end

function M.release_hand_proposal(proposal_ref)
  local n = neuro()
  local held = n and n.held_plan_write
  if not (held and proposal_ref ~= nil) then return false end
  if held.proposal_ref ~= proposal_ref then return false end
  n.held_plan_write = nil
  return true
end

local function held_values(scopes, proposal_ref, choice)
  local n = neuro()
  local held = n and n.held_plan_write
  if not held then return nil end
  if held.run_generation ~= n.run_generation then
    n.held_plan_write = nil
    return nil
  end
  if held.proposal_ref ~= proposal_ref then
    return nil
  end
  -- Do not carry a plan for a choice that did not execute into a different choice.
  if proposal_ref == nil and held.choice ~= nil and held.choice ~= choice then
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

local ROUND_ACTIONS = { play_hand = true, discard_hand = true }

local function boss_plan_open(action_name)
  local blind = G and G.GAME and G.GAME.blind
  if ROUND_ACTIONS[action_name] and not (blind and blind.boss) then
    return false, "Not saved: a play or discard saves plan.boss_plan only on the Boss round, and this blind is not the Boss."
  end
  if not PlanHandlers.boss_plan_writable() then
    return false, "Not saved: plan.boss_plan is kept for the boss this ante shows, and none is shown yet."
  end
  return true
end

local function plan_fields_note(action_name, explicit, advertised)
  local note = ignored_plan_note(explicit, advertised)
  if explicit.boss_plan ~= nil and takes(advertised, "boss_plan") and not blank_text(explicit.boss_plan) then
    local open, why = boss_plan_open(action_name)
    if not open then note = with_note(note, why) end
  end
  return note
end

function M.ignored_note(action_name, data)
  if not COVERED[action_name] or type(data) ~= "table" or type(data.plan) ~= "table" then return nil end
  return plan_fields_note(action_name, data.plan, advertised_plan_keys(action_name))
end

function M.prepare(action_name, data)
  if action_name == "record_plan" then
    local note = PlanHandlers.record_plan_note(data)
    return note and { note_only = true, ignored_note = note } or nil
  end
  if not COVERED[action_name] then return nil end
  data = type(data) == "table" and data or {}
  if action_name == "resolve_play" and data.plan ~= nil then
    return reject("Answering a play review cannot create or replace plan fields; it only settles the reviewed play.")
  end
  local state = require("core.state").get_state_name()
  local requirements = Gate.action_requirements(state, action_name)
  local explicit = type(data.plan) == "table" and data.plan or nil
  local plan_data = {}
  local explicitly_written = {}
  local blanked = {}
  local inherited, resumed = false, false

  local advertised = advertised_plan_keys(action_name)
  local ignored_note = explicit and plan_fields_note(action_name, explicit, advertised) or nil
  local boss_writable = boss_plan_open(action_name)
  if explicit then
    for field, key in pairs(PLAN_KEYS) do
      local in_scope = (advertised == nil or advertised[key] == true) and (field ~= "boss" or boss_writable)
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

  local scopes = field_scopes()
  local proposal_ref = action_name == "resolve_play" and Gate.proposal_ref() or nil
  local choice = choice_of(action_name, data)
  local held = held_values(scopes, proposal_ref, choice)
  if held then
    for _, key in pairs(PLAN_KEYS) do
      if plan_data[key] == nil and held[key] ~= nil then
        plan_data[key] = held[key]
        resumed = true
      end
    end
  end

  local scope_pins = nil
  local missing, any_blank = {}, false
  for _, field in ipairs(PLAN_FIELDS) do
    local required = (requirements.plan or {})[field]
    if required and blanked[field] then
      missing[#missing + 1], any_blank = "plan." .. PLAN_KEYS[field], true
    elseif required and plan_data[PLAN_KEYS[field]] == nil then
      local value, pinned = current_plan_value(field)
      if value == nil then
        missing[#missing + 1] = "plan." .. PLAN_KEYS[field]
      else
        plan_data[PLAN_KEYS[field]] = value
        if pinned ~= nil then
          scope_pins = scope_pins or {}
          scope_pins[field] = pinned
        end
        inherited = true
      end
    end
  end
  if #missing > 0 then
    return reject(with_note("Provide " .. require("context.ctx_helpers").join(missing) .. " with this action"
      .. (any_blank and ": an empty value is not a plan." or "."), ignored_note))
  end

  local review = Gate.check("plan", action_name, data)
  if review then
    review.message = with_note(review.message, ignored_note)
    if review.brief then review.brief = with_note(review.brief, ignored_note) end
    Metrics.incr("plan_tx_rejected")
    return nil, review
  end

  local plan_commit, plan_err
  if has_fields(plan_data) or resumed or has_fields(requirements.plan) then
    local scope_snapshot
    if action_name == "select_blind" or action_name == "leave_shop" then
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

  if not plan_commit and action_name ~= "resolve_play" then
    return ignored_note and { note_only = true, ignored_note = ignored_note } or nil
  end
  if inherited then Metrics.incr("plan_tx_inherited") end
  if resumed then Metrics.incr("plan_tx_resumed") end

  local n = neuro() or {}
  return {
    plan_commit = plan_commit,
    plan_values = plan_data,
    plan_scopes = scopes,
    requirements = requirements,
    shop_visit_epoch = state == "SHOP" and n.shop_visit_epoch or nil,
    shop_origin = state == "SHOP",
    proposal_ref = proposal_ref,
    choice = choice,
    ignored_note = ignored_note,
  }
end

function M.settle(action_name, data, tx)
  if not tx then return end
  if action_name == "resolve_play" and data and data.answer == "no" then
    return M.release_hand_proposal(tx.proposal_ref)
  end
  if tx.note_only then return end
  if action_name == "resolve_play" and tx.proposal_ref == nil then return end
  if tx.shop_origin and SHOP_MUTATIONS[action_name] then Gate.mark_shop_changed(action_name) end
  M.release()
  if tx.plan_commit then tx.plan_commit() end
  Gate.complete_requirements(tx.requirements, tx.shop_visit_epoch)
  Metrics.incr("plan_tx_committed")
end

return M
