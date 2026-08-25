local CardUtil = require("facts.card_util")
local Utils = require("util.utils")

local AREA_ALIASES = {
  consumables = "consumeables",
  consumable  = "consumeables",
  consumeable = "consumeables",
}

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

local function check_target_name(card, provided, index, area_label)
  if type(provided) ~= "string" or provided == "" then return nil end
  local actual = tostring(Utils.safe_name_or(card))
  local have = actual:lower():gsub("%s+", " ")
  local want = provided:lower():gsub("%s+", " ")
  if have == want or have:sub(1, #want) == want then return nil end
  local hb = (have:gsub("^the ", ""))
  local wb = (want:gsub("^the ", ""))
  if #wb > 0 and (hb == wb or hb:sub(1, #wb) == wb) then return nil end
  return string.format(
    "Index %s in '%s' is currently '%s', not '%s' -- indices shift after a sell/use/pick. Re-check the rows and pick again.",
    tostring(index), tostring(area_label), actual, provided)
end

local function find_card_by_name(area, provided)
  if type(provided) ~= "string" or provided == "" then return nil end
  if not (area and area.cards) then return nil end
  local want = provided:lower():gsub("%s+", " ")
  local match_c, match_i, count = nil, nil, 0
  for i, c in ipairs(area.cards) do
    local have = tostring(Utils.safe_name_or(c)):lower():gsub("%s+", " ")
    if have:find(want, 1, true) or want:find(have, 1, true) then
      count = count + 1
      match_c, match_i = c, i
    end
  end
  if count == 1 then return match_c, match_i end
  return nil
end

local function validate_index(idx, count, field, noun)
  if type(idx) ~= "number" or idx < 1 or idx > count then
    return false, (field or "index") .. " " .. tostring(idx) .. " out of range (you have "
      .. count .. " " .. (noun or "items") .. "). Use 1-" .. count .. "."
  end
  return true
end

local function blind_size_rule_error(debuff, count, min_override)
  if type(debuff) ~= "table" or type(count) ~= "number" or count <= 0 then return nil end
  local min_cards = tonumber(min_override or debuff.h_size_ge or 0) or 0
  if min_cards > 0 and count < min_cards then
    return string.format("Blind rule requires at least %d played cards. Selected %d.", min_cards, count)
  end
  local max_cards = tonumber(debuff.h_size_le or 0) or 0
  if max_cards > 0 and count > max_cards then
    return string.format("Blind rule allows at most %d played cards. Selected %d.", max_cards, count)
  end
  return nil
end

return { check_target_name = check_target_name, find_card_by_name = find_card_by_name, validate_hand_indices = validate_hand_indices, get_area = get_area, validate_area_card = validate_area_card, validate_index = validate_index, AREA_ALIASES = AREA_ALIASES, blind_size_rule_error = blind_size_rule_error }
