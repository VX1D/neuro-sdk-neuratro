
if arg and arg[0] and arg[0]:match("test_staging_roundtrip%.lua$") then
  print("test_staging_roundtrip.lua is a module, not a standalone test: it defines M.run() but this file never calls it.")
  print("Run the suite via: luajit tests/run_staging.lua")
  os.exit(2)
end

local M = {}

local function make_bridge()
  local b = { session_id = nil, results = {}, contexts = {} }
  function b:send_action_result(id, ok, message) self.results[#self.results + 1] = { id = id, ok = ok } end
  function b:send_context(_, _) return true end
  function b:register_actions(_) end
  function b:force_actions(_, _, _, _) end
  function b:send(_) end
  return b
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

local function set_state(state)
  G.STATES = G.STATES or {}
  if G.STATES[state] == nil then
    local nx = 0
    for _, v in pairs(G.STATES) do if v > nx then nx = v end end
    G.STATES[state] = nx + 1
  end
  G.STATE = G.STATES[state]
end

local function fresh(Dispatcher, Actions, state)
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro" }
  G.FUNCS = {}
  G.GAME = {
    dollars = 20, bankrupt_at = 0, stake = 1,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5, free_rerolls = 0 },
    round_resets = { ante = 2 },
    blind = { chips = 300, mult = 1 },
    chips = 0, used_vouchers = {},
  }
  G.hand = { cards = hand_cards(5), highlighted = {}, config = { card_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = { juice_card({ ability = { set = "Tarot", name = "The Fool", consumeable = { max_highlighted = 1, min_highlighted = 1 } } }) }, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { juice_card({ cost = 4 }) } }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  G.pack_cards = { cards = { juice_card({ ability = { set = "Tarot", name = "The Fool" } }), juice_card() } }
  G.booster_pack = { cards = G.pack_cards.cards }
  G.OVERLAY_MENU = nil
  set_state(state)
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

local function drive(Staging, bridge, cap)
  for _ = 1, (cap or 400) do
    tick(0.25)
    Staging.update()
    if not Staging.is_busy() then break end
  end
end

function M.run()
  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  local Actions = G.NEURO and G.NEURO.actions
  if not Dispatcher or not Actions then error("staging_rt: wire dispatcher/actions") end
  local Staging = require("core.staging")
  local Tuning = require("core.config")

  print("====================================================")
  print("[stg] staging deferred round-trip suite")
  print("====================================================")

  local fails = {}
  local function fail(s) fails[#fails + 1] = s end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1,2"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    local msg = { command = "action", data = { id = "stg-A", name = "play_hand",
      data = '{"indices":[1,2]}' } }
    if not Staging.should_stage(msg) then fail("A: play_hand should stage") end
    local bridge = make_bridge()
    if not Staging.queue(msg, bridge) then fail("A: queue returned false") end
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("A: want 1 result, got %d", #bridge.results))
    elseif bridge.results[1].id ~= "stg-A" then fail("A: id not echoed") end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-B", name = "discard_hand",
      data = '{"indices":[3]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("B: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1,2,3"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    local TxCache = require("core.tx_cache")
    local executions = 0
    G.FUNCS.play_cards_from_highlighted = function()
      executions = executions + 1
      G.hand.cards = {}
      G.hand.highlighted = {}
      G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    end
    local msg = { command = "action", data = { id = "stg-C", name = "play_hand",
      data = '{"indices":[1,2,3]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    if #bridge.results ~= 1 then fail(string.format("C: queue must ack exactly once, got %d", #bridge.results))
    elseif bridge.results[1].id ~= "stg-C" then fail("C: ack result id not echoed")
    elseif bridge.results[1].ok ~= true then fail("C: ack result should be ok=true (sent before execution)") end
    tick(0.25); Staging.update()
    set_state("SHOP")
    tick(0.25); Staging.update()
    if #bridge.results ~= 1 then fail(string.format("C: cancel must emit no extra result, got %d", #bridge.results)) end
    if Staging.is_busy() then fail("C: staged not cleared after cancel") end
    local settled = TxCache.get("stg-C")
    if not settled or settled.ok ~= true then fail("C: cancel removed the settled success from TxCache") end
    local replay_bridge = make_bridge()
    Dispatcher.route_message({ command = "action", data = { id = "stg-C", name = "play_hand",
      data = '{"indices":[1]}' } }, replay_bridge)
    if #replay_bridge.results ~= 1 or replay_bridge.results[1].id ~= "stg-C"
        or replay_bridge.results[1].ok ~= true then
      fail("C: redelivery of the settled id did not replay its success")
    end
    if executions ~= 0 or Staging.is_busy() then fail("C: settled id redelivery executed or staged again") end
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    G.FUNCS.play_cards_from_highlighted = function()
      executions = executions + 1
      G.hand.cards = {}
      G.hand.highlighted = {}
      G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    end
    local next_bridge = make_bridge()
    if not Staging.queue({ command = "action", data = { id = "stg-C-next", name = "play_hand",
      data = '{"indices":[1]}' } }, next_bridge) then
      fail("C: new decision with a new id could not be queued")
    end
    if #next_bridge.results ~= 1 or next_bridge.results[1].id ~= "stg-C-next"
        or next_bridge.results[1].ok ~= true then
      fail("C: new decision was not acknowledged at queue")
    end
    drive(Staging, next_bridge)
    if executions ~= 1 then fail("C: new decision with a new id did not execute exactly once") end
    if #next_bridge.results ~= 1 then fail("C: execution emitted a second result") end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1,2"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    local msg = { command = "action", data = { id = "stg-D", name = "play_hand",
      data = '{"indices":[1,2]}' } }
    local bridge = make_bridge()
    if not Staging.queue(msg, bridge) then fail("D: first queue failed") end
    local dup = Staging.queue({ command = "action", data = { id = "stg-D", name = "discard_hand",
      data = '{"indices":[4]}' } }, bridge)
    if dup ~= false then fail("D: duplicate id was NOT rejected") end
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("D: want 1 result after dup, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SHOP")
    local PlanGate = require("core.plan_gate")
    G.NEURO.plan = {
      money = "buy the mock joker",
      money_scope = PlanGate.current_economy_scope(),
    }
    G.NEURO.econ_plan_ok = true
    local msg = { command = "action", data = { id = "stg-E", name = "buy_from_shop",
      data = '{"area":"shop_jokers","index":1}' } }
    if not Staging.should_stage(msg) then fail("E: buy_from_shop should stage") end
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("E: want 1 result, got %d", #bridge.results)) end
    tick(5.0)
    local leaked = 0
    if G.NEURO.ai_glow then
      for _ in pairs(G.NEURO.ai_glow) do leaked = leaked + 1 end
    end
    if leaked > 0 then
      fail(string.format("E: %d glow window(s) outlived the buy", leaked))
    end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-F", name = "use_consumable",
      data = '{"area":"consumables","index":1,"hand_indices":[1]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("F: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "TAROT_PACK")
    G.NEURO.state_enter_serial = 1
    require("core.decision_window").evaluate("choose_pack_card")
    local msg = { command = "action", data = { id = "stg-G", name = "choose_pack_card",
      data = '{"area":"pack_cards","index":1}' } }
    if not Staging.should_stage(msg) then fail("G: pack choose_pack_card should stage") end
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("G: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1,2"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    local msg = { command = "action", data = { id = "stg-H", name = "play_hand",
      data = '{"indices":[1,2]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("H: want 1 result, got %d", #bridge.results))
    elseif bridge.results[1].ok ~= true then fail("H: staged action failed with no executor wired (fallback broken)") end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local bridge = make_bridge()
    local exec_calls = 0
    Staging._test.set_validator(function() return true end)
    Staging.set_executor(function(m, b)
      exec_calls = exec_calls + 1
      Staging.reset_run_state()
      if b and b.send_action_result then b:send_action_result(m.data.id, true, "ok") end
    end)

    local logged = {}
    local real_print = print
    _G.print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      logged[#logged + 1] = table.concat(parts, " ")
    end

    Staging.queue({ command = "action", data = { id = "stg-I", name = "play_hand",
      data = '{"indices":[1,2]}' } }, bridge)
    drive(Staging, bridge)

    fresh(Dispatcher, Actions, "SELECTING_HAND")
    Staging.queue({ command = "action", data = { id = "stg-I2", name = "play_hand",
      data = '{"indices":[1,2]}' } }, bridge)
    drive(Staging, bridge)

    _G.print = real_print
    Staging.set_executor(Dispatcher.handle_message)
    Staging._test.set_validator(nil)

    local crashed = nil
    for _, line in ipairs(logged) do
      if line:find("staging update error", 1, true) then crashed = line end
    end
    if crashed then fail("I: reentrant staged clear crashed Staging.update -> " .. crashed) end
    if exec_calls ~= 2 then
      fail(string.format("I: want 2 exec calls (injected executor must survive a run reset), got %d", exec_calls))
    end
    if #bridge.results ~= 2 then
      fail(string.format("I: want 2 results across the reentrant pair, got %d", #bridge.results))
    end
    if Staging.is_busy() then fail("I: staging left busy after reentrant clear") end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local bridge = make_bridge()
    local queued_inner = nil
    Staging._test.set_validator(function() return true end)
    Staging.set_executor(function(m, b)
      if m.data.id == "stg-J" then
        Staging.reset_run_state()
        queued_inner = Staging.queue({ command = "action", data = { id = "stg-J2",
          name = "discard_hand", data = '{"indices":[1]}' } }, b)
      end
      if b and b.send_action_result then b:send_action_result(m.data.id, true, "ok") end
    end)

    Staging.queue({ command = "action", data = { id = "stg-J", name = "play_hand",
      data = '{"indices":[1,2]}' } }, bridge)
    drive(Staging, bridge)
    Staging.set_executor(Dispatcher.handle_message)
    Staging._test.set_validator(nil)

    if queued_inner ~= true then fail("J: the reentrantly staged action was refused") end
    if #bridge.results ~= 2 then
      fail(string.format("J: want 2 results (outer + reentrant), got %d", #bridge.results))
    else
      if bridge.results[1].id ~= "stg-J" or bridge.results[1].ok ~= true then
        fail("J: outer action lost its own result")
      end
      if bridge.results[2].id ~= "stg-J2" or bridge.results[2].ok ~= true then
        fail("J: reentrantly staged action never ran (outer frame clobbered it)")
      end
    end
    if Staging.is_busy() then fail("J: staging left busy after the reentrant pair") end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local bridge = make_bridge()
    Staging._test.set_validator(function() return true end)
    Staging.set_executor(function(m, b)
      if m.data.id == "stg-K" then
        Staging.queue({ command = "action", data = { id = "stg-K2",
          name = "discard_hand", data = '{"indices":[1]}' } }, b)
      end
      if b and b.send_action_result then b:send_action_result(m.data.id, true, "ok") end
    end)

    Staging.queue({ command = "action", data = { id = "stg-K", name = "play_hand",
      data = '{"indices":[1,2]}' } }, bridge)
    drive(Staging, bridge)
    Staging.set_executor(Dispatcher.handle_message)
    Staging._test.set_validator(nil)

    local k_results = 0
    for _, r in ipairs(bridge.results) do if r.id == "stg-K" then k_results = k_results + 1 end end
    if k_results ~= 1 then
      fail(string.format("K: the executing id got %d results, want exactly 1", k_results))
    elseif bridge.results[1].id ~= "stg-K" or bridge.results[1].ok ~= true then
      fail("K: the executing action was cancelled by the reentrant queue")
    end
    if #bridge.results ~= 2 or bridge.results[2].id ~= "stg-K2" or bridge.results[2].ok ~= true then
      fail(string.format("K: want the newer action to run after the current one, got %d results", #bridge.results))
    end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1,2"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    local TxCache = require("core.tx_cache")
    TxCache.reset()
    local executions = 0
    G.FUNCS.play_cards_from_highlighted = function()
      executions = executions + 1
      G.hand.cards = {}
      G.hand.highlighted = {}
      G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    end
    local bridge = make_bridge()
    Staging.queue({ command = "action", data = { id = "stg-L", name = "play_hand",
      data = '{"indices":[1,2]}' } }, bridge)
    if #bridge.results ~= 1 or bridge.results[1].id ~= "stg-L" or bridge.results[1].ok ~= true then
      fail(string.format("L: queue must ack the action exactly once (success=true), got %d", #bridge.results))
    end
    tick(0.25); Staging.update()
    Staging.reset_run_state()
    if #bridge.results ~= 1 then
      fail(string.format("L: reset must not emit a second result, got %d", #bridge.results))
    end
    if Staging.is_busy() then fail("L: staging left busy after reset") end
    local settled = TxCache.get("stg-L")
    if not settled or settled.ok ~= true then fail("L: reset removed the settled success from TxCache") end
    local replay_bridge = make_bridge()
    Dispatcher.route_message({ command = "action", data = { id = "stg-L", name = "play_hand",
      data = '{"indices":[1]}' } }, replay_bridge)
    if #replay_bridge.results ~= 1 or replay_bridge.results[1].id ~= "stg-L"
        or replay_bridge.results[1].ok ~= true then
      fail("L: reset action redelivery did not replay the settled success")
    end
    if executions ~= 0 or Staging.is_busy() then fail("L: settled id redelivery executed or staged again") end

    fresh(Dispatcher, Actions, "SELECTING_HAND")
    G.NEURO.last_quality_reject = "1"
    G.NEURO.last_quality_review_serial = 0
    G.NEURO.weak_fired_serial = 0
    G.FUNCS.play_cards_from_highlighted = function()
      executions = executions + 1
      G.hand.cards = {}
      G.hand.highlighted = {}
      G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    end
    local next_bridge = make_bridge()
    if not Staging.queue({ command = "action", data = { id = "stg-L-next", name = "play_hand",
      data = '{"indices":[1]}' } }, next_bridge) then
      fail("L: new decision with a new id could not be queued after reset")
    end
    drive(Staging, next_bridge)
    if executions ~= 1 then fail("L: new decision with a new id did not execute exactly once") end
    if #next_bridge.results ~= 1 or next_bridge.results[1].id ~= "stg-L-next"
        or next_bridge.results[1].ok ~= true then
      fail("L: new decision did not retain its single queue-time success")
    end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    Staging.reset_run_state()
    local DW = require("core.decision_window")
    local real_would_reject = DW.would_reject
    DW.would_reject = function() error("injected preflight fault") end

    local logged = {}
    local real_print = print
    _G.print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      logged[#logged + 1] = table.concat(parts, " ")
    end
    local ok_stage, staged_or_err = pcall(Staging.should_stage, { command = "action",
      data = { id = "stg-M", name = "choose_pack_card", data = '{"area":"booster_pack","index":1}' } })
    _G.print = real_print
    DW.would_reject = real_would_reject

    if not ok_stage then
      fail("M: a failing preflight escaped should_stage -> " .. tostring(staged_or_err))
    elseif staged_or_err ~= true then
      fail("M: a failing preflight must fall through to staging, got " .. tostring(staged_or_err))
    end
    local reported = false
    for _, line in ipairs(logged) do
      if line:find("staging preflight error (decision window)", 1, true) then reported = true end
    end
    if not reported then fail("M: the preflight fault was never reported") end
  end

  print("====================================================")
  if #fails == 0 then
    print("==== staging-roundtrip: 13/13 cases PASS, 0 FAIL ====")
  else
    print(string.format("==== staging-roundtrip: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails
end

return M
