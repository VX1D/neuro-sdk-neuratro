local M = {}

local Utils = require("util.utils")

local function hidden(card)
  local ok, concealed = pcall(function()
    return require("facts.card_util").is_hidden(card)
  end)
  return not ok or concealed ~= false
end

local function clean_label(value, fallback)
  local text = Utils.normalize_ws(value or fallback or "item")
  return text ~= "" and text or (fallback or "item")
end

function M.is_public(card)
  return not hidden(card)
end

local SPREAD = {
  jokers = true, consumables = true, hand = true, play = true,
  shop_jokers = true, shop_vouchers = true, shop_booster = true, pack_cards = true,
}

function M.label(card, area, index)
  if hidden(card) then
    if SPREAD[area] and index ~= nil then
      return string.format("face-down item #%s in %s", tostring(index), area)
    end
    return (type(area) == "string" and area ~= "area") and ("face-down card in the " .. area) or "face-down card"
  end
  return clean_label(Utils.safe_name_or(card), "item")
end

function M.multiset_key(card, area, index)
  if hidden(card) then
    if not SPREAD[area] then return "hidden:" .. tostring(area or "area") end
    return "hidden:" .. area .. ":" .. tostring(index or "?")
  end
  local center = type(card) == "table" and card.config and card.config.center
  if type(center) == "table" and type(center.key) == "string" and center.key ~= "" then
    return "center:" .. center.key
  end
  return "label:" .. M.label(card, area, index)
end

return M
