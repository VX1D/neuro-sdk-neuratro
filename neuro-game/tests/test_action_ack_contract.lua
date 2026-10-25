_G.NEURO_TEST = true

local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("action-ack-contract")
local Dispatcher = require("core.dispatcher")
local json = require("util.neuro_json")
local Enforce = require("tests.helpers").enforce()

local function stage_registered_actions(state)
  require("core.action_registry").note_registered(
    require("core.actions").get_valid_actions_for_state(state))
end

local function bridge(at_result)
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
        seen = at_result and at_result() or nil,
      }
      return true
    end,
    send_context = function(self, message)
      self.events[#self.events + 1] = "context"
      self.contexts[#self.contexts + 1] = message
      return true
    end,
    is_transition_cooldown = function() return false end,
  }
end

local Execute = require("core.execute")
local function route(message, b)
  Dispatcher.route_message(message, b)
  for _ = 1, 400 do
    if Execute.busy() == nil then break end
    clock = clock + 0.05
    require("core.staging").update(0.05)
    G.E_MANAGER:run()
    Execute.step(clock)
  end
end

local function reset(state)
  clock = clock + 20
  local states = require("tests.engine_cards").states()
  _G.G = {
    STATE = states[state],
    STATES = states,
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
  require("tests.helpers").event_manager()
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  stage_registered_actions(state)
end

do
  reset("MENU")
  G.NEURO.persona = "hiyori"
  local b = bridge(function() return G.NEURO.persona end)
  local message = {
    command = "action",
    run_generation = 1,
    data = { id = "ack-order", name = "choose_persona", data = '{"persona":"evil"}' },
  }
  route(message, b)
  check("validation emits one admission result",
    #b.results == 1 and b.results[1].ok == true
      and b.results[1].reason_code == "ACTION_ACCEPTED",
    b.results[1] and (tostring(b.results[1].ok) .. "/" .. tostring(b.results[1].reason_code)) or "none")
  check("callback has not executed before the result", b.results[1] and b.results[1].seen == "hiyori",
    b.results[1] and tostring(b.results[1].seen))
  check("prepared callback executes after admission", G.NEURO.persona == "evil", G.NEURO.persona)
  check("execution follows the admission result, and echoing her own choice sends no context (BEST_PRACTICES.md:8)",
    table.concat(b.events, ",") == "result",
    table.concat(b.events, ","))
end
do
  reset("BLIND_SELECT")
  G.NEURO.decision_serial = 1
  G.GAME.blind_on_deck = "Small"
  G.GAME.round_resets = {
    blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
    blind_choices = { Small = "bl_small" },
    blind_tags = { Small = {} },
  }
  G.P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" } }
  G.blind_select = {}
  local option = { get_UIE_by_ID = function() return nil end }
  G.blind_select_opts = { small = option }
  local skips = 0
  G.FUNCS.skip_blind = function()
    skips = skips + 1
    G.GAME.blind_on_deck = "Big"
  end
  stage_registered_actions("BLIND_SELECT")

  local window = require("tests.helpers").open_force("BLIND_SELECT", { "skip_blind" })
  local rejected_message = require("tests.helpers").inbound_action(
    "skip_blind", "forced-stage-withdraw-rejected", "{}")
  local rejected_bridge = bridge()
  rejected_bridge.withdraw_actions = function() return false end
  route(rejected_message, rejected_bridge)
  check("a rejected disposable withdrawal refuses admission before execution",
    skips == 0 and #rejected_bridge.results == 1 and rejected_bridge.results[1].ok == false,
    tostring(skips) .. "/" .. tostring(rejected_bridge.results[1] and rejected_bridge.results[1].ok))
  check("a rejected disposable withdrawal leaves the source force open for retry",
    require("core.window").current() == window)
  local message = require("tests.helpers").inbound_action("skip_blind", "forced-stage", "{}")
  local b = bridge(function() return skips end)
  local withdrawn
  b.withdraw_actions = function(self, names)
    self.events[#self.events + 1] = "withdraw"
    withdrawn = names
    return true
  end
  route(message, b)
  check("forced disposable validation reports success before execution",
    #b.results == 1 and b.results[1].reason_code == "ACTION_ACCEPTED" and b.results[1].seen == 0,
    tostring(b.results[1] and b.results[1].reason_code) .. "/" .. tostring(b.results[1] and b.results[1].seen))
  check("disposable actions are unregistered before the result (README.md:23-25)",
    b.events[1] == "withdraw" and b.events[2] == "result" and type(withdrawn) == "table",
    table.concat(b.events, ","))
  check("the answered force is closed", require("core.window").current() == nil and window.phase == "ended")
  check("the accepted staged action executes after its source force closes",
    skips == 1 and G.GAME.blind_on_deck == "Big",
    tostring(skips) .. "/" .. tostring(G.GAME.blind_on_deck))
  check("staged execution does not emit a second action result", #b.results == 1, #b.results)
end
do
  reset("SHOP")
  local card = require("tests.engine_cards").card({
    ability = { set = "Joker", name = "Test Joker" },
    config = { center = { key = "j_test", set = "Joker", loc_txt = { name = "Test Joker" } } },
    cost = 5,
    sell_cost = 2,
    sort_id = "j_test",
  })
  G.shop_jokers.cards = { card }
  stage_registered_actions("SHOP")
  local calls = 0
  G.FUNCS.buy_from_shop = function()
    calls = calls + 1
    G.shop_jokers.cards = {}
    G.jokers.cards = { card }
  end
  local b = bridge(function() return calls end)
  local message = {
    command = "action",
    run_generation = 1,
    data = {
      id = "ack-buy",
      name = "buy_from_shop",
      data = json.encode({
        area = "shop_jokers",
        index = 1,
        plan = { money_plan = "Buy this upgrade and preserve the remaining reserve." },
      }),
    },
  }

  route(message, b)
  check("buy validates with one admission result",
    #b.results == 1 and b.results[1].ok == true
      and b.results[1].reason_code == "ACTION_ACCEPTED",
    #b.results)
  check("buy callback is still untouched before the result", b.results[1] and b.results[1].seen == 0,
    b.results[1] and tostring(b.results[1].seen))
  check("buy callback executes once after admission", calls == 1, calls)
  check("buy admission result is not duplicated after execution",
    #b.results == 1 and b.results[1].reason_code == "ACTION_ACCEPTED",
    #b.results)
  local event = G.NEURO.gameplay_journal and G.NEURO.gameplay_journal.ordered[1]
  check("verified buy publishes its captured public event exactly once",
    event and #G.NEURO.gameplay_journal.ordered == 1
      and event.action_id == "ack-buy" and event.kind == "shop_buy"
      and event.public_subject == "Test Joker" and event.paid == 5,
    event and event.public_subject)
end

do
  reset("SHOP")
  local card = require("tests.engine_cards").card({
    ability = { set = "Joker", name = "Sale Joker" },
    config = { center = { key = "j_sale", set = "Joker", loc_txt = { name = "Sale Joker" } } },
    sell_cost = 3,
    sort_id = "j_sale",
  })
  G.jokers.cards = { card }
  do
    local _, review = require("handlers.shop_handlers").handle_sell_card({
      area = "jokers", index = 1, name = "Sale Joker" })
    require("core.gate").delivered(review)
  end
  stage_registered_actions("SHOP")
  local calls = 0
  G.FUNCS.sell_card = function()
    calls = calls + 1
    G.jokers.cards = {}
  end
  local b = bridge(function() return calls end)
  local message = {
    command = "action",
    run_generation = 1,
    data = {
      id = "ack-sell",
      name = "sell_card",
      data = json.encode({
        area = "jokers",
        index = 1,
        plan = {
          money_plan = "Sell this joker and preserve the remaining reserve.",
          build_plan = "Keep the remaining build and replace this slot deliberately.",
        },
      }),
    },
  }
  route(message, b)
  check("sell validates with one admission result",
    #b.results == 1 and b.results[1].ok == true
      and b.results[1].reason_code == "ACTION_ACCEPTED",
    #b.results)
  check("sell callback is still untouched before the result", b.results[1] and b.results[1].seen == 0,
    b.results[1] and tostring(b.results[1].seen))
  check("sell callback executes once after admission", calls == 1, calls)
  check("sell admission result is not duplicated after execution",
    #b.results == 1 and b.results[1].reason_code == "ACTION_ACCEPTED",
    #b.results)
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
  local buy_card = require("tests.engine_cards").card({
    ability = { set = "Joker", name = "Fractional Buy" },
    config = { center = { key = "j_fractional_buy", set = "Joker" } },
    cost = 5.5, sell_cost = 2, sort_id = "fractional-buy",
  })
  G.shop_jokers.cards = { buy_card }
  local _, _, buy_event = ShopHandlers.handle_buy_from_shop({
    _action_id = "fractional-buy", area = "shop_jokers", index = 1,
  })
  check("buy observer preserves an unsupported fractional value for validator refusal",
    buy_event and buy_event.paid == 5.5, buy_event and buy_event.paid)

  reset("SHOP")
  local sell_card = require("tests.engine_cards").card({
    ability = { set = "Joker", name = "Fractional Sell" },
    config = { center = { key = "j_fractional_sell", set = "Joker" } },
    sell_cost = 2.5, sort_id = "fractional-sell",
  })
  G.jokers.cards = { sell_card }
  do
    local _, review = ShopHandlers.handle_sell_card({ area = "jokers", index = 1,
      name = "Fractional Sell" })
    require("core.gate").delivered(review)
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
  local b = bridge(function() return G.NEURO.gameplay_journal == nil end)
  local message = {
    command = "action", run_generation = 1,
    data = { id = fixture.id, name = "reroll_shop",
      data = json.encode({ plan = { money_plan = "Use this reroll and review the resulting offers." } }) },
  }
  route(message, b)
  check(fixture.id .. " validates", b.results[1] and b.results[1].ok == true, b.results[1] and b.results[1].message)
  check(fixture.id .. " has no journal entry before the result", b.results[1] and b.results[1].seen == true)
  local event = G.NEURO.gameplay_journal and G.NEURO.gameplay_journal.ordered[1]
  check(fixture.id .. " publishes the prepared cost after application",
    calls == 1 and event and event.kind == "shop_reroll" and event.paid == fixture.paid
      and event.used_free_reroll == (fixture.free > 0),
    string.format("calls=%s event=%s last=%s failed=%s", tostring(calls), tostring(event and event.paid),
      tostring(G.NEURO.last_action_name), tostring(G.NEURO.last_failed_reason)))
end

do
  reset("SELECTING_HAND")
  local Validate = require("core.validate")
  local b = bridge()
  local real_validate = Validate.validate
  Validate.validate = function() error("validator boom", 0) end
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "crash-1", name = "play_hand", data = '{"indices":[1]}' } }, b)
  Validate.validate = real_validate
  check("a validator crash does not queue the action", Execute.busy() == nil)
  check("a validator crash sends exactly one result", #b.results == 1, #b.results)
  check("a validator crash reports INTERNAL_ERROR rather than bare ACTION_REJECTED",
    b.results[1] and b.results[1].reason_code == "INTERNAL_ERROR",
    b.results[1] and tostring(b.results[1].reason_code))
  check("a validator crash is answered exactly once and redelivery replays the verdict",
    require("core.bridge").tx.get("crash-1") ~= nil)
end

do
  local saved_preflight = Dispatcher.preflight
  Dispatcher.preflight = function()
    G.NEURO.weak_fired_serial = 7
    return nil, "refused by the validator"
  end
  local function refused_admission(delivers)
    reset("MENU")
    local b = bridge()
    if not delivers then
      b.send_action_result = function() return false end
    end
    Dispatcher.route_message({ command = "action", run_generation = 1,
      data = { id = "refused-" .. tostring(delivers), name = "open_run_setup", data = "{}" } }, b)
    return Execute.busy() ~= nil, G.NEURO.weak_fired_serial
  end
  local accepted, serial = refused_admission(false)
  check("an undeliverable refusal puts the spent confirmation back",
    accepted == false and serial == nil, tostring(accepted) .. "/" .. tostring(serial))
  accepted, serial = refused_admission(true)
  check("a delivered refusal keeps what validation consumed",
    accepted == false and serial == 7, tostring(accepted) .. "/" .. tostring(serial))
  Dispatcher.preflight = saved_preflight
end

done()
