_G.NEURO_TEST = true

local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("action-ack-contract")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")

local function stage_registered_actions(state)
  require("core.action_registry").note_registered(
    require("core.actions").get_valid_actions_for_state(state))
end

local function bridge()
  return {
    events = {},
    results = {},
    contexts = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.events[#self.events + 1] = "result"
      self.results[#self.results + 1] = {
        id = id,
        ok = ok,
        message = message,
        reason_code = reason_code,
      }
      return true
    end,
    send_context = function(self, message)
      self.events[#self.events + 1] = "context"
      self.contexts[#self.contexts + 1] = message
      return true
    end,
    record_action_phase = function(self, _, _, phase)
      self.events[#self.events + 1] = phase
      return true
    end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

local function reset(state)
  clock = clock + 20
  local state_id = state == "SHOP" and 2 or 1
  _G.G = {
    STATE = state_id,
    STATES = { MENU = 1, SHOP = 2 },
    GAME = {
      dollars = 20,
      current_round = { reroll_cost = 5, free_rerolls = 0 },
      modifiers = {},
    },
    FUNCS = {},
    NEURO = {
      state = state,
      run_generation = 1,
      state_enter_serial = 1,
      shop_visit_epoch = 1,
      economy_epoch = 1,
      once_serials = {},
    },
    hand = { cards = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
  }
  if state == "SHOP" then G.shop = {} end
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  stage_registered_actions(state)
end

local saved_pre_action = Enforce.pre_action
Enforce.pre_action = function() return true end

do
  reset("MENU")
  G.NEURO.persona = "hiyori"
  local b = bridge()
  local message = {
    command = "action",
    run_generation = 1,
    data = { id = "ack-order", name = "choose_persona", data = '{"persona":"evil"}' },
  }

  local accepted = Dispatcher.validate_message(message, b)
  check("validation prepares an accepted action", accepted == true)
  check("validation sends exactly one positive result", #b.results == 1 and b.results[1].ok == true,
    #b.results)
  check("positive result is neutral before execution", b.results[1] and b.results[1].message == nil,
    b.results[1] and b.results[1].message)
  check("callback has not executed when result is sent", G.NEURO.persona == "hiyori", G.NEURO.persona)
  check("prepare, result, acknowledgement order is fixed",
    table.concat(b.events, ",") == "prepared,result,acknowledged", table.concat(b.events, ","))

  Dispatcher.handle_message(message, b)
  check("prepared callback executes after acknowledgement", G.NEURO.persona == "evil", G.NEURO.persona)
  check("execution emits no second action result", #b.results == 1, #b.results)
  check("execution phase follows the result",
    table.concat(b.events, ","):find("prepared,result,acknowledged,executing", 1, true) == 1,
    table.concat(b.events, ","))
end

do
  reset("SHOP")
  local card = {
    ability = { set = "Joker", name = "Test Joker" },
    config = { center = { key = "j_test", set = "Joker", loc_txt = { name = "Test Joker" } } },
    cost = 5,
    sell_cost = 2,
    sort_id = "j_test",
  }
  G.shop_jokers.cards = { card }
  stage_registered_actions("SHOP")
  local calls = 0
  G.FUNCS.buy_from_shop = function()
    calls = calls + 1
    G.shop_jokers.cards = {}
    G.jokers.cards = { card }
  end
  local b = bridge()
  local message = {
    command = "action",
    run_generation = 1,
    data = {
      id = "ack-buy",
      name = "buy_from_shop",
      data = {
        area = "shop_jokers",
        index = 1,
        plan = { money_plan = "Buy this upgrade and preserve the remaining reserve." },
      },
    },
  }

  local accepted = Dispatcher.validate_message(message, b)
  check("buy validates", accepted == true, b.results[1] and b.results[1].message)
  check("buy ACK does not claim execution or predicted money",
    b.results[1] and b.results[1].ok == true and b.results[1].message == nil,
    b.results[1] and b.results[1].message)
  check("buy callback is still untouched at ACK", calls == 0, calls)
  Dispatcher.handle_message(message, b)
  check("buy callback executes once after ACK", calls == 1, calls)
  check("buy execution emits no second result", #b.results == 1, #b.results)
  local event = G.NEURO.gameplay_journal and G.NEURO.gameplay_journal.ordered[1]
  check("verified buy publishes its captured public event exactly once",
    event and #G.NEURO.gameplay_journal.ordered == 1
      and event.action_id == "ack-buy" and event.kind == "shop_buy"
      and event.public_subject == "Test Joker" and event.paid == 5,
    event and event.public_subject)
end

do
  reset("SHOP")
  local card = {
    ability = { set = "Joker", name = "Sale Joker" },
    config = { center = { key = "j_sale", set = "Joker", loc_txt = { name = "Sale Joker" } } },
    sell_cost = 3,
    sort_id = "j_sale",
  }
  G.jokers.cards = { card }
  do
    local _, review = require("handlers.shop_handlers").handle_sell_card({
      area = "jokers", index = 1, name = "Sale Joker" })
    local CR = require("core.context_review")
    CR.stage(review.context_review_candidate, { status = "written" })
    CR.step_delivery()
  end
  stage_registered_actions("SHOP")
  local calls = 0
  G.FUNCS.sell_card = function()
    calls = calls + 1
    G.jokers.cards = {}
  end
  local b = bridge()
  local message = {
    command = "action",
    run_generation = 1,
    data = {
      id = "ack-sell",
      name = "sell_card",
      data = {
        area = "jokers",
        index = 1,
        plan = {
          money_plan = "Sell this joker and preserve the remaining reserve.",
          build_plan = "Keep the remaining build and replace this slot deliberately.",
        },
      },
    },
  }

  local accepted = Dispatcher.validate_message(message, b)
  check("sell validates", accepted == true, b.results[1] and b.results[1].message)
  check("sell ACK does not predict sale, price, or roster",
    b.results[1] and b.results[1].ok == true and b.results[1].message == nil,
    b.results[1] and b.results[1].message)
  check("sell callback is still untouched at ACK", calls == 0, calls)
  Dispatcher.handle_message(message, b)
  check("sell callback executes once after ACK", calls == 1, calls)
  check("legacy sale text is context after execution, not action result",
    b.contexts[1] and b.contexts[1]:find("After the completed action 'sell_card': Sold: Sale Joker for $3", 1, true) ~= nil,
    b.contexts[1])
  check("sell execution emits no second result", #b.results == 1, #b.results)
  local event = G.NEURO.gameplay_journal and G.NEURO.gameplay_journal.ordered[1]
  check("verified sale publishes its captured public event exactly once",
    event and #G.NEURO.gameplay_journal.ordered == 1
      and event.action_id == "ack-sell" and event.kind == "shop_sell"
      and event.public_subject == "Sale Joker" and event.received == 3,
    event and event.public_subject)
end

do
  local ShopHandlers = require("handlers.shop_handlers")
  reset("SHOP")
  local buy_card = {
    ability = { set = "Joker", name = "Fractional Buy" },
    config = { center = { key = "j_fractional_buy", set = "Joker" } },
    cost = 5.5, sell_cost = 2, sort_id = "fractional-buy",
  }
  G.shop_jokers.cards = { buy_card }
  local _, _, buy_event = ShopHandlers.handle_buy_from_shop({
    _action_id = "fractional-buy", area = "shop_jokers", index = 1,
  })
  check("buy observer preserves an unsupported fractional value for validator refusal",
    buy_event and buy_event.paid == 5.5, buy_event and buy_event.paid)

  reset("SHOP")
  local sell_card = {
    ability = { set = "Joker", name = "Fractional Sell" },
    config = { center = { key = "j_fractional_sell", set = "Joker" } },
    sell_cost = 2.5, sort_id = "fractional-sell",
  }
  G.jokers.cards = { sell_card }
  do
    local _, review = ShopHandlers.handle_sell_card({ area = "jokers", index = 1,
      name = "Fractional Sell" })
    local CR = require("core.context_review")
    CR.stage(review.context_review_candidate, { status = "written" })
    CR.step_delivery()
  end
  local _, _, sell_event = ShopHandlers.handle_sell_card({
    _action_id = "fractional-sell", area = "jokers", index = 1,
  })
  check("sell observer preserves an unsupported fractional value for validator refusal",
    sell_event and sell_event.received == 2.5, sell_event and sell_event.received)
end

for _, fixture in ipairs({
  { id = "ack-reroll-paid", free = 0, paid = 5 },
  { id = "ack-reroll-free", free = 1, paid = 0 },
}) do
  reset("SHOP")
  G.GAME.current_round.free_rerolls = fixture.free
  G.GAME.round_scores = { times_rerolled = { amt = 0 } }
  local calls = 0
  G.FUNCS.reroll_shop = function()
    calls = calls + 1
    if G.GAME.current_round.free_rerolls > 0 then
      G.GAME.current_round.free_rerolls = G.GAME.current_round.free_rerolls - 1
    else
      G.GAME.dollars = G.GAME.dollars - G.GAME.current_round.reroll_cost
    end
    G.GAME.current_round.reroll_cost = G.GAME.current_round.reroll_cost + 1
    G.GAME.round_scores.times_rerolled.amt = G.GAME.round_scores.times_rerolled.amt + 1
  end
  local b = bridge()
  local message = {
    command = "action", run_generation = 1,
    data = { id = fixture.id, name = "reroll_shop", data = {
      plan = { money_plan = "Use this reroll and review the resulting offers." },
    } },
  }
  local accepted = Dispatcher.validate_message(message, b)
  check(fixture.id .. " validates", accepted == true, b.results[1] and b.results[1].message)
  check(fixture.id .. " has no journal entry before execution", G.NEURO.gameplay_journal == nil)
  Dispatcher.handle_message(message, b)
  local event = G.NEURO.gameplay_journal and G.NEURO.gameplay_journal.ordered[1]
  check(fixture.id .. " publishes the prepared cost after application",
    calls == 1 and event and event.kind == "shop_reroll" and event.paid == fixture.paid
      and event.used_free_reroll == (fixture.free > 0),
    string.format("calls=%s event=%s last=%s failed=%s", tostring(calls), tostring(event and event.paid),
      tostring(G.NEURO.last_action_name), tostring(G.NEURO.last_failed_reason)))
end

do
  reset("SELECTING_HAND")
  local Staging = require("core.staging")
  local b = bridge()
  Staging.reset_run_state()
  Staging._test.set_validator(function() error("validator boom", 0) end)
  local queued = Staging.queue({ command = "action", run_generation = 1,
    data = { id = "crash-1", name = "play_hand", data = '{"indices":[1]}' } }, b)
  Staging._test.set_validator(nil)
  check("a validator crash does not queue the action", queued == false)
  check("a validator crash sends exactly one result", #b.results == 1, #b.results)
  check("a validator crash reports INTERNAL_ERROR rather than bare ACTION_REJECTED",
    b.results[1] and b.results[1].reason_code == "INTERNAL_ERROR",
    b.results[1] and tostring(b.results[1].reason_code))
  check("a validator crash is answered exactly once and redelivery replays the verdict",
    require("core.tx_cache").get("crash-1") ~= nil)
end

Enforce.pre_action = saved_pre_action
done()
