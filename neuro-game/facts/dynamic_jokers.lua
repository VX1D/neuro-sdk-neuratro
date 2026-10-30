local CardUtil = require("facts.card_util")
local PublicCard = require("facts.public_card_identity")
local NumericEffects = require("facts.numeric_effects")

local M = {}

local function num(v) return tonumber(v) or 0 end

local id_of = NumericEffects.card_id

local no_rank = CardUtil.has_no_rank

local function suited(suit)
  return function(card)
    local ok, v = pcall(function() return card:is_suit(suit) end)
    if not ok then return nil end
    return v and true or false
  end
end

local function ranked(ids)
  return function(card)
    local id = id_of(card)
    if not id then return nil end
    return ids[id] == true
  end
end

local faced = NumericEffects.card_is_face

local function round_card(field)
  local r = G and G.GAME and G.GAME.current_round
  return r and r[field] or nil
end

M.MATCH = {
  face = faced,
  king = ranked({ [13] = true }),
  queen = ranked({ [12] = true }),
  king_or_queen = ranked({ [12] = true, [13] = true }),
  ace = ranked({ [14] = true }),
  ten_or_four = ranked({ [10] = true, [4] = true }),
  fibonacci = ranked({ [2] = true, [3] = true, [5] = true, [8] = true, [14] = true }),
  even = function(card)
    local id = id_of(card)
    if not id then return nil end
    return id >= 0 and id <= 10 and id % 2 == 0
  end,
  odd = function(card)
    local id = id_of(card)
    if not id then return nil end
    return id == 14 or (id >= 0 and id <= 10 and id % 2 == 1)
  end,
  clubs = suited("Clubs"),
  spades = suited("Spades"),
  hearts = suited("Hearts"),
  idol_card = function(card)
    local target = round_card("idol_card")
    if not target then return nil end
    local id = id_of(card)
    if not id then return nil end
    if id ~= target.id then return false end
    return suited(target.suit)(card)
  end,
  round_suit = function(card)
    local target = round_card("ancient_card")
    if not target then return nil end
    return suited(target.suit)(card)
  end,
}

local function g_match(id, text) return { kind = "card_match", match = id, text = text } end
local function g_state(id, text, active) return { kind = "board_state", id = id, text = text, active = active } end
local function g_select(id, text) return { kind = "board_state", id = id, text = text, unconditional = true } end

local function on_this_hand(test)
  return function(card, board)
    if not require("facts.game_facts").hand_can_score() then return nil end
    local live = test(card, board)
    if live == nil then return nil end
    return live and true or false
  end
end
local function g_odds(den_from, seed, id, text)
  return { kind = "odds", num = 1, den_from = den_from, seed = seed, match = id, text = text }
end
local function g_random(lo, hi) return { kind = "random", min = lo, max = hi, text = "a random roll" } end

function M.chance(card, base_num, base_den, seed)
  return SMODS.get_probability_vars(card, base_num, base_den, seed)
end

function M.odds(gate, card)
  if type(gate) ~= "table" or gate.kind ~= "odds" then return nil end
  local den = M.read_from(card, gate.den_from)
  if not den or den <= 0 then return nil end
  return M.chance(card, gate.num or 1, den, gate.seed)
end

