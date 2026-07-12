local Actions = require("core.actions")
local ActionPolicy = require("core.action_policy")
local StateKinds = require("core.state_kinds")
local ForceHelpers = require("force.force_helpers")
local MenuFlow = require("force.menu_flow")

local M = {}

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
  return {
    query = "State: ROUND_EVAL. Round complete. Your move: cash_out|{}.",
    actions = { "cash_out" }
  }
end

FORCE_HANDLERS["GAME_OVER"] = MenuFlow.game_over
FORCE_HANDLERS["SPLASH"] = MenuFlow.splash
FORCE_HANDLERS["MENU"] = MenuFlow.menu

function M.get_force_for_state(state_name)
  if StateKinds.is_unlock_popup() and Actions.is_action_valid("exit_overlay_menu") then
    return {
      query = "An unlock popup is blocking the game. Use exit_overlay_menu to dismiss it "
        .. "(this also unblocks starting a new run). Your move: exit_overlay_menu|{}.",
      actions = { "exit_overlay_menu" },
    }
  end
  -- must precede the generic exit_overlay_menu intercept; gate on state_name, not a live probe (overlay lingers past run start -> BLIND_SELECT stuck loop)
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
      query = "A popup is blocking the game. " .. overlay_tail .. ".",
      actions = overlay_actions,
    }
  end

  local handler = FORCE_HANDLERS[state_name]
  if not handler and StateKinds.is_pack_state(state_name) then
    handler = force_pack
  end
  if not handler then return nil end

  -- refund one-shot hints consumed by a build that never ships, else a dropped force burns them for that state entry
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

  for _, name in ipairs(actions) do
    if type(name) == "string" and not seen[name] and state_set[name] and Actions.is_action_valid(name) then
      filtered[#filtered + 1] = name
      seen[name] = true
    end
  end

  if #filtered == 0 then
    local fallback = Actions.get_valid_actions_for_state(state_name)
    for _, name in ipairs(fallback) do
      if type(name) == "string" and not seen[name] then
        filtered[#filtered + 1] = name
        seen[name] = true
      end
    end
  end

  local progress = {}
  local ride_along = {}
  for _, name in ipairs(filtered) do
    if not ActionPolicy.NON_PROGRESS[name] then
      progress[#progress + 1] = name
    elseif ActionPolicy.RIDE_ALONG[name] then
      ride_along[#ride_along + 1] = name
    end
  end

  -- never force an info-only set: info actions don't clear force_inflight -> soft-loop until the stall watchdog
  if #progress == 0 then
    ForceHelpers.restore_once_serials(hint_snapshot)
    return nil
  end
  for _, name in ipairs(ride_along) do progress[#progress + 1] = name end
  force.actions = progress
  return force
end

return M
