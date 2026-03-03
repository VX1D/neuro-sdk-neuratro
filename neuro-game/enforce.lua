local Actions = require("actions")
local State = require("state")
local ContextCompact = require("context_compact")
local dotenv = require("dotenv")

local Enforce = {}

local _speed_mult = tonumber(os.getenv("NEURO_SPEED_MULT") or "") or 1.0
local _fast = _speed_mult < 0.6

local COOLDOWN_SECONDS = dotenv.num("NEURO_ENFORCE_COOLDOWN", _fast and 0.18 or 0.60)
local STATE_COOLDOWN_SECONDS = {
  SHOP           = dotenv.num("NEURO_THROTTLE_SHOP",          _fast and 0.30 or 1.20),
  TAROT_PACK     = dotenv.num("NEURO_THROTTLE_TAROT_PACK",    _fast and 0.35 or 1.20),
  PLANET_PACK    = dotenv.num("NEURO_THROTTLE_PLANET_PACK",   _fast and 0.35 or 1.20),
  SPECTRAL_PACK  = dotenv.num("NEURO_THROTTLE_SPECTRAL_PACK", _fast and 0.35 or 1.20),
  STANDARD_PACK  = dotenv.num("NEURO_THROTTLE_STANDARD_PACK", _fast and 0.35 or 1.20),
  BUFFOON_PACK   = dotenv.num("NEURO_THROTTLE_BUFFOON_PACK",  _fast and 0.35 or 1.20),
}
-- Global minimum gap between ANY two actions (prevents interleaving different actions too fast)
local GLOBAL_COOLDOWN_SECONDS = dotenv.num("NEURO_GLOBAL_COOLDOWN", _fast and 0.65 or 2.0)
local GLOBAL_STATE_COOLDOWN_SECONDS = {
  SELECTING_HAND = dotenv.num("NEURO_GLOBAL_THROTTLE_SELECTING_HAND", _fast and 0.55 or 1.8),
  SHOP           = dotenv.num("NEURO_GLOBAL_THROTTLE_SHOP",           _fast and 2.20 or 6.0),
  BLIND_SELECT   = dotenv.num("NEURO_GLOBAL_THROTTLE_BLIND_SELECT",   _fast and 0.80 or 3.0),
  TAROT_PACK     = dotenv.num("NEURO_GLOBAL_THROTTLE_TAROT_PACK",     _fast and 1.40 or 4.5),
  PLANET_PACK    = dotenv.num("NEURO_GLOBAL_THROTTLE_PLANET_PACK",    _fast and 1.40 or 4.5),
  SPECTRAL_PACK  = dotenv.num("NEURO_GLOBAL_THROTTLE_SPECTRAL_PACK",  _fast and 1.40 or 4.5),
  STANDARD_PACK  = dotenv.num("NEURO_GLOBAL_THROTTLE_STANDARD_PACK",  _fast and 1.40 or 4.5),
  BUFFOON_PACK   = dotenv.num("NEURO_GLOBAL_THROTTLE_BUFFOON_PACK",   _fast and 1.40 or 4.5),
}
local DEFAULT_MAX_REPEAT = 3
local MAX_REROLL_SHOP_REPEAT = 30
local FORCE_ONLY = false
do
  local env = os.getenv("NEURO_FORCE_ONLY")
  if env then
    env = env:lower()
    FORCE_ONLY = env == "1" or env == "true" or env == "yes"
  end
end

local ACTION_NAME_SET = {}
do
  local defs = Actions.get_static_actions()
  for i = 1, #defs do
    ACTION_NAME_SET[defs[i].name] = true
  end
end

local tracker = {
  last_action = nil,
  repeat_count = 0,
  per_action_last = {},
  last_state = nil,
  last_refresh_at = 0,
  last_refresh_state = nil,
  last_any_action_at = 0,  -- global: time of the last successfully throttle-passed action
}

local REFRESH_COOLDOWN = 0.35

local function now_time()
  if G and G.TIMERS and G.TIMERS.REAL then
    return G.TIMERS.REAL
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function get_cooldown(state_name)
  return STATE_COOLDOWN_SECONDS[state_name] or COOLDOWN_SECONDS
end

local function get_global_cooldown(state_name)
  return GLOBAL_STATE_COOLDOWN_SECONDS[state_name] or GLOBAL_COOLDOWN_SECONDS
end

local function get_effective_state(state_name)
  if state_name and state_name ~= "UNKNOWN" then
    return state_name
  end
  local sn = State.get_state_name and State.get_state_name()
  if sn and sn ~= "UNKNOWN" then
    return sn
  end
  return state_name
end

local function is_in_active_force(name, state_name)
  if not (G and G.NEURO.force_inflight and G.NEURO.force_state == state_name) then
    return false
  end
  local set = G.NEURO.force_action_set
  return set and set[name] or false
end

