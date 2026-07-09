local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local HandFacts = require("facts.hand_facts")
local DebuffFacts = require("facts.debuff_facts")
local compact_text = CtxHelpers.compact_text
local fmt_num = require("util.utils").fmt_num   -- chips/score can exceed 2^63, where %d wraps
local short_value = CtxHelpers.short_value
local short_suit = CtxHelpers.short_suit
local short_enh = CtxHelpers.short_enh
local short_seal = CtxHelpers.short_seal
local short_edition = CtxHelpers.short_edition

local M = {}

local function card_token(card, include_debuff, readable)
  local base = card.base or {}
  local enh = short_enh(card)
  local seal = short_seal(card)
  local ed = short_edition(card)
  -- stone cards have no rank/suit; emitting a rank/suit head would be misleading
  local head
  if CardUtil.enhancement_key(card) == "m_stone" then
    head = (enh ~= "" and enh) or "Stone"
    enh = ""
  elseif readable then
    head = tostring(base.value or "?") .. " of " .. tostring(base.suit or "?")
  else
    head = tostring(short_value(base.value)) .. tostring(short_suit(base.suit))
  end
  local mods = ""
  if enh ~= "" then mods = mods .. "+" .. enh end
  if seal ~= "" then mods = mods .. "+" .. seal end
  if ed ~= "" then mods = mods .. "+" .. ed end
  if include_debuff and card.debuff then mods = mods .. "+DB" end
  if type(card.ability) == "table" and card.ability.forced_selection then mods = mods .. "+LOCK" end
  return head .. mods
end

local function hand_section()
  if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
    return nil
  end
  local parts = {}
  for i, card in ipairs(G.hand.cards) do
    parts[#parts + 1] = i .. "=" .. card_token(card, true)
  end
  return "H:" .. table.concat(parts, " ")
end

local function hand_limits_section()
  if not (G and G.hand and G.hand.config and G.GAME and G.GAME.current_round) then
    return nil
  end
  local max_highlight = CardUtil.highlight_limit()
  local hand_limit = CardUtil.hand_limit()
  local highlighted = G.hand.highlighted and #G.hand.highlighted or 0
  local hands_left = G.GAME.current_round.hands_left or 0
  local discards_left = G.GAME.current_round.discards_left or 0
  local can_play = hands_left > 0 and "Y" or "N"
  local can_discard = discards_left > 0 and "Y" or "N"
  return string.format("HL|MH:%d|SEL:%d|HS:%d|CP:%s|CD:%s",
    max_highlight, highlighted, hand_limit, can_play, can_discard)
end

local function levels_section()
  local rows = HandFacts.levels()
  if #rows == 0 then return nil end

  local lines = {}
  lines[#lines + 1] = DebuffFacts.flint_active() and "L:n,lv,c,m,p (Flint active: c,m already halved)" or "L:n,lv,c,m,p"
  for _, row in ipairs(rows) do
    -- fmt_num for chips/mult: %d truncates fractional plasma bases and wraps huge levels
    lines[#lines + 1] = string.format("%s,%d,%s,%s,%d",
      compact_text(row.name, 24), row.level, fmt_num(row.chips), fmt_num(row.mult), row.played or 0)
  end
  return table.concat(lines, "\n")
end


-- size only: per-suit/per-rank remaining counts would be deck-counting, out of bounds
local function deck_cards_section()
  if not G or not G.deck or not G.deck.cards or #G.deck.cards == 0 then return nil end
  return "DC:" .. tostring(#G.deck.cards)
end

local function play_area_section()
  if not (G and G.play and G.play.cards and #G.play.cards > 0) then return nil end
  local parts = {}
  for _, card in ipairs(G.play.cards) do
    parts[#parts + 1] = card_token(card, true)
  end
  -- space-separated: comma is the CSV column delimiter elsewhere, card tokens must not use it
  return "PLAY|" .. table.concat(parts, " ")
end

local function last_play_section(state_name)
  local lp = G and G.NEURO and G.NEURO.last_play
  if type(lp) ~= "table" then return nil end
  if lp.kind == "discard" then
    return "LP|discard|" .. tostring(lp.played or 0) .. " cards"
  end
  local out = "LP|" .. tostring(lp.hand_type or "?") .. "|played " .. tostring(lp.played or 0) .. " cards"
  if lp.scored then out = out .. ", " .. tostring(lp.scored) .. " scored" end
  local cur = G.GAME and tonumber(G.GAME.chips)
  local pre = tonumber(lp.pre_chips)
  if cur and pre and (cur > pre or state_name == "ROUND_EVAL") then
    out = out .. "|+" .. fmt_num(cur - pre) .. "c"
    local target = G.GAME.blind and tonumber(G.GAME.blind.chips)
    if target and target > 0 then
      out = out .. "|" .. fmt_num(cur) .. "/" .. fmt_num(target)
      out = out .. "|SHF:" .. fmt_num(math.max(0, target - cur))
    end
  end
  return out
end

local function clear_last_play()
  if G and G.NEURO then G.NEURO.last_play = nil end
end

M.card_token = card_token
M.hand_section = hand_section
M.last_play_section = last_play_section
M.clear_last_play = clear_last_play
M.hand_limits_section = hand_limits_section
M.levels_section = levels_section
M.deck_cards_section = deck_cards_section
M.play_area_section = play_area_section

return M
