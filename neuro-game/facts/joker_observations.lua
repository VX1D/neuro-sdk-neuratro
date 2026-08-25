local M = {}
local Utils = require("util.utils")
local PublicCard = require("facts.public_card_identity")

local CHANNELS = {
  { "score_chips", "Chips" }, { "score_mult", "Mult" },
  { "score_xchips", "xChips" }, { "score_xmult", "xMult" },
  { "dollars", "dollars" }, { "retrigger", "retriggers" },
}

local function record(card)
  local id = type(card) == "table" and card.sort_id or nil
  local all = G and G.NEURO and G.NEURO.joker_observations
  return id ~= nil and type(all) == "table" and all[id] or nil
end

local function condition_ratio(card)
  local ok, JokerHits = pcall(require, "core.joker_hits")
  if not ok or type(JokerHits) ~= "table" or type(JokerHits.condition_counts) ~= "function" then
    return nil
  end
  local ok_counts, hits, hands = pcall(JokerHits.condition_counts, card)
  if not (ok_counts and hits and hands) then return nil end
  return "held " .. hits .. "/" .. hands
end

function M.for_card(card)
  local rec = record(card)
  local ratio = condition_ratio(card)
  local parts, known = {}, false
  if type(rec) == "table" then
    for i = 1, #CHANNELS do
      local channel, label = CHANNELS[i][1], CHANNELS[i][2]
      if rec[channel] then parts[#parts + 1] = label; known = true end
    end
    if rec.last_dollar_payout and type(rec.last_dollar_payout.amount) == "number" then
      parts[#parts + 1] = "last end-of-round payout " .. Utils.money(rec.last_dollar_payout.amount)
    end
    if rec.activated and not known then parts[#parts + 1] = "other activation" end
  end
  if ratio then parts[#parts + 1] = ratio end
  if #parts == 0 then return nil end
  return table.concat(parts, ", "), ratio ~= nil
end

local LEGEND = " (held N/M = its condition has held on N of your last M hands)"

function M.roster_line(cards)
  if type(cards) ~= "table" then return nil end
  local parts, any_ratio = {}, false
  for i = 1, #cards do
    if PublicCard.is_public(cards[i]) then
      local seen, has_ratio = M.for_card(cards[i])
      if seen then
        parts[#parts + 1] = i .. ". " .. seen
        any_ratio = any_ratio or has_ratio
      end
    end
  end
  if #parts == 0 then return nil end
  return "Observed this run, by roster number" .. (any_ratio and LEGEND or "")
    .. ": " .. table.concat(parts, "; ") .. "."
end

return M
