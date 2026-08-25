local M = {}

local Utils = require("util.utils")

local function face_down(card)
  local ok, hidden = pcall(require("facts.card_util").is_face_down, card)
  return ok and hidden == true
end

local function clean_label(value, fallback)
  local text = Utils.normalize_ws(value or fallback or "item")
  return text ~= "" and text or (fallback or "item")
end

function M.is_public(card)
  return not face_down(card)
end

function M.label(card, area, index)
  if face_down(card) then
    return string.format("face-down item #%s in %s", tostring(index or "?"), tostring(area or "area"))
  end
  return clean_label(Utils.safe_name_or(card), "item")
end

function M.multiset_key(card, area, index)
  if face_down(card) then
    return "hidden:" .. tostring(area or "area") .. ":" .. tostring(index or "?")
  end
  local center = type(card) == "table" and card.config and card.config.center
  if type(center) == "table" and type(center.key) == "string" and center.key ~= "" then
    return "center:" .. center.key
  end
  return "label:" .. M.label(card, area, index)
end

return M
