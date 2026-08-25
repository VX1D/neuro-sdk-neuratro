_G.NEURO_TEST = true
local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("confirm-rollback")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local saved_pre_action = Enforce.pre_action
Enforce.pre_action = function() return true end

local function stage_registered_actions(state)
  require("core.action_registry").note_registered(
    require("core.actions").get_valid_actions_for_state(state))
end

local function bridge(reject_result)
  return {
    results = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
      if reject_result then return false, { status = "rejected" } end
      return true
    end,
    send_context = function() return true end,
    record_action_phase = function() return true end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

clock = clock + 20
_G.G = {
  STATE = 2,
  STATES = { MENU = 1, SHOP = 2 },
  GAME = { dollars = 20, current_round = { reroll_cost = 5, free_rerolls = 0 }, modifiers = {} },
  FUNCS = {},
  NEURO = {
    state = "SHOP",
    state_enter_serial = 1,
    decision_serial = 1,
    run_generation = 1,
  },
  jokers = { cards = {} },
}

local card = {
  ability = { set = "Joker", name = "Sale Joker" },
  config = { center = { key = "j_sale", set = "Joker", loc_txt = { name = "Sale Joker" } } },
  sell_cost = 3,
  sort_id = "j_sale",
}
G.jokers.cards = { card }
stage_registered_actions("SHOP")
local sell_calls = 0
G.FUNCS.sell_card = function()
  sell_calls = sell_calls + 1
  G.jokers.cards = {}
end

local function sell_message(id)
  return {
    command = "action", run_generation = 1,
    data = { id = id, name = "sell_card",
      data = { area = "jokers", index = 1, plan = { money_plan = "sell", build_plan = "sell" } } },
  }
end

G.NEURO.last_sell_reject = "sell:1:j_sale"
G.NEURO.last_sell_review_serial = 1

local bA = bridge(true)
local accepted = Dispatcher.validate_message(sell_message("confirm-rollback-a"), bA)
check("case A: sell validates against the armed latch", accepted == true)
check("case A: engine never invoked sell_card since the write was rejected", sell_calls == 0)
check("case A: joker was never removed", #G.jokers.cards == 1)
check("case A: confirmation latch is restored on rollback",
  G.NEURO.last_sell_reject == "sell:1:j_sale", tostring(G.NEURO.last_sell_reject))
check("case A: review serial is restored alongside it",
  G.NEURO.last_sell_review_serial == 1, tostring(G.NEURO.last_sell_review_serial))

G.NEURO.decision_serial = 2
G.NEURO.last_sell_reject = "sell:1:j_sale"
G.NEURO.last_sell_review_serial = 2

local bB = bridge(false)
local accepted_b = Dispatcher.validate_message(sell_message("confirm-rollback-b"), bB)
check("case B: sell validates and is parked awaiting execution", accepted_b == true)
check("case B: latch is consumed while the job is parked (not yet rolled back)",
  G.NEURO.last_sell_reject == nil, tostring(G.NEURO.last_sell_reject))

Dispatcher.abort_prepared("confirm-rollback-b", "test transport boundary")
check("case B: engine never invoked sell_card for the aborted job", sell_calls == 0)
check("case B: joker was never removed by the aborted job", #G.jokers.cards == 1)
check("case B: confirmation latch is restored after abort_prepared",
  G.NEURO.last_sell_reject == "sell:1:j_sale", tostring(G.NEURO.last_sell_reject))
check("case B: review serial is restored alongside it",
  G.NEURO.last_sell_review_serial == 2, tostring(G.NEURO.last_sell_review_serial))

Enforce.pre_action = saved_pre_action
done()
