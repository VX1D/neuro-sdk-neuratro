_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("pack-payload-facts")

local ForcePack = require("force.force_pack")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")

local function tarot(name, key)
  return { ability = { name = name, set = "Tarot" }, sell_cost = 1, cost = 3,
    config = { center = { key = key, set = "Tarot", loc_txt = { name = name } } } }
end

local function board(dollars, owned)
  local mine = {}
  for i = 1, (owned or 0) do mine[i] = tarot("The Fool", "c_fool") end
  _G.G = {
    STATE = 9, STATES = { TAROT_PACK = 9 }, STATE_COMPLETE = true,
    NEURO = { enabled = true, persona = "neuro", decision_serial = 1, run_generation = 1,
      once_serials = {}, session_once_serials = {}, state_enter_serial = 1, reserved_dollars = 0,
      dispatcher = Dispatcher, actions = Actions },
    FUNCS = {}, TIMERS = { REAL = 100 },
    GAME = { dollars = dollars, round = 1, round_resets = { ante = 1, blind_choices = {} },
      current_round = { hands_left = 3, discards_left = 2 }, modifiers = {}, probabilities = { normal = 1 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = mine, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8 } },
    deck = { cards = {} },
    pack_cards = { cards = { tarot("The Hermit", "c_hermit"), tarot("The Star", "c_star"),
      tarot("The Moon", "c_moon") } },
  }
end

board(9, 0)
local q = ForcePack.build("TAROT_PACK").query
check("the pack payload states the bank", q:find("$9 in bank", 1, true) ~= nil, q)
board(1, 0)
local q1 = ForcePack.build("TAROT_PACK").query
check("the bank is read live, not baked", q1:find("$1 in bank", 1, true) ~= nil, q1)
board(-3, 0)
check("a negative bank still renders",
  ForcePack.build("TAROT_PACK").query:find("-$3 in bank", 1, true) ~= nil,
  ForcePack.build("TAROT_PACK").query)

board(9, 0)
q = ForcePack.build("TAROT_PACK").query
check("the pack list is bound to its area string",
  q:find('booster_pack = the cards in the pack', 1, true) ~= nil, q)
check("with the index range that goes with it",
  q:find("booster_pack = the cards in the pack (1-3)", 1, true) ~= nil, q)
check("the old area-less label is gone",
  q:find("Pack card indices:", 1, true) == nil, q)
check("an area you do not own is not advertised",
  q:find("consumeables = ", 1, true) == nil, q)

board(9, 2)
q = ForcePack.build("TAROT_PACK").query
check("owned consumables are bound to their own area string",
  q:find('consumeables = the Consumables you already own (1-2)', 1, true) ~= nil, q)
check("both areas are named in one place",
  q:find("booster_pack = ", 1, true) ~= nil and q:find("consumeables = ", 1, true) ~= nil, q)

board(9, 0)
G.pack_cards.cards[1].ability.consumeable = { min_highlighted = 1, max_highlighted = 1 }
G.pack_cards.cards[1].config.center.config = { max_highlighted = 1 }
q = ForcePack.build("TAROT_PACK").query
check("no bare N is offered as a hand_indices argument",
  q:find('"hand_indices":%[N') == nil, q)
check("the targeting hint is actually offered and uses bracketed-placeholder notation",
  q:find("hand_indices", 1, true) ~= nil and q:find('"hand_indices":%[<pick ') ~= nil, q)

done()
