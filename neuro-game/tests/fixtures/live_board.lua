local Vanilla = require("tests.fixtures.vanilla_jokers")

local M = {}

M.TEXT = {
  j_hologram = "This Joker gains X0.25 Mult every time a playing card is added to your deck (Currently X1.5 Mult)",
  j_cavendish = "X3 Mult 1 in 1000 chance this card is destroyed at the end of round",
  j_rocket = "Earn $7 at end of round Payout increases by $2 when Boss Blind is defeated",
  j_baron = "Each King held in hand gives X1.5 Mult",
  j_scary_face = "Played face cards give +30 Chips when scored",
  j_blueprint = "Copies ability of Joker to the right",
  j_mime = "Retrigger all card held in hand abilities",
  j_banner = "+30 Chips for each remaining discard",
  j_fibonacci = "Each played Ace, 2, 3, 5, or 8 gives +8 Mult when scored",
  j_odd_todd = "Played cards with odd rank give +31 Chips when scored (A, 9, 7, 5, 3)",
}

M.OWNED = { "j_hologram", "j_cavendish", "j_rocket", "j_baron", "j_scary_face" }
M.SHOP = { "j_blueprint", "j_mime", "j_banner" }

M.SIGIL = {
  j_hologram = "X0.25", j_cavendish = "1000", j_rocket = "$7", j_baron = "X1.5",
  j_scary_face = "+30 Chips when scored", j_blueprint = "to the right",
  j_mime = "Retrigger all card held", j_banner = "each remaining discard",
  j_fibonacci = "+8 Mult", j_odd_todd = "+31 Chips",
}

function M.joker(key, sort_id)
  local card = Vanilla.card_played(key, sort_id)
  card.config.center.loc_txt = { name = card.config.center.name, description = { M.TEXT[key] } }
  card.debuff = false
  return card
end

local RANKS = { A = 14, K = 13, Q = 12, J = 11, ["10"] = 10, ["9"] = 9, ["8"] = 8, ["7"] = 7,
  ["6"] = 6, ["5"] = 5, ["4"] = 4, ["3"] = 3, ["2"] = 2 }
local LONG = { A = "Ace", K = "King", Q = "Queen", J = "Jack" }

function M.pcard(rank, suit, sort_id)
  local id = RANKS[rank] or 10
  local c = {
    sort_id = sort_id,
    sell_cost = 1,
    base = { value = LONG[rank] or rank, suit = suit, id = id, nominal = math.min(id, 10),
      nominal_chips = math.min(id, 10) },
    ability = { effect = "Base", name = "Default Base", set = "Default", bonus = 0 },
    config = { center = { key = "c_base", set = "Default" } },
  }
  function c:get_id() return self.base.id end
  function c:is_suit(s) return self.base.suit == s end
  function c:is_face() return self.base.id >= 11 and self.base.id <= 13 end
  return c
end

function M.hand8()
  local spec = { { "K", "Hearts" }, { "K", "Spades" }, { "Q", "Hearts" }, { "J", "Hearts" },
    { "9", "Hearts" }, { "7", "Clubs" }, { "5", "Diamonds" }, { "3", "Spades" } }
  local out = {}
  for i, s in ipairs(spec) do out[i] = M.pcard(s[1], s[2], 200 + i) end
  return out
end

function M.deck(n)
  local out, i = {}, 0
  local suits = { "Hearts", "Diamonds", "Spades", "Clubs" }
  local ranks = { "A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2" }
  while i < n do
    i = i + 1
    out[i] = M.pcard(ranks[((i - 1) % 13) + 1], suits[((i - 1) % 4) + 1], 300 + i)
  end
  return out
end

M.CENTERS = {
  c_hanged_man = { name = "The Hanged Man", set = "Tarot",
    config = { remove_card = true, max_highlighted = 2 },
    text = { "Destroy up to 2 selected cards" } },
  c_pluto = { name = "Pluto", set = "Planet", config = { hand_type = "High Card" },
    text = { "(lvl.1) Level up High Card", "+1 Mult and +10 chips" } },
  c_fool = { name = "The Fool", set = "Tarot", config = {},
    text = { "Creates the last Tarot or Planet card used during this run", "The Fool excluded" } },
}

