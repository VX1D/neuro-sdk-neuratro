local ActionResult = require("core.action_result")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local Contracts = require("facts.target_contracts")
local UseCard = require("handlers.use_card")
local Utils = require("util.utils")

local M = {}
local function ordinary_action(area)
  return area == "booster_pack" and "choose_pack_card" or "use_consumable"
end

local function directional_action(area)
  return area == "booster_pack" and "choose_directional_pack_card" or "use_directional_consumable"
end

function M.handle(data)
  local _, card, err = CardArea.validate_area_card(data)
  if err then return ActionResult.reject("TARGET_UNAVAILABLE", err) end
  if CardUtil.is_face_down(card) then
    return ActionResult.reject("TARGET_UNAVAILABLE", "A face-down card cannot be used with a directional target contract.")
  end
  local actual = tostring(Utils.safe_name_or(card)):lower():gsub("%s+", " ")
  local wanted = tostring(data.name or ""):lower():gsub("%s+", " ")
  if actual ~= wanted then
    return ActionResult.reject("STALE_TARGET", string.format(
      "Index %s in '%s' is currently '%s', not '%s' -- re-check the row and choose again.",
      tostring(data.index), tostring(data.area), Utils.safe_name_or(card), tostring(data.name)))
  end
  local contract = Contracts.get(card)
  if not contract or contract.mode ~= "ordered_pair" then
    return ActionResult.reject("INVALID_SELECTION",
      "This card has no registered directional target contract; use " .. ordinary_action(data.area) .. ".")
  end
  local left, right = data.left_index, data.right_index
  if type(left) ~= "number" or left % 1 ~= 0 or type(right) ~= "number" or right % 1 ~= 0 then
    return ActionResult.reject("INVALID_SELECTION", "left_index and right_index must be integer hand positions.")
  end
  if left >= right then
    return ActionResult.reject("INVALID_SELECTION", "Directional targets must be two distinct cards in visual left-to-right order (left_index < right_index).")
  end
  local translated = {}
  for k, v in pairs(data) do translated[k] = v end
  translated.hand_indices = { left, right }
  translated._directional_contract = true
  translated._action_name = directional_action(data.area)
  return UseCard.handle_use_card(translated)
end
return M
