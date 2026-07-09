local DebuffFacts = require("facts.debuff_facts")
local CardUtil = require("facts.card_util")
local NUMERIC_EFFECTS = require("facts.numeric_effects")
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

-- single source for suit/rank/run: never read card.base.suit directly (wrong under four fingers/shortcut/wild/smeared/stone)
local function smods() return rawget(_G, "SMODS") end
local function sm(fn, arg)
  local SM = smods()
  if SM and type(SM[fn]) == "function" then
    local ok, v = pcall(SM[fn], arg)
    if ok then return v end
  end
  return nil
end
-- split so a modded no-suit-but-ranked (or no-rank-but-suited) card is dropped only from the count it lacks
local function has_no_suit(card)
  local SM = smods()
  if SM and type(SM.has_no_suit) == "function" then
    local ok, v = pcall(SM.has_no_suit, card); if ok and v then return true end
  end
  local ck = card and card.config and card.config.center and card.config.center.key
  return ck == "m_stone"
end
local function has_no_rank(card)
  local SM = smods()
  if SM and type(SM.has_no_rank) == "function" then
    local ok, v = pcall(SM.has_no_rank, card); if ok and v then return true end
  end
  if card and type(card.get_id) == "function" then
    local ok, id = pcall(card.get_id, card); if ok and type(id) == "number" and id < 0 then return true end
  end
  local ck = card and card.config and card.config.center and card.config.center.key
  return ck == "m_stone"
end
local function rank_of(card)
  if card and type(card.get_id) == "function" then
    local ok, id = pcall(card.get_id, card); if ok and type(id) == "number" then return id end
  end
  local base = card and card.base
  return base and HAND_VALUE_RANK[tostring(base.value)] or nil
end
local function in_suit(card, suit)
  if card and type(card.is_suit) == "function" then
    local ok, v = pcall(card.is_suit, card, suit, true, true); if ok then return v and true or false end
  end
  local base = card and card.base
  return (base and tostring(base.suit) == suit) or false
end
local function suit_list()
  local SM = smods()
  return (SM and SM.Suit and SM.Suit.obj_buffer and #SM.Suit.obj_buffer > 0)
    and SM.Suit.obj_buffer or { "Hearts", "Diamonds", "Spades", "Clubs" }
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

local function best_near_straight_ranks(present, thr)
  if not thr or thr < 2 then return nil end
  local best_w, best_cnt = nil, 0
  for w = 1, 15 - thr do
    local cnt = 0
    for r = w, w + thr - 1 do if present[r] then cnt = cnt + 1 end end
    if cnt > best_cnt then best_cnt, best_w = cnt, w end
  end
  if best_w and best_cnt == thr - 1 then
    local set = {}
    for r = best_w, best_w + thr - 1 do if present[r] then set[r] = true end end
    return set
  end
  return nil
end

local function shape(cards)
  local _, max_suit = count_suits(cards)
  local rank_counts, present = count_ranks(cards)
  local max_run, run_ranks = max_run_of(present)
  local flush_thr = tonumber(sm("four_fingers", "flush")) or 5
  local straight_thr = tonumber(sm("four_fingers", "straight")) or 5
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
    straight_ready = max_run >= straight_thr, near_straight = straight_thr > 1 and max_run == straight_thr - 1,
    pairs = pair_count, trips = trips_count, quads = quad_count,
    high_pair_rank = high_pair_rank,
  }
end

-- accepts a flat card list or the engine's nested array-of-groups shape; refs not in G.hand.cards are skipped
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

-- evaluate sets are card-groups ordered best-first; a ready list is one best instance, never the union
local function best_group(set)
  if type(set) ~= "table" then return {} end
  if type(set[1]) == "table" and type(set[1][1]) == "table" then return set[1] end
  return set
end