-- Engine port: game-dump/card.lua:1841 (Card:can_use_consumeable), restricted to the branches a
-- corpus board can reach. facts/card_util.lua:162 falls back to a slot check without it, so a
-- Planet card that is always usable was rendered "Usable now: no".
local function can_use_consumeable(self, any_state)
  local G = _G.G
  local ab = self.ability or {}
  local cons = ab.consumeable or {}
  local S = G.STATES or {}
  if not any_state then
    for _, blocked in ipairs({ "HAND_PLAYED", "DRAW_TO_HAND", "PLAY_TAROT" }) do
      if S[blocked] ~= nil and G.STATE == S[blocked] then return false end
    end
  end
  if ab.name == "The Hermit" or cons.hand_type or ab.name == "Temperance"
      or ab.name == "Black Hole" then
    return true
  end
  local cons_area = G.consumeables or { cards = {}, config = {} }
  local room = #cons_area.cards < (cons_area.config and cons_area.config.card_limit or 0)
  if ab.name == "The Emperor" or ab.name == "The High Priestess" then
    return room or self.area == cons_area
  end
  if ab.name == "The Fool" then
    return (room or self.area == cons_area)
      and G.GAME.last_tarot_planet ~= nil and G.GAME.last_tarot_planet ~= "c_fool"
  end
  if ab.name == "Judgement" or ab.name == "The Soul" or ab.name == "Wraith" then
    local jk = G.jokers or { cards = {}, config = {} }
    return #jk.cards < (jk.config and jk.config.card_limit or 0) or self.area == jk
  end
  for _, name in ipairs({ "SELECTING_HAND", "TAROT_PACK", "SPECTRAL_PACK", "PLANET_PACK" }) do
    if S[name] ~= nil and G.STATE == S[name] and cons.max_highlighted then
      local hl = #((G.hand and G.hand.highlighted) or {})
      return (cons.mod_num or math.min(5, cons.max_highlighted)) >= hl
        and hl >= (cons.min_highlighted or 1)
    end
  end
  return false
end

function M.consumable(key, sort_id)
  local centre = M.CENTERS[key]
  local cons = {}
  for k, v in pairs(centre.config) do cons[k] = v end
  if cons.max_highlighted then cons.mod_num = math.min(5, cons.max_highlighted) end
  return { sort_id = sort_id, sell_cost = 1, cost = 3,
    ability = { name = centre.name, set = centre.set, consumeable = cons },
    can_use_consumeable = can_use_consumeable,
    config = { center = { key = key, set = centre.set, name = centre.name,
      loc_txt = { name = centre.name, text = centre.text } } } }
end

local TD = require("tests.test_deadlock")

