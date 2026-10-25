local CardUtil = require("facts.card_util")
local PublicCardIdentity = require("facts.public_card_identity")
local DisplayNames = require("facts.display_names")
local Utils = require("util.utils")

local M = {}

local PACK_SKIP = { j_red_card = true }
local BLIND_SKIP = { j_throwback = true, tag_skip = true }

local NOTE = {
  shop = " a Booster Pack as skipped only when you buy and open it, then close it early (even after taking a card); a pack left unbought in the shop is not skipped. ",
  pack = " a Booster Pack as skipped only when you skip an opened pack; a pack left unbought in the shop is not skipped. ",
  blind = " a Blind as skipped only when you skip it; a blind you play is not skipped. ",
}

local function public_cards(...)
  local out = {}
  for i = 1, select("#", ...) do
    local area = select(i, ...)
    for _, card in ipairs((type(area) == "table" and area.cards) or {}) do
      if PublicCardIdentity.is_public(card) then out[#out + 1] = card end
    end
  end
  return out
end

local function tag_names(keys)
  local out = {}
  local tags = G and G.GAME and G.GAME.tags
  for _, tag in ipairs(type(tags) == "table" and tags or {}) do
    if keys[tag.key] then out[#out + 1] = DisplayNames.tag(tag.key) end
  end
  local offered = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_tags
  for _, key in pairs(type(offered) == "table" and offered or {}) do
    if keys[key] then
      out[#out + 1] = DisplayNames.tag(key)
    end
  end
  return out
end

function M.note(screen, ...)
  local kind = screen == "blind" and "blind" or "pack"
  local keys = kind == "pack" and PACK_SKIP or BLIND_SKIP
  local names, seen = {}, {}
  for _, card in ipairs(public_cards(...)) do
    local name = keys[CardUtil.center_key(card)] and Utils.safe_name_or(card)
    if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
  end
  if kind == "blind" then
    for _, name in ipairs(tag_names(keys)) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
  end
  if #names == 0 then return "" end
  return table.concat(names, " and ") .. (#names > 1 and " count" or " counts") .. NOTE[screen]
end

return M
