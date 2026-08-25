local M = {}

local Actions = require("core.actions")
local StateKinds = require("core.state_kinds")
local ForceState = require("core.force_state")
local TransitionGuard = require("core.transition_guard")

local function index_range(count)
  count = tonumber(count) or 0
  return count > 0 and ("1-" .. count) or "none"
end

local function collect_actions(names)
  local list, set, accepted = {}, {}, {}
  for _, name in ipairs(names or {}) do
    if Actions.is_action_valid(name) then
      list[#list + 1] = name
      set[name] = true
      if not TransitionGuard.reject_reason(name) then accepted[name] = true end
    end
  end
  return list, set, accepted
end

local once_until = require("util.once").once_until

-- The correction is an imperative about one instant; it rides this query because every force
-- declares ephemeral_context, so SPECIFICATION.md:156 has Neuro forget it when the force completes.
local function failed_action_warning()
  if not (G and G.NEURO and G.NEURO.last_failed_action) then return "" end
  local base = "Previous action rejected by game: " .. G.NEURO.last_failed_action
  local correction = G.NEURO.last_failed_correction
  local reason = G.NEURO.last_failed_reason
  if (type(correction) ~= "string" or correction == "") and type(reason) == "string" and reason ~= "" then
    base = base .. " (" .. reason .. ")"
  end
  base = base .. ". "
  if type(correction) == "string" and correction ~= "" then base = base .. correction .. " " end
  return base
end

local function repeat_pressured()
  local ok_e, Enforce = pcall(require, "core.enforce")
  if not ok_e or not Enforce or not Enforce.repeat_pressure then return nil end
  local ok_p, name, count = pcall(Enforce.repeat_pressure)
  if not ok_p or not name then return nil end
  return name, count
end

local function pending_gate_note(names)
  local ok_dw, DecisionWindow = pcall(require, "core.decision_window")
  if not ok_dw or not DecisionWindow or not DecisionWindow.would_reject then return "" end
  local pressured = repeat_pressured()
  local gated = {}
  for _, name in ipairs(names or {}) do
    if name ~= pressured then
      local ok_q, blocked = pcall(DecisionWindow.would_reject, name)
      if ok_q and blocked then gated[#gated + 1] = name end
    end
  end
  if #gated == 0 then return "" end
  return string.format(
    "%s %s a confirmation on the first send: it explains what is at stake and changes nothing, and an identical repeat carries it out. ",
    table.concat(gated, " and "), #gated == 1 and "returns" or "return")
end

local function repeat_pressure_note()
  local name, count = repeat_pressured()
  if not name then return "" end
  return string.format(
    "You have sent %s with the same parameters %d times in a row; another identical send is refused and changes nothing. Different parameters start over. ",
    name, count)
end

local DeckNames = require("facts.deck_names")
local get_back_display_name = DeckNames.get_back_display_name
local deck_name_of = DeckNames.deck_name_of

local function menu_action_tree_query(offered)
  offered = offered or {}
  local parts = {
    "Action tree:",
    "MENU -> setup_run (opens run setup screen to choose deck, stake, seed).",
    "MENU -> change_selected_back (pick a deck by key).",
    "MENU -> change_stake (adjust stake).",
  }
  if Actions.is_action_valid("copy_seed") then
    parts[#parts + 1] = "MENU -> copy_seed (copy the current seed)."
  end
  if offered.change_challenge_description then
    parts[#parts + 1] = "MENU -> change_challenge_description then start_challenge_run (only when challenges are listed)."
  end
  return table.concat(parts, " ")
end

local function hiyori_persona_gate()
  if G and G.NEURO and G.NEURO.persona == "hiyori" then
    return {
      query = "State: LOGIN. Identity not selected. Use choose_persona with persona='neuro' for Neuro-sama or 'evil' for Evil Neuro.",
      actions = { "choose_persona" }
    }
  end
  return nil
end

M.collect_actions = collect_actions
M.index_range = index_range
function M.joker_full_warn(js, negative_ok)
  local tail = negative_ok and "Negative edition jokers bypass this limit. "
    or "Non-Negative jokers require an open joker slot. Selling frees one immediately, but is permanent. "
  return string.format("Joker slots FULL (%d/%d). ", js.count, js.limit) .. tail
end
M.once_until = once_until
M.failed_action_warning = failed_action_warning
M.pending_gate_note = pending_gate_note
M.repeat_pressure_note = repeat_pressure_note
M.get_back_display_name = get_back_display_name
M.deck_name_of = deck_name_of
M.menu_action_tree_query = menu_action_tree_query
M.is_run_setup_overlay = StateKinds.is_run_setup_overlay
M.hiyori_persona_gate = hiyori_persona_gate

M.set_action_phase = ForceState.set_action_phase
M.clear_force_state = ForceState.clear_force_state
local BLOCKING_STATES = {
  BLIND_SELECT = true, ROUND_EVAL = true, GAME_OVER = true,
}

function M.force_priority(state_name, overlay_block)
  if (overlay_block and state_name ~= "RUN_SETUP") or state_name == "GAME_OVER" then return "high" end
  if BLOCKING_STATES[state_name] or StateKinds.is_pack_state(tostring(state_name or "")) then
    return "medium"
  end
  return "low"
end

M.invalidate = ForceState.invalidate
M.rearm = ForceState.rearm
M.snapshot_once_serials = ForceState.snapshot_once_serials
M.restore_once_serials = ForceState.restore_once_serials
M.record_failure = ForceState.record_failure
M.force_is_stale = ForceState.force_is_stale

return M
