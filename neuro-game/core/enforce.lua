local Actions = require("core.actions")
local State = require("core.state")
local StateKinds = require("core.state_kinds")
local ContextCompact = require("context.context_compact")
local dotenv = require("util.dotenv")
local Metrics = require("util.metrics")

local Enforce = {}

local Tuning = require("core.tuning")

local PACK_STATES = StateKinds.PACK_STATES
-- per-pack env overrides win; otherwise packs share the grouped tuning knobs
local ENV_STATE_CD, ENV_GLOBAL_CD = {}, {}
for state in pairs(PACK_STATES) do
  ENV_STATE_CD[state] = tonumber(dotenv.get("NEURO_THROTTLE_" .. state) or "")
  ENV_GLOBAL_CD[state] = tonumber(dotenv.get("NEURO_GLOBAL_THROTTLE_" .. state) or "")
end
local DEFAULT_MAX_REPEAT = 3
local MAX_REROLL_SHOP_REPEAT = 30
-- NEURO_FORCE_ONLY is read live from Tuning, not cached at load

local ACTION_NAME_SET = {}
do
  local defs = Actions.get_static_actions()
  for i = 1, #defs do
    ACTION_NAME_SET[defs[i].name] = true
  end
end

local BYPASS_STATE_VALIDATION = {
  exit_overlay_menu = true,
  start_challenge_run = true,
  start_setup_run = true,
}

-- single source so the cooldown and repeat gates cannot drift apart
local UNGATED_ACTIONS = {
  exit_overlay_menu = true,
}

local tracker = {
  last_action = nil,
  repeat_count = 0,
  per_action_last = {},
  last_state = nil,
  last_refresh_at = 0,
  last_refresh_state = nil,
  last_any_action_at = 0,
}


local now_time = require("util.utils").now

local function get_cooldown(state_name)
  local env = ENV_STATE_CD[state_name]
  if env then return env end
  if state_name == "SHOP" then return Tuning.get("NEURO_THROTTLE_SHOP") end
  if PACK_STATES[state_name] then return Tuning.get("NEURO_THROTTLE_PACK") end
  return Tuning.get("NEURO_ENFORCE_COOLDOWN")
end

local function get_global_cooldown(state_name)
  local env = ENV_GLOBAL_CD[state_name]
  if env then return env end
  if state_name == "SELECTING_HAND" then return Tuning.get("NEURO_GLOBAL_THROTTLE_SELECTING_HAND") end
  if state_name == "SHOP" then return Tuning.get("NEURO_GLOBAL_THROTTLE_SHOP") end
  if state_name == "BLIND_SELECT" then return Tuning.get("NEURO_GLOBAL_THROTTLE_BLIND_SELECT") end
  if PACK_STATES[state_name] then return Tuning.get("NEURO_GLOBAL_THROTTLE_PACK") end
  return Tuning.get("NEURO_GLOBAL_COOLDOWN")
end

local function is_in_active_force(name, state_name)
  if not (G and G.NEURO and G.NEURO.force_inflight and G.NEURO.force_state == state_name) then
    return false
  end
  local set = G.NEURO.force_action_set
  return set and set[name] or false
end

local function is_allowed_in_state(name, state_name)
  if name == "exit_overlay_menu" then
    return true
  end
  if not state_name or state_name == "UNKNOWN" then
    return name == "start_challenge_run" or name == "start_setup_run"
  end
  local state_set = Actions.get_state_action_set(state_name)
  if not state_set[name] then
    return false
  end
  if is_in_active_force(name, state_name) then
    return true
  end
  return Actions.is_action_valid(name)
end

local is_forced_action = require("force.force_helpers").is_forced_action

-- shared refresh throttle; nil while same-state cooldown active
local function begin_refresh()
  local state_name = State.get_state_name()
  local t = now_time()
  if tracker.last_refresh_state == state_name and (t - (tracker.last_refresh_at or 0)) < Tuning.get("NEURO_REFRESH_COOLDOWN") then
    return nil
  end
  tracker.last_refresh_state = state_name
  tracker.last_refresh_at = t
  return state_name, Actions.get_valid_actions_for_state(state_name)
end

local function send_context_refresh(bridge)
  if bridge and bridge.send_context then
    local state_name, valid_actions = begin_refresh()
    if state_name then
      bridge:send_context(ContextCompact.build(state_name, valid_actions), true)
    end
  end
end

local function send_correction(bridge, reason)
  if not (bridge and bridge.send_context) then return end
  local state_name, valid_actions = begin_refresh()
  if not state_name then return end
  local parts = {
    "STATE:" .. tostring(state_name),
    "ACTION_ERR|" .. tostring(reason or "invalid"),
    "ALLOWED|" .. table.concat(valid_actions or {}, ","),
  }
  bridge:send_context(table.concat(parts, "\n"), true)
end

