local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local HandFacts = require("facts.hand_facts")
local FactHints = require("facts.fact_hints")
local CoreState = require("core.state")
local normalize_text = CtxHelpers.normalize_text
local fmt_num = require("util.utils").fmt_num   -- chips/score can exceed 2^63, where %d wraps
local short_value = CtxHelpers.short_value
local short_suit = CtxHelpers.short_suit
local short_enh = CtxHelpers.short_enh
local short_seal = CtxHelpers.short_seal
local short_edition = CtxHelpers.short_edition
local decode_card = CtxHelpers.decode_card
local yn = CtxHelpers.yn

local M = {}

local function card_token(card, include_debuff, readable)
  if CardUtil.is_face_down(card) then
    return readable and "face-down (hidden)" or "FD"
  end
  local base = card.base or {}
  local enh = short_enh(card)
  local seal = short_seal(card)
  local ed = short_edition(card)
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
  if include_debuff and card.debuff and type(card.ability) == "table" and card.ability.played_this_ante
     and require("facts.debuff_facts").pillar_active() then
    mods = mods .. "+USED"
  end
  if type(card.ability) == "table" and card.ability.forced_selection then mods = mods .. "+LOCK" end
  if type(card.ability) == "table" and not card.ability.extra_enhancement then
    local perma = tonumber(card.ability.perma_bonus) or 0
    if perma > 0 then mods = mods .. "+perma" .. perma .. "c" end
  end
  return head .. mods
end

