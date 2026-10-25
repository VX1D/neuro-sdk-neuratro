require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("force-target-examples")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Dispatcher = require("core.dispatcher")

LB.CONSUMABLE_TEXT.c_magician = { "Enhances 2 selected cards to Lucky Cards" }
LB.CONSUMABLE_TEXT.c_death = { "Select 2 cards, convert the left card into the right card" }

local function has(text, needle) return (text or ""):find(needle, 1, true) ~= nil end

local function pack_board(consumables)
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards", { keep_consumables = true })
  local cards = { LB.consumable("c_magician", 610), LB.consumable("c_death", 611),
    LB.consumable("c_pluto", 612) }
  for _, c in ipairs(cards) do c.area = G.pack_cards end
  G.pack_cards.cards = cards
  G.booster_pack.cards = cards
  G.consumeables.cards = consumables or {}
  for _, c in ipairs(G.consumeables.cards) do c.area = G.consumeables end
end

do
  pack_board()
  local p = FP.build("SMODS_BOOSTER_OPENED")
  local q = p and p.query or ""
  local s = p and p.state or ""
  check("the pack card rows in the state say how many cards each targets",
    has(s, "1. The Magician (Tarot). Targets 1 to 2 cards. Takeable now:")
      and has(s, "2. Death (Tarot). Targets 2 cards. Takeable now:")
      and not has(s, "3. Pluto (Planet). Targets"), s)
  check("a card that targets nothing gets no target field",
    has(q, 'name "Pluto", area "booster_pack", index 3')
      and not has(q, 'index 3, hand_indices'), q)
  local ok_with = type(Dispatcher.preflight("choose_pack_card",
    { name = "The Magician", area = "booster_pack", index = 1, hand_indices = { 1 } })) == "function"
  local ok_without = type(Dispatcher.preflight("choose_pack_card",
    { name = "The Magician", area = "booster_pack", index = 1 })) == "function"
  check("the pick as the line names it preflights, and without hand_indices it does not",
    ok_with and not ok_without, tostring(ok_with) .. "/" .. tostring(ok_without))
end

do
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  local p = FP.build("SELECTING_HAND")
  local q, s = p and p.query or "", p and p.state or ""
  check("the state says what the owned Hanged Man targets", has(s, "Targets 1 to 2 cards"), s)
  check("no use_consumable example on that frame states the schema's 1-5 ceiling as the card's range",
    not has(q, "hand_indices (1-5") and not has(s, "hand_indices (1-5"), q)
end

done()