function M.enrich(opts)
  opts = opts or {}
  local G = _G.G
  local roster = {}
  for i, key in ipairs(M.OWNED) do roster[i] = M.joker(key, 800 + i) end
  if opts.jokers then
    local cut = {}
    for i = 1, opts.jokers do cut[i] = roster[i] end
    roster = cut
  end
  local limit = (G.jokers and G.jokers.config and G.jokers.config.card_limit) or 5
  G.jokers = { cards = roster, config = { card_limit = math.max(limit, #roster) } }

  G.FUNCS = G.FUNCS or {}
  G.FUNCS.get_poker_hand_info = TD.get_poker_hand_info

  if G.hand then
    G.hand.cards = M.hand8()
    G.hand.highlighted = {}
    G.hand.config = G.hand.config or {}
    G.hand.config.card_limit = 8
    G.hand.config.highlighted_limit = 5
  end
  G.deck = { cards = M.deck(44) }
  G.playing_cards = {}
  for _, c in ipairs(G.deck.cards) do G.playing_cards[#G.playing_cards + 1] = c end
  for _, c in ipairs(G.hand and G.hand.cards or {}) do G.playing_cards[#G.playing_cards + 1] = c end

  if G.consumeables and not opts.keep_consumables then
    G.consumeables.cards = { M.consumable("c_hanged_man", 900), M.consumable("c_pluto", 901) }
    G.consumeables.config = G.consumeables.config or { card_limit = 2 }
    for _, c in ipairs(G.consumeables.cards) do c.area = G.consumeables end
  end

  if G.shop_jokers and G.shop_jokers.cards and #G.shop_jokers.cards > 0 and not opts.keep_shop then
    local stock = {}
    for i, key in ipairs(M.SHOP) do
      local c = M.joker(key, 700 + i)
      c.cost = 4 + i
      stock[i] = c
    end
    G.shop_jokers.cards = stock
  end

  local bp = G.pack_cards or G.booster_pack
  if bp and bp.cards and #bp.cards > 0 and #bp.cards < 3 then
    local proto = bp.cards[1]
    while #bp.cards < 3 do
      local clone = {}
      for k, v in pairs(proto) do clone[k] = v end
      clone.base = proto.base and { value = proto.base.value, suit = proto.base.suit,
        id = proto.base.id, nominal = proto.base.nominal } or nil
      clone.sort_id = 600 + #bp.cards
      bp.cards[#bp.cards + 1] = clone
    end
  end

  G.GAME.hands = G.GAME.hands or {}
  local levels = { Pair = 3, ["Two Pair"] = 2, Flush = 4, Straight = 1, ["High Card"] = 1,
    ["Three of a Kind"] = 2, ["Full House"] = 1, ["Four of a Kind"] = 1, ["Straight Flush"] = 1 }
  for name, lvl in pairs(levels) do
    G.GAME.hands[name] = { visible = true, level = lvl, chips = 10 * lvl, mult = 2 * lvl,
      played = lvl - 1, l_chips = 10, l_mult = 1 }
  end
  G.GAME.used_vouchers = G.GAME.used_vouchers or {}
  G.GAME.used_vouchers.v_overstock_norm = true
  G.GAME.used_vouchers.v_grabber = true
  G.GAME.probabilities = G.GAME.probabilities or { normal = 1 }
  return G
end

local RESET = { "hand", "jokers", "consumeables", "deck", "playing_cards", "shop_jokers",
  "shop_vouchers", "shop_booster", "pack_cards", "booster_pack", "shop", "blind_select_opts",
  "blind_select", "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS", "playbook_extra" }

local STATE_ID, next_state_id = {}, 0
local function enter_state(name)
  if not STATE_ID[name] then next_state_id = next_state_id + 1; STATE_ID[name] = next_state_id end
  _G.G.STATES = _G.G.STATES or {}
  _G.G.STATES[name] = STATE_ID[name]
  _G.G.STATE = STATE_ID[name]
end

M.VARIANTS = {}

function M.VARIANTS.flipped(G)
  for _, card in ipairs(G.jokers.cards) do card.facing = "back" end
  if G.hand and G.hand.cards and G.hand.cards[1] then G.hand.cards[1].facing = "back" end
end

M.INTENTS = {
  { tag = "CORE", note = "the whole build hangs off this multiplier; nothing else here scales" },
  { tag = "SCALING", note = "worth a slot only while the destroy roll stays this unlikely" },
  { tag = "HOLD", note = "pays the rent between bosses; first out when a better fit appears" },
  { tag = "CHANGE", note = "needs a hand shape I keep not drawing, so it is the swap candidate" },
  { tag = "HOLD", note = "" },
}

function M.VARIANTS.marked(G)
  G.jokers.cards[2].debuff = true
  G.jokers.cards[3].ability.eternal = true
  local intents = {}
  for i, card in ipairs(G.jokers.cards) do
    local spec = M.INTENTS[((i - 1) % #M.INTENTS) + 1]
    intents[card.sort_id] = { tag = spec.tag, note = spec.note,
      provenance = { ante = 3, decision_serial = 12 } }
  end
  G.NEURO.joker_intents = intents
end

M.BOARDS = {
  { state = "SELECTING_HAND", desc = "Normal: 5 cards, 4 hands, 3 discards" },
  { state = "SELECTING_HAND", desc = "Amber Acorn: the boss that names reordering", boss = true },
  { state = "SHOP", desc = "Normal: affordable joker, affordable booster, $10" },
  { state = "BLIND_SELECT", desc = "Small blind selectable" },
  { state = "BLIND_SELECT", desc = "Boss blind only (no skip, no reroll voucher)", boss = true },
  { state = "ROUND_EVAL", desc = "Normal: cash_out available" },
  { state = "TAROT_PACK", desc = "Has pack cards" },
  { state = "BUFFOON_PACK", desc = "BUFFOON_PACK variant with pack cards" },
  { state = "STANDARD_PACK", desc = "STANDARD_PACK with cards" },
  { state = "PLANET_PACK", desc = "PLANET_PACK with cards" },
  { state = "SPECTRAL_PACK", desc = "SPECTRAL_PACK with cards" },
  { state = "SMODS_BOOSTER_OPENED", desc = "SMODS_BOOSTER_OPENED with cards" },
  { state = "SELECTING_HAND", boss = true,
    base = "Amber Acorn: the boss that names reordering", variant = "flipped",
    desc = "Amber Acorn with the row flipped: face-down jokers and a face-down card in hand" },
  { state = "SHOP",
    base = "Normal: affordable joker, affordable booster, $10", variant = "marked",
    desc = "Marked roster: a debuffed joker, an eternal joker, and the model's own plan on every row" },
}

M.BLOCKED = {
  { state = "SHOP", desc = "$0 nothing affordable, has jokers to sell" },
}

M.OUT_OF_RUN = {
  { state = "MENU", desc = "Normal: has G.GAME" },
  { state = "SPLASH", desc = "Normal: minimal state" },
  { state = "RUN_SETUP", desc = "Run setup overlay active" },
  { state = "GAME_OVER", desc = "No overlay (setup_run must work)" },
}

local function scenario(state, desc)
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc == desc then return sc end
  end
  error("live_board: no test_deadlock scenario " .. state .. " / " .. desc)
end

local function board_record(state, desc)
  for _, list in ipairs({ M.BOARDS, M.BLOCKED, M.OUT_OF_RUN }) do
    for _, b in ipairs(list) do
      if b.state == state and b.desc == desc then return b end
    end
  end
  return nil
end

function M.load(state, desc, opts)
  local Actions = require("core.actions")
  local Dispatcher = require("core.dispatcher")
  local rec = board_record(state, desc)
  local sc = scenario(state, (rec and rec.base) or desc)
  for _, k in ipairs(RESET) do _G.G[k] = nil end
  _G.G.GAME = { current_round = {} }
  _G.G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", run_generation = 1,
    once_serials = {}, session_once_serials = {}, decision_serial = 1, state_enter_serial = 1,
    jokers_sold_run = 0, reserved_dollars = 0, shop_reroll_count = 0 }
  TD.apply_mock(sc.mock())
  M.enrich(opts)
  if rec and rec.variant then M.VARIANTS[rec.variant](_G.G) end
  enter_state(state)
  require("context.context_compact").invalidate_cache()
  require("facts.fact_hints").reset_pending()
  return sc
end

return M
