require("tests.stubs").setup({ love = "zero" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {},
  TIMERS = { REAL = 1, TOTAL = 1 } }

local Engine = require("tests.real_engine")
Engine.load("use-effect-pile-return", 7)

local check, done = require("tests.helpers").harness("use-effect-pile-return")
local UseCard = require("handlers.use_card")

local events
_G.Event = function(cfg) return cfg end
for _, name in ipairs({ "stop_use", "set_consumeable_usage", "update_hand_text", "check_for_unlock", "delay" }) do
  _G[name] = function() end
end
_G.SMODS = _G.SMODS or {}
SMODS.enh_cache = { write = function() end }

local function suit_card(sort_id, value, id, suit)
  local c = Engine.playing_card(sort_id, G.hand)
  c.base = { value = value, suit = suit, id = id }
  c.ability.card_limit, c.ability.extra_slots_used = 0, 0
  c.juice_up = function() end
  c.set_cost = function() end
  return c
end

-- Closing a pack returns hand cards to the deck face down.
local function drain_hand_to_deck()
  while #G.hand.cards > 0 do
    local c = table.remove(G.hand.cards, 1)
    c.area, c.facing = G.deck, "back"
    G.deck.cards[#G.deck.cards + 1] = c
  end
end

local function run_events()
  local i = 1
  while events[i] do events[i].func(); i = i + 1 end
  events = {}
end

local function board()
  events = {}
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(), STATES = Engine.STATES,
    STATE = Engine.STATES.SPECTRAL_PACK, NEURO = { run_generation = 1 }, FUNCS = {},
    TIMERS = { REAL = 1, TOTAL = 1 }, CONTROLLER = { locks = {} },
    P_SEALS = { Red = { config = {} } },
    GAME = { dollars = 5, hands = {}, used_vouchers = {} },
    E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end },
    hand = Engine.area("hand", 1, 8), deck = Engine.area("deck", 1, 52), discard = Engine.area("discard", 1, 52),
    jokers = Engine.area("joker", 1, 5), consumeables = Engine.area("consumeable", 1, 2),
  }
  local ranks = { { "6", 6, "Spades" }, { "Queen", 12, "Hearts" }, { "Jack", 11, "Clubs" } }
  for i, r in ipairs(ranks) do G.hand.cards[i] = suit_card(i, r[1], r[2], r[3]) end
  local deja = Engine.consumable(60, "Deja Vu", "c_deja_vu", "Spectral", { extra = "Red", max_highlighted = 1 }, nil)
  deja.ability.extra = "Red"
  deja.juice_up = function() end
  return deja
end

local function deja_vu_then_close(target_index, target_face_down)
  local deja = board()
  local target = G.hand.cards[target_index]
  if target_face_down then target.facing = "back" end
  G.hand.highlighted = { target }
  local before = UseCard.outcome_snapshot()
  deja:use_consumeable()
  run_events()
  check("the dump's Deja Vu put a Red Seal on the selected card", target.seal == "Red", tostring(target.seal))
  drain_hand_to_deck()
  return before, target
end

do
  local before = deja_vu_then_close(1)
  for _, unsettled in ipairs({ false, true }) do
    local msg = UseCard.outcome_suffix(before, unsettled)
    check("Deja Vu's seal on a card the pack close drew back is reported (unsettled=" .. tostring(unsettled) .. ")",
      msg == " -- 6 of Spades gained a Red Seal, then went back into your deck", msg)
  end
end

do
  local before = deja_vu_then_close(1, true)
  local msg = UseCard.outcome_suffix(before, false)
  check("a seal on a face-down hand card is not described", not msg:find("Spades", 1, true)
    and not msg:find("Red", 1, true), msg)
end

done()
