local ActionResult = require("core.action_result")
local Actions = require("core.actions")
local State = require("core.state")
local StateKinds = require("core.state_kinds")
local TransitionGuard = require("core.transition_guard")
local Metrics = require("util.metrics")
local ForceState = require("core.force_state")
local ActionPolicy = require("core.action_policy")
local ActionRegistry = require("core.action_registry")

local Enforce = {}

local DEFAULT_MAX_REPEAT = 3
local MAX_REROLL_SHOP_REPEAT = 30
local REJECT_STREAK_LIMIT = 3
local WINDOW_REFUSAL_BUDGET = 2 * REJECT_STREAK_LIMIT

local ACTION_NAME_SET = {}
local ACTION_PROPS = {}
do
  local defs = require("core.action_registry").definitions()
  for i = 1, #defs do
    local def = defs[i]
    ACTION_NAME_SET[def.name] = true
    local props = def.schema and def.schema.properties
    if type(props) == "table" then
      local declared = {}
      for key in pairs(props) do declared[key] = true end
      ACTION_PROPS[def.name] = declared
    end
  end
end

local BYPASS_STATE_VALIDATION = {
  exit_overlay_menu = true,
  start_challenge_run = true,
  start_setup_run = true,
}

local UNGATED_ACTIONS = {
  exit_overlay_menu = true,
}

local tracker = {
  last_action = nil,
  last_payload = nil,
  junk_action = nil,
  junk_count = 0,
  repeat_count = 0,
  rejects = {},
  reject_epoch = nil,
  reject_total = 0,
  per_action_last = {},
  last_state = nil,
  last_refresh_at = 0,
  last_refresh_state = nil,
  last_any_action_at = 0,
}

local Utils = require("util.utils")

local function get_cooldown(state_name)
  if state_name == "SHOP" then return Utils.gate_seconds("enforce_state_throttle", "NEURO_THROTTLE_SHOP") end
  if StateKinds.is_pack_state(state_name) then return Utils.gate_seconds("enforce_state_throttle", "NEURO_THROTTLE_PACK") end
  return Utils.gate_seconds("enforce_per_action_cooldown", "NEURO_ENFORCE_COOLDOWN")
end

local function get_global_cooldown(state_name)
  if state_name == "SELECTING_HAND" then return Utils.gate_seconds("enforce_state_throttle", "NEURO_GLOBAL_THROTTLE_SELECTING_HAND") end
  if state_name == "SHOP" then return Utils.gate_seconds("enforce_state_throttle", "NEURO_GLOBAL_THROTTLE_SHOP") end
  if state_name == "BLIND_SELECT" then return Utils.gate_seconds("enforce_state_throttle", "NEURO_GLOBAL_THROTTLE_BLIND_SELECT") end
  if StateKinds.is_pack_state(state_name) then return Utils.gate_seconds("enforce_state_throttle", "NEURO_GLOBAL_THROTTLE_PACK") end
  return Utils.gate_seconds("enforce_global_cooldown", "NEURO_GLOBAL_COOLDOWN")
end

local function is_in_active_force(name, state_name)
  return ForceState.is_active_action(name, state_name)
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

local is_forced_action = ForceState.is_forced_action

local function begin_refresh()
  local state_name = State.get_state_name()
  local t = Utils.gate_now("context_refresh_cooldown")
  if tracker.last_refresh_state == state_name and (t - (tracker.last_refresh_at or 0))
    < Utils.gate_seconds("context_refresh_cooldown", "NEURO_REFRESH_COOLDOWN") then
    return nil
  end
  tracker.last_refresh_state = state_name
  tracker.last_refresh_at = t
  return state_name, Actions.get_valid_actions_for_state(state_name)
end

local CODE_REMEDY = {
  NO_SLOT = "Nothing was bought and no money moved.",
  INSUFFICIENT_FUNDS = "Nothing was bought and no money moved: sell a card for cash, take a cheaper row, or leave the shop and bank what you have.",
}

