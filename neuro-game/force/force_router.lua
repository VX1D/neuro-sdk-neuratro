local Actions = require("core.actions")
local ActionPolicy = require("core.action_policy")
local StateKinds = require("core.state_kinds")
local ForceHelpers = require("force.force_helpers")
local MenuFlow = require("force.menu_flow")
local TransitionGuard = require("core.transition_guard")
local Utils = require("util.utils")
local Metrics = require("util.metrics")
local ForceState = require("core.force_state")
local ContextDelivery = require("core.context_delivery")

local M = {}

local function insert_after_state_segment(query, note)
  query = query or ""
  local state_prefix, rest = query:match("^(State:%s[^.]-%.%s*)(.*)$")
  if state_prefix then
    return state_prefix .. note .. rest
  end
  return note .. query
end

local function run_generation()
  return tonumber(G and G.NEURO and G.NEURO.run_generation) or 0
end

local function clear_guard_defer()
  M._guard_defer_at = nil
  M._guard_defer_state = nil
  M._guard_defer_generation = nil
end

local function clear_pack_exit_defer()
  M._pack_exit_at = nil
  M._pack_exit_generation = nil
end

local function pack_exit_suppresses(state_name)
  if not (StateKinds.is_pack_state(state_name)
      and G and G.NEURO and G.NEURO.pack_exit_pending) then
    clear_pack_exit_defer()
    return false
  end
  -- G.FUNCS.end_consumeable destroys G.booster_pack a beat before it hands the state back (dump
  -- button_callbacks.lua:2618-2622 then :2656), so a missing pack object is the exit itself, already
  -- under way, and naming pack actions again would name them on a pack that no longer exists.
  local now = Utils.gate_now("router_pack_exit_defer")
  local generation = run_generation()
  if not M._pack_exit_at or M._pack_exit_generation ~= generation or now < M._pack_exit_at then
    M._pack_exit_at = now
    M._pack_exit_generation = generation
  end
  if (now - M._pack_exit_at) < Utils.gate_seconds("router_pack_exit_defer", "NEURO_ROUTER_DEFER_FAILSAFE") then
    return true
  end
  if G.booster_pack == nil then
    G.NEURO.pack_exit_pending = nil
    local diagnostic_key = tostring(generation) .. ":" .. tostring(state_name)
    if G.NEURO.pack_transition_stall_key ~= diagnostic_key then
      G.NEURO.pack_transition_stall_key = diagnostic_key
      G.NEURO.pack_transition_stalled = { state = state_name, at = now }
      Metrics.incr("pack_transition_stalled")
      print("[neuro-game] Pack object disappeared but the engine remained in "
        .. tostring(state_name) .. " past the transition deadline")
      ContextDelivery.prompt_at("pack_transition_stall", ContextDelivery.here("state " .. tostring(state_name)),
        "Engine transition stalled after the booster pack closed. While that condition remains, no pack action is executable and the game waits for Balatro to leave the pack state.")
    end
    clear_pack_exit_defer()
    return true
  end
  G.NEURO.pack_exit_pending = nil
  clear_pack_exit_defer()
  return false
end

function M.observe_pack_exit(state_name)
  return pack_exit_suppresses(state_name)
end

local FORCE_HANDLERS = {}

FORCE_HANDLERS["SELECTING_HAND"] = require("force.force_selecting_hand").build
FORCE_HANDLERS["SHOP"] = require("force.force_shop").build
FORCE_HANDLERS["BLIND_SELECT"] = require("force.force_blind_select").build
local force_pack = require("force.force_pack").build
FORCE_HANDLERS["TAROT_PACK"] = force_pack
FORCE_HANDLERS["PLANET_PACK"] = force_pack
FORCE_HANDLERS["SPECTRAL_PACK"] = force_pack
FORCE_HANDLERS["STANDARD_PACK"] = force_pack
FORCE_HANDLERS["BUFFOON_PACK"] = force_pack
FORCE_HANDLERS["SMODS_BOOSTER_OPENED"] = force_pack

FORCE_HANDLERS["ROUND_EVAL"] = function()
  return { query = "State: ROUND_EVAL. Round complete. Your move: cash_out|{}.", actions = { "cash_out" } }
end

FORCE_HANDLERS["GAME_OVER"] = MenuFlow.game_over
FORCE_HANDLERS["SPLASH"] = MenuFlow.splash
FORCE_HANDLERS["MENU"] = MenuFlow.menu

