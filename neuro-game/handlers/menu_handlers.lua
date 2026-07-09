local CardArea = require("facts.card_area_util")
local mock_UIBox = CardArea.mock_UIBox

local function find_back_by_key(pool, key)
  if not pool then return nil end
  for i, v in ipairs(pool) do
    if v.key == key then return i, v.name end
  end
  return nil
end

-- these engine funcs take custom payload shapes, not {config,UIBox}, so can't use call_gfunc
local function make_passthrough(field, expected_type, fname, payload_fn, err_msg)
  return function(data)
    if type(data[field]) ~= expected_type then
      return nil, err_msg
    end
    return function()
      local fn = G.FUNCS and G.FUNCS[fname]
      if fn then
        local payload = payload_fn(data)
        payload.UIBox = mock_UIBox
        fn(payload)
      end
    end
  end
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
    -- set the tab FIRST so the selection sticks even without the overlay open; UI refresh is best-effort (pcall)
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
  local target_idx, target_name = find_back_by_key(pool, data.back)
  if not target_idx then
    return nil, "Deck key '" .. data.back .. "' not found. Use a key like b_red, b_blue."
  end
  return function()
    local center = G.P_CENTER_POOLS.Back[target_idx]
    if not center then return "Deck not found at index" end
    if G.GAME and G.GAME.viewed_back and G.GAME.viewed_back.change_to then
      G.GAME.viewed_back:change_to(center)
    end
    if G.GAME and G.GAME.selected_back and G.GAME.selected_back.change_to then
      G.GAME.selected_back:change_to(center)
    end
    local prof = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    if prof and prof.MEMORY then
      prof.MEMORY.deck = target_name
    end
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
    G.NEURO.deck_chosen = true
    return "Deck changed to " .. target_name
  end
end

local function handle_change_viewed_back(data)
  if type(data.to_key) ~= "string" then
    return nil, "Back key is required. Provide a valid back key."
  end
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back
  if pool and SMODS and SMODS.collection_pool then
    local ok_pool, p = pcall(SMODS.collection_pool, pool)
    if ok_pool and p then pool = p end
  end
  local idx, name = find_back_by_key(pool, data.to_key)
  if not idx then
    return nil, "Deck key '" .. data.to_key .. "' not found. Use a key like b_red, b_blue."
  end
  if not (G.GAME and G.GAME.viewed_back and G.sticker_card) then
    return nil, "Deck view is not open. Use setup_run first."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_viewed_back
    if fn then fn({ to_key = idx, to_val = name, UIBox = mock_UIBox }) end
    return "Viewing deck: " .. tostring(name)
  end
end

local handle_change_viewed_collab = make_passthrough("to_key", "string", "change_viewed_collab",
  function(d) return { to_key = d.to_key, to_val = d.to_key } end,
  "Collab key is required. Provide a valid collab key.")

return {
  handle_change_stake = handle_change_stake,
  handle_change_challenge_description = handle_change_challenge_description,
  handle_change_selected_back = handle_change_selected_back,
  handle_change_viewed_back = handle_change_viewed_back,
  handle_change_viewed_collab = handle_change_viewed_collab,
}