local function dollars() return (G and G.GAME and num(G.GAME.dollars) + num(G.GAME.dollar_buffer)) or 0 end
local function starting_deck() return (G and G.GAME and num(G.GAME.starting_deck_size)) or 0 end
local function playing_cards() return (G and G.playing_cards and #G.playing_cards) or 0 end
local function deck_cards() return (G and G.deck and G.deck.cards and #G.deck.cards) or 0 end
local function discards_left() return (G and G.GAME and G.GAME.current_round and num(G.GAME.current_round.discards_left)) or 0 end
local function tarot_used() return (G and G.GAME and G.GAME.consumeable_usage_total and num(G.GAME.consumeable_usage_total.tarot)) or 0 end
local function extra_field(c, k) local e = c and c.ability and c.ability.extra; return (type(e) == "table" and num(e[k])) or 0 end
local function joker_count()
  local n = 0
  if G and G.jokers and G.jokers.cards then
    for _, j in ipairs(G.jokers.cards) do
      if j.ability and j.ability.set == "Joker" then n = n + 1 end
    end
  end
  return n
end

local function bull_figure(c, money) return num(c.ability.extra) * math.max(0, money) end
local function bootstraps_figure(c, money)
  local steps = math.floor(money / math.max(1, extra_field(c, "dollars")))
  return steps >= 1 and extra_field(c, "mult") * steps or 0
end

function M.read_from(card, from, board)
  if type(from) == "function" then return from(card, board) end
  local ability = card and card.ability
  if type(ability) ~= "table" then return nil end
  local outer, inner = tostring(from):match("^([%w_]+)%.([%w_]+)$")
  if outer then
    local nest = ability[outer]
    return (type(nest) == "table") and tonumber(nest[inner]) or nil
  end
  return tonumber(ability[from])
end

local function copy_source(card, kind)
  local cards = G and G.jokers and G.jokers.cards
  if type(cards) ~= "table" then return nil end
  local target
  if kind == "brainstorm" then
    target = cards[1]
  else
    for i = 1, #cards do if cards[i] == card then target = cards[i + 1] end end
  end
  if type(target) ~= "table" or target == card then return nil end
  return target
end

-- Mirrors the engine's compatible/incompatible label (Card:update), which reads blueprint_compat whatever the facing.
function M.copy_now(card, kind)
  if card.debuff then return { status = "debuffed_self" } end
  local target = copy_source(card, kind)
  if not target then return { status = "none" } end
  local center = target.config and target.config.center
  local compatible = type(center) == "table" and center.blueprint_compat and true or false
  if not PublicCard.is_public(target) then return { status = compatible and "hidden" or "hidden_incompatible" } end
  if not compatible then return { status = "incompatible", target = target } end
  if target.debuff then return { status = "debuffed", target = target } end
  return { status = "copying", target = target }
end

function M.copy_target(card, kind)
  local target = copy_source(card, kind)
  if not target or target.debuff then return nil, false end
  if not PublicCard.is_public(target) then return nil, true end
  local center = target.config and target.config.center
  if not (type(center) == "table" and center.blueprint_compat) then return nil, false end
  return target, false
end

function M.resolve_copy(card)
  local seen, cur = {}, card
  while type(cur) == "table" and CardUtil.copy_joker_kind(cur) do
    if seen[cur] then return nil end
    seen[cur] = true
    local target, concealed = M.copy_target(cur, CardUtil.copy_joker_kind(cur))
    if concealed then return nil, true end
    if not target then return nil end
    cur = target
  end
  return cur
end

local function running(key)
  local out, concealed = {}, false
  for i, j in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if not PublicCard.is_public(j) then
      concealed = true
    elseif not j.debuff then
      local target, hidden = M.resolve_copy(j)
      if hidden then concealed = true end
      if target and CardUtil.center_key(target) == key then out[#out + 1] = { card = j, source = target, slot = i } end
    end
  end
  return out, concealed
end

local function seal_of(card)
  local s = type(card) == "table" and card.seal
  if type(s) == "table" then s = s.key or s.name end
  return s
end

function M.card_reps(board, area, card, first)
  local reps = 1
  for _, e in ipairs(board and board.retriggers or {}) do
    if e.area == area and e.live ~= false and num(e.reps) > 0 then
      local m
      if e.first_only then
        m = (card == first)
      elseif e.match then
        local ok, v = pcall(e.match, card)
        if not ok then return nil end
        m = v
      else
        m = true
      end
      if m then reps = reps + e.reps end
    end
  end
  if seal_of(card) == "Red" then reps = reps + 1 end
  return reps
end

local function hook_live() return require("facts.boss.model").active_key() == "bl_hook" end

local function held_unsettled_why()
  if hook_live() then
    return "The Hook discards 2 held cards at random before they score"
  end
  return nil
end

function M.held_at_score(selection)
  local held, exact = CardUtil.held_after_play(selection)
  local chosen = type(selection) == "table" and #selection > 0
  local why = chosen and not exact and held_unsettled_why() or nil
  local r = G and G.GAME and G.GAME.current_round
  if type(held) ~= "table" or not chosen or #selection ~= 1 or not (r and num(r.hands_played) == 0) then
    return held, exact, why
  end
  local copies, concealed = running("j_dna")
  if concealed and not why then why = "a face-down joker could be DNA, which adds a copy of the card you play" end
  if #copies == 0 then return held, exact and not concealed, why end
  local out = {}
  for i, c in ipairs(held) do out[i] = c end
  for _ = 1, #copies do out[#out + 1] = setmetatable({}, { __index = selection[1] }) end
  return out, exact and not concealed, why
end

local ROWS = {}
local function E(key, rows) ROWS[key] = rows end

local function first_face(cards)
  for _, c in ipairs(cards) do
    if not PublicCard.is_public(c) then return false end
    if faced(c) then return c end
  end
  return nil
end

local function card_row(kind, scope, from, ref, match, text, extra)
  local row = { kind = kind, scope = scope, from = from, ref = ref, gate = g_match(match, text), match = match }
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end

E("j_photograph", { card_row("xmult", "scoring_card", "extra", 3472, "face", "the first played face card",
  { at_most_once = true, pick = first_face }) })
E("j_idol", { card_row("xmult", "scoring_card", "extra", 3506, "idol_card", "played cards of the round's rank and suit") })
E("j_scary_face", { card_row("chips", "scoring_card", "extra", 3515, "face", "played face cards") })
E("j_smiley", { card_row("mult", "scoring_card", "extra", 3522, "face", "played face cards") })
E("j_scholar", {
  card_row("chips", "scoring_card", "extra.chips", 3538, "ace", "played Aces"),
  card_row("mult", "scoring_card", "extra.mult", 3538, "ace", "played Aces"),
})
E("j_walkie_talkie", {
  card_row("chips", "scoring_card", "extra.chips", 3546, "ten_or_four", "played 10s and 4s"),
  card_row("mult", "scoring_card", "extra.mult", 3546, "ten_or_four", "played 10s and 4s"),
})
E("j_fibonacci", { card_row("mult", "scoring_card", "extra", 3564, "fibonacci", "played Aces, 2s, 3s, 5s and 8s") })
E("j_even_steven", { card_row("mult", "scoring_card", "extra", 3575, "even", "played even ranks") })
E("j_odd_todd", { card_row("chips", "scoring_card", "extra", 3585, "odd", "played odd ranks") })
E("j_onyx_agate", { card_row("mult", "scoring_card", "extra", 3612, "clubs", "played Clubs") })
E("j_arrowhead", { card_row("chips", "scoring_card", "extra", 3619, "spades", "played Spades") })
E("j_bloodstone", {{ kind = "xmult", scope = "scoring_card", from = "extra.Xmult", ref = 3626,
  gate = g_odds("extra.odds", "bloodstone", "hearts", "played Hearts, when its chance roll succeeds"), match = "hearts" }})
E("j_ancient", { card_row("xmult", "scoring_card", "extra", 3634, "round_suit", "played cards of the round's suit") })
E("j_triboulet", { card_row("xmult", "scoring_card", "extra", 3641, "king_or_queen", "played Kings and Queens") })

E("j_shoot_the_moon", { card_row("mult", "held_card", function() return 13 end, 3651, "queen", "Queens held in hand") })
E("j_baron", { card_row("xmult", "held_card", "extra", 3666, "king", "Kings held in hand") })
local function lowest_held(cards)
  local best, best_id
  for _, c in ipairs(cards) do
    if not PublicCard.is_public(c) then return false end
    if not no_rank(c) then
      local id = c.base and tonumber(c.base.id)
      if not id then return false end
      if not best_id or id <= best_id then best, best_id = c, id end
    end
  end
  return best
end

local function raised_fist_ceiling(_, board)
  local hand, fixed = M.held_at_score(board and board.selection)
  if type(hand) ~= "table" or #hand == 0 then return nil end
  local seated = {}
  for i, c in ipairs(hand) do
    if not PublicCard.is_public(c) then return nil end
    if not no_rank(c) then
      local nominal = c and c.base and tonumber(c.base.nominal)
      local id = c and c.base and tonumber(c.base.id)
      if not (nominal and id) then return nil end
      seated[#seated + 1] = { id = id, nominal = nominal, card = c, seat = i }
    end
  end
  if #seated == 0 then return 0 end
  table.sort(seated, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    return a.seat < b.seat
  end)
  local limit = fixed and 0 or (tonumber(CardUtil.highlight_limit()) or 0)
  local best = 0
  for k = 0, math.min(limit, #seated - 1) do
    local elected
    for i = k + 1, #seated do
      if seated[i].id == seated[k + 1].id then elected = seated[i] end
    end
    local v = elected.card.debuff and 0 or elected.nominal * 2
    if v > best then best = v end
  end
  return best
end

E("j_raised_fist", {{ kind = "mult", scope = "held_card", ref = 3699, at_most_once = true,
  gate = g_select("lowest_held", "the lowest-ranked card still in your hand when the hand scores"),
  ceiling_from = raised_fist_ceiling, pick = lowest_held,
  from = function(c, board)
    local hand, exact = M.held_at_score(board and board.selection)
    if type(hand) ~= "table" or #hand == 0 then return nil end
    if not exact then return raised_fist_ceiling(c, board) end
    local best = lowest_held(hand)
    if best == false then return nil end
    if not best or best.debuff then return 0 end
    local nominal = best.base and tonumber(best.base.nominal)
    return nominal and nominal * 2 or nil
  end }})

E("j_baseball", {{ kind = "xmult", scope = "other_joker", from = "extra", ref = 3780,
  gate = g_state("uncommon_joker", "each other Uncommon joker"), match = "uncommon_joker" }})

local function loyalty_pays(c)
  local every, created = extra_field(c, "every"), tonumber(c.ability.hands_played_at_create)
  local played = G and G.GAME and tonumber(G.GAME.hands_played)
  if not (every > 0 and created and played) then return nil end
  return (every - 1 - (played - created)) % (every + 1) == every
end

local function selection_size(board)
  local sel = board and board.selection
  return type(sel) == "table" and #sel > 0 and #sel or nil
end

E("j_loyalty_card", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4006,
  gate = g_state("loyalty", "every few hands", on_this_hand(loyalty_pays)) }})
E("j_half", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4046,
  gate = g_state("small_hand", "a played hand of 3 or fewer cards", on_this_hand(function(c, board)
    local n = selection_size(board)
    if not n then return nil end
    return n <= extra_field(c, "size")
  end)) }})
E("j_acrobat", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4062,
  gate = g_state("last_hand", "the final hand of the round",
    on_this_hand(function() return num(G.GAME.current_round.hands_left) <= 1 end)) }})
