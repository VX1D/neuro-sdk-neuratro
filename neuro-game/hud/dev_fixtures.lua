local Fixtures = {}

local RANK_X = {
  ["2"] = 0, ["3"] = 1, ["4"] = 2, ["5"] = 3, ["6"] = 4, ["7"] = 5, ["8"] = 6,
  ["9"] = 7, ["10"] = 8, Jack = 9, Queen = 10, King = 11, Ace = 12,
}
local SUIT_Y = { Hearts = 0, Clubs = 1, Diamonds = 2, Spades = 3 }
local SUIT_CODE = { Hearts = "H", Clubs = "C", Diamonds = "D", Spades = "S" }
local RANK_CODE = { Ace = "A", King = "K", Queen = "Q", Jack = "J", ["10"] = "T" }

local _next_id = 90000
local function next_id()
  _next_id = _next_id + 1
  return _next_id
end

local function noop() end
local function sparse_ui_registry(size)
  size = math.max(0, math.floor(tonumber(size) or 4000))
  local middle = math.floor(size / 2)
  local function sentinel(index)
    return { fixture_index = index, remove = noop }
  end
  return {
    MOVEABLE = { [0] = sentinel(0) },
    UIBOX = { [middle] = sentinel(middle) },
    NODE = { [size] = sentinel(size) },
  }
end

local function copy_center(key, fallback_set, name)
  local real = G and G.P_CENTERS and G.P_CENTERS[key]
  local c = {}
  if real then
    for k, v in pairs(real) do c[k] = v end
  else
    c.pos = { x = 0, y = 0 }
    c.rarity = 1
  end
  c.key = key
  c.set = c.set or fallback_set or "Joker"
  c.name = name or c.name or key
  c.loc_txt = { name = name or c.name or key }
  return c
end

function Fixtures.card(spec)
  spec = spec or {}
  local key = spec.key or "j_joker"
  local name = spec.name or key
  local center = copy_center(key, spec.set, name)
  if spec.set then center.set = spec.set end
  if spec.rarity then center.rarity = spec.rarity end
  if spec.soul_pos then center.soul_pos = spec.soul_pos end
  if spec.no_pos then center.pos = {} end
  if spec.loc_text then center.loc_txt.text = spec.loc_text end
  if type(spec.loc_vars) == "function" then center.loc_vars = spec.loc_vars end

  local cost = spec.cost or 5
  local id = next_id()
  local card = {
    ID = id,
    config = { center = center },
    ability = {
      set = center.set, name = name,
      mult = 0, h_mult = 0, h_mod = 0, t_mult = 0, t_chips = 0, x_mult = 1, extra = 0,
    },
    base = { name = key },
    cost = cost,
    sell_cost = math.max(1, math.floor(cost / 2)),
    debuff = spec.debuff and true or false,
    highlighted = false,
    ARGS = { send_to_shader = { 0, id } },
    VT = { x = 0, y = 0, w = 71, h = 95, scale = 1 },
    T = { x = 0, y = 0, w = 1, h = 1.4 },
    juice_up = noop,
    juice_card = noop,
  }
  if spec.facing then card.facing = spec.facing end
  if spec.edition then card.edition = spec.edition end
  if spec.seal then card.seal = spec.seal end
  if spec.enhancement then card.ability.enhancement = spec.enhancement end
  if spec.eternal then card.ability.eternal = true end
  if spec.rental then card.ability.rental = true end
  if spec.perishable then
    card.ability.perishable = true
    card.ability.perish_tally = spec.perish_tally or 3
  end
  if spec.undiscovered then
    card.ability.name = "Not Discovered"
    card.generate_UIBox_ability_table = function() return { name = "Not Discovered" } end
  end
  if spec.value and spec.suit then
    local code = (SUIT_CODE[spec.suit] or "S") .. "_" .. (RANK_CODE[spec.value] or spec.value)
    local real = G and G.P_CARDS and G.P_CARDS[code]
    local pos = real and real.pos
      or { x = RANK_X[spec.value] or 0, y = SUIT_Y[spec.suit] or 0 }
    card.config.card = { value = spec.value, suit = spec.suit, pos = pos }
    card.base.value, card.base.suit = spec.value, spec.suit
    card.base.nominal = 10
  end
  return card
