local M = {}

local read = require("tests.helpers").read_file

local function block(src, header)
  local lines = {}
  for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  for i = 1, #lines do
    if lines[i]:find(header, 1, true) == 1 then
      for j = i + 1, #lines do
        if lines[j] == "end" then return table.concat(lines, "\n", i, j) end
      end
    end
  end
  error("engine block not found: " .. header)
end

local VALUE = { [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9",
  [10] = "10", [11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace" }
M.VALUE = VALUE

function M.load(dump)
  local smods = dump .. "/../../smods/src/"
  local card_src, misc, overrides, utils = read(dump .. "/card.lua"), read(dump .. "/functions/misc_functions.lua"),
    read(smods .. "overrides.lua"), read(smods .. "utils.lua")
  if not (card_src and misc and overrides and utils) then return nil end
  _G.Moveable = { extend = function() local c = {}; c.__index = c; return c end }
  assert(loadstring(card_src, "@card.lua"))()
  for _, h in ipairs({ "function get_flush(", "function get_X_same(", "function get_highest(" }) do
    assert(loadstring(block(misc, h), "@misc_functions.lua"))()
  end
  require("tests.engine_cards").install_smods({})
  SMODS.optional_features, SMODS.Stickers, SMODS.Rarities = {}, {}, {}
  SMODS.Suit = { obj_buffer = { "Spades", "Hearts", "Clubs", "Diamonds" } }
  SMODS.Ranks, SMODS.Rank = {}, { obj_buffer = {}, max_id = { value = 14 } }
  local keys = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }
  for i, k in ipairs(keys) do
    local id = i + 1
    SMODS.Ranks[k] = { key = k, id = id, next = { keys[i + 1] or "2" }, straight_edge = (k == "Ace"),
      face = (id >= 11 and id <= 13), nominal = (id == 14 and 11) or math.min(id, 10) }
    SMODS.Rank.obj_buffer[i] = k
  end
  function SMODS.get_card_areas() return { G.jokers } end
  function SMODS.find_card(key, count_debuffed)
    local r = {}
    for _, v in ipairs((G.jokers and G.jokers.cards) or {}) do
      if v.config.center.key == key and (count_debuffed or not v.debuff) then r[#r + 1] = v end
    end
    return r
  end
  local NAME2KEY = { ["Smeared Joker"] = "j_smeared", Shortcut = "j_shortcut", Pareidolia = "j_pareidolia",
    Splash = "j_splash", ["Four Fingers"] = "j_four_fingers" }
  _G.find_joker = function(name) return SMODS.find_card(NAME2KEY[name] or name) end
  function SMODS.four_fingers() return next(SMODS.find_card("j_four_fingers")) and 4 or 5 end
  function SMODS.shortcut() return next(SMODS.find_card("j_shortcut")) and true or false end
  function SMODS.wrap_around_straight() return false end
  function SMODS.get_enhancements(card)
    return card.ability.set == "Enhanced" and { [card.config.center.key] = true } or {}
  end
  function SMODS.has_enhancement(card, key) return SMODS.get_enhancements(card)[key] == true end
  function SMODS.has_no_suit(card) return SMODS.has_enhancement(card, "m_stone") end
  function SMODS.has_any_suit(card) return SMODS.has_enhancement(card, "m_wild") end
  function SMODS.has_no_rank(card) return SMODS.has_enhancement(card, "m_stone") end
  function SMODS.always_scores(card) return SMODS.has_enhancement(card, "m_stone") end
  function SMODS.never_scores() return nil end
  function SMODS.is_eternal() return false end
  function SMODS.smeared_check() return false end
  function SMODS.merge_lists(...)
    local ret, seen = {}, {}
    for _, lists in ipairs({ ... }) do
      for _, li in ipairs(lists) do
        for _, v in ipairs(li) do if not seen[v] then ret[#ret + 1] = v; seen[v] = true end end
      end
    end
    return ret
  end
  function SMODS.calculate_context() return {} end
  function SMODS.get_probability_vars(_, num, den)
    return num * (G.GAME.probabilities.normal or 1), den
  end
  function SMODS.pseudorandom_probability(obj, seed, num, den)
    local n, d = SMODS.get_probability_vars(obj, num, den)
    return pseudorandom(seed) < n / d
  end
  function SMODS.scale_card(card, args)
    local ref = args.ref_table or card.ability.extra
    local scalar = (args.scalar_table or ref)[args.scalar_value] or 1
    if args.operation == "X" then ref[args.ref_value] = ref[args.ref_value] * scalar
    elseif args.operation == "-" then ref[args.ref_value] = ref[args.ref_value] - scalar
    else ref[args.ref_value] = ref[args.ref_value] + scalar end
  end
  function Card:can_calculate(ignore) return not self.debuff or ignore end
  assert(loadstring(block(utils, "function SMODS.blueprint_effect("), "@smods_utils"))()
  assert(loadstring(block(utils, "function SMODS.multiplicative_stacking("), "@smods_utils"))()
  assert(loadstring(block(utils, "function Card:is_rarity("), "@smods_utils"))()
  SMODS.PokerHandParts = {
    _highest = { func = function(h) return get_highest(h) end },
    _straight = { func = function(h) return get_straight(h, SMODS.four_fingers(), SMODS.shortcut(), false) end },
    _flush = { func = function(h) return get_flush(h) end },
    _all_pairs = { func = function(h)
      local two = get_X_same(2, h, true)
      if not next(two) then return {} end
      return { SMODS.merge_lists(two) }
    end },
  }
  SMODS.PokerHandPart = { obj_buffer = { "_highest", "_straight", "_flush", "_all_pairs", "_2", "_3", "_4", "_5" } }
  for i = 2, 5 do SMODS.PokerHandParts["_" .. i] = { func = function(h) return get_X_same(i, h, true) end } end
  local ev = {
    ["Flush Five"] = function(p) if not next(p._5) or not next(p._flush) then return {} end return { SMODS.merge_lists(p._5, p._flush) } end,
    ["Flush House"] = function(p) if #p._3 < 1 or #p._2 < 2 or not next(p._flush) then return {} end return { SMODS.merge_lists(p._all_pairs, p._flush) } end,
    ["Five of a Kind"] = function(p) return p._5 end,
    ["Straight Flush"] = function(p) if not next(p._straight) or not next(p._flush) then return end return { SMODS.merge_lists(p._straight, p._flush) } end,
    ["Four of a Kind"] = function(p) return p._4 end,
    ["Full House"] = function(p) if #p._3 < 1 or #p._2 < 2 then return {} end return p._all_pairs end,
    ["Flush"] = function(p) return p._flush end,
    ["Straight"] = function(p) return p._straight end,
    ["Three of a Kind"] = function(p) return p._3 end,
    ["Two Pair"] = function(p) if #p._2 < 2 then return {} end return p._all_pairs end,
    ["Pair"] = function(p) return p._2 end,
    ["High Card"] = function(p) return p._highest end,
  }
  SMODS.PokerHands = {}
  for k, f in pairs(ev) do SMODS.PokerHands[k] = { key = k, evaluate = f } end
  _G.G = _G.G or {}
  G.FUNCS = G.FUNCS or {}
  G.C = setmetatable({}, { __index = function() return {} end })
  G.E_MANAGER = { add_event = function() end }
  G.handlist = { "Flush Five", "Flush House", "Five of a Kind", "Straight Flush", "Four of a Kind", "Full House",
    "Flush", "Straight", "Three of a Kind", "Two Pair", "Pair", "High Card" }
  G.P_CENTERS = {}
  G.P_SEALS = {}
  for _, h in ipairs({ "function get_straight(", "function evaluate_poker_hand(", "function G.FUNCS.get_poker_hand_info(" }) do
    assert(loadstring(block(overrides, h), "@smods_overrides"))()
  end
  M.get_poker_hand_info = G.FUNCS.get_poker_hand_info
  _G.localize = function(x) return type(x) == "string" and x or "" end
  _G.Event = function(t) return t end
  _G.card_eval_status_text = function() end
  _G.juice_card_until = function() end
  _G.play_sound = function() end
  _G.delay = function() end
  _G.pseudoseed = function(s) return s end
  _G.pseudorandom = function() return 0.5 end
  _G.ease_dollars = function() end
  _G.copy_card = function(other)
    local c = M.card(other.base.id, other.base.suit, nil, { seal = other.seal })
    c.states = {}
    return c
  end
  return true
end

local uid = 0

function M.card(id, suit, enhancement, opts)
  opts = opts or {}
  uid = uid + 1
  local enh = enhancement or "c_base"
  local set = enh == "c_base" and "Default" or "Enhanced"
  local c = setmetatable({}, Card)
  c.unique_val, c.sort_id = uid, 5000 + uid
  c.base = { id = id, value = VALUE[id], suit = suit, nominal = SMODS.Ranks[VALUE[id]].nominal,
    face_nominal = ({ [11] = 0.1, [12] = 0.2, [13] = 0.3 })[id] or 0,
    suit_nominal = ({ Spades = 0.04, Hearts = 0.03, Clubs = 0.02, Diamonds = 0.01 })[suit] }
  c.config = { center = { key = enh, set = set } }
  c.ability = { set = set, name = enh, effect = enh == "m_gold" and "Gold Card" or "", bonus = 0, mult = 0,
    x_mult = 1, h_mult = 0, h_x_mult = 0, p_dollars = 0, perma_bonus = 0, perma_p_dollars = 0 }
  c.facing = "front"
  c.debuff = opts.debuff
  c.seal = opts.seal
  c.states = {}
  function c.add_to_deck() end
  return c
end

function M.joker(fixture_card)
  return setmetatable(fixture_card, Card)
end

local ADD = { "chips", "h_chips", "chip_mod" }
local MUL_ADD = { "mult", "h_mult", "mult_mod" }
local X = { "x_mult", "Xmult", "xmult", "x_mult_mod", "Xmult_mod" }

local function apply(state, ret, from_joker)
  if type(ret) ~= "table" then return false end
  local did = false
  for _, k in ipairs(ADD) do
    if ret[k] then
      state.chips = state.chips + ret[k]; did = true
      if from_joker then state.joker_chips = state.joker_chips + ret[k] end
    end
  end
  for _, k in ipairs(MUL_ADD) do if ret[k] then state.mult = state.mult + ret[k]; did = true end end
  for _, k in ipairs(X) do if ret[k] then state.mult = state.mult * ret[k]; did = true end end
  if ret.p_dollars or ret.dollars then did = true end
  return did
end

local function context(base, extra)
  local c = {}
  for k, v in pairs(base) do c[k] = v end
  for k, v in pairs(extra) do c[k] = v end
  return c
end

local function live_jokers()
  local out = {}
  for _, j in ipairs(G.jokers.cards) do if not j.debuff then out[#out + 1] = j end end
  return out
end

-- Repetitions are collected only after the first pass calculates an effect.
local function score_card(state, card, area, base)
  -- eval_card returns {} for debuffed cards and jokers evaluating them.
  if card.debuff then return end
  local reps, j = 1, 1
  while j <= reps do
    local calculated = false
    local own = {}
    if area == G.play then
      local chips = card:get_chip_bonus()
      if chips ~= 0 then own.chips = chips end
      local mult = card:get_chip_mult()
      if mult ~= 0 then own.mult = mult end
      local x = card:get_chip_x_mult()
      if x > 0 and x ~= 1 then own.x_mult = x end
      card:get_p_dollars()
      calculated = true
    else
      local hm = card:get_chip_h_mult()
      if hm ~= 0 then own.h_mult = hm end
      local hx = card:get_chip_h_x_mult()
      if hx > 0 and hx ~= 1 then own.x_mult = hx end
    end
    if apply(state, own, false) then calculated = true end
    -- Edition scoring follows the card’s own effect.
    if area == G.play and apply(state, card:get_edition(), false) then calculated = true end
    local effects = { own }
    for _, joker in ipairs(live_jokers()) do
      local ret = joker:calculate_joker(context(base, { individual = true, cardarea = area, other_card = card }))
      if ret then
        effects[#effects + 1] = ret
        if apply(state, ret, true) then calculated = true end
      end
    end
    if j == 1 and calculated then
      if card.seal == "Red" then reps = reps + 1 end
      for _, joker in ipairs(live_jokers()) do
        local ret = joker:calculate_joker(context(base,
          { repetition = true, cardarea = area, other_card = card, card_effects = effects }))
        if type(ret) == "table" and ret.repetitions then reps = reps + ret.repetitions end
      end
    end
    j = j + 1
  end
end

function M.score(selection)
  local seat = {}
  for i, c in ipairs(G.hand.cards) do seat[c] = i end
  local played = {}
  for _, c in ipairs(selection) do played[#played + 1] = c end
  table.sort(played, function(a, b) return seat[a] < seat[b] end)
  local held, is_played = {}, {}
  for _, c in ipairs(played) do is_played[c] = true end
  for _, c in ipairs(G.hand.cards) do if not is_played[c] then held[#held + 1] = c end end
  G.play = { cards = played }
  G.hand.cards = held
  local text, _, poker_hands, scoring = M.get_poker_hand_info(played)
  local member = {}
  for _, c in ipairs(scoring) do member[c] = true end
  local scoring_hand = {}
  local splash = next(SMODS.find_card("j_splash"))
  for _, c in ipairs(played) do
    if member[c] or splash or SMODS.always_scores(c) then scoring_hand[#scoring_hand + 1] = c end
  end
  G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
  local h = G.GAME.hands[text]
  h.played = h.played + 1
  h.played_this_round = h.played_this_round + 1
  local base = { full_hand = played, scoring_hand = scoring_hand, scoring_name = text, poker_hands = poker_hands }
  for _, joker in ipairs(live_jokers()) do
    joker:calculate_joker(context(base, { before = true, cardarea = G.jokers }))
  end
  G.GAME.current_round.hands_played = G.GAME.current_round.hands_played + 1
  local state = { chips = h.chips, mult = h.mult, joker_chips = 0 }
  for _, c in ipairs(played) do
    if member[c] or splash or SMODS.always_scores(c) then
      if not c.debuff then score_card(state, c, G.play, base) end
    end
  end
  for _, c in ipairs(G.hand.cards) do score_card(state, c, G.hand, base) end
  for _, joker in ipairs(G.jokers.cards) do
    local ed = not joker.debuff and joker.edition or {}
    apply(state, { chips = ed.chips, mult = ed.mult }, true)
    if not joker.debuff then
      apply(state, joker:calculate_joker(context(base, { cardarea = G.jokers, joker_main = true })), true)
    end
    for _, other in ipairs(live_jokers()) do
      apply(state, other:calculate_joker(context(base, { other_joker = joker, other_main = joker })), true)
    end
    apply(state, { x_mult = ed.x_mult }, true)
  end
  -- The run count advances only after the hand has been evaluated.
  G.GAME.hands_played = (G.GAME.hands_played or 0) + 1
  return state.mult, state.joker_chips, text, state.chips
end

return M