local function humanize_reason(reason)
  reason = tostring(reason or "invalid")
  local tag = reason:match("^([%a_]+)") or reason
  if ActionResult.CODES[tag] then
    local body = reason:match("^[%u_]+:%s*(.*)$") or ""
    local remedy = CODE_REMEDY[tag] or "Nothing was executed; choose differently."
    return (body ~= "" and (body .. " ") or "") .. remedy
  end
  local name = reason:match("name=([^%s]+)")
  local state = reason:match("state=([^%s]+)")
  if tag == "unknown_action" then
    return "'" .. tostring(reason:match("unknown_action=(.+)$")) .. "' isn't a recognized action."
  elseif tag == "not_in_state" then
    return (name or "That action") .. " isn't available in the current state"
      .. (state and (" (" .. state .. ")") or "") .. "."
  elseif tag == "transitioning" then
    return "The game is mid-transition -- wait a moment and try again."
  elseif tag == "resolving" then
    return "A previous action (" .. (name or "?") .. ") is still resolving -- wait a moment."
  elseif tag == "unavailable" then
    return (name or "That action") .. " isn't available right now."
  elseif tag == "throttle" then
    return "Sent too many times too quickly -- slow down."
  elseif tag == "throttle_repeat" then
    return "Repeated too many times in a row -- try something else."
  elseif tag == "decision_window" then
    return (name or "That action") .. " needs its pending confirmation resolved first."
  end
  return reason:gsub("_", " ")
end

local function refuse(message, code)
  return false, message, ActionResult.is_transient(code), code
end

local pending_correction = nil

local function build_correction_text(reason, detail)
  local state_name = State.get_state_name()
  if not state_name then return nil end
  local tag = tostring(reason):match("^([%a_]+)") or tostring(reason)
  if tag == "decision_window" then
    return humanize_reason(reason)
  end
  if type(detail) == "string" and detail ~= "" then
    return (detail:gsub("^%s+", ""))
  end
  return "Your last action wasn't applied: " .. humanize_reason(reason)
end

local function send_correction(bridge, reason, detail)
  if not bridge then return end
  if not begin_refresh() then return end
  local text = build_correction_text(reason, detail)
  if text then pending_correction = text end
end

