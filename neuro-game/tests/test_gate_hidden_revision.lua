_G.NEURO_TEST = true

local STATES = require("tests.engine_cards").states()
local hand = { cards = {} }
local jokers = { cards = {} }
_G.G = {
  NEURO = require("tests.helpers").started_bridge({ state = "SELECTING_HAND", state_enter_serial = 1, decision_serial = 1 }),
  FUNCS = {}, GAME = { dollars = 4, chips = 0, current_round = { hands_left = 3, discards_left = 2 }, hands = {} },
  STATES = STATES, STATE = STATES.SELECTING_HAND, hand = hand, jokers = jokers,
}
require("tests.engine_cards").install_smods({ Mods = {} })

local check, done = require("tests.helpers").harness("gate-hidden-revision")
local Gate = require("core.gate")

local function playing(value, suit, facing)
  return { sort_id = #hand.cards + 1, facing = facing or "front", area = hand,
    base = { value = value, suit = suit }, config = { center = { key = "c_base" } },
    ability = { name = "Default Base", effect = "" } }
end

local function joker(key, extra, facing)
  return { sort_id = 100 + #jokers.cards, facing = facing or "front", area = jokers,
    config = { center = { key = key } }, ability = { name = key, effect = "", extra = extra } }
end

hand.cards = { playing("Ace", "Spades"), playing("King", "Hearts", "back"), playing("4", "Clubs") }
jokers.cards = { joker("j_ride_the_bus", 2), joker("j_green_joker", { hand_add = 1, current_mult = 3 }, "back") }

local base = Gate.context_revision()

local hidden_card, hidden_joker = hand.cards[2], jokers.cards[2]
hidden_card.base.value, hidden_card.base.suit = "2", "Diamonds"
hidden_card.seal, hidden_card.edition, hidden_card.debuff = "Red", { foil = true }, true
hidden_card.config.center = { key = "m_glass" }
check("a face-down hand card's identity is not in the decision key", Gate.context_revision() == base)

hidden_joker.config.center = { key = "j_joker" }
hidden_joker.ability = { name = "Joker", effect = "", extra = 99 }
hidden_joker.edition = { negative = true }
check("a face-down joker's identity and state are not in the decision key", Gate.context_revision() == base)

jokers.cards[1].ability.extra = 3
check("a face-up joker's state still advances the decision key", Gate.context_revision() == base + 1)

hand.cards[3].base.value = "5"
check("a face-up hand card's identity still advances the decision key", Gate.context_revision() == base + 2)

hidden_card.facing = "front"
check("turning a hidden card face-up advances the decision key", Gate.context_revision() == base + 3)

done()
