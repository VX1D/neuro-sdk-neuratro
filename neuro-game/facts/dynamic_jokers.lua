local CardUtil = require("facts.card_util")

local M = {}

local function num(v) return tonumber(v) or 0 end

local function id_of(card)
  local ok, v = pcall(function() return card:get_id() end)
  if ok and type(v) == "number" then return v end
  return nil
end

-- Card:get_id returns a large negative for a no-rank card (card.lua:1174-1179), which is what keeps
-- every M.MATCH predicate safe; Raised Fist is the one branch that walks base.id instead and needs
-- the enhancement tested directly (card.lua:3702).
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

local function faced(card)
  local ok, v = pcall(function() return card:is_face() end)
  if not ok then return nil end
  return v and true or false
end

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
    if not id or id ~= target.id then return id and false or nil end
    return suited(target.suit)(card)
  end,
  round_suit = function(card)
    local target = round_card("ancient_card")
    if not target then return nil end
    return suited(target.suit)(card)
  end,
}

local function g_match(id, text) return { kind = "card_match", match = id, text = text } end
local function g_state(id, text) return { kind = "board_state", id = id, text = text } end
local function g_odds(den, id, text) return { kind = "odds", num = 1, den = den, match = id, text = text } end
local function g_random(lo, hi) return { kind = "random", min = lo, max = hi, text = "a random roll" } end

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

local ROWS = {}
local function E(key, rows) ROWS[key] = rows end

E("j_photograph", {{ kind = "xmult", scope = "scoring_card", from = "extra", ref = 3472,
  gate = g_match("face", "the first played face card"), at_most_once = true, match = "face" }})
E("j_idol", {{ kind = "xmult", scope = "scoring_card", from = "extra", ref = 3506,
  gate = g_match("idol_card", "played cards of the round's rank and suit"), match = "idol_card" }})
E("j_scary_face", {{ kind = "chips", scope = "scoring_card", from = "extra", ref = 3515,
  gate = g_match("face", "played face cards"), match = "face" }})
E("j_smiley", {{ kind = "mult", scope = "scoring_card", from = "extra", ref = 3522,
  gate = g_match("face", "played face cards"), match = "face" }})
E("j_scholar", {
  { kind = "chips", scope = "scoring_card", from = "extra.chips", ref = 3538, gate = g_match("ace", "played Aces"), match = "ace" },
  { kind = "mult", scope = "scoring_card", from = "extra.mult", ref = 3538, gate = g_match("ace", "played Aces"), match = "ace" },
})
E("j_walkie_talkie", {
  { kind = "chips", scope = "scoring_card", from = "extra.chips", ref = 3546, gate = g_match("ten_or_four", "played 10s and 4s"), match = "ten_or_four" },
  { kind = "mult", scope = "scoring_card", from = "extra.mult", ref = 3546, gate = g_match("ten_or_four", "played 10s and 4s"), match = "ten_or_four" },
})
E("j_fibonacci", {{ kind = "mult", scope = "scoring_card", from = "extra", ref = 3564,
  gate = g_match("fibonacci", "played Aces, 2s, 3s, 5s and 8s"), match = "fibonacci" }})
E("j_even_steven", {{ kind = "mult", scope = "scoring_card", from = "extra", ref = 3575,
  gate = g_match("even", "played even ranks"), match = "even" }})
E("j_odd_todd", {{ kind = "chips", scope = "scoring_card", from = "extra", ref = 3585,
  gate = g_match("odd", "played odd ranks"), match = "odd" }})
E("j_onyx_agate", {{ kind = "mult", scope = "scoring_card", from = "extra", ref = 3612,
  gate = g_match("clubs", "played Clubs"), match = "clubs" }})
E("j_arrowhead", {{ kind = "chips", scope = "scoring_card", from = "extra", ref = 3619,
  gate = g_match("spades", "played Spades"), match = "spades" }})
E("j_bloodstone", {{ kind = "xmult", scope = "scoring_card", from = "extra.Xmult", ref = 3626,
  gate = g_odds(2, "hearts", "played Hearts, 1 in 2 of the time"), match = "hearts" }})
E("j_ancient", {{ kind = "xmult", scope = "scoring_card", from = "extra", ref = 3634,
  gate = g_match("round_suit", "played cards of the round's suit"), match = "round_suit" }})
E("j_triboulet", {{ kind = "xmult", scope = "scoring_card", from = "extra", ref = 3641,
  gate = g_match("king_or_queen", "played Kings and Queens"), match = "king_or_queen" }})

E("j_shoot_the_moon", {{ kind = "mult", scope = "held_card", from = function() return 13 end, ref = 3651,
  gate = g_match("queen", "Queens held in hand"), match = "queen" }})
E("j_baron", {{ kind = "xmult", scope = "held_card", from = "extra", ref = 3666,
  gate = g_match("king", "Kings held in hand"), match = "king" }})