local function best_scoring_cards(name, set)
  local out = {}
  for _, c in ipairs(best_group(set)) do out[#out + 1] = c end
  if name == "Flush" then
    table.sort(out, function(a, b) return (rank_of(a) or 0) > (rank_of(b) or 0) end)
  elseif name == "Straight" then
    local seen, dedup = {}, {}
    for _, c in ipairs(out) do
      local r = rank_of(c)
      if r and not seen[r] then seen[r] = true; dedup[#dedup + 1] = c end
    end
    out = dedup
  end
  local cap = play_cap()
  while #out > cap do table.remove(out) end
  return out
end

local function contained_types(cards)
  local t = {}
  if type(cards) ~= "table" or #cards == 0 then return t end
  local counts = count_ranks(cards)
  local n2, n3, n4, n5 = 0, 0, 0, 0
  for _, c in pairs(counts) do
    if c == 2 then n2 = n2 + 1
    elseif c == 3 then n3 = n3 + 1
    elseif c == 4 then n4 = n4 + 1
    elseif c >= 5 then n5 = n5 + 1 end
  end
  local sh = shape(cards)
  t["High Card"] = true
  if n5 > 0 then t["Five of a Kind"] = true end
  if n4 > 0 or t["Five of a Kind"] then t["Four of a Kind"] = true end
  if n3 > 0 or t["Four of a Kind"] then t["Three of a Kind"] = true end
  if n2 > 0 or t["Three of a Kind"] then t["Pair"] = true end
  if n3 > 0 and n2 > 0 then t["Full House"] = true end
  if (n2 == 2) or (n3 == 1 and n2 == 1) then t["Two Pair"] = true end
  if sh.straight_ready then t["Straight"] = true end
  if sh.flush_ready then
    t["Flush"] = true
    if sh.straight_ready then t["Straight Flush"] = true end
    if n3 > 0 and n2 > 0 then t["Flush House"] = true end
    if n5 > 0 then t["Flush Five"] = true end
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
  local ch, mu = tonumber(hd.chips) or 0, tonumber(hd.mult) or 0
  -- The Flint halves the played hand's base chips+mult; show the halved base so the projection is right
  if DebuffFacts.flint_active() then ch, mu = DebuffFacts.flint_halve(ch, mu) end
  return string.format("(lv%g %gc x%g)", tonumber(hd.level) or 1, ch, mu)
end

local function type_conditional_jokers()
  local map
  if not (G and G.jokers and G.jokers.cards) then return map end
  for i, jc in ipairs(G.jokers.cards) do
    -- debuffed jokers don't fire (common_events.lua:586), so never annotate them
    local ab = type(jc) == "table" and not jc.debuff and jc.ability
    local ht = type(ab) == "table" and ab.type
    if type(ht) == "string" and ht ~= "" then
      for _, e in ipairs(NUMERIC_EFFECTS) do
        if (e.cond or e.type_cond) and ab[e.field] and ab[e.field] ~= e.skip then
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

local function joker_note(matches)
  if type(matches) ~= "table" or #matches == 0 then return "" end
  local s = {}
  for i, v in ipairs(matches) do s[i] = "J" .. tostring(v) end
  return "(" .. table.concat(s, ",") .. (#s > 1 and " apply)" or " applies)")
end

local function hand_structure_summary()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return ""
  end

  local debuffed = DebuffFacts.count(G.hand.cards)
  local has_restr = DebuffFacts.has_hand_restriction()

  local facedown = false
  local bname = (G.GAME and G.GAME.blind and tostring(G.GAME.blind.name)) or ""
  for _, n in ipairs({ "The House", "The Wheel", "The Fish", "The Mark" }) do
    if bname == n then facedown = true end
  end

  local sh = shape(G.hand.cards)
  local pair_count, trips_count = sh.pairs, sh.trips
  local has3, has4 = sh.trips > 0, sh.quads > 0
  local high_pair_rank = sh.high_pair_rank
  local max_suit, max_run = sh.max_suit, sh.max_run
  local flush_thr, straight_thr = sh.flush_thr, sh.straight_thr

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
  if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local ok, ph = pcall(function()
      local _, _, p = G.FUNCS.get_poker_hand_info(G.hand.cards)
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
    local rank_counts = count_ranks(G.hand.cards)
    local function take_cards(take)
      local out = {}
      for _, c in ipairs(G.hand.cards) do
        if not has_no_rank(c) then
          local r = rank_of(c)
          if r and take[r] and take[r] > 0 then
            take[r] = take[r] - 1
            out[#out + 1] = c
          end
        end
      end
      return out
    end
    local function top_rank(min_count, exclude) return rank_top(rank_counts, min_count, exclude) end
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
      local cards = take and take_cards(take)
      if cards and #cards > 0 and contained_types(cards)[name] then
        mark_ready(name, cards)
      end
    end
  end

  local near_set = {}
  local discards = (G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left) or 0
  if discards > 0 then
    local function near(name) if not ready_set[name] then near_set[name] = true end end
    local _, present_ranks = count_ranks(G.hand.cards)
    if flush_thr > 1 and max_suit == flush_thr - 1 then near("Flush") end
    if straight_thr > 1 and (max_run == straight_thr - 1
        or (not sm("shortcut") and near_straight_window(present_ranks, straight_thr))) then near("Straight") end
    if has4 then near("Five of a Kind") end
    if has3 then near("Four of a Kind") end
    if trips_count >= 1 or pair_count >= 2 then near("Full House") end
    if pair_count >= 1 then near("Three of a Kind") end
    if pair_count == 1 then near("Two Pair") end
  end

  local function ranked(set, cap)
    local list = {}
    for name in pairs(set) do
      if (HAND_ORDER[name] or 0) >= 2 then list[#list + 1] = name end
    end
    table.sort(list, function(a, b) return (HAND_ORDER[a] or 0) > (HAND_ORDER[b] or 0) end)
    while #list > cap do table.remove(list) end
    return list
  end

  local high_pair = high_pair_rank > 0 and (HAND_RANK_LABEL[high_pair_rank] or tostring(high_pair_rank)) or "-"
  -- pairs/trips/quads are cumulative (>=2 / >=3 / >=4), so a five-of-a-kind reads as all three; label explicitly
  local out = string.format("Structure: pairs>=2:%d trips>=3:%d quads>=4:%d top:%s suit_max:%d run_max:%d.",
    pair_count, trips_count, sh.quads, high_pair, max_suit, max_run)

  if debuffed > 0 then
    out = out .. string.format(" %d card(s) DEBUFFED (they score 0).", debuffed)
  end

  local play_note = DebuffFacts.boss_play_note()
  if play_note then out = out .. " " .. play_note end

  local ready = ranked(ready_set, 4)
  if debuffed > 0 then
    -- an all-debuffed hand scores 0, not "ready"; else the poker-rank sort surfaces it as the top play
    local kept = {}
    for _, n in ipairs(ready) do
      if not ready_dud[n] then kept[#kept + 1] = n end
    end
    ready = kept
  end
  if has_restr then
    local note = DebuffFacts.boss_hand_restriction_note()
    if note then out = out .. " " .. note end
    -- size-floor boss (Psychic: must play >=N) constrains card count not type; pad to N before checking or valid types drop
    local min_sz = 0
    do
      local d = G.GAME and G.GAME.blind and G.GAME.blind.debuff
      if type(d) == "table" then min_sz = tonumber(d.h_size_ge) or 0 end
    end
    local function padded(best)
      if min_sz <= #best then return best end
      local set, present = {}, {}
      for _, c in ipairs(best) do set[#set + 1] = c; present[c] = true end
      for _, c in ipairs(G.hand.cards) do
        if #set >= min_sz then break end
        if not present[c] then set[#set + 1] = c; present[c] = true end
      end
      return set
    end
    local kept = {}
    for _, n in ipairs(ready) do
      if not DebuffFacts.boss_would_debuff(padded(ready_best[n] or {}), n) then kept[#kept + 1] = n end
    end
    ready = kept
  end
  if #ready > 0 then
    local jmap = type_conditional_jokers()
    local function applied_jokers(name)
      if not jmap then return nil end
      local ct = contained_types(ready_best[name] or {})
      ct[name] = true
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
    for i, n in ipairs(ready) do
      local deb_note = ""
      if ready_dud[n] then
        deb_note = "(all debuffed~0)"
      elseif (ready_deb[n] or 0) > 0 then
        deb_note = "(" .. tostring(ready_deb[n]) .. " debuffed~0)"
      end
      ready[i] = n .. idx_suffix(ready_ix[n]) .. level_note(n)
        .. (jmap and joker_note(applied_jokers(n)) or "") .. deb_note
    end
    out = out .. " Ready: " .. table.concat(ready, ", ") .. "."
    if G.jokers and G.jokers.cards then
      for _, jc in ipairs(G.jokers.cards) do
        local ck = jc and not jc.debuff and jc.config and jc.config.center and jc.config.center.key
        if ck == "j_splash" then
          out = out .. " All played cards score (Splash)."
          break
        end
      end
    end
  end

  local near_label = {}
  if near_set["Flush"] then
    local counts = count_suits(G.hand.cards)
    for _, s in ipairs(suit_list()) do
      local key = (type(s) == "table" and (s.key or s.name)) or s
      if counts[key] == flush_thr - 1 then
        local ix, all_deb = {}, true
        for i, c in ipairs(G.hand.cards) do
          if not has_no_suit(c) and in_suit(c, key) then
            ix[#ix + 1] = i
            if not c.debuff then all_deb = false end
          end
        end
        -- a suit-debuff boss (The Club etc.) zeroes the whole suit; skip a fully-debuffed near-flush suit, keep scanning
        if not all_deb then
          near_label["Flush"] = string.format("Flush: %d %s%s", counts[key], tostring(key), idx_suffix(ix))
          break
        end
      end
    end
    if not near_label["Flush"] then near_set["Flush"] = nil end
  end
  if near_set["Straight"] then
    local _, present = count_ranks(G.hand.cards)
    local rr = ((not sm("shortcut")) and best_near_straight_ranks(present, straight_thr)) or sh.run_ranks or {}
    local ix, used = {}, {}
    for i, c in ipairs(G.hand.cards) do
      if not has_no_rank(c) then
        local rid = rank_of(c)
        if rid and (rr[rid] or (rid == 14 and rr[1])) and not used[rid] then
          used[rid] = true; ix[#ix + 1] = i
        end
      end
    end
    if #ix > 0 then near_label["Straight"] = "Straight" .. idx_suffix(ix) end
  end

  do
    local rank_counts = count_ranks(G.hand.cards)
    local function top_rank(min_count, exclude) return rank_top(rank_counts, min_count, exclude) end
    local function rank_positions(take)
      local ix = {}
      for i, c in ipairs(G.hand.cards) do
        if not has_no_rank(c) then
          local r = rank_of(c)
          if r and take[r] and take[r] > 0 then
            take[r] = take[r] - 1
            ix[#ix + 1] = i
          end
        end
      end
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
          local ix = rank_positions(take)
          if #ix > 0 then near_label[name] = name .. idx_suffix(ix) end
        end
      end
    end
  end

  local nr = ranked(near_set, 4)
  if has_restr then
    -- don't advertise building toward a hand type the boss now forbids (Eye already-used / Mouth locked type)
    local kept = {}
    for _, n in ipairs(nr) do
      if not DebuffFacts.boss_blocks_handname(n) then kept[#kept + 1] = n end
    end
    nr = kept
  end
  if #nr > 0 then
    for i, n in ipairs(nr) do nr[i] = "near " .. (near_label[n] or n) end
    out = out .. " Close: " .. table.concat(nr, ", ") .. "."
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
-- truthy-visible test; callers disagreed on nil (visible vs visible ~= false)
local function hand_visible(hd)
  return not not (type(hd) == "table" and hd.visible)
end
local function levels()
  local rows = {}
  if not (G and G.GAME and G.GAME.hands) then return rows end
  local flint = DebuffFacts.flint_active()
  for name, hd in pairs(G.GAME.hands) do
    if hand_visible(hd) then
      local ch, mu = hd.chips or 0, hd.mult or 0
      if flint then ch, mu = DebuffFacts.flint_halve(ch, mu) end
      rows[#rows + 1] = { name = name, level = hd.level or 1, chips = ch, mult = mu, played = hd.played or 0 }
    end
  end
  table.sort(rows, function(a, b)
    local ao, bo = LEVEL_ORDER[a.name] or 999, LEVEL_ORDER[b.name] or 999
    if ao ~= bo then return ao < bo end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

M.summary = hand_structure_summary
M.count_suits = count_suits
M.count_ranks = count_ranks
M.shape = shape
M.contained_types = contained_types
M.levels = levels
M.hand_visible = hand_visible

return M
