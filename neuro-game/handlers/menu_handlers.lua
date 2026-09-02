local GameActions = require("core.game_actions")
local mock_UIBox = GameActions.mock_UIBox

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
  if G.GAME and G.GAME.viewed_back and G.GAME.viewed_back.change_to then
    G.GAME.viewed_back:change_to(center)
  end
  if G.GAME and G.GAME.selected_back and G.GAME.selected_back.change_to then
    G.GAME.selected_back:change_to(center)
  end
  local prof = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
  if prof and prof.MEMORY then prof.MEMORY.deck = name end
  if G.NEURO then G.NEURO.selected_back_key = key end
  return name, center
end

local function handle_change_stake(data)
  if type(data.to_key) ~= "number" then
    return nil, "Stake key is required. Provide a numeric stake id."
  end
  local max_stake = (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake and #G.P_CENTER_POOLS.Stake) or 8
  if data.to_key ~= math.floor(data.to_key) or data.to_key < 1 or data.to_key > max_stake then
    return nil, string.format("Stake must be an integer 1-%d.", max_stake)
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_stake
    if fn then fn({ to_key = data.to_key, to_val = data.to_key, UIBox = mock_UIBox }) end
    return "Stake set to " .. data.to_key
  end
end

local function handle_change_challenge_description(data)
  local id = data.id
  if type(id) ~= "string" and type(id) ~= "number" then
    return nil, "Challenge id is required. Provide a valid challenge id."
  end
  local idx = nil
  if not (G and G.CHALLENGES) then
    return nil, "Challenges are not available yet."
  end
  if type(id) == "number" then
    idx = G.CHALLENGES[id] and id or nil
  else
    for k, v in ipairs(G.CHALLENGES) do
      if v.id == id or v.name == id then
        idx = k
        break
      end
    end
  end
  if not idx then
    return nil, "Challenge '" .. tostring(id) .. "' not found. Use the id from the challenge list."
  end
  return function()
    G.challenge_tab = G.CHALLENGES[idx]
    local fn = G.FUNCS and G.FUNCS.change_challenge_description
    if fn then pcall(fn, { config = { id = idx }, UIBox = mock_UIBox }) end
    return "Challenge selected: " .. tostring(G.CHALLENGES[idx].name or id)
  end
end

local function handle_change_selected_back(data)
  if type(data.back) ~= "string" then
    return nil, "Back key is required. Provide a valid back key."
  end
  local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back
  local target_idx, _, target = find_back_by_key(pool, data.back)
  if not target_idx then
    return nil, "Deck key '" .. data.back .. "' not found. Use a key like b_red, b_blue."
  end
  if target.unlocked == false then
    return nil, "Deck key '" .. data.back .. "' is locked. Choose a key from Decks you can select."
  end
  return function()
    local selected_name = apply_selected_back(data.back)
    if not selected_name then return "Deck selection failed: " .. tostring(data.back) end
    pcall(function()
      if G.sticker_card then
        G.sticker_card.sticker = get_deck_win_sticker(G.GAME.viewed_back.effect.center)
        if G.sticker_card.area and G.sticker_card.area.cards then
          for _, card in pairs(G.sticker_card.area.cards) do
            card.children.back = false
            card:set_ability(card.config.center, true)
          end
        end
      end
    end)
    if G.NEURO then
      G.NEURO.selected_back_key = data.back
      G.NEURO.deck_chosen = true
    end
    return "Deck changed to " .. selected_name
  end
end

return {
  handle_change_stake = handle_change_stake,
  handle_change_challenge_description = handle_change_challenge_description,
  apply_selected_back = apply_selected_back,
  handle_change_selected_back = handle_change_selected_back,
}
