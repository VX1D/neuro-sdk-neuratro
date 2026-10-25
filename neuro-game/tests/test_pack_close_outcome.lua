require("tests.stubs").setup({ love = "zero" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {},
  TIMERS = { REAL = 1, TOTAL = 1 } }

local Engine = require("tests.real_engine")
Engine.load("pack-close-outcome", 4)

local check, done = require("tests.helpers").harness("pack-close-outcome")
local UseCard = require("handlers.use_card")

local events
_G.Event = function(cfg) return cfg end
for _, name in ipairs({ "stop_use", "set_consumeable_usage", "update_hand_text", "check_for_unlock", "delay" }) do
  _G[name] = function() end
end
_G.pseudoseed = function(key) return key end
_G.pseudorandom_element = function(pool) return pool[1] end

-- Ectoplasm writes hand size through SMODS card_limits, not the live card_limit field.
local function smods_area(kind, limit)
  local area = Engine.area(kind, 5, limit)
  area.config.card_limits = { base = limit, mod = 0, total_slots = limit }
  return area
end

-- SMODS folds card_limits.mod into the live limit on its next update.
local function smods_update(area)
  local l = area.config.card_limits
  l.total_slots = l.base + l.mod
  area.config.card_limit = l.total_slots
end

local function suit_card(sort_id, value, id, suit, area)
  local c = Engine.playing_card(sort_id, area)
  c.base = { value = value, suit = suit, id = id }
  return c
end

local function drain_one_to_deck()
  local c = table.remove(G.hand.cards, 1)
  c.area, c.facing = G.deck, "back"
  G.deck.cards[#G.deck.cards + 1] = c
end

local function board()
  events = {}
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(), STATES = Engine.STATES,
    STATE = Engine.STATES.SPECTRAL_PACK, NEURO = { run_generation = 1 }, FUNCS = {},
    TIMERS = { REAL = 1, TOTAL = 1 },
    GAME = { dollars = 5, hands = {}, used_vouchers = {} },
    E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end },
    hand = smods_area("hand", 8), deck = Engine.area("deck", 1, 52),
    jokers = Engine.area("joker", 1, 5), consumeables = Engine.area("consumeable", 1, 2),
  }
  local summit = setmetatable({ sort_id = 50, facing = "front", area = G.jokers, children = {},
    ability = { set = "Joker", name = "Mystic Summit" },
    config = { center = { key = "j_mystic_summit", set = "Joker", name = "Mystic Summit" } } }, Card)
  summit.set_edition = function(self, edition) self.edition = { negative = true, type = "negative" } end
  G.jokers.cards[1] = summit
  local ranks = { { "Ace", 14, "Diamonds" }, { "Queen", 12, "Hearts" }, { "Jack", 11, "Spades" } }
  for i, r in ipairs(ranks) do G.hand.cards[i] = suit_card(i, r[1], r[2], r[3], G.hand) end
  local ecto = Engine.consumable(60, "Ectoplasm", "c_ectoplasm", "Spectral", {}, nil)
  ecto.juice_up = function() end
  ecto.eligible_editionless_jokers = { summit }
  return ecto
end

local function run_events()
  local i = 1
  while events[i] do events[i].func(); i = i + 1 end
  events = {}
end

do
  local ecto = board()
  local before = UseCard.outcome_snapshot()
  ecto:use_consumeable()
  run_events()
  smods_update(G.hand)
  check("the dump's Ectoplasm made the joker Negative and cut hand size",
    G.jokers.cards[1].edition and G.jokers.cards[1].edition.negative and G.hand.config.card_limit == 7,
    tostring(G.hand.config.card_limit))
  drain_one_to_deck()
  local msg = UseCard.outcome_suffix(before, false)
  check("a hand card the pack close drew back to the deck is not reported as the card's effect",
    msg:find("Mystic Summit", 1, true) ~= nil and msg:find("8 -> 7", 1, true) ~= nil
      and msg:find("Ace", 1, true) == nil and msg:find("Jack", 1, true) == nil, msg)
  drain_one_to_deck(); drain_one_to_deck()
  msg = UseCard.outcome_suffix(before, false)
  check("a fully drained hand still reports only Ectoplasm's own changes",
    msg:find("Mystic Summit", 1, true) ~= nil and msg:find("8 -> 7", 1, true) ~= nil
      and msg:find("Ace", 1, true) == nil and msg:find("Jack", 1, true) == nil, msg)
end

do
  board()
  local before = UseCard.outcome_snapshot()
  local gone = table.remove(G.hand.cards, 2)
  gone.area, gone.removed = nil, true
  local msg = UseCard.outcome_suffix(before, false)
  check("a destroyed hand card is still reported", msg:find("Queen of Hearts", 1, true) ~= nil, msg)
end

done()
