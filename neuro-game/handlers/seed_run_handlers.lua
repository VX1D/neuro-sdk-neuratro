local GameActions = require("core.game_actions")
local ActionResult = require("core.action_result")
local StateKinds = require("core.state_kinds")
local Filtered = require("core.filtered")
local mock_UIBox = GameActions.mock_UIBox

local DeckFacts = require("facts.deck_facts")

local function set_seeded(on)
  local choices = DeckFacts.run_select_choices()
  if not choices then return end
  choices.enable_seed = on
  pcall(SMODS.RunSelect.Functions.update_seed_input, on)
end

local function set_seed(seed)
  local choices = DeckFacts.run_select_choices()
  if not choices then return end
  pcall(G.FUNCS.run_select_paste_seed, { UIBox = G.OVERLAY_MENU, config = {} })
  choices.seed = seed
end

local function handle_toggle_seeded_run(_data)
  if not StateKinds.is_run_setup_overlay() then
    return nil, "Run setup screen is not open. Open run setup first, then toggle seeded mode."
  end
  return function()
    set_seeded(not DeckFacts.run_seed())
    return ActionResult.done()
  end
end

local function handle_paste_seed(data)
  local raw = data and data.seed
  local from_param = (raw ~= nil and tostring(raw) ~= "")
  if not from_param then
    if G and G.CLIPBOARD and tostring(G.CLIPBOARD) ~= "" then
      raw = tostring(G.CLIPBOARD)
    elseif love and love.system and love.system.getClipboardText then
      raw = tostring(love.system.getClipboardText() or "")
    else
      raw = ""
    end
  end

  local cleaned = Filtered.sanitize(tostring(raw or ""), true)
  if not from_param then
    cleaned = cleaned:match("^%s*(.-)%s*$")
  end
  if cleaned == "" then
    return nil, "No valid seed provided. Provide a seed parameter (1-8 letters/digits) or copy one to the clipboard."
  end

  if cleaned:find("[^A-Za-z0-9]") then
    if from_param then
      return nil, "Invalid characters in seed. Seed may only contain letters (A-Z) and digits (0-9)."
    end
    return nil, "Clipboard does not contain a bare seed. It must be only letters (A-Z) and digits (0-9) with nothing else -- copy just the seed, or pass it as a seed parameter."
  end
  if #cleaned > 8 then
    if from_param then
      return nil, "Seed is too long (max 8 characters). Provide a seed parameter (1-8 letters/digits)."
    end
    return nil, "Clipboard seed is too long (max 8 characters). Copy just the seed, or pass it as a seed parameter."
  end

  local seed_val = cleaned:upper()
  local seeded, current = DeckFacts.run_seed()
  if seeded and current == seed_val then return ActionResult.unchanged("Seed " .. seed_val .. " is already set") end

  return function()
    if G then G.CLIPBOARD = seed_val end
    if love and love.system and love.system.setClipboardText then
      pcall(function() love.system.setClipboardText(seed_val) end)
    end
    if G then
      set_seeded(true)
      set_seed(seed_val)
      if G.NEURO then G.NEURO.seed_pasted = seed_val end
    end

    return ActionResult.done()
  end
end

local function handle_start_challenge_run(_data)
  local idx = DeckFacts.selected_challenge()
  if not idx then
    return nil, "No challenge selected. Select a challenge first, then start the challenge run."
  end
  if not DeckFacts.challenge_unlocked(G.CHALLENGES[idx], idx) then
    return nil, require("handlers.menu_handlers").locked_challenge_reason(DeckFacts.selectable_challenge_ids())
  end

  return function()
    G.FUNCS.start_challenge_run({ config = { id = idx }, UIBox = mock_UIBox })
    return ActionResult.done()
  end
end

return {
  handle_toggle_seeded_run = handle_toggle_seeded_run,
  handle_paste_seed = handle_paste_seed,
  handle_start_challenge_run = handle_start_challenge_run,
}
