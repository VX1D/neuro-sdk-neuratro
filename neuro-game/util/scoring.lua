local Scoring = {}

local CardSemantics = require("facts.card_semantics")
local NumericEffects = require("facts.numeric_effects")
local DynamicJokers = require("facts.dynamic_jokers")
local CardUtil = require("facts.card_util")

local function has_face_down(cards)
  for _, card in ipairs(cards or {}) do
    if CardUtil.is_hidden(card) then return true end
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
  local out, hidden = {}, false
  for _, card in ipairs(cards) do
    if type(card) == "table" then
      if CardUtil.is_hidden(card) then
        hidden = true
      else
        out[#out + 1] = card
      end
    end
  end
  return out, hidden
end

local function joker_slot(card)
  local cards = G and G.jokers and G.jokers.cards
  if type(card) ~= "table" or type(cards) ~= "table" or CardUtil.is_hidden(card) then return nil end
  for i, c in ipairs(cards) do if c == card then return i end end
  return nil
end

local function always_scores(card)
  if type(card) ~= "table" then return false end
  local ok, v = pcall(SMODS.always_scores, card)
  return ok and v and true or false
end

local function never_scores(card)
  local ok, v = pcall(SMODS.never_scores, card)
  return ok and v and true or false
end

local function played_order(selection)
  local seat = {}
  for i, c in ipairs(G and G.hand and G.hand.cards or {}) do seat[c] = i end
  local out = {}
  for i, c in ipairs(selection) do out[i] = { card = c, i = i, seat = seat[c] or math.huge } end
  table.sort(out, function(a, b)
    if a.seat ~= b.seat then return a.seat < b.seat end
    return a.i < b.i
  end)
  for i, e in ipairs(out) do out[i] = e.card end
  return out
end

-- The subset follows engine order; Splash includes all selected cards, while face-down cards stay unread.
local function scoring_subset(selection)
  if type(selection) ~= "table" or #selection == 0 then return nil end
  local info = G and G.FUNCS and G.FUNCS.get_poker_hand_info
  if type(info) ~= "function" then return nil end
  local ok, _, _, _, scoring = pcall(info, selection)
  if not ok or type(scoring) ~= "table" or #scoring == 0 then return nil end
  local splash = splash_state()
  local played = played_order(selection)
  local whole = splash ~= "no" or has_face_down(selection)
  local member = {}
  for _, card in ipairs(scoring) do member[card] = true end
  local out = {}
  for _, card in ipairs(played) do
    if (CardUtil.is_hidden(card) or not never_scores(card))
        and (whole or member[card] or always_scores(card)) then
      out[#out + 1] = card
    end
  end
  if whole then return out, splash == "yes" and not has_face_down(selection) end
  return out, true
end

local function matching_cards(scoring, match)
  local n = 0
  for _, card in ipairs(scoring) do
    if type(card) == "table" and not CardUtil.is_hidden(card) and not card.debuff
        and (not match or match(card)) then n = n + 1 end
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
  local selection_count = type(selection) == "table" and #selection or 0
  if selection_count > cap then cap = selection_count end
  local scoring = board and board.scoring
  local scoring_count = type(scoring) == "table" and #scoring or 0
  if scoring_count > cap then cap = scoring_count end
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

local function concealed(card)
  return CardUtil.is_hidden(card) and not CardUtil.is_aggregate_public(card)
end

-- The unplayed pool is public as a whole, but concealed cards are not inspected individually.
local POOLED = setmetatable({}, { __mode = "k" })

local function unreadable(card, cards)
  local open = cards and POOLED[cards]
  return concealed(card) and not (open and open[card])
end

local function count_matches(cards, match, keep_debuffed, also)
  local n, maybe, hit = 0, 0, {}
  for _, card in ipairs(cards or {}) do
    if type(card) == "table" then
      if unreadable(card, cards) then
        maybe = maybe + 1
      elseif keep_debuffed or not card.debuff then
        local m = tri_match(match, card)
        if m ~= false and also then
          local ok, a = pcall(also, card)
          if not ok or a == nil then m = nil elseif not a then m = false end
        end
        if m == nil then maybe = maybe + 1
        elseif m then n = n + 1; hit[n] = card end
      end
    end
  end
  if maybe > 0 then return nil, n + maybe end
  return n, n, hit
end
local function discarded(card) return G and G.discard and card.area == G.discard end

local function deck_population()
  if G and G.playing_cards and #G.playing_cards > 0 then
    local open = {}
    for _, c in ipairs((CardUtil.unplayed_pool()) or {}) do open[c] = true end
    local out = {}
    for _, c in ipairs(G.playing_cards) do
      if type(c) == "table" and (open[c] or not discarded(c)) then out[#out + 1] = c end
    end
    if #out == 0 then return nil end
    POOLED[out] = open
    return out
  end
  if G and G.deck and G.deck.cards and #G.deck.cards > 0 then return G.deck.cards end
  return nil
end

local function pool_place(deck)
  local pile = G and G.discard and G.discard.cards
  if not (type(pile) == "table" and #pile > 0) then return "in your deck" end
  for _, c in ipairs(deck or {}) do
    if type(c) == "table" and discarded(c) then return "in your hand, draw pile and unseen discards" end
  end
  return "in your hand and draw pile"
end

local function hand_size()
  local n = G and G.hand and G.hand.config and tonumber(G.hand.config.card_limit)
  if n and n > 0 then return n end
  return nil
end

local function held_after_play(board)
  return DynamicJokers.held_at_score(board and board.selection)
end
local function held_bound(board)
  local remaining, exact = held_after_play(board)
  if remaining then return #remaining end
  if exact then return 0 end
  return hand_size()
end

local function population_uncached(row, board, also)
  if row.scope == "scoring_card" then
    if board.scoring then
      local exact, bound, hit = count_matches(board.scoring, row.match, false, also)
      if exact and board.scoring_exact then return exact, nil, nil, hit end
      local n = exact or bound
      return nil, math.min(n, scoring_hand_cap(board)), board.scoring_exact
        and ("the " .. n .. " cards you are about to score")
        or ("the " .. #board.scoring .. " cards you are about to play")
    end
    local deck = deck_population()
    if deck then
      local exact, bound = count_matches(deck, row.match, false, also)
      local cap = math.min(exact or bound, scoring_hand_cap(board))
      local why = exact and (such_cards(exact) .. " " .. pool_place(deck)) or SCORING_HAND_SOURCE
      return nil, cap, why
    end
    return nil, scoring_hand_cap(board), SCORING_HAND_SOURCE
  end
  if row.scope == "held_card" then
    local held, exact_pop, unsettled = held_after_play(board)
    if held and not has_face_down(held) then
      local exact, _, hit = count_matches(held, row.match, false, also)
      if exact then
        if exact_pop then return exact, nil, nil, hit end
        return nil, exact, such_cards(exact) .. " in hand, and "
          .. (unsettled or "the ones you play stop counting as held")
      end
    end
    local limit = held_bound(board)
    if not limit then return nil, nil, nil end
    local deck = deck_population()
    local exact_deck = deck and select(1, count_matches(deck, row.match, false, also)) or nil
    local cap = math.min(exact_deck or limit, limit)
    local why = exact_deck and (such_cards(exact_deck) .. " " .. pool_place(deck) .. ", and you hold at most " .. limit)
      or ("you hold at most " .. limit .. " cards")
    return nil, cap, why
  end
  if row.scope == "other_joker" then
    local jokers = G and G.jokers and G.jokers.cards
    if type(jokers) ~= "table" then return nil, nil, nil end
    local others = {}
    for _, j in ipairs(jokers) do
      if j ~= scope_src(row) then others[#others + 1] = j end
    end
    local exact = count_matches(others, row.match, true, also)
    if exact then return exact, nil, nil end
    return nil, #others, "the " .. #others .. " other jokers you own"
  end
  return nil, nil, nil
end

local function population_for(row, board, also)
  local cache = board.cache
  if not cache then return population_uncached(row, board, also) end
  local tag = row.scope .. "|" .. tostring(row.match) .. "|" .. tostring(scope_src(row)) .. "|" .. tostring(also)
  local hit = cache[tag]
  if hit then return hit[1], hit[2], hit[3], hit[4] end
  local a, b, c, d = population_uncached(row, board, also)
  cache[tag] = { a, b, c, d }
  return a, b, c, d
end

local function gate_source(row)
  local g = row.gate
  if not g then return nil end
  return g.text or NumericEffects.gate_phrase(g.kind, g.value and tostring(g.value), "prose") or nil
end

local function gate_state(row, board)
  local active = row.gate and row.gate.kind == "board_state" and row.gate.active
  if type(active) ~= "function" then return nil end
  local ok, live = pcall(active, scope_src(row), board or {})
  if not ok then return nil end
  return live
end

local function gate_inactive(row, board) return gate_state(row, board) == false end

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

local function card_reps(board, scope, card, first)
  return DynamicJokers.card_reps(board, RETRIGGER_AREA[scope], card, first)
end

local function own_red(card)
  local s = card.seal
  if type(s) == "table" then s = s.key or s.name end
  return s == "Red"
end

local function concealed_red_budget()
  local cards = G and G.playing_cards
  if type(cards) ~= "table" then return math.huge end
  local n = 0
  for _, c in ipairs(cards) do
    if type(c) == "table" and concealed(c) and CardUtil.is_composition_public(c) and own_red(c) then n = n + 1 end
  end
  return n
end

local function red_sealed(card, hidden)
  if not hidden then return own_red(card) end
  return not CardUtil.is_composition_public(card) or concealed_red_budget() > 0
end

local function red_seal_count(pool)
  local n, hidden = 0, 0
  for _, c in ipairs(pool or {}) do
    if type(c) == "table" then
      if not concealed(c) then
        if own_red(c) then n = n + 1 end
      elseif CardUtil.is_composition_public(c) then hidden = hidden + 1
      else n = n + 1 end
    end
  end
  if hidden > 0 then n = n + math.min(hidden, concealed_red_budget()) end
  return n
end

local function scorable_pool(board)
  if board.scoring then return board.scoring end
  return deck_population()
end

local function overlap(row, board, test, ceiling)
  local exact, bound = population_for(row, board, test)
  local n = exact or bound
  if not n then return ceiling end
  return math.min(n, ceiling)
end

-- Count retriggers only when their card can match the row.
local function row_extra_passes(row, board, entries, ceiling)
  local extra, reaching, reds = 0, {}, 0
  for _, e in ipairs(entries or {}) do
    local n = ceiling
    if e.first_only then n = math.min(1, ceiling)
    elseif e.match then n = overlap(row, board, e.match, ceiling) end
    if n > 0 then
      extra = extra + e.reps * n
      reaching[#reaching + 1] = e
    end
  end
  if RETRIGGER_AREA[row.scope] and ceiling > 0 then
    local pool = row.scope == "held_card" and held_after_play(board) or scorable_pool(board)
    reds = math.min(overlap(row, board, own_red, ceiling), red_seal_count(pool))
  end
  return extra, (#reaching > 0) and reaching or nil, reds
end

local function retrigger_why(why, entries)
  local names = {}
  for _, e in ipairs(entries) do names[#names + 1] = safe_name(e.card) end
  local list = (#names == 1) and names[1]
    or (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names])
  return why .. ", each re-scored by " .. list
end

local function registry_row(row)
  local src = scope_src(row)
  local center = type(src) == "table" and src.config and src.config.center
  for _, r in ipairs(center and DynamicJokers.ROWS[center.key] or {}) do
    if r.kind == row.kind and r.scope == row.scope then return r end
  end
  return nil
end

local function odds_of(row)
  if not (row.gate and row.gate.kind == "odds") then return nil, nil, false end
  local n, d = DynamicJokers.odds(row.gate, scope_src(row))
  if not (n and d) then return nil, nil, true end
  return n, d, n < d
end

local function odds_why(row)
  local n, d = odds_of(row)
  if not n then return "it pays only on a chance roll" end
  local fmt = require("util.utils").fmt_num
  return "it pays " .. fmt(n) .. " time" .. (n == 1 and "" or "s") .. " in " .. fmt(d)
end

local SIM_RANK = { chips = 1, mult = 2, xchips = 3, xmult = 4 }

local function by_slot(rows)
  local out = {}
  for i, row in ipairs(rows) do
    local slot = joker_slot(row.joker_src)
    if slot then out[#out + 1] = { row = row, slot = slot, rank = SIM_RANK[row.kind] or 5, i = i } end
  end
  table.sort(out, function(a, b)
    if a.slot ~= b.slot then return a.slot < b.slot end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.i < b.i
  end)
  return out
end

-- Simulate exact order only when every card and joker in the phase is public.
local function simulate(board, rows)
  local sim = { steps = {}, totals = {}, undecided = {} }
  if board.hidden_jokers then return sim end
  local phases = {}
  if board.scoring and board.scoring_exact and not has_face_down(board.scoring) then
    phases[#phases + 1] = { scope = "scoring_card", cards = board.scoring, first = board.scoring[1] }
  end
  if board.selection and #board.selection > 0 then
    local held, exact = held_after_play(board)
    if exact and type(held) == "table" and not has_face_down(held) then
      phases[#phases + 1] = { scope = "held_card", cards = held }
    end
  end
  for _, phase in ipairs(phases) do
    local list = {}
    for _, row in ipairs(rows) do
      if row.scope == phase.scope and SIM_RANK[row.kind] and not gate_inactive(row, board) then list[#list + 1] = row end
    end
    local ordered = by_slot(list)
    local picks = {}
    for _, o in ipairs(ordered) do
      local reg = registry_row(o.row)
      if reg and type(reg.pick) == "function" then
        local ok, target = pcall(reg.pick, phase.cards)
        if not ok or target == false then sim.undecided[o.row] = true else picks[o.row] = target or "none" end
      end
      o.chance = select(3, odds_of(o.row))
      sim.totals[o.row] = { values = {} }
    end
    local phase_ok = true
    for _, c in ipairs(phase.cards) do
      if not c.debuff then
        local hits = {}
        for _, o in ipairs(ordered) do
          if not sim.undecided[o.row] then
            local pays
            if picks[o.row] then pays = picks[o.row] == c else pays = tri_match(o.row.match, c) end
            if pays == nil then sim.undecided[o.row] = true
            elseif pays then hits[#hits + 1] = o end
          end
        end
        local passes = 1
        if phase.scope == "scoring_card" or #hits > 0 then
          passes = card_reps(board, phase.scope, c, phase.first)
          if not passes then phase_ok = false; break end
        end
        for pass = 1, passes do
          for _, o in ipairs(hits) do
            local t = sim.totals[o.row].values
            t[#t + 1] = o.row.rate
            sim.steps[#sim.steps + 1] = { slot = o.slot, rank = o.rank, kind = o.row.kind, value = o.row.rate,
              card = c, pass = pass, phase = phase.scope, row = o.row, chance = o.chance }
          end
        end
      end
    end
    if not phase_ok then
      for _, o in ipairs(ordered) do sim.undecided[o.row] = true end
      local kept = {}
      for _, st in ipairs(sim.steps) do if st.phase ~= phase.scope then kept[#kept + 1] = st end end
      sim.steps = kept
    end
  end
  return sim
end

local function sim_total(row, board)
  local sim = board.sim
  local t = sim and sim.totals[row]
  if not t or sim.undecided[row] then return nil end
  local q = Q.known(apply(row.kind, row.rate, 0))
  for _, v in ipairs(t.values) do q = Q.combine(row.kind, q, Q.known(v)) end
  if select(3, odds_of(row)) then
    return Q.at_most(q.n, #t.values .. " scoring pass" .. (#t.values == 1 and "" or "es") .. " it can pay on, and " .. odds_why(row))
  end
  return q
end

local function max_passes_one(row, board)
  local extra, _, reds = row_extra_passes(row, board, retriggers_for(board, row.scope), 1)
  return 1 + extra + reds
end

function Scoring.total_of(row, board)
  board = board or {}
  if row.scope == "hand" then
    if not row.gate then return Q.known(row.rate) end
    if row.gate.kind == "rescored" then
      if row.at_score then
        local q = Q.known(row.at_score)
        q.why = { gate_source(row) }
        return q
      end
      if row.ceiling then return Q.at_most(row.ceiling, gate_source(row)) end
      return Q.unknown(gate_source(row))
    end
    if row.gate.kind == "random" then
      return Q.at_most(row.ceiling or row.rate, "its " .. row.gate.min .. "-" .. row.gate.max .. " roll")
    end
    if gate_state(row, board) == true then return Q.known(row.rate) end
    return Q.at_most(row.rate, gate_source(row))
  end
  local simulated = sim_total(row, board)
  if simulated then return simulated end
  if row.at_most_once then
    if board.hidden_jokers and (row.scope == "scoring_card" or row.scope == "held_card") then
      return Q.unknown("a concealed joker may add unreadable retriggers")
    end
    local passes = max_passes_one(row, board)
    local why = gate_source(row)
    if passes > 1 then why = (why or "one card") .. ", which retriggers can score " .. passes .. " times" end
    local unsettled = row.scope == "held_card" and select(3, held_after_play(board))
    if unsettled then why = (why or "one card") .. ", and " .. unsettled end
    return Q.at_most(apply(row.kind, row.ceiling or row.rate, passes), why)
  end
  local exact, ceiling, why, matched = population_for(row, board)
  local entries = retriggers_for(board, row.scope)
  if exact then
    if board.hidden_jokers and (row.scope == "scoring_card" or row.scope == "held_card") then
      return Q.unknown("a concealed joker may add unreadable retriggers")
    end
    local passes = 0
    if RETRIGGER_AREA[row.scope] then
      for _, c in ipairs(matched or {}) do
        local r = card_reps(board, row.scope, c, board.scoring and board.scoring[1])
        if not r then passes = nil; break end
        passes = passes + r
      end
    else
      passes = exact
    end
    if passes ~= nil then
      if select(3, odds_of(row)) then
        return Q.at_most(apply(row.kind, row.rate, passes), exact .. " matching cards, and " .. odds_why(row))
      end
      return Q.known(apply(row.kind, row.rate, passes))
    end
    ceiling, why = exact, such_cards(exact) .. " matching, but retrigger matching is undecidable"
  end
  if ceiling then
    local extra, reaching, reds = row_extra_passes(row, board, entries, ceiling)
    local passes = ceiling + extra + reds
    if reaching then why = retrigger_why(why, reaching) end
    if reds > 0 then why = why .. ", Red Seals included" end
    if select(3, odds_of(row)) then why = why .. ", and " .. odds_why(row) end
    return Q.at_most(apply(row.kind, row.rate, passes), why)
  end
  return Q.unknown(gate_source(row) or "a count I cannot read")
end

-- Blueprint and Brainstorm copies inherit retrigger context.
local function retrigger_entries(selection)
  local cards = public_jokers()
  local out, scoring, scanned, scoring_exact = {}, nil, false, false
  for _, card in ipairs(cards) do
    local source = type(card) == "table" and not card.debuff and DynamicJokers.resolve_copy(card)
    local center = source and source.config and source.config.center
    local spec = center and center.key and NumericEffects.RETRIGGER[center.key]
    if spec then
      local reps = spec.reps(source)
      if reps > 0 then
        if not scanned then scoring, scoring_exact = scoring_subset(selection); scanned = true end
        local entry = { key = center.key, card = card, source = source, kind = "reps", scope = "retrigger",
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

local KINDS = { "chips", "mult", "xmult", "xchips" }

local function add_refusal(ledger, key, name, reason)
  local tag = tostring(name) .. "|" .. tostring(reason)
  if ledger.refused_seen[tag] then return end
  ledger.refused_seen[tag] = true
  ledger.refused[#ledger.refused + 1] = { key = key, name = name, reason = reason }
end

local function scope_population_size(scope, board)
  if scope == "scoring_card" then
    if board.scoring then return #board.scoring end
    return scoring_hand_cap(board)
  end
  if scope == "held_card" then return held_bound(board) end
  if scope == "other_joker" then
    local jokers = G and G.jokers and G.jokers.cards
    if type(jokers) ~= "table" then return nil end
    return math.max(#jokers - 1, 0)
  end
  return nil
end

local function scope_card_pool(scope, board)
  if scope == "held_card" then
    local held = held_after_play(board)
    if held and #held > 0 and not has_face_down(held) then return held end
    return deck_population()
  end
  if scope == "scoring_card" then return board.scoring or deck_population() end
  if scope == "other_joker" then
    local jokers = G and G.jokers and G.jokers.cards
    return type(jokers) == "table" and jokers or nil
  end
  return nil
end

local function pool_passes(entries, card, hidden)
  local base, first, unknown = 1, 0, false
  for _, e in ipairs(entries or {}) do
    if e.first_only then
      first = first + e.reps
    else
      local m = true
      if e.match and not hidden then
        local ok, v = pcall(e.match, card)
        if ok then m = v else unknown = true end
      end
      if m then base = base + e.reps end
    end
  end
  if red_sealed(card, hidden) then base = base + 1 end
  return base, first, unknown
end

local function budget_combine(kind, rows, scope, budget, board)
  local pool = budget and scope_card_pool(scope, board)
  if not pool then
    local combined = Q.identity(kind)
    for _, row in ipairs(rows) do combined = Q.combine(kind, combined, row.total) end
    return combined
  end
  local entries = retriggers_for(board, scope)
  local cards = RETRIGGER_AREA[scope] ~= nil
  local plain, boosted, why = {}, {}, {}
  local retrigger_unknown = false
  for _, row in ipairs(rows) do why[#why + 1] = row.total.why[1] end
  for _, card in ipairs(pool) do
    local hidden = type(card) == "table" and unreadable(card, pool)
    -- Treat concealed cards as matching every row to keep the ceiling sound.
    if type(card) == "table" and (hidden or not (cards and card.debuff)) then
      local base, first = 1, 0
      if cards then
        local unknown
        base, first, unknown = pool_passes(entries, card, hidden)
        if unknown then retrigger_unknown = true end
      end
      local v, w = 1, 1
      for _, row in ipairs(rows) do
        if card ~= scope_src(row) and (hidden or tri_match(row.match, card) ~= false) then
          v = v * row.rate ^ base
          w = w * row.rate ^ (base + first)
        end
      end
      if w > 1 then plain[#plain + 1] = v; boosted[#plain] = w end
    end
  end
  local order = {}
  for i = 1, #plain do order[i] = i end
  table.sort(order, function(a, b) return plain[a] > plain[b] end)
  local function top(n, skip)
    local p, taken = 1, 0
    for _, i in ipairs(order) do
      if taken >= n then break end
      if i ~= skip then p = p * plain[i]; taken = taken + 1 end
    end
    return p
  end
  local total_value = top(budget)
  if budget >= 1 then
    for i = 1, #plain do
      local with_first = boosted[i] * top(budget - 1, i)
      if with_first > total_value then total_value = with_first end
    end
  end
  if retrigger_unknown then why[#why + 1] = "retrigger matching is undecidable" end
  return Q.at_most(total_value, table.concat(why, "; "))
end

local function by_type_bucket(ledger, hand_type)
  local bucket = ledger.by_type[hand_type]
  if not bucket then
    bucket = { acc_chips = 0, acc_mult = 0, acc_xmult = 1, acc_xchips = 1,
      con_chips = 0, con_mult = 0, con_xmult = 1, con_xchips = 1, sources = {}, njokers = 0 }
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
  -- Keep contained and exact-type factors separate; division cannot recover the original factors.
  local part = row.accumulator and "acc_" or "con_"
  if factor(row.kind) then
    bucket[part .. row.kind] = bucket[part .. row.kind] * row.value
  elseif row.kind == "chips" or row.kind == "mult" then
    bucket[part .. row.kind] = bucket[part .. row.kind] + row.value
  end
  return true
end

local function build_ledger(aggregate, board, retriggers)
  local ledger = {
    always = {}, gated = {}, sources = {}, refused = {}, refused_seen = {}, source_seen = {}, by_type = {},
    dormant = {}, met = {}, rows = aggregate.rows, board = board,
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
        elseif row.scope == "hand" and total.k == "known"
            and (row.gate.kind == "rescored" or gate_state(row, board) == true) then
          ledger.covered.hand = true
          if not Q.is_identity(row.kind, total) then
            ledger.met[#ledger.met + 1] = { name = safe_name(row.joker_src), kind = row.kind, total = total,
              why = gate_source(row), rescored = row.gate.kind == "rescored", slot = joker_slot(row.joker_src) }
          end
        elseif gate_inactive(row, board) then
          if not Q.is_identity(row.kind, total) then
            ledger.dormant[#ledger.dormant + 1] = { name = safe_name(row.joker_src), kind = row.kind,
              total = total, why = gate_source(row) }
          end
        else
          ledger.covered[row.scope] = true
          if not Q.is_identity(row.kind, total) then
            local owner = row.joker_src or safe_name(row.joker_src)
            local seen = ledger.source_seen[owner] or {}
            ledger.source_seen[owner] = seen
            local tag = row.kind .. "|" .. tostring(total.n) .. "|" .. tostring(total.why[1])
            if not seen[tag] then
              seen[tag] = true
              ledger.sources[#ledger.sources + 1] = { name = safe_name(row.joker_src), kind = row.kind,
                total = total, why = total.why[1], src = row.joker_src, slot = joker_slot(row.joker_src) }
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
  local roster, hidden_jokers = public_jokers()
  local retriggers = retrigger_entries(selection)
  local board = { scoring = scoring, scoring_exact = scoring_exact, selection = selection,
    retriggers = retriggers, hidden_jokers = hidden_jokers, cache = {} }
  local aggregate = CardSemantics.aggregate(roster, board)
  board.sim = simulate(board, aggregate.rows)
  local guaranteed = aggregate.guaranteed
  if guaranteed.chips == 0 and guaranteed.mult == 0 and guaranteed.xmult == 1
      and guaranteed.xchips == 1 and #aggregate.conditional == 0 and not retriggers
      and #aggregate.refusals == 0 then return nil end
  local ledger = build_ledger(aggregate, board, retriggers)
  return {
    chips = guaranteed.chips,
    mult = guaranteed.mult,
    xmult = guaranteed.xmult,
    xchips = guaranteed.xchips,
    cond_by_type = ledger.by_type,
    conditional = aggregate.conditional,
    retriggers = retriggers,
    hidden_jokers = hidden_jokers or nil,
    ledger = ledger,
  }
end

-- Per joker, score edition chips/mult, its effect and other jokers' effects on it, then edition xMult.
local KIND_RANK = SIM_RANK
local OTHER_JOKER_RANK = 6

local function step_rank(row)
  if row.source == "edition" then return factor(row.kind) and 7 or 0 end
  return KIND_RANK[row.kind] or 5
end

local REGISTER = { chips = "chips", xchips = "chips", mult = "mult", xmult = "mult" }

local function commutes(steps)
  local add, mul = {}, {}
  for _, st in ipairs(steps) do
    if factor(st.kind) then mul[REGISTER[st.kind]] = true else add[REGISTER[st.kind]] = true end
  end
  return not ((add.mult and mul.mult) or (add.chips and mul.chips))
end

local function folded(kind, a, b) return factor(kind) and a * b or a + b end

local function per_joker(steps)
  local by, out = {}, {}
  for _, st in ipairs(steps) do
    local key = st.slot .. "|" .. st.kind
    if by[key] then
      by[key].value = folded(st.kind, by[key].value, st.value)
    else
      by[key] = { slot = st.slot, rank = st.rank, kind = st.kind, value = st.value, cards = true }
      out[#out + 1] = by[key]
    end
  end
  table.sort(out, function(a, b)
    if a.slot ~= b.slot then return a.slot < b.slot end
    return a.rank < b.rank
  end)
  return out
end

local function per_card(steps)
  local out = {}
  for _, st in ipairs(steps) do
    local last = out[#out]
    if last and last.slot == st.slot and last.kind == st.kind and last.card == st.card then
      last.value = folded(st.kind, last.value, st.value)
    else
      out[#out + 1] = { slot = st.slot, rank = st.rank, kind = st.kind, value = st.value, cards = true,
        card = st.card, held = st.phase == "held_card" }
    end
  end
  return out
end

function Scoring.slot_chain(summary, applies)
  local led = summary and summary.ledger
  local cards = G and G.jokers and G.jokers.cards
  if not (led and led.rows and type(cards) == "table") then return nil end
  local board = led.board or {}
  local sim = board.sim
  local card_steps = {}
  for _, st in ipairs(sim and sim.steps or {}) do
    if not st.chance and not sim.undecided[st.row] and not Q.is_identity(st.kind, Q.known(st.value)) then
      card_steps[#card_steps + 1] = st
    end
  end
  local steps = commutes(card_steps) and per_joker(card_steps) or per_card(card_steps)
  local joker_steps = {}
  local function add(slot, rank, row, value)
    if not slot or value == nil or Q.is_identity(row.kind, Q.known(value)) then return end
    joker_steps[#joker_steps + 1] = { slot = slot, rank = rank, kind = row.kind, value = value,
      cards = false, seq = #joker_steps + 1 }
  end
  for _, row in ipairs(led.rows) do
    local q, slot = row.total, joker_slot(row.joker_src)
    if slot and q and KIND_RANK[row.kind] and not RETRIGGER_AREA[row.scope] then
      if row.gate and row.gate.kind == "hand_type" then
        if row.scope == "hand" and applies and applies(row.hand_type, row.accumulator) then
          add(slot, step_rank(row), row, row.value)
        end
      elseif q.k == "known" and not gate_inactive(row, board) then
        if row.scope == "other_joker" then
          for i, other in ipairs(cards) do
            if other ~= scope_src(row) and not concealed(other) and tri_match(row.match, other) then
              add(i, OTHER_JOKER_RANK, row, row.rate)
            end
          end
        else
          add(slot, step_rank(row), row, q.n)
        end
      end
    end
  end
  table.sort(joker_steps, function(a, b)
    if a.slot ~= b.slot then return a.slot < b.slot end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.seq < b.seq
  end)
  -- The engine pays a joker's stored value and growth together.
  for _, st in ipairs(joker_steps) do
    local last = steps[#steps]
    if last and not last.cards and last.slot == st.slot and last.kind == st.kind and last.rank == st.rank then
      last.value = folded(st.kind, last.value, st.value)
    else
      steps[#steps + 1] = st
    end
  end
  return steps
end

local ORDER_PAIRS = { { add = "mult", factor = "xmult" }, { add = "chips", factor = "xchips" } }

local function at_scoring(e)
  if e.scope ~= "hand" or (e.gate and e.gate.kind ~= "rescored") then return nil end
  return Scoring.total_of(e, {})
end

local function slot_add(card, kind)
  local flat, bound, typed, typed_exact, typed_type = 0, nil, 0, false, nil
  for _, e in ipairs(CardSemantics.project(card).effects) do
    if e.kind == kind and e.scope == "hand" then
      local g = e.gate
      local q = at_scoring(e)
      if q then
        if q.k == "unknown" then return 0 end
        flat = flat + q.n
        if q.k == "at_most" then bound = "at_most" end
      elseif g.kind == "hand_type" and e.hand_type and e.value > typed then
        typed, typed_exact, typed_type = e.value, e.accumulator and true or false, e.hand_type
      end
    end
  end
  if DynamicJokers.growth_state(card, kind) == "unread" then
    if bound == "at_most" then return 0 end
    bound = "at_least"
  end
  return flat + typed, typed_type and { hand_type = typed_type, exact = typed_exact } or nil, bound
end

-- Unknown rescored factors have a floor of x1; the game never pays below x1.
local function guaranteed_factor(card, kind)
  local total, floor = 1, DynamicJokers.growth_state(card, kind) ~= nil
  for _, e in ipairs(CardSemantics.project(card).effects) do
    local q = e.kind == kind and at_scoring(e)
    if q then
      if q.k == "known" then total = total * q.n else floor = true end
    end
  end
  return total, floor
end

function Scoring.joker_order_gap()
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" or #cards < 2 then return nil end
  for _, card in ipairs(cards) do
    if type(card) == "table" and CardUtil.is_hidden(card) then return nil end
  end
  local groups, sig, marks = {}, {}, {}
  for _, pair in ipairs(ORDER_PAIRS) do
    local pivot, behind, factors, floored = nil, {}, {}, false
    for i, card in ipairs(cards) do
      local center = type(card) == "table" and card.config and card.config.center or nil
      local key = tostring(center and (center.key or center.name) or "?")
      if type(card) == "table" and not card.debuff then
        local amount, cond, bound = slot_add(card, pair.add)
        local x, floor = guaranteed_factor(card, pair.factor)
        factors[i] = x
        floored = floored or floor
        sig[#sig + 1] = pair.add .. ":" .. key .. ":" .. tostring(bound or "") .. tostring(amount)
          .. ":" .. tostring(x) .. (floor and "+" or "")
          .. (cond and (":" .. cond.hand_type .. (cond.exact and "=" or "")) or "")
        if pivot then
          if amount > 0 then
            behind[#behind + 1] = { index = i, card = card, amount = amount, cond = cond, bound = bound }
          end
        elseif x > 1 then
          pivot = { index = i, card = card, factor = x, floor = floor }
        end
      else
        sig[#sig + 1] = pair.add .. ":" .. key .. ":debuffed"
      end
    end
    -- Growth makes each gain a floor; an additive ceiling cannot bound it.
    local priced = {}
    for _, b in ipairs(behind) do
      b.gain_bound = floored and "at_least" or b.bound
      if not (floored and b.bound == "at_most") then priced[#priced + 1] = b end
    end
    behind = priced
    if pivot and #behind > 0 then
      for _, b in ipairs(behind) do
        local left, right = 1, 1
        for i, x in pairs(factors) do
          if i < b.index then left = left * x else right = right * x end
        end
        b.gain = b.amount * right * (left - 1)
      end
      marks[#marks + 1] = pair.add .. pivot.index
      for _, b in ipairs(behind) do marks[#marks + 1] = b.index end
      groups[#groups + 1] = { add = pair.add, factor = pair.factor, pivot = pivot, behind = behind }
    end
  end
  if #groups == 0 then return nil end
  return { groups = groups, signature = table.concat(sig, "|") .. "#" .. table.concat(marks, ",") }
end

Scoring.always_scores = always_scores
Scoring.never_scores = never_scores
Scoring.splash_state = splash_state
Scoring.scoring_subset = scoring_subset

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
