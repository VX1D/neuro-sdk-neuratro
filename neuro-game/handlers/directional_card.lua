local ActionResult = require("core.action_result")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local Contracts = require("facts.target_contracts")
local UseCard = require("handlers.use_card")
local Utils = require("util.utils")

local M = {}

local function role_order(apply_to, take_from)
  return function()
    local cards = G and G.hand and G.hand.cards
    if not cards then return end
    local a, t
    for i, c in ipairs(cards) do
      if c == apply_to then a = i elseif c == take_from then t = i end
    end
    if a and t and a > t then
      cards[a], cards[t] = cards[t], cards[a]
      if G.hand.align_cards then G.hand:align_cards() end
    end
  end
end

function M.handle(data)
  local _, card, err = CardArea.validate_area_card(data)
  if err then return ActionResult.reject("TARGET_UNAVAILABLE", err) end
  if CardUtil.is_hidden(card) then
    return ActionResult.reject("TARGET_UNAVAILABLE", "A face-down card cannot be used with a directional target contract.")
  end
  local actual = tostring(Utils.safe_name_or(card)):lower():gsub("%s+", " ")
  local wanted = data.name:lower():gsub("%s+", " ")
  if actual ~= wanted then
    return ActionResult.reject("STALE_TARGET", string.format(
      "Index %s in '%s' is currently '%s', not '%s' -- re-check the row and choose again.",
      tostring(data.index), tostring(data.area), Utils.safe_name_or(card), tostring(data.name)))
  end
  local contract = Contracts.get(card)
  if not contract or contract.mode ~= "ordered_pair" then
    return ActionResult.reject("INVALID_SELECTION",
      "This card has no registered directional target contract; use " .. UseCard.canonical_action(data.area, false) .. ".")
  end
  local left, right = data.left_index, data.right_index
  if left == right then
    return ActionResult.reject("INVALID_SELECTION", string.format(
      "left_index and right_index are both %d; %s needs two different hand cards.", left, tostring(data.name)))
  end
  local translated = {}
  for k, v in pairs(data) do translated[k] = v end
  translated.hand_indices = { left, right }
  translated._action_name = UseCard.canonical_action(data.area, true)
  local exec, err = UseCard.handle_use_card(translated)
  if type(exec) ~= "function" or left < right then return exec, err end
  local reorder = role_order(G.hand.cards[left], G.hand.cards[right])
  return function(...)
    reorder()
    return exec(...)
  end
end
return M