end

function Fixtures.area(cards, limit)
  local a = {
    cards = cards or {},
    config = { card_limit = limit or 5 },
    highlighted = {},
  }
  a.add_to_highlighted = function(self, card)
    if not card then return end
    for _, c in ipairs(self.highlighted) do if c == card then return end end
    self.highlighted[#self.highlighted + 1] = card
    require("core.game_actions").set_highlight(card, true)
  end
  a.remove_from_highlighted = function(self, card)
    for i, c in ipairs(self.highlighted) do
      if c == card then table.remove(self.highlighted, i) break end
    end
    require("core.game_actions").set_highlight(card, false)
  end
  return a
end

Fixtures.CARD_KINDS = {
  { id = "joker",     label = "Joker" },
  { id = "playing",   label = "Playing" },
  { id = "stone",     label = "Stone" },
  { id = "tarot",     label = "Tarot" },
  { id = "planet",    label = "Planet" },
  { id = "spectral",  label = "Spectral" },
  { id = "voucher",   label = "Voucher" },
  { id = "legendary", label = "Legendary" },
  { id = "wide",      label = "Wide art" },
  { id = "long",      label = "Long text" },
  { id = "nopos",     label = "No art" },
}

local LONG_TEXT = {
  "Gains {C:mult}+4{} Mult for every card discarded this round, resets when the",
  "blind is defeated, doubles while a Gold Seal card is held in hand, and",
  "loses half its accumulated Mult whenever a Joker is sold in the shop.",
}

local function fixture_loc_vars(_center, _info_queue, card)
  local ability = card and card.ability or {}
  return { vars = { ability.mult or 0 } }
end

local KIND_SPEC = {
  joker     = { key = "j_joker", name = "Joker", set = "Joker", cost = 4,
                loc_vars = fixture_loc_vars },
  playing   = { key = "m_bonus", name = "Ace of Spades", set = "Enhanced",
                value = "Ace", suit = "Spades", cost = 3 },
  stone     = { key = "m_stone", name = "Stone Card", set = "Enhanced",
                value = "2", suit = "Clubs", cost = 3 },
  tarot     = { key = "c_magician", name = "The Magician", set = "Tarot", cost = 3 },
  planet    = { key = "c_pluto", name = "Pluto", set = "Planet", cost = 3 },
  spectral  = { key = "c_familiar", name = "Familiar", set = "Spectral", cost = 4 },
  voucher   = { key = "v_grabber", name = "Grabber", set = "Voucher", cost = 10 },
  legendary = { key = "j_caino", name = "Canio", set = "Joker", cost = 20, rarity = 4,
                soul_pos = { x = 0, y = 0 } },
  wide      = { key = "j_photograph", name = "Photograph", set = "Joker", cost = 5, rarity = 2 },
  long      = { key = "j_dev_long", name = "Antimatter Prototype Obelisk of the Seventeenth Ante",
                set = "Joker", cost = 18, rarity = 3, loc_text = LONG_TEXT },
  nopos     = { key = "j_dev_nopos", name = "Unrendered Prototype", set = "Joker",
                cost = 7, no_pos = true },
}

Fixtures.MODIFIERS = {
  { id = "none",       label = "none" },
  { id = "foil",       label = "Foil" },
  { id = "holo",       label = "Holo" },
  { id = "polychrome", label = "Polychrome" },
  { id = "negative",   label = "Negative" },
  { id = "seal_gold",  label = "Gold seal" },
  { id = "seal_red",   label = "Red seal" },
  { id = "seal_blue",  label = "Blue seal" },
  { id = "seal_purple", label = "Purple seal" },
  { id = "enh_bonus",  label = "Bonus" },
  { id = "enh_mult",   label = "Mult" },
  { id = "enh_wild",   label = "Wild" },
  { id = "enh_glass",  label = "Glass" },
  { id = "enh_steel",  label = "Steel" },
  { id = "enh_gold",   label = "Gold" },
  { id = "enh_lucky",  label = "Lucky" },
  { id = "eternal",    label = "Eternal" },
  { id = "perishable", label = "Perishable" },
  { id = "rental",     label = "Rental" },
  { id = "debuff",     label = "Debuffed" },
  { id = "facedown",   label = "Face-down" },
  { id = "loaded",     label = "All at once" },
}

local MOD_SPEC = {
  none        = {},
  foil        = { edition = { foil = true } },
  holo        = { edition = { holo = true } },
  polychrome  = { edition = { polychrome = true } },
  negative    = { edition = { negative = true } },
  seal_gold   = { seal = "Gold" },
  seal_red    = { seal = "Red" },
  seal_blue   = { seal = "Blue" },
  seal_purple = { seal = "Purple" },
  enh_bonus   = { enhancement = "m_bonus" },
  enh_mult    = { enhancement = "m_mult" },
  enh_wild    = { enhancement = "m_wild" },
  enh_glass   = { enhancement = "m_glass" },
  enh_steel   = { enhancement = "m_steel" },
  enh_gold    = { enhancement = "m_gold" },
  enh_lucky   = { enhancement = "m_lucky" },
  eternal     = { eternal = true },
  perishable  = { perishable = true, perish_tally = 3 },
  rental      = { rental = true },
  debuff      = { debuff = true },
  facedown    = { facing = "back" },
  loaded      = { edition = { polychrome = true }, seal = "Purple", enhancement = "m_glass",
                  eternal = true, rental = true, perishable = true, perish_tally = 2 },
}

function Fixtures.subject(kind_id, mod_id)
  local spec = {}
  for k, v in pairs(KIND_SPEC[kind_id] or KIND_SPEC.joker) do spec[k] = v end
  for k, v in pairs(MOD_SPEC[mod_id] or MOD_SPEC.none) do spec[k] = v end
  return Fixtures.card(spec)
end

Fixtures.LAYOUTS = {
  { id = "few",      label = "Few" },
  { id = "empty",    label = "Empty" },
  { id = "full",     label = "Full" },
  { id = "overflow", label = "Overflow" },
}

local FILLER = {
  { key = "j_greedy_joker", name = "Greedy Joker", cost = 5 },
  { key = "j_jolly", name = "Jolly Joker", cost = 5 },
  { key = "j_zany", name = "Zany Joker", cost = 6, rarity = 2 },
  { key = "j_crazy", name = "Crazy Joker", cost = 6, rarity = 2 },
  { key = "j_mad", name = "Mad Joker", cost = 6, rarity = 2 },
  { key = "j_droll", name = "Droll Joker", cost = 6 },
  { key = "j_sly", name = "Sly Joker", cost = 4 },
  { key = "j_wily", name = "Wily Joker", cost = 5 },
  { key = "j_clever", name = "Clever Joker", cost = 5 },
  { key = "j_devious", name = "Devious Joker", cost = 5, rarity = 2 },
  { key = "j_crafty", name = "Crafty Joker", cost = 6 },
  { key = "j_half", name = "Half Joker", cost = 5 },
}

local LAYOUT_COUNTS = {
  empty    = { jokers = 0, cons = 0, cons_limit = 2 },
  few      = { jokers = 2, cons = 1, cons_limit = 2 },
  full     = { jokers = 5, cons = 2, cons_limit = 2 },
  overflow = { jokers = 12, cons = 4, cons_limit = 4 },
}

local function filler_cards(n)
  local out = {}
  for i = 1, n do
    local f = FILLER[((i - 1) % #FILLER) + 1]
    out[i] = Fixtures.card({ key = f.key, name = f.name, cost = f.cost, rarity = f.rarity })
  end
  return out
end

Fixtures.EVENTS = {
  { id = "none",      label = "none" },
  { id = "buy",       label = "Joker buy" },
  { id = "voucher",   label = "Voucher buy" },
  { id = "voucher_backlog", label = "Voucher behind backlog" },
  { id = "crosscut",  label = "Receipt cross-cut" },
  { id = "toasts",    label = "Receipt cycle" },
  { id = "gain",      label = "Pack pick receipt" },
  { id = "showcase",  label = "Showcase entry" },
  { id = "pick",      label = "Pack pick" },
  { id = "money",     label = "Money change" },
  { id = "login",     label = "Login anim" },
  { id = "cookie",    label = "Cookie" },
  { id = "picklate",  label = "Pack late claim" },
  { id = "pickmore",  label = "Pack pick, stays open" },
  { id = "usecard",   label = "Use card" },
  { id = "buyuse",    label = "Buy & use" },
  { id = "pickmorph", label = "Pick morph" },
  { id = "packclaim", label = "Claim + receipt" },
  { id = "boosteropen", label = "Booster receipt vs pack" },
  { id = "lastcons",   label = "Last consumable" },
  { id = "leaveshop",  label = "Shop leaves" },
  { id = "shoptopack", label = "Receipt into pack" },
  { id = "picklive",   label = "Pack pick, area emptied" },
  { id = "picklast",   label = "Pack pick, last one" },
  { id = "packfinal",  label = "Pack final pick" },
  { id = "packtear",   label = "Pack fast teardown" },
  { id = "usecons_shop", label = "Consumable in shop" },
  { id = "leavepack",  label = "Pack leaves unpicked" },
  { id = "swapcons",   label = "Carousel swap" },
}

Fixtures.STATES = {
  "SHOP", "BLIND_SELECT", "SELECTING_HAND", "HAND_PLAYED", "DRAW_TO_HAND",
  "ROUND_EVAL", "NEW_ROUND", "PLAY_TAROT", "TAROT_PACK", "PLANET_PACK",
  "SPECTRAL_PACK", "STANDARD_PACK", "BUFFOON_PACK", "SMODS_BOOSTER_OPENED",
  "SMODS_REDEEM_VOUCHER", "GAME_OVER", "MENU", "SPLASH", "RUN_SETUP",
  "TUTORIAL", "SANDBOX", "DEMO_CTA", "UNKNOWN",
}

local PACK_POOL = {
  TAROT_PACK = { "c_fool", "c_magician", "c_high_priestess", "c_empress" },
  PLANET_PACK = { "c_pluto", "c_mercury", "c_venus", "c_earth" },
  SPECTRAL_PACK = { "c_familiar", "c_grim", "c_incantation", "c_talisman" },
  BUFFOON_PACK = { "j_zany", "j_crazy", "j_mad", "j_droll" },
}

local PACK_SET = {
  TAROT_PACK = "Tarot", PLANET_PACK = "Planet",
  SPECTRAL_PACK = "Spectral", BUFFOON_PACK = "Joker",
}

function Fixtures.pack_cards(state)
  if state == "STANDARD_PACK" or state == "SMODS_BOOSTER_OPENED" then
    local vals = { "Ace", "King", "7", "3" }
    local suits = { "Spades", "Hearts", "Diamonds", "Clubs" }
    local out = {}
    for i = 1, 4 do
      out[i] = Fixtures.card({
        key = "m_bonus", set = "Enhanced", name = vals[i] .. " of " .. suits[i],
        value = vals[i], suit = suits[i], cost = 3,
      })
    end
    return out
  end
  local pool = PACK_POOL[state] or PACK_POOL.TAROT_PACK
  local set = PACK_SET[state] or "Tarot"
  local out = {}
  for i, key in ipairs(pool) do
    out[i] = Fixtures.card({ key = key, set = set, name = key, cost = 3 })
  end
  return out
end

Fixtures.VOUCHER_KEYS = {
  "v_overstock_norm", "v_clearance_sale", "v_grabber", "v_seed_money", "v_overstock_plus",
}

Fixtures.VOUCHER_NAMES = {
  v_overstock_norm = "Overstock", v_clearance_sale = "Clearance Sale", v_grabber = "Grabber",
  v_seed_money = "Seed Money", v_overstock_plus = "Overstock Plus",
}

Fixtures.HAND_LEVEL_SNAP = { Flush = 3 }

function Fixtures.game(opts)
  opts = opts or {}
  return {
    hands = {
      Flush = { level = 5, visible = true },
      Pair = { level = 2, visible = true },
      ["High Card"] = { level = 1, visible = true },
    },
    dollars = opts.dollars or 25,
    chips = 0,
    round = 3,
    joker_limit = opts.joker_limit or 5,
    consumeable_limit = opts.cons_limit or 2,
    joker_buffer = 0,
    consumeable_buffer = 0,
    current_round = { reroll_cost = opts.reroll_cost },
    round_resets = { ante = 2, blind_choices = { Small = "bl_small", Big = "bl_big" } },
    used_vouchers = opts.used_vouchers or {},
    selected_back = (G and G.P_CENTERS and (G.P_CENTERS.b_plasma or G.P_CENTERS.b_red)) or nil,
    seeded = true,
    pseudorandom = { seed = "DEVHARNESS" },
    pack_choices = opts.pack_choices,
    blind = opts.blind,
  }
end

function Fixtures.boss_blind()
  return {
    in_blind = true, boss = true, chips = 5000, mult = 2, name = "The Hook",
    get_loc_debuff_text = function() return "1 selected card debuffed each hand" end,
  }
end

function Fixtures.shop(subject)
  return {
    jokers = Fixtures.area({
      subject,
      Fixtures.card({ key = "j_blueprint", name = "Blueprint", cost = 10, rarity = 3,
        undiscovered = true, edition = { holo = true }, seal = "Gold", eternal = true }),
      Fixtures.card({ key = "j_misprint", name = "Misprint", cost = 4 }),
    }),
    vouchers = Fixtures.area({
      Fixtures.card({ key = "v_grabber", set = "Voucher", name = "Grabber", cost = 10 }),
      Fixtures.card({ key = "v_seed_money", set = "Voucher", name = "Seed Money", cost = 30 }),
    }),
    boosters = Fixtures.area({
      Fixtures.card({ key = "p_arcana_normal_1", set = "Booster", name = "Arcana Pack", cost = 4 }),
      Fixtures.card({ key = "p_buffoon_normal_1", set = "Booster", name = "Buffoon Pack", cost = 6 }),
    }),
  }
end

function Fixtures.owned(layout_id, subject)
  local counts = LAYOUT_COUNTS[layout_id] or LAYOUT_COUNTS.few
  local jokers = filler_cards(counts.jokers)
  if counts.jokers > 0 and subject then jokers[1] = subject end
  local cons = {}
  local cons_keys = { "c_fool", "c_pluto", "c_familiar", "c_magician" }
  for i = 1, counts.cons do
    cons[i] = Fixtures.card({ key = cons_keys[((i - 1) % #cons_keys) + 1], set = "Tarot",
      name = cons_keys[((i - 1) % #cons_keys) + 1], cost = 3 })
  end
  return Fixtures.area(jokers, math.max(5, counts.jokers)),
    Fixtures.area(cons, counts.cons_limit)
end

if rawget(_G, "NEURO_TEST") then
  Fixtures._test = {
    KIND_SPEC = KIND_SPEC,
    MOD_SPEC = MOD_SPEC,
    LAYOUT_COUNTS = LAYOUT_COUNTS,
    sparse_ui_registry = sparse_ui_registry,
  }
end

return Fixtures
