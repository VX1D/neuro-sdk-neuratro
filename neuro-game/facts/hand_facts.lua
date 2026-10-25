local GameFacts = require("facts.game_facts")
local DebuffFacts = require("facts.debuff_facts")
local BossModel = require("facts.boss.model")
local CardUtil = require("facts.card_util")
local DeckNames = require("facts.deck_names")
local Scoring = require("util.scoring")
local PublicCard = require("facts.public_card_identity")
local Utils = require("util.utils")
local M = {}

local HAND_RANK_LABEL = { [14] = "A", [13] = "K", [12] = "Q", [11] = "J" }

local HAND_ORDER = {
  ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4,
  ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8,
  ["Straight Flush"] = 9, ["Five of a Kind"] = 10, ["Flush House"] = 11, ["Flush Five"] = 12,
}

local has_no_suit = CardUtil.has_no_suit
local rank_of = CardUtil.rank_id
local function suit_list() return SMODS.Suit.obj_buffer end

local SUIT_COLOR = { Hearts = "red", Diamonds = "red", Spades = "black", Clubs = "black" }
local function smeared_active() return CardUtil.owns_live_joker("j_smeared") end

local function public_cards(cards)
  local out = {}
  for _, c in ipairs(cards) do
    if type(c) == "table" and PublicCard.is_public(c) then out[#out + 1] = c end
  end
  return out
end

local function public_pool(pool, concealed)
  if type(pool) ~= "table" or (tonumber(concealed) or 0) > 0 then return false end
  for _, c in ipairs(pool) do
    if not (PublicCard.is_public(c) or CardUtil.is_aggregate_public(c)) then return false end
  end
  return true
end

local function in_suit(card, suit)
  local ok, v = pcall(card.is_suit, card, suit, true, true)
  return ok and v and true or false
end

local function suited(c, key) return not has_no_suit(c) and in_suit(c, key) end
local function suit_key_of(s) return (type(s) == "table" and (s.key or s.name)) or s end

local function count_suits(cards)
  local res, max_suit = {}, 0
  for _, s in ipairs(suit_list()) do
    local key = suit_key_of(s)
    local n = 0
    for _, c in ipairs(cards) do if suited(c, key) then n = n + 1 end end
    res[key] = n
    if n > max_suit then max_suit = n end
  end
  return res, max_suit
end

local function count_ranks(cards)
  local counts, present = {}, {}
  for _, c in ipairs(cards) do
    local rid = rank_of(c)
    if rid and rid >= 2 then
      counts[rid] = (counts[rid] or 0) + 1
      present[rid] = true
      if rid == 14 then present[1] = true end
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
  local shortcut = SMODS.shortcut() and true or false
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

local function rank_tally(cards)
  local t = {}
  for _, c in ipairs(cards) do
    local r = rank_of(c)
    if r then t[r] = (t[r] or 0) + 1 end
  end
  return t
end

local function rank_is(r) return function(c) return rank_of(c) == r end end

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

local function best_straight_keep(present, thr)
  if not thr or thr < 2 then return nil end
  local pool, flipped = CardUtil.unplayed_pool()
  local live = public_pool(pool, flipped) and rank_tally(pool) or nil
  local ranks = {}
  for r = 2, 14 do if present[r] then ranks[#ranks + 1] = r end end
  local best, best_score
  local keep = {}
  local function consider()
    local probe = {}
    for _, r in ipairs(keep) do probe[r] = true; if r == 14 then probe[1] = true end end
    local outs, n_ranks = straight_outs(probe, thr)
    if n_ranks == 0 then return end
    local n_live = 0
    for r in pairs(outs) do n_live = n_live + ((live and live[r]) or 0) end
    local score = { live and n_live or n_ranks, n_ranks }
    local better = not best_score
    if not better then
      for k = 1, 2 do
        if score[k] ~= best_score[k] then better = score[k] > best_score[k]; break end
      end
    end
    if better then
      probe[1] = nil
      best, best_score = { set = probe, outs = outs, out_ranks = n_ranks }, score
    end
  end
  local function choose(from, left)
    if left == 0 then consider(); return end
    for i = from, #ranks - left + 1 do
      keep[#keep + 1] = ranks[i]
      choose(i + 1, left - 1)
      keep[#keep] = nil
    end
  end
  choose(1, thr - 1)
  return best
end

local function shape(cards)
  local suit_counts, max_suit = count_suits(cards)
  local rank_counts, present = count_ranks(cards)
  local max_run, run_ranks = max_run_of(present)
  local flush_thr = SMODS.four_fingers("flush")
  local straight_thr = SMODS.four_fingers("straight")
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

local function play_cap() return CardUtil.highlight_limit() end

local function discard_cap()
  local ok, n = pcall(function()
    return math.max(1, require("core.plan_limits").discard_select_max())
  end)
  return (ok and n) or CardUtil.highlight_limit()
end

local function arm_active() return BossModel.active_key(true) == "bl_arm" end

local function arm_drop(level, chips, mult, hd)
  if not arm_active() or (level or 1) <= 1 then return level, chips, mult end
  local lc, lm = tonumber(hd and hd.l_chips), tonumber(hd and hd.l_mult)
  if not (lc and lm) then return level, chips, mult end
  return level - 1, math.max(chips - lc, 0), math.max(mult - lm, 1)
end

-- `score_level`, chips and mult already reflect The Arm’s level drop and Flint’s halving.
local function hand_values(name, hd)
  if type(hd) ~= "table" then return nil end
  local level = tonumber(hd.level) or 1
  local lv, ch, mu = arm_drop(level, tonumber(hd.chips) or 0, tonumber(hd.mult) or 0, hd)
  if DebuffFacts.flint_active() then ch, mu = DebuffFacts.flint_halve(ch, mu) end
  return { name = name, level = level, score_level = lv, chips = ch, mult = mu,
    played = tonumber(hd.played) or 0 }
end
local function current_values(name) return hand_values(name, G and G.GAME and G.GAME.hands and G.GAME.hands[name]) end

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
    if BossModel.active_key(true) == "bl_serpent" then
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
    if ed.holo then v = v + 25 end
    if ed.polychrome then v = v + 30 end
  end
  if v < 1 then v = 1 end
  return v
end

local function set_value(cards)
  local v = 0
  for _, c in ipairs(cards) do v = v + play_value(c) end
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

local function sort_in_play_order(list)
  local order = {}
  for i, c in ipairs(list) do order[c] = i end
  sort_by_play_value(list, order)
end

local function rank_copies(cards, key)
  local by, ord = {}, {}
  for i, c in ipairs(cards) do
    ord[c] = i
    local r = rank_of(c)
    if r and r >= 2 then
      by[r] = by[r] or {}
      by[r][#by[r] + 1] = c
    end
  end
  local priority = key and function(card) return suited(card, key) and 1 or 0 end
  for _, list in pairs(by) do
    sort_by_play_value(list, ord, priority)
  end
  return by, ord
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
  local shortcut = SMODS.shortcut() and true or false
  local best, best_v = nil, -1
  for _, s in ipairs(suit_list()) do
    local key = suit_key_of(s)
    local by, ord = rank_copies(group, key)
    local in_key = {}
    for _, c in ipairs(group) do if suited(c, key) then in_key[#in_key + 1] = c end end
    sort_by_play_value(in_key, ord)
    by[1] = by[14]
    local function consider_run(seq)
      local set, used, n_suited = {}, {}, 0
      for _, rk in ipairs(seq) do
        local c = by[rk][1]
        if used[c] then return end
        set[#set + 1] = c; used[c] = true
        if suited(c, key) then n_suited = n_suited + 1 end
      end
      for _, c in ipairs(in_key) do
        if n_suited >= flush_thr or #set >= cap then break end
        if not used[c] then
          set[#set + 1] = c; used[c] = true; n_suited = n_suited + 1
        end
      end
      if n_suited < flush_thr then return end
      local pool = {}
      for _, c in ipairs(in_key) do if not used[c] then pool[#pool + 1] = c end end
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
      local v = set_value(set)
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
    local by = rank_copies(group, key)
    local function consider(cards)
      if #cards == 0 or #cards > cap then return end
      local n = 0
      for _, c in ipairs(cards) do if suited(c, key) then n = n + 1 end end
      if n < flush_thr then return end
      local sc = set_value(cards)
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

-- Straight Flush and Flush House groups use only the first flush suit found, which may not complete the hand.
local function best_scoring_cards(name, set, hand)
  local cap = play_cap()
  local out = {}
  for _, c in ipairs(best_group(set)) do out[#out + 1] = c end
  local whole = {}
  for _, c in ipairs(hand or out) do whole[#whole + 1] = c end
  if name == "Flush" then
    sort_in_play_order(out)
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
    out = best_straight_flush_set(whole,
      SMODS.four_fingers("straight"),
      SMODS.four_fingers("flush"), cap) or {}
  elseif name == "Flush House" or name == "Flush Five" then
    out = best_flush_set(name, whole, SMODS.four_fingers("flush"), cap) or {}
  elseif NATURAL_SIZE[name] then
    local n = NATURAL_SIZE[name]
    if #out > n then
      sort_in_play_order(out)
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

-- Check each type against the whole selection; Flush plus Straight also flags Straight Flush.
local function forced_card(cards)
  for _, c in ipairs(cards or {}) do
    if type(c) == "table" and type(c.ability) == "table" and c.ability.forced_selection then return c end
  end
  return nil
end

local function top_of(types)
  local top, order = nil, 0
  for n in pairs(types) do
    if (HAND_ORDER[n] or 0) > order then top, order = n, HAND_ORDER[n] end
  end
  return top
end

local function played_type(set)
  if G and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok, text = pcall(G.FUNCS.get_poker_hand_info, set)
    if ok and type(text) == "string" and HAND_ORDER[text] then return text end
  end
  return top_of(contained_types_cached(set))
end

local function each_subset(cards, size, fn)
  local cur = {}
  local function rec(from)
    if #cur == size then return fn(cur) end
    for i = from, #cards - (size - #cur) + 1 do
      cur[#cur + 1] = cards[i]
      local stop = rec(i + 1)
      cur[#cur] = nil
      if stop then return true end
    end
  end
  if size >= 1 and size <= #cards then rec(1) end
end

local function copy_list(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

-- The engine scores only the selection’s top type, so a Ready row must top its own cards.
local function as_top(name, best, cards)
  if top_of(contained_types_cached(best)) == name then return best end
  for size = #best, 1, -1 do
    local pick, pick_v
    each_subset(cards, size, function(s)
      if top_of(contained_types(s)) == name then
        local v = set_value(s)
        if not pick or v > pick_v then pick, pick_v = copy_list(s), v end
      end
    end)
    if pick then return pick end
  end
  return nil
end

local function with_forced(name, best, forced)
  for _, c in ipairs(best) do if c == forced then return best end end
  local cands = {}
  if #best < play_cap() then
    local s = { forced }
    for _, c in ipairs(best) do s[#s + 1] = c end
    cands[1] = s
  end
  for i = 1, #best do
    local s = { forced }
    for j, c in ipairs(best) do if j ~= i then s[#s + 1] = c end end
    cands[#cands + 1] = s
  end
  local pick, pick_v
  for _, s in ipairs(cands) do
    if played_type(s) == name then
      local v = set_value(s)
      if not pick or v > pick_v then pick, pick_v = s, v end
    end
  end
  return pick
end

local function with_always_scoring(best_of, cards)
  local extra = {}
  for _, c in ipairs(cards) do
    if type(c) == "table" and PublicCard.is_public(c) and not c.debuff and Scoring.always_scores(c)
        and c.seal ~= "Blue" then
      extra[#extra + 1] = c
    end
  end
  if #extra == 0 then return best_of end
  for name, best in pairs(best_of) do
    local set, member = {}, {}
    for i, c in ipairs(best) do set[i] = c; member[c] = true end
    for _, c in ipairs(extra) do
      if #set >= play_cap() then break end
      if not member[c] then
        set[#set + 1] = c
        if played_type(set) ~= name then set[#set] = nil end
      end
    end
    best_of[name] = set
  end
  return best_of
end

local function take_copies(by, take)
  local out = {}
  for r, n in pairs(take) do
    local list = by[r] or {}
    for k = 1, math.min(n, #list) do out[#out + 1] = list[k] end
  end
  return out
end

local function ready_hands(cards)
  local best_of = {}
  if type(cards) ~= "table" or #cards == 0 then return best_of end
  local function mark(name, best)
    if type(best) ~= "table" or #best == 0 then return end
    best_of[name] = as_top(name, best, cards)
  end
  if G and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok, ph = pcall(function()
      local _, _, p = G.FUNCS.get_poker_hand_info(cards)
      return p
    end)
    if ok and type(ph) == "table" then
      for name, set in pairs(ph) do
        if name ~= "top" and set and next(set) then mark(name, best_scoring_cards(name, set, cards)) end
      end
    end
  end
  local _, rank_counts = shape(cards)
  local by = rank_copies(cards)
  for name, want in pairs({ ["Two Pair"] = 2, ["Full House"] = 3 }) do
    local a = rank_top(rank_counts, want)
    local b = a and rank_top(rank_counts, 2, a)
    local made = b and take_copies(by, { [a] = want, [b] = 2 })
    if made and #made > 0 and contained_types(made)[name] then best_of[name] = as_top(name, made, cards) end
  end
  local forced = forced_card(cards)
  if forced then
    for name, best in pairs(best_of) do best_of[name] = with_forced(name, best, forced) end
  end
  return with_always_scoring(best_of, cards)
end

local MAX_PRICED_SELECTIONS = 1600

local function n_choose(n, k)
  if k < 0 or k > n then return 0 end
  local r = 1
  for i = 1, k do r = r * (n - k + i) / i end
  return r
end

local function ready_by_value(cards, value)
  local out = {}
  if type(cards) ~= "table" or #cards == 0 or type(value) ~= "function" then return out end
  local function offer(name, set)
    local v = name and value(set, name)
    local cur = out[name]
    if v and (not cur or v > cur.value) then out[name] = { set = set, value = v } end
  end
  local cap = math.min(play_cap(), #cards)
  local total = 0
  for k = 1, cap do total = total + n_choose(#cards, k) end
  if total > MAX_PRICED_SELECTIONS then
    for name, best in pairs(ready_hands(cards)) do offer(name, best) end
    return out
  end
  local forced = forced_card(cards)
  for k = 1, cap do
    each_subset(cards, k, function(s)
      local has_forced = not forced
      for _, c in ipairs(s) do
        if c == forced then has_forced = true end
        if c.seal == "Blue" and Scoring.always_scores(c) then return end
      end
      if not has_forced then return end
      local set = copy_list(s)
      offer(top_of(contained_types(set)), set)
    end)
  end
  return out
end

local FIVE_CARD = { Straight = true, Flush = true, ["Full House"] = true, ["Straight Flush"] = true,
  ["Flush House"] = true, ["Flush Five"] = true }

local function scoring_of(set, name)
  for _, c in ipairs(set) do
    if Scoring.always_scores(c) or Scoring.never_scores(c) then return Scoring.scoring_subset(set) end
  end
  local splash = Scoring.splash_state()
  if splash == "yes" then return set, true end
  local size = NATURAL_SIZE[name] or (name == "Two Pair" and 4)
    or (FIVE_CARD[name] and SMODS.four_fingers("flush") == 5 and SMODS.four_fingers("straight") == 5 and 5)
  if splash == "no" and size and #set == size then return set, true end
  return Scoring.scoring_subset(set)
end

local function exact_value(set, name)
  local scoring, exact = scoring_of(set, name)
  if not (scoring and exact) then return nil end
  return M.selection_value(set, name, scoring)
end

local function ready_sets(cards)
  local sets = ready_hands(cards)
  -- Price only selections where every card scores; a non-scoring card adds no known value.
  local splash_off = Scoring.splash_state() == "no"
  local function all_scoring(set, name)
    if splash_off and NATURAL_SIZE[name] and #set > NATURAL_SIZE[name] then
      local extra = false
      for _, c in ipairs(set) do if Scoring.always_scores(c) then extra = true break end end
      if not extra then return nil end
    end
    local scoring, exact = scoring_of(set, name)
    if not (scoring and exact and #scoring == #set) then return nil end
    return M.selection_value(set, name, scoring)
  end
  for name, priced in pairs(ready_by_value(cards, all_scoring)) do
    local cur = sets[name]
    if cur then
      local cur_v = exact_value(cur, name)
      if not cur_v or priced.value > cur_v then sets[name] = priced.set end
    end
  end
  return sets
end

local function top_scoring(sets)
  local top, top_v
  for name, set in pairs(sets) do
    local v = exact_value(set, name)
    if not v then return nil end
    if not top_v or v > top_v then top, top_v = name, v end
  end
  return top
end

local STEP_UNIT = { chips = " chips", xchips = " chips", mult = " mult", xmult = " mult" }

local function step_text(kind, value)
  if kind == "xmult" or kind == "xchips" then return Utils.fmt_xmult(value) .. STEP_UNIT[kind] end
  return Utils.signed(value) .. STEP_UNIT[kind]
end

local function card_label(st)
  for i, c in ipairs(G and G.hand and G.hand.cards or {}) do
    if c == st.card then return (st.held and "on held card " or "on card ") .. i end
  end
  return st.held and "on the held copy" or "on a played card"
end

local function chain_list(steps)
  local parts, last, last_card = {}, nil, nil
  for _, st in ipairs(steps) do
    local text = step_text(st.kind, st.value)
    if st.card and st.card ~= last_card then
      parts[#parts + 1] = (#parts > 0 and "then " or "") .. card_label(st) .. " joker " .. st.slot .. " " .. text
    elseif st.slot == last then
      parts[#parts] = parts[#parts] .. " " .. text
    else
      parts[#parts + 1] = "joker " .. st.slot .. " " .. text
    end
    last, last_card = st.slot, st.card
  end
  return table.concat(parts, ", ")
end

-- Engine order is every joker for each card, followed by the joker pass.
local function chain_parts(steps)
  local card_phase, joker_phase = {}, {}
  for _, st in ipairs(steps or {}) do
    local list = st.cards and card_phase or joker_phase
    list[#list + 1] = st
  end
  local parts = {}
  if #card_phase > 0 then parts[#parts + 1] = "as the cards score: " .. chain_list(card_phase) end
  if #joker_phase > 0 then parts[#parts + 1] = "then jokers left to right: " .. chain_list(joker_phase) end
  return parts
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
  t[#t + 1] = "n" .. tostring(#G.hand.cards)
  for i, c in ipairs(G.hand.cards) do
    if type(c) ~= "table" or not PublicCard.is_public(c) then
      t[#t + 1] = tostring(i) .. "/hidden"
    else
      local base = c and c.base or {}
      local center = c and c.config and c.config.center or {}
      t[#t + 1] = table.concat({
        tostring(i), tostring(base.value or "-"), tostring(base.suit or "-"),
        tostring(center.key or "-"), tostring(CardUtil.enhancement_key(c) or "-"),
        c.debuff and "!" or "", "public",
      }, "/")
    end
  end
  local suits = {}
  for _, suit in ipairs(suit_list()) do suits[#suits + 1] = tostring(suit_key_of(suit)) end
  table.sort(suits)
  t[#t + 1] = "suits:" .. table.concat(suits, ",")
  t[#t + 1] = "smeared:" .. (smeared_active() and "active" or "off")
  t[#t + 1] = tostring(SMODS.four_fingers("flush"))
  t[#t + 1] = tostring(SMODS.four_fingers("straight"))
  t[#t + 1] = SMODS.shortcut() and "sc1" or "sc0"
  return table.concat(t, ";")
end

local function cache_strong(names, sig)
  local strong = false
  for n in pairs(names) do
    if STRONG_READY[n] then strong = true break end
  end
  _strong_cache.sig, _strong_cache.val = sig, strong
  return strong
end

local function n_face_down(cards)
  return require("facts.text").count(cards, function(c) return type(c) ~= "table" or not PublicCard.is_public(c) end)
end

local function draw_facing_sentence(rule)
  local odds = rule.chance_text
  local function how(v)
    if not v then return "face up" end
    if v == "all" then return "face down" end
    if v == "chance" then
      return odds and ("each with a " .. odds .. " chance of arriving face down")
        or "each with a chance of arriving face down"
    end
    if v == "faces" then
      return "face down if they are face cards"
        .. (odds and (", any other card with a " .. odds .. " chance") or "")
    end
    return "possibly face down"
  end
  local p, d = how(rule.play), how(rule.discard)
  if p == d then return "Replacements after a play or a discard are drawn " .. p .. "." end
  return "Replacements after a discard are drawn " .. d .. "; after a play, " .. p .. "."
end

local function discard_draw_read(rule)
  local kind = rule.discard
  local p = tonumber(rule.chance) or 0
  if not kind then return { q = 1 } end
  if (kind == "chance" or kind == "faces") and p < 0.5 then
    return { q = 1 - p, faces = kind == "faces",
      only_faces = kind == "faces" and p == 0 and (rule.play == "faces" or not rule.play) }
  end
  return nil
end

local function is_face_card(c)
  if type(c) ~= "table" or type(c.is_face) ~= "function" then return false end
  local ok, v = pcall(c.is_face, c)
  return ok and v and true or false
end

function M.structure()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return nil
  end

  local n_fd = n_face_down(G.hand.cards)
  local fd_lead = ""
  local odds_lead, no_odds_lead, odds_tail, no_odds_tail = "", "", "", ""
  local cards = G.hand.cards
  local hand_pos = {}
  for i, c in ipairs(G.hand.cards) do hand_pos[c] = i end
  local draw_rule = BossModel.next_draw_facedown()
  local read = discard_draw_read(draw_rule)
  local facing = draw_facing_sentence(draw_rule)
  local miss_note = (read and (read.q < 1 or read.faces)) and "The draw odds below count a face-down draw as a miss. " or ""
  local range_note = (read and read.only_faces)
    and "they are face cards, which the draw odds below never count as outs, so no hidden card hides a counted out. "
    or "each draw figure below is a range whose low end assumes those cards hold every out. "
  if n_fd > 0 then
    local visible = #G.hand.cards - n_fd
    if visible == 0 then
      return { hidden = string.format(
        "Structure: all %d cards face-down (hidden), 0 visible. No hand analysis is possible until they "
        .. "flip; any play or discard here is blind. %s ", n_fd, facing) }
    end
    if not read then
      fd_lead = string.format(
        "%d card(s) face-down (hidden), %d visible. %s "
        .. "Discarding here is a blind gamble: you cannot see if it helps, its replacements may come face-down "
        .. "too, and the one-card-away odds below are withheld while a card is hidden. ",
        n_fd, visible, facing)
    else
      fd_lead = string.format("%d card(s) face-down (hidden), %d visible. %s ", n_fd, visible, facing)
        .. ((draw_rule.discard == "faces" and "Only face cards arrive face down, so a discard toward a non-face "
          .. "out is a real draw you will see, not a blind gamble. ")
          or (draw_rule.discard and "Most replacements arrive face up, so a discard toward a one-card-away hand "
            .. "is a real draw you will mostly see, not a blind gamble. ") or "")
      odds_lead = "The hidden cards still count as unplayed"
        .. (read.only_faces and "; " or ", so ") .. range_note
        .. miss_note
    end
  else
    local _, _, where = CardUtil.unplayed_pool()
    local unseen = where and ((where.discard or 0) + (where.other or 0)) or 0
    if unseen > 0 then
      fd_lead = string.format("%d card(s) you discarded unseen still count as unplayed, so the draw pile's "
        .. "exact makeup is unknown", unseen)
      if read then
        odds_lead, no_odds_lead = "; " .. range_note, ". "
      else
        fd_lead = fd_lead .. " and the one-card-away odds below are withheld. "
      end
    end
    if draw_rule.discard then
      if read then
        odds_tail = facing .. " " .. miss_note
        no_odds_tail = facing .. " "
      else
        fd_lead = fd_lead .. facing .. " The one-card-away odds below are withheld. "
      end
    end
  end
  if n_fd > 0 then cards = public_cards(G.hand.cards) end

  local debuffed = DebuffFacts.count(cards)
  local has_restr = DebuffFacts.has_hand_restriction()

  local facedown = (draw_rule.play or draw_rule.discard) and true or false

  local sh, rank_counts, present_ranks, suit_counts = shape(cards)
  -- The +LOCK card leaves on every discard, so one-card-away keeps exclude it.
  local forced = forced_card(cards)
  local kcards, ksh, k_rank_counts, k_present, k_suit_counts = cards, sh, rank_counts, present_ranks, suit_counts
  if forced then
    kcards = {}
    for _, c in ipairs(cards) do if c ~= forced then kcards[#kcards + 1] = c end end
    ksh, k_rank_counts, k_present, k_suit_counts = shape(kcards)
  end
  local function top_rank(min_count, exclude) return rank_top(k_rank_counts, min_count, exclude) end
  local pair_count, trips_count = sh.pairs, sh.trips
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
  local function floor_of(name)
    if min_play > (HAND_PLAY_SIZE[name] or min_play) then return min_play end
    return nil
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
    for i in ipairs(G.hand.cards) do
      if not inx[i] then rest[#rest + 1] = i end
    end
    return rest
  end
  local function draws_for(ix) return draws_after_discard(math.min(#others_of(ix), discard_cap())) end
  local function keep_entry(name, ix, draw, deb)
    local rest = others_of(ix)
    local cap = discard_cap()
    return { name = name, ix = ix, others = #rest > 0 and rest or nil, cap = #rest > cap and cap or nil,
      draw = draw, deb = deb, floor = floor_of(name) }
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
  -- A completing card drawn face-down counts as a miss because the out must be seen.
  local function seen_pct(n, m, k, q)
    if q >= 1 then return complete_pct(n, m, k) end
    if k < 1 or n < 1 or m < 1 then return 0 end
    k = math.min(k, m)
    local all, miss = n_choose(m, k), 0
    for j = 0, math.min(n, k) do
      miss = miss + n_choose(n, j) * n_choose(m - n, k - j) / all * (1 - q) ^ j
    end
    return math.floor((1 - miss) * 100 + 0.5)
  end
  local function draw_note(match, k)
    local pool, concealed = CardUtil.unplayed_pool()
    if not pool or #pool == 0 or not match or not read then return false end
    if (tonumber(k) or 0) < 1 then return false end
    k = k or 1
    local function outs()
      local n, hideable, faced = 0, 0, 0
      for _, c in ipairs(pool) do
        if match(c) then
          if read.faces and is_face_card(c) then
            faced = faced + 1
          else
            n = n + 1
            if not read.only_faces or is_face_card(c) then hideable = hideable + 1 end
          end
        end
      end
      return n, hideable, faced
    end
    if (concealed or 0) == 0 then
      -- Draw odds are public only when every card in the pool is public.
      if not public_pool(pool, concealed) then return false end
      local n, _, faced = outs()
      if n == 0 then return nil end
      return { n = n, m = #pool, pct = seen_pct(n, #pool, k, read.q), faced = faced > 0 and faced or nil }
    end
    for _, c in ipairs(pool) do
      if not (PublicCard.is_public(c) or CardUtil.is_composition_public(c)) then return false end
    end
    local m = #pool - concealed
    if m < 1 then return false end
    local n, hideable, faced = outs()
    if n == 0 then return nil end
    faced = faced > 0 and faced or nil
    local lo, hi = n - math.min(concealed, hideable), math.min(n, m)
    local plo, phi = seen_pct(lo, m, k, read.q), seen_pct(hi, m, k, read.q)
    if lo == hi then return { n = hi, m = m, pct = phi, faced = faced } end
    return { lo = lo, n = hi, m = m, plo = plo, pct = phi, faced = faced }
  end
  local pile_memo
  local function deck_rank_pile()
    if pile_memo ~= nil then return pile_memo end
    local dk, flipped = CardUtil.unplayed_pool()
    if type(dk) ~= "table" or #dk == 0 or not public_pool(dk, flipped) then
      pile_memo = false; return false
    end
    pile_memo = rank_tally(dk)
    return pile_memo
  end
  local function best_kicker(exclude)
    local pile = deck_rank_pile()
    if not pile then return nil end
    local best, best_n = nil, 0
    for _, c in ipairs(kcards) do
      local r = rank_of(c)
      if r ~= nil and r ~= exclude and (k_rank_counts[r] or 0) == 1 and (pile[r] or 0) > best_n then
        best, best_n = r, pile[r]
      end
    end
    return best
  end

  local function near_entry(name, ix, match)
    if type(ix) ~= "table" or #ix == 0 then return nil end
    local deb = deb_in_ix(ix)
    if deb == #ix then return nil end
    local dn = draw_note(match, draws_for(ix))
    if dn == nil then return nil end
    return keep_entry(name, ix, dn, deb)
  end

  local ready_set = {}
  local ready_dud = {}
  local ready_deb = {}
  local ready_ix = {}
  local ready_best = {}
  local function mark_ready(name, best)
    ready_set[name] = true
    ready_best[name] = best
    ready_ix[name] = positions_of(best)
    if debuffed > 0 then
      ready_deb[name] = DebuffFacts.count(best)
      if DebuffFacts.all_debuffed(best) then ready_dud[name] = true end
    end
  end
  for name, best in pairs(ready_sets(cards)) do mark_ready(name, best) end

  cache_strong(ready_set, strong_sig())

  local near_set = {}
  local discards = GameFacts.discards_left()
  if discards > 0 then
    -- An outranked hand type already present is not one card away.
    local held = contained_types(cards)
    -- Keep an unrevealed secret hand unnamed until the game exposes it.
    local hands = G and G.GAME and G.GAME.hands or {}
    local function near(name)
      if hands[name] and hands[name].visible == false then return end
      if not ready_set[name] and not held[name] then near_set[name] = true end
    end
    if flush_thr > 1 and ksh.max_suit == flush_thr - 1 then near("Flush") end
    if ksh.near_straight then near("Straight") end
    if ksh.quads > 0 then near("Five of a Kind") end
    if ksh.trips > 0 then near("Four of a Kind") end
    if ksh.trips >= 1 or ksh.pairs >= 2 then near("Full House") end
    if ksh.pairs >= 1 then near("Three of a Kind") end
    if ksh.pairs == 1 then near("Two Pair") end
  end

  local function by_order(a, b) return (HAND_ORDER[a] or 0) > (HAND_ORDER[b] or 0) end
  local function ranked(set, cap, cache, keep)
    local list = {}
    for name in pairs(set) do
      if (HAND_ORDER[name] or 0) >= 2 then list[#list + 1] = name end
    end
    if #list == 0 and set["High Card"] then list[1] = "High Card" end
    table.sort(list, by_order)
    while #list > cap do table.remove(list) end
    if keep and set[keep] then
      local listed = false
      for _, n in ipairs(list) do if n == keep then listed = true end end
      if not listed then
        list[math.min(#list + 1, cap)] = keep
        table.sort(list, by_order)
      end
    end
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

  local out = {
    lead = fd_lead, debuffed = debuffed, facedown = facedown, ready = {}, close = {},
    shape = { pairs = pair_count, trips = trips_count, quads = sh.quads, max_suit = max_suit, max_run = max_run,
      top = high_pair_rank > 0 and M.rank_label(high_pair_rank) or nil },
  }

  local ready = ranked(ready_set, 4, _ready_order_cache, top_scoring(ready_best))
  local ready_zeroed = {}
  if has_restr then
    local function padded(best)
      if min_play <= #best then return best end
      local set, present = {}, {}
      for _, c in ipairs(best) do set[#set + 1] = c; present[c] = true end
      for _, c in ipairs(cards) do
        if #set >= min_play then break end
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
    local tooth_on = DebuffFacts.tooth_active()
    local ox_hand = DebuffFacts.ox_active() and DebuffFacts.most_played_hand() or nil
    for i, n in ipairs(ready) do
      local ix = ready_ix[n]
      out.ready[i] = {
        name = n, ix = ix, level = current_values(n),
        deb = ready_dud[n] and "all" or (ready_deb[n] or 0), floor = floor_of(n),
        cost = (tooth_on and ix and #ix > 0) and #ix or nil, ox = (ox_hand and n == ox_hand) and true or nil,
        chain = chain_parts(M.joker_chain(ready_best[n], n)), zeroed = ready_zeroed[n],
      }
    end
    if CardUtil.owns_live_joker("j_splash") then out.splash = CardUtil.highlight_limit() end
  end

  local near_label = {}
  if near_set["Flush"] then
    local counts = k_suit_counts
    for _, s in ipairs(suit_list()) do
      local key = suit_key_of(s)
      if counts[key] == flush_thr - 1 then
        local ix, all_deb = {}, true
        for _, c in ipairs(kcards) do
          if suited(c, key) then
            ix[#ix + 1] = hand_pos[c]
            if not c.debuff then all_deb = false end
          end
        end
        local outs = draw_note(function(c) return suited(c, key) end,
          draws_for(ix))
        if not all_deb and outs ~= nil then
          local entry = keep_entry("Flush", ix, outs, deb_in_ix(ix))
          entry.suit_count = counts[key]
          entry.suit = smeared_active() and (SUIT_COLOR[key] or tostring(key)) or tostring(key)
          near_label["Flush"] = entry
          break
        end
      end
    end
    if not near_label["Flush"] then near_set["Flush"] = nil end
  end
  if near_set["Straight"] then
    local pick = best_straight_keep(k_present, straight_thr)
    local rr = pick and pick.set or {}
    local missing = pick and pick.outs or {}
    local st_match = function(c)
      local r = rank_of(c)
      return (r and missing[r]) and true or false
    end
    local best_at = {}
    for _, c in ipairs(kcards) do
      local rid = rank_of(c)
      if rid and rr[rid] then
        local cur = best_at[rid]
        if not cur or (G.hand.cards[cur].debuff and not c.debuff) then best_at[rid] = hand_pos[c] end
      end
    end
    local ix = {}
    for _, i in pairs(best_at) do ix[#ix + 1] = i end
    table.sort(ix)
    if #ix > 0 then
      local entry = near_entry("Straight", ix, st_match)
      if entry then
        entry.open = pick.out_ranks >= 2
        near_label["Straight"] = entry
      else
        near_set["Straight"] = nil
      end
    end
  end

  do
    local kby
    local function rank_positions(take)
      kby = kby or rank_copies(kcards)
      local ix = {}
      for _, c in ipairs(take_copies(kby, take)) do ix[#ix + 1] = hand_pos[c] end
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
          local anchor = name == "Two Pair" and next(take) or nil
          if name == "Full House" then
            for r, nn in pairs(take) do if nn >= 3 then anchor = r end end
          end
          if name == "Five of a Kind" or name == "Four of a Kind" or name == "Three of a Kind" then
            match = rank_is(next(take))
          elseif anchor then
            -- One-card outs require a public kicker rank; otherwise the anchor needs two cards.
            local kick = best_kicker(anchor)
            if kick ~= nil then take[kick] = 1; match = rank_is(kick) end
          elseif name == "Full House" then
            match = function(c) return take[rank_of(c) or false] ~= nil end
          end
          local entry = match and near_entry(name, rank_positions(take), match) or nil
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
  local figures = false
  for i, n in ipairs(nr) do
    out.close[i] = near_label[n] or { name = n }
    out.close[i].zeroed = near_zeroed[n]
    if type(out.close[i].draw) == "table" then figures = true end
  end
  out.lead = fd_lead .. (figures and (odds_lead .. odds_tail) or (no_odds_lead .. no_odds_tail))
  return out
end

local function hand_visible(hd)
  return not not (type(hd) == "table" and hd.visible)
end
local function level_rows(row_of)
  local rows = {}
  if not (G and G.GAME and G.GAME.hands) then return rows end
  for name, hd in pairs(G.GAME.hands) do
    if hand_visible(hd) then rows[#rows + 1] = row_of(name, hd) end
  end
  table.sort(rows, function(a, b)
    local ao, bo = HAND_ORDER[a.name] or 999, HAND_ORDER[b.name] or 999
    if ao ~= bo then return ao < bo end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end
local function levels() return level_rows(hand_values) end

function M.base_levels()
  return level_rows(function(name, hd)
    local level = hd.level or 1
    local chips = hd.s_chips or (level == 1 and hd.chips) or nil
    local mult = hd.s_mult or (level == 1 and hd.mult) or nil
    if chips and mult then return { name = name, chips = math.max(chips, 0), mult = math.max(mult, 0) } end
  end)
end

function M.level_notes()
  local notes = {}
  if DebuffFacts.flint_active() then notes[#notes + 1] = "Flint active: c,m already halved" end
  if arm_active() then
    notes[#notes + 1] = "The Arm active: chips and mult already include the one-level drop it applies to the hand you play"
  end
  if plasma_balances() then
    notes[#notes + 1] = "Plasma deck: final score balances total chips and mult"
  end
  return notes
end

function M.any_face_down()
  return (G and G.hand and G.hand.cards and n_face_down(G.hand.cards) > 0) or false
end

function M.discard_advice_applies()
  return not M.any_face_down() or discard_draw_read(BossModel.next_draw_facedown()) ~= nil
end

function M.has_strong_ready()
  if not (G and G.hand and G.hand.cards and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function") then
    return false
  end
  local sig = strong_sig()
  if sig and sig == _strong_cache.sig then return _strong_cache.val end
  return cache_strong(ready_hands(public_cards(G.hand.cards)), sig)
end

function M.joker_chain(cards, name)
  if type(cards) ~= "table" or #cards == 0 then return nil end
  local ok, js = pcall(Scoring.joker_summary, cards)
  if not ok or not js then return nil end
  local ct = with_type(cards, name)
  return Scoring.slot_chain(js, function(t, exact) return ct[t] and (t == name or not exact) end), js
end

function M.joker_chain_prose(steps)
  return table.concat(chain_parts(steps), "; ")
end

local function level_base(name)
  local v = current_values(name)
  if v then return v.chips, v.mult end
  return nil
end

function M.level_value(name)
  local chips, mult = level_base(name)
  return chips and chips * mult or nil
end

-- Exclude chance effects such as Lucky, so this estimate is a floor; editions score afterward.
local function card_parts(c)
  local ab = type(c.ability) == "table" and c.ability or {}
  local ok, v = pcall(c.get_chip_bonus, c)
  local chips = ok and tonumber(v) or 0
  local mult = (tonumber(ab.perma_mult) or 0) + (ab.effect ~= "Lucky Card" and tonumber(ab.mult) or 0)
  -- `Card:get_chip_x_mult` adds `perma_x_mult` to `x_mult`.
  local base_x = tonumber(ab.x_mult) or 1
  if base_x == 0 then base_x = 1 end
  local x = base_x * (1 + ((not ab.extra_enhancement and tonumber(ab.perma_x_mult)) or 0))
  if x < 1 then x = 1 end
  local ed = type(c.edition) == "table" and c.edition or {}
  return chips + (tonumber(ed.chips) or 0), mult, x, tonumber(ed.mult) or 0, tonumber(ed.x_mult) or 1
end

function M.selection_value(played, name, scoring)
  if type(played) ~= "table" or #played == 0 then return nil end
  for _, c in ipairs(played) do if not PublicCard.is_public(c) then return nil end end
  local chips, mult = level_base(name)
  if not chips then return nil end
  scoring = scoring or Scoring.scoring_subset(played) or played
  for _, c in ipairs(scoring) do
    if type(c) == "table" and not c.debuff then
      local cc, cm, cx, em, ex = card_parts(c)
      chips, mult = chips + cc, ((mult + cm) * cx + em) * ex
    end
  end
  -- Held Steel cards score after played cards, so different kept cards affect the comparison.
  local in_play = {}
  for _, c in ipairs(played) do in_play[c] = true end
  for _, c in ipairs((G and G.hand and G.hand.cards) or {}) do
    local ab = type(c) == "table" and type(c.ability) == "table" and c.ability
    if ab and not in_play[c] and not c.debuff and PublicCard.is_public(c) then
      for _ = 1, c.seal == "Red" and 2 or 1 do
        mult = (mult + (tonumber(ab.h_mult) or 0)) * math.max(tonumber(ab.h_x_mult) or 1, 1)
      end
    end
  end
  for _, st in ipairs(M.joker_chain(played, name) or {}) do
    local v = tonumber(st.value) or 0
    if st.kind == "chips" then chips = chips + v
    elseif st.kind == "xchips" then chips = chips * v
    elseif st.kind == "mult" then mult = mult + v
    elseif st.kind == "xmult" then mult = mult * v end
  end
  return chips * mult
end

M.HAND_ORDER = HAND_ORDER
function M.rank_label(id) return HAND_RANK_LABEL[id] or tostring(id) end
M.levels = levels
M.hand_values = current_values
M.plasma_balances = plasma_balances
M.ready_hands = ready_hands

return M
