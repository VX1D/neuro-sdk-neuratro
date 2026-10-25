require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("force-ack-phase")

local STATES = require("tests.engine_cards").states()

local CLOCK = 1000

local forces, registered, unregistered = {}, {}, {}
local withdrawals = {}
local wire = {}
local results = {}
local contexts = {}
local function record_context(_, message, silent, receipt)
  contexts[#contexts + 1] = { message = message, silent = silent }
  if receipt then receipt.status = "written" end
  return true
end
local register_calls, unregister_calls = 0, 0

local Helpers = require("tests.helpers")
local play_card = Helpers.play_card

local function bridge_stub()
  local stub = Helpers.stub_bridge({
    send_action_result = Helpers.result_log(results, { "id", "ok", "message", "code" }, true),
    register_actions = "noop", send_context = record_context, is_transition_cooldown = "false",
  })
  if G and G.NEURO then
    G.NEURO.is_transition_cooldown = function() return stub.is_transition_cooldown() end
  end
  return stub
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Win = require("core.window")
local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }

local function consume_highlighted()
  local hand = G and G.hand
  local cards = hand and hand.cards or {}
  for _, selected in ipairs((hand and hand.highlighted) or {}) do
    for i = #cards, 1, -1 do
      if cards[i] == selected then
        table.remove(cards, i)
        break
      end
    end
  end
  if hand then hand.highlighted = {} end
end