local function is_allowed_in_state(name, state_name)
  if not state_name or state_name == "UNKNOWN" then
    return name == "start_run" or name == "start_challenge_run" or name == "start_setup_run"
  end
  local state_set = Actions.get_state_action_set(state_name)
  if not state_set[name] then
    return false
  end
  -- Trust force handler's validation — it already checked is_action_valid when building the force
  if is_in_active_force(name, state_name) then
    return true
  end
  return Actions.is_action_valid(name)
end

local function is_forced_action(name)
  if not (G and G.NEURO.force_inflight and name) then
    return false
  end
  local set = G.NEURO.force_action_set
  if set then
    return not not set[name]
  end
  local list = G.NEURO.force_actions
  if list then
    for i = 1, #list do
      if list[i] == name then
        return true
      end
    end
  end
  return false
end

local function send_context_refresh(bridge)
  if bridge and bridge.send_context then
    local state_name = State.get_state_name()
    local valid_actions = Actions.get_valid_actions_for_state(state_name)
    local t = now_time()
    if tracker.last_refresh_state == state_name and (t - (tracker.last_refresh_at or 0)) < REFRESH_COOLDOWN then
      return
    end
    tracker.last_refresh_state = state_name
    tracker.last_refresh_at = t
    bridge:send_context(ContextCompact.build(state_name, valid_actions), true)
  end
end

local function get_max_repeat(state_name, name)
  if state_name == "GAME_OVER" or state_name == "MENU" or state_name == "SPLASH" or state_name == "RUN_SETUP" then
    return 15
  end

  if state_name == "SELECTING_HAND" and (
    name == "set_hand_highlight"
    or name == "play_cards_from_highlighted"
    or name == "discard_cards_from_highlighted"
    or name == "clear_hand_highlight"
  ) then
    return 30
  end

  if state_name == "SHOP" and name == "reroll_shop" then
    if not (G and G.GAME) then
      return DEFAULT_MAX_REPEAT
    end
    local money = G.GAME.dollars
    local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost
    if type(money) == "number" and type(cost) == "number" and cost > 0 then
      local affordable = math.floor(money / cost)
      local allowed = math.max(DEFAULT_MAX_REPEAT, affordable)
      return math.min(MAX_REROLL_SHOP_REPEAT, allowed)
    end
  end
  return DEFAULT_MAX_REPEAT
end

local function check_throttle(name, state_name)
  local now = now_time()

  -- Global cooldown: minimum gap between ANY two actions
  local global_cd = get_global_cooldown(state_name)
  local since_last = now - (tracker.last_any_action_at or 0)
  if since_last < global_cd then
    local remaining = math.ceil((global_cd - since_last) * 10) / 10
    return false, string.format("Please wait %.1f seconds before acting again.", remaining)
  end

  -- Per-action cooldown: prevent hammering the same action
  local last = tracker.per_action_last[name]
  local cooldown = get_cooldown(state_name)
  if last and (now - last) < cooldown then
    local remaining = math.ceil((cooldown - (now - last)) * 10) / 10
    return false, string.format("Please wait %.1f seconds before acting again.", remaining)
  end

  if tracker.last_state ~= state_name then
    tracker.last_state = state_name
    tracker.last_action = nil
    tracker.repeat_count = 0
  end
  if tracker.last_action == name then
    tracker.repeat_count = (tracker.repeat_count or 0) + 1
  else
    tracker.last_action = name
    tracker.repeat_count = 1
  end
  local max_repeat = get_max_repeat(state_name, name)
  if tracker.repeat_count > max_repeat then
    return false, string.format("Action '%s' repeated %d times (max %d). Try a different action.", name, tracker.repeat_count - 1, max_repeat)
  end

  tracker.per_action_last[name] = now
  tracker.last_any_action_at = now
  return true
end

function Enforce.pre_action(bridge, name)
  if not ACTION_NAME_SET[name] then
    send_context_refresh(bridge)
    return false, "This action is not allowed in this build. Pick one of the listed actions."
  end
  local state_name = get_effective_state(State.get_state_name())
  if not is_allowed_in_state(name, state_name) then
    send_context_refresh(bridge)
    return false, string.format("Action '%s' is not available in state '%s'.", name, state_name)
  end
  if not is_in_active_force(name, state_name) and not Actions.is_action_valid(name) then
    send_context_refresh(bridge)
    return false, string.format("Action '%s' is currently unavailable due to game conditions.", name)
  end
  if FORCE_ONLY and not is_forced_action(name) then
    send_context_refresh(bridge)
    return false, "This action is only allowed during an active action force. Wait for a forced action."
  end
  if bridge and bridge.is_transition_cooldown and bridge:is_transition_cooldown() then
    send_context_refresh(bridge)
    return false, "The game is transitioning between screens. Wait a moment, then try again."
  end
  local ok_throttle, throttle_err = check_throttle(name, state_name)
  if not ok_throttle then
    send_context_refresh(bridge)
    return false, throttle_err
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