local function raised_fist_ceiling(_, board)
  local hand, fixed = CardUtil.held_after_play(board and board.selection)
  if type(hand) ~= "table" or #hand == 0 then return nil end
  local seated = {}
  for i, c in ipairs(hand) do
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
  gate = g_state("lowest_held", "the lowest-ranked card still in your hand when the hand scores"),
  ceiling_from = raised_fist_ceiling,
  from = function(_, board)
    local hand = CardUtil.held_after_play(board and board.selection)
    if type(hand) ~= "table" or #hand == 0 then return nil end
    local best
    for _, c in ipairs(hand) do
      if not no_rank(c) then
        local nominal = c and c.base and tonumber(c.base.nominal)
        local id = c and c.base and tonumber(c.base.id)
        if not (nominal and id) then return nil end
        if not best or id <= best.id then best = { id = id, nominal = nominal, card = c } end
      end
    end
    if not best or best.card.debuff then return 0 end
    return best.nominal * 2
  end }})

E("j_baseball", {{ kind = "xmult", scope = "other_joker", from = "extra", ref = 3780,
  gate = g_state("uncommon_joker", "each other Uncommon joker"), match = "uncommon_joker" }})

E("j_loyalty_card", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4006,
  gate = g_state("loyalty", "every few hands") }})
E("j_half", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4046,
  gate = g_state("small_hand", "a played hand of 3 or fewer cards") }})
E("j_acrobat", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4062,
  gate = g_state("last_hand", "the final hand of the round") }})
E("j_mystic_summit", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4068,
  gate = g_state("no_discards", "having no discards left") }})
E("j_misprint", {{ kind = "mult", scope = "hand", from = "extra.max", ref = 4074,
  gate = g_random(0, 23), ceiling_from = "extra.max" }})
E("j_supernova", {{ kind = "mult", scope = "hand", ref = 4104, per_hand_type = true,
  gate = g_state("hand_type_table", "the hand type you play"),
  from = function() return nil end }})
E("j_flower_pot", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4180,
  gate = g_state("four_suits", "a scoring hand with all four suits") }})
E("j_seeing_double", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4213,
  gate = g_state("club_and_other", "a scoring Club plus a card of another suit") }})
E("j_drivers_license", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4291,
  gate = g_state("enhanced_16", "16 or more Enhanced cards in your deck") }})
E("j_blackboard", {{ kind = "xmult", scope = "hand", from = "extra", ref = 4299,
  gate = g_state("all_held_black", "every card you hold being a Spade or Club") }})
E("j_stencil", {{ kind = "xmult", scope = "hand", from = "x_mult", ref = 4314,
  gate = g_state("empty_slots", "an empty joker slot") }})
E("j_card_sharp", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4388,
  gate = g_state("type_repeat", "replaying a hand type you already played this round") }})

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
  from = function(c) return num(c.ability.extra) * math.max(0, dollars()) end }})
E("j_fortune_teller", {{ kind = "mult", scope = "hand", ref = 4364, from = function() return tarot_used() end }})
E("j_gros_michel", {{ kind = "mult", scope = "hand", from = "extra.mult", ref = 4370 }})
E("j_cavendish", {{ kind = "xmult", scope = "hand", from = "extra.Xmult", ref = 4376 }})
E("j_caino", {{ kind = "xmult", scope = "hand", ref = 4400,
  from = function(c) return tonumber(c.ability.caino_xmult) or 1 end }})
E("j_bootstraps", {{ kind = "mult", scope = "hand", ref = 4394, from = function(c)
  local steps = math.floor(dollars() / math.max(1, extra_field(c, "dollars")))
  return steps >= 1 and extra_field(c, "mult") * steps or 0
end }})

for key, ref in pairs({ j_ceremonial = 4110, j_swashbuckler = 4322, j_joker = 4328, j_trousers = 4334,
  j_ride_the_bus = 4340, j_flash = 4346, j_popcorn = 4352, j_green_joker = 4358, j_red_card = 4382 }) do
  E(key, {{ kind = "mult", scope = "hand", from = "mult", ref = ref }})
end

for _, key in ipairs({ "j_constellation", "j_vampire", "j_hologram", "j_obelisk", "j_lucky_cat",
  "j_campfire", "j_glass", "j_hit_the_road", "j_madness", "j_ramen", "j_throwback", "j_yorick" }) do
  E(key, {{ kind = "xmult", scope = "hand", from = "x_mult", ref = 4027, generic_ref = true }})
end

M.ROWS = ROWS

local FX_SHAPE = {
  mult   = { op = "+", unit = " Mult",  skip = 0 },
  chips  = { op = "+", unit = " Chips", skip = 0 },
  xmult  = { op = "x", unit = " Mult",  skip = 1 },
  xchips = { op = "x", unit = " Chips", skip = 1 },
}

local _extra_specs_memo = {}

function M.extra_specs(key)
  if key == nil then return {} end
  local rows = ROWS[key]
  local memo = _extra_specs_memo[key]
  -- ROWS is exported and mutable, so the memo is only valid while it still describes the same rows.
  if memo and memo.rows == rows then return memo.specs end
  local out = {}
  for _, row in ipairs(rows or {}) do
    local shape = FX_SHAPE[row.kind]
    if shape and type(row.from) == "string" and not row.ceiling_from then
      local nest, field = row.from:match("^(extra)%.([%w_]+)$")
      if nest then
        out[#out + 1] = { field = field, nest = nest, op = shape.op, unit = shape.unit,
          skip = shape.skip, gate = row.gate }
      end
    end
  end
  _extra_specs_memo[key] = { rows = rows, specs = out }
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