local function hand_section()
  if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
    return nil
  end
  local parts = {}
  for i, card in ipairs(G.hand.cards) do
    parts[#parts + 1] = i .. ") " .. decode_card(card_token(card, true, true))
  end
  return "Your hand: " .. table.concat(parts, ", ") .. "."
end

local function hand_limits_section()
  if not (G and G.hand and G.hand.config and G.GAME and G.GAME.current_round) then
    return nil
  end
  local max_highlight = CardUtil.highlight_limit()
  local hand_limit = CardUtil.hand_limit()
  local hand_now = G.hand.cards and #G.hand.cards or 0
  local highlighted = G.hand.highlighted and #G.hand.highlighted or 0
  local hands_left = GameFacts.hands_left()
  local discards_left = GameFacts.discards_left()
  local limit_note = "hand size limit " .. tostring(hand_limit)
  if hand_now > hand_limit then
    limit_note = limit_note .. " (currently holding " .. tostring(hand_now)
      .. ", above that limit)"
  end
  return string.format("You may select up to %s cards (%s selected); %s. Can play: %s. Can discard: %s.",
    tostring(max_highlight), tostring(highlighted), limit_note,
    yn(hands_left > 0), yn(discards_left > 0))
end

local function visible_types_key(all_rows)
  local names = {}
  for _, row in ipairs(all_rows or {}) do names[#names + 1] = tostring(row.name) end
  table.sort(names)
  return "hand_base_values:" .. table.concat(names, ",")
end

local function queue_base_values_once()
  if not (G and G.NEURO) then return end
  if CoreState.get_state_name() ~= "SHOP" then return end
  local rows = HandFacts.base_levels()
  if #rows == 0 then return end
  local parts = {}
  for _, row in ipairs(rows) do
    parts[#parts + 1] = string.format("%s: %s chips x %s mult = %s",
      normalize_text(row.name), fmt_num(row.chips), fmt_num(row.mult),
      fmt_num(row.chips * row.mult))
  end
  FactHints.emit(visible_types_key(rows),
    "Level-1 starting hand values (fixed; sent once per hand-type set): "
      .. table.concat(parts, "; ") .. ". ")
end

local function level_row(row)
  -- Under Plasma the two factors are still the numbers cards and jokers add to, but their product is
  -- not the score: back.lua:157-160 balances the totals at final_scoring_step, so a hand played on
  -- its own makes floor((chips+mult)/2) squared. The header note stated the mechanism while the
  -- number beside it ignored it.
  local product, balance = row.chips * row.mult, ""
  if HandFacts.plasma_balances() then
    local half = math.floor((row.chips + row.mult) / 2)
    product = half * half
    balance = string.format(" (Plasma balances %s+%s to %s x %s)",
      fmt_num(row.chips), fmt_num(row.mult), fmt_num(half), fmt_num(half))
  end
  return string.format("%s: level %d, %s chips x %s mult = %s before any card or joker%s, played %d.",
    normalize_text(row.name), row.level, fmt_num(row.chips), fmt_num(row.mult),
    fmt_num(product), balance, row.played or 0)
end

local function levels_section()
  local rows = HandFacts.levels()
  if #rows == 0 then return nil end

  local notes = HandFacts.level_notes()
  local note_str = nil
  if #notes > 0 then
    note_str = table.concat(notes, "; "):gsub("c,m", "chips and mult")
  end

  if not note_str then
    local upgraded = {}
    for _, row in ipairs(rows) do
      if row.level ~= 1 then upgraded[#upgraded + 1] = row end
    end
    if #upgraded == 0 then
      queue_base_values_once()
      return "Hand levels: all level 1."
    end
    local lines = { "Hand levels:" }
    for _, row in ipairs(upgraded) do
      lines[#lines + 1] = level_row(row)
    end
    if #upgraded < #rows then
      lines[#lines + 1] = "(all other hands: level 1)"
      queue_base_values_once()
    end
    return table.concat(lines, "\n")
  end

  local lines = { "Hand levels (" .. note_str .. "):" }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = level_row(row)
  end
  return table.concat(lines, "\n")
end

local function hand_focus_options_section()
  local rows = HandFacts.levels()
  if #rows == 0 then return nil end
  local names = {}
  for _, row in ipairs(rows) do names[#names + 1] = normalize_text(row.name) end
  return "plan.hand_focus accepts exactly these hand names: " .. table.concat(names, ", ")
    .. "; no other hand type is unlocked yet."
end

local function deck_cards_section()
  if not G or not G.deck or not G.deck.cards then return nil end
  local n = #G.deck.cards
  if n == 0 then return "0 cards left in the draw pile: a discard would replace nothing." end
  return tostring(n) .. " cards left in the draw pile."
end

local DD_RANK = { [14]="A",[13]="K",[12]="Q",[11]="J",[10]="10",[9]="9",[8]="8",
  [7]="7",[6]="6",[5]="5",[4]="4",[3]="3",[2]="2" }
local DD_VALUE_ID = {
  ["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,["9"]=9,["10"]=10,
  Jack=11, Queen=12, King=13, Ace=14,
}
local function dd_rank_id(c)
  if type(c.get_id) == "function" then
    local ok, id = pcall(function() return c:get_id() end)
    if ok and type(id) == "number" then return id end
  end
  return c.base and DD_VALUE_ID[tostring(c.base.value)] or nil
end
local function modifier_tally(cards, acc)
  acc = acc or { editions = {}, seals = {}, enhancements = {} }
  local function tally(t, k)
    if not k or k == "" then return end
    t[tostring(k)] = (t[tostring(k)] or 0) + 1
  end
  for _, c in ipairs(cards or {}) do
    tally(acc.editions, CardUtil.edition_name(c.edition))
    tally(acc.seals, CardUtil.seal_name(c.seal))
    tally(acc.enhancements, CardUtil.enhancement_name(CardUtil.enhancement_key(c)))
  end
  return acc
end

local function modifier_prose(acc)
  local groups = {}
  for _, g in ipairs({ { "editions", acc.editions }, { "seals", acc.seals },
                       { "enhancements", acc.enhancements } }) do
    local keys = {}
    for k in pairs(g[2]) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " x" .. g[2][k] end
    if #parts > 0 then groups[#groups + 1] = g[1] .. " " .. table.concat(parts, ", ") end
  end
  if #groups == 0 then return nil end
  return table.concat(groups, "; ")
end

local unplayed_pool = CardUtil.unplayed_pool

local function draw_composition_section()
  local pool, flipped = unplayed_pool()
  if not pool or #pool == 0 then return nil end
  local suits = { Hearts = 0, Spades = 0, Diamonds = 0, Clubs = 0 }
  local ranks, wild, stone = {}, 0, 0
  for _, c in ipairs(pool) do
    local ck = c and c.config and c.config.center and c.config.center.key
    if ck == "m_stone" then
      stone = stone + 1
    else
      if ck == "m_wild" then
        wild = wild + 1
      else
        local s = c and c.base and c.base.suit
        if suits[s] then suits[s] = suits[s] + 1 end
      end
      local id = dd_rank_id(c)
      if id and id >= 2 and id <= 14 then
        ranks[id] = (ranks[id] or 0) + 1
      end
    end
  end
  local sp = {}
  for _, s in ipairs({ "Hearts", "Spades", "Diamonds", "Clubs" }) do
    if suits[s] > 0 then sp[#sp + 1] = tostring(suits[s]) .. " " .. s end
  end
  if wild > 0 then sp[#sp + 1] = tostring(wild) .. " wild" end
  if stone > 0 then sp[#sp + 1] = tostring(stone) .. " stone" end
  local rp = {}
  for id = 14, 2, -1 do
    if ranks[id] then rp[#rp + 1] = DD_RANK[id] .. " x" .. ranks[id] end
  end
  if #sp == 0 and #rp == 0 then return nil end
  local p = {}
  if #sp > 0 then p[#p + 1] = "Unplayed pool by suit: " .. table.concat(sp, ", ") .. "." end
  if #rp > 0 then p[#p + 1] = "Ranks in that pool: " .. table.concat(rp, ", ") .. "." end
  local mods = modifier_prose(modifier_tally(pool))
  if mods then p[#p + 1] = "Modifiers in that pool: " .. mods .. "." end
  -- UI_definitions.lua:3623-3627 prints the same "N cards flipped" note beside these tallies. The
  -- total is stated because these tallies run over the pool and the size line runs over the pile:
  -- without it the two sums differed by the flipped cards with nothing to reconcile them.
  if flipped > 0 then
    p[#p + 1] = "(" .. tostring(#pool) .. " cards tallied: the " .. tostring(#pool - flipped)
      .. " in the pile plus " .. tostring(flipped) .. " face-down hand card"
      .. (flipped == 1 and "" or "s") .. " the game counts as unplayed.)"
  end
  return table.concat(p, " ")
end

local function deck_modifiers_section()
  if not G then return nil end
  local acc, scope
  if type(G.playing_cards) == "table" and #G.playing_cards > 0 then
    acc, scope = modifier_tally(G.playing_cards), "full deck"
  else
    acc = modifier_tally(G.hand and G.hand.cards)
    modifier_tally(G.deck and G.deck.cards, acc)
    scope = "hand + draw pile"
  end
  local groups = modifier_prose(acc)
  if not groups then return "Card modifiers (" .. scope .. "): none." end
  return "Card modifiers (" .. scope .. "): " .. groups .. "."
end

local function deck_content_signature()
  if not G then return "-" end
  local counts = {}
  local function scan(cards, tag)
    for _, c in ipairs(cards or {}) do
      local base = c.base or {}
      local key = tag .. tostring(CardUtil.enhancement_key(c) or "-")
        .. "/" .. tostring(CardUtil.seal_name(c.seal) or "-")
        .. "/" .. tostring(CardUtil.edition_name(c.edition) or "-")
        .. "/" .. tostring(base.value or "-") .. tostring(base.suit or "-")
      counts[key] = (counts[key] or 0) + 1
    end
  end
  scan(G.playing_cards, "P")
  scan(G.deck and G.deck.cards, "D")
  local keys = {}
  for k in pairs(counts) do keys[#keys + 1] = k end
  table.sort(keys)
  for i = 1, #keys do keys[i] = keys[i] .. "x" .. counts[keys[i]] end
  return table.concat(keys, ",")
end

local function play_area_section()
  if not (G and G.play and G.play.cards and #G.play.cards > 0) then return nil end
  local parts = {}
  for _, card in ipairs(G.play.cards) do
    parts[#parts + 1] = decode_card(card_token(card, true, true))
  end
  return "In play: " .. table.concat(parts, ", ") .. "."
end

local function last_play_section(state_name)
  local lp = G and G.NEURO and G.NEURO.last_play
  if type(lp) ~= "table" then return nil end
  if lp.kind == "discard" then
    local left = tonumber(lp.discards_left_after)
    local remaining = left
      and (", " .. tostring(left) .. " discard" .. (left == 1 and "" or "s") .. " remain") or ""
    return "Last discard: replaced " .. tostring(lp.played or 0) .. " cards" .. remaining
      .. ". The current hand below is the result."
  end
  local out = "Last hand: " .. tostring(lp.hand_type or "?")
  out = out .. ", played " .. tostring(lp.played or 0) .. " cards"
  if lp.scored then out = out .. ", " .. tostring(lp.scored) .. " scored" end
  local cur = G.GAME and tonumber(G.GAME.chips)
  local pre = tonumber(lp.pre_chips)
  if cur and pre and (cur > pre or state_name == "ROUND_EVAL") then
    out = out .. ", +" .. fmt_num(cur - pre) .. " chips"
    local target = G.GAME.blind and tonumber(G.GAME.blind.chips)
    if target and target > 0 then
      out = out .. ", now " .. fmt_num(cur) .. "/" .. fmt_num(target)
      local shf = math.max(0, target - cur)
      out = out .. ", " .. (shf <= 0 and "target cleared" or (fmt_num(shf) .. " short"))
    end
  end
  return out .. "."
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
M.draw_composition_section = draw_composition_section
M.deck_modifiers_section = deck_modifiers_section
M.deck_content_signature = deck_content_signature
M.hand_focus_options_section = hand_focus_options_section
M.play_area_section = play_area_section

return M
