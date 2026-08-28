_G.NEURO_TEST = true

local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }

local check, done = require("tests.helpers").harness("execution-noop-detection")
local Execution = require("core.action_execution")
local Receipt = require("core.action_receipt")
local Shop = require("handlers.shop_handlers")
local Hand = require("handlers.hand_handlers")
local Use = require("handlers.use_card")

local function card(id, set)
  return {
    sort_id = id,
    cost = 0,
    sell_cost = 1,
    ability = { name = "Card " .. tostring(id), set = set or "Default" },
    config = { center = { key = "c_" .. tostring(id), set = set or "Default" } },
    base = { value = "5", suit = "Spades" },
    get_nominal = function(self) return self.sort_id end,
  }
end

local function base(state)
  Receipt.reset("test_case")
  local a, b = card(1, "Joker"), card(2, "Joker")
  _G.G = {
    STATE = 1,
    STATES = { MENU = 1, SHOP = 2, ROUND_EVAL = 3, SELECTING_HAND = 4 },
    NEURO = { state = state or "MENU", run_generation = 4, persona = "neuro", plan_revision = 2,
      seed_pasted = "OLD", once_serials = {}, decision_serial = 1, weak_fired_serial = 1 },
    GAME = {
      dollars = 20,
      pseudorandom = { seed = "ABC123" },
      current_round = { hands_left = 3, discards_left = 2, free_rerolls = 0 },
      round_resets = {
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
      round_scores = { times_rerolled = { amt = 0 } },
      used_vouchers = {},
    },
    FUNCS = {},
    hand = { cards = { card(1), card(2) }, highlighted = {}, config = { highlighted_limit = 5 } },
    jokers = { cards = { a, b }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
    P_CENTER_POOLS = { Back = { { key = "b_red" }, { key = "b_blue" } } },
    PROFILES = { [1] = { MEMORY = { stake = 1 } } },
    SETTINGS = { profile = 1 },
    viewed_stake = 1,
    viewed_collab = "none",
    run_setup_seed = false,
    setup_seed = "OLD",
    challenge_tab = { id = "old" },
    CHALLENGES = { { id = "old" }, { id = "new" } },
  }
  return a, b
end

local async_cases = {
  { "cash_out", {}, function() G.round_eval = {}; G.NEURO.state = "ROUND_EVAL" end },
  { "exit_overlay_menu", {}, function() G.OVERLAY_MENU = {} end },
  { "reroll_boss", {}, function() G.GAME.round_resets.boss_rerolled = false end },
  { "reroll_shop", {}, function() G.shop = {}; G.NEURO.state = "SHOP" end },
  { "select_blind", { blind = "small" }, function() G.NEURO.state = "BLIND_SELECT" end },
  { "setup_run", {}, function() G.OVERLAY_MENU = nil end },
  { "skip_blind", {}, function() G.GAME.blind_on_deck = "Small" end },
  { "skip_booster", {}, function() G.pack_cards = { cards = {} }; G.GAME.pack_choices = 1 end },
  { "start_challenge_run", {}, function() G.NEURO.state = "MENU" end },
  { "start_setup_run", {}, function() G.NEURO.state = "MENU" end },
  { "toggle_shop", {}, function() G.shop = {}; G.NEURO.state = "SHOP" end },
}

for i, spec in ipairs(async_cases) do
  base()
  spec[3]()
  local data = spec[2]
  data._action_id = "async-noop-" .. i
  local result = Execution.wrap(spec[1], data, function() end)()
  check(spec[1] .. " no-op enters verification", Receipt.is_receipt(result))
  Receipt.transition(result, "acknowledged")
  Receipt.transition(result, "executing")
  Receipt.transition(result, "verifying")
  Receipt.update(clock + 20, G.NEURO.run_generation)
  check(spec[1] .. " no-op never becomes applied", result.phase ~= "applied")
end

do
  base("MENU")
  local result = Execution.wrap("start_setup_run", { _action_id = "generation-success" }, function() end)()
  Receipt.transition(result, "acknowledged")
  Receipt.transition(result, "executing")
  Receipt.transition(result, "verifying")
  G.NEURO.run_generation = 5
  Receipt.update(clock + 1, 5)
  check("start run recognizes its own generation change exactly once", result.phase == "applied")
end

local sync_cases = {
  { "choose_persona", { persona = "evil" } },
  { "change_stake", { to_key = 2 } },
  { "change_selected_back", { back = "b_blue" } },
  { "change_challenge_description", { id = "new" } },
  { "paste_seed", { seed = "NEW123" } },
  { "toggle_seeded_run", {} },
  { "set_plan", {} },
  { "set_joker_intents", { intents = { { index = 1, tag = "CORE" } } } },
  { "set_joker_order", { from_index = 1, to_index = 2 } },
  { "copy_seed", {} },
}

for _, spec in ipairs(sync_cases) do
  base()
  local result = Execution.wrap(spec[1], spec[2], function() end)()
  check(spec[1] .. " synchronous no-op is a structural failure",
    Receipt.is_outcome(result) and result.status == "failed")
end

do
  base("SHOP")
  G.STATE = G.STATES.SHOP
  G.shop = {}
  local target = card(10, "Joker")
  G.shop_jokers.cards = { target }
  G.jokers.cards = {}
  G.FUNCS.buy_from_shop = function() return false end
  local exec = Shop.handle_buy_from_shop({ area = "shop_jokers", index = 1, _action_id = "buy-false" })
  local result = exec()
  Receipt.transition(result, "acknowledged")
  Receipt.transition(result, "executing")
  Receipt.transition(result, "verifying")
  Receipt.update(clock, 4)
  check("buy return false is an explicit failure", result.phase == "failed")
end

do
  base("SHOP")
  local target = card(11, "Tarot")
  G.consumeables.cards = { target }
  G.FUNCS.sell_card = function() return false end
  local exec = Shop.handle_sell_card({ area = "consumeables", index = 1, _action_id = "sell-false" })
  local result = exec()
  check("sell return false is a structural failure",
    Receipt.is_outcome(result) and result.status == "failed")
end

local function hand_noop(action)
  base("SELECTING_HAND")
  G.STATE = G.STATES.SELECTING_HAND
  G.GAME.hands = { Pair = { level = 1, chips = 10, mult = 2 } }
  G.FUNCS.get_poker_hand_info = function(selected) return "Pair", {}, { Pair = { selected } }, selected end
  G.FUNCS[action == "play" and "play_cards_from_highlighted" or "discard_cards_from_highlighted"] = function()
    return false
  end
  if action == "play" then
    G.NEURO.play_confirm = {
      signature = Hand.play_signature({ G.hand.cards[1] }),
      content = Hand.play_content({ G.hand.cards[1] }),
      indices = { 1 },
      decision_serial = 1,
      run_generation = G.NEURO.run_generation,
    }
  end
  local handler = action == "play" and Hand.handle_play_hand or Hand.handle_discard_hand
  return handler({ indices = { 1 }, _action_id = action .. "-false" })()
end

for _, action in ipairs({ "play", "discard" }) do
  local result = hand_noop(action)
  check(action .. " callback refusal is a structural failure",
    Receipt.is_outcome(result) and result.status == "failed")
end

do
  base("SELECTING_HAND")
  local target = card(12, "Tarot")
  target.can_use_consumeable = function() return false end
  G.consumeables.cards = { target }
  local _, result = Use.handle_use_card({ area = "consumeables", index = 1, _action_id = "use-refused" })
  check("use_card check_use refusal is rejected before execution",
    type(result) == "table" and result.reason_code == "PRECONDITION_FAILED")
end

done()
