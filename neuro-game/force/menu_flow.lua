local Actions = require("core.actions")
local ActionPolicy = require("core.action_policy")
local ForceHelpers = require("force.force_helpers")
local hiyori_persona_gate = ForceHelpers.hiyori_persona_gate
local DeckFacts = require("facts.deck_facts")

local M = {}

local function key_bits()
  local CtxMisc = require("context.ctx_misc")
  local ActionRegistry = require("core.action_registry")
  local bits = {}
  if G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back and #DeckFacts.deck_records() > 0 then
    bits.select_deck = ActionRegistry.prompt("select_deck") .. " with back set to a deck's key from the Decks you can select list"
  end
  if CtxMisc.stake_list_line() then
    bits.select_stake = ActionRegistry.prompt("select_stake") .. " with to_key set to a stake's number from the Stakes list"
  end
  return bits
end

local function offer(state, candidates)
  local state_set = Actions.get_state_action_set(state)
  local actions, offered = {}, {}
  for _, name in ipairs(candidates) do
    if state_set[name] and Actions.is_action_valid(name) then
      actions[#actions + 1] = name
      offered[name] = true
    end
  end
  return actions, offered
end

local function already_set_note(offered)
  local fields = {}
  if offered.select_deck then fields[#fields + 1] = "deck" end
  if offered.select_stake then fields[#fields + 1] = "stake" end
  if #fields == 0 then return "" end
  return "Picking the " .. table.concat(fields, " or ") .. " already set changes nothing. "
end

function M.menu()
  local hg = hiyori_persona_gate()
  if hg then return hg end
  local candidates = { "open_run_setup", "select_deck", "select_stake", "copy_seed" }
  local names = {}
  local challenges = DeckFacts.selectable_challenges()
  if #challenges > 0 then
    for _, ch in ipairs(challenges) do
      names[#names + 1] = ch.id .. " (" .. tostring(require("facts.display_names").challenge(ch)) .. ")"
      if #names >= 25 then break end
    end
    candidates[#candidates + 1] = "select_challenge"
    candidates[#candidates + 1] = "start_challenge_run"
  end
  local actions, offered = offer("MENU", candidates)
  local query = ""
  if offered.select_deck or offered.select_stake then
    query = "Your deck and stake are already set (see Run setup); picking the one already set changes nothing. "
  end
  query = query .. "Open run setup to begin a run. "
  query = query .. DeckFacts.variety_advice(DeckFacts.viewed_deck_key())
  query = query .. ForceHelpers.menu_action_tree_query(offered) .. " "
  local _, picked = DeckFacts.selected_challenge()
  if picked and offered.start_challenge_run then
    query = query .. "Selected challenge: " .. tostring(require("facts.display_names").challenge(picked))
      .. " -- starting the challenge run begins it. "
  end
  if #names > 0 then
    query = query .. "Unlocked challenges -- select a challenge with id set to one of these ids, then "
      .. "start the challenge run: " .. table.concat(names, ", ") .. ". "
  end
  return {
    tool_bits = key_bits(),
    query = query,
    actions = actions
  }
end

function M.game_over()
  local hg = hiyori_persona_gate()
  if hg then return hg end
  local outcome = ""
  if G and G.GAME then
    local run = require("facts.game_facts").run_progress()
    outcome = run.won
      and string.format("Run WON: you beat the Ante %d Boss; the Endless run after it ended. ", run.win_ante)
      or "Run lost. "
  end
  local actions, offered = offer("GAME_OVER", { "open_run_setup", "select_deck", "copy_seed" })
  return {
    query = outcome
      .. "Open run setup to start a new run "
      .. "(deck, stake, and seeded-run options are inside). "
      .. (offered.select_deck and "Selecting a deck is also available. " or "") .. already_set_note(offered)
      .. DeckFacts.variety_advice(DeckFacts.viewed_deck_key())
      .. (offered.copy_seed and "For a seeded rematch: copy the seed now, then paste it inside run setup." or ""),
    actions = actions,
  }
end

local function seed_steps(offered, seeded)
  local paste = "paste a seed of 1-8 alphanumeric characters (letters/digits only), or omit the seed to paste from the clipboard"
  local start = offered.start_run and ", then start the run" or ""
  if seeded then
    local out = offered.paste_seed and ("To play a specific seed: " .. paste .. start .. ". ") or ""
    if offered.toggle_seeded_run then
      out = out .. "Toggling the seeded run turns seeded mode OFF for a random seed. "
    end
    return out
  end
  if offered.toggle_seeded_run and offered.paste_seed then
    return "To play a specific seed: toggle the seeded run to turn seeded mode ON, then " .. paste .. start .. ". "
  end
  return ""
end

function M.run_setup()
  local candidates = { "start_run", "select_deck", "toggle_seeded_run",
    "paste_seed", "copy_seed", "select_stake", "exit_overlay_menu" }
  local actions, offered = offer("RUN_SETUP", candidates)
  local has_progress = false
  for _, name in ipairs(actions) do
    if not ActionPolicy.NON_PROGRESS[name] then has_progress = true end
  end
  if not has_progress then return nil end
  local query = "Run setup screen is open. "
  query = query .. already_set_note(offered)
  if offered.select_deck then query = query .. DeckFacts.variety_advice(DeckFacts.viewed_deck_key()) end
  if offered.start_run then
    query = query .. "Starting the run begins it with the current deck and stake. "
  end
  query = query .. seed_steps(offered, (DeckFacts.run_seed()))
  if offered.exit_overlay_menu then
    query = query .. "Closing the overlay leaves run setup for the main menu without starting a run. "
  end
  return { query = query, actions = actions, tool_bits = key_bits() }
end

M.SCREENS = { "MENU", "GAME_OVER", "RUN_SETUP" }

return M
