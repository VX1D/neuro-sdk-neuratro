local M = {}
local Utils = require("util.utils")
local PublicCard = require("facts.public_card_identity")

local CHANNELS = {
  { "score_chips", "Chips" }, { "score_mult", "Mult" },
  { "score_xchips", "xChips" }, { "score_xmult", "xMult" },
  { "dollars", "dollars" }, { "retrigger", "retriggers" },
}

local DECLARED = { chips = "Chips", mult = "Mult", xchips = "xChips", xmult = "xMult" }
local DECLARED_ORDER = { "chips", "mult", "xchips", "xmult" }

local function declared_kinds(card)
  local ok, projection = pcall(function() return require("facts.card_semantics").project(card) end)
  if not ok or type(projection) ~= "table" then return nil end
  local seen = {}
  for _, e in ipairs(projection.effects or {}) do seen[e.kind] = true end
  local out = {}
  for _, kind in ipairs(DECLARED_ORDER) do
    if seen[kind] then out[#out + 1] = DECLARED[kind] end
  end
  return #out > 0 and table.concat(out, ", ") or nil
end

local function record(card)
  local id = type(card) == "table" and card.sort_id or nil
  local all = G and G.NEURO and G.NEURO.joker_observations
  return id ~= nil and type(all) == "table" and all[id] or nil
end

local function condition_ratio(card)
  local ok_counts, hits, hands, label, why = pcall(require("core.joker_hits").condition_counts, card)
  if not (ok_counts and hits and hands) then return nil end
  label = label or "held"
  return label .. " " .. hits .. "/" .. hands, label, why
end

local function unconditional(card)
  local ok_u, yes = pcall(require("core.joker_hits").unconditional, card)
  return ok_u and yes == true
end

local function for_card(card)
  local rec = record(card)
  local ratio, ratio_label, ratio_why = condition_ratio(card)
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
  if ratio then
    parts[#parts + 1] = ratio
  elseif known and unconditional(card) then
    parts[#parts + 1] = "always"
    ratio_label = "always"
  end
  if #parts == 0 then return nil end
  if not known then
    local kinds = declared_kinds(card)
    if kinds then table.insert(parts, 1, kinds .. " (from its text; not seen paying yet)") end
  end
  return table.concat(parts, ", "), ratio_label, ratio_why
end

local LEGEND_ALWAYS = "always = no condition, it pays whenever it scores"
local LEGEND_HELD = "held N/M = its condition has held on N of your last M hands"
local PAID_TAIL = "; for a joker that pays a stored value, its condition is not visible apart from that"

function M.roster_line(cards)
  if type(cards) ~= "table" then return nil end
  local parts, used = {}, {}
  for i = 1, #cards do
    if PublicCard.is_public(cards[i]) then
      local seen, label, why = for_card(cards[i])
      if seen then
        parts[#parts + 1] = i .. ". " .. seen
        if label then used[label] = true end
        if why == "growth" then used.growth = true end
      end
    end
  end
  if #parts == 0 then return nil end
  local legends = {}
  if used.held then legends[#legends + 1] = LEGEND_HELD end
  if used.paid then
    legends[#legends + 1] = "paid N/M = it paid out on N of "
      .. (used.held and "those M hands" or "your last M hands") .. (used.growth and PAID_TAIL or "")
  end
  if used.always then legends[#legends + 1] = LEGEND_ALWAYS end
  local legend = (#legends > 0) and (" (" .. table.concat(legends, "; ") .. ")") or ""
  return "Observed this run, by roster number" .. legend .. ": " .. table.concat(parts, "; ") .. "."
end

if _G.NEURO_TEST then
  M.for_card = for_card
end

return M