local function board(state_name)
  Helpers.orch_board({ state = state_name, clock = CLOCK, states = STATES, edit = function(g)
    g.hand = Helpers.card_area(g.hand)
    g.FUNCS.play_cards_from_highlighted = function()
      consume_highlighted()
      G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    end
    g.FUNCS.discard_cards_from_highlighted = function()
      consume_highlighted()
      G.GAME.current_round.discards_left = G.GAME.current_round.discards_left - 1
    end
  end })
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces, registered, unregistered, results, contexts = {}, {}, {}, {}, {}
  withdrawals = {}
  register_calls, unregister_calls = 0, 0
  local live = {}
  G.NEURO = Helpers.orch_neuro({
    transport_session = "ack-phase-test", transport_epoch = 1,
    dispatcher = Dispatcher, actions = Actions, state = state_name, send_context = record_context,
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
    withdraw_actions = function(_, names)
      local copy = {}
      for i, name in ipairs(names or {}) do copy[i] = name end
      withdrawals[#withdrawals + 1] = copy
      return true
    end,
  })
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
  function G.NEURO:force_actions(_ctx, _query, actions)
    local w = G.NEURO.force_window
    forces[#forces + 1] = { t = G.TIMERS.REAL, state = w and w.state,
      actions = table.concat(actions, ",") }
    local seen = {}
    for _, n in ipairs(actions or {}) do seen[n] = true end
    wire[#wire + 1] = { kind = "force", set = seen, t = G.TIMERS.REAL }
  end
  Win.reset()
  require("core.validate").reset_run_state()
  require("core.bridge").tx.reset()
end

require("core.orchestrator")

local T = require("tests.helpers").orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for = T.tick_for

local answer_n = 0
local function frame(name, payload)
  answer_n = answer_n + 1
  Helpers.stage_registered(nil, { name })
  return Helpers.inbound_action(name, "ack-" .. answer_n, payload)
end

local function answer(bridge, name, payload)
  local msg = frame(name, payload)
  require("core.bridge").tx.open(msg.data.id, name, G.TIMERS.REAL)
  Dispatcher.handle_message(msg, bridge)
  require("core.execute").step(G.TIMERS.REAL)
  return results[#results]
end

local function route(bridge, name, payload)
  Dispatcher.route_message(frame(name, payload), bridge)
  return results[#results]
end

local function phase() return require("tests.helpers").force_phase() end

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

local function end_window(b)
  b.is_transition_cooldown = function() return true end
  answer(b, "play_hand", '{"indices":[1,2]}')
  b.is_transition_cooldown = function() return false end
end

local BAD_PLAY = '{"indices":[1,2,99]}'
local BAD_BUY = '{"area":"shop_jokers","index":99,"plan":{"money_plan":"save up"}}'
local STREAK = 3

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("A: the arming loop opens exactly one window", #forces == 1, #forces)
  check("A: and it offers the action under test",
    forces[1] and forces[1].actions:find("play_hand", 1, true) ~= nil,
    forces[1] and forces[1].actions)

  for i = 1, STREAK do
    local r = answer(b, "play_hand", BAD_PLAY)
    check("A: refusal " .. i .. " is unsuccessful, as SPECIFICATION.md:188 requires",
      r.ok == false and r.code == "INVALID_SELECTION", tostring(r.code) .. "/" .. tostring(r.ok))
    check("A: and a refused answer leaves the offer standing in FORCED",
      phase() == Window.FORCED, phase())
  end

  local still = answer(b, "play_hand", BAD_PLAY)
  check("A: past the old streak the same refusal is still unsuccessful: there is no retry budget",
    still.ok == false and still.code == "INVALID_SELECTION",
    tostring(still.code) .. "/" .. tostring(still.ok))
  check("A: the refusal still carries its prose",
    type(still.message) == "string" and still.message ~= "", tostring(still.message))
  check("A: the force stays standing", phase() == Window.FORCED, phase())
  check("A: the decision was never made, so its serial does not move",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))
  check("A: a refused offer is not withdrawn on the wire", #withdrawals == 0, #withdrawals)

  local before = #forces
  tick_for(5)
  check("A: Neuro retries the standing force, so nothing new is asked",
    #forces == before and phase() == Window.FORCED, #forces .. " forces after " .. before)
  check("A: and the offer still carries the full action list",
    forces[#forces] and forces[#forces].actions == forces[1].actions,
    forces[#forces] and forces[#forces].actions)
end

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
  check("identical invalid payloads are refused success=false every time", refused == 47, refused)
  check("the standing force is not closed by the repeats", phase() == Window.FORCED, phase())
  tick_for(Win.REFUSED_LIVENESS - 10)
  check("and no fresh force is issued on top of it", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  end_window(b)
  check("B: the fixture ended the window", phase() == Window.ENDED, phase())

  local serial_before = G.NEURO.decision_serial
  local r = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("B: a correct answer is admitted before execution",
    r.ok == true and r.code == "ACTION_ACCEPTED", tostring(r.code) .. "/" .. tostring(r.ok))
  check("B: the current decision serial remains stable within the state",
    G.NEURO.decision_serial == serial_before,
    tostring(serial_before) .. " -> " .. tostring(G.NEURO.decision_serial))

  local before = #forces
  tick_for(20)
  check("B: with the decision made, the next question is asked", #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local serial_before = G.NEURO.decision_serial
  local TxCache = require("core.bridge").tx
  local id = "dup-1"
  local msg = { command = "action", data = { id = id, name = "play_hand", data = '{"indices":[1,2,99]}' } }
  TxCache.open(id, "play_hand", G.TIMERS.REAL)
  Dispatcher.handle_message(msg, b)
  local r1 = results[#results]
  Dispatcher.handle_message(msg, b)
  local r2 = results[#results]
  check("DUP: a redelivered id replays its first result",
    r1 and r2 and r1.ok == r2.ok and r1.code == r2.code and r1.message == r2.message, tostring(r1 and r1.code))
  check("DUP: serial unchanged", G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  check("DUP: TxCache entry exists and is stable", TxCache.get(id) ~= nil, tostring(TxCache.get(id)))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local rounds, forces_at_start = 6, #forces
  local codes = {}
  for i = 1, rounds do
    local r = answer(b, "play_hand", '{"indices":[1]}')
    codes[i] = r and r.ok == true and r.code or "retry"
    tick_for(20)
  end
  local followups = 0
  for i = 2, rounds do
    if codes[i] == "POLICY_ACKNOWLEDGED" then followups = followups + 1 end
  end
  check("D: the first answer opens the confirmation and every resend is acknowledged",
    codes[1] == "CONFIRMATION_REQUIRED" and followups == rounds - 1, table.concat(codes, ","))
  check("D: a resend outside the confirmation force leaves that force standing, not re-asked",
    #forces == forces_at_start + 1, #forces)
  check("D: and the follow-up force is the one standing", phase() == Window.FORCED, phase())
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  b.is_transition_cooldown = function() return true end
  local r = answer(b, "play_hand", '{"indices":[1,2]}')
  check("E: an in-force action during a transition is answered success=true with the wait",
    r.ok == true and r.code == "TRANSITION_PENDING",
    tostring(r.code) .. "/" .. tostring(r.ok))
  check("E: and the window ends", phase() == Window.ENDED, phase())
  local parked = #forces
  tick_for(20)
  check("E: an unsettled game is not re-asked", #forces == parked, #forces)

  local again = answer(b, "play_hand", '{"indices":[1,2]}')
  check("E: with no force open, a further answer during the transition is retried (success=false)",
    again.ok == false and again.code == "TRANSITION_PENDING",
    tostring(again.code) .. "/" .. tostring(again.ok))
  check("E: ending the window needs no wire withdrawal", #withdrawals == 0, #withdrawals)
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
    r.ok == true and r.code == "TRANSITION_PENDING",
    tostring(r.code) .. "/" .. tostring(r.ok))
  check("E: success=true ends the local force exactly as it ends the SDK force",
    phase() == Window.ENDED, phase())
  check("E: nor the serial", G.NEURO.decision_serial == serial_before,
    tostring(G.NEURO.decision_serial))
  tick_for(20)
  check("E: nothing is asked while the operator holds the pause", #forces == before, #forces)
  G.NEURO.llm_paused = nil
  tick_for(20)
  check("E: the ended force is asked again after unpause", #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  end_window(b)
  check("F: the fixture ended the window", phase() == Window.ENDED, phase())

  local stale_window = G.NEURO.force_window
  local registered_before = #registered
  unregistered = {}
  G.STATE = STATES.SHOP
  G.shop = {}
  tick_for(20)
  check("F: a state change sends no withdrawal for a force success=true already resolved",
    stale_window.phase == Window.ENDED and #withdrawals == 0, tostring(#withdrawals))
  check("F: the canonical catalogue is additive across the state change",
    #registered == registered_before and #unregistered == 0
      and G.NEURO._registered_sigs.play_hand ~= nil,
    tostring(#registered) .. "/" .. tostring(#unregistered))
  check("F: the SHOP successor is offered",
    #forces == 2 and forces[2].state == "SHOP" and phase() == Window.FORCED,
    #forces .. "/" .. tostring(forces[2] and forces[2].state) .. "/" .. phase())
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  end_window(b)
  unregistered = {}
  require("core.neuro_lifecycle").bump_run_generation("transport reconnected")
  check("F: a reconnect leaves no window", phase() == Window.ENDED, phase())
  check("F: but unregisters nothing -- the client lost the socket, not the screen",
    #unregistered == 0 and #withdrawals == 0, table.concat(unregistered, ","))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  answer(b, "play_hand", BAD_PLAY)
  check("WARN: a retried refusal records its warning", G.NEURO.last_failed_reason ~= nil,
    tostring(G.NEURO.last_failed_reason))
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
  check("the interleaved answer is admitted before execution",
    interleaved.ok == true and interleaved.code == "ACTION_ACCEPTED",
    tostring(interleaved.code) .. "/" .. tostring(interleaved.ok))
  tick_for(10)
  for _ = 1, STREAK do
    answer(b, "buy_from_shop", BAD_BUY)
    tick_for(1)
  end

  local still = answer(b, "buy_from_shop", BAD_BUY)
  check("the fourth refusal is still unsuccessful even though they were not consecutive",
    still.ok == false and still.code == "TARGET_UNAVAILABLE",
    tostring(still.code) .. "/" .. tostring(still.ok))
  check("and the window stays open", phase() == Window.FORCED, phase())

  local parked = #forces
  tick_for(5)
  check("nothing new is asked while the force stands", #forces == parked, #forces .. " forces after " .. parked)
  local reasked = #forces
  local reasked_window = G.NEURO.force_window
  tick_for(Win.REFUSED_LIVENESS - 5)
  check("the standing force churns nothing for the whole liveness bound it is given",
    #forces == reasked, #forces .. " forces after " .. reasked)
  tick_for(6)
  check("past that bound the unanswered force is withdrawn (README.md:27)",
    reasked_window.phase == Window.ENDED and reasked_window.ended_by == "liveness_timeout"
      and #withdrawals == 1,
    tostring(reasked_window.phase) .. "/" .. tostring(reasked_window.ended_by) .. "/" .. #withdrawals)
  tick_for(5)
  check("and the successor force is offered",
    #forces == reasked + 1 and phase() == Window.FORCED, #forces .. "/" .. phase())
end

do
  board("SHOP")
  G.shop = {}
  local b = bridge_stub()
  tick_for(10)
  local plan_payload = '{"hand_plan":"Flush line","build_plan":"Upgrade mult","money_plan":"Save $20"}'
  for i = 1, 3 do
    local r = answer(b, "record_plan", plan_payload)
    check("identical send " .. i .. " is admitted before execution",
      r.ok == true and r.code == "ACTION_ACCEPTED",
      tostring(r.code) .. "/" .. tostring(r.ok))
    tick_for(10)
  end
  local capped = answer(b, "record_plan", plan_payload)
  check("the fourth trips the repeat cap and is acknowledged as a forced answer",
    capped.code == "POLICY_ACKNOWLEDGED" and capped.ok == true, tostring(capped.code))
  check("which resolves the shop force", phase() == Window.ENDED, phase())

  local parked = #forces
  tick_for(10)
  check("and the decision is asked again by exactly one force", #forces == parked + 1, #forces)
end

do
  shop_board()
  local b = bridge_stub()
  tick_for(10)
  local opened = #forces
  for _ = 1, STREAK do
    answer(b, "buy_from_shop", BAD_BUY)
    tick_for(1)
  end
  check("success=false refusals ask nothing new; Neuro retries the standing force (SPEC:188)",
    #forces == opened and phase() == Window.FORCED, #forces .. "/" .. phase())

  local forces_after, unregister_calls_after = #forces, unregister_calls
  local serial_before = G.NEURO.decision_serial
  local refused_n = 0
  for _ = 1, 20 do
    local r = answer(b, "buy_from_shop", BAD_BUY)
    if r and r.ok == false then refused_n = refused_n + 1 end
    tick_for(1)
  end
  check("twenty more refusals are all success=false and ask nothing new",
    refused_n == 20 and #forces == forces_after and phase() == Window.FORCED,
    refused_n .. " refused, " .. (#forces - forces_after) .. " new forces")
  check("canonical action registration is not torn down by repeated refusals",
    unregister_calls - unregister_calls_after == 0 and #withdrawals == 0,
    (unregister_calls - unregister_calls_after) .. " teardowns")
  check("still nothing was decided, so the serial stays put",
    G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  require("core.context_delivery").event("ack-phase-probe", "probe", { occurrence = CLOCK })
  check("the capture records a persistent context frame", #contexts == 1 and contexts[1].message == "probe",
    #contexts)
  contexts = {}
  local res = answer(b, "play_hand", '{"indices":[99]}')
  tick_for(1)
  check("the below-gate refusal is unsuccessful", res.ok == false, tostring(res.ok))
  check("and it writes nothing to the persistent channel", #contexts == 0,
    contexts[1] and contexts[1].message)
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
  for i = 1, STREAK do
    contexts = {}
    local r = answer(b, "play_hand", BAD_PLAY)
    tick_for(1)
    check("send " .. i .. " is refused below the gate and writes nothing persistent",
      r.code == "INVALID_SELECTION" and r.ok == false and #contexts == 0,
      tostring(r.code) .. "/" .. tostring(r.ok) .. "/" .. tostring(contexts[1] and contexts[1].message))
  end
  for i = STREAK + 1, 10 do
    local r = answer(b, "play_hand", BAD_PLAY)
    check("send " .. i .. " is still refused below the gate with success=false",
      r.code == "INVALID_SELECTION" and r.ok == false, tostring(r.code) .. "/" .. tostring(r.ok))
  end
end

do
  shop_board()
  bridge_stub()
  tick_for(10)
  check("the fixture leaves one force unanswered on the wire",
    #forces == 1 and phase() == Window.FORCED, phase())

  local stale_window = G.NEURO.force_window
  local registered_before = #registered
  G.STATE = STATES.BLIND_SELECT
  tick_for(20)
  check("a state change withdraws the already-sent force by unregistering its names (README.md:27)",
    stale_window.phase == Window.ENDED and stale_window.ended_by == "state_changed" and #withdrawals == 1,
    tostring(stale_window.phase) .. "/" .. tostring(stale_window.ended_by) .. "/" .. #withdrawals)
  check("the stable catalogue keeps the SHOP names without omission withdrawal",
    #registered == registered_before and #unregistered == 0
      and G.NEURO._registered_sigs.buy_from_shop ~= nil,
    tostring(#registered) .. "/" .. tostring(#unregistered))
  check("the BLIND_SELECT successor is offered",
    #forces == 2 and forces[2].state == "BLIND_SELECT" and phase() == Window.FORCED,
    #forces .. "/" .. tostring(forces[2] and forces[2].state) .. "/" .. phase())

  local before_reconnect = #forces
  require("core.neuro_lifecycle").bump_run_generation("transport reconnected")
  check("reconnect clears the successor force before re-arming", phase() == Window.ENDED, phase())
  tick_for(20)
  check("reconnect re-offers the new state after reset",
    #forces == before_reconnect + 1
      and forces[#forces].state == "BLIND_SELECT" and phase() == Window.FORCED,
    #forces .. "/" .. tostring(forces[#forces] and forces[#forces].state))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local opened, teardowns = #forces, unregister_calls
  local refused_n = 0
  for _ = 1, 40 do
    local r = answer(b, "play_hand", BAD_PLAY)
    if r and r.ok == false then refused_n = refused_n + 1 end
    tick_for(1)
  end
  local asked = #forces - opened
  check("forty identical refusals decide nothing", G.NEURO.decision_serial == 1,
    tostring(G.NEURO.decision_serial))
  check("every one of them is success=false: there is no retry budget", refused_n == 40, refused_n)
  check("Neuro retries the standing force, so nothing new is asked", asked == 0, asked .. " questions for 40 answers")
  check("canonical action registration is not torn down by repeated refusals",
    unregister_calls - teardowns == 0 and #withdrawals == 0,
    (unregister_calls - teardowns) .. " teardowns")
  check("and the standing force is the one force in flight", phase() == Window.FORCED, phase())
  local reasked = #forces
  local reasked_window = G.NEURO.force_window
  tick_for(Win.REFUSED_LIVENESS - 5)
  check("the standing force costs nothing further before its liveness bound",
    #forces == reasked, #forces .. " forces after " .. reasked)
  tick_for(6)
  check("past that bound the standing force is withdrawn instead of remaining latched",
    reasked_window.phase == Window.ENDED and reasked_window.ended_by == "liveness_timeout"
      and #withdrawals == 1,
    tostring(reasked_window.phase) .. "/" .. tostring(reasked_window.ended_by))
  tick_for(5)
  check("and the successor is offered",
    #forces == reasked + 1 and phase() == Window.FORCED, #forces .. "/" .. phase())
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  G.FUNCS.discard_cards_from_highlighted = function() end
  local r = answer(b, "discard_hand", '{"indices":[1]}')
  check("H: the forced discard is admitted with success=true",
    r and r.ok == true and r.code == "ACTION_ACCEPTED", r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  local window = G.NEURO.force_window
  check("H: and the admission ends its window", type(window) == "table" and window.phase == Window.ENDED,
    tostring(window and window.phase))
  G.STATE = STATES.SHOP
  tick_for(20)
  check("H: a later state change sends no withdrawal for it", #withdrawals == 0, #withdrawals)
end

done()
