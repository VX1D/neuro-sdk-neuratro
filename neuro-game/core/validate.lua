local M = {}

local json = require("util.neuro_json")
local Utils = require("util.utils")
local Metrics = require("util.metrics")
local Wire = require("core.bridge").wire
local Tx = require("core.bridge").tx
local Actions = require("core.actions")
local ActionRegistry = require("core.action_registry")
local ActionResult = require("core.action_result")
local ActionPolicy = require("core.action_policy")
local StateKinds = require("core.state_kinds")
local State = require("core.state")
local Gate = require("core.gate")
local PlanTransaction = require("core.plan_transaction")
local Window = require("core.window")
local Execute = require("core.execute")
local SchemaValidate = require("util.schema_validate")
local CardArea = require("facts.card_area_util")


local STOP_USE_GATED = { use_consumable = true, use_directional_consumable = true,
  choose_pack_card = true, choose_directional_pack_card = true, skip_pack = true, sell_card = true }
local PLAY_AREA_GATED = { use_consumable = true, use_directional_consumable = true,
  choose_pack_card = true, choose_directional_pack_card = true, sell_card = true }
local UI_GATED = {
  play_hand = true, discard_hand = true, resolve_play = true,
  use_consumable = true, use_directional_consumable = true,
  choose_pack_card = true, choose_directional_pack_card = true, skip_pack = true,
  buy_from_shop = true, sell_card = true, reroll_shop = true, leave_shop = true,
  select_blind = true, skip_blind = true, reroll_boss = true, cash_out = true, set_joker_order = true,
  open_run_setup = true, select_deck = true, select_stake = true, toggle_seeded_run = true,
  paste_seed = true, start_run = true, select_challenge = true, start_challenge_run = true,
}
local LOCK = { leave_shop = "leave_shop", reroll_shop = "shop_reroll", skip_blind = "skip_blind", select_blind = "skip_blind" }
local LATCH = { cash_out = 1.0, select_blind = 0.8, reroll_boss = 0.5, skip_pack = 0.8 }
local LOCK_LEAK_S = 5.0

local BUSY = "The game is still resolving an earlier move or effect on screen, so nothing was applied."
local ENGINE_BUSY = "The game is busy with something on screen, so nothing was applied."

local latched, lock_seen, blocked_since = {}, {}, {}
local engine_failsafe_open = false

function M.stop_use_active()
  return not not (G and G.GAME and (tonumber(G.GAME.STOP_USE) or 0) > 0)
end

local function outlived(key, blocked)
  if not blocked then
    blocked_since[key] = nil
    return false
  end
  local t = Utils.gate_now("engine_gate_failsafe")
  blocked_since[key] = blocked_since[key] or t
  return t - blocked_since[key] >= Utils.gate_seconds("engine_gate_failsafe", "NEURO_ENGINE_GATE_FAILSAFE")
end

function M.engine_ready()
  local blocked = not Utils.engine_settled() or not not (G and G.CONTROLLER and G.CONTROLLER.locked)
    or M.stop_use_active()
  engine_failsafe_open = outlived("engine", blocked)
  return not blocked or engine_failsafe_open
end

local function blind_blocks_play()
  return not not (G.GAME and G.GAME.blind and G.GAME.blind.block_play)
end