E("j_mystic_summit", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4068,
  gate = g_state("no_discards", "having no discards left",
    on_this_hand(function(c) return discards_left() == extra_field(c, "d_remaining") end)) }})
E("j_misprint", {{ kind = "mult", scope = "hand", from = "extra.max", ref = 4074,
  gate = g_random(0, 23), ceiling_from = "extra.max" }})
E("j_supernova", {{ kind = "mult", scope = "hand", ref = 4104, per_hand_type = true,
  gate = g_select("hand_type_table", "the hand type you play"),
  from = function() return nil end }})
E("j_flower_pot", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4180,
  gate = g_state("four_suits", "a scoring hand with all four suits") }})
E("j_seeing_double", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4213,
  gate = g_state("club_and_other", "a scoring Club plus a card of another suit") }})
E("j_drivers_license", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4291,
  gate = g_state("enhanced_16", "16 or more Enhanced cards in your deck",
    function(c) return num(c.ability.driver_tally) >= 16 end) }})
-- Blackboard checks suit alone for every held card, including debuffed cards.
E("j_blackboard", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4299,
  gate = g_state("all_held_black", "every card you hold being a Spade or Club", on_this_hand(function(_, board)
    if not selection_size(board) then return nil end
    local held, exact = M.held_at_score(board.selection)
    if type(held) ~= "table" or not exact then return nil end
    for _, c in ipairs(held) do
      if not PublicCard.is_public(c) then return nil end
      local ok, black = pcall(function() return c:is_suit("Clubs", nil, true) or c:is_suit("Spades", nil, true) end)
      if not ok then return nil end
      if not black then return false end
    end
    return true
  end)) }})
