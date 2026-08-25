local GameFacts = require("facts.game_facts")
local DebuffFacts = require("facts.debuff_facts")
local CardUtil = require("facts.card_util")
local NUMERIC_EFFECTS = require("facts.numeric_effects")
local DeckNames = require("facts.deck_names")
local Scoring = require("util.scoring")
local PublicCard = require("facts.public_card_identity")
local Utils = require("util.utils")
local M = {}

local HAND_VALUE_RANK = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
  ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
  Jack = 11, Queen = 12, King = 13, Ace = 14,
}

local HAND_RANK_LABEL = {
  [14] = "A", [13] = "K", [12] = "Q", [11] = "J", [10] = "10",
  [9] = "9", [8] = "8", [7] = "7", [6] = "6", [5] = "5",
  [4] = "4", [3] = "3", [2] = "2",
}

local HAND_ORDER = {
  ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4,
  ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8,
  ["Straight Flush"] = 9, ["Five of a Kind"] = 10, ["Flush House"] = 11, ["Flush Five"] = 12,
}

local function smods() return rawget(_G, "SMODS") end
local function sm(fn, arg)
  local SM = smods()
  if SM and type(SM[fn]) == "function" then
    local ok, v = pcall(SM[fn], arg)
    if ok then return v end
  end
  return nil
end
local function has_no_suit(card)
  local SM = smods()
  if SM and type(SM.has_no_suit) == "function" then
    local ok, v = pcall(SM.has_no_suit, card); if ok and v then return true end
  end
  local ck = card and card.config and card.config.center and card.config.center.key
  return ck == "m_stone"
end
local has_no_rank = CardUtil.has_no_rank
local function rank_of(card)
  if card and type(card.get_id) == "function" then
    local ok, id = pcall(card.get_id, card); if ok and type(id) == "number" then return id end
  end
  local base = card and card.base
  return base and HAND_VALUE_RANK[tostring(base.value)] or nil
