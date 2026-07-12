local M = {}

local Actions = require("core.actions")
local StateKinds = require("core.state_kinds")
local ForceState = require("core.force_state")

local function collect_actions(names)
  local list, set = {}, {}
  for _, name in ipairs(names or {}) do
    if Actions.is_action_valid(name) then
      list[#list + 1] = name
      set[name] = true
    end
  end
  return list, set
end

local once_until = require("util.once").once_until

local function failed_action_warning()
  if not (G and G.NEURO and G.NEURO.last_failed_action) then return "" end
  local base = "Previous action rejected by game: " .. G.NEURO.last_failed_action
  local reason = G.NEURO.last_failed_reason
  if type(reason) == "string" and reason ~= "" then base = base .. " (" .. reason .. ")" end
  return base .. ". "
end

local DeckNames = require("facts.deck_names")
local get_back_display_name = DeckNames.get_back_display_name
local deck_name_of = DeckNames.deck_name_of

local function menu_action_tree_query()
  local parts = {
    "Action tree:",
    "MENU -> setup_run (opens run setup screen to choose deck, stake, seed).",
    "MENU -> change_selected_back (pick a deck by key).",
    "MENU -> change_stake (adjust stake).",
    "MENU -> copy_seed (copy the current seed).",
    "MENU -> help.",
    "MENU -> change_challenge_description then start_challenge_run (only when challenges are listed).",
  }
  return table.concat(parts, " ")
end

local function hiyori_persona_gate()
  if G and G.NEURO and G.NEURO.persona == "hiyori" then
    return {
      query = "Identity not selected. Use choose_persona with persona='neuro' for Neuro-sama or 'evil' for Evil Neuro.",
      actions = { "choose_persona" }
    }
  end
  return nil
end

M.collect_actions = collect_actions
function M.joker_full_warn(js, negative_ok)
  local tail = negative_ok and "Negative edition jokers bypass this limit. "
    or "Non-Negative jokers require an open joker slot. Selling a joker frees its slot immediately, but selling is permanent -- the card is gone for the run, so keep jokers that work with your others. "
  return string.format("Joker slots FULL (%d/%d). ", js.count, js.limit) .. tail
end
M.once_until = once_until
M.failed_action_warning = failed_action_warning
M.get_back_display_name = get_back_display_name
M.deck_name_of = deck_name_of
M.menu_action_tree_query = menu_action_tree_query
M.is_run_setup_overlay = StateKinds.is_run_setup_overlay
M.hiyori_persona_gate = hiyori_persona_gate

M.is_forced_action = ForceState.is_forced_action
M.set_action_phase = ForceState.set_action_phase
M.clear_force_state = ForceState.clear_force_state
M.is_inflight = ForceState.is_inflight
M.drop_fingerprint = ForceState.drop_fingerprint
M.arm = ForceState.arm
M.supersede = ForceState.supersede
M.stall = ForceState.stall
M.mark_answered = ForceState.mark_answered
M.rearm = ForceState.rearm
M.snapshot_once_serials = ForceState.snapshot_once_serials
M.restore_once_serials = ForceState.restore_once_serials
M.record_failure = ForceState.record_failure
M.correct_optimistic = ForceState.correct_optimistic
M.force_is_stale = ForceState.force_is_stale

return M