E("j_stencil", {{ kind = "xmult", scope = "hand", from = "x_mult", ref = 4314 }})
local hand_info
E("j_card_sharp", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4388,
  gate = g_state("type_repeat", "replaying a hand type you already played this round", on_this_hand(function(_, board)
    local text = hand_info(board)
    local h = text and G.GAME.hands and G.GAME.hands[text]
    if type(h) ~= "table" then return nil end
    return num(h.played_this_round) >= 1
  end)) }})

E("j_abstract", {{ kind = "mult", scope = "hand", ref = 4052,
  from = function(c) return num(c.ability.extra) * joker_count() end }})
E("j_banner", {{ kind = "chips", scope = "hand", ref = 4081,
  from = function(c) return num(c.ability.extra) * discards_left() end }})
E("j_stuntman", {{ kind = "chips", scope = "hand", from = "extra.chip_mod", ref = 4087 }})
E("j_wee", {{ kind = "chips", scope = "hand", from = "extra.chips", ref = 4221 }})
E("j_castle", {{ kind = "chips", scope = "hand", from = "extra.chips", ref = 4228 }})
E("j_blue_joker", {{ kind = "chips", scope = "hand", ref = 4235,
  from = function(c) return num(c.ability.extra) * deck_cards() end }})
E("j_erosion", {{ kind = "mult", scope = "hand", ref = 4242,
  from = function(c) return math.max(0, starting_deck() - playing_cards()) * num(c.ability.extra) end }})
E("j_square", {{ kind = "chips", scope = "hand", from = "extra.chips", ref = 4249 }})
E("j_runner", {{ kind = "chips", scope = "hand", from = "extra.chips", ref = 4256 }})
E("j_ice_cream", {{ kind = "chips", scope = "hand", from = "extra.chips", ref = 4263 }})
E("j_stone", {{ kind = "chips", scope = "hand", ref = 4270,
  from = function(c) return num(c.ability.extra) * num(c.ability.stone_tally) end }})
E("j_steel_joker", {{ kind = "xmult", scope = "hand", ref = 4277,
  from = function(c) local t = num(c.ability.steel_tally); return t > 0 and 1 + num(c.ability.extra) * t or 1 end }})
E("j_bull", {{ kind = "chips", scope = "hand", ref = 4284,
  from = function(c) return bull_figure(c, dollars()) end }})
E("j_fortune_teller", {{ kind = "mult", scope = "hand", ref = 4364, from = function() return tarot_used() end }})
E("j_gros_michel", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4370 }})
E("j_cavendish", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4376 }})
E("j_caino", {{ kind = "xmult", scope = "hand", ref = 4400,
  from = function(c) return tonumber(c.ability.caino_xmult) or 1 end }})
E("j_bootstraps", {{ kind = "mult", scope = "hand", ref = 4394, from = function(c)
  return bootstraps_figure(c, dollars())
end }})

for key, ref in pairs({ j_ceremonial = 4110, j_swashbuckler = 4322, j_joker = 4328, j_trousers = 4334,
  j_ride_the_bus = 4340, j_flash = 4346, j_popcorn = 4352, j_green_joker = 4358, j_red_card = 4382 }) do
  E(key, {{ kind = "mult", scope = "hand", from = "mult", ref = ref }})
end

for _, key in ipairs({ "j_constellation", "j_vampire", "j_hologram", "j_obelisk", "j_lucky_cat",
  "j_campfire", "j_glass", "j_hit_the_road", "j_madness", "j_ramen", "j_throwback", "j_yorick" }) do
  E(key, {{ kind = "xmult", scope = "hand", from = "x_mult", ref = 4027, generic_ref = true }})
end

-- The engine rescores these jokers between the play and `joker_main` passes.
local function fmt(n) return (tostring(tonumber(string.format("%.2f", n)))) end

local function selection_of(board)
  local sel = board and board.selection
  return type(sel) == "table" and #sel > 0 and sel or nil
end

local function exact_scoring(board)
  return board and board.scoring_exact and type(board.scoring) == "table" and board.scoring or nil
end

function hand_info(board)
  local sel = exact_scoring(board) and selection_of(board)
  local info = sel and G and G.FUNCS and G.FUNCS.get_poker_hand_info
  if type(info) ~= "function" then return nil end
  local ok, text, _, poker_hands = pcall(info, sel)
  if not ok or type(text) ~= "string" or type(poker_hands) ~= "table" then return nil end
  return text, poker_hands
end

local function contains(poker_hands, name)
  local set = poker_hands[name]
  return type(set) == "table" and next(set) ~= nil
end

local function played_retriggers(board)
  for _, e in ipairs(board and board.retriggers or {}) do
    if e.area == "played" and e.live ~= false and num(e.reps) > 0 then return true end
  end
  return false
end

local function count_scoring(board, pred)
  local scoring = exact_scoring(board)
  if not scoring then return nil end
  local n = 0
  for _, c in ipairs(scoring) do
    if not c.debuff then
      local m = pred(c)
      if m == nil then return nil end
      if m then n = n + 1 end
    end
  end
  return n
