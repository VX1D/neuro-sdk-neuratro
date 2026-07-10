local CardArea = require("facts.card_area_util")
local ForceHelpers = require("force.force_helpers")
local Filtered = require("core.filtered")
local mock_UIBox = CardArea.mock_UIBox

local function handle_toggle_seeded_run(_data)
  -- G.run_setup_seed is the engine's own flag (start_setup_run reads it), but the overlay resets it to nil on rebuild, so a flip while closed is lost
  if not ForceHelpers.is_run_setup_overlay() then
    return nil, "Run setup screen is not open. Use setup_run first, then toggle seeded mode."
  end
  return function()
    G.run_setup_seed = not G.run_setup_seed

    local fn = G.FUNCS and G.FUNCS.toggle_seeded_run
    local target = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") or nil
    if fn and target and target.config and target.config.object then
      pcall(fn, { config = { object = target.config.object }, UIBox = G.OVERLAY_MENU })
    end

    return string.format("Seeded mode: %s", G.run_setup_seed and "ON" or "OFF")
  end
end

local function handle_paste_seed(data)
  local raw = data and data.seed
  if raw == nil or tostring(raw) == "" then
    if G and G.CLIPBOARD and tostring(G.CLIPBOARD) ~= "" then
      raw = tostring(G.CLIPBOARD)
    elseif love and love.system and love.system.getClipboardText then
      raw = tostring(love.system.getClipboardText() or "")
    else
      raw = ""
    end
  end

  local cleaned = Filtered.sanitize(tostring(raw or ""), true)
  local seed_val = cleaned:upper():gsub("[^A-Z0-9]", ""):sub(1, 8)
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