local function get_max_repeat(state_name, name)
  if StateKinds.is_menu_state(state_name) then
    return 15
  end

  if state_name == "SELECTING_HAND" and (
    name == "play_hand"
    or name == "discard_hand"
  ) then
    return 30
  end

  if state_name == "SHOP" and name == "reroll_shop" then
    -- reuse the canonical count (spendable + free rerolls), not raw dollars/cost
    -- pcall: a throw here must not propagate to the pre_action guard and mask the real throttle answer
    local ok_rf, rf = pcall(require("context.ctx_economy").reroll_facts)
    if ok_rf and rf and type(rf.max_affordable) == "number" then
      local allowed = math.max(DEFAULT_MAX_REPEAT, rf.max_affordable)
      return math.min(MAX_REROLL_SHOP_REPEAT, allowed)
    end
  end

  if name == "buy_from_shop" or name == "sell_card" or name == "use_card" then
    return 20
  end
  return DEFAULT_MAX_REPEAT
end

local function check_cooldown(name, state_name)
  if UNGATED_ACTIONS[name] then
    return true
  end
  local now = now_time()

  local global_cd = get_global_cooldown(state_name)
  local since_last = now - (tracker.last_any_action_at or 0)
  if since_last < global_cd then
    local remaining = math.ceil((global_cd - since_last) * 10) / 10
    Metrics.set("throttle_cooldown", remaining)
    return false, string.format("Please wait %.1f seconds before acting again.", remaining)
  end

  local last = tracker.per_action_last[name]
  local cooldown = get_cooldown(state_name)
  if last and (now - last) < cooldown then
    local remaining = math.ceil((cooldown - (now - last)) * 10) / 10
    Metrics.set("throttle_cooldown", remaining)
    return false, string.format("Please wait %.1f seconds before acting again.", remaining)
  end

  return true
end

local function commit_cooldown(name)
  local now = now_time()
  tracker.per_action_last[name] = now
  tracker.last_any_action_at = now
  Metrics.set("throttle_cooldown", 0)
end

-- repeat cap applies to forced actions too, bounding reroll/loop spam; denied attempts never advance the streak
local function check_repeat(name, state_name)
  if UNGATED_ACTIONS[name] then
    return true
  end
  if tracker.last_state ~= state_name then
    tracker.last_state = state_name
    tracker.last_action = nil
    tracker.repeat_count = 0
  end
  local count
  if tracker.last_action == name then
    count = (tracker.repeat_count or 0) + 1
  else
    count = 1
  end
  local max_repeat = get_max_repeat(state_name, name)
  if count > max_repeat then
    Metrics.set("throttle_repeat", count - 1)
    return false, string.format("Action '%s' repeated %d times (max %d). Try a different action.", name, count - 1, max_repeat)
  end
  tracker.last_action = name
  tracker.repeat_count = count
  Metrics.set("throttle_repeat", count)
  return true
end

function Enforce.pre_action(bridge, name)
  if not ACTION_NAME_SET[name] then
    send_correction(bridge, "unknown_action=" .. tostring(name))
    return false, "This action is not allowed in this build. Pick one of the listed actions."
  end
  local state_name = State.get_state_name()
  if not is_allowed_in_state(name, state_name) then
    send_correction(bridge, string.format("not_in_state name=%s state=%s", name, state_name))
    return false, string.format("Action '%s' is not available in state '%s'.", name, state_name)
  end
  if BYPASS_STATE_VALIDATION[name]
    and not is_in_active_force(name, state_name)
    and not Actions.is_action_valid(name) then
    send_correction(bridge, "unavailable name=" .. tostring(name))
    return false, string.format("Action '%s' is currently unavailable due to game conditions.", name)
  end
  if Tuning.bool("NEURO_FORCE_ONLY") and not is_forced_action(name) then
    send_correction(bridge, "force_only")
    return false, "This action is only allowed during an active action force. Wait for a forced action."
  end
  if bridge and bridge.is_transition_cooldown and bridge:is_transition_cooldown() then
    send_correction(bridge, "transitioning")
    -- transient: retryable once the transition ends, so the caller must not cache this rejection
    return false, "The game is transitioning between screens. Wait a moment, then try again.", true
  end
  local skip_cooldown = is_in_active_force(name, state_name) or is_forced_action(name)
  if not skip_cooldown then
    local ok_cd, cd_err = check_cooldown(name, state_name)
    if not ok_cd then
      send_correction(bridge, "throttle")
      -- transient: retryable once the cooldown elapses, so the caller must not cache this rejection
      return false, cd_err, true
    end
  end
  local ok_repeat, repeat_err = check_repeat(name, state_name)
  if not ok_repeat then
    send_correction(bridge, "throttle_repeat")
    return false, repeat_err
  end
  if not skip_cooldown then
    commit_cooldown(name)
  end
  return true
end

function Enforce.post_action(bridge, ok)
  if not ok then
    send_context_refresh(bridge)
  end
end

function Enforce.on_error(bridge)
  send_context_refresh(bridge)
end

return Enforce