function Enforce.untagged_joker_indices()
  local out = {}
  if not (G and G.jokers and type(G.jokers.cards) == "table") then return out end
  local tags = (G and G.NEURO and G.NEURO.joker_intents) or {}
  for i, card in ipairs(G.jokers.cards) do
    local sid = card and card.sort_id
    if not (sid and tags[sid] and tags[sid].tag) then out[#out + 1] = i end
  end
  return out
end

function Enforce.untagged_joker_prose()
  local ix = Enforce.untagged_joker_indices()
  if #ix == 0 then return nil end
  local list = tostring(ix[1])
  for i = 2, #ix do
    list = list .. (i == #ix and " and " or ", ") .. ix[i]
  end
  return "Jokers that carry no tag: " .. list
end

local function state_gate_detail(name, state_name)
  if name == "sell_card" and state_name == "SELECTING_HAND" then
    return " This mod blocks selling while a hand is in play (base Balatro allows it); sell_card is available in the shop."
  end
  if name == "toggle_shop" then
    local prose = Enforce.untagged_joker_prose()
    if prose then
      return " " .. prose .. ". set_joker_intents tags them; toggle_shop returns to the list once every joker has one."
    end
  end
  if Actions.get_state_action_set(state_name)[name] then return "" end
  local contract = ActionRegistry.get(name)
  local states = contract and contract.states
  if type(states) == "table" then
    local list = {}
    for key in pairs(states) do list[#list + 1] = tostring(key) end
    if #list > 0 and #list <= 3 then
      table.sort(list)
      local where = list[1]
      for i = 2, #list do where = where .. (i == #list and " or " or ", ") .. list[i] end
      return string.format(" %s works in %s; this is %s, so choose from the actions this state offers.",
        name, where, tostring(state_name))
    end
  end
  return ""
end

function Enforce.take_correction()
  local correction = pending_correction
  pending_correction = nil
  return correction
end

local function get_max_repeat(state_name, name)
  if StateKinds.is_menu_state(state_name) then
    return 15
  end

  if state_name == "SELECTING_HAND" and (
    name == "play_hand"
    or name == "discard_hand"
    or name == "confirm_play"
  ) then
    return 30
  end

  if state_name == "BLIND_SELECT" and (name == "select_blind" or name == "skip_blind") then
    return 6
  end

  if state_name == "SHOP" and name == "reroll_shop" then
    local ok_rf, rf = pcall(require("facts.economy_facts").reroll_facts)
    if ok_rf and rf and type(rf.max_affordable) == "number" then
      local allowed = math.max(DEFAULT_MAX_REPEAT, rf.max_affordable)
      return math.min(MAX_REROLL_SHOP_REPEAT, allowed)
    end
  end

  if name == "buy_from_shop" or name == "sell_card" or name == "use_card" or name == "use_directional_card" then
    return 20
  end
  return DEFAULT_MAX_REPEAT
end

local function check_cooldown(name, state_name)
  if UNGATED_ACTIONS[name] then
    return true
  end
  local global_cd = get_global_cooldown(state_name)
  local since_last = Utils.gate_now("enforce_global_cooldown") - (tracker.last_any_action_at or 0)
  if since_last < global_cd then
    local remaining = math.ceil((global_cd - since_last) * 10) / 10
    Metrics.set("throttle_cooldown", remaining)
    return false, string.format("Please wait %.1f seconds before acting again.", remaining), true
  end

  local last = tracker.per_action_last[name]
  local cooldown = get_cooldown(state_name)
  local since_this = Utils.gate_now("enforce_per_action_cooldown") - (last or 0)
  if last and since_this < cooldown then
    local remaining = math.ceil((cooldown - since_this) * 10) / 10
    Metrics.set("throttle_cooldown", remaining)
    return false, string.format("Please wait %.1f seconds before acting again.", remaining)
  end

  return true
end

local cooldown_snapshot = nil

local function commit_cooldown(name)
  cooldown_snapshot = {
    name = name,
    per_action_last = tracker.per_action_last[name],
    last_any_action_at = tracker.last_any_action_at,
  }
  tracker.per_action_last[name] = Utils.gate_now("enforce_per_action_cooldown")
  tracker.last_any_action_at = Utils.gate_now("enforce_global_cooldown")
  Metrics.set("throttle_cooldown", 0)
end

local ADVISORY_FIELDS = { plan = true }
local ORDERLESS_ARRAYS = { indices = true, hand_indices = true, intents = true }
local TARGET_CONFIRMATION_FIELDS = { name = true }

local function canonical(value, field)
  if type(value) ~= "table" then
    return type(value) .. ":" .. tostring(value)
  end
  local count = #value
  if count > 0 then
    local parts = {}
    for i = 1, count do parts[i] = canonical(value[i]) end
    if ORDERLESS_ARRAYS[field] then table.sort(parts) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(value) do
    if not ADVISORY_FIELDS[k] and not TARGET_CONFIRMATION_FIELDS[k] then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  local parts = {}
  for i = 1, #keys do
    parts[i] = keys[i] .. "=" .. canonical(value[keys[i]], keys[i])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function declared_only(decoded, name)
  local declared = ACTION_PROPS[name]
  if not declared then return decoded end
  local kept = {}
  for key, value in pairs(decoded) do
    if declared[key] then kept[key] = value end
  end
  return kept
end

local function payload_key(payload, name)
  if payload == nil or payload == "" then return "", true end
  local decoded = payload
  if type(payload) == "string" then
    local ok, parsed = pcall(require("util.neuro_json").decode, payload)
    if not ok or type(parsed) ~= "table" then return nil, false end
    decoded = parsed
  elseif type(payload) ~= "table" then
    return nil, false
  end
  local key = canonical(declared_only(decoded, name))
  if key == "{}" then key = "" end
  return key, true
end

local streak_snapshot = nil

local function snapshot_streak()
  streak_snapshot = {
    last_action = tracker.last_action,
    last_payload = tracker.last_payload,
    repeat_count = tracker.repeat_count,
    junk_action = tracker.junk_action,
    junk_count = tracker.junk_count,
  }
end

local function reset_streaks_for_state(state_name)
  if tracker.last_state == state_name then return end
  tracker.last_state = state_name
  tracker.last_action = nil
  tracker.last_payload = nil
  tracker.repeat_count = 0
  tracker.junk_action = nil
  tracker.junk_count = 0
  tracker.rejects = {}
end

local function check_repeat(name, state_name, payload)
  if UNGATED_ACTIONS[name] then
    return true
  end
  reset_streaks_for_state(state_name)
  snapshot_streak()
  local max_malformed = get_max_repeat(state_name, name)
  local key, parsed = payload_key(payload, name)
  if not parsed then
    local junk = (tracker.junk_action == name) and ((tracker.junk_count or 0) + 1) or 1
    tracker.junk_action = name
    tracker.junk_count = (junk < max_malformed) and junk or max_malformed
    if junk > max_malformed then
      Metrics.set("throttle_repeat", junk - 1)
      return false, string.format("Action '%s' repeated %d times (max %d). Try a different action.",
        name, junk - 1, max_malformed)
    end
    return true
  end
  tracker.junk_action, tracker.junk_count = nil, 0
  local count
  if tracker.last_action == name and tracker.last_payload == key then
    count = (tracker.repeat_count or 0) + 1
  else
    count = 1
  end
  tracker.last_action = name
  tracker.last_payload = key
  local max_repeat = get_max_repeat(state_name, name)
  tracker.repeat_count = (count < max_repeat) and count or max_repeat
  if count > max_repeat then
    Metrics.set("throttle_repeat", count - 1)
    return false, string.format("Action '%s' repeated %d times (max %d). Try a different action.", name, count - 1, max_repeat)
  end
  Metrics.set("throttle_repeat", count)
  return true
end

function Enforce.rollback_action()
  local cooldown = cooldown_snapshot
  if cooldown then
    cooldown_snapshot = nil
    tracker.per_action_last[cooldown.name] = cooldown.per_action_last
    tracker.last_any_action_at = cooldown.last_any_action_at
  end
  local snapshot = streak_snapshot
  if not snapshot then return end
  streak_snapshot = nil
  tracker.last_action = snapshot.last_action
  tracker.last_payload = snapshot.last_payload
  tracker.repeat_count = snapshot.repeat_count
  tracker.junk_action = snapshot.junk_action
  tracker.junk_count = snapshot.junk_count
  Metrics.set("throttle_repeat", tonumber(tracker.repeat_count) or 0)
end

local function decision_epoch()
  local neuro = G and G.NEURO
  return table.concat({
    tostring(State.get_state_name() or ""),
    tostring(neuro and neuro.run_generation or ""),
    tostring(neuro and neuro.state_enter_serial or ""),
    tostring(neuro and neuro.decision_serial or ""),
  }, "\0")
end

local function stage_code_remedy(fingerprint)
  if pending_correction then return end
  local code, message = tostring(fingerprint or ""):match("^([^%z]+)%z(.*)$")
  if not (code and ActionResult.CODES[code] and CODE_REMEDY[code]) then return end
  message = tostring(message or ""):gsub("^%s+", "")
  pending_correction = (message ~= "" and (message .. " ") or "") .. CODE_REMEDY[code]
end

function Enforce.note_rejection(name, fault_fingerprint)
  reset_streaks_for_state(State.get_state_name())
  local epoch = decision_epoch()
  if tracker.reject_epoch ~= epoch then
    tracker.reject_epoch = epoch
    tracker.reject_total = 0
    tracker.rejects = {}
  end
  local previous = tracker.rejects[name]
  local fingerprint = tostring(fault_fingerprint or "")
  local count = (type(previous) == "table" and previous.fingerprint == fingerprint)
    and ((tonumber(previous.count) or 0) + 1) or 1
  tracker.rejects[name] = { fingerprint = fingerprint, count = count }
  tracker.reject_total = (tonumber(tracker.reject_total) or 0) + 1
  stage_code_remedy(fingerprint)
  if count <= REJECT_STREAK_LIMIT and tracker.reject_total <= WINDOW_REFUSAL_BUDGET then
    return false
  end
  Metrics.incr("action_rejection_acknowledged")
  return true
end

function Enforce.note_accepted(name)
  tracker.rejects[name] = nil
  if ActionPolicy.NON_PROGRESS[name] then return end
  tracker.reject_total = 0
end

function Enforce.repeat_pressure()
  local state_name = State.get_state_name()
  if tracker.last_state ~= state_name or not tracker.last_action then return nil end
  local max_repeat = get_max_repeat(state_name, tracker.last_action)
  local count = tonumber(tracker.repeat_count) or 0
  if count < max_repeat then return nil end
  return tracker.last_action, count
end

function Enforce.pre_action(bridge, name, payload)
  streak_snapshot = nil
  cooldown_snapshot = nil
  if not ACTION_NAME_SET[name] then
    send_correction(bridge, "unknown_action=" .. tostring(name))
    return refuse("This action is not allowed in this build. Pick one of the listed actions.", "ACTION_UNAVAILABLE")
  end
  local state_name = State.get_state_name()
  if not is_allowed_in_state(name, state_name) then
    local detail = state_gate_detail(name, state_name)
    send_correction(bridge, string.format("not_in_state name=%s state=%s", name, state_name), detail)
    return refuse(string.format("Action '%s' is not available in state '%s'.%s", name, state_name, detail),
      "ACTION_UNAVAILABLE")
  end
  local in_force = is_in_active_force(name, state_name) or is_forced_action(name)
  if bridge and bridge.is_transition_cooldown and bridge:is_transition_cooldown() then
    send_correction(bridge, "transitioning")
    if in_force then
      return refuse(
        "The game is still transitioning between screens, so nothing was applied. Wait a moment, then choose again.",
        "TRANSITION_ACKNOWLEDGED")
    end
    return refuse("The game is transitioning between screens. Wait a moment, then try again.", "TRANSITION_PENDING")
  end
  do
    local busy = TransitionGuard.reject_reason(name)
    if busy then
      send_correction(bridge, "resolving name=" .. tostring(name))
      return refuse(busy, in_force and "TRANSITION_ACKNOWLEDGED" or "TRANSITION_PENDING")
    end
  end
  do
    local rejection, prose = require("core.decision_window").evaluate(name, bridge)
    if rejection then
      send_correction(bridge, "decision_window=" .. tostring(rejection) .. " name=" .. tostring(name))
      return refuse(prose, "CONFIRMATION_REQUIRED")
    end
  end
  if BYPASS_STATE_VALIDATION[name]
    and not is_in_active_force(name, state_name)
    and not Actions.is_action_valid(name) then
    send_correction(bridge, "unavailable name=" .. tostring(name))
    return refuse(string.format("Action '%s' is currently unavailable due to game conditions.", name), "ACTION_UNAVAILABLE")
  end
  local skip_cooldown = in_force
  if not skip_cooldown then
    local ok_cd, cd_err = check_cooldown(name, state_name)
    if not ok_cd then
      send_correction(bridge, "throttle")
      return refuse(cd_err, "TRANSITION_PENDING")
    end
  end
  local ok_repeat, repeat_err = check_repeat(name, state_name, payload)
  if not ok_repeat then
    send_correction(bridge, "throttle_repeat")
    if skip_cooldown then
      return refuse("Nothing happened: " .. repeat_err .. " The game state is unchanged.",
        "POLICY_ACKNOWLEDGED")
    end
    return refuse(repeat_err, "POLICY_REJECTED")
  end
  if not skip_cooldown then
    commit_cooldown(name)
  end
  return true
end

function Enforce.post_action(_bridge, _ok)
end

function Enforce.on_error(_bridge)
end

function Enforce.reset_streaks()
  streak_snapshot = nil
  cooldown_snapshot = nil
  tracker.rejects = {}
  tracker.reject_epoch = nil
  tracker.reject_total = 0
  tracker.last_action = nil
  tracker.last_payload = nil
  tracker.repeat_count = 0
  tracker.junk_action = nil
  tracker.junk_count = 0
  Metrics.set("throttle_repeat", 0)
end

function Enforce.reset_run_state()
  pending_correction = nil
  Enforce.reset_streaks()
  tracker.per_action_last = {}
  tracker.last_state = nil
  tracker.last_refresh_at = 0
  tracker.last_refresh_state = nil
  tracker.last_any_action_at = 0
end

return Enforce
