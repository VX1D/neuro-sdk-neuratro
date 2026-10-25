local M = {}

local RANKS = {}
for i, value in ipairs({ "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }) do
  local id = i + 1
  RANKS[value] = { key = value, id = id, face = id >= 11 and id <= 13,
    nominal = (id == 14 and 11) or math.min(id, 10) }
end
M.RANKS = RANKS

local function center_of(key) return (G and G.P_CENTERS and G.P_CENTERS[key]) or {} end

local Rules = {}
M.Rules = Rules

function Rules.get_enhancements(card)
  return card.ability.set == "Enhanced" and { [card.config.center.key] = true } or {}
end

function Rules.has_enhancement(card, key)
  if card.config.center.key == key then return true end
  return Rules.get_enhancements(card)[key] == true
end

function Rules.has_no_suit(card)
  local stone, wild = false, false
  for k in pairs(SMODS.get_enhancements(card)) do
    if k == "m_stone" or center_of(k).no_suit then stone = true end
    if k == "m_wild" or center_of(k).any_suit then wild = true end
  end
  return stone and not wild
end

function Rules.has_any_suit(card)
  for k in pairs(SMODS.get_enhancements(card)) do
    if k == "m_wild" or center_of(k).any_suit then return true end
  end
end

function Rules.has_no_rank(card)
  for k in pairs(SMODS.get_enhancements(card)) do
    if k == "m_stone" or center_of(k).no_rank then return true end
  end
end

function Rules.always_scores(card)
  for k in pairs(SMODS.get_enhancements(card)) do
    if k == "m_stone" or center_of(k).always_scores then return true end
  end
  if center_of((card.edition or {}).key).always_scores then return true end
end

function Rules.never_scores(card)
  for k in pairs(SMODS.get_enhancements(card)) do
    if center_of(k).never_scores then return true end
  end
  if center_of((card.edition or {}).key).never_scores then return true end
end

local function owns(key)
  for _, j in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if j.config and j.config.center and j.config.center.key == key and not j.debuff then return true end
  end
  return false
end

function Rules.four_fingers() return owns("j_four_fingers") and 4 or 5 end
function Rules.shortcut() return owns("j_shortcut") end

function Rules.smeared_check(card, suit)
  if not owns("j_smeared") then return false end
  local red = { Hearts = true, Diamonds = true }
  return red[card.base.suit] == red[suit]
end

function Rules.get_probability_vars(_, base_numerator, base_denominator)
  if not G.jokers then return base_numerator, base_denominator end
  return base_numerator * (G.GAME and G.GAME.probabilities.normal or 1), base_denominator
end

function Rules.check_applied_stakes(stake, deck)
  local applied = stake and stake.applied_stakes
  if type(applied) == "table" and next(applied) ~= nil then
    for _, applied_stake in ipairs(applied) do
      if not (deck and deck.wins_by_key and deck.wins_by_key[applied_stake]) then return false end
    end
  end
  return true
end

function M.install_smods(t)
  t = t or {}
  for name, fn in pairs(Rules) do
    if t[name] == nil then t[name] = fn end
  end
  t.ConsumableTypes = t.ConsumableTypes or { Tarot = { key = "Tarot" }, Planet = { key = "Planet" },
    Spectral = { key = "Spectral" } }
  t.Suit = t.Suit or { obj_buffer = { "Diamonds", "Clubs", "Hearts", "Spades" } }
  t.RunSelect = t.RunSelect or { Pages = {}, Internals = { pages = {}, current_page = 1 },
    Setup = { choices = { seed = "" } }, Functions = {} }
  _G.SMODS = t
  return t
end

local Card = {}
Card.__index = Card
M.Card = Card

function Card:highlight(on) self.highlighted = on end

function Card:can_calculate(ignore_debuff) return not self.debuff or ignore_debuff end

function Card:get_id()
  if SMODS.has_no_rank(self) and not self.vampired then return -math.random(100, 1000000) end
  return self.base.id
end

function Card:get_nominal(mod)
  local mult, rank_mult = 1, 1
  if mod == "suit" then mult = 10000 end
  local no_suit, no_rank = SMODS.has_no_suit(self), SMODS.has_no_rank(self)
  if self.ability.effect == "Stone Card" or (no_suit and no_rank) then
    mult = -10000
  elseif no_suit then
    mult = 0
  elseif no_rank then
    rank_mult = 0
  end
  return 10 * self.base.nominal * rank_mult + self.base.suit_nominal * mult
    + (self.base.suit_nominal_original or 0) * 0.0001 * mult + 10 * self.base.face_nominal * rank_mult
    + 0.000001 * self.unique_val
end

function Card:is_face(from_boss)
  if self.debuff and not from_boss then return end
  local id = self:get_id()
  local rank = RANKS[self.base.value]
  if not id then return end
  if (id > 0 and rank and rank.face) or owns("j_pareidolia") then return true end
end

function Card:is_suit(suit, bypass_debuff, flush_calc)
  if flush_calc then
    if SMODS.has_no_suit(self) then return false end
    if SMODS.has_any_suit(self) and self:can_calculate() then return true end
    if SMODS.smeared_check(self, suit) then return true end
    return self.base.suit == suit
  end
  if self.debuff and not bypass_debuff then return end
  if SMODS.has_no_suit(self) then return false end
  if SMODS.has_any_suit(self) then return true end
  if SMODS.smeared_check(self, suit) then return true end
  return self.base.suit == suit
end

function Card:get_chip_bonus()
  if self.ability.extra_enhancement then return self.ability.bonus end
  if self.ability.effect == "Stone Card" or self.config.center.replace_base_card then
    return self.ability.bonus + (self.ability.perma_bonus or 0)
  end
  return self.base.nominal + self.ability.bonus + (self.ability.perma_bonus or 0)
end

function M.card(t)
  return setmetatable(t, Card)
end

local CENTERS = {
  c_base = { name = "Default Base", set = "Default", effect = "Base", config = {} },
  m_bonus = { name = "Bonus", set = "Enhanced", effect = "Bonus Card", config = { bonus = 30 } },
  m_mult = { name = "Mult", set = "Enhanced", effect = "Mult Card", config = { mult = 4 } },
  m_wild = { name = "Wild Card", set = "Enhanced", effect = "Wild Card", config = {} },
  m_glass = { name = "Glass Card", set = "Enhanced", effect = "Glass Card", config = { Xmult = 2, extra = 4 } },
  m_steel = { name = "Steel Card", set = "Enhanced", effect = "Steel Card", config = { h_x_mult = 1.5 } },
  m_stone = { name = "Stone Card", set = "Enhanced", effect = "Stone Card", config = { bonus = 50 } },
  m_gold = { name = "Gold Card", set = "Enhanced", effect = "Gold Card", config = { h_dollars = 3 } },
  m_lucky = { name = "Lucky Card", set = "Enhanced", effect = "Lucky Card", config = { mult = 20, p_dollars = 20 } },
}
for key, center in pairs(CENTERS) do center.key = key end
M.CENTERS = CENTERS

function M.enhance(card, key)
  local center = {}
  for k, v in pairs(CENTERS[key]) do center[k] = v end
  local cfg, old = center.config, card.ability or {}
  card.config = card.config or {}
  card.config.center, card.config.center_key = center, key
  card.ability = { name = center.name, effect = center.effect, set = center.set,
    mult = cfg.mult or 0, h_mult = 0, h_x_mult = cfg.h_x_mult or 0, h_dollars = cfg.h_dollars or 0,
    p_dollars = cfg.p_dollars or 0, x_mult = cfg.Xmult or 1, x_chips = 1, bonus = cfg.bonus or 0,
    extra = cfg.extra, forced_selection = old.forced_selection, perma_bonus = old.perma_bonus or 0,
    perma_mult = old.perma_mult or 0, perma_x_mult = old.perma_x_mult or 0 }
  return card
end

function M.playing(value, suit, opts)
  opts = opts or {}
  local rank = RANKS[value]
  local card = M.card({
    base = { value = value, suit = suit, id = rank.id, nominal = rank.nominal, times_played = 0 },
    edition = opts.edition, seal = opts.seal, debuff = opts.debuff, facing = opts.facing or "front",
    sort_id = opts.sort_id, playing_card = opts.sort_id, children = {},
  })
  require("tests.engine_hand_info").set_base(card)
  return M.enhance(card, opts.enhancement or "c_base")
end

local function dump_source(file)
  local dump = os.getenv("BALATRO_DUMP")
  local skip = require("tests.skip_ledger")
  if not dump or dump == "" then
    skip.bail("engine_cards", 1, "BALATRO_DUMP is unset; set it to the lovely dump directory")
  end
  local fh = io.open(dump .. "/" .. file, "r")
  if not fh then skip.bail("engine_cards", 1, "game dump not readable at " .. dump .. "/" .. file) end
  local src = fh:read("*a")
  fh:close()
  return src
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function compile_span(file, from, to, prefix, suffix, arg)
  local src = dump_source(file)
  local s = assert(src:find(from, 1, true), file .. ": no " .. from)
  local e = assert(src:find(to, s + 1, true), file .. ": no end after " .. from)
  local line = select(2, src:sub(1, s):gsub("\n", "")) + 1
  local chunk = prefix .. string.rep("\n", line - 1) .. src:sub(s, e - 1) .. "\n" .. suffix
  return assert((loadstring or load)(chunk, "@" .. file))(arg)
end

local engine = nil
local function engine_methods()
  if engine then return engine end
  engine = {}
  compile_span("card.lua", "function Card:can_use_consumeable(", "\nfunction Card:check_use(", "local Card = ...;", "", engine)
  compile_span("card.lua", "function Card:check_use(", "\nfunction Card:", "local Card = ...;", "", engine)
  return engine
end

local function refresh_use_pools(card)
  local ability, jokers = card.ability, (G.jokers and G.jokers.cards) or {}
  if ability.consumeable and ability.consumeable.max_highlighted then
    ability.consumeable.mod_num = math.min(5, ability.consumeable.max_highlighted)
  end
  local pool = nil
  if ability.name == "The Wheel of Fortune" or ability.name == "Ectoplasm" or ability.name == "Hex" then
    pool = {}
    for _, v in pairs(jokers) do
      if v.ability.set == "Joker" and not v.edition then pool[#pool + 1] = v end
    end
  end
  if ability.name == "The Wheel of Fortune" then card.eligible_strength_jokers = pool end
  if ability.name == "Ectoplasm" or ability.name == "Hex" then card.eligible_editionless_jokers = pool end
end

function Card:can_use_consumeable(any_state, skip_check)
  refresh_use_pools(self)
  return engine_methods().can_use_consumeable(self, any_state, skip_check)
end

function Card:check_use() return engine_methods().check_use(self) end

local consumable_centers = nil
function M.consumable_centers()
  if not consumable_centers then
    consumable_centers = compile_span("game.lua", "--All Consumeables", "--Vouchers", "return {", "}")
    for key, center in pairs(consumable_centers) do center.key = key end
  end
  return consumable_centers
end

local engine_states = nil
function M.states()
  engine_states = engine_states
    or compile_span("globals.lua", "self.STATES = {", "}", "local self = {};", "} return self.STATES")
  return copy(engine_states)
end

function M.consumable(key, t)
  t = t or {}
  local center = copy(assert(M.consumable_centers()[key], "no vanilla consumable " .. tostring(key)))
  for k, v in pairs(t.center or {}) do center[k] = v end
  t.center = nil
  local cfg = center.config
  local ability = { name = center.name, effect = center.effect, set = center.set, mult = 0, h_mult = 0,
    h_x_mult = 0, h_dollars = 0, p_dollars = 0, t_mult = 0, t_chips = 0, x_mult = 1, h_chips = 0,
    x_chips = 1, h_x_chips = 1, repetitions = 0, h_size = 0, d_size = 0, extra_value = 0, type = "",
    order = center.order, perma_bonus = 0, perma_mult = 0, perma_x_mult = 0, card_limit = 0,
    extra_slots_used = 0, bonus = 0, debuff_sources = {} }
  for k, v in pairs(cfg) do ability[k] = copy(v) end
  ability.consumeable = cfg
  t.ability = ability
  t.config = { center = center, center_key = key }
  return M.card(t)
end

return M
