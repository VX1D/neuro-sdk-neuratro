local CardUtil = require("facts.card_util")

local AREA_ALIASES = {
  consumables = "consumeables",
  consumable  = "consumeables",
  consumeable = "consumeables",
}
local mock_UIBox = {
  get_UIE_by_ID = function() return nil end,
  set_role = function() end,
  recalculate = function() end,
  add_child = function() end
}

local function clear_ai_flags(list)
  if not (G and G.NEURO and G.NEURO.ai_highlighted and type(list) == "table") then return end
  for _, card in ipairs(list) do
    if card then G.NEURO.ai_highlighted[card] = nil end
  end
end

local function clear_area_highlight(area)
  if not area then return end
  clear_ai_flags(area.highlighted)

  if type(area.unhighlight_all) == "function" then
    pcall(function() area:unhighlight_all() end)
    return
  end

  local highlighted = area.highlighted
  if type(highlighted) ~= "table" then
    area.highlighted = {}
    return
  end

  if type(area.remove_from_highlighted) == "function" then
    for i = #highlighted, 1, -1 do
      local card = highlighted[i]
      if card then
        pcall(function() area:remove_from_highlighted(card) end)
      end
    end
  else
    for i = 1, #highlighted do
      local card = highlighted[i]
      if card then
        card.highlighted = false
      end
    end
    area.highlighted = {}
  end
end

-- keep the AI-glow flag in lockstep with highlight or clearing highlight leaks the glow
local function set_highlight(card, on)
  if not card then return end
  card.highlighted = on and true or false
  if G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = on and true or nil
  end
end

local function add_area_highlight(area, card)
  if not area or not card then return false end
  if type(area.add_to_highlighted) == "function" then
    local ok = pcall(function() area:add_to_highlighted(card) end)
    if ok and G and G.NEURO and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
    return ok
  end
  area.highlighted = area.highlighted or {}
  card.highlighted = true
  if G and G.NEURO and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
  table.insert(area.highlighted, card)
  return true
end

local function normalize_indices(indices, max_cards, cap)
  local out = {}
  local seen = {}
  if type(indices) ~= "table" then return out end
  cap = cap or CardUtil.highlight_limit()
  for i = 1, #indices do
    local idx = tonumber(indices[i])
    if idx and idx == math.floor(idx) then
      if idx >= 1 and idx <= max_cards and not seen[idx] then
        out[#out + 1] = idx
        seen[idx] = true
        if #out >= cap then break end
      end
    end
  end
  return out
end

-- unlike normalize_indices, errors on bad input instead of silently dropping/truncating
local function validate_hand_indices(indices, max_cards, cap)
  cap = cap or CardUtil.highlight_limit()
  if type(indices) ~= "table" or #indices == 0 then
    return nil, string.format("Provide 1-%d card indices, e.g. {\"indices\":[1,2]}. Hand has %d cards.", cap, max_cards)
  end
  if #indices > cap then
    return nil, string.format("Too many cards: at most %d, you provided %d.", cap, #indices)
  end
  local out = {}
  local seen = {}
  for i = 1, #indices do
    local idx = tonumber(indices[i])
    if not idx or idx ~= math.floor(idx) then
      return nil, "Invalid index '" .. tostring(indices[i]) .. "'. Use whole numbers 1-" .. max_cards .. "."
    end
    if idx < 1 or idx > max_cards then
      return nil, string.format("Index %d is out of range. Hand has %d cards, use 1-%d.", idx, max_cards, max_cards)
    end
    if seen[idx] then
      return nil, string.format("Duplicate index %d. Each card can be selected only once.", idx)
    end
    seen[idx] = true
    out[#out + 1] = idx
  end
  return out, nil
end

local function get_area(area_name)
  if not area_name or not G then
    return nil
  end
  area_name = AREA_ALIASES[area_name] or area_name
  if area_name == "booster_pack" or area_name == "pack_cards" then
    return CardUtil.pack_area()
  end
  return G[area_name]
end

local function validate_area_card(data)
  local area = get_area(data.area)
  if not area or not area.cards then
    return nil, nil, "Area '" .. tostring(data.area) .. "' is not available right now."
  end
  if #area.cards == 0 then
    return nil, nil, "Area '" .. tostring(data.area) .. "' is empty."
  end
  if type(data.index) ~= "number" or data.index < 1 or data.index > #area.cards then
    return nil, nil, "Index " .. tostring(data.index) .. " out of bounds ('" .. tostring(data.area) .. "' has " .. #area.cards .. " cards). Use 1-" .. #area.cards .. "."
  end
  local card = area.cards[data.index]
  if not card then
    return nil, nil, "Card at index " .. tostring(data.index) .. " is nil in '" .. tostring(data.area) .. "'."
  end
  return area, card, nil
end

local function validate_index(idx, count, field, noun)
  if type(idx) ~= "number" or idx < 1 or idx > count then
    return false, (field or "index") .. " " .. tostring(idx) .. " out of range (you have "
      .. count .. " " .. (noun or "items") .. "). Use 1-" .. count .. "."
  end
  return true
end

local function call_gfunc(name, config, uibox)
  local fn = G and G.FUNCS and G.FUNCS[name]
  if not fn then return false end
  fn({ config = config or {}, UIBox = uibox or mock_UIBox })
  return true
end

-- debuff.h_size_ge/h_size_le are the boss blind min/max played-card rule (e.g. The Psychic's "must play 5")
local function blind_size_rule_error(debuff, count)
  if type(debuff) ~= "table" or type(count) ~= "number" or count <= 0 then return nil end
  local min_cards = tonumber(debuff.h_size_ge or 0) or 0
  if min_cards > 0 and count < min_cards then
    return string.format("Blind rule requires at least %d played cards. Selected %d.", min_cards, count)
  end
  local max_cards = tonumber(debuff.h_size_le or 0) or 0
  if max_cards > 0 and count > max_cards then
    return string.format("Blind rule allows at most %d played cards. Selected %d.", max_cards, count)
  end
  return nil
end

return { mock_UIBox = mock_UIBox, clear_area_highlight = clear_area_highlight, add_area_highlight = add_area_highlight, set_highlight = set_highlight, normalize_indices = normalize_indices, validate_hand_indices = validate_hand_indices, get_area = get_area, validate_area_card = validate_area_card, validate_index = validate_index, AREA_ALIASES = AREA_ALIASES, call_gfunc = call_gfunc, blind_size_rule_error = blind_size_rule_error }
