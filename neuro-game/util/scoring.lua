local Scoring = {}

local CardSemantics = require("facts.card_semantics")
local NumericEffects = require("facts.numeric_effects")
local DynamicJokers = require("facts.dynamic_jokers")
local CardUtil = require("facts.card_util")

local function has_face_down(cards)
  for _, card in ipairs(cards or {}) do
    if CardUtil.is_face_down(card) then return true end
  end
  return false
end

local function splash_state()
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" then return "no" end
  local PublicCard = require("facts.public_card_identity")
  local unknown = false
  for i, card in ipairs(cards) do
    if type(card) == "table" and not card.debuff then
      if PublicCard.multiset_key(card, "jokers", i) == "center:j_splash" then return "yes" end
      if not PublicCard.is_public(card) then unknown = true end
    end
  end
  return unknown and "unknown" or "no"
end

local function public_jokers()
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" then return {}, false end
  local PublicCard = require("facts.public_card_identity")
  local out, down = {}, 0
  for _, card in ipairs(cards) do
    if type(card) == "table" then
      if PublicCard.is_public(card) then out[#out + 1] = card else down = down + 1 end
    end
  end
  if down > 0 and down == #cards then return cards, false end
  return out, down > 0
end

-- SMODS.always_scores/never_scores (smods/src/utils.lua:1135-1154) are the engine's own predicates;
-- the Stone key is the offline fallback for a run without SMODS loaded.
local function always_scores(card)
  if type(card) ~= "table" then return false end
  local SM = rawget(_G, "SMODS")
  if SM and type(SM.always_scores) == "function" then
    local ok, v = pcall(SM.always_scores, card)
    if ok and v then return true end
  end
  return CardUtil.enhancement_key(card) == "m_stone"
end

local function never_scores(card)
  local SM = rawget(_G, "SMODS")
  if not (SM and type(SM.never_scores) == "function") then return false end
  local ok, v = pcall(SM.never_scores, card)
  return ok and v and true or false
end

local function scoring_subset(selection)
  if type(selection) ~= "table" or #selection == 0 then return nil end
  local info = G and G.FUNCS and G.FUNCS.get_poker_hand_info
  if type(info) ~= "function" then return nil end
  local ok, _, _, _, scoring = pcall(info, selection)
  if not ok or type(scoring) ~= "table" or #scoring == 0 then return nil end
  local splash = splash_state()
  if splash ~= "no" or has_face_down(selection) then
    local whole = {}
    for _, card in ipairs(selection) do
      if not never_scores(card) then whole[#whole + 1] = card end
    end
    return whole, splash == "yes" and not has_face_down(selection)
  end
  local widened, seen = {}, {}
  for _, card in ipairs(scoring) do widened[#widened + 1] = card; seen[card] = true end
  for _, card in ipairs(selection) do
    if not seen[card] and always_scores(card) and not never_scores(card) then
      widened[#widened + 1] = card
      seen[card] = true
    end
  end
  return widened, true
end

local function matching_cards(scoring, match)
  local n = 0
  for _, card in ipairs(scoring) do
    if type(card) == "table" and not card.debuff and (not match or match(card)) then n = n + 1 end
  end
  return n
end

local Q = {}
Scoring.Q = Q

local function factor(kind) return kind == "xmult" or kind == "xchips" end

function Q.known(n) return { k = "known", n = n, why = {} } end
function Q.unknown(reason) return { k = "unknown", why = { tostring(reason or "something I cannot read") } } end
function Q.at_most(n, source)
  if not source or source == "" then return Q.unknown("a ceiling I cannot source") end
  return { k = "at_most", n = n, why = { source } }
end

function Q.identity(kind) return Q.known(factor(kind) and 1 or 0) end

function Q.combine(kind, a, b)
  if a.k == "unknown" then return { k = "unknown", why = a.why } end
  if b.k == "unknown" then return { k = "unknown", why = b.why } end
  local why = {}
  for _, w in ipairs(a.why) do why[#why + 1] = w end
  for _, w in ipairs(b.why) do why[#why + 1] = w end
  return {
    k = (a.k == "at_most" or b.k == "at_most") and "at_most" or "known",
    n = factor(kind) and (a.n * b.n) or (a.n + b.n),
    why = why,
  }
end

function Q.is_identity(kind, q)
  return q.k ~= "unknown" and q.n == (factor(kind) and 1 or 0)
end

local function apply(kind, rate, count)
  if factor(kind) then return rate ^ count end
  return rate * count
end

local VANILLA_PLAY_LIMIT = 5

local function scoring_hand_cap(board)
  local cap = VANILLA_PLAY_LIMIT
  local limit = tonumber(CardUtil.highlight_limit())
  if limit and limit > cap then cap = limit end
  local selection = board and board.selection
  if type(selection) == "table" and #selection > cap then cap = #selection end
  local scoring = board and board.scoring
  if type(scoring) == "table" and #scoring > cap then cap = #scoring end
  return cap
end

local SCORING_HAND_SOURCE = "the cards one hand can score"

local function such_cards(n)
  return tostring(n) .. ((tonumber(n) == 1) and " such card" or " such cards")
end

local function safe_name(card)
  local ok, n = pcall(require("util.utils").safe_name_or, card)
  return (ok and n) or "a joker"
end

-- A row Blueprint copied is paid by the TARGET's own branch (smods/src/utils.lua:2251-2253), so
-- context.other_joker's `self ~= context.other_joker` test excludes the target, not the copier.
local function scope_src(row)
  return row.copy_src or row.joker_src
end

local function tri_match(match, card)
  if not match then return true end
  local suit = tostring(match):match("^suit:(.+)$")
  if suit then
    local ok, v = pcall(function() return card:is_suit(suit) end)
    if not ok then return nil end
    return v and true or false
  end
  if match == "uncommon_joker" then
    local ok, v = pcall(function() return card:is_rarity("Uncommon") end)
    if ok then return v and true or false end
    local rarity = card and card.config and card.config.center and card.config.center.rarity
    if rarity == nil then return nil end
    return rarity == 2 or rarity == "Uncommon"
  end
  local fn = DynamicJokers.MATCH[match]
  if not fn then return nil end
  return fn(card)
end

local function count_matches(cards, match)
  local n, decidable, hit = 0, true, {}
  for _, card in ipairs(cards or {}) do
    if type(card) == "table" and not card.debuff then
      local m = tri_match(match, card)
      if m == nil then decidable = false
      elseif m then n = n + 1; hit[n] = card end
    end
  end
  if not decidable then return nil, #(cards or {}) end
  return n, n, hit
end

local function deck_population()
  if G and G.playing_cards and #G.playing_cards > 0 then return G.playing_cards end
  if G and G.deck and G.deck.cards and #G.deck.cards > 0 then return G.deck.cards end
  return nil
end

local function hand_size()
  local n = G and G.hand and G.hand.config and tonumber(G.hand.config.card_limit)
  if n and n > 0 then return n end
  return nil
end

-- The G.hand pass runs in the same loop as the play, before the refill (state_events.lua:672 vs
-- :454), so a held-card scope reads the post-move hand; CardUtil owns that predicate.
local function held_after_play(board)
  return CardUtil.held_after_play(board and board.selection)
end

local function held_bound(board)
  local remaining, exact = held_after_play(board)
  if remaining and exact then return #remaining end
  return hand_size()
end

local function population_uncached(row, board)
  if row.scope == "scoring_card" then
    if board.scoring and not has_face_down(board.scoring) then
      local exact, bound, hit = count_matches(board.scoring, row.match)
      if exact and board.scoring_exact then return exact, nil, nil, hit end
      local n = exact or bound
      return nil, math.min(n, scoring_hand_cap(board)), board.scoring_exact
        and ("the " .. n .. " cards you are about to score")
        or ("the " .. #board.scoring .. " cards you are about to play")
    end
    local deck = deck_population()
    if deck then
      local exact, bound = count_matches(deck, row.match)
      local cap = math.min(exact or bound, scoring_hand_cap(board))
      local why = exact and (such_cards(exact) .. " in your deck") or SCORING_HAND_SOURCE
      return nil, cap, why
    end
    return nil, scoring_hand_cap(board), SCORING_HAND_SOURCE
  end
  if row.scope == "held_card" then
    local held, exact_pop = held_after_play(board)
    if held and not has_face_down(held) then
      local exact, _, hit = count_matches(held, row.match)
      if exact then
        if exact_pop then return exact, nil, nil, hit end
        return nil, exact, such_cards(exact) .. " in hand, and the ones you play stop counting as held"
      end
    end
    local limit = held_bound(board)
    if not limit then return nil, nil, nil end
    local deck = deck_population()
    local exact_deck = deck and select(1, count_matches(deck, row.match)) or nil
    local cap = math.min(exact_deck or limit, limit)
    local why = exact_deck and (such_cards(exact_deck) .. " in your deck, and you hold at most " .. limit)
      or ("you hold at most " .. limit .. " cards")
    return nil, cap, why
  end
  if row.scope == "other_joker" then
    local jokers = G and G.jokers and G.jokers.cards
    if type(jokers) ~= "table" then return nil, nil, nil end
    local PublicCard = require("facts.public_card_identity")
    local others, hidden = {}, false
    for _, j in ipairs(jokers) do
      if j ~= scope_src(row) then
        others[#others + 1] = j
        if not PublicCard.is_public(j) then hidden = true end
      end
    end
    local exact = (not hidden) and count_matches(others, row.match) or nil
    if exact then return exact, nil, nil end
    return nil, #others, "the " .. #others .. " other jokers you own"
  end
  return nil, nil, nil
end

local function population_for(row, board)
  local cache = board.cache
  if not cache then return population_uncached(row, board) end
  local tag = row.scope .. "|" .. tostring(row.match) .. "|" .. tostring(scope_src(row))
  local hit = cache[tag]
  if hit then return hit[1], hit[2], hit[3], hit[4] end
  local a, b, c, d = population_uncached(row, board)
  cache[tag] = { a, b, c, d }
  return a, b, c, d
end

local function gate_source(row)
  local g = row.gate
  if not g then return nil end
  return g.text or NumericEffects.gate_phrase(g.kind, g.value and tostring(g.value), "prose") or nil
end

local RETRIGGER_AREA = { scoring_card = "played", held_card = "held" }

local function retriggers_for(board, scope)
  local area = RETRIGGER_AREA[scope]
  if not area then return nil end
  local live = {}
  for _, e in ipairs(board.retriggers or {}) do
    if e.area == area and e.live ~= false and (tonumber(e.reps) or 0) > 0 then live[#live + 1] = e end
  end
  if #live == 0 then return nil end
  return live
end

local function extra_passes_exact(entries, cards, first_card)
  local extra = 0
  for _, e in ipairs(entries) do
    for _, c in ipairs(cards or {}) do
      local m
      if e.first_only then m = (c == first_card)
      elseif e.match then m = e.match(c)
      else m = true end
      if m == nil then return nil end
      if m then extra = extra + e.reps end
    end
  end
  return extra
end

local function extra_passes_ceiling(entries, count)
  local extra = 0
  for _, e in ipairs(entries) do
    extra = extra + (e.first_only and e.reps or e.reps * count)
  end
  return extra
end

local function retrigger_why(why, entries)
  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = safe_name(e.card) end
  local list = (#names == 1) and names[1]
    or (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names])
  return why .. ", each re-scored by " .. list
end

function Scoring.total_of(row, board)
  board = board or {}
  if row.scope == "hand" then
    if not row.gate then return Q.known(row.rate) end
    if row.gate.kind == "random" then
      return Q.at_most(row.ceiling or row.rate, "its " .. row.gate.min .. "-" .. row.gate.max .. " roll")
    end
    return Q.at_most(row.rate, gate_source(row))
  end
  if row.at_most_once then return Q.at_most(row.ceiling or row.rate, gate_source(row)) end
  local exact, ceiling, why, matched = population_for(row, board)
  local entries = retriggers_for(board, row.scope)
  if exact then
    local extra = entries and extra_passes_exact(entries, matched, board.scoring and board.scoring[1]) or 0
    if extra then
      local passes = exact + extra
      if row.gate and row.gate.kind == "odds" then
        return Q.at_most(apply(row.kind, row.rate, passes),
          exact .. " matching cards, and it pays 1 time in " .. row.gate.den)
      end
      return Q.known(apply(row.kind, row.rate, passes))
    end
    ceiling, why = exact, such_cards(exact) .. " matching, re-scored an unreadable number of times"
  end
  if ceiling then
    local passes = ceiling
    if entries then
      passes = ceiling + extra_passes_ceiling(entries, ceiling)
      why = retrigger_why(why, entries)
    end
    if row.gate and row.gate.kind == "odds" and row.gate.den then
      why = why .. ", and it pays 1 time in " .. row.gate.den
    end
    return Q.at_most(apply(row.kind, row.rate, passes), why)
  end
  return Q.unknown(gate_source(row) or "a count I cannot read")
end

local function retrigger_entries(selection)
  local cards = public_jokers()
  local out, scoring, scanned, scoring_exact = {}, nil, false, false
  for _, card in ipairs(cards) do
    local center = type(card) == "table" and not card.debuff and card.config and card.config.center
    local spec = center and center.key and NumericEffects.RETRIGGER[center.key]
    if spec then
      local reps = spec.reps(card)
      if reps > 0 then
        if not scanned then scoring, scoring_exact = scoring_subset(selection); scanned = true end
        local entry = { key = center.key, card = card, kind = "reps", scope = "retrigger",
          area = spec.scope, subject = spec.subject, reps = reps,
          match = spec.match, first_only = spec.first_only }
        if spec.gate then
          entry.gated = true
          local gate = type(spec.gate) == "table" and spec.gate or nil
          entry.gate_text = gate and type(gate.text) == "string" and gate.text or nil
          local ok, active = false, false
          if gate and type(gate.active) == "function" then ok, active = pcall(gate.active) end
          entry.live = ok and active and true or false
        end
        if scoring and scoring_exact and entry.area == "played" then
          if entry.live == nil then entry.live = true end
          entry.cards = spec.first_only and 1 or matching_cards(scoring, spec.match)
          entry.passes = entry.cards * reps
        end
        out[#out + 1] = entry
      end
    end
  end
  if #out == 0 then return nil end
  return out
end

local function retrigger_passes(entries)
  local total, known = 0, false
  for _, e in ipairs(entries or {}) do
    if e.passes and e.live ~= false then total = total + e.passes; known = true end
  end
  if not known then return nil end
  return total
end

local KINDS = { "chips", "mult", "xmult", "xchips" }

local function add_refusal(ledger, key, name, reason)
  local tag = tostring(name) .. "|" .. tostring(reason)
  if ledger.refused_seen[tag] then return end
  ledger.refused_seen[tag] = true
  ledger.refused[#ledger.refused + 1] = { key = key, name = name, reason = reason }
end

local function scope_population_size(scope, board)
  if scope == "scoring_card" then
    if board.scoring and not has_face_down(board.scoring) then return #board.scoring end
    return scoring_hand_cap(board)
  end
  if scope == "held_card" then return held_bound(board) end
  if scope == "other_joker" then
    local jokers = G and G.jokers and G.jokers.cards
    return type(jokers) == "table" and math.max(#jokers - 1, 0) or nil
  end
  return nil
end

local function scope_card_pool(scope, board)
  if scope == "held_card" then
    local held = held_after_play(board)
    if held and #held > 0 and not has_face_down(held) then return held end
    return deck_population()
  end
  if scope == "scoring_card" then return deck_population() end
  if scope == "other_joker" then
    local pool, hidden = public_jokers()
    return (not hidden) and pool or nil
  end
  return nil
end

local function budget_combine(kind, rows, scope, budget, board)
  local pool = budget and scope_card_pool(scope, board)
  if not pool then
    local combined = Q.identity(kind)
    for _, row in ipairs(rows) do combined = Q.combine(kind, combined, row.total) end
    return combined
  end
  local entries = retriggers_for(board, scope)
  local values, why = {}, {}
  for _, row in ipairs(rows) do why[#why + 1] = row.total.why[1] end
  for _, card in ipairs(pool) do
    if type(card) == "table" and not card.debuff then
      local passes = 1
      if entries then passes = passes + (extra_passes_exact(entries, { card }, card) or
        extra_passes_ceiling(entries, 1)) end
      local v = 1
      for _, row in ipairs(rows) do
        if card ~= scope_src(row) and tri_match(row.match, card) ~= false then
          v = v * row.rate ^ passes
        end
      end
      if v > 1 then values[#values + 1] = v end
    end
  end
  table.sort(values, function(a, b) return a > b end)
  local total_value = 1
  for i = 1, math.min(budget, #values) do total_value = total_value * values[i] end
  return Q.at_most(total_value, table.concat(why, "; "))
end

local function by_type_bucket(ledger, hand_type)
  local bucket = ledger.by_type[hand_type]
  if not bucket then
    bucket = { chips = 0, mult = 0, xmult = 1, xchips = 1,
      acc_chips = 0, acc_mult = 0, acc_xmult = 1, acc_xchips = 1, sources = {}, njokers = 0 }
    ledger.by_type[hand_type] = bucket
  end
  return bucket
end

local function add_by_type_row(ledger, row)
  local ht = row.hand_type
  if not ht or ht == "" or row.scope ~= "hand" then return end
  local bucket = by_type_bucket(ledger, ht)
  if row.accumulator then bucket.accumulator = true end
  if row.joker_src and not bucket.sources[row.joker_src] then
    bucket.sources[row.joker_src] = true
    bucket.njokers = bucket.njokers + 1
  end
  if row.kind == "xmult" then
    bucket.xmult = bucket.xmult * row.value
    if row.accumulator then bucket.acc_xmult = bucket.acc_xmult * row.value end
  elseif row.kind == "chips" then
    bucket.chips = bucket.chips + row.value
    if row.accumulator then bucket.acc_chips = bucket.acc_chips + row.value end
  elseif row.kind == "mult" then
    bucket.mult = bucket.mult + row.value
    if row.accumulator then bucket.acc_mult = bucket.acc_mult + row.value end
  elseif row.kind == "xchips" then
    bucket.xchips = bucket.xchips * row.value
    if row.accumulator then bucket.acc_xchips = bucket.acc_xchips * row.value end
  end
  return true
end

local function build_ledger(aggregate, board, retriggers)
  local ledger = {
    always = {}, gated = {}, sources = {}, refused = {}, refused_seen = {}, source_seen = {}, by_type = {},
    covered = { hand = false, scoring_card = false, held_card = false, other_joker = false, retrigger = retriggers ~= nil },
  }
  for _, kind in ipairs(KINDS) do
    ledger.always[kind] = Q.identity(kind)
    ledger.gated[kind] = Q.identity(kind)
  end
  local factor_groups, group_order = {}, {}
  for _, row in ipairs(aggregate.rows) do
    if row.kind ~= "reps" then
      local total = Scoring.total_of(row, board)
      row.total = total
      if total.k == "unknown" then
        add_refusal(ledger, row.key, safe_name(row.joker_src), total.why[1])
      else
        if not row.gate and row.scope == "hand" then
          ledger.covered[row.scope] = true
          ledger.always[row.kind] = Q.combine(row.kind, ledger.always[row.kind], total)
        elseif row.gate and row.gate.kind == "hand_type" then
          if add_by_type_row(ledger, row) then ledger.covered[row.scope] = true end
        else
          ledger.covered[row.scope] = true
          if not Q.is_identity(row.kind, total) then
            local name = safe_name(row.joker_src)
            local tag = name .. "|" .. row.kind .. "|" .. tostring(total.n) .. "|" .. tostring(total.why[1])
            if not ledger.source_seen[tag] then
              ledger.source_seen[tag] = true
              ledger.sources[#ledger.sources + 1] = { name = name, kind = row.kind,
                total = total, why = total.why[1] }
            end
          end
          local ceiling
          if factor(row.kind) and total.k == "at_most" and not row.at_most_once then
            local _, bound = population_for(row, board)
            ceiling = bound
          end
          if ceiling then
            local gkey = row.kind .. "|" .. row.scope
            if not factor_groups[gkey] then
              factor_groups[gkey] = { kind = row.kind, scope = row.scope, rows = {} }
              group_order[#group_order + 1] = gkey
            end
            local grp = factor_groups[gkey]
            grp.rows[#grp.rows + 1] = row
          else
            ledger.gated[row.kind] = Q.combine(row.kind, ledger.gated[row.kind], total)
          end
        end
      end
    end
  end
  for _, gkey in ipairs(group_order) do
    local grp = factor_groups[gkey]
    local budget = scope_population_size(grp.scope, board)
    local combined = budget_combine(grp.kind, grp.rows, grp.scope, budget, board)
    ledger.gated[grp.kind] = Q.combine(grp.kind, ledger.gated[grp.kind], combined)
  end
  for _, r in ipairs(aggregate.refusals) do
    add_refusal(ledger, r.key, safe_name(r.card), r.reason)
  end
  return ledger
end

function Scoring.joker_summary(selection, _opts)
  if not (G and G.jokers and G.jokers.cards) then return nil end
  local scoring, scoring_exact = scoring_subset(selection)
  local retriggers = retrigger_entries(selection)
  local board = { scoring = scoring, scoring_exact = scoring_exact, selection = selection,
    retriggers = retriggers, cache = {} }
  local roster, hidden_jokers = public_jokers()
  local aggregate = CardSemantics.aggregate(roster, board)
  local guaranteed = aggregate.guaranteed
  local cond_xmult, cond_xchips, cond_mult, cond_chips = 1, 1, 0, 0
  local cond_mult_per_card = 0
  for _, effect in ipairs(aggregate.conditional) do
    if not (effect.hand_type and effect.hand_type ~= "") then
      if effect.scope == "scoring_card" and effect.kind == "mult" then
        cond_mult_per_card = cond_mult_per_card + effect.value
      elseif effect.scope == "hand" then
        if effect.kind == "xmult" then cond_xmult = cond_xmult * effect.value
        elseif effect.kind == "xchips" then cond_xchips = cond_xchips * effect.value
        elseif effect.kind == "mult" then cond_mult = cond_mult + effect.value
        elseif effect.kind == "chips" then cond_chips = cond_chips + effect.value end
      end
    end
  end
  if guaranteed.chips == 0 and guaranteed.mult == 0 and guaranteed.xmult == 1
      and guaranteed.xchips == 1 and #aggregate.conditional == 0 and not retriggers
      and #aggregate.refusals == 0 then return nil end
  local ledger = build_ledger(aggregate, board, retriggers)
  return {
    chips = guaranteed.chips,
    mult = guaranteed.mult,
    xmult = guaranteed.xmult,
    xchips = guaranteed.xchips,
    cond_xmult = cond_xmult,
    cond_xchips = cond_xchips,
    cond_mult = cond_mult,
    cond_mult_per_card = cond_mult_per_card,
    cond_chips = cond_chips,
    cond_by_type = ledger.by_type,
    conditional = aggregate.conditional,
    retriggers = retriggers,
    retrigger_passes = retrigger_passes(retriggers),
    hidden_jokers = hidden_jokers or nil,
    ledger = ledger,
  }
end

local function guaranteed_flat_mult(card)
  local total = 0
  for _, e in ipairs(CardSemantics.project(card).effects) do
    if e.kind == "mult" and e.certainty == "guaranteed" and e.source ~= "edition" and not e.per_card then
      total = total + e.value
    end
  end
  return total
end

local function guaranteed_xmult(card)
  local total = 1
  for _, e in ipairs(CardSemantics.project(card).effects) do
    if e.kind == "xmult" and e.certainty == "guaranteed" then total = total * e.value end
  end
  return total
end

function Scoring.joker_order_gap()
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" or #cards < 2 then return nil end
  local PublicCard = require("facts.public_card_identity")
  for _, card in ipairs(cards) do
    if type(card) == "table" and not PublicCard.is_public(card) then return nil end
  end
  local pivot, behind, sig = nil, {}, {}
  for i, card in ipairs(cards) do
    local center = type(card) == "table" and card.config and card.config.center or nil
    sig[#sig + 1] = tostring(center and (center.key or center.name) or "?")
    if type(card) == "table" and not card.debuff then
      local flat = guaranteed_flat_mult(card)
      if pivot then
        if flat > 0 then behind[#behind + 1] = { index = i, card = card, mult = flat } end
      else
        local x = guaranteed_xmult(card)
        if x > 1 then pivot = { index = i, card = card, xmult = x } end
      end
    end
  end
  if not pivot or #behind == 0 then return nil end
  local marks = { pivot.index }
  for _, b in ipairs(behind) do marks[#marks + 1] = b.index end
  return {
    pivot = pivot,
    behind = behind,
    signature = table.concat(sig, "|") .. "#" .. table.concat(marks, ","),
  }
end

function Scoring.owned_has_xmult()
  return CardSemantics.has_guaranteed_xmult(public_jokers())
end

function Scoring.owned_xmult_state()
  local cards, hidden = public_jokers()
  if CardSemantics.has_guaranteed_xmult(cards) then return "guaranteed" end
  for _, c in ipairs(cards) do
    if not c.debuff and CardSemantics.produces_xmult(c) then return "conditional" end
  end
  if hidden then return "unknown" end
  return "none"
end

return Scoring