function M.hand_settled()
  local resolving = not not ((G.play and type(G.play.cards) == "table" and #G.play.cards > 0) or blind_blocks_play())
  return outlived("hand", resolving) or not resolving
end

local function fresh_hold(key, held)
  if not held then
    lock_seen[key] = nil
    return false
  end
  local t = Utils.gate_now("controller_lock_leak")
  local e = lock_seen[key]
  if not e or t - e.last > LOCK_LEAK_S then e = { first = t } end
  e.last = t
  lock_seen[key] = e
  return t - e.first < LOCK_LEAK_S
end

local function controller_blocked()
  local c = G and G.CONTROLLER
  if type(c) ~= "table" then return false end
  local locks = type(c.locks) == "table" and c.locks or {}
  if locks.frame then return true end
  local locked = not not c.locked
  for _, held in pairs(locks) do locked = locked or not not held end
  if not locked then return false end
  return not (G.SETTINGS and G.SETTINGS.paused) or not not G.screenwipe
end

function M.settling(name)
  if STOP_USE_GATED[name] and M.stop_use_active() and not engine_failsafe_open then return BUSY end
  local lock = LOCK[name]
  local named = lock and G and G.CONTROLLER and G.CONTROLLER.locks and fresh_hold(lock, G.CONTROLLER.locks[lock])
  local controller, play
  if UI_GATED[name] then
    controller = fresh_hold("controller", controller_blocked()) and not engine_failsafe_open
    play = PLAY_AREA_GATED[name] and fresh_hold("play_area",
      type(G.play) == "table" and type(G.play.cards) == "table" and #G.play.cards > 0)
    play = play or (name == "play_hand" and fresh_hold("block_play", blind_blocks_play()))
  end
  if named then return BUSY end
  if controller or play then return ENGINE_BUSY end
  local t = latched[name]
  if t and Utils.gate_now("action_settle_latch") - t < LATCH[name] then return BUSY end
  return nil
end


local DEFAULT_MAX_REPEAT = 3
local UNGATED = { exit_overlay_menu = true }

local tracker = {}

local ACTION_PROPS, NESTED_PROPS, PROSE_FIELDS = {}, {}, {}
local function collect_prose(schema, out)
  if type(schema) ~= "table" then return end
  for key, sub in pairs(schema.properties or {}) do
    if type(sub) == "table" and sub.type == "string" and sub.maxLength
        and sub.enum == nil and sub.const == nil and sub.pattern == nil then
      out[key] = true
    end
    collect_prose(sub, out)
  end
  collect_prose(schema.items, out)
end
for _, def in ipairs(ActionRegistry.definitions()) do
  local props = def.schema and def.schema.properties
  if type(props) == "table" then
    ACTION_PROPS[def.name], NESTED_PROPS[def.name] = {}, {}
    for key, sub in pairs(props) do
      ACTION_PROPS[def.name][key] = true
      for inner in pairs(type(sub) == "table" and type(sub.properties) == "table" and sub.properties or {}) do
        NESTED_PROPS[def.name][inner] = key
      end
    end
  end
  PROSE_FIELDS[def.name] = {}
  collect_prose(def.schema, PROSE_FIELDS[def.name])
end

local IGNORED_FIELDS = { plan = true, name = true }
local ORDERLESS_ARRAYS = { indices = true, hand_indices = true, intents = true }

local function canonical(value, field, prose)
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  if #value > 0 then
    local parts = {}
    for i = 1, #value do parts[i] = canonical(value[i], nil, prose) end
    if ORDERLESS_ARRAYS[field] then table.sort(parts) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(value) do
    if not IGNORED_FIELDS[k] and not prose[k] then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  for i, k in ipairs(keys) do keys[i] = k .. "=" .. canonical(value[k], k, prose) end
  return "{" .. table.concat(keys, ",") .. "}"
end

local function payload_key(name, data)
  local declared, kept = ACTION_PROPS[name], {}
  for key, value in pairs(data) do
    if not declared or declared[key] then kept[key] = value end
  end
  return canonical(kept, nil, PROSE_FIELDS[name] or {})
end

local function max_repeat(state_name, name)
  if StateKinds.is_menu_state(state_name) then return 15 end
  if state_name == "SELECTING_HAND" and (name == "play_hand" or name == "discard_hand" or name == "resolve_play") then
    return 30
  end
  if state_name == "BLIND_SELECT" and (name == "select_blind" or name == "skip_blind") then return 6 end
  if state_name == "SHOP" and name == "reroll_shop" then
    local ok, facts = pcall(require("facts.economy_facts").reroll_facts)
    if ok and facts and type(facts.max_affordable) == "number" then return math.max(1, facts.max_affordable) end
  end
  if name == "buy_from_shop" or name == "sell_card" or name == "use_consumable" or name == "use_directional_consumable"
      or name == "choose_pack_card" or name == "choose_directional_pack_card" then
    return 20
  end
  return DEFAULT_MAX_REPEAT
end

local function track_state(state_name)
  if tracker.state == state_name then return end
  tracker.state, tracker.streak = state_name, nil
end

function M.repeat_rule(name)
  local fields = {}
  for key in pairs(ACTION_PROPS[name] or {}) do
    if not (IGNORED_FIELDS[key] or (PROSE_FIELDS[name] or {})[key]) then fields[#fields + 1] = tostring(key) end
  end
  table.sort(fields)
  local s = "plan and free-text fields do not make a send different; only an accepted send of another action, "
  if #fields > 0 then s = s .. "a change to " .. table.concat(fields, "/") .. ", " end
  return s .. "or a new screen restarts the count"
end

local function next_streak(state_name, name, data)
  track_state(state_name)
  local key, streak = payload_key(name, data), tracker.streak
  if streak and streak.name == name and streak.key == key then
    return { name = name, key = key, count = streak.count + 1, cap = streak.cap }
  end
  return { name = name, key = key, count = 1, cap = max_repeat(state_name, name) }
end

function M.repeat_pressure()
  local state_name = State.get_state_name()
  local streak = tracker.streak
  if tracker.state ~= state_name or not streak or streak.count < streak.cap then return nil end
  return streak.name, streak.count
end

local function note_answered()
  local n = G and G.NEURO
  if n then n.answered_decisions = (tonumber(n.answered_decisions) or 0) + 1 end
end

function M.note_accepted(job)
  note_answered()
  local state_name = State.get_state_name()
  track_state(state_name)
  if job.streak then tracker.streak = job.streak end
  Metrics.set("throttle_repeat", job.streak and job.streak.count or 0)
  if LATCH[job.name] then latched[job.name] = nil end
end

function M.note_applied(name)
  if LATCH[name] then latched[name] = Utils.gate_now("action_settle_latch") end
end

local AWAIT_STATE = "Wait for the updated game state, then choose again."

function M.busy_reason(name, bridge)
  local job = Execute.busy()
  if job then
    return job == "staged" and "Your previous accepted action is about to run, so nothing was applied."
      or "The previous accepted action is still being verified, so nothing was applied.", AWAIT_STATE
  end
  bridge = bridge or (G and G.NEURO)
  if bridge and bridge.is_transition_cooldown and bridge:is_transition_cooldown() then
    return "The game is still transitioning between screens, so nothing was applied."
  end
  return M.settling(name)
end

function M.reset_streaks()
  tracker.streak = nil
  Metrics.set("throttle_repeat", 0)
end

function M.reset_run_state()
  M.reset_streaks()
  tracker.state = nil
  latched, lock_seen, blocked_since, engine_failsafe_open = {}, {}, {}, false
end


local CODE_REMEDY = {
  NO_SLOT = "Nothing was bought and no money moved.",
  INSUFFICIENT_FUNDS = "Nothing was bought and no money moved: sell a card for cash, take a cheaper row, or leave the shop and bank what you have.",
}

local function sentence(text)
  text = tostring(text or "")
  if text == "" or text:find("[%.!?]%s*$") then return text end
  return text .. "."
end

local function with_remedy(code, message)
  local remedy = CODE_REMEDY[code]
  message = tostring(message or "")
  if not remedy or message:find(remedy, 1, true) then return message end
  return (message ~= "" and (sentence(message) .. " ") or "") .. remedy
end

local function refuse(bridge, id, name, rejection, forced)
  local code = rejection.reason_code
  if ActionResult.unrecognised(code) then
    return Execute.answer(bridge, id, name, false, rejection.message, code)
  end
  local success = ActionResult.terminal(code, forced)
  local message = with_remedy(code, rejection.message)
  if code == "CONFIRMATION_REQUIRED" then
    message = Gate.result_message(rejection)
  elseif success and rejection.reasked then
    message = ActionResult.reasked_message(rejection)
  end
  local Lifecycle = require("core.neuro_lifecycle")
  if success then Lifecycle.clear_failure() else Lifecycle.record_failure(name, message) end
  local delivered = Execute.answer(bridge, id, name, success, message, code)
  if delivered and code == "CONFIRMATION_REQUIRED" then Gate.delivered(rejection, rejection.message) end
  if delivered and success then note_answered() end
  if delivered and success and code ~= "CONFIRMATION_REQUIRED" then Execute.note_unchanged(name) end
  return delivered
end

local function reject(bridge, id, name, code, message, forced)
  refuse(bridge, id, name, ActionResult.error(code, message), forced)
  return nil
end


local function strip_nulls(data, schema, depth)
  depth = (depth or 0) + 1
  if depth > 8 or type(data) ~= "table" or type(schema) ~= "table" then return end
  for key, sub in pairs(schema.properties or {}) do
    local value = data[key]
    if json.is_null(value) and not SchemaValidate.permits_null(sub) then
      data[key] = nil
    elseif type(value) == "table" then
      strip_nulls(value, sub, depth)
    end
  end
  if type(schema.items) == "table" then
    for i = 1, #data do
      if type(data[i]) == "table" and not json.is_null(data[i]) then strip_nulls(data[i], schema.items, depth) end
    end
  end
end

local function internal_field(value, path)
  if type(value) ~= "table" then return nil end
  for key, child in pairs(value) do
    if type(key) == "string" and key:sub(1, 1) == "_" then return path .. "." .. key end
    local nested = internal_field(child, path .. "." .. tostring(key))
    if nested then return nested end
  end
  return nil
end

local function decode(payload, schema)
  if payload == nil or json.is_null(payload) or payload == "" then return json.object({}) end
  local shape = " " .. SchemaValidate.payload_shape(schema)
  if type(payload) ~= "string" then return nil, ActionResult.SDK.INVALID_JSON .. shape end
  local ok, decoded = pcall(json.decode, payload)
  if not ok then return nil, ActionResult.SDK.INVALID_JSON .. shape end
  if type(decoded) == "table" and SchemaValidate.is_object_table(decoded) then return decoded end
  return nil, "Action parameters must be a JSON object." .. shape
end

local ACTION_NAME_DISPLAY_MAX = 256
local CONFIRMATION_FIELDS_ONLY = "This review accepts only answer: yes or no."

local function unregistered(bridge, id, name)
  local now = ActionRegistry.now()
  ActionRegistry.prune(now)
  local message, code
  -- The reference SDK's own replies (dev/Unity/Assets/Messages/Incoming/Action.cs:52-59), word for word.
  if ActionRegistry.is_withdrawn(name) and ActionRegistry.is_recently_unregistered(name, now) then
    message, code = ActionResult.SDK.UNREGISTERED, "ACTION_UNREGISTERED"
    Metrics.incr("action_recently_unregistered")
  elseif name == Wire.INVALID_ACTION_NAME then
    message, code = ActionResult.SDK.NO_NAME, "ACTION_UNKNOWN"
    Metrics.incr("action_name_unusable")
  else
    local shown = #name <= ACTION_NAME_DISPLAY_MAX and name or (name:sub(1, ACTION_NAME_DISPLAY_MAX) .. " [truncated]")
    message, code = string.format(ActionResult.SDK.UNKNOWN_ACTION, shown), "ACTION_UNKNOWN"
    Metrics.incr(ActionRegistry.get(name) and "action_withdrawn" or "action_unknown")
  end
  return reject(bridge, id, name, code, message, false)
end

local UNMODELLED_OFFER = { start_run = true, start_challenge_run = true }
local function unmodelled(state_name) return not state_name or state_name == "UNKNOWN" end

local function offered_moves(state_name, except)
  local phrases = {}
  for _, name in ipairs(Actions.get_valid_actions_for_state(state_name)) do
    if name ~= except and ActionRegistry.is_registered(name) then phrases[#phrases + 1] = ActionRegistry.phrase(name) end
  end
  return phrases
end

local OFF_SCREEN_HINT = {
  record_plan = "Your plan is recorded at blind select, after the round or in the shop; "
    .. "on a Boss round a play or discard can carry plan.boss_plan.",
}

local LISTS_USABLE_MOVES = { exit_overlay_menu = true }

local function moves_sentence(label, moves)
  return #moves > 0 and (" The moves " .. label .. ": " .. table.concat(moves, "; ") .. ".") or ""
end

local function screen_move(name, state_name)
  return Actions.get_state_action_set(state_name)[name] or (UNMODELLED_OFFER[name] and unmodelled(state_name))
end

local function unavailable_message(name, state_name, data)
  if screen_move(name, state_name) then
    local usable = LISTS_USABLE_MOVES[name] and offered_moves(state_name, name) or {}
    return "That move can't be used right now. "
      .. (Actions.unavailable_reason(name, data) or "Choose from the moves you are offered.")
      .. moves_sentence("you can use now", usable)
  end
  local hint = OFF_SCREEN_HINT[name] and (" " .. OFF_SCREEN_HINT[name]) or ""
  local offer = offered_moves(state_name)
  if #offer == 0 then return "That move isn't part of this screen." .. hint .. " Choose from the moves you are offered." end
  return "That move isn't part of this screen." .. hint .. moves_sentence("offered now", offer)
end

local function unavailable(name, state_name, data)
  if screen_move(name, state_name) then
    local rejection = Actions.unavailable_rejection(name, data)
    if ActionResult.is_error(rejection) then return rejection end
  end
  return ActionResult.error("ACTION_UNAVAILABLE", unavailable_message(name, state_name, data))
end

local function off_screen(name, state_name)
  local screen = Actions.screen_action_set(state_name)
  return screen ~= nil and not screen[name]
end

local function offered(name, state_name)
  for _, candidate in ipairs(Actions.get_valid_actions_for_state(state_name)) do
    if candidate == name then return true end
  end
  return unmodelled(state_name) and UNMODELLED_OFFER[name] == true and Actions.is_action_valid(name)
end

local function note_hold(rejection, ...)
  if rejection.reason_code ~= "CONFIRMATION_REQUIRED" then return rejection end
  local parts = {}
  for i = 1, select("#", ...) do
    local note = select(i, ...)
    if note then parts[#parts + 1] = note end
  end
  if #parts > 0 then rejection.note = table.concat(parts, " ") end
  return rejection
end

local function refuse_preflight(bridge, id, name, rejection, forced, tx, weak_fired, field_note)
  local proposal = rejection.proposal ~= nil and rejection.reason_code == "CONFIRMATION_REQUIRED"
  if name ~= "resolve_play" and not proposal then PlanTransaction.hold(tx) end
  if refuse(bridge, id, name, note_hold(rejection, type(tx) == "table" and tx.ignored_note or nil, field_note),
      forced) == false then
    if G and G.NEURO then G.NEURO.weak_fired_serial = weak_fired end
    return nil
  end
  if proposal and Gate.proposal() then PlanTransaction.hold(tx, Gate.proposal_ref()) end
  return nil
end


local function parameters(msg, bridge, name)
  Actions.get_static_actions()
  local schema = (ActionRegistry.get(name) or {}).schema or {}
  local data, malformed = decode(msg.data.data, schema)
  if not data then return nil, ActionResult.error("SCHEMA_INVALID", malformed) end
  local hidden_field = internal_field(data, "parameters")
  if hidden_field then
    return nil, ActionResult.error("SCHEMA_INVALID",
      "Invalid action parameters: internal field '" .. hidden_field .. "' is not accepted.")
  end
  if type(data.area) == "string" then data.area = CardArea.AREA_ALIASES[data.area] or data.area end
  if name == "resolve_play" then
    for key in pairs(data) do
      if key ~= "answer" then return nil, ActionResult.error("SCHEMA_INVALID", CONFIRMATION_FIELDS_ONLY) end
    end
    local tx = Gate.proposal()
    local has_ref = bridge and type(bridge.confirmation_proposal_ref) == "function"
    local ok_ref, active = true, nil
    if has_ref then ok_ref, active = pcall(bridge.confirmation_proposal_ref, bridge, msg.data.id) end
    if not tx or (has_ref and (not ok_ref or active ~= tx.ref)) then
      return nil, ActionResult.error("POLICY_ACKNOWLEDGED",
        "This confirmation is stale or no longer offered; nothing was applied. Choose the currently offered confirmation action.")
    end
  end
  local ok_schema, schema_err = SchemaValidate.validate_value(schema, data, "parameters")
  if not ok_schema then
    return nil, ActionResult.error("SCHEMA_INVALID", "Invalid action parameters: " .. schema_err)
  end
  strip_nulls(data, schema)
  data._action_name = name
  return data
end

local function admission(name, data, forced, state_name)
  if name ~= "resolve_play" and Gate.stale_mutator(name) then
    return ActionResult.error("POLICY_ACKNOWLEDGED",
      "A play review is awaiting your answer; this move was acknowledged without changing anything. Answer the review first.")
  end
  local overlay = Actions.overlay_block_reason(name)
  if overlay and forced then return ActionResult.wait(Actions.OVERLAY_FACT, Actions.OVERLAY_RETRY, Actions.OVERLAY_REASKED) end
  if overlay then return ActionResult.error("ACTION_UNAVAILABLE", overlay) end
  if not offered(name, state_name) then return unavailable(name, state_name, data) end
  local review = Gate.check("admission", name, data)
  if review then return review end
  local streak = not UNGATED[name] and next_streak(state_name, name, data) or nil
  if streak and streak.count > streak.cap then
    Metrics.set("throttle_repeat", streak.count - 1)
    local text = string.format("Action '%s' repeated %d times (max %d) with the same parameters; "
      .. "this send is refused and changed nothing. %s.", name, streak.count - 1, streak.cap,
      (M.repeat_rule(name):gsub("^%l", string.upper)))
    if forced then
      return ActionResult.error("POLICY_ACKNOWLEDGED", "Nothing happened: " .. text .. " The game state is unchanged.")
    end
    return ActionResult.error("POLICY_REJECTED", text)
  end
  return nil, streak
end

local function plan_refusal(name, data, tx_err)
  local plan = ActionResult.normalize(tx_err, "PRECONDITION_FAILED")
  local n = G and G.NEURO
  if n then n._candidate_probe = true end
  local ok, exec, err = pcall(require("core.dispatcher").preflight, name, data)
  if n then n._candidate_probe = nil end
  if not ok or exec or ActionResult.terminal(type(err) == "table" and err.reason_code or nil) then return plan end
  local target = ActionResult.normalize(err or "That action does not apply on the current screen.", "ACTION_REJECTED")
  target.message = target.message .. " " .. plan.message
  return target
end

local function unknown_fields_note(name, data)
  local declared, nested, unknown, misplaced = ACTION_PROPS[name] or {}, NESTED_PROPS[name] or {}, {}, {}
  local accepted = require("handlers.plan_handlers").ACCEPTED_UNDECLARED[name] or {}
  for key in pairs(data) do
    if type(key) == "string" and key:sub(1, 1) ~= "_" and not declared[key] and not accepted[key] then
      if nested[key] then misplaced[#misplaced + 1] = key else unknown[#unknown + 1] = key end
    end
  end
  table.sort(unknown)
  table.sort(misplaced)
  local notes = {}
  if #unknown > 0 then
    notes[#notes + 1] = "Not used: " .. table.concat(unknown, ", ")
      .. (#unknown == 1 and " is not a parameter of this move." or " are not parameters of this move.")
  end
  for _, key in ipairs(misplaced) do
    notes[#notes + 1] = string.format("Not saved: %s belongs under %s; send it as %s.%s.",
      key, nested[key], nested[key], key)
  end
  return #notes > 0 and table.concat(notes, " ") or nil
end

function M.validate(msg, bridge)
  local id, name = msg.data.id, msg.data.name
  if Tx.get(id) then
    Metrics.incr("action_result_duplicate_suppressed")
    return nil
  end
  Window.on_response()
  local forced = Window.forced(name)
  if type(name) ~= "string" or name == "" then
    return reject(bridge, id, "<missing-action-name>", "ACTION_UNKNOWN", ActionResult.SDK.NO_NAME, false)
  end
  if not ActionRegistry.is_registered(name) then return unregistered(bridge, id, name) end
  if G and G.NEURO and G.NEURO.llm_paused then
    Execute.answer(bridge, id, name, true,
      "Paused by operator -- nothing happened. Wait; you will be asked again shortly.", "TRANSITION_PENDING")
    return nil
  end
  local state_name = State.get_state_name()
  local busy, retry = M.busy_reason(name, bridge)
  if busy then
    refuse(bridge, id, name, ActionResult.wait(busy, retry), forced)
    return nil
  end
  local overlay_move = Utils.list_to_set(Actions.overlay_actions(state_name) or {})[name]
  if not overlay_move and not unmodelled(state_name) and not Actions.screen_action_set(state_name) then
    refuse(bridge, id, name, ActionResult.wait("The game is still changing screens, so nothing was applied."), forced)
    return nil
  end
  if off_screen(name, state_name) then
    refuse(bridge, id, name, unavailable(name, state_name), forced)
    return nil
  end
  local data, bad = parameters(msg, bridge, name)
  if not data then
    refuse(bridge, id, name, bad, forced)
    return nil
  end
  local field_note = unknown_fields_note(name, data)
  local rejection, streak = admission(name, data, forced, state_name)
  if rejection then
    refuse(bridge, id, name, note_hold(rejection, PlanTransaction.ignored_note(name, data), field_note), forced)
    return nil
  end

  data._action_id = id
  local tx, tx_err = PlanTransaction.prepare(name, data)
  if tx_err then
    refuse(bridge, id, name, note_hold(plan_refusal(name, data, tx_err), field_note), forced)
    return nil
  end
  local weak_fired = G and G.NEURO and G.NEURO.weak_fired_serial
  local ok_preflight, exec, err, gameplay_event = pcall(require("core.dispatcher").preflight, name, data)
  if not ok_preflight then
    print("[neuro-game] preflight error for " .. tostring(name) .. ": " .. tostring(exec))
    exec, err = nil, ActionResult.internal_error()
  end
  if not exec then
    local refusal = ActionResult.normalize(err or "That action does not apply on the current screen, so nothing ran. Choose one of the actions you are offered now.",
      ok_preflight and "ACTION_REJECTED" or "INTERNAL_ERROR")
    return refuse_preflight(bridge, id, name, refusal, forced, tx, weak_fired, field_note)
  end

  local ends_pack = name == "skip_pack" or ((name == "choose_pack_card" or name == "choose_directional_pack_card")
    and (tonumber(G and G.GAME and G.GAME.pack_choices) or 0) <= 1)
  return {
    id = id, name = name, data = data, exec = exec, bridge = bridge, forced = forced, streak = streak,
    state = state_name, run_generation = G and G.NEURO and G.NEURO.run_generation,
    tx = tx, weak_fired = weak_fired, gameplay_event = gameplay_event,
    ack_snapshot = Gate.snapshot(name), ends_pack = ends_pack,
    disposable = ActionPolicy.disposable_group(name), field_note = field_note,
  }
end

function M.crashed(bridge, id, name)
  if Tx.get(id) then return end
  local fault = ActionResult.internal_error()
  Execute.answer(bridge, id, name, false, fault.message, fault.reason_code)
end

if rawget(_G, "NEURO_TEST") then
  M._test = { admission = admission }
end

return M
