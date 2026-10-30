local CardUtil = require("facts.card_util")
local Utils = require("util.utils")

local AREA_ALIASES = {
  consumeables = "consumables",
  consumable   = "consumables",
  consumeable  = "consumables",
}
local ENGINE_AREA = { consumables = "consumeables" }

local function validate_hand_indices(indices, max_cards, cap)
  cap = cap or CardUtil.highlight_limit()
  if max_cards < 1 then
    return nil, "No cards are in hand right now, so there is nothing to select."
  end
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

local function hand_card_name(card)
  if not require("facts.public_card_identity").is_public(card) then return "face-down" end
  return Utils.playing_card_label(card)
end

local function name_key(text)
  return Utils.normalize_ws(tostring(text or "")):lower()
end

local function hand_listing(cards)
  local rows = {}
  for i, card in ipairs(cards) do rows[i] = i .. ". " .. hand_card_name(card) end
  return table.concat(rows, ", ")
end

-- An optional name echo; an empty one names nothing, so it is treated as absent.
local function echo(value)
  if value == "" or (type(value) == "table" and next(value) == nil) then return nil end
  return value
end

local function validate_hand_cards(indices, names, cards, field)
  field = field or "cards"
  if type(names) ~= "table" or #names ~= #indices then
    return nil, string.format("Send one card name per hand position in %s (%d %s, %d %s). Your hand now: %s.",
      field, #indices, #indices == 1 and "position" or "positions", type(names) == "table" and #names or 0,
      (type(names) == "table" and #names or 0) == 1 and "name" or "names", hand_listing(cards))
  end
  -- The echo names the selected cards in any order, so it is matched as a multiset (bipartite matching).
  local actual, owner = {}, {}
  for j, idx in ipairs(indices) do actual[j] = name_key(hand_card_name(cards[idx])) end
  local function fits(i, j)
    return name_key(names[i]):sub(1, #actual[j]) == actual[j]
  end
  local function claim(i, seen)
    for j = 1, #indices do
      if not seen[j] and fits(i, j) then
        seen[j] = true
        if not owner[j] or claim(owner[j], seen) then
          owner[j] = i
          return true
        end
      end
    end
    return false
  end
  for i = 1, #names do
    if not claim(i, {}) then
      local held, named, rows = 0, 0, {}
      for j, idx in ipairs(indices) do
        rows[j] = idx .. ". " .. hand_card_name(cards[idx])
        if fits(i, j) then held = held + 1 end
      end
      for k = 1, #names do
        if name_key(names[k]) == name_key(names[i]) then named = named + 1 end
      end
      local selected = table.concat(rows, ", ")
      local fact
      if held == 0 then
        fact = string.format("%s is not among the cards at the positions you selected (%s)", tostring(names[i]), selected)
      elseif named > held then
        fact = string.format("You named %s %d times, but the positions you selected (%s) hold it %d %s",
          tostring(names[i]), named, selected, held, held == 1 and "time" or "times")
      else
        fact = string.format("The names you sent do not match the cards at the positions you selected (%s)", selected)
      end
      return nil, string.format("%s, so nothing was done. Your hand now: %s.", fact, hand_listing(cards))
    end
  end
  return true
end

local function get_area(area_name)
  if not area_name or not G then
    return nil
  end
  area_name = AREA_ALIASES[area_name] or area_name
  if area_name == "booster_pack" or area_name == "pack_cards" then
    return CardUtil.pack_area()
  end
  return G[ENGINE_AREA[area_name] or area_name]
end

local RECHECK = " Re-check the rows in the current state and choose again."

local function validate_area_card(data)
  local area = get_area(data.area)
  if not area or not area.cards then
    return nil, nil, "Area '" .. tostring(data.area) .. "' is not available right now." .. RECHECK
  end
  if #area.cards == 0 then
    return nil, nil, "Area '" .. tostring(data.area) .. "' is empty." .. RECHECK
  end
  if type(data.index) ~= "number" or data.index < 1 or data.index > #area.cards then
    return nil, nil, "Index " .. tostring(data.index) .. " out of bounds ('" .. tostring(data.area) .. "' has " .. #area.cards .. " cards). Use 1-" .. #area.cards .. "."
  end
  local card = area.cards[data.index]
  if not card then
    return nil, nil, "Index " .. tostring(data.index) .. " in '" .. tostring(data.area) .. "' holds no card." .. RECHECK
  end
  return area, card, nil
end

local function bound_echo(text)
  if #text > 128 then return text:sub(1, 125) .. "..." end
  return text
end

local AREA_NAME_LIST_MAX = 20

local function area_card_names(area_key)
  local area = get_area(area_key)
  local cards = type(area) == "table" and area.cards or nil
  if type(cards) ~= "table" then return nil end
  local names, seen = {}, {}
  for _, card in ipairs(cards) do
    if not CardUtil.is_hidden(card) then
      local ok, name = pcall(Utils.safe_name_or, card)
      if ok and type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
  if #names == 0 then return nil end
  return names
end

local function area_name_sentence(area_key)
  local names = area_card_names(area_key)
  if not names then return "" end
  local shown, truncated = names, false
  if #names > AREA_NAME_LIST_MAX then
    shown, truncated = {}, true
    for i = 1, AREA_NAME_LIST_MAX do shown[i] = names[i] end
  end
  return " Names there now, in position order: " .. table.concat(shown, ", ") .. (truncated and ", and others." or ".")
end

local function norm_name(s) return (s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")) end

local function same_name(actual, provided)
  local a = norm_name(actual)
  return a == norm_name(provided) or a == norm_name((provided:gsub("%s*%b()", "")))
end

local function check_target_name(card, provided, index, area_label)
  if type(provided) ~= "string" or provided == "" then return nil end
  -- Never identify a face-down card in a refusal.
  if CardUtil.is_hidden(card) then
    return string.format(
      "Index %s in '%s' is face down, so its name cannot be matched -- target it by index alone.",
      tostring(index), tostring(area_label))
  end
  local actual = tostring(Utils.safe_name_or(card))
  if same_name(actual, provided) then return nil end
  return string.format(
    "Index %s in '%s' is currently '%s', not '%s' -- indices shift after a sell/use/pick. Re-check the rows and pick again.",
    tostring(index), tostring(area_label), actual, bound_echo(provided))
    .. area_name_sentence(area_label)
end

local function find_card_by_name(area, provided)
  if type(provided) ~= "string" or provided == "" then return nil end
  if not (area and area.cards) then return nil end
  local match_c, match_i, count = nil, nil, 0
  for i, c in ipairs(area.cards) do
    -- Skip concealed cards so this code cannot resolve an unseen identity.
    if not CardUtil.is_hidden(c) and same_name(tostring(Utils.safe_name_or(c)), provided) then
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

local TARGET_RULES = {
  buy_from_shop = { relocate_missing = true },
  sell_card = {},
  use_consumable = { face_down_by_index = true },
  choose_pack_card = { face_down_by_index = true },
  use_directional_consumable = { exact_name = true },
  choose_directional_pack_card = { exact_name = true },
}

local function resolve_target(data, rules)
  rules = rules or {}
  local named = type(data.name) == "string" and data.name ~= ""
  local area, card, err = validate_area_card(data)
  if err then
    local rc, ri
    if rules.relocate_missing and named then
      area = get_area(data.area)
      rc, ri = find_card_by_name(area, data.name)
    end
    if rc then return area, rc, ri end
    return nil, nil, nil, "TARGET_UNAVAILABLE", err
  end
  if rules.face_down_by_index and CardUtil.is_hidden(card) then return area, card, data.index end
  local name_err = check_target_name(card, data.name, data.index, data.area)
  if not name_err then return area, card, data.index end
  if not rules.exact_name and named then
    local rc, ri = find_card_by_name(area, data.name)
    if rc then return area, rc, ri end
  end
  return nil, nil, nil, "STALE_TARGET", name_err
end

return { echo = echo, bound_echo = bound_echo, resolve_target = resolve_target, TARGET_RULES = TARGET_RULES, validate_hand_indices = validate_hand_indices, validate_hand_cards = validate_hand_cards, hand_card_name = hand_card_name, get_area = get_area, validate_area_card = validate_area_card, validate_index = validate_index, AREA_ALIASES = AREA_ALIASES, blind_size_rule_error = blind_size_rule_error }
