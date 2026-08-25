local GameActions = require("core.game_actions")
local ForceHelpers = require("force.force_helpers")
local Filtered = require("core.filtered")
local mock_UIBox = GameActions.mock_UIBox

local function handle_toggle_seeded_run(_data)
  if not ForceHelpers.is_run_setup_overlay() then
    return nil, "Run setup screen is not open. Use setup_run first, then toggle seeded mode."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.toggle_seeded_run
    local target = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") or nil
    if fn and target and target.config and target.config.object then
      pcall(fn, { config = { object = target.config.object }, UIBox = G.OVERLAY_MENU })
    else
      G.run_setup_seed = not G.run_setup_seed
    end

    return string.format("Seeded mode: %s", G.run_setup_seed and "ON" or "OFF")
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
  if seed_val == "" then
    return nil, "No valid seed provided (or it was filtered). Provide a clean seed parameter or clipboard value."
  end

  return function()
    if G then
      G.run_setup_seed = true
      G.setup_seed = seed_val
      if G.NEURO then G.NEURO.seed_pasted = seed_val end
      G.CLIPBOARD = seed_val
    end
    if love and love.system and love.system.setClipboardText then
      pcall(function() love.system.setClipboardText(seed_val) end)
    end

    local fn = G and G.FUNCS and G.FUNCS.paste_seed
    if fn and G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID then
      pcall(fn, { UIBox = G.OVERLAY_MENU, config = {} })
    end

    return "Seed set to: " .. seed_val
  end
end

local function resolve_challenge_index()
  local tab = G and G.challenge_tab or nil
  if not (tab and G and G.CHALLENGES) then return nil end
  if type(tab) == "number" then
    return G.CHALLENGES[tab] and tab or nil
  end
  if type(tab) == "table" then
    for k, v in ipairs(G.CHALLENGES) do
      if v == tab or (tab.id and v.id == tab.id) then return k end
    end
  end
  return nil
end

local function handle_start_challenge_run(_data)
  local idx = resolve_challenge_index()
  if not idx then
    return nil, "No challenge selected. Choose challenge first, then start_challenge_run."
  end

  return function()
    local challenge = G.CHALLENGES[idx]
    local fn = G and G.FUNCS and G.FUNCS.start_challenge_run
    if fn then
      fn({ config = { id = idx }, UIBox = mock_UIBox })
    else
      local fallback = G and G.FUNCS and G.FUNCS.start_run
      if fallback then
        fallback(nil, { stake = 1, challenge = challenge })
      end
    end
    return "Starting challenge run: " .. tostring(challenge.name or challenge.id or idx)
  end
end

return {
  handle_toggle_seeded_run = handle_toggle_seeded_run,
  handle_paste_seed = handle_paste_seed,
  handle_start_challenge_run = handle_start_challenge_run,
}
