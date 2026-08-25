rawset(_G, "NEURO_TEST", true)
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local HandHandlers = require("handlers.hand_handlers")
local Scoring = require("util.scoring")
local CtxHelpers = require("context.ctx_helpers")
local check, done = H.harness("confirm hidden derivability")

local sid = 0
local function card(v, suit)
  sid = sid + 1
  local id = H.RID[v]
  local c = {
    base = { value = H.VALN[v] or v, suit = suit, id = id, nominal = (id <= 10 and id or 10) },
    sort_id = sid, cost = 1, sell_cost = 1,
    ability = { set = "Default", name = "Base", effect = "" },
    config = { center = { key = "c_base", set = "Default" } },
    facing = "front",
  }
  c.is_suit = function(_, s) return s == suit end
  c.get_id = function(self) return self.base.id end
  c.is_face = function(self) return self.base.id >= 11 and self.base.id <= 13 end
  return c
end

local function joker(key, name, ability, desc)
  sid = sid + 1
  ability = ability or {}
  ability.name = name
  ability.set = "Joker"
  return { sort_id = sid, cost = 5, sell_cost = 2, ability = ability, facing = "front",
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name, description = { desc or "" } } } },
    is_rarity = function(_, r) return r == "Common" end }
end

local RANKS = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
local SUITS = { "Spades","Hearts","Clubs","Diamonds" }