end

local owns = CardUtil.owns_live_joker

local function most_played_after(text)
  local hands = G and G.GAME and G.GAME.hands
  local mine = type(hands) == "table" and hands[text]
  if type(mine) ~= "table" then return nil end
  local after = num(mine.played) + 1
  for name, h in pairs(hands) do
    if name ~= text and type(h) == "table" and h.visible ~= false and num(h.played) >= after then
      return false
    end
  end
  return true
end
M.most_played_after = most_played_after

local function has_enhancement(card, key)
  local ok, v = pcall(SMODS.has_enhancement, card, key)
  return ok and v and true or false
end

-- The Hook discards up to two held cards before scoring and fires discard context for each.
local function hook_worlds(board)
  local sel = selection_of(board)
  if not (sel and hook_live()) then return nil end
  local held = CardUtil.held_after_play(sel)
  if type(held) ~= "table" then return nil end
  if #held <= 2 then return { held } end
  local worlds = {}
  for i = 1, #held - 1 do
    for j = i + 1, #held do worlds[#worlds + 1] = { held[i], held[j] } end
  end
  return worlds
end

local function hook_count_range()
  if not hook_live() then return nil end
  local n = (G and G.hand and G.hand.cards and #G.hand.cards) or 0
  local ok, lo_play, hi_play = pcall(function() return require("facts.boss.legality").play_size_bounds() end)
  if not ok then lo_play, hi_play = 1, CardUtil.highlight_limit() end
  lo_play, hi_play = tonumber(lo_play) or 1, tonumber(hi_play) or 5
  return math.min(2, math.max(0, n - hi_play)), math.min(2, math.max(0, n - lo_play))
end

local function over_worlds(board, figure)
  local worlds = hook_worlds(board)
  if not worlds then return nil end
  local lo, hi
  for _, d in ipairs(worlds) do
    local v = figure(d)
    if v == nil then return nil end
    lo = (lo == nil or v < lo) and v or lo
    hi = (hi == nil or v > hi) and v or hi
  end
  return lo, hi
end

local function live_count(cards, pred)
  local n = 0
  for _, c in ipairs(cards) do
    if not PublicCard.is_public(c) then return nil end
    if not c.debuff then
      local m = pred(c)
      if m == nil then return nil end
      if m then n = n + 1 end
    end
  end
  return n
end

local ON_DISCARD = {
  j_green_joker = function(c, d)
    local m = num(c.ability.mult)
    if #d > 0 and m ~= 0 then m = math.max(0, m - extra_field(c, "discard_sub")) end
    return m
  end,
  j_ramen = function(c, d)
    local x = num(c.ability.x_mult)
    for _ = 1, #d do
      if x - num(c.ability.extra) <= 1 then return 1 end
      x = x - num(c.ability.extra)
    end
    return x
  end,
  j_yorick = function(c, d)
    local x, left = num(c.ability.x_mult), num(c.ability.yorick_discards)
    for _ = 1, #d do
      if left <= 1 then left = extra_field(c, "discards"); x = x + extra_field(c, "xmult") else left = left - 1 end
    end
    return x
  end,
  j_castle = function(c, d)
    local target = round_card("castle_card")
    local n = target and live_count(d, suited(target.suit))
    if n == nil then return nil end
    return extra_field(c, "chips") + extra_field(c, "chip_mod") * n
  end,
  j_hit_the_road = function(c, d)
    local n = live_count(d, ranked({ [11] = true }))
    if n == nil then return nil end
    return num(c.ability.x_mult) + num(c.ability.extra) * n
  end,
}

local ON_DISCARD_CEILING = {
  j_castle = function(c, k)
    local target = round_card("castle_card")
    local n = target and live_count((G and G.hand and G.hand.cards) or {}, suited(target.suit))
    return n and extra_field(c, "chips") + extra_field(c, "chip_mod") * math.min(k, n) or nil
  end,
  j_hit_the_road = function(c, k)
    local n = live_count((G and G.hand and G.hand.cards) or {}, ranked({ [11] = true }))
    return n and num(c.ability.x_mult) + num(c.ability.extra) * math.min(k, n) or nil
  end,
}

local HOOK_TEXT = {
  j_green_joker = "The Hook's discard before scoring takes it down 1 Mult first (not below 0)",
  j_ramen = "The Hook's discard before scoring takes x0.01 Mult off it per card",
  j_yorick = "The Hook's discarded cards count toward its next x1 Mult",
  j_castle = "it gains Chips for each card of its suit The Hook discards before scoring",
  j_hit_the_road = "it gains xMult for each Jack The Hook discards before scoring",
}

local function hook_figure(key, c, board)
  local fn = ON_DISCARD[key]
  if not fn then return nil end
  local lo, hi = over_worlds(board, function(d) return fn(c, d) end)
  if lo ~= nil then return lo, hi end
  if selection_of(board) then return nil end
  local k_lo, k_hi = hook_count_range()
  if not k_lo then return nil end
  if k_lo == k_hi and not ON_DISCARD_CEILING[key] then
    local stub = {}
    for i = 1, k_lo do stub[i] = false end
    local v = fn(c, stub)
    return v, v
  end
  local ceil = ON_DISCARD_CEILING[key]
  if ceil then return nil, ceil(c, k_hi) end
  local best
  for k = k_lo, k_hi do
    local stub = {}
    for i = 1, k do stub[i] = false end
    local v = fn(c, stub)
    best = (best == nil or v > best) and v or best
  end
  return nil, best
end

local function hook_exact(key, c, board)
  local lo, hi = hook_figure(key, c, board)
  return (lo ~= nil and lo == hi) and lo or nil
end

local function hook_rescore(key)
  return {
    active = function() return hook_live() end,
    text = function() return HOOK_TEXT[key] end,
    value = function(c, board) return hook_exact(key, c, board) end,
    ceiling = function(c, board) return select(2, hook_figure(key, c, board)) end,
  }
end

-- Growth-only jokers pay their stored value every hand, so only growth is a rescored row.
local function grows(kind, stored, spec)
  local function figure(c, gain)
    if gain == nil then return nil end
    if kind ~= "xmult" then return gain end
    local s = stored(c)
    return s > 0 and (s + gain) / s or nil
  end
  return {
    grows = kind,
    unknown = spec.unknown,
    active = spec.active,
    text = function(c)
      local t = spec.text(c)
      if kind ~= "xmult" then return t end
      return t .. " (this factor is on top of its current x" .. fmt(stored(c)) .. " Mult)"
    end,
    value = function(c, board) return figure(c, spec.gain(c, board)) end,
    ceiling = spec.ceiling and function(c, board) return figure(c, spec.ceiling(c, board)) end or nil,
  }
end

local function stored_x(c) return num(c.ability.x_mult) end
local function stored_chips(c) return extra_field(c, "chips") end

local function hook_growth(key, kind, stored)
  return grows(kind, stored, {
    unknown = HOOK_TEXT[key],
    active = function() return hook_live() end,
    text = function() return HOOK_TEXT[key] end,
    gain = function(c, board)
      local v = hook_exact(key, c, board)
      return v and v - stored(c) or nil
    end,
    ceiling = function(c, board)
      local hi = select(2, hook_figure(key, c, board))
      return hi and hi - stored(c) or nil
    end,
  })
end

-- Bull and Bootstraps read `dollar_buffer` in `joker_main`, after card and other money effects.
local function earned_this_hand(board)
  local scoring = exact_scoring(board)
  if not scoring or board.hidden_jokers then return nil, nil end
  local by = {}
  for _, key in ipairs({ "j_rough_gem", "j_ticket", "j_business", "j_reserved_parking", "j_todo_list", "j_matador",
    "j_mail", "j_trading" }) do
    local list, concealed = running(key)
    if concealed then return nil, nil end
    by[key] = list
  end
  local reshaped = owns("j_midas_mask") ~= false or owns("j_vampire") ~= false
  local sure, maybe = 0, 0
  local function pay(amount, card, base_den, seed)
    if base_den then
      local n, d = M.chance(card, 1, base_den, seed)
      if n < d then maybe = maybe + amount; return end
    end
    sure = sure + amount
  end
  local first = scoring[1]
  for _, c in ipairs(scoring) do
    if not c.debuff then
      local reps = M.card_reps(board, "played", c, first)
      if not reps then return nil, nil end
      for _ = 1, reps do
        local a = type(c.ability) == "table" and c.ability or {}
        if seal_of(c) == "Gold" and not a.extra_enhancement then pay(CardUtil.gold_seal_dollars()) end
        if num(a.p_dollars) ~= 0 then
          if a.effect == "Lucky Card" then pay(num(a.p_dollars), c, 15, "lucky_money") else pay(num(a.p_dollars)) end
        end
        if not a.extra_enhancement then pay(num(a.perma_p_dollars)) end
        for _, j in ipairs(by.j_rough_gem) do
          if suited("Diamonds")(c) then pay(num(j.source.ability.extra)) end
        end
        for _, j in ipairs(by.j_ticket) do
          if has_enhancement(c, "m_gold") then pay(num(j.source.ability.extra)) end
        end
        for _, j in ipairs(by.j_business) do
          if faced(c) then pay(2, j.source, num(j.source.ability.extra), "business") end
        end
      end
    end
  end
  for _, j in ipairs(by.j_todo_list) do
    local text = hand_info(board)
    if text == nil then return nil, nil end
    if text == j.source.ability.to_do_poker_hand then pay(extra_field(j.source, "dollars")) end
  end
  if #by.j_reserved_parking > 0 then
    local held, exact = M.held_at_score(board.selection)
    if type(held) ~= "table" or not exact then return nil, nil end
    for _, c in ipairs(held) do
      if not PublicCard.is_public(c) then return nil, nil end
      if not c.debuff and faced(c) then
        local reps = M.card_reps(board, "held", c)
        if not reps then return nil, nil end
        for _ = 1, reps do
          for _, j in ipairs(by.j_reserved_parking) do
            pay(extra_field(j.source, "dollars"), j.source, extra_field(j.source, "odds"), "parking")
          end
        end
      end
    end
  end
  for _, j in ipairs(by.j_matador) do maybe = maybe + num(j.source.ability.extra) end
  if hook_live() and (#by.j_mail > 0 or #by.j_trading > 0) then
    local target = round_card("mail_card")
    local used = num(G.GAME.current_round and G.GAME.current_round.discards_used)
    local lo, hi = over_worlds(board, function(d)
      local got = 0
      if #by.j_mail > 0 then
        local n = target and live_count(d, ranked({ [num(target.id)] = true }))
        if n == nil then return nil end
        for _, j in ipairs(by.j_mail) do got = got + num(j.source.ability.extra) * n end
      end
      for _, j in ipairs(by.j_trading) do
        if j.card == j.source and #d == 1 and used <= 0 then got = got + num(j.source.ability.extra) end
      end
      return got
    end)
    if lo == nil then return nil, nil end
    sure, maybe = sure + lo, maybe + (hi - lo)
  end
  if reshaped then return nil, nil end
  if maybe > 0 then return nil, sure + maybe end
  return sure, sure
end

local function money_rescore(figure, text)
  return {
    active = function(_, board)
      local exact, ceiling = earned_this_hand(board)
      return exact_scoring(board) ~= nil and not (exact == 0 and ceiling == 0)
    end,
    text = function() return text end,
    value = function(c, board)
      local exact = earned_this_hand(board)
      return exact and figure(c, dollars() + exact) or nil
    end,
    ceiling = function(c, board)
      local _, ceiling = earned_this_hand(board)
      return ceiling and figure(c, dollars() + ceiling) or nil
    end,
  }
end

local function conditional_growth(kind, value, unit, condition, holds)
  return grows(kind, nil, {
    text = function(c) return "it gains +" .. fmt(value(c)) .. " " .. unit .. " before it pays if " .. condition end,
    gain = function(c, board)
      local hit = holds(board)
      if hit == nil then return nil end
      return hit and value(c) or 0
    end,
    ceiling = function(c) return value(c) end,
  })
end

local function chip_mod(c) return extra_field(c, "chip_mod") end

local function green_gain(c) return "it gains +" .. fmt(extra_field(c, "hand_add")) .. " Mult before every hand pays" end

local RESCORE = {
  j_green_joker = {
    text = function(c)
      if not hook_live() then return green_gain(c) end
      return HOOK_TEXT.j_green_joker .. ", then " .. green_gain(c)
    end,
    value = function(c, board)
      if not hook_live() then return num(c.ability.mult) + extra_field(c, "hand_add") end
      local v = hook_exact("j_green_joker", c, board)
      return v and v + extra_field(c, "hand_add") or nil
    end,
    ceiling = function(c, board)
      local _, hi = hook_figure("j_green_joker", c, board)
      return hi and hi + extra_field(c, "hand_add") or nil
    end,
  },
  j_ramen = hook_rescore("j_ramen"),
  j_yorick = hook_growth("j_yorick", "xmult", stored_x),
  j_castle = hook_growth("j_castle", "chips", stored_chips),
  j_hit_the_road = hook_growth("j_hit_the_road", "xmult", stored_x),
  j_ride_the_bus = {
    text = function(c)
      return "before it pays, it resets to 0 if a face card scores, otherwise it gains +"
        .. fmt(num(c.ability.extra)) .. " Mult"
    end,
    value = function(c, board)
      local faces = count_scoring(board, M.MATCH.face)
      if faces == nil then return nil end
      return faces > 0 and 0 or num(c.ability.mult) + num(c.ability.extra)
    end,
    ceiling = function(c) return num(c.ability.mult) + num(c.ability.extra) end,
  },
  j_obelisk = {
    text = function(c)
      return "before it pays, it resets to x1 Mult if this hand type has now been played more times"
        .. " than every other hand type (a tie keeps it growing), otherwise it gains x"
        .. fmt(num(c.ability.extra)) .. " Mult"
    end,
    value = function(c, board)
      local text = hand_info(board)
      local reset = text and most_played_after(text)
      if reset == nil then return nil end
      return reset and 1 or num(c.ability.x_mult) + num(c.ability.extra)
    end,
    ceiling = function(c) return num(c.ability.x_mult) + num(c.ability.extra) end,
  },
  j_trousers = conditional_growth("mult", function(c) return num(c.ability.extra) end, "Mult",
    "the hand contains a Two Pair", function(board)
      local _, hands = hand_info(board)
      if not hands then return nil end
      return contains(hands, "Two Pair") or contains(hands, "Full House")
    end),
  j_square = conditional_growth("chips", chip_mod, "Chips", "exactly 4 cards are played", function(board)
    local sel = selection_of(board)
    if not sel then return nil end
    return #sel == 4
  end),
  j_runner = conditional_growth("chips", chip_mod, "Chips", "the hand contains a Straight", function(board)
    local _, hands = hand_info(board)
    if not hands then return nil end
    return contains(hands, "Straight")
  end),
  j_vampire = grows("xmult", stored_x, {
    text = function(c)
      return "before it pays, it gains x" .. fmt(num(c.ability.extra))
        .. " Mult for each scoring Enhanced card and strips their Enhancements"
    end,
    gain = function(c, board)
      if owns("j_midas_mask") ~= false then return nil end
      local n = count_scoring(board, function(card) return CardUtil.enhancement_key(card) ~= nil end)
      if n == nil then return nil end
      return num(c.ability.extra) * n
    end,
    ceiling = function(c) return num(c.ability.extra) * num(CardUtil.highlight_limit()) end,
  }),
  j_wee = grows("chips", nil, {
    unknown = "how much it grows before it pays (each scoring 2 adds to it); its current Chips count as always on",
    text = function(c)
      return "it gains +" .. fmt(extra_field(c, "chip_mod")) .. " Chips for each scoring 2 before it pays"
    end,
    -- Scaling occurs on every scoring pass of a 2, including retriggers and Red Seals.
    gain = function(c, board)
      local scoring = exact_scoring(board)
      if not scoring then return nil end
      local n = 0
      for _, card in ipairs(scoring) do
        if not card.debuff then
          local id = id_of(card)
          if id == nil then return nil end
          if id == 2 then
            local reps = M.card_reps(board, "played", card, scoring[1])
            if not reps then return nil end
            n = n + reps
          end
        end
      end
      return extra_field(c, "chip_mod") * n
    end,
  }),
  j_lucky_cat = grows("xmult", stored_x, {
    unknown = "how much it grows before it pays (each scoring Lucky card that triggers adds to it); its current xMult counts as always on",
    text = function(c)
      return "it gains x" .. fmt(num(c.ability.extra)) .. " Mult each time a scoring Lucky card triggers, before it pays"
    end,
    gain = function(_, board)
      local n = count_scoring(board, function(card) return CardUtil.enhancement_key(card) == "m_lucky" end)
      if n == 0 then return 0 end
      return nil
    end,
    ceiling = function(c, board)
      if played_retriggers(board) then return nil end
      local n = count_scoring(board, function(card) return CardUtil.enhancement_key(card) == "m_lucky" end)
      return n and num(c.ability.extra) * n or nil
    end,
  }),
  j_hologram = grows("xmult", stored_x, {
    unknown = "how much it grows before it pays (DNA copies a single card played as the round's first hand, and each added card grows it); its current xMult counts as always on",
    active = function()
      local r = G and G.GAME and G.GAME.current_round
      return owns("j_dna") == true and num(r and r.hands_played) == 0
    end,
    text = function(c)
      return "DNA copies a single card played as the round's first hand, and each added card gives it x"
        .. fmt(num(c.ability.extra)) .. " Mult before it pays"
    end,
    gain = function(_, board)
      local sel = selection_of(board)
      if sel and #sel ~= 1 then return 0 end
      return nil
    end,
  }),
}
if _G.NEURO_TEST then
  M.RESCORE = RESCORE
end

local function growth_state(spec, c, board)
  if spec.active and not spec.active(c, board) then return nil end
  if spec.value(c, board) ~= nil then return nil end
  return (spec.ceiling and spec.ceiling(c, board) ~= nil) and "ceiling" or "unread"
end

local function growth_unread(spec, c, board) return growth_state(spec, c, board) == "unread" end

function M.growth_state(card, kind)
  local src = M.resolve_copy(card)
  local center = type(src) == "table" and src.config and src.config.center
  local spec = center and RESCORE[center.key]
  if not (spec and spec.grows == kind) then return nil end
  return growth_state(spec, src)
end

local INERT = { chips = 0, mult = 0, xmult = 1 }
for key, spec in pairs(RESCORE) do
  local rows = ROWS[key] or {}
  if spec.grows then
    local stored = rows[1]
    local base = INERT[spec.grows]
    -- An unread growth value is nil, so refuse the action rather than silently dropping it.
    local function from(c, board)
      if growth_unread(spec, c, board) then return nil end
      return base
    end
    rows[#rows + 1] = { kind = spec.grows, scope = "hand", ref = stored.ref, generic_ref = stored.generic_ref,
      from = from, rescore = spec,
      gate = spec.unknown and { kind = "board_state", id = "growth", text = spec.unknown } or nil }
  else
    for _, row in ipairs(rows) do row.rescore = spec end
  end
end
-- Read this value in `joker_main` after the play has added money.
ROWS.j_bull[1].rescore = money_rescore(bull_figure, "it counts the money this hand's cards earn before it pays")
ROWS.j_bootstraps[1].rescore = money_rescore(bootstraps_figure,
  "it counts the money this hand's cards earn before it pays")

M.ROWS = ROWS

local FX_SHAPE = {
  mult   = { op = "+", unit = " Mult",  skip = 0 },
  chips  = { op = "+", unit = " Chips", skip = 0 },
  xmult  = { op = "x", unit = " Mult",  skip = 1 },
  xchips = { op = "x", unit = " Chips", skip = 1 },
}

function M.extra_specs(key)
  if key == nil then return {} end
  local out = {}
  for _, row in ipairs(ROWS[key] or {}) do
    local shape = FX_SHAPE[row.kind]
    if shape and type(row.from) == "string" and not row.ceiling_from then
      local nest, field = row.from:match("^(extra)%.([%w_]+)$")
      if nest then
        out[#out + 1] = { field = field, nest = nest, op = shape.op, unit = shape.unit,
          skip = shape.skip, gate = row.gate }
      end
    end
  end
  return out
end

function M.declares(key, kind)
  for _, row in ipairs(ROWS[key] or {}) do
    if row.kind == kind then return true end
  end
  return false
end

function M.per_hand_type(key)
  if key ~= "j_supernova" then return nil end
  local out, order = {}, {}
  if G and G.GAME and type(G.GAME.hands) == "table" then
    for name, h in pairs(G.GAME.hands) do
      if type(h) == "table" and h.visible ~= false then
        out[name] = num(h.played) + 1
        order[#order + 1] = { name = name, rank = tonumber(h.order) or math.huge }
      end
    end
  end
  table.sort(order, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.name < b.name
  end)
  local names = {}
  for i = 1, #order do names[i] = order[i].name end
  return { kind = "mult", per_type = out, order = names }
end

return M
