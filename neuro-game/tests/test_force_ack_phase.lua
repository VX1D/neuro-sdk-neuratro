-- Driven through the real Orchestrator, not a dispatcher mock, which misses the arming loop re-offering the same decision one debounce later. Per SPECIFICATION.md:184-188, ACKNOWLEDGED covers success=true-with-reason: the exchange ends but the decision isn't made.
_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-ack-phase")

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7, MENU = 11 }

local CLOCK = 1000

local forces, registered, unregistered = {}, {}, {}
local register_calls, unregister_calls = 0, 0
local wire = {}
local results = {}
local contexts = {}

local play_card = require("tests.helpers").play_card

local function bridge_stub()
  return {
    send_action_result = function(_, id, ok, message, code)
      results[#results + 1] = { id = id, ok = ok, message = message, code = code }
    end,
    send_context = function(_, ctx, silent)
      contexts[#contexts + 1] = { text = ctx, silent = silent }
    end,
    register_actions = function() end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Helpers = require("tests.helpers")

local function board(state_name)
  _G.G = {
    STATE = STATES[state_name], STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = CLOCK }, SETTINGS = { GAMESPEED = 1 },
    OVERLAY_MENU = nil, screenwipe = nil,
    GAME = {
      dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, STOP_USE = 0,
      blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Small Blind" },
      hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_hook = { key = "bl_hook", name = "The Hook" } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces, registered, unregistered, results, contexts = {}, {}, {}, {}, {}
  register_calls, unregister_calls = 0, 0
  wire = {}
  local live = {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = state_name,
    update = function() end,
    send_context = function() end,
    register_actions = function(_, defs)
      register_calls = register_calls + 1
      local seen = {}
      for _, d in ipairs(defs or {}) do
        registered[#registered + 1] = d.name or d
        seen[d.name or d] = true
      end
      local stale = {}
      for n in pairs(live) do
        if not seen[n] then stale[#stale + 1] = n end
      end
      if #stale > 0 then G.NEURO:_unregister_now(stale) end
      wire[#wire + 1] = { kind = "register", set = seen, t = G.TIMERS.REAL }
      for n in pairs(seen) do live[n] = "sig" end
    end,
    unregister_actions = function(_, names) G.NEURO:_unregister_now(names) end,
  }
  function G.NEURO:_unregister_now(names)
    unregister_calls = unregister_calls + 1
    local seen = {}
    for _, n in ipairs(names or {}) do
      unregistered[#unregistered + 1] = n
      seen[n] = true
      live[n] = nil
    end
    wire[#wire + 1] = { kind = "unregister", set = seen, t = G.TIMERS.REAL }
  end
  G.NEURO._registered_sigs = live
  G.NEURO._desired_action_names = require("core.orchestrator").desired_action_names
  G.NEURO.retract_undesired = require("core.bridge").retract_undesired
  function G.NEURO:force_actions(_ctx, _query, actions)
    G.NEURO.force_generation = tonumber(G.NEURO.run_generation)
    forces[#forces + 1] = { t = G.TIMERS.REAL, state = G.NEURO.force_state,
      actions = table.concat(actions, ",") }
    local seen = {}
    for _, n in ipairs(actions or {}) do seen[n] = true end
    wire[#wire + 1] = { kind = "force", set = seen, t = G.TIMERS.REAL }
  end
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("ack-phase")
  require("core.tx_cache").reset()
end

local Orch = require("core.orchestrator")

local function tick_for(seconds)
  for _ = 1, math.floor(seconds / 0.1) do
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) break end
  end
end

local answer_n = 0
-- Staleness is a property of the open question, not of the frame: SPECIFICATION.md:222-236 gives an
-- inbound action only id/name/data, so the fixture ages the offer instead of stamping the answer.
local function frame(name, payload, stale_generation)
  answer_n = answer_n + 1
  Helpers.stage_registered(nil, { name })
  if stale_generation then G.NEURO.force_generation = stale_generation end
  return { command = "action",
    data = { id = "ack-" .. answer_n, name = name, data = payload } }
end

local function refresh_offer()
  G.NEURO.force_generation = tonumber(G.NEURO.run_generation)
end

local function answer(bridge, name, payload)
  Dispatcher.handle_message(frame(name, payload), bridge)
  return results[#results]
end

local function route(bridge, name, payload, generation)
  Dispatcher.route_message(frame(name, payload, generation), bridge)
  return results[#results]
end

local function phase() return require("tests.helpers").force_phase(FS) end

local function shop_board()
  board("SHOP")
  G.shop = {}
  G.shop_jokers.cards[1] = {
    ability = { set = "Joker", name = "Joker" },
    config = { center = { key = "j_joker", set = "Joker" } },
    cost = 4, sell_cost = 2, sort_id = 91,
    juice_up = function() end, highlight = function() end,
  }
  G.FUNCS.buy_from_shop = function() end
  G.FUNCS.reroll_shop = function() end
  G.FUNCS.toggle_shop = function() end
end

local BAD_PLAY = '{"indices":[1,2,99]}'   -- index 99 does not exist -> INVALID_SELECTION, every time
local BAD_BUY = '{"area":"shop_jokers","index":99,"plan":{"money_plan":"save up"}}'
local STREAK = 3                          -- refusals before the rejection streak acknowledges

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("A: the arming loop opens exactly one window", #forces == 1, #forces)
  check("A: and it offers the action under test",
    forces[1] and forces[1].actions:find("play_hand", 1, true) ~= nil,
    forces[1] and forces[1].actions)

  local unregistered_before = #unregistered
  for i = 1, STREAK do
    local r = answer(b, "play_hand", BAD_PLAY)
    check("A: refusal " .. i .. " is unsuccessful, as SPECIFICATION.md:184 requires",
      r.ok == false and r.code == "INVALID_SELECTION", tostring(r.code) .. "/" .. tostring(r.ok))
    check("A: and a refused answer leaves the offer standing in FORCED",
      phase() == Window.FORCED, phase())
  end

  local acked = answer(b, "play_hand", BAD_PLAY)
  check("A: past the streak the same refusal acknowledges (SPEC:187-188 -- success plus the reason)",
    acked.ok == true and acked.code == "INVALID_SELECTION",
    tostring(acked.code) .. "/" .. tostring(acked.ok))
  check("A: the acknowledged answer still carries the refusal prose",
    type(acked.message) == "string" and acked.message ~= "", tostring(acked.message))
  check("A: the offer moves to ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())
  check("A: nothing is left in flight on the wire", G.NEURO.force_inflight == false,
    tostring(G.NEURO.force_inflight))
  check("A: the decision was never made, so its serial does not move",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))
  check("A: the offer keeps its actions -- ACKNOWLEDGED withdraws nothing",
    #unregistered == unregistered_before, table.concat(unregistered, ","))
  check("A: and it does not ask to be re-armed", not G.NEURO.force_dirty,
    tostring(G.NEURO.force_dirty))

  local before = #forces
  tick_for(60)
  check("A: a minute of ticks asks the same question no second time, while the budget holds",
    #forces == before, #forces .. " forces after " .. before)
  check("A: the offer is still standing and still answerable",
    phase() == Window.ACKNOWLEDGED and FS.is_forced_action("play_hand"), phase())

  local spent = answer(b, "play_hand", BAD_PLAY)
  check("A: a further acknowledgement in the same decision spends the budget",
    spent.ok == true and G.NEURO.force_last_result == "ack_exhausted",
    tostring(spent.ok) .. "/" .. tostring(G.NEURO.force_last_result))
  check("A: spending it ends the offer -- ack_exhausted tears the window down",
    phase() == Window.ENDED, phase())
  check("A: and still decides nothing, so the serial stays put",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))
  tick_for(20)
  check("A: the game comes back with the question instead of going quiet for good",
    #forces == before + 1, #forces)
  check("A: and the fresh offer carries the full action list, not a narrowed one",
    forces[#forces] and forces[#forces].actions == forces[before].actions,
    forces[#forces] and forces[#forces].actions)
end

-- SPECIFICATION.md:234-236 requires success=false for a malformed payload, and :184 hands the retry to the caller, so the game keeps answering without asking anything new -- that's the contract working, not a livelock.
do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before = #forces
  local refused = 0
  for _ = 1, 47 do
    local r = answer(b, "play_hand", '{"indices":[1,2,3,4,5,6]}')
    if r and r.ok == false and r.code == "SCHEMA_INVALID" then refused = refused + 1 end
  end
  check("identical invalid payloads receive only the bounded SDK retry budget", refused == 3, refused)
  check("the bounded streak terminally acknowledges nonexecution and closes the retrying force",
    phase() ~= Window.FORCED, phase())
  tick_for(60)
  check("after bounded acknowledgement the game may issue one fresh force, not livelock the old one",
    #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, STREAK + 1 do answer(b, "play_hand", BAD_PLAY) end
  check("B: the fixture reached ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())

  local serial_before = G.NEURO.decision_serial
  local r = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("B: a correct in-offer answer after the acknowledgement is accepted",
    r.ok == true and r.code == nil, tostring(r.code) .. "/" .. tostring(r.ok))
  check("B: it bumps the decision serial by exactly one",
    G.NEURO.decision_serial == serial_before + 1,
    tostring(serial_before) .. " -> " .. tostring(G.NEURO.decision_serial))
  check("B: and it ends the window", phase() == Window.ENDED, phase())

  local before = #forces
  tick_for(20)
  check("B: with the decision made, the next question is asked", #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local ALIEN = "florblegorb_not_real"
  check("C: the offer under test does not contain the name we are about to send",
    forces[1] and forces[1].actions:find(ALIEN, 1, true) == nil,
    forces[1] and forces[1].actions)

  local serial_before = G.NEURO.decision_serial
  local before = #forces
  local acked = 0
  for _ = 1, 30 do
    local r = route(b, ALIEN, "{}", 99)
    if r and r.ok == true and r.code == "STALE_GENERATION" then acked = acked + 1 end
    tick_for(1)
  end
  check("C: the fixture really produces thirty terminal acknowledgements", acked == 30, acked)
  check("C: an alien name does not close the standing offer", phase() == Window.FORCED, phase())
  check("C: nor spend its serial", G.NEURO.decision_serial == serial_before,
    tostring(G.NEURO.decision_serial))
  check("C: and no second question goes out", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("the standing offer really contains the name the stale frame carries",
    FS.is_forced_action("play_hand") and phase() == Window.FORCED, phase())

  local serial_before = G.NEURO.decision_serial
  local before = #forces
  local unregistered_before = #unregistered
  local r = route(b, "play_hand", '{"indices":[1,2]}', 99)
  check("wire success=true and STALE_GENERATION",
    r.ok == true and r.code == "STALE_GENERATION", tostring(r.code) .. "/" .. tostring(r.ok))
  check("phase is still FORCED", phase() == Window.FORCED, phase())
  check("force_inflight=true", G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))
  check("serial unchanged", G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  check("no unregister", #unregistered == unregistered_before, #unregistered)

  tick_for(60)
  check("after 60s still exactly 1 force sent",
    #forces == before, #forces .. " forces after " .. before)

  refresh_offer()
  local good = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("fresh answer with current generation completes decision and bumps serial by 1",
    good.ok == true and G.NEURO.decision_serial == serial_before + 1,
    tostring(serial_before) .. " -> " .. tostring(G.NEURO.decision_serial))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local rounds, forces_at_start = 6, #forces
  local confirms = 0
  for _ = 1, rounds do
    local r = answer(b, "play_hand", '{"indices":[1]}')
    if r and r.ok == true and r.code == "CONFIRMATION_REQUIRED" then confirms = confirms + 1 end
    G.NEURO.play_confirm = nil
    tick_for(20)
  end
  check("D: every round really answered CONFIRMATION_REQUIRED", confirms == rounds, confirms)
  check("D: each intended follow-up gets its own force -- one per confirmation",
    #forces == forces_at_start + rounds, #forces)
  check("D: an intended follow-up never parks the offer in ACKNOWLEDGED",
    phase() ~= Window.ACKNOWLEDGED, phase())
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  b.is_transition_cooldown = function() return true end
  local r = answer(b, "play_hand", '{"indices":[1,2]}')
  check("E: an in-force action during a transition is acknowledged",
    r.ok == true and r.code == "TRANSITION_ACKNOWLEDGED",
    tostring(r.code) .. "/" .. tostring(r.ok))
  check("E: the acknowledgement parks the offer instead of re-arming it",
    phase() == Window.ACKNOWLEDGED, phase())
  local parked = #forces
  tick_for(20)
  check("E: a parked offer is not re-asked one-for-one", #forces == parked, #forces)

  local spent = answer(b, "play_hand", '{"indices":[1,2]}')
  check("E: the next acknowledgement spends the budget",
    spent.ok == true and spent.code == "TRANSITION_ACKNOWLEDGED"
      and G.NEURO.force_last_result == "ack_exhausted",
    tostring(spent.code) .. "/" .. tostring(G.NEURO.force_last_result))
  b.is_transition_cooldown = function() return false end
  tick_for(20)
  check("E: and the game comes back with the question", #forces == parked + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local serial_before = G.NEURO.decision_serial
  local before = #forces
  G.NEURO.llm_paused = true
  local r = route(b, "play_hand", '{"indices":[1,2]}')
  check("E: the paused game answers without asking for a retry (SPEC:187-188)",
    r.ok == true and r.code == "TRANSITION_ACKNOWLEDGED",
    tostring(r.code) .. "/" .. tostring(r.ok))
  check("E: success=true ends the local force exactly as it ends the SDK force",
    phase() == Window.ENDED, phase())
  check("E: nor the serial", G.NEURO.decision_serial == serial_before,
    tostring(G.NEURO.decision_serial))
  check("E: the ended force is rearmed for a fresh question after unpause",
    G.NEURO.force_inflight == false and G.NEURO.force_dirty == true,
    tostring(G.NEURO.force_inflight) .. "/" .. tostring(G.NEURO.force_dirty))
  G.NEURO.llm_paused = nil
  check("E: unpausing alone sends nothing before the next orchestrator tick", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, STREAK + 1 do answer(b, "play_hand", BAD_PLAY) end
  check("F: the fixture reached ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())

  local stale_window = FS.window()
  unregistered, registered = {}, {}
  G.STATE = STATES.SHOP
  G.NEURO.state = "SHOP"
  tick_for(20)
  check("F: the state change ends the acknowledged window",
    stale_window.phase == Window.ENDED, stale_window.phase)
  check("F: it takes the old offer's names off the client",
    table.concat(unregistered, ","):find("play_hand", 1, true) ~= nil,
    table.concat(unregistered, ","))
  check("F: and puts the new state's set on, so the client is never left with none",
    #registered > 0, tostring(#registered))
  check("F: the new state gets to ask its own question",
    forces[#forces] and forces[#forces].state == "SHOP",
    forces[#forces] and tostring(forces[#forces].state))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, STREAK + 1 do answer(b, "play_hand", BAD_PLAY) end
  check("F: the fixture reached ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())

  unregistered = {}
  FS.reconnect()
  check("F: a reconnect ends the acknowledged window too", phase() == Window.ENDED, phase())
  check("F: but unregisters nothing -- the client lost the socket, not the screen",
    #unregistered == 0, table.concat(unregistered, ","))
end

do
  board("SELECTING_HAND")
  G.NEURO.force_window = nil
  check("G: acknowledging nothing reports that nothing was acknowledged",
    FS.acknowledge_offer() == false)

  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  check("G: an offer the client has never been handed cannot have ended its exchange",
    FS.acknowledge_offer() == false and phase() == Window.REGISTERED, phase())
  FS.mark_sent(CLOCK)
  check("G: a sent offer can", FS.acknowledge_offer() == true and phase() == Window.ACKNOWLEDGED,
    phase())
  check("G: the ACK_LIMIT-th acknowledgement invalidates as ack_exhausted instead",
    FS.acknowledge_offer() == true and phase() == Window.ENDED and G.NEURO.force_last_result == "ack_exhausted",
    phase() .. "/" .. tostring(G.NEURO.force_last_result))
end

local function rearm_sent(state_name)
  if G.NEURO.force_cancel_pending then
    CLOCK = CLOCK + FS.CANCEL_SETTLE
    G.TIMERS.REAL = CLOCK
    FS.cancel_pending(CLOCK)
  end
  G.NEURO.force_window = nil
  G.NEURO.force_inflight = false
  FS.arm(state_name, { "play_hand" }, { play_hand = true }, CLOCK)
  FS.mark_sent(CLOCK)
end

do
  board("SELECTING_HAND")
  rearm_sent("SELECTING_HAND")
  check("the first acknowledgement of a decision parks the offer",
    FS.acknowledge_offer() == true and phase() == Window.ACKNOWLEDGED, phase())

  rearm_sent("SELECTING_HAND")
  check("a re-arm inside the same decision does not refill the budget",
    FS.acknowledge_offer() == true and G.NEURO.force_last_result == "ack_exhausted",
    phase() .. "/" .. tostring(G.NEURO.force_last_result))

  G.NEURO.decision_serial = G.NEURO.decision_serial + 1
  rearm_sent("SELECTING_HAND")
  check("a decision that actually moved on gets its park back",
    FS.acknowledge_offer() == true and phase() == Window.ACKNOWLEDGED, phase())

  FS.reconnect()
  rearm_sent("SELECTING_HAND")
  check("and so does the offer after a reconnect -- the client never saw the old one",
    FS.acknowledge_offer() == true and phase() == Window.ACKNOWLEDGED, phase())
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, STREAK + 1 do answer(b, "play_hand", BAD_PLAY) end
  check("ACK: the fixture reached ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())
  local serial_before = G.NEURO.decision_serial
  local before = #forces
  local r = route(b, "play_hand", '{"indices":[1,2]}', 99)
  check("ACK: phase still ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())
  check("ACK: force_inflight=false", G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("ACK: serial unchanged", G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  tick_for(60)
  check("ACK: no new force", #forces == before, #forces)
  refresh_offer()
  local good = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("ACK: subsequent valid action completes decision", good.ok == true and G.NEURO.decision_serial == serial_before + 1, tostring(good.ok))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local serial_before = G.NEURO.decision_serial
  local before = #forces
  local TxCache = require("core.tx_cache")
  local id = "dup-stale-1"
  local msg = { command = "action", data = { id = id, name = "play_hand", data = "{}" } }
  G.NEURO.force_generation = 99
  Dispatcher.route_message(msg, b)
  local r1 = results[#results]
  Dispatcher.route_message(msg, b)
  local r2 = results[#results]
  check("DUP: two consistent wire results acceptable", r1.ok == true and r2.ok == true and r1.code == r2.code, tostring(r1.code))
  check("DUP: force count unchanged", #forces == before, #forces)
  check("DUP: serial unchanged", G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  check("DUP: TxCache entry exists and is stable", TxCache.get(id) ~= nil, tostring(TxCache.get(id)))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before = #forces
  for i=1,5 do route(b, "play_hand", '{"indices":[1]}', 99) end
  tick_for(1)
  check("BURST: new force = 0", #forces == before, #forces)
  for i=1,5 do
    route(b, "play_hand", '{"indices":[1]}', 99)
    tick_for(1)
  end
  check("PACED: new force = 0", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  answer(b, "play_hand", BAD_PLAY)
  local warning_before = G.NEURO.last_failed_reason
  check("WARN: warning is set", warning_before ~= nil, tostring(warning_before))
  route(b, "play_hand", '{"indices":[1]}', 99)
  check("WARN: warning remains unchanged", G.NEURO.last_failed_reason == warning_before, tostring(G.NEURO.last_failed_reason))
end

do
  shop_board()
  local b = bridge_stub()
  tick_for(10)
  check("the shop offer really contains the action under test",
    forces[#forces] and forces[#forces].actions:find("buy_from_shop", 1, true) ~= nil,
    forces[#forces] and forces[#forces].actions)

  answer(b, "buy_from_shop", BAD_BUY)
  tick_for(1)
  local interleaved = answer(b, "record_plan", '{"hand_plan":"Flush line"}')
  check("the interleaved answer really was accepted", interleaved.ok == true and interleaved.code == nil,
    tostring(interleaved.code) .. "/" .. tostring(interleaved.ok))
  tick_for(1)
  for _ = 1, STREAK - 1 do
    answer(b, "buy_from_shop", BAD_BUY)
    tick_for(1)
  end

  local acked = answer(b, "buy_from_shop", BAD_BUY)
  check("the fourth refusal acknowledges even though they were not consecutive",
    acked.ok == true and acked.code == "TARGET_UNAVAILABLE",
    tostring(acked.code) .. "/" .. tostring(acked.ok))
  check("and parks the offer", phase() == Window.ACKNOWLEDGED, phase())

  local parked = #forces
  tick_for(60)
  check("a minute of ticks asks nothing while the budget holds",
    #forces == parked, #forces .. " forces after " .. parked)
  tick_for(60)
  check("but a park nobody answers again is re-asked, where it used to last for good",
    #forces == parked + 1, #forces .. " forces after " .. parked)
  check("with the full action list it opened with, not a narrowed one",
    forces[#forces].actions == forces[parked].actions, forces[#forces].actions)
  check("and the re-ask is the one force in flight, so nothing may be sent on top of it",
    phase() == Window.FORCED, phase())
  local reasked = #forces
  local remaining = FS.FORCE_LIVENESS_TIMEOUT - (G.TIMERS.REAL - G.NEURO.force_sent_at)
  tick_for(remaining - 5)
  check("the re-ask churns nothing for the whole liveness bound it is given",
    #forces == reasked, #forces .. " forces after " .. reasked)
  tick_for(15)
  check("and past that bound it is asked once more, not left on the wire for good",
    #forces == reasked + 1, #forces .. " forces after " .. reasked)
end

do
  board("SHOP")
  local b = bridge_stub()
  tick_for(10)
  local plan_payload = '{"hand_plan":"Flush line","build_plan":"Upgrade mult","money_plan":"Save $20"}'
  for i = 1, 3 do
    local r = answer(b, "record_plan", plan_payload)
    check("identical send " .. i .. " is still accepted", r.ok == true and r.code == nil,
      tostring(r.code) .. "/" .. tostring(r.ok))
    tick_for(1)
  end
  local capped = answer(b, "record_plan", plan_payload)
  check("the fourth trips the repeat cap and is acknowledged, not refused",
    capped.ok == true and capped.code == "POLICY_ACKNOWLEDGED", tostring(capped.code))
  check("which parks the offer", phase() == Window.ACKNOWLEDGED, phase())

  local parked = #forces
  tick_for(60)
  check("a minute of ticks asks nothing while the budget holds",
    #forces == parked, #forces .. " forces after " .. parked)

  local spent = answer(b, "record_plan", plan_payload)
  check("the second acknowledgement of this decision spends the budget",
    spent.ok == true and G.NEURO.force_last_result == "ack_exhausted",
    tostring(G.NEURO.force_last_result))
  tick_for(10)
  check("and the shop asks again", #forces == parked + 1, #forces)
end

do
  shop_board()
  local b = bridge_stub()
  tick_for(10)

  local spent = false
  for _ = 1, 8 do
    answer(b, "buy_from_shop", BAD_BUY)
    if G.NEURO.force_last_result == "ack_exhausted" then spent = true break end
    tick_for(1)
  end
  check("the fixture spends the decision's budget", spent, tostring(G.NEURO.force_last_result))
  tick_for(10)
  check("and the recovery question goes back out", phase() == Window.FORCED, phase())

  local forces_after, unregister_calls_after = #forces, unregister_calls
  local serial_before = G.NEURO.decision_serial
  for _ = 1, 20 do
    answer(b, "buy_from_shop", BAD_BUY)
    tick_for(1)
  end
  tick_for(20)
  local reasks = #forces - forces_after
  check("twenty further acknowledgements cost two re-asks, not twenty -- the budget doubles",
    reasks == 2, reasks .. " re-asks for 20 answers")
  check("so the client's action set is torn down once per re-ask, never once per answer",
    unregister_calls - unregister_calls_after == reasks,
    (unregister_calls - unregister_calls_after) .. " teardowns for " .. reasks .. " re-asks")
  check("the offer parks instead of being torn down again",
    phase() == Window.ACKNOWLEDGED, phase())
  check("and the parked offer is still hers to answer",
    FS.is_forced_action("buy_from_shop"), phase())
  check("still nothing was decided, so the serial stays put",
    G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
end

do
  board("SELECTING_HAND")
  rearm_sent("SELECTING_HAND")
  FS.acknowledge_offer()
  check("the fixture leaves a spent budget behind",
    (tonumber(G.NEURO.decision_ack_count) or 0) > 0, tostring(G.NEURO.decision_ack_count))
  require("core.neuro_lifecycle").reset_run_state()
  check("a run reset clears it along with the rest of the run's force state",
    (tonumber(G.NEURO.decision_ack_count) or 0) == 0 and G.NEURO.decision_ack_serial == nil,
    tostring(G.NEURO.decision_ack_count) .. "/" .. tostring(G.NEURO.decision_ack_serial))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  contexts = {}
  local res = answer(b, "play_hand", '{"indices":[99]}')
  check("the below-gate refusal is unsuccessful", res.ok == false, tostring(res.ok))
  check("and it writes nothing to the permanent channel", #contexts == 0, #contexts)
  check("the refusal prose still reaches Neuro, as the action result",
    type(res.message) == "string" and #res.message > 0, tostring(res.message))
  check("no raw reason code is handed to the model in readable prose",
    tostring(res.message):find("INVALID SELECTION", 1, true) == nil
      and tostring(res.message):find("INVALID_SELECTION", 1, true) == nil, tostring(res.message))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  contexts = {}

  for i = 1, 10 do
    local r = answer(b, "play_hand", BAD_PLAY)
    if i <= 5 then
      check("send " .. i .. " is refused below the gate",
        r.code == "INVALID_SELECTION", tostring(r.code))
    else
      check("send " .. i .. " closes the expired force without asking the SDK to retry it",
        r.code == "FORCE_EXPIRED" and r.ok == true, tostring(r.code))
    end
  end

  check("the force was torn down mid-burst, so the callable set really did widen",
    require("core.force_state").is_active_action("play_hand", "SELECTING_HAND") ~= true)
  check("and across the whole burst the permanent channel stayed empty",
    #contexts == 0, #contexts)
end

do
  shop_board()
  bridge_stub()
  tick_for(10)
  check("the fixture leaves one force unanswered on the wire",
    #forces == 1 and phase() == Window.FORCED and G.NEURO.force_inflight == true,
    phase() .. "/" .. tostring(G.NEURO.force_inflight))

  local cancelled = {}
  for name in forces[1].actions:gmatch("[^,]+") do cancelled[name] = true end
  check("and the state it moves to shares a name with that offer, which is the production case",
    cancelled.record_plan == true, forces[1].actions)

  G.STATE = STATES.BLIND_SELECT
  G.NEURO.state = "BLIND_SELECT"
  tick_for(20)
  check("the state change does ask the new state's question", #forces == 2, #forces)

  local f1, f2 = nil, nil
  for i = 1, #wire do
    if wire[i].kind == "force" then
      if not f1 then f1 = i elseif not f2 then f2 = i end
    end
  end
  check("both forces are on the recorded wire", f1 ~= nil and f2 ~= nil,
    tostring(f1) .. "/" .. tostring(f2))

  local function covers(fr)
    for name in pairs(fr.set) do if cancelled[name] then return true end end
    return false
  end

  local cancel_at = nil
  for i = f1 + 1, f2 - 1 do
    if wire[i].kind == "unregister" and covers(wire[i]) then cancel_at = i end
  end
  check("the unanswered offer is withdrawn before the second force goes out",
    cancel_at ~= nil, tostring(cancel_at))

  local settle = require("core.force_state").CANCEL_SETTLE
  local early_force = nil
  for i = (cancel_at or f2) + 1, f2 - 1 do
    if wire[i].kind == "force" and covers(wire[i])
      and wire[i].t < wire[cancel_at].t + settle then
      early_force = wire[i].t - wire[cancel_at].t
      break
    end
  end
  check("no successor force lands inside the settle window -- registering is bookkeeping, "
    .. "asking is not", early_force == nil, "forced after " .. tostring(early_force) .. "s")

  check("nor does the second force go out before the withdrawal has settled",
    wire[f2].t - wire[cancel_at].t >= settle,
    (wire[f2].t - wire[cancel_at].t) .. "s < " .. settle .. "s")

  local arming = nil
  for i = 1, f2 - 1 do
    if wire[i].kind == "register" then
      local complete = true
      for name in pairs(wire[f2].set) do
        if not wire[i].set[name] then complete = false break end
      end
      if complete then arming = i end
    end
  end
  check("the second offer's names reach the client in the same tick as the force itself",
    arming ~= nil and (wire[f2].t - wire[arming].t) < 0.15,
    tostring(arming) .. " @ " .. tostring(arming and (wire[f2].t - wire[arming].t)))

  check("the client is never left with an empty action set either",
    #registered > 0, tostring(#registered))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local opened, teardowns = #forces, unregister_calls
  local last_new_force_at = 0
  for i = 1, 40 do
    local before = #forces
    answer(b, "play_hand", BAD_PLAY)
    tick_for(1)
    if #forces > before then last_new_force_at = i end
  end
  local asked = #forces - opened
  check("forty identical refusals decide nothing", G.NEURO.decision_serial == 1,
    tostring(G.NEURO.decision_serial))
  check("the game keeps asking past the budget instead of going quiet for good",
    last_new_force_at > 5, "last question after answer " .. last_new_force_at)
  check("but logarithmically -- forty answers cost four questions, not forty",
    asked == 4, asked .. " questions for 40 answers")
  check("one teardown per question, so there is no unregister/register/force loop",
    unregister_calls - teardowns == asked,
    (unregister_calls - teardowns) .. " teardowns for " .. asked .. " questions")
  check("and the offer is parked, not in flight, when the answers stop",
    phase() == Window.ACKNOWLEDGED, phase())

  local parked = #forces
  tick_for(60)
  check("a minute of that silence is still the anti-churn policy", #forces == parked, #forces)
  tick_for(60)
  check("five minutes of idle no longer ends with nothing asked -- the park is bounded",
    #forces == parked + 1, #forces .. " forces after " .. parked)
  check("the re-ask is unanswered on the wire, which is what stops it repeating",
    phase() == Window.FORCED, phase())
  local reasked = #forces
  local remaining = FS.FORCE_LIVENESS_TIMEOUT - (G.TIMERS.REAL - G.NEURO.force_sent_at)
  tick_for(remaining - 5)
  check("so the re-ask costs nothing further for its whole liveness bound",
    #forces == reasked, #forces .. " forces after " .. reasked)
  tick_for(15)
  check("and past that bound the unanswered re-ask is itself bounded, not permanent",
    #forces == reasked + 1, #forces .. " forces after " .. reasked)
end

done()