local function base_G()
  local deck, by = {}, {}
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = card(v, s)
      deck[#deck + 1] = c
      by[v .. s] = c
    end
  end
  local g = {
    NEURO = { run_generation = 1 }, STATE = 1,
    STATES = { SELECTING_HAND = 1, SHOP = 2, BLIND_SELECT = 3, ROUND_EVAL = 7, MENU = 20 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = deck }, playing_cards = deck, FUNCS = {},
    GAME = { dollars = 20, chips = 0, hands = {}, probabilities = { normal = 1 },
      blind = { name = "Big Blind", chips = 600, debuff = {}, disabled = false,
                get_type = function() return "Big" end },
      current_round = { hands_left = 4, discards_left = 0 } },
  }
  _G.G = g
  return g, by
end

local function real_phi(sel)
  local counts, order = {}, {}
  for _, c in ipairs(sel or {}) do
    local id = c.base.id
    if not counts[id] then order[#order + 1] = id end
    counts[id] = (counts[id] or 0) + 1
  end
  local pairs_n, trips_n, best_id, best_n = 0, 0, nil, 0
  for _, id in ipairs(order) do
    local n = counts[id]
    if n >= 3 then trips_n = trips_n + 1 elseif n == 2 then pairs_n = pairs_n + 1 end
    if n > best_n then best_id, best_n = id, n end
  end
  local name = "High Card"
  if trips_n > 0 then name = "Three of a Kind"
  elseif pairs_n >= 2 then name = "Two Pair"
  elseif pairs_n == 1 then name = "Pair" end
  local scoring = {}
  if best_n > 1 then
    for _, c in ipairs(sel) do if c.base.id == best_id then scoring[#scoring + 1] = c end end
  else
    for _, c in ipairs(sel or {}) do scoring[#scoring + 1] = c end
  end
  local ph = { [name] = scoring }
  if trips_n > 0 or pairs_n >= 2 then ph["Pair"] = scoring end
  return name, {}, ph, scoring
end

local function confirm(sel, indices)
  local msg = HandHandlers.play_confirm_reject(sel, indices)
  return tostring(msg)
end

local function place(visible, hidden, pos)
  local out = {}
  for _, c in ipairs(visible) do out[#out + 1] = c end
  table.insert(out, pos, hidden)
  return out
end

local function select_from(hand, wanted)
  local want = {}
  for _, c in ipairs(wanted) do want[c] = true end
  local sel, idx = {}, {}
  for i, c in ipairs(hand) do
    if want[c] then sel[#sel + 1] = c; idx[#idx + 1] = i end
  end
  return sel, idx
end

local function idx_str(idx)
  return "[" .. table.concat(idx, ",") .. "]"
end

local function each_position(n, fn)
  local bad = nil
  for pos = 1, n do
    local ok, detail = fn(pos)
    if not ok and not bad then bad = "at hidden position " .. pos .. ": " .. tostring(detail) end
  end
  return bad == nil, bad or "all positions 1.." .. n
end

local function baron_board(hidden_rank, pos)
  local g, by = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  local hidden = by[hidden_rank .. "Clubs"]
  hidden.facing = "back"
  g.hand.cards = place({ by["KSpades"], by["KHearts"],
                         by["4Diamonds"], by["7Hearts"], by["9Clubs"] }, hidden, pos)
  g.FUNCS.get_poker_hand_info = real_phi
  local sel, idx = select_from(g.hand.cards, { by["4Diamonds"], by["7Hearts"], by["9Clubs"] })
  return confirm(sel, idx)
end

check("held face-down card: its rank is not derivable from the play confirmation", each_position(6,
  function(pos)
    local k, t = baron_board("K", pos), baron_board("2", pos)
    return k == t, "[" .. k .. "] vs [" .. t .. "]"
  end))
check("held face-down card: the confirmation still prices Baron off the public deck",
  each_position(6, function(pos)
    local k = baron_board("K", pos)
    return k:find("at most x3.38 Mult", 1, true) ~= nil
      and k:find("4 such cards in your deck, and you hold at most 3", 1, true) ~= nil, k
  end))

do
  local g, by = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  g.hand.cards = { by["KSpades"], by["KHearts"], by["KClubs"],
                   by["4Diamonds"], by["7Hearts"], by["9Clubs"] }
  g.FUNCS.get_poker_hand_info = real_phi
  local visible = confirm({ by["4Diamonds"], by["7Hearts"], by["9Clubs"] }, { 4, 5, 6 })
  check("all-visible hand: the confirmation states Baron's exact x3.38 with no hedge",
    visible:find("add x3.38 Mult to High Card (Baron x3.38 Mult)", 1, true) ~= nil, visible)
end

local function triboulet_board(hidden_rank, pos)
  local g, by = base_G()
  local trib = joker("j_triboulet", "Triboulet", { extra = 2 },
    "Played Kings and Queens each give X2 Mult when scored")
  trib.area = g.jokers
  g.jokers.cards = { trib }
  local hidden = by[hidden_rank .. "Clubs"]
  hidden.facing = "back"
  g.hand.cards = place({ by["KSpades"], by["QHearts"],
                         by["4Diamonds"], by["7Hearts"] }, hidden, pos)
  g.FUNCS.get_poker_hand_info = real_phi
  local sel, idx = select_from(g.hand.cards, { by["KSpades"], by["QHearts"], hidden })
  return confirm(sel, idx)
end

check("played face-down card: its rank is not derivable from the play confirmation",
  each_position(5, function(pos)
    local k, t = triboulet_board("K", pos), triboulet_board("2", pos)
    return k == t, "[" .. k .. "] vs [" .. t .. "]"
  end))
check("played face-down card: the confirmation still prices Triboulet off the public deck",
  each_position(5, function(pos)
    local k = triboulet_board("K", pos)
    return k:find("at most x", 1, true) ~= nil and k:find("in your deck", 1, true) ~= nil, k
  end))

do
  local g, by = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  g.hand.cards = { by["KSpades"], by["KHearts"], by["KClubs"],
                   by["4Diamonds"], by["7Hearts"], by["9Clubs"] }
  g.FUNCS.get_poker_hand_info = real_phi
  local q = Scoring.joker_summary().ledger.gated.xmult
  check("no selection: three held Kings are a ceiling, not a certainty",
    q.k == "at_most" and math.abs(q.n - 3.375) < 1e-9, q.k .. " " .. tostring(q.n))
  check("no selection: the ceiling names where its count came from",
    q.why[1] == "3 such cards in hand, and the ones you play stop counting as held",
    tostring(q.why[1]))
  check("no selection: the rendered clause carries the hedge",
    CtxHelpers.quantity_clause("xmult", q) == "at most x3.38 Mult",
    tostring(CtxHelpers.quantity_clause("xmult", q)))
end

local LEVELS = { ["High Card"] = { level = 1, chips = 5, mult = 1, visible = true },
                 ["Pair"] = { level = 1, chips = 10, mult = 2, visible = true },
                 ["Three of a Kind"] = { level = 1, chips = 30, mult = 3, visible = true } }

local function mark_board(hidden_rank, discards, pos)
  local g, by = base_G()
  for k, v in pairs(LEVELS) do g.GAME.hands[k] = v end
  g.GAME.current_round.discards_left = discards
  local hidden = by[hidden_rank .. "Clubs"]
  hidden.facing = "back"
  hidden.ability.wheel_flipped = true
  g.hand.cards = place({ by["KSpades"], by["4Diamonds"],
                         by["7Hearts"], by["9Clubs"] }, hidden, pos)
  g.FUNCS.get_poker_hand_info = real_phi
  local sel, idx = select_from(g.hand.cards, { by["KSpades"], hidden })
  return confirm(sel, idx), idx
end

check("weak pause: the hand a face-down card would complete is not derivable",
  each_position(5, function(pos)
    local k, t = mark_board("K", 2, pos), mark_board("2", 2, pos)
    return k == t, "[" .. k .. "] vs [" .. t .. "]"
  end))
check("weak pause: it masks the same four fields the engine masks",
  each_position(5, function(pos)
    local k, idx = mark_board("K", 2, pos)
    return k:find("Selection " .. idx_str(idx) .. " = ???? (lvl ?, ? chips x ? mult).", 1, true) ~= nil, k
  end))
check("weak pause: it says why the hand has no name", each_position(5, function(pos)
  local k = mark_board("K", 2, pos)
  return k:find("face down", 1, true) ~= nil, k
end))

check("general confirmation: the hidden card's hand type is not derivable",
  each_position(5, function(pos)
    local k, t = mark_board("K", 0, pos), mark_board("2", 0, pos)
    return k == t, "[" .. k .. "] vs [" .. t .. "]"
  end))
check("general confirmation: it names no hand type and says why", each_position(5, function(pos)
  local k = mark_board("K", 0, pos)
  return k:find("Committing this hand", 1, true) ~= nil
    and k:find("face down", 1, true) ~= nil, k
end))

do
  local g, by = base_G()
  for k, v in pairs(LEVELS) do g.GAME.hands[k] = v end
  g.GAME.current_round.discards_left = 2
  g.hand.cards = { by["KSpades"], by["4Diamonds"], by["KClubs"], by["7Hearts"], by["9Clubs"] }
  g.FUNCS.get_poker_hand_info = real_phi
  local visible = confirm({ by["KSpades"], by["KClubs"] }, { 1, 3 })
  check("all-visible selection: the confirmation still states the exact hand and its numbers",
    visible:find("Selection [1,3] = Pair (lvl 1, 10 chips x 2 mult).", 1, true) ~= nil, visible)
end

local function forced_board(hidden_rank, pos)
  local g, by = base_G()
  for k, v in pairs(LEVELS) do g.GAME.hands[k] = v end
  g.GAME.current_round.hands_left = 1
  g.GAME.current_round.discards_left = 0
  local hidden = by[hidden_rank .. "Clubs"]
  hidden.facing = "back"
  hidden.ability.wheel_flipped = true
  g.hand.cards = place({ by["KSpades"], by["KHearts"],
                         by["4Diamonds"], by["7Hearts"], by["9Clubs"] }, hidden, pos)
  g.FUNCS.get_poker_hand_info = real_phi
  local sel, idx = select_from(g.hand.cards, { by["4Diamonds"], by["7Hearts"], by["9Clubs"] })
  return confirm(sel, idx)
end

check("readiness scan: whether the confirmation appears does not depend on the hidden card",
  each_position(6, function(pos)
    local k, t = forced_board("K", pos), forced_board("2", pos)
    return k == t, "[" .. k .. "] vs [" .. t .. "]"
  end))

done()
