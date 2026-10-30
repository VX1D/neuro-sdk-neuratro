local GameActions = require("core.game_actions")
local ActionResult = require("core.action_result")
local DeckFacts = require("facts.deck_facts")
local mock_UIBox = GameActions.mock_UIBox
local bound_echo = require("facts.card_area_util").bound_echo

local function find_back_by_key(pool, key)
  if not pool then return nil end
  for i, v in ipairs(pool) do
    if v.key == key then return i, v.name, v end
  end
  return nil
end

local function apply_selected_back(key)
  local idx, name, center = find_back_by_key(G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back, key)
  if not idx or not center then return nil end
  if G.GAME and G.GAME.selected_back and G.GAME.selected_back.change_to then
    G.GAME.selected_back:change_to(center)
  end
  if G.NEURO then G.NEURO.selected_back_key = key end
  return name, center
end

local function sync_run_select()
  local choices = DeckFacts.run_select_choices()
  if not choices then return end
  local rs = SMODS.RunSelect
  local center, stake = DeckFacts.run_deck_center(), DeckFacts.run_stake()
  local deck_moved = center ~= nil and choices.deck_choice ~= center.key
  local stake_key = DeckFacts.stake_key(stake)
  local stake_moved = stake_key ~= nil and choices.stake_choice ~= stake_key
  if center then choices.deck_choice = center.key end
  if stake_key then choices.stake_choice = stake_key end
  local internals, fns = rs.Internals, rs.Functions
  local page = rs.Pages[internals.pages[internals.current_page]]
  if type(page) ~= "table" then return end
  if deck_moved and (page.key == "deck_choice" or page.include_deck_preview) and internals.preview_area then
    pcall(fns.populate_preview_ui, "deck_choice", center.key, true)
  end
  if (deck_moved or stake_moved) and page.include_stake_tower and internals.stake_tower then
    pcall(fns.populate_stake_tower, stake_key, true)
  end
end

local function locked_challenge_reason(ids)
  if #ids == 0 then return "That challenge is locked, and no challenge is unlocked yet." end
  return "That challenge is locked. Unlocked challenge ids: " .. table.concat(ids, ", ") .. "."
end

local function handle_change_stake(data)
  local selectable = DeckFacts.selectable_stakes()
  local allowed = #selectable == 0
  for _, index in ipairs(selectable) do if index == data.to_key then allowed = true break end end
  if not allowed then
    return nil, string.format("Stake %d is locked for this deck. Stakes you can select: %s.",
      data.to_key, table.concat(selectable, ", "))
  end
  if DeckFacts.run_stake() == data.to_key then
    local stake = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[data.to_key]
    local name = stake and require("facts.display_names").of("Stake", stake.key, stake) or ("Stake " .. data.to_key)
    return ActionResult.unchanged(name .. " is already selected")
  end
  return function()
    G.FUNCS.change_stake({ to_key = data.to_key, to_val = data.to_key, UIBox = mock_UIBox })
    if G.NEURO then G.NEURO.selected_stake = data.to_key end
    sync_run_select()
    return ActionResult.done()
  end
end

local function handle_change_challenge_description(data)
  local id = data.id
  local idx = nil
  if not (G and G.CHALLENGES) then
    return nil, ActionResult.wait("The challenge list is not loaded yet, so nothing was selected.",
      "Wait for the challenge menu to be shown, then select the challenge again.")
  end
  for _, entry in ipairs(DeckFacts.selectable_challenges()) do
    if entry.id == id then
      idx = entry.index
      break
    end
  end
  if not idx then
    for k, v in ipairs(G.CHALLENGES) do
      if v.id == id or tostring(k) == id then
        return nil, locked_challenge_reason(DeckFacts.selectable_challenge_ids())
      end
    end
    local ids = DeckFacts.selectable_challenge_ids()
    return nil, "Challenge '" .. bound_echo(tostring(id)) .. "' not found. "
      .. (#ids > 0 and ("Use one of these ids: " .. table.concat(ids, ", ") .. ".") or "No challenge is unlocked yet.")
  end
  return function()
    G.challenge_tab = G.CHALLENGES[idx]
    pcall(G.FUNCS.change_challenge_description, { config = { id = idx }, UIBox = mock_UIBox })
    return ActionResult.done()
  end
end

local function handle_change_selected_back(data)
  local current = DeckFacts.run_deck_center()
  if current and current.key == data.back then return ActionResult.unchanged(DeckFacts.run_deck_name() .. " is already selected") end
  return function()
    if not apply_selected_back(data.back) then return nil, "Deck '" .. bound_echo(data.back) .. "' could not be selected; nothing changed. Choose again." end
    if G.NEURO then
      G.NEURO.selected_back_key = data.back
      G.NEURO.deck_chosen = true
    end
    sync_run_select()
    return ActionResult.done()
  end
end

local function open_new_run_setup()
  local fn = G.FUNCS and G.FUNCS.setup_run
  if type(fn) == "function" then
    local can_continue = G.FUNCS.can_continue
    G.FUNCS.can_continue = function() return false end
    pcall(fn, { config = {}, UIBox = mock_UIBox })
    G.FUNCS.can_continue = can_continue
  end
  if G.SETTINGS then G.SETTINGS.current_setup = "New Run" end
end

return {
  open_new_run_setup = open_new_run_setup,
  locked_challenge_reason = locked_challenge_reason,
  handle_change_stake = handle_change_stake,
  handle_change_challenge_description = handle_change_challenge_description,
  apply_selected_back = apply_selected_back,
  sync_run_select = sync_run_select,
  handle_change_selected_back = handle_change_selected_back,
}
