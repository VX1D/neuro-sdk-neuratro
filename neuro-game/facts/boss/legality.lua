local Model = require("facts.boss.model")
local M = {}

local function DF()
  local ok, mod = pcall(require, "facts.debuff_facts")
  return ok and mod or nil
end

local function active_boss()
  local b = G and G.GAME and G.GAME.blind
  if type(b) ~= "table" or b.disabled then return nil end
  return b, Model.resolve_key(b)
end

local function only_the_hand_remains()
  local cr = G and G.GAME and G.GAME.current_round
  if type(cr) ~= "table" then return false end
  return (tonumber(cr.hands_left) or 0) > 0 and (tonumber(cr.discards_left) or 0) <= 0
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
  if min_items > max_items and max_items >= 1 and only_the_hand_remains() then
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
    local df = DF()
    local locked = b.only_hand and ((df and df.loc_hand and df.loc_hand(b.only_hand)) or tostring(b.only_hand))
    if locked and locked ~= tostring(handname) then
      return "zeroed by The Mouth (locked to " .. locked .. ")"
    end
    return "zeroed by The Mouth (boss rule)"
  end
  return "zeroed by " .. tostring(name) .. " (boss rule)"
end

function M.sell_allowed_in_round()
  local b, key = active_boss()
  return key == "bl_final_leaf" and b ~= nil
end

-- Amber Acorn shuffles the joker order at blind start (dump blind.lua:218-232), so reordering is a
-- live decision inside the round and set_joker_order has to stay on the offer.
function M.boss_names_reorder()
  local b, key = active_boss()
  return key == "bl_final_acorn" and b ~= nil
end

function M.sell_blocked_now()
  if require("core.state").get_state_name() ~= "SELECTING_HAND" then return false end
  return not M.sell_allowed_in_round()
end

M.MASK_HAND, M.MASK_FIELD = "????", "?"
M.MASK_NOTE = "One selected card is face down, so the game will not name this hand until it flips."

function M.selection_hidden(cards)
  local CardUtil = require("facts.card_util")
  for _, c in ipairs(cards or {}) do
    if CardUtil.is_face_down(c) then return true end
  end
  return false
end

local function selection_line(indices, handname, level, chips, mult)
  local ix = "[" .. table.concat(indices or {}, ",") .. "]"
  local detail = ""
  if level ~= nil and chips ~= nil and mult ~= nil then
    detail = " (lvl " .. tostring(level) .. ", " .. tostring(chips) .. " chips x " .. tostring(mult) .. " mult)"
  elseif level ~= nil then
    detail = " (lvl " .. tostring(level) .. ")"
  end
  return "Selection " .. ix .. " = " .. tostring(handname or "?") .. detail .. "."
end

M.selection_line = selection_line

function M.spend_line(hands_left, discards_left)
  return string.format("Playing spends 1 of %d hands; discarding spends 1 of %d discards.",
    tonumber(hands_left) or 0, tonumber(discards_left) or 0)
end

local function resource_line()
  local parts = {}
  local ok_rem, remaining = pcall(function() return require("facts.economy_facts").blind_remaining() end)
  if ok_rem and type(remaining) == "number" then
    parts[#parts + 1] = require("util.utils").fmt_num(remaining) .. " to clear"
  end
  local GameFacts = require("facts.game_facts")
  parts[#parts + 1] = string.format("%d hand(s), %d discard(s) left", GameFacts.hands_left(), GameFacts.discards_left())
  return table.concat(parts, "; ") .. ". Resend the same indices to commit this play."
end

local function pillar_contrast(selected_cards)
  local _, key = active_boss()
  if key ~= "bl_pillar" then return nil end
  local Utils = require("util.utils")
  local sel_pos = {}
  local hand = G and G.hand and G.hand.cards or {}
  for pos, c in ipairs(hand) do sel_pos[c] = pos end
  local rank_of = function(c)
    if type(c.get_id) == "function" then
      local ok, id = pcall(function() return c:get_id() end)
      if ok then return id end
    end
    return nil
  end
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

function M.play_verdict(selected_cards, indices)
  local b, key = active_boss()
  if not b then return nil end
  local df = DF()
  if not df then return nil end
  local handname, level
  pcall(function()
    if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
      local text = G.FUNCS.get_poker_hand_info(selected_cards)
      if type(text) == "string" and text ~= "" then handname = text end
    end
    local hd = handname and G.GAME and G.GAME.hands and G.GAME.hands[handname]
    if type(hd) == "table" then level = hd.level end
  end)
  local hidden = M.selection_hidden(selected_cards)
  local shown_name = hidden and nil or handname
  local shown_level = hidden and M.MASK_FIELD or level

  local boss_fact
  local ok_bw, blocked, certain = pcall(df.boss_would_debuff, selected_cards, handname)
  if not ok_bw then require("util.metrics").incr("boss_verdict_probe_failed") end
  if ok_bw and blocked then
    local rec = Model.get(key)
    if rec and rec.templates and rec.templates.rejection then
      boss_fact = require("facts.boss.render").render("rejection", key,
        { blind = b, vars = { handname = tostring(shown_name or "this hand type") } })
    else
      local name = (key and Model.boss_name(key)) or b.name or (rec and rec.name) or "this boss"
      boss_fact = "BOSS (" .. tostring(name) .. "): the engine reports this hand scores 0 under this boss's rule."
    end
  elseif (not ok_bw) or certain == false then
    local rec = Model.get(key)
    local name = (key and Model.boss_name(key)) or b.name or (rec and rec.name) or "this boss"
    boss_fact = "BOSS (" .. tostring(name) .. "): the boss rule could not be checked for this"
      .. " selection -- it may score 0."
  elseif df.all_debuffed and df.count and df.count(selected_cards) > 0
    and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok_i, _, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, selected_cards)
    if ok_i and type(scoring_hand) == "table" and df.all_debuffed(scoring_hand) then
      local rec = Model.get(key)
      local name = (key and Model.boss_name(key)) or b.name or (rec and rec.name) or "this boss"
      boss_fact = "BOSS (" .. tostring(name) .. "): every scoring card in this selection is +DB -- debuffed"
        .. " cards add 0 chips and 0 mult; the base hand value and joker effects still score."
      local contrast = pillar_contrast(selected_cards)
      if contrast then boss_fact = boss_fact .. contrast end
    end
  end
  if not boss_fact then return nil end

  return selection_line(indices, hidden and M.MASK_HAND or shown_name, shown_level)
    .. "\n" .. boss_fact .. "\n" .. resource_line()
end

return M
