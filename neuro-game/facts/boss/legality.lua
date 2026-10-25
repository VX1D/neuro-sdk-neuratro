local Model = require("facts.boss.model")
local M = {}

local DF = Model.debuff_facts

local function active_boss()
  local b = G and G.GAME and G.GAME.blind
  if type(b) ~= "table" or b.disabled then return nil end
  return b, Model.resolve_key(b)
end

local function hand_left()
  local cr = G and G.GAME and G.GAME.current_round
  return type(cr) == "table" and (tonumber(cr.hands_left) or 0) > 0
end

function M.play_size_bounds()
  local min_items = 1
  local max_items = require("core.plan_limits").play_select_max()
  local cards = G and G.hand and G.hand.cards
  if type(cards) == "table" then max_items = math.min(max_items, #cards) end
  local b = active_boss()
  local d = b and type(b.debuff) == "table" and b.debuff or nil
  if d then
    local ge = tonumber(d.h_size_ge)
    local le = tonumber(d.h_size_le)
    if ge and ge > 0 then min_items = math.max(min_items, math.floor(ge)) end
    if le and le > 0 then max_items = math.min(max_items, math.floor(le)) end
  end
  if min_items > max_items and max_items >= 1 and hand_left() then
    return 1, max_items, true
  end
  return min_items, max_items
end

function M.play_has_legal_size()
  local min_items, max_items = M.play_size_bounds()
  return min_items <= max_items
end

function M.play_floor_relaxed()
  local _, _, relaxed = M.play_size_bounds()
  return relaxed == true
end

function M.zeroed_note(handname)
  local b, key = active_boss()
  if not b then return nil end
  local rec = Model.get(key)
  local name = (rec and rec.name) or b.name or "boss"
  if key == "bl_eye" then
    return "zeroed by The Eye (already played this round)"
  end
  if key == "bl_mouth" then
    -- `only_hand` is the engine hand key; only the displayed name is localized.
    if b.only_hand and b.only_hand ~= handname then
      local df = DF()
      return "zeroed by The Mouth (locked to " .. (df.loc_hand(b.only_hand) or tostring(b.only_hand)) .. ")"
    end
    return "zeroed by The Mouth (boss rule)"
  end
  return "zeroed by " .. tostring(name) .. " (boss rule)"
end

-- These sales take effect only during a round.
local IN_ROUND_SELL = {
  Luchador = {
    note = "Luchador disables the current Boss Blind",
    live = function(b)
      if not b then return false end
      if type(b.get_type) == "function" then return b:get_type() == "Boss" end
      return b.boss == true
    end,
  },
}

local function in_round_sell(card)
  if type(card) ~= "table" or require("facts.card_util").is_hidden(card) then return nil end
  local name = type(card.ability) == "table" and card.ability.name
  local effect = name and IN_ROUND_SELL[name]
  return effect and effect.live((active_boss())) and effect or nil
end

local function sell_allowed_in_round(card)
  local b, key = active_boss()
  if key == "bl_final_leaf" and b ~= nil then return true end
  return card ~= nil and in_round_sell(card) ~= nil
end

function M.in_round_sell_note()
  local notes = {}
  for _, card in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    local effect = in_round_sell(card)
    if effect then notes[#notes + 1] = effect.note end
  end
  return #notes > 0 and table.concat(notes, "; ") or nil
end

function M.boss_names_reorder()
  local b, key = active_boss()
  return key == "bl_final_acorn" and b ~= nil
end

function M.sell_blocked_now(card)
  if require("core.state").get_state_name() ~= "SELECTING_HAND" then return false end
  return not sell_allowed_in_round(card)
end

M.MASK_HAND, M.MASK_FIELD = "????", "?"

function M.hidden_count(cards)
  local CardUtil = require("facts.card_util")
  local n = 0
  for _, c in ipairs(cards or {}) do
    if CardUtil.is_hidden(c) then n = n + 1 end
  end
  return n
end

function M.selection_hidden(cards)
  return M.hidden_count(cards) > 0
end

local function mask_text(n)
  local lead = n == 1 and "One selected card is" or (n .. " selected cards are")
  return lead .. " face down, so the game will not name this hand until " .. (n == 1 and "it flips." or "they flip.")
end

M.MASK_NOTE = mask_text(1)

function M.mask_note(cards)
  local n = M.hidden_count(cards)
  if n == 0 then return nil end
  return mask_text(n)
end

local function selection_line(indices, handname, level, chips, mult, score_level)
  local ix = "[" .. table.concat(indices or {}, ",") .. "]"
  if handname == M.MASK_HAND then
    return "Selection " .. ix .. " = hand type hidden: it includes a face-down card, and the game names the hand only once it flips."
  end
  local lvl = level ~= nil and ("lvl " .. tostring(level)
    .. ((score_level ~= nil and score_level ~= level) and (", scores at lvl " .. tostring(score_level) .. " when played") or ""))
  local detail = ""
  if lvl and chips ~= nil and mult ~= nil then
    detail = " (" .. lvl .. ", " .. tostring(chips) .. " chips x " .. tostring(mult) .. " mult)"
  elseif lvl then
    detail = " (" .. lvl .. ")"
  end
  return "Selection " .. ix .. " = " .. tostring(handname or "?") .. detail .. "."
end

M.selection_line = selection_line

function M.spend_line(hands_left, discards_left)
  local Text = require("facts.text")
  return "Playing spends 1 of " .. Text.plural(tonumber(hands_left) or 0, "hand")
    .. "; discarding spends 1 of " .. Text.plural(tonumber(discards_left) or 0, "discard") .. "."
end

local function resource_line()
  local parts = {}
  local ok_rem, remaining = pcall(function() return require("facts.economy_facts").blind_remaining() end)
  if ok_rem and type(remaining) == "number" then
    parts[#parts + 1] = require("util.utils").fmt_num(remaining) .. " to clear"
  end
  local GameFacts = require("facts.game_facts")
  parts[#parts + 1] = string.format("%d hand(s), %d discard(s) left", GameFacts.hands_left(), GameFacts.discards_left())
  return table.concat(parts, "; ") .. "."
end

local function pillar_contrast(selected_cards)
  local CardUtil = require("facts.card_util")
  if M.selection_hidden(selected_cards) then return nil end
  local _, key = active_boss()
  if key ~= "bl_pillar" then return nil end
  local Utils = require("util.utils")
  local sel_pos = {}
  local hand = G and G.hand and G.hand.cards or {}
  for _, c in ipairs(hand) do
    if CardUtil.is_hidden(c) then return nil end
  end
  for pos, c in ipairs(hand) do sel_pos[c] = pos end
  local rank_of = CardUtil.rank_id
  for _, c in ipairs(selected_cards or {}) do
    if type(c) == "table" and c.debuff and type(c.ability) == "table" and c.ability.played_this_ante then
      local r = rank_of(c)
      for pos, other in ipairs(hand) do
        if other ~= c and not other.debuff and r ~= nil and rank_of(other) == r then
          return string.format(" Card %s (%s) is +DB; card %d (%s) is the same rank and is not +DB.",
            tostring(sel_pos[c] or "?"), Utils.playing_card_label(c), pos, Utils.playing_card_label(other))
        end
      end
    end
  end
  return nil
end

local function boss_label(b, key)
  local rec = Model.get(key)
  return (key and Model.display_name(key)) or b.name or (rec and rec.name) or "this boss"
end

function M.play_verdict(selected_cards, indices)
  local b, key = active_boss()
  if not b then return nil end
  local df = DF()

  local hidden = M.selection_hidden(selected_cards)

  -- A face-down card hides the hand type, so do not classify this selection.
  local handname, values
  if not hidden then
    pcall(function()
      if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
        local text = G.FUNCS.get_poker_hand_info(selected_cards)
        if type(text) == "string" and text ~= "" then handname = text end
      end
      values = handname and require("facts.hand_facts").hand_values(handname)
    end)
  end
  local shown_level = hidden and M.MASK_FIELD or (values and values.level)
  local shown_score_level = values and values.score_level or nil

  local boss_fact
  local ok_bw, blocked, certain
  if hidden then
    ok_bw, blocked, certain = pcall(df.boss_would_debuff_concealed, selected_cards)
  else
    ok_bw, blocked, certain = pcall(df.boss_would_debuff, selected_cards, handname)
  end
  if not ok_bw then require("util.metrics").incr("boss_verdict_probe_failed") end
  if ok_bw and blocked then
    local rec = Model.get(key)
    if rec and rec.templates and rec.templates.rejection then
      boss_fact = require("facts.boss.render").render("rejection", key,
        { blind = b, vars = { handname = tostring(handname or "this hand type") } })
    else
      boss_fact = "BOSS (" .. tostring(boss_label(b, key)) .. "): the engine reports this hand scores 0 under this boss's rule."
    end
  elseif hidden and ok_bw and certain == false then
    boss_fact = "BOSS (" .. tostring(boss_label(b, key)) .. "): a face-down card hides this selection's hand type,"
      .. " so the boss rule cannot be checked -- it may score 0."
  elseif (not ok_bw) or certain == false then
    boss_fact = "BOSS (" .. tostring(boss_label(b, key)) .. "): the boss rule could not be checked for this"
      .. " selection -- it may score 0."
  elseif not hidden and df.count(selected_cards) > 0
    and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok_i, _, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, selected_cards)
    if ok_i and type(scoring_hand) == "table" and df.all_debuffed(scoring_hand) then
      boss_fact = "BOSS (" .. tostring(boss_label(b, key)) .. "): every scoring card in this selection is +DB -- debuffed"
        .. " cards add 0 chips and 0 mult; the base hand value and joker effects still score."
      local contrast = pillar_contrast(selected_cards)
      if contrast then boss_fact = boss_fact .. contrast end
    end
  end
  if not boss_fact then return nil end

  return selection_line(indices, hidden and M.MASK_HAND or handname, shown_level, nil, nil, shown_score_level)
    .. "\n" .. boss_fact .. "\n" .. resource_line()
end

return M
