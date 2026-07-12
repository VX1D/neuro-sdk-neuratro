-- Staging (deferred-action) round-trip. Stageable actions (play/discard/buy/use) don't
-- execute immediately: Staging.queue holds them, Staging.update drives HOVER->EXECUTE over
-- the clock, and EXECUTE calls Dispatcher.handle_message. This asserts the SDK invariant
-- across that deferred path:
--   * an executed stage yields EXACTLY ONE action/result (id echoed)
--   * a cancelled stage (state change / replaced) yields ZERO results and stays RETRYABLE
--     (id not settled), never a spurious or double result
--   * duplicate ids are dropped, not double-staged

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
  for i = 1, n do t[i] = juice_card() end
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
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, rules_sent = true, persona = "neuro" }
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
  tick(1.0)
end

-- drive Staging to completion (or cap); returns results emitted on the bridge
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

  print("====================================================")
  print("[stg] staging deferred round-trip suite")
  print("====================================================")

  local fails = {}
  local function fail(s) fails[#fails + 1] = s end

  -- A: play (multi-card highlight) executes -> exactly one result
  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-A", name = "play_hand",
      data = '{"indices":[1,2]}' } }
    if not Staging.should_stage(msg) then fail("A: play_hand should stage") end
    local bridge = make_bridge()
    if not Staging.queue(msg, bridge) then fail("A: queue returned false") end
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("A: want 1 result, got %d", #bridge.results))
    elseif bridge.results[1].id ~= "stg-A" then fail("A: id not echoed") end
  end

  -- B: discard (single-card highlight) executes -> exactly one result
  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-B", name = "discard_hand",
      data = '{"indices":[3]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("B: want 1 result, got %d", #bridge.results)) end
  end

  -- C: cancel on state change -> EXACTLY ONE (transient false) result so Neuro is not left
  -- hanging, but the id is NOT settled, so a retry re-evaluates. Zero results would hang;
  -- a settled result would replay the stale cancel on retry -- both wrong.
  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-C", name = "play_hand",
      data = '{"indices":[1,2,3]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    tick(0.25); Staging.update()          -- one hover frame
    set_state("SHOP")                      -- live state now differs from state_at_queue
    tick(0.25); Staging.update()           -- should cancel (transient)
    if #bridge.results ~= 1 then fail(string.format("C: cancel must emit exactly 1 result, got %d", #bridge.results))
    elseif bridge.results[1].id ~= "stg-C" then fail("C: cancel result id not echoed")
    elseif bridge.results[1].ok ~= false then fail("C: cancel result should be ok=false") end
    if Staging.is_busy() then fail("C: staged not cleared after cancel") end
    -- retryable: transient cancel must NOT settle the id, so the same id can be re-queued
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local b2 = make_bridge()
    if not Staging.queue({ command = "action", data = { id = "stg-C", name = "play_hand",
      data = '{"indices":[1]}' } }, b2) then
      fail("C: cancelled id could not be re-queued (was wrongly settled)")
    end
    drive(Staging, b2)
  end

  -- D: duplicate id dropped, not double-staged
  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
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

  -- E: buy_from_shop stage executes -> exactly one result
  do
    fresh(Dispatcher, Actions, "SHOP")
    local msg = { command = "action", data = { id = "stg-E", name = "buy_from_shop",
      data = '{"area":"shop_jokers","index":1}' } }
    if not Staging.should_stage(msg) then fail("E: buy_from_shop should stage") end
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("E: want 1 result, got %d", #bridge.results)) end
  end

  -- F: use_card stage executes -> exactly one result
  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-F", name = "use_card",
      data = '{"area":"consumables","index":1,"hand_indices":[1]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("F: want 1 result, got %d", #bridge.results)) end
  end

  -- G: pack pick (use_card in a pack state) executes -> exactly one result. This is the
  -- deferred path that drives the booster confetti/BOOM pick animation.
  do
    fresh(Dispatcher, Actions, "TAROT_PACK")
    local msg = { command = "action", data = { id = "stg-G", name = "use_card",
      data = '{"area":"pack_cards","index":1}' } }
    if not Staging.should_stage(msg) then fail("G: pack use_card should stage") end
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("G: want 1 result, got %d", #bridge.results)) end
  end

  do
    fresh(Dispatcher, Actions, "SELECTING_HAND")
    local msg = { command = "action", data = { id = "stg-H", name = "play_hand",
      data = '{"indices":[1,2]}' } }
    local bridge = make_bridge()
    Staging.queue(msg, bridge)
    drive(Staging, bridge)
    if #bridge.results ~= 1 then fail(string.format("H: want 1 result, got %d", #bridge.results))
    elseif bridge.results[1].ok ~= true then fail("H: staged action failed with no executor wired (fallback broken)") end
  end

  print("====================================================")
  if #fails == 0 then
    print("==== staging-roundtrip: 8/8 cases PASS, 0 FAIL ====")
  else
    print(string.format("==== staging-roundtrip: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails
end

return M