local function build_force(state_name)
  if pack_exit_suppresses(state_name) then
    return nil
  end
  if StateKinds.is_unlock_popup() and Actions.is_action_valid("exit_overlay_menu") then
    return {
      query = "State: OVERLAY. An unlock popup is blocking the game. Use exit_overlay_menu to dismiss it "
        .. "(this also unblocks starting a new run). Your move: exit_overlay_menu|{}.",
      actions = { "exit_overlay_menu" },
    }
  end
  if state_name == "RUN_SETUP" then
    return MenuFlow.run_setup()
  end

  if not StateKinds.is_progression_overlay() and Actions.is_action_valid("exit_overlay_menu") then
    local overlay_actions = { "exit_overlay_menu" }
    if (state_name == "MENU" or state_name == "SPLASH")
        and Actions.is_action_valid("setup_run") then
      overlay_actions[#overlay_actions + 1] = "setup_run"
    end
    local overlay_tail = "Your move: exit_overlay_menu|{}"
    if overlay_actions[2] == "setup_run" then overlay_tail = overlay_tail .. "; setup_run|{}" end
    return {
      query = "State: OVERLAY. A popup is blocking the game. " .. overlay_tail .. ".",
      actions = overlay_actions,
    }
  end

  local handler = FORCE_HANDLERS[state_name]
  if not handler and StateKinds.is_pack_state(state_name) then
    handler = force_pack
  end
  if not handler then return nil end

  local hint_snapshot = ForceHelpers.snapshot_once_serials()
  local force = handler(state_name)
  if type(force) ~= "table" then
    ForceHelpers.restore_once_serials(hint_snapshot)
    return nil
  end

  local actions = force.actions or {}
  local state_set = Actions.get_state_action_set(state_name)
  local seen = {}
  local filtered = {}
  local guard_pruned = {}

  for _, name in ipairs(actions) do
    if type(name) == "string" and not seen[name] and state_set[name] and Actions.is_action_valid(name) then
      if TransitionGuard.reject_reason(name) then
        guard_pruned[#guard_pruned + 1] = name
      else
        filtered[#filtered + 1] = name
        seen[name] = true
      end
    end
  end

  local tagging_is_the_exit = false
  if state_name == "SHOP" then
    local ok_tags, untagged = pcall(function()
      return require("facts.card_util").untagged_joker_count()
    end)
    if not ok_tags then
      require("util.metrics").incr("force_tag_count_error")
      print("[neuro-game] Could not count untagged jokers while building the shop force: "
        .. tostring(untagged))
    end
    tagging_is_the_exit = not ok_tags or (tonumber(untagged) or 0) > 0
  end

  local function offers_progress()
    for _, name in ipairs(filtered) do
      if (tagging_is_the_exit and name == "set_joker_intents")
          or not ActionPolicy.NON_PROGRESS[name] then
        return true
      end
    end
    return false
  end

  local fallback
  local function absorb_fallback(respect_guard)
    fallback = fallback or Actions.get_valid_actions_for_state(state_name)
    for _, name in ipairs(fallback) do
      if type(name) == "string" and not seen[name]
          and not (respect_guard and TransitionGuard.reject_reason(name)) then
        filtered[#filtered + 1] = name
        seen[name] = true
      end
    end
  end

  local deferring = false
  local guard_note = false

  if state_name == "SELECTING_HAND" then
    local blind = G and G.GAME and G.GAME.blind
    if blind and blind.block_play and not blind.disabled then deferring = true end
  end
  if #guard_pruned > 0 then
    local filtered_can_progress = false
    for _, name in ipairs(filtered) do
      if not (ActionPolicy.FORFEIT[name] or ActionPolicy.SETTLING_NONPROGRESS[name]
          or ActionPolicy.NON_PROGRESS[name]) then
        filtered_can_progress = true; break
      end
    end
    local pruned_can_progress = false
    for _, name in ipairs(guard_pruned) do
      if not ActionPolicy.FORFEIT[name] and not ActionPolicy.NON_PROGRESS[name] then
        pruned_can_progress = true; break
      end
    end
    if #filtered > 0 and not (pruned_can_progress and not filtered_can_progress) then
      guard_note = true
    else
      deferring = true
    end
  end

  if not offers_progress() then
    absorb_fallback(true)
    if not offers_progress() then deferring = true end
  end

  local guard_overridden = false
  if deferring then
    local now = Utils.gate_now("router_guard_defer")
    local generation = run_generation()
    if M._guard_defer_state ~= state_name or not M._guard_defer_at
        or M._guard_defer_generation ~= generation or now < M._guard_defer_at then
      M._guard_defer_at = now
      M._guard_defer_state = state_name
      M._guard_defer_generation = generation
    end
    if (now - M._guard_defer_at) < Utils.gate_seconds("router_guard_defer", "NEURO_ROUTER_DEFER_FAILSAFE") then
      ForceHelpers.restore_once_serials(hint_snapshot)
      return nil
    end
    if not offers_progress() then
      for _, name in ipairs(guard_pruned) do
        if not seen[name] then
          filtered[#filtered + 1] = name
          seen[name] = true
        end
      end
      absorb_fallback(false)
      guard_overridden = true
    end
  else
    clear_guard_defer()
  end

  if guard_note and not guard_overridden then
    force.query = insert_after_state_segment(force.query,
      "NOTE: only these actions are accepted RIGHT NOW: " .. table.concat(filtered, ", ")
        .. " -- the rest are settling on screen; if you need one of them, pick a listed action or wait. ")
  end

  local progress = {}
  local ride_along = {}
  for _, name in ipairs(filtered) do
    if (tagging_is_the_exit and name == "set_joker_intents")
        or not ActionPolicy.NON_PROGRESS[name] then
      progress[#progress + 1] = name
    elseif ActionPolicy.RIDE_ALONG[name] then
      ride_along[#ride_along + 1] = name
    end
  end

  if #progress == 0 then
    ForceHelpers.restore_once_serials(hint_snapshot)
    return nil
  end
  for _, name in ipairs(ride_along) do progress[#progress + 1] = name end
  force.actions = progress
  local stalled = ForceState.liveness_stall_repeats(state_name)
  if stalled >= ForceState.LIVENESS_ESCALATE_AT then
    force.query = insert_after_state_segment(force.query,
      "NOTE: this decision has now gone unanswered " .. tostring(stalled)
        .. " times and each offer was withdrawn; nothing on the board changed and the game cannot "
        .. "continue until you answer with one of the actions below. ")
  end
  return force
end

function M.get_force_for_state(state_name)
  local TaskMode = require("core.task_mode")
  if TaskMode.active then return TaskMode.get_force() end
  return build_force(state_name)
end

return M
