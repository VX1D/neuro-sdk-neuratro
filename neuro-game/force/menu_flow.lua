local Actions = require("core.actions")
local ActionPolicy = require("core.action_policy")
local ForceHelpers = require("force.force_helpers")
local hiyori_persona_gate = ForceHelpers.hiyori_persona_gate
local menu_action_tree_query = ForceHelpers.menu_action_tree_query
local deck_name_of = ForceHelpers.deck_name_of

local M = {}

function M.splash()
  local hg = hiyori_persona_gate()
  if hg then return hg end
  return {
    query = "State: SPLASH/MENU. Use setup_run to open the run setup screen "
      .. "(deck, stake, and seeded-run options are inside). "
      .. "change_selected_back is also available.",
    actions = { "setup_run", "change_selected_back" }
  }
end

function M.menu()
  local hg = hiyori_persona_gate()
  if hg then return hg end
  local actions = { "setup_run", "change_selected_back", "change_stake" }
  if Actions.is_action_valid("copy_seed") then actions[#actions + 1] = "copy_seed" end
  local names = {}
  if G and G.CHALLENGES and #G.CHALLENGES > 0 then
    for _, ch in ipairs(G.CHALLENGES) do
      names[#names + 1] = tostring(ch.name or ch.id)
      if #names >= 25 then break end
    end
    actions[#actions + 1] = "change_challenge_description"
    actions[#actions + 1] = "start_challenge_run"
  end
  local offered = {}
  for _, name in ipairs(actions) do offered[name] = true end
  local query = "State: MENU. "
  if G and G.GAME then
    query = query .. string.format("Current stake: %d. ", G.GAME.stake or 1)
  end
  local deck_name = deck_name_of(G and G.GAME and G.GAME.selected_back)
  query = query .. string.format("Current deck: %s. ", deck_name)
  query = query .. "Use setup_run to open the run setup screen where you will choose your deck and optionally a seed. "
  query = query .. menu_action_tree_query(offered)
  if #names > 0 then
    query = query .. "Challenges available -- use change_challenge_description with one of these, then "
      .. "start_challenge_run: " .. table.concat(names, ", ") .. ". "
  end
  return {
    query = query,
    actions = actions
  }
end

function M.game_over()
  local hg = hiyori_persona_gate()
  if hg then return hg end
  local outcome = ""
  if G and G.GAME then
    local ante = G.GAME.round_resets and G.GAME.round_resets.ante
    outcome = "Run " .. (G.GAME.won and "WON" or "lost")
      .. (ante and (" at Ante " .. tostring(ante)) or "")
      .. (G.GAME.round and (", round " .. tostring(G.GAME.round)) or "") .. ". "
  end
  local seed_advice = Actions.is_action_valid("copy_seed")
    and " For a seeded rematch: copy_seed now, then paste it inside run setup." or ""
  return {
    query = "State: GAME_OVER. " .. outcome
      .. "Use setup_run to open the run setup screen and start a new run "
      .. "(deck, stake, and seeded-run options are inside). change_selected_back "
      .. "is also available." .. seed_advice,
    actions = (function()
      local a = { "setup_run", "change_selected_back" }
      if Actions.is_action_valid("copy_seed") then a[#a + 1] = "copy_seed" end
      return a
    end)(),
  }
end

function M.run_setup()
  local deck_name = deck_name_of(G.GAME and G.GAME.viewed_back)
  local query = "State: RUN_SETUP. Run setup screen is open. Current deck: " .. deck_name .. ". "
    .. "Switch with change_selected_back using a deck key from the Decks you can select list. "
  query = query .. "start_setup_run begins the run with the current deck. "
  query = query .. "Seeded mode: " .. (G.run_setup_seed and "ON" or "OFF") .. ". "
  if G.setup_seed and G.setup_seed ~= "" then
    query = query .. "Pasted seed: " .. tostring(G.setup_seed) .. ". "
  end
  query = query .. 'To play a specific seed: toggle_seeded_run (turn ON), then '
    .. 'paste_seed|{"seed":"ABC123XY"} (1-8 letters/digits; omit seed to paste from clipboard), then start_setup_run. '
  local candidates = { "start_setup_run", "change_selected_back", "toggle_seeded_run",
    "paste_seed", "copy_seed", "change_stake" }
  local state_set = Actions.get_state_action_set("RUN_SETUP")
  local actions = {}
  local has_progress = false
  for _, name in ipairs(candidates) do
    if state_set[name] and Actions.is_action_valid(name) then
      actions[#actions + 1] = name
      if not ActionPolicy.NON_PROGRESS[name] then has_progress = true end
    end
  end
  if not has_progress then return nil end
  return { query = query, actions = actions }
end

return M