end
local BASE_SUITS = { "Hearts", "Diamonds", "Spades", "Clubs" }
local function suit_list()
  local SM = smods()
  return (SM and SM.Suit and SM.Suit.obj_buffer and #SM.Suit.obj_buffer > 0)
    and SM.Suit.obj_buffer or BASE_SUITS
end

local SUIT_COLOR = { Hearts = "red", Diamonds = "red", Spades = "black", Clubs = "black" }
local function smeared_active()
  if not (G and G.jokers and G.jokers.cards) then return false end
  for i, jc in ipairs(G.jokers.cards) do
    local ck = (type(jc) == "table" and not jc.debuff)
      and PublicCard.multiset_key(jc, "jokers", i) or nil
    if ck == "center:j_smeared" then return true end
  end
  return false
end

local function smeared_concealed()
  if not (G and G.jokers and G.jokers.cards) then return false end
  for _, jc in ipairs(G.jokers.cards) do
    if type(jc) == "table" and not jc.debuff and not PublicCard.is_public(jc) then
      local center = jc.config and jc.config.center
      if center and center.key == "j_smeared" then return true end
    end
  end
  return false
end

local function any_suit_on_face(card)
  if sm("has_any_suit", card) then return true end
  local ck = card and card.config and card.config.center and card.config.center.key
  return ck == "m_wild"
end

local function in_suit(card, suit)
  local yes
  if card and type(card.is_suit) == "function" then
    local ok, v = pcall(card.is_suit, card, suit, true, true)
    if ok then yes = v and true or false end
  end
  if yes == nil then
    local base = card and card.base
    yes = (base and tostring(base.suit) == suit) or false
  end
  if yes and not smeared_active() and smeared_concealed() and not any_suit_on_face(card) then
    local own = card and card.base and card.base.suit
    if own ~= nil and tostring(own) ~= suit then return false end
  end
  return yes
end

local function count_suits(cards)
  local res, max_suit = {}, 0
  for _, s in ipairs(suit_list()) do
    local key = (type(s) == "table" and (s.key or s.name)) or s
    local n = 0
    for _, c in ipairs(cards) do if not has_no_suit(c) and in_suit(c, key) then n = n + 1 end end
    res[key] = n
    if n > max_suit then max_suit = n end
  end
  return res, max_suit
end

local function count_ranks(cards)
  local counts, present = {}, {}
  for _, c in ipairs(cards) do
    if not has_no_rank(c) then
      local rid = rank_of(c)
      if rid and rid >= 2 then
        counts[rid] = (counts[rid] or 0) + 1
        present[rid] = true
        if rid == 14 then present[1] = true end
      end
    end
  end
  return counts, present
end

local function rank_top(rank_counts, min_count, exclude)
  local best
  for rid, n in pairs(rank_counts) do
    if n >= min_count and rid ~= exclude and (not best or rid > best) then best = rid end
  end
  return best
end

local function max_run_of(present)
  local shortcut = sm("shortcut") and true or false
  local function run_from(start)
    local len, r, ranks = 1, start, { [start] = true }
    while true do
      if present[r + 1] then r = r + 1
      elseif shortcut and present[r + 2] then r = r + 2
      else break end
      len = len + 1
      ranks[r] = true
    end
    return len, ranks
  end
  local max_run, best_ranks = 0, {}
  for start = 1, 14 do
    if present[start] then
      local len, ranks = run_from(start)
      if len > max_run then max_run, best_ranks = len, ranks end
    end
  end
  return max_run, best_ranks
end

local function near_straight_window(present, thr)
  if not thr or thr < 2 then return false end
  for w = 1, 15 - thr do
    local cnt = 0
    for r = w, w + thr - 1 do if present[r] then cnt = cnt + 1 end end
    if cnt == thr - 1 then return true end
  end
  return false
end

local function straight_outs(present, thr)
  local outs, n = {}, 0
  if not thr or thr < 2 then return outs, 0 end
  for r = 2, 14 do
    if not present[r] then
      local probe = {}
      for k, v in pairs(present) do probe[k] = v end
      probe[r] = true
      if r == 14 then probe[1] = true end
      if max_run_of(probe) >= thr then outs[r] = true; n = n + 1 end
    end
  end
  return outs, n
end

local function best_near_straight_ranks(present, thr)
  if not thr or thr < 2 then return nil end
  local remaining = {}
  local pool = CardUtil.unplayed_pool()
  for _, c in ipairs(pool or {}) do
    if not has_no_rank(c) then
      local r = rank_of(c)
      if r then remaining[r] = (remaining[r] or 0) + 1 end
    end
  end
  local best_w, best_cnt, best_outs = nil, 0, -1
  for w = 1, 15 - thr do
    local cnt, outs = 0, 0
    for r = w, w + thr - 1 do
      if present[r] then
        cnt = cnt + 1
      else
        outs = outs + (remaining[r == 1 and 14 or r] or 0)
      end
    end
    if cnt > best_cnt or (cnt == best_cnt and outs > best_outs) then
      best_cnt, best_w, best_outs = cnt, w, outs
    end
  end
  if best_w and best_cnt == thr - 1 then
    local set, missing = {}, {}
    for r = best_w, best_w + thr - 1 do
      if present[r] then set[r] = true else missing[r] = true end
    end
    return set, missing
  end
  return nil
end

local function shape(cards)
  local suit_counts, max_suit = count_suits(cards)
  local rank_counts, present = count_ranks(cards)
  local max_run, run_ranks = max_run_of(present)
  local flush_thr = tonumber(sm("four_fingers", "flush")) or 5
  local straight_thr = tonumber(sm("four_fingers", "straight")) or 5
  local straight_out_count = 0
  if max_run < straight_thr then
    local _, count = straight_outs(present, straight_thr)
    straight_out_count = count
  end
  local pair_count, trips_count, quad_count, high_pair_rank = 0, 0, 0, 0
  for rid, count in pairs(rank_counts) do
    if count >= 2 then pair_count = pair_count + 1; if rid > high_pair_rank then high_pair_rank = rid end end
    if count >= 3 then trips_count = trips_count + 1 end
    if count >= 4 then quad_count = quad_count + 1 end
  end
  return {
    max_suit = max_suit, max_run = max_run, run_ranks = run_ranks,
    flush_thr = flush_thr, straight_thr = straight_thr,
    flush_ready = max_suit >= flush_thr, near_flush = flush_thr > 1 and max_suit == flush_thr - 1,
    straight_ready = max_run >= straight_thr,
    near_straight = max_run < straight_thr and straight_out_count > 0,
    pairs = pair_count, trips = trips_count, quads = quad_count,
    high_pair_rank = high_pair_rank,
  }, rank_counts, present, suit_counts
end

local function positions_of(set)
  local out = {}
  if type(set) ~= "table" or not (G and G.hand and G.hand.cards) then return out end
  local pos = {}
  for i, c in ipairs(G.hand.cards) do pos[c] = i end
  local seen = {}
  DebuffFacts.for_each_leaf_card(set, function(c)
    local i = pos[c]
    if i and not seen[i] then seen[i] = true; out[#out + 1] = i end
  end)
  table.sort(out)
  return out
end

local function play_cap()
  return CardUtil.highlight_limit()
end

local function discard_cap()
  local ok, n = pcall(function()
    return math.max(1, require("core.plan_limits").discard_select_max())
  end)
  return (ok and n) or CardUtil.highlight_limit()
end

local function active_boss_key()
  local b = G and G.GAME and G.GAME.blind
  if type(b) ~= "table" or b.disabled or not b.in_blind then return nil end
  local ok, key = pcall(function() return require("facts.boss.model").resolve_key(b) end)
  return ok and key or nil
end

local function arm_active()
  return active_boss_key() == "bl_arm"
end

local function arm_drop(level, chips, mult, hd)
  if not arm_active() or (level or 1) <= 1 then return level, chips, mult end
  local lc, lm = tonumber(hd and hd.l_chips), tonumber(hd and hd.l_mult)
  if not (lc and lm) then return level, chips, mult end
  return level - 1, math.max(chips - lc, 0), math.max(mult - lm, 1)
end

-- Plasma balances chips against mult at final_scoring_step (back.lua:157-160), so the PRODUCT of a
-- hand's two printed factors is not the score it makes; the factors themselves are untouched.
local function plasma_balances()
  local c = DeckNames.current_deck_center()
  return not not (c and c.key == "b_plasma")
end

local function draws_after_discard(d)
  d = tonumber(d) or 0
  if d < 1 then return 0 end
  local hand = G and G.hand
  local held = (hand and hand.cards and #hand.cards) or 0
  local cap = (hand and hand.config and tonumber(hand.config.card_limit)) or held
  local pile = (G and G.deck and G.deck.cards and #G.deck.cards) or nil
  local k = math.max(cap - (held - d), 0)
  if pile then
    if active_boss_key() == "bl_serpent" then
      k = math.min(pile, 3)
    elseif k > pile then
      k = pile
    end
  end
  return k
end

local function best_group(set)
  if type(set) ~= "table" then return {} end
  if type(set[1]) == "table" and type(set[1][1]) == "table" then return set[1] end
  return set
end

local ENH_VALUE = {
  m_bonus = 30, m_mult = 15, m_glass = 20, m_lucky = 10,
  m_gold = -5, m_steel = -8, m_wild = 0,
}
local function play_value(card)
  if not card or card.debuff then return 0 end
  local r = rank_of(card)
  local v
  if not r or r < 2 then v = 0
  elseif r >= 14 then v = 11
  elseif r >= 11 then v = 10
  else v = r end
  local ek = CardUtil.enhancement_key(card)
  if ek and ENH_VALUE[ek] then v = v + ENH_VALUE[ek] end
  local ed = card.edition
  if type(ed) == "table" then
    if ed.foil then v = v + 50 end
    if ed.holo or ed.holographic then v = v + 25 end
    if ed.polychrome then v = v + 30 end
  end
  if v < 1 then v = 1 end
  return v
end

local function better_copy(a, b)
  if not a then return true end
  return play_value(b) > play_value(a)
end

local function sort_by_play_value(list, order, priority)
  table.sort(list, function(a, b)
    if priority then
      local ap, bp = priority(a), priority(b)
      if ap ~= bp then return ap > bp end
    end
    local av, bv = play_value(a), play_value(b)
    if av ~= bv then return av > bv end
    return (order[a] or 0) < (order[b] or 0)
  end)
end

local function suit_key_of(s) return (type(s) == "table" and (s.key or s.name)) or s end

local function rank_copies(cards)
  local by, ord = {}, {}
  for i, c in ipairs(cards) do
    ord[c] = i
    if not has_no_rank(c) then
      local r = rank_of(c)
      if r and r >= 2 then
        by[r] = by[r] or {}
        by[r][#by[r] + 1] = c
      end
    end
  end
  for _, list in pairs(by) do
    sort_by_play_value(list, ord)
  end
  return by
end

local function dedup_run(group)
  local by, order = {}, {}
  for _, c in ipairs(group) do
    local r = rank_of(c)
    if r then
      if not by[r] then order[#order + 1] = r end
      if better_copy(by[r], c) then by[r] = c end
    end
  end
  local out = {}
  for _, r in ipairs(order) do out[#out + 1] = by[r] end
  return out
end

local function best_window(seq, L)
  if #seq <= L then return seq end
  local best_i, best_c = 1, -1
  for i = 1, #seq - L + 1 do
    local s = 0
    for j = i, i + L - 1 do s = s + play_value(seq[j]) end
    if s >= best_c then best_c, best_i = s, i end
  end
  local out = {}
  for j = best_i, best_i + L - 1 do out[#out + 1] = seq[j] end
  return out
end

local function best_straight_flush_set(group, straight_thr, flush_thr, cap)
  local shortcut = sm("shortcut") and true or false
  local best, best_v = nil, -1
  for _, s in ipairs(suit_list()) do
    local key = suit_key_of(s)
    local by, ord, suited = {}, {}, {}
    for i, c in ipairs(group) do
      ord[c] = i
      if not has_no_suit(c) and in_suit(c, key) then suited[#suited + 1] = c end
      if not has_no_rank(c) then
        local r = rank_of(c)
        if r and r >= 2 then
          by[r] = by[r] or {}
          by[r][#by[r] + 1] = c
        end
      end
    end
    local function suit_priority(card)
      return ((not has_no_suit(card)) and in_suit(card, key)) and 1 or 0
    end
    for _, list in pairs(by) do
      sort_by_play_value(list, ord, suit_priority)
    end
    sort_by_play_value(suited, ord)
    by[1] = by[14]
    local function consider_run(seq)
      local set, used, n_suited = {}, {}, 0
      for _, rk in ipairs(seq) do
        local c = by[rk][1]
        if used[c] then return end
        set[#set + 1] = c; used[c] = true
        if not has_no_suit(c) and in_suit(c, key) then n_suited = n_suited + 1 end
      end
      for _, c in ipairs(suited) do
        if n_suited >= flush_thr or #set >= cap then break end
        if not used[c] then
          set[#set + 1] = c; used[c] = true; n_suited = n_suited + 1
        end
      end
      if n_suited < flush_thr then return end
      local pool = {}
      for _, c in ipairs(suited) do if not used[c] then pool[#pool + 1] = c end end
      for _, rk in ipairs(seq) do
        for _, c in ipairs(by[rk]) do
          if not used[c] then pool[#pool + 1] = c end
        end
      end
      sort_by_play_value(pool, ord)
      for _, c in ipairs(pool) do
        if #set >= cap then break end
        if not used[c] then set[#set + 1] = c; used[c] = true end
      end
      local v = 0
      for _, c in ipairs(set) do v = v + play_value(c) end
      if v > best_v then best_v, best = v, set end
    end
    local seq = {}
    local function dfs(r)
      seq[#seq + 1] = r
      if #seq >= straight_thr then consider_run(seq) end
      if #seq < cap then
        if r + 1 <= 14 and by[r + 1] then dfs(r + 1) end
        if shortcut and r + 2 <= 14 and by[r + 2] then dfs(r + 2) end
      end
      seq[#seq] = nil
    end
    for start = 1, 14 do
      if by[start] then dfs(start) end
    end
  end
  return best
end

local function best_flush_set(name, group, flush_thr, cap)
  local best, best_c = nil, -1
  for _, s in ipairs(suit_list()) do
    local key = suit_key_of(s)
    local by, ord = {}, {}
    for i, c in ipairs(group) do
      ord[c] = i
      if not has_no_rank(c) then
        local r = rank_of(c)
        if r and r >= 2 then
          by[r] = by[r] or {}
          by[r][#by[r] + 1] = c
        end
      end
    end
    for _, list in pairs(by) do
      sort_by_play_value(list, ord, function(card)
        return ((not has_no_suit(card)) and in_suit(card, key)) and 1 or 0
      end)
    end
    local function consider(cards)
      if #cards == 0 or #cards > cap then return end
      local suited = 0
      for _, c in ipairs(cards) do
        if not has_no_suit(c) and in_suit(c, key) then suited = suited + 1 end
      end
      if suited < flush_thr then return end
      local sc = 0
      for _, c in ipairs(cards) do sc = sc + play_value(c) end
      if sc > best_c then best_c, best = sc, cards end
    end
    local rids = {}
    for r in pairs(by) do rids[#rids + 1] = r end
    table.sort(rids, function(x, y) return x > y end)
    if name == "Flush Five" then
      for _, r in ipairs(rids) do
        local list = by[r]
        if #list >= 5 then consider({ list[1], list[2], list[3], list[4], list[5] }) end
      end
    else
      for _, a in ipairs(rids) do
        local la = by[a]
        if #la >= 3 then
          for _, b in ipairs(rids) do
            local lb = by[b]
            if b ~= a and #lb >= 2 then
              consider({ la[1], la[2], la[3], lb[1], lb[2] })
            end
          end
        end
      end
    end
  end
  return best
end

local NATURAL_SIZE = {
  ["High Card"] = 1, ["Pair"] = 2, ["Three of a Kind"] = 3,
  ["Four of a Kind"] = 4, ["Five of a Kind"] = 5,
}

local VERIFY_REBUILT = {
  ["Straight"] = true, ["Straight Flush"] = true,
  ["Flush House"] = true, ["Flush Five"] = true,
  ["Full House"] = true, ["Two Pair"] = true,
}

local function best_scoring_cards(name, set)
  local cap = play_cap()
  local out = {}
  for _, c in ipairs(best_group(set)) do out[#out + 1] = c end
  if name == "Flush" then
    local ord = {}
    for i, c in ipairs(out) do ord[c] = i end
    sort_by_play_value(out, ord)
  elseif name == "Straight" then
    local seq = dedup_run(out)
    local win = best_window(seq, math.min(#seq, cap))
    if #win < cap then
      local used, wr, ordp = {}, {}, {}
      for _, c in ipairs(win) do
        used[c] = true
        local r = rank_of(c); if r then wr[r] = true end
      end
      local pool = {}
      for i, c in ipairs(out) do
        ordp[c] = i
        local r = rank_of(c)
        if r and wr[r] and not used[c] then pool[#pool + 1] = c end
      end
      sort_by_play_value(pool, ordp)
      for _, c in ipairs(pool) do
        if #win >= cap then break end
        win[#win + 1] = c
      end
    end
    out = win
  elseif name == "Straight Flush" then
    out = best_straight_flush_set(out,
      tonumber(sm("four_fingers", "straight")) or 5,
      tonumber(sm("four_fingers", "flush")) or 5, cap) or {}
  elseif name == "Flush House" or name == "Flush Five" then
    out = best_flush_set(name, out, tonumber(sm("four_fingers", "flush")) or 5, cap) or {}
  elseif name == "Full House" or name == "Two Pair" then
    local by = rank_copies(out)
    local want = (name == "Full House") and 3 or 2
    local a, b
    for r, list in pairs(by) do if #list >= want and (not a or r > a) then a = r end end
    for r, list in pairs(by) do if r ~= a and #list >= 2 and (not b or r > b) then b = r end end
    if a and b then
      local kept = {}
      for k = 1, want do kept[#kept + 1] = by[a][k] end
      for k = 1, 2 do kept[#kept + 1] = by[b][k] end
      out = kept
    else
      out = {}
    end
  elseif NATURAL_SIZE[name] then
    local n = NATURAL_SIZE[name]
    if #out > n then
      local ord = {}
      for i, c in ipairs(out) do ord[c] = i end
      sort_by_play_value(out, ord)
      while #out > n do table.remove(out) end
    end
  end
  while #out > cap do table.remove(out) end
  return out
end

local contained_cache = setmetatable({}, { __mode = "k" })
local contained_types

local function contained_types_cached(cards)
  if type(cards) ~= "table" then return {} end
  local hit = contained_cache[cards]
  if hit then return hit end
  local t = contained_types(cards)
  contained_cache[cards] = t
  return t
end

local function with_type(cards, name)
  return setmetatable({ [name] = true }, { __index = contained_types_cached(cards) })
end

function contained_types(cards)
  local t = {}
  if type(cards) ~= "table" or #cards == 0 then return t end
  local sh, counts = shape(cards)
  local n2, n3, n4, n5 = 0, 0, 0, 0
  for _, c in pairs(counts) do
    if c >= 2 then n2 = n2 + 1 end
    if c >= 3 then n3 = n3 + 1 end
    if c >= 4 then n4 = n4 + 1 end
    if c >= 5 then n5 = n5 + 1 end
  end
  t["High Card"] = true
  if n5 > 0 then t["Five of a Kind"] = true end
  if n4 > 0 then t["Four of a Kind"] = true end
  if n3 > 0 then t["Three of a Kind"] = true end
  if n2 > 0 then t["Pair"] = true end
  if n3 >= 1 and n2 >= 2 then t["Full House"] = true end
  if n2 >= 2 then t["Two Pair"] = true end
  if sh.straight_ready then t["Straight"] = true end
  if sh.flush_ready then
    t["Flush"] = true
    if sh.straight_ready then t["Straight Flush"] = true end
    local fthr = sh.flush_thr or 5
    local suits = suit_list()
    local rank_total, rs = {}, {}
    for _, c in ipairs(cards) do
      if not has_no_rank(c) then
        local r = rank_of(c)
        if r then
          rank_total[r] = (rank_total[r] or 0) + 1
          for _, s in ipairs(suits) do
            if in_suit(c, s) then
              rs[s] = rs[s] or {}
              rs[s][r] = (rs[s][r] or 0) + 1
            end
          end
        end
      end
    end
    for r, tot in pairs(rank_total) do
      if tot >= 5 then
        for _, s in ipairs(suits) do
          if (rs[s] and rs[s][r] or 0) >= fthr then t["Flush Five"] = true end
        end
      end
    end
    for r3, c3 in pairs(rank_total) do
      if c3 >= 3 then
        for r2, c2 in pairs(rank_total) do
          if r2 ~= r3 and c2 >= 2 then
            for _, s in ipairs(suits) do
              local sc = rs[s] or {}
              if math.min(3, sc[r3] or 0) + math.min(2, sc[r2] or 0) >= fthr then
                t["Flush House"] = true
              end
            end
          end
        end
      end
    end
  end
  return t
end

local function idx_suffix(ix)
  if type(ix) ~= "table" or #ix == 0 then return "" end
  local s = {}
  for i, v in ipairs(ix) do s[i] = tostring(v) end
  return "[" .. table.concat(s, ",") .. "]"
end

local function level_note(name)
  local hd = G and G.GAME and G.GAME.hands and G.GAME.hands[name]
  if type(hd) ~= "table" then return "" end
  local lv = tonumber(hd.level) or 1
  local ch, mu = tonumber(hd.chips) or 0, tonumber(hd.mult) or 0
  lv, ch, mu = arm_drop(lv, ch, mu, hd)
  if DebuffFacts.flint_active() then ch, mu = DebuffFacts.flint_halve(ch, mu) end
  return string.format("(lv%g %gc x%g)", lv, ch, mu)
end

local function type_conditional_jokers()
  local map
  if not (G and G.jokers and G.jokers.cards) then return nil end
  for i, jc in ipairs(G.jokers.cards) do
    -- Amber Acorn (blind.lua:222-231) flips the row and shuffles it three times: the slot of a
    -- face-down joker IS the fact the boss removes, so it may not be recorded, let alone printed.
    local ab = type(jc) == "table" and not jc.debuff and PublicCard.is_public(jc) and jc.ability
    local ht = type(ab) == "table" and ab.type
    if type(ht) == "string" and ht ~= "" then
      for _, e in ipairs(NUMERIC_EFFECTS) do
        local v = NUMERIC_EFFECTS.read(ab, e)
        if e.gate == "hand_type" and v and v ~= e.skip then
          map = map or {}
          map[ht] = map[ht] or {}
          map[ht][#map[ht] + 1] = i
          break
        end
      end
    end
  end
  return map
end

local function agg_text(agg)
  if type(agg) ~= "table" then return "" end
  local p = {}
  if (agg.chips or 0) ~= 0 then p[#p + 1] = Utils.signed(agg.chips, "c") end
  if (agg.mult or 0) ~= 0 then p[#p + 1] = Utils.signed(agg.mult, "m") end
  if (agg.xmult or 1) ~= 1 then p[#p + 1] = Utils.fmt_xmult(agg.xmult) end
  if (agg.xchips or 1) ~= 1 then p[#p + 1] = Utils.fmt_xmult(agg.xchips) .. "c" end
  if #p == 0 then return "" end
  return table.concat(p, " ")
end

local function joker_note(matches, agg)
  if type(matches) ~= "table" or #matches == 0 then return "" end
  local s = {}
  for i, v in ipairs(matches) do s[i] = "J" .. tostring(v) end
  local val = agg_text(agg)
  if val ~= "" then val = " " .. val else val = (#s > 1 and " apply" or " applies") end
  return "(" .. table.concat(s, ",") .. val .. ")"
end

local function guaranteed_note(g)
  if not g then return "" end
  local val = agg_text(g)
  if val == "" then return "" end
  return "(jokers-always: " .. val .. ")"
end

local function cond_note(agg)
  local val = agg_text(agg)
  if val == "" then return "" end
  return "(jokers: " .. val .. ")"
end

local STRONG_READY = {
  Straight = true, Flush = true, ["Full House"] = true, ["Four of a Kind"] = true,
  ["Straight Flush"] = true, ["Five of a Kind"] = true, ["Flush House"] = true, ["Flush Five"] = true,
}

local _ready_order_cache = {}
local function fisher_yates(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = math.random(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end
local shuffle_impl = fisher_yates
if rawget(_G, "NEURO_TEST") then
  M._set_shuffle = function(fn) shuffle_impl = fn or fisher_yates end
end

local _strong_cache = { sig = nil, val = false }
local function strong_sig()
  if not (G and G.hand and G.hand.cards) then return nil end
  local t = {}
  t[#t + 1] = "g" .. tostring((G.NEURO and G.NEURO.run_generation) or 0)
  for _, c in ipairs(G.hand.cards) do
    local base = c and c.base or {}
    t[#t + 1] = table.concat({
      tostring(c), tostring(base.value or "-"), tostring(base.suit or "-"),
      c.debuff and "!" or "", CardUtil.is_face_down(c) and "fd" or "up",
    }, "/")
  end
  t[#t + 1] = tostring((G.jokers and G.jokers.cards and #G.jokers.cards) or 0)
  t[#t + 1] = tostring(tonumber(sm("four_fingers", "flush")) or 5)
  t[#t + 1] = tostring(tonumber(sm("four_fingers", "straight")) or 5)
  t[#t + 1] = sm("shortcut") and "sc1" or "sc0"
  return table.concat(t, ";")
end

local function n_face_down(cards)
  local n = 0
  for _, c in ipairs(cards or {}) do if CardUtil.is_face_down(c) then n = n + 1 end end
  return n
end

local function hand_structure_summary()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return ""
  end

  local n_fd = n_face_down(G.hand.cards)
  local fd_lead = ""
  local cards = G.hand.cards
  local hand_pos = {}
  for i, c in ipairs(G.hand.cards) do hand_pos[c] = i end
  if n_fd > 0 then
    local visible = #G.hand.cards - n_fd
    local fish_discards_faceup = DebuffFacts.fish_discards_faceup()
    if visible == 0 then
      if fish_discards_faceup then
        return string.format(
          "Structure: all %d cards face-down (hidden), 0 visible. Under The Fish, discarding hidden "
          .. "cards draws face-up replacements; playing makes its replacement draws face-down. Your call. ",
          n_fd)
      end
      return string.format(
        "Structure: all %d cards face-down (hidden), 0 visible. No hand analysis is possible until they "
        .. "flip; any play or discard here is blind (fresh draws may also come face-down). Your call. ",
        n_fd)
    end
    if fish_discards_faceup then
      fd_lead = string.format(
        "%d card(s) face-down (hidden), %d visible. Under The Fish, discarding hidden cards draws "
        .. "face-up replacements, while replacements after a play are face-down. The one-card-away "
        .. "odds below are withheld until every card is visible. ", n_fd, visible)
    else
      fd_lead = string.format(
        "%d card(s) face-down (hidden), %d visible. "
        .. "Decide from the visible cards -- discarding here is a blind gamble (you cannot see if it helps, "
        .. "fresh draws may also come face-down, and the one-card-away odds below are withheld while a card "
        .. "is hidden), so prefer playing your best hand from what you can see over burning discards. ",
        n_fd, visible)
    end
    local vis = {}
    for _, c in ipairs(G.hand.cards) do
      if not CardUtil.is_face_down(c) then vis[#vis + 1] = c end
    end
    cards = vis
  end

  local debuffed = DebuffFacts.count(cards)
  local has_restr = DebuffFacts.has_hand_restriction()

  local facedown = DebuffFacts.boss_draws_facedown()

  local sh, rank_counts, present_ranks, suit_counts = shape(cards)
  local rank_copies_memo
  local function copies_by_rank()
    rank_copies_memo = rank_copies_memo or rank_copies(cards)
    return rank_copies_memo
  end
  local function top_rank(min_count, exclude) return rank_top(rank_counts, min_count, exclude) end
  local pair_count, trips_count = sh.pairs, sh.trips
  local has3, has4 = sh.trips > 0, sh.quads > 0
  local high_pair_rank = sh.high_pair_rank
  local max_suit, max_run = sh.max_suit, sh.max_run
  local flush_thr, straight_thr = sh.flush_thr, sh.straight_thr

  local min_play = 0
  do
    local d = G.GAME and G.GAME.blind and not G.GAME.blind.disabled and G.GAME.blind.debuff
    if type(d) == "table" then min_play = tonumber(d.h_size_ge) or 0 end
  end
  local HAND_PLAY_SIZE = {
    ["Pair"] = 2, ["Two Pair"] = 4, ["Three of a Kind"] = 3, ["Four of a Kind"] = 4,
    ["Full House"] = 5, ["Five of a Kind"] = 5, ["Flush House"] = 5, ["Flush Five"] = 5,
    ["Straight"] = straight_thr, ["Flush"] = flush_thr, ["Straight Flush"] = math.max(straight_thr, flush_thr),
  }
  local function floor_note(name)
    if min_play > (HAND_PLAY_SIZE[name] or min_play) then return "(play " .. min_play .. "+ cards)" end
    return ""
  end
  local function deb_in_ix(ix)
    local n = 0
    for _, i in ipairs(ix) do local c = G.hand.cards[i]; if c and c.debuff then n = n + 1 end end
    return n
  end
  local function others_of(ix)
    local inx = {}
    for _, i in ipairs(ix) do inx[i] = true end
    local rest = {}
    for _, c in ipairs(cards) do
      local i = hand_pos[c]
      if i and not inx[i] then rest[#rest + 1] = i end
    end
    return rest
  end
  local function others_suffix(ix)
    local rest = others_of(ix)
    if #rest == 0 then return "" end
    local cap = discard_cap()
    if #rest <= cap then return "/other" .. idx_suffix(rest) end
    local order = {}
    for i, p in ipairs(rest) do order[i] = p end
    table.sort(order, function(a, b)
      local ra = rank_of(G.hand.cards[a]) or 0
      local rb = rank_of(G.hand.cards[b]) or 0
      if ra ~= rb then return ra < rb end
      return a < b
    end)
    local take = {}
    for i = 1, cap do take[i] = order[i] end
    table.sort(take)
    return "/other" .. idx_suffix(take) .. "(discard at most " .. cap .. ")"
  end
  local function complete_pct(n, m, k)
    if k < 1 or n < 1 or m < 1 then return 0 end
    if k >= m then return 100 end
    if n >= m then return 100 end
    local miss = 1.0
    for i = 0, k - 1 do
      miss = miss * (m - n - i) / (m - i)
      if miss <= 0 then return 100 end
    end
    return math.floor((1 - miss) * 100 + 0.5)
  end
  local function draw_note(match, k)
    local pool, flipped = CardUtil.unplayed_pool()
    if not pool or #pool == 0 or not match then return "" end
    if flipped > 0 then return "" end
    if (tonumber(k) or 0) < 1 then return "" end
    local n = 0
    for _, c in ipairs(pool) do if match(c) then n = n + 1 end end
    if n == 0 then return nil end
    return string.format("(draw %d/%d=%d%%)", n, #pool, complete_pct(n, #pool, k or 1))
  end
  local pile_memo
  local function deck_rank_pile()
    if pile_memo ~= nil then return pile_memo end
    local dk, flipped = CardUtil.unplayed_pool()
    if type(dk) ~= "table" or #dk == 0 or flipped > 0 then pile_memo = false; return false end
    local pile = {}
    for _, c in ipairs(dk) do
      if not has_no_rank(c) then
        local r = rank_of(c)
        if r ~= nil then pile[r] = (pile[r] or 0) + 1 end
      end
    end
    pile_memo = pile
    return pile
  end
  local function best_kicker(exclude)
    local pile = deck_rank_pile()
    if not pile then return nil end
    local best, best_n = nil, 0
    for _, c in ipairs(cards) do
      if not has_no_rank(c) then
        local r = rank_of(c)
        if r ~= nil and r ~= exclude and (rank_counts[r] or 0) == 1 and (pile[r] or 0) > best_n then
          best, best_n = r, pile[r]
        end
      end
    end
    return best
  end

  local function near_entry(name, ix, match)
    if type(ix) ~= "table" or #ix == 0 then return nil end
    local deb = deb_in_ix(ix)
    if deb == #ix then return nil end
    local draws = draws_after_discard(math.min(#others_of(ix), discard_cap()))
    local dn = draw_note(match, draws)
    if dn == nil then return nil end
    local note = (deb > 0) and ("(" .. deb .. " debuffed~0)") or ""
    return name .. " keep" .. idx_suffix(ix) .. others_suffix(ix)
      .. dn .. note .. floor_note(name)
  end

  local ready_set = {}
  local ready_dud = {}
  local ready_deb = {}
  local ready_ix = {}
  local ready_best = {}
  local function mark_ready(name, best)
    if type(best) ~= "table" or #best == 0 then return end
    if VERIFY_REBUILT[name] and not contained_types_cached(best)[name] then return end
    ready_set[name] = true
    ready_best[name] = best
    ready_ix[name] = positions_of(best)
    if debuffed > 0 then
      ready_deb[name] = DebuffFacts.count(best)
      if DebuffFacts.all_debuffed(best) then ready_dud[name] = true end
    end
  end
  if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok, ph = pcall(function()
      local _, _, p = G.FUNCS.get_poker_hand_info(cards)
      return p
    end)
    if ok and type(ph) == "table" then
      for name, set in pairs(ph) do
        if name ~= "top" and set and next(set) then
          mark_ready(name, best_scoring_cards(name, set))
        end
      end
    end
  end

  do
    local function take_cards(take)
      local by = copies_by_rank()
      local out = {}
      for r, n in pairs(take) do
        local list = by[r] or {}
        for k = 1, math.min(n, #list) do out[#out + 1] = list[k] end
      end
      return out
    end
    local function compose(name)
      if name == "Two Pair" then
        local a = top_rank(2)
        local b = a and top_rank(2, a)
        if a and b then return { [a] = 2, [b] = 2 } end
      elseif name == "Full House" then
        local a = top_rank(3)
        local b = a and top_rank(2, a)
        if a and b then return { [a] = 3, [b] = 2 } end
      end
      return nil
    end
    for _, name in ipairs({ "Two Pair", "Full House" }) do
      local take = compose(name)
      local made = take and take_cards(take)
      if made and #made > 0 and contained_types(made)[name] then
        mark_ready(name, made)
      end
    end
  end

  do
    local strong = false
    for n in pairs(ready_set) do
      if STRONG_READY[n] then strong = true break end
    end
    _strong_cache.sig = strong_sig()
    _strong_cache.val = strong
  end

  local near_set = {}
  local discards = GameFacts.discards_left()
  if discards > 0 then
    local function near(name) if not ready_set[name] then near_set[name] = true end end
    if flush_thr > 1 and max_suit == flush_thr - 1 then near("Flush") end
    if straight_thr > 1 and max_run < straight_thr and (max_run == straight_thr - 1
        or (not sm("shortcut") and near_straight_window(present_ranks, straight_thr))) then near("Straight") end
    if has4 then near("Five of a Kind") end
    if has3 then near("Four of a Kind") end
    if trips_count >= 1 or pair_count >= 2 then near("Full House") end
    if pair_count >= 1 then near("Three of a Kind") end
    if pair_count == 1 then near("Two Pair") end
  end

  local function ranked(set, cap, cache)
    local list = {}
    for name in pairs(set) do
      if (HAND_ORDER[name] or 0) >= 2 then list[#list + 1] = name end
    end
    table.sort(list, function(a, b) return (HAND_ORDER[a] or 0) > (HAND_ORDER[b] or 0) end)
    while #list > cap do table.remove(list) end
    if #list <= 1 or not cache then return list end
    local canon = {}
    for i, n in ipairs(list) do canon[i] = n end
    table.sort(canon)
    local key = tostring(strong_sig()) .. "#" .. table.concat(canon, ",")
    if cache.key ~= key then
      cache.key, cache.order = key, shuffle_impl(list)
    end
    local out = {}
    for i, n in ipairs(cache.order) do out[i] = n end
    return out
  end

  local high_pair = high_pair_rank > 0 and (HAND_RANK_LABEL[high_pair_rank] or tostring(high_pair_rank)) or "-"
  local out = fd_lead .. string.format("Structure: pairs>=2:%d trips>=3:%d quads>=4:%d top:%s suit_max:%d run_max:%d.",
    pair_count, trips_count, sh.quads, high_pair, max_suit, max_run)

  if debuffed > 0 then
    out = out .. string.format(" %d card(s) DEBUFFED (they score 0).", debuffed)
  end

  local ready = ranked(ready_set, 4, _ready_order_cache)
  local ready_zeroed = {}
  if has_restr then
    local min_sz = 0
    do
      local d = G.GAME and G.GAME.blind and not G.GAME.blind.disabled and G.GAME.blind.debuff
      if type(d) == "table" then min_sz = tonumber(d.h_size_ge) or 0 end
    end
    local function padded(best)
      if min_sz <= #best then return best end
      local set, present = {}, {}
      for _, c in ipairs(best) do set[#set + 1] = c; present[c] = true end
      for _, c in ipairs(cards) do
        if #set >= min_sz then break end
        if not present[c] then set[#set + 1] = c; present[c] = true end
      end
      return set
    end
    for _, n in ipairs(ready) do
      local zeroed, certain = DebuffFacts.boss_would_debuff(padded(ready_best[n] or {}), n)
      if zeroed then
        ready_zeroed[n] = require("facts.boss.legality").zeroed_note(n)
      elseif certain == false then
        ready_zeroed[n] = "boss rule could not be checked -- this hand may score 0"
      end
    end
  end
  if #ready > 0 then
    local jmap = type_conditional_jokers()
    local function applied_jokers(name)
      if not jmap then return nil end
      local ct = with_type(ready_best[name] or {}, name)
      local seen, list = {}, {}
      for htype, idxs in pairs(jmap) do
        if ct[htype] then
          for _, ji in ipairs(idxs) do
            if not seen[ji] then seen[ji] = true; list[#list + 1] = ji end
          end
        end
      end
      table.sort(list)
      return list
    end
    local jsum = Scoring.joker_summary()
    local by_type = (jsum and jsum.ledger and jsum.ledger.by_type) or {}
    local by_type_names = {}
    for t in pairs(by_type) do by_type_names[#by_type_names + 1] = t end
    table.sort(by_type_names)
    local ready_cond = {}
    do
      if next(by_type) then
        for _, n in ipairs(ready) do
          local ct = with_type(ready_best[n] or {}, n)
          local agg = { chips = 0, mult = 0, xmult = 1, xchips = 1 }
          for _, t in ipairs(by_type_names) do
            local b = by_type[t]
            if ct[t] then
              if t == n then
                agg.chips = agg.chips + (b.chips or 0)
                agg.mult = agg.mult + (b.mult or 0)
                agg.xmult = agg.xmult * (b.xmult or 1)
                agg.xchips = agg.xchips * (b.xchips or 1)
              else
                agg.chips = agg.chips + (b.chips or 0) - (b.acc_chips or 0)
                agg.mult = agg.mult + (b.mult or 0) - (b.acc_mult or 0)
                agg.xmult = agg.xmult * ((b.xmult or 1) / (b.acc_xmult or 1))
                agg.xchips = agg.xchips * ((b.xchips or 1) / (b.acc_xchips or 1))
              end
            end
          end
          if agg.chips ~= 0 or agg.mult ~= 0 or agg.xmult ~= 1 or agg.xchips ~= 1 then
            ready_cond[n] = agg
          end
        end
      end
    end
    local joker_index = {}
    for ji, jc in ipairs((G.jokers and G.jokers.cards) or {}) do
      local nm = (jc and PublicCard.is_public(jc)) and jc.ability and jc.ability.name or nil
      if nm and not joker_index[nm] then joker_index[nm] = ji end
    end
    local function selection_totals(name)
      local best = ready_best[name]
      if type(best) ~= "table" or #best == 0 then return nil, nil end
      local ok, js = pcall(Scoring.joker_summary, best)
      local led = ok and js and js.ledger or nil
      if not led or not led.gated then return nil, nil end
      local agg, any = { chips = 0, mult = 0, xmult = 1, xchips = 1 }, false
      for _, kind in ipairs({ "chips", "mult", "xmult", "xchips" }) do
        local q = led.gated[kind]
        if type(q) == "table" and q.k == "known" and not Scoring.Q.is_identity(kind, q) then
          any = true
          agg[kind] = q.n
        end
      end
      if not any then return nil, nil end
      local srcs = {}
      for _, s in ipairs(led.sources or {}) do
        local ji = joker_index[s.name]
        if ji then srcs[ji] = true end
      end
      return agg, srcs
    end
    local tooth_on = DebuffFacts.tooth_active()
    local ox_hand = DebuffFacts.ox_active() and DebuffFacts.most_played_hand() or nil
    for i, n in ipairs(ready) do
      local deb_note = ""
      if ready_dud[n] then
        deb_note = "(all debuffed~0)"
      elseif (ready_deb[n] or 0) > 0 then
        deb_note = "(" .. tostring(ready_deb[n]) .. " debuffed~0)"
      end
      local cost_note = ""
      if tooth_on and ready_ix[n] and #ready_ix[n] > 0 then
        cost_note = " (-$" .. #ready_ix[n] .. ")"
      end
      local ox_note = (ox_hand and n == ox_hand) and " (OX: zeroes $ if played)" or ""
      local zeroed = ready_zeroed[n] and (" -- " .. ready_zeroed[n]) or ""
      local jlist = (jmap and applied_jokers(n)) or {}
      local jagg = ready_cond[n]
      local sel_agg, sel_src = selection_totals(n)
      if sel_agg then
        local merged = { chips = 0, mult = 0, xmult = 1, xchips = 1 }
        local function fold(part)
          if not part then return end
          merged.chips = merged.chips + (part.chips or 0)
          merged.mult = merged.mult + (part.mult or 0)
          merged.xmult = merged.xmult * (part.xmult or 1)
          merged.xchips = merged.xchips * (part.xchips or 1)
        end
        fold(jagg)
        fold(sel_agg)
        jagg = merged
        local seen = {}
        for _, ji in ipairs(jlist) do seen[ji] = true end
        for ji in pairs(sel_src) do
          if not seen[ji] then seen[ji] = true; jlist[#jlist + 1] = ji end
        end
        table.sort(jlist)
      end
      local jnote = (#jlist > 0) and joker_note(jlist, jagg) or ""
      if jnote == "" and jagg then jnote = cond_note(jagg) end
      ready[i] = n .. idx_suffix(ready_ix[n]) .. level_note(n)
        .. jnote .. deb_note .. floor_note(n)
        .. cost_note .. ox_note
        .. guaranteed_note(jsum) .. zeroed
    end
    out = out .. " Ready: " .. table.concat(ready, "; ") .. "."
    if G.jokers and G.jokers.cards then
      for i, jc in ipairs(G.jokers.cards) do
        local ck = (jc and not jc.debuff) and PublicCard.multiset_key(jc, "jokers", i) or nil
        if ck == "center:j_splash" then
          out = out .. string.format(" All played cards score (Splash) -- you may still play at most %d.",
            CardUtil.highlight_limit())
          break
        end
      end
    end
  end

  local near_label = {}
  if near_set["Flush"] then
    local counts = suit_counts
    for _, s in ipairs(suit_list()) do
      local key = (type(s) == "table" and (s.key or s.name)) or s
      if counts[key] == flush_thr - 1 then
        local ix, all_deb = {}, true
        for _, c in ipairs(cards) do
          if not has_no_suit(c) and in_suit(c, key) then
            ix[#ix + 1] = hand_pos[c]
            if not c.debuff then all_deb = false end
          end
        end
        local outs = draw_note(function(c) return not has_no_suit(c) and in_suit(c, key) end,
          draws_after_discard(math.min(#others_of(ix), discard_cap())))
        if not all_deb and outs ~= nil then
          local deb = deb_in_ix(ix)
          local dn = (deb > 0) and ("(" .. deb .. " debuffed~0)") or ""
          local label = smeared_active() and (SUIT_COLOR[key] or tostring(key)) or tostring(key)
          near_label["Flush"] = string.format("Flush: %d %s keep%s%s%s%s%s",
            counts[key], label, idx_suffix(ix), others_suffix(ix), outs,
            dn, floor_note("Flush"))
          break
        end
      end
    end
    if not near_label["Flush"] then near_set["Flush"] = nil end
  end
  if near_set["Straight"] then
    local present = present_ranks
    local rr
    if not sm("shortcut") then rr = best_near_straight_ranks(present, straight_thr) end
    rr = rr or sh.run_ranks or {}
    local missing = straight_outs(rr, straight_thr)
    local st_match = function(c)
      if has_no_rank(c) then return false end
      local r = rank_of(c)
      if not r then return false end
      return (missing[r] or (r == 14 and missing[1])) and true or false
    end
    local best_at = {}
    for _, c in ipairs(cards) do
      if not has_no_rank(c) then
        local rid = rank_of(c)
        if rid and (rr[rid] or (rid == 14 and rr[1])) then
          local cur = best_at[rid]
          if not cur or (G.hand.cards[cur].debuff and not c.debuff) then best_at[rid] = hand_pos[c] end
        end
      end
    end
    local ix = {}
    for _, i in pairs(best_at) do ix[#ix + 1] = i end
    table.sort(ix)
    if #ix > 0 then
      local entry = near_entry("Straight", ix, st_match)
      if entry then
        local open = false
        if max_run == straight_thr - 1 then
          local lo, hi = 99, 0
          for r in pairs(sh.run_ranks) do if r < lo then lo = r end; if r > hi then hi = r end end
          open = (lo - 1 >= 1) and (hi + 1 <= 14)
        end
        near_label["Straight"] = entry .. (open and " (open draw)" or " (inside draw)")
      else
        near_set["Straight"] = nil
      end
    end
  end

  do
    local function rank_positions(take)
      local pos = hand_pos
      local by = copies_by_rank()
      local ix = {}
      for r, n in pairs(take) do
        local list = by[r] or {}
        for k = 1, math.min(n, #list) do ix[#ix + 1] = pos[list[k]] end
      end
      table.sort(ix)
      return ix
    end
    local function forming(name)
      if name == "Five of a Kind" then
        local r = top_rank(4); return r and { [r] = 4 }
      elseif name == "Four of a Kind" then
        local r = top_rank(3); return r and { [r] = 3 }
      elseif name == "Full House" then
        local t = top_rank(3)
        if t then
          local take = { [t] = 3 }
          local p = top_rank(2, t)
          if p then take[p] = 2 end
          return take
        end
        local p1 = top_rank(2)
        local p2 = p1 and top_rank(2, p1)
        if p1 and p2 then return { [p1] = 2, [p2] = 2 } end
      elseif name == "Three of a Kind" or name == "Two Pair" then
        local r = top_rank(2); return r and { [r] = 2 }
      end
      return nil
    end
    for name in pairs(near_set) do
      if not near_label[name] then
        local take = forming(name)
        if take then
          local match
          if name == "Five of a Kind" or name == "Four of a Kind" or name == "Three of a Kind" then
            local rneed
            for r in pairs(take) do rneed = r end
            match = function(c)
              if has_no_rank(c) then return false end
              return rank_of(c) == rneed
            end
          elseif name == "Two Pair" then
            local pr
            for r in pairs(take) do pr = r end
            local kick = best_kicker(pr)
            if kick == nil then
              match = nil
            else
              take[kick] = 1
              match = function(c)
                if has_no_rank(c) then return false end
                return rank_of(c) == kick
              end
            end
          elseif name == "Full House" then
            local trip
            for r, nn in pairs(take) do if nn >= 3 then trip = r end end
            if trip then
              local kick = best_kicker(trip)
              if kick == nil then
                match = nil
              else
                take[kick] = 1
                match = function(c)
                  if has_no_rank(c) then return false end
                  return rank_of(c) == kick
                end
              end
            else
              match = function(c)
                if has_no_rank(c) then return false end
                local r = rank_of(c)
                return r ~= nil and take[r] ~= nil
              end
            end
          end
          local entry = near_entry(name, rank_positions(take), match)
          if entry then near_label[name] = entry else near_set[name] = nil end
        end
      end
    end
  end

  local nr = ranked(near_set, 4)
  local near_zeroed = {}
  if has_restr then
    for _, n in ipairs(nr) do
      if DebuffFacts.boss_blocks_handname(n) then
        near_zeroed[n] = require("facts.boss.legality").zeroed_note(n)
      end
    end
  end
  if #nr > 0 then
    for i, n in ipairs(nr) do
      nr[i] = "near " .. (near_label[n] or n) .. (near_zeroed[n] and (" -- " .. near_zeroed[n]) or "")
    end
    out = out .. " Close: " .. table.concat(nr, "; ") .. "."
  end

  if facedown then
    out = out .. " (This boss draws some cards face-down - your hand may change.)"
  end

  return out .. " "
end

local LEVEL_ORDER = {}
for k, v in pairs(HAND_ORDER) do LEVEL_ORDER[k] = v end
LEVEL_ORDER["mix"] = 13
LEVEL_ORDER["mixhouse"] = 14
LEVEL_ORDER["straightmix"] = 15
LEVEL_ORDER["mixed5"] = 16
local function hand_visible(hd)
  return not not (type(hd) == "table" and hd.visible)
end
local function sort_level_rows(rows)
  table.sort(rows, function(a, b)
    local ao, bo = LEVEL_ORDER[a.name] or 999, LEVEL_ORDER[b.name] or 999
    if ao ~= bo then return ao < bo end
    return tostring(a.name) < tostring(b.name)
  end)
end
local function levels()
  local rows = {}
  if not (G and G.GAME and G.GAME.hands) then return rows end
  local flint = DebuffFacts.flint_active()
  for name, hd in pairs(G.GAME.hands) do
    if hand_visible(hd) then
      local lv, ch, mu = hd.level or 1, hd.chips or 0, hd.mult or 0
      lv, ch, mu = arm_drop(lv, ch, mu, hd)
      if flint then ch, mu = DebuffFacts.flint_halve(ch, mu) end
      rows[#rows + 1] = { name = name, level = lv, chips = ch, mult = mu, played = hd.played or 0 }
    end
  end
  sort_level_rows(rows)
  return rows
end

-- Level-1 base values, which are fixed game data: `chips = s_chips + l_chips*(level-1)`
-- (common_events.lua:483), so the base survives every Planet upgrade. Flint's halving is a boss
-- debuff on the CURRENT values and must not touch these -- this row is what retained context
-- states as permanently true about a hand type.
local function base_levels()
  local rows = {}
  if not (G and G.GAME and G.GAME.hands) then return rows end
  for name, hd in pairs(G.GAME.hands) do
    if hand_visible(hd) then
      local level = hd.level or 1
      local chips = hd.s_chips or (level == 1 and hd.chips) or nil
      local mult = hd.s_mult or (level == 1 and hd.mult) or nil
      if chips and mult then
        rows[#rows + 1] = { name = name, chips = math.max(chips, 0), mult = math.max(mult, 0) }
      end
    end
  end
  sort_level_rows(rows)
  return rows
end

local function leveled_types()
  local rows = levels()
  local out = {}
  for _, r in ipairs(rows) do
    if (r.level or 1) >= 2 then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

local function leveled_spread_note()
  local rows = leveled_types()
  if #rows < 2 then return "" end
  local parts = {}
  for _, r in ipairs(rows) do
    parts[#parts + 1] = string.format("%s (lvl %d, played %dx)", r.name, r.level, r.played or 0)
  end
  return string.format("Leveled hand types this run (%d): %s. ", #rows, table.concat(parts, ", "))
end

local function level_notes()
  local notes = {}
  if DebuffFacts.flint_active() then notes[#notes + 1] = "Flint active: c,m already halved" end
  if arm_active() then
    notes[#notes + 1] = "The Arm active: rows already include the one-level drop it applies to the hand you play"
  end
  if plasma_balances() then
    notes[#notes + 1] = "Plasma deck: final score balances total chips and mult"
  end
  return notes
end

function M.any_face_down()
  return (G and G.hand and G.hand.cards and n_face_down(G.hand.cards) > 0) or false
end

function M.has_strong_ready()
  if not (G and G.hand and G.hand.cards and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function") then
    return false
  end
  if n_face_down(G.hand.cards) > 0 then return false end
  local sig = strong_sig()
  if sig and sig == _strong_cache.sig then return _strong_cache.val end
  local ok, ph = pcall(function() local _, _, p = G.FUNCS.get_poker_hand_info(G.hand.cards); return p end)
  if not (ok and type(ph) == "table") then return false end
  for name, set in pairs(ph) do
    if STRONG_READY[name] and set and next(set) then
      local best = best_scoring_cards(name, set)
      if type(best) == "table" and #best > 0
        and (not VERIFY_REBUILT[name] or contained_types(best)[name]) then return true end
    end
  end
  return false
end

M.summary = hand_structure_summary
M.level_notes = level_notes
M.leveled_spread_note = leveled_spread_note
M.shape = shape
M.contained_types = contained_types
M.HAND_ORDER = HAND_ORDER
M.levels = levels
M.base_levels = base_levels
M.plasma_balances = plasma_balances

if _G.NEURO_TEST then
  M.hand_visible = hand_visible
end

return M
