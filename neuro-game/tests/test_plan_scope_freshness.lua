_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("plan-scope-freshness")

local states = { SHOP = 1, BLIND_SELECT = 2, SELECTING_HAND = 3 }

local function world(consumable_count)
  local cards = {}
  for i = 1, (consumable_count or 0) do
    cards[i] = { ability = { set = "Planet", name = "Venus" }, config = { center = { set = "Planet" } } }
  end
  _G.G = {
    STATE = states.SHOP, STATES = states,
    GAME = {
      dollars = 12, blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 2,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
    },
    NEURO = { run_generation = 5, economy_epoch = 0, shop_visit_epoch = 0,
      _decision_windows = {}, once_serials = {}, decision_serial = 1, state_enter_serial = 1 },
    FUNCS = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = cards, config = { card_limit = 2 } },
    shop = {}, shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" } },
  }
end

world(2)
local PlanGate = require("core.plan_gate")
local PlanHandler = require("handlers.plan_handlers").handle_set_plan

local function write_money_plan(text)
  local commit = PlanHandler({ money_plan = text })
  if type(commit) == "function" then commit() end
  return type(commit) == "function"
end

PlanGate.enter_shop()
check("a money_plan written with slots full is accepted and current",
  write_money_plan("Free a consumable slot; next buy Celestial Pack") and
    PlanGate.money_plan_is_current(G.NEURO.plan))

G.consumeables.cards = { G.consumeables.cards[1] }
PlanGate.mark_shop_changed("use_card")
check("freeing a consumable slot ages the note whose premise was that slot",
  not PlanGate.money_plan_is_current(G.NEURO.plan))

world(1)
PlanGate.enter_shop()
check("a money_plan written at 1/2 slots is current", write_money_plan("Bank toward interest"))
G.consumeables.cards[2] = { ability = { set = "Tarot", name = "The Fool" } }
check("P2a filling the slot ages it", not PlanGate.money_plan_is_current(G.NEURO.plan))
G.consumeables.cards[2] = nil
check("P2b using that card again restores the situation, and with it the note",
  PlanGate.money_plan_is_current(G.NEURO.plan))

world(1)
PlanGate.enter_shop()
check("a money_plan written while solvent is current", write_money_plan("Buy the cheap joker"))
G.GAME.dollars = 11
check("P3a a purchase that leaves money to spend does not age it",
  PlanGate.money_plan_is_current(G.NEURO.plan))
G.GAME.dollars = 0
check("P3b running the bank dry does age it",
  not PlanGate.money_plan_is_current(G.NEURO.plan))

world(1)
PlanGate.enter_shop()
check("a money_plan is written on entering the shop", write_money_plan("Hold enough for interest"))
local epoch_before = G.NEURO.economy_epoch
PlanGate.mark_shop_changed("buy_from_shop")
check("P4a a plain purchase leaves it current, so the shop stays unlocked",
  G.NEURO.economy_epoch == epoch_before
    and PlanGate.money_plan_is_current(G.NEURO.plan)
    and not PlanGate.buy_locked())
PlanGate.mark_shop_changed("reroll_shop")
check("P4b a reroll does age it -- it destroys the options the plan named",
  not PlanGate.money_plan_is_current(G.NEURO.plan))

local PlanTx = require("core.plan_transaction")
world(1)
PlanGate.enter_shop()
check("a money_plan is written at 1/2 slots", write_money_plan("Bank toward interest"))
local written_scope = G.NEURO.plan.money_scope
local tx = PlanTx.prepare("buy_from_shop", {})
G.consumeables.cards[2] = { ability = { set = "Tarot", name = "The Fool" } }
if tx and tx.plan_commit then tx.plan_commit() end
check("P5a the carried text keeps the stamp it was written under, not the one it committed at",
  G.NEURO.plan.money_scope == written_scope, tostring(G.NEURO.plan.money_scope))
check("P5b so the slot change still ages it instead of reading as a fresh decision",
  not PlanGate.money_plan_is_current(G.NEURO.plan))

done()
