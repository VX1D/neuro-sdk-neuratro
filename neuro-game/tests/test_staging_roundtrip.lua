
if arg and arg[0] and arg[0]:match("test_staging_roundtrip%.lua$") then
  print("test_staging_roundtrip.lua is a module, not a standalone test: it defines M.run() but this file never calls it.")
  print("Run the suite via: luajit tests/run_staging.lua")
  os.exit(2)
end

local M = {}

local function make_bridge()
  return require("tests.helpers").fake_bridge({ ack = true, register = "noop", force = true, send = true })
end

local function juice_card(o)
  local c = {
    cost = 3, sell_cost = 1,
    ability = { set = "Default", name = "Mock" },
    config = { center = {} },
    base = { value = "10", suit = "Hearts" },
    juice_up = function() end,
    highlight = function() end,
  }
  if o then for k, v in pairs(o) do c[k] = v end end
  return c
end

local function hand_cards(n)
  local t = {}
  for i = 1, n do
    local c = juice_card()
    c.sort_id = i
    t[i] = c
  end
  return t
end

local _clock = 0
local function tick(dt)
  _clock = _clock + dt
  G.TIMERS = G.TIMERS or {}
  G.TIMERS.REAL = _clock
end

local function fresh(Dispatcher, Actions, state)
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", register_actions = function() end }
  G.FUNCS = { get_poker_hand_info = require("tests.helpers").poker_hand_info("Pair") }
  G.GAME = {
    dollars = 20, bankrupt_at = 0, stake = 1,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5, free_rerolls = 0 },
    round_resets = { ante = 2 },
    blind = { chips = 300, mult = 1 },
    chips = 0, used_vouchers = {},
  }
  G.hand = require("tests.helpers").card_area({ cards = hand_cards(5), highlighted = {}, config = { card_limit = 5 } })
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local EngineCards = require("tests.engine_cards")
  G.consumeables = { cards = { EngineCards.consumable("c_lovers", { cost = 3, sell_cost = 1, juice_up = function() end }) },
    config = { card_limit = 2 } }
  G.shop_jokers = { cards = { juice_card({ cost = 4 }) } }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  G.pack_cards = { cards = { EngineCards.consumable("c_hermit", { cost = 3, sell_cost = 1, juice_up = function() end }),
    juice_card() } }
  G.booster_pack = { cards = G.pack_cards.cards }
  G.OVERLAY_MENU = nil
  G.CONTROLLER = { locked = false }
  require("tests.helpers").in_engine_state(state)
  local function remove_highlighted(area)
    local kept = {}
    for _, card in ipairs(area.cards) do
      local selected = false
      for _, marked in ipairs(area.highlighted or {}) do if card == marked then selected = true break end end
      if not selected then kept[#kept + 1] = card end
    end
    area.cards = kept
    area.highlighted = {}
  end
  G.FUNCS.play_cards_from_highlighted = function()
    remove_highlighted(G.hand)
    G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
  end
  G.FUNCS.discard_cards_from_highlighted = function()
    remove_highlighted(G.hand)
    G.GAME.current_round.discards_left = G.GAME.current_round.discards_left - 1
  end
  G.FUNCS.buy_from_shop = function(e)
    for i, card in ipairs(G.shop_jokers.cards) do
      if card == e.config.ref_table then table.remove(G.shop_jokers.cards, i); G.jokers.cards[#G.jokers.cards + 1] = card break end
    end
  end
  G.FUNCS.use_card = function(e)
    for _, source in ipairs({ G.consumeables, G.pack_cards, G.booster_pack }) do
      for i, card in ipairs((source and source.cards) or {}) do
        if card == e.config.ref_table then table.remove(source.cards, i) break end
      end
    end
  end
  Dispatcher.reset_run_state()
  require("tests.helpers").stage_registered(state,
    { "play_hand", "discard_hand", "sell_card", "buy_from_shop", "use_consumable" })
  tick(3.0)
end

local function drive(Staging, cap)
  local Execute = require("core.execute")
  for _ = 1, (cap or 400) do
    tick(0.25)
    Staging.update()
    Execute.step(G.TIMERS.REAL)
    if not Staging.is_busy() and not Execute.busy() then break end
  end
end

local function route(Dispatcher, id, name, data, bridge)
  bridge = bridge or make_bridge()
  Dispatcher.route_message({ command = "action", data = { id = id, name = name,
    data = require("tests.helpers").with_card_names(name, data) } }, bridge)
  return bridge
end

local function counting_play(counter)
  G.FUNCS.play_cards_from_highlighted = function()
    counter.n = counter.n + 1
    G.hand.cards = {}
    G.hand.highlighted = {}
    G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
  end
end

local function quiet_review()
  require("core.config").set("NEURO_CONFIRM_HAND", "off")
  G.NEURO.last_quality_reject = "1,2,3"
  G.NEURO.last_quality_review_serial = 0
  G.NEURO.weak_fired_serial = 0
end

function M.run()
  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  local Actions = G.NEURO and G.NEURO.actions
  if not Dispatcher or not Actions then error("staging_rt: wire dispatcher/actions") end
  local Staging = require("core.staging")
  local Execute = require("core.execute")
  local TxCache = require("core.bridge").tx

  print("====================================================")
  print("[stg] staging deferred round-trip suite")
  print("====================================================")

  local fails = {}
  local function fail(s) fails[#fails + 1] = s end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    local plays = { n = 0 }
    counting_play(plays)
    local bridge = route(Dispatcher, "stg-A", "play_hand", '{"indices":[1,2]}')
    if #bridge.results ~= 1 or bridge.results[1].id ~= "stg-A" or bridge.results[1].ok ~= true then
      fail("A: the admission result must go out before the hover")
    end
    if plays.n ~= 0 or Execute.busy() ~= "staged" then fail("A: play_hand should stage behind its hover") end
    drive(Staging)
    if plays.n ~= 1 then fail("A: the staged play did not run exactly once") end
    if #bridge.results ~= 1 then fail(string.format("A: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local bridge = route(Dispatcher, "stg-B", "discard_hand", '{"indices":[3]}')
    drive(Staging)
    if #bridge.results ~= 1 then fail(string.format("B: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    local plays = { n = 0 }
    counting_play(plays)
    local bridge = route(Dispatcher, "stg-C", "play_hand", '{"indices":[1,2,3]}')
    tick(0.25); Staging.update(); Execute.step(G.TIMERS.REAL)
    require("tests.helpers").in_engine_state("SHOP")
    tick(0.25); Staging.update(); Execute.step(G.TIMERS.REAL)
    if #bridge.results ~= 1 or bridge.results[1].ok ~= true then
      fail(string.format("C: cancellation must retain the one admission result, got %d", #bridge.results))
    end
    if Execute.busy() then fail("C: the cancelled action is still in flight") end
    if not TxCache.get("stg-C") then fail("C: the admission result is missing from TxCache") end
    local replay = route(Dispatcher, "stg-C", "play_hand", '{"indices":[1]}')
    if #replay.results ~= 0 then fail("C: a redelivered answered id received a second result") end
    if plays.n ~= 0 then fail("C: the cancelled play executed") end
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    counting_play(plays)
    local next_bridge = route(Dispatcher, "stg-C-next", "play_hand", '{"indices":[1]}')
    drive(Staging)
    if plays.n ~= 1 then fail("C: a new decision with a new id did not execute exactly once") end
    if #next_bridge.results ~= 1 or next_bridge.results[1].ok ~= true then
      fail("C: the new decision did not get exactly one success result")
    end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    local bridge = route(Dispatcher, "stg-D", "play_hand", '{"indices":[1,2]}')
    route(Dispatcher, "stg-D", "discard_hand", '{"indices":[4]}', bridge)
    drive(Staging)
    if #bridge.results ~= 1 then fail(string.format("D: want 1 result after dup, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SHOP")
    local PlanGate = require("core.gate")
    G.NEURO.plan = { money = "buy the mock joker", money_scope = PlanGate.current_economy_scope() }
    G.NEURO.econ_plan_ok = true
    local bridge = route(Dispatcher, "stg-E", "buy_from_shop", '{"area":"shop_jokers","index":1}')
    if Execute.busy() ~= "staged" then fail("E: buy_from_shop should stage") end
    drive(Staging)
    if #bridge.results ~= 1 then fail(string.format("E: want 1 result, got %d", #bridge.results)) end
    tick(5.0)
    Staging.update()
    local leaked = 0
    for _ in pairs(G.NEURO.ai_glow or {}) do leaked = leaked + 1 end
    if leaked > 0 then fail(string.format("E: %d glow window(s) outlived the buy", leaked)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local bridge = route(Dispatcher, "stg-F", "use_consumable",
      '{"area":"consumables","index":1,"hand_indices":[1]}')
    drive(Staging)
    if #bridge.results ~= 1 then fail(string.format("F: want 1 result, got %d", #bridge.results)) end
    if bridge.results[1].ok ~= true then fail("F: use_consumable refused: " .. tostring(bridge.results[1].message)) end
  end

  do
    fresh(Dispatcher, Actions, "SMODS_BOOSTER_OPENED")
    G.NEURO.state_enter_serial = 1
    require("tests.helpers").review("choose_pack_card")
    local bridge = route(Dispatcher, "stg-G", "choose_pack_card", '{"area":"pack_cards","index":1}')
    drive(Staging)
    if #bridge.results ~= 1 then fail(string.format("G: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    local plays = { n = 0 }
    counting_play(plays)
    local bridge = route(Dispatcher, "stg-K", "play_hand", '{"indices":[1,2]}')
    local newer = route(Dispatcher, "stg-K2", "discard_hand", '{"indices":[4]}')
    drive(Staging)
    if #bridge.results ~= 1 or bridge.results[1].ok ~= true or plays.n ~= 1 then
      fail("K: a newer action must not cancel the staged one")
    end
    if #newer.results ~= 1 then
      fail("K: a newer action during the hover is answered with a wait")
    end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    local plays = { n = 0 }
    counting_play(plays)
    local bridge = route(Dispatcher, "stg-L", "play_hand", '{"indices":[1,2]}')
    tick(0.25); Staging.update()
    Dispatcher.reset_run_state()
    drive(Staging)
    if #bridge.results ~= 1 or bridge.results[1].ok ~= true then
      fail(string.format("L: a reset keeps the one admission result, got %d", #bridge.results))
    end
    if plays.n ~= 0 or Execute.busy() then fail("L: the reset action still ran or stayed in flight") end
    local replay = route(Dispatcher, "stg-L", "play_hand", '{"indices":[1]}')
    if #replay.results ~= 0 then fail("L: same-session redelivery emitted a duplicate result") end
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    quiet_review()
    counting_play(plays)
    local next_bridge = route(Dispatcher, "stg-L-next", "play_hand", '{"indices":[1]}')
    drive(Staging)
    if plays.n ~= 1 then fail("L: a new decision with a new id did not execute exactly once") end
    if #next_bridge.results ~= 1 or next_bridge.results[1].ok ~= true then
      fail("L: the new decision did not keep its single success result")
    end
  end

  print("====================================================")
  if #fails == 0 then
    print("==== staging-roundtrip: 10/10 cases PASS, 0 FAIL ====")
  else
    print(string.format("==== staging-roundtrip: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails
end

return M
