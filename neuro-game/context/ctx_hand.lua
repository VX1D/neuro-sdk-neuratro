local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local HandFacts = require("facts.hand_facts")
local PublicCard = require("facts.public_card_identity")
local FactHints = require("facts.fact_hints")
local CoreState = require("core.state")
local normalize_text = CtxHelpers.normalize_text
local PlanLimits = require("core.plan_limits")
local Legality = require("facts.boss.legality")
local fmt_num = require("util.utils").fmt_num   -- %d wraps when chips or score exceed 2^63
local short_enh = CtxHelpers.short_enh
local short_seal = CtxHelpers.short_seal
local short_edition = CtxHelpers.short_edition
local decode_card = CtxHelpers.decode_card
local plural = CtxHelpers.plural

local M = {}
local function card_token(card, include_debuff)
  if type(card) ~= "table" or not PublicCard.is_public(card) then
    return "face-down (hidden)"
  end
  local base = card.base or {}
  local enh = short_enh(card)
  local seal = short_seal(card)
  local ed = short_edition(card)
  local head
  if require("util.utils").hides_front(card) then
    head = (enh ~= "" and enh) or require("util.utils").playing_card_label(card)
    enh = ""
  else
    head = tostring(base.value or "?") .. " of " .. tostring(base.suit or "?")
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
  local parts = { "## Your hand" }
  for i, card in ipairs(G.hand.cards) do
    parts[#parts + 1] = i .. ". " .. decode_card(card_token(card, true))
  end
  return table.concat(parts, "\n")
end

local function hand_limits_section(action_set)
  if not (G and G.hand and G.hand.config and G.GAME and G.GAME.current_round) then
    return nil
  end
  local max_highlight = CardUtil.highlight_limit()
  local hand_limit = CardUtil.hand_limit()
  local hand_now = G.hand.cards and #G.hand.cards or 0
  local highlighted = G.hand.highlighted and #G.hand.highlighted or 0
  if action_set ~= nil then
    local offered_cap
    if CtxHelpers.has_action(action_set, "play_hand") then
      local _, play_max = Legality.play_size_bounds()
      offered_cap = math.max(1, tonumber(play_max) or 1)
    end
    if CtxHelpers.has_action(action_set, "discard_hand") then
      local discard_max = math.max(1, PlanLimits.discard_select_max())
      offered_cap = offered_cap and math.max(offered_cap, discard_max) or discard_max
    end
    if offered_cap then max_highlight = math.min(max_highlight, offered_cap) end
  end
  local limit_note = "hand size limit " .. tostring(hand_limit)
  if hand_now > hand_limit then
    limit_note = limit_note .. " (currently holding " .. tostring(hand_now)
      .. ", above that limit)"
  end
  return string.format("You may select up to %s cards (%s selected); %s.\n%s.\n%s.",
    tostring(max_highlight), tostring(highlighted), limit_note,
    CtxHelpers.can_line("play", action_set, { "play_hand" }),
    CtxHelpers.can_line("discard", action_set, { "discard_hand" }))
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
  local lines = { "## Level-1 starting hand values" }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.format("- %s: %s chips x %s mult = %s",
      normalize_text(row.name), fmt_num(row.chips), fmt_num(row.mult),
      fmt_num(row.chips * row.mult))
  end
  FactHints.emit(visible_types_key(rows), table.concat(lines, "\n"))
end

local function level_row(row)
  local product, balance = row.chips * row.mult, ""
  if HandFacts.plasma_balances() then
    local half = math.floor((row.chips + row.mult) / 2)
    product = half * half
    balance = string.format(" (Plasma balances %s+%s to %s x %s)",
      fmt_num(row.chips), fmt_num(row.mult), fmt_num(half), fmt_num(half))
  end
  local level = tostring(row.level)
  if row.score_level and row.score_level ~= row.level then
    level = level .. " (scores at level " .. tostring(row.score_level) .. " when played)"
  end
  return string.format("%s: level %s, %s chips x %s mult = %s before any card or joker%s, played %d.",
    normalize_text(row.name), level, fmt_num(row.chips), fmt_num(row.mult),
    fmt_num(product), balance, row.played or 0)
end

local function level_note()
  local notes = HandFacts.level_notes()
  if #notes == 0 then return nil end
  return (table.concat(notes, "; "):gsub("c,m", "chips and mult"))
end

local function levels_heading()
  local note = level_note()
  return note and ("Hand levels (" .. note .. ")") or "Hand levels"
end

local function levels_section()
  local rows = HandFacts.levels()
  if #rows == 0 then return nil end

  local shown, partial = rows, false
  if not level_note() then
    shown = {}
    for _, row in ipairs(rows) do
      if row.level ~= 1 then shown[#shown + 1] = row end
    end
    if #shown == 0 then
      queue_base_values_once()
      return "Hand levels: all level 1."
    end
    partial = #shown < #rows
  end
  local lines = { "## " .. levels_heading() }
  for _, row in ipairs(shown) do
    lines[#lines + 1] = level_row(row)
  end
  if partial then
    lines[#lines + 1] = "(all other hands: level 1)"
    queue_base_values_once()
  end
  return table.concat(lines, "\n")
end

local function hand_focus_options_section()
  local rows = HandFacts.levels()
  if #rows == 0 then return nil end
  local names = {}
  for _, row in ipairs(rows) do names[#names + 1] = normalize_text(row.name) end
  return "Unlocked hand types: " .. table.concat(names, ", ") .. "; no other hand type is unlocked yet."
end

local function deck_cards_section()
  if not G or not G.deck or not G.deck.cards then return nil end
  local n = #G.deck.cards
  if n == 0 then return "0 cards left in the draw pile: a discard would replace nothing." end
  return tostring(n) .. " cards left in the draw pile."
end

local function aggregate_card(c)
  return type(c) == "table" and (PublicCard.is_public(c) or CardUtil.is_composition_public(c))
end

local function modifier_tally(cards, acc)
  acc = acc or { editions = {}, seals = {}, enhancements = {} }
  local unknown = 0
  local function tally(t, k)
    if not k or k == "" then return end
    t[tostring(k)] = (t[tostring(k)] or 0) + 1
  end
  for _, c in ipairs(cards or {}) do
    if not aggregate_card(c) then
      unknown = unknown + 1
    else
      tally(acc.editions, CardUtil.edition_name(c.edition))
      tally(acc.seals, CardUtil.seal_name(c.seal))
      tally(acc.enhancements, CardUtil.enhancement_name(CardUtil.enhancement_key(c)))
    end
  end
  return acc, unknown
end

local function unknown_card_note(unknown)
  local n = tonumber(unknown) or 0
  if n <= 0 then return "" end
  return "(" .. plural(n, "face-down card") .. " outside the deck, hand, discard pile and play area excluded from the tally: "
    .. n .. " unknown.)"
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

local function draw_composition_section()
  local pool, concealed, where = CardUtil.unplayed_pool()
  if not pool or #pool == 0 then return nil end
  local suits = { Hearts = 0, Spades = 0, Diamonds = 0, Clubs = 0 }
  local ranks, wild, stone, unknown = {}, 0, 0, 0
  for _, c in ipairs(pool) do
    if not aggregate_card(c) then
      unknown = unknown + 1
    else
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
        local id = CardUtil.rank_id(c)
        if id and id >= 2 and id <= 14 then
          ranks[id] = (ranks[id] or 0) + 1
        end
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
    if ranks[id] then rp[#rp + 1] = HandFacts.rank_label(id) .. " x" .. ranks[id] end
  end
  if #sp == 0 and #rp == 0 then return nil end
  local p = {}
  if (concealed or 0) > 0 then
    local extra = {}
    if (where.hand or 0) > 0 then extra[#extra + 1] = plural(where.hand, "face-down card") .. " in your hand" end
    if (where.discard or 0) > 0 then
      extra[#extra + 1] = plural(where.discard, "face-down card") .. " you discarded unseen"
    end
    if (where.other or 0) > 0 then extra[#extra + 1] = plural(where.other, "face-down card") .. " elsewhere" end
    p[#p + 1] = "Unplayed pool = the " .. plural(#pool - concealed, "card") .. " in the draw pile plus "
      .. table.concat(extra, " and ") .. ", which the game's deck view also counts as unplayed."
  end
  if #sp > 0 then p[#p + 1] = "Unplayed pool by suit: " .. table.concat(sp, ", ") .. "." end
  if #rp > 0 then p[#p + 1] = "Ranks in that pool: " .. table.concat(rp, ", ") .. "." end
  local mods = modifier_prose(modifier_tally(pool))
  if mods then p[#p + 1] = "Modifiers in that pool: " .. mods .. "." end
  local note = unknown_card_note(unknown)
  if note ~= "" then p[#p + 1] = note end
  return table.concat(p, " ")
end

local function deck_modifiers_section()
  if not G then return nil end
  local acc, scope, unknown
  if type(G.playing_cards) == "table" and #G.playing_cards > 0 then
    acc, unknown = modifier_tally(G.playing_cards)
    scope = "full deck"
  else
    local hand_cards, draw_cards = G.hand and G.hand.cards, G.deck and G.deck.cards
    acc, unknown = modifier_tally(hand_cards)
    local _, draw_unknown = modifier_tally(draw_cards, acc)
    unknown = unknown + draw_unknown
    scope = "hand + draw pile"
  end
  local groups = modifier_prose(acc)
  local note = unknown_card_note(unknown)
  if note ~= "" then note = " " .. note end
  if not groups then return "Card modifiers (" .. scope .. "): none." .. note end
  return "Card modifiers (" .. scope .. "): " .. groups .. "." .. note
end

local function play_area_section()
  if not (G and G.play and G.play.cards and #G.play.cards > 0) then return nil end
  local parts = {}
  for _, card in ipairs(G.play.cards) do
    parts[#parts + 1] = decode_card(card_token(card, true))
  end
  return "In play: " .. table.concat(parts, ", ") .. "."
end

local function last_play_section(state_name)
  local lp = G and G.NEURO and G.NEURO.last_play
  if type(lp) ~= "table" then return nil end
  if lp.kind == "discard" then
    local left = tonumber(lp.discards_left_after)
    local remaining = left and (", " .. plural(left, "discard") .. (left == 1 and " remains" or " remain")) or ""
    return "Last discard: replaced " .. plural(lp.played or 0, "card") .. remaining
      .. ". The current hand below is the result."
  end
  local out = "Last hand: " .. tostring(lp.hand_type or "?")
  out = out .. ", played " .. plural(lp.played or 0, "card")
  if lp.scored then out = out .. ", " .. tostring(lp.scored) .. " scored" end
  if lp.zeroed then out = out .. ", " .. lp.zeroed end
  local cur = G.GAME and tonumber(G.GAME.chips)
  local pre = tonumber(lp.pre_chips)
  local delta = tonumber(lp.chips_delta)
  if delta and cur and pre and cur ~= pre + delta then
    -- Cash-out eases the round score to zero; report this hand’s settled score separately.
    out = out .. ", +" .. fmt_num(delta) .. " chips"
  elseif cur and pre and (cur > pre or state_name == "ROUND_EVAL" or (lp.outcome_observed and cur >= pre)) then
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
M.levels_heading = levels_heading
M.deck_cards_section = deck_cards_section
M.draw_composition_section = draw_composition_section
M.deck_modifiers_section = deck_modifiers_section
M.hand_focus_options_section = hand_focus_options_section
M.play_area_section = play_area_section

return M
