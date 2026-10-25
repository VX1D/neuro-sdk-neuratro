require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("force-liveness-watchdog")

local STATES = require("tests.engine_cards").states()
local CLOCK = 5000

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Win = require("core.window")
local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }
local Helpers = require("tests.helpers")
local Orch = require("core.orchestrator")
local Metrics = require("util.metrics")

local SLOWEST_LIVE_ANSWER = 83.3

local play_card = Helpers.play_card

local function base_board(state_name)
  Helpers.orch_board({ state = state_name, clock = CLOCK, states = STATES })
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end
end

local T = Helpers.orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for, tick_until = T.tick_for, T.tick_until
local function phase() return Helpers.force_phase() end

do
  local forces, withdrawals = 0, 0
  base_board("SELECTING_HAND")
  G.NEURO = Helpers.orch_neuro({
    state = "SELECTING_HAND", send_context = "written", send_action_result = "noop", register_actions = "true",
    force_actions = function() forces = forces + 1 return true end,
    withdraw_actions = function() withdrawals = withdrawals + 1 return true end,
  })
  Helpers.orch_reset()
  local LIVENESS = require("core.config").get("NEURO_FORCE_LIVENESS_TIMEOUT")
  local armed = tick_until(function() return phase() == "forced" end, 15)
  check("fixture: the force went out and its window is forced", armed and forces == 1, phase())
  check("its liveness clock starts at the send", G.NEURO.force_window.sent_at ~= nil)

  local sent_wall = CLOCK
  local before_metric = Metrics._counters.force_cancel_reason_liveness_timeout or 0
  tick_for(LIVENESS - 20)
  check("still within the bound, the window is not torn down", phase() == "forced" and withdrawals == 0, phase())

  local torn_down = tick_until(function() return withdrawals > 0 end, 30)
  check("past the bound the unanswered force is withdrawn by unregistering its actions",
    torn_down and withdrawals == 1)
  check("it happens no earlier than the bound itself", (CLOCK - sent_wall) >= LIVENESS - 1, CLOCK - sent_wall)
  check("and it is counted under its reason",
    (Metrics._counters.force_cancel_reason_liveness_timeout or 0) > before_metric)
  check("and the game asks again", tick_until(function() return forces == 2 end, 15), forces)
end

do
  local forces, attempts, refuse = 0, 0, true
  base_board("SELECTING_HAND")
  Orch.reset_run_state()
  G.NEURO = Helpers.orch_neuro({
    state = "SELECTING_HAND", send_context = "written", send_action_result = "noop", register_actions = "true",
    force_actions = function() forces = forces + 1 return true end,
    withdraw_actions = function() attempts = attempts + 1 return not refuse end,
  })
  Win.reset()
  require("core.validate").reset_run_state()
  require("core.action_registry").reset()
  require("core.bridge").tx.reset()
  local LIVENESS = require("core.config").get("NEURO_FORCE_LIVENESS_TIMEOUT")
  check("fixture: the force went out", tick_until(function() return phase() == "forced" end, 15) and forces == 1, phase())

  tick_until(function() return attempts > 0 end, LIVENESS + 30)
  tick_for(30)
  check("a refused withdrawal keeps the window forced and sends no second force",
    attempts > 1 and phase() == "forced" and forces == 1 and G.NEURO.force_window.ended_by == nil,
    string.format("attempts=%d phase=%s forces=%d", attempts, tostring(phase()), forces))
  check("and the unanswered decision is not counted until it is actually withdrawn", G.NEURO.force_liveness == nil)

  refuse = false
  check("once the transport takes the withdrawal the window ends and the game asks again",
    tick_until(function() return forces == 2 end, 30) and G.NEURO.force_liveness ~= nil, forces)
end

Orch.reset_run_state()
local forces, results, wire = {}, {}, {}

local function bridge_stub()
  return Helpers.stub_bridge({
    send_action_result = Helpers.result_log(results, { "id", "ok", "message", "code" }),
    replay_action_result = Helpers.no, send_context = "written", register_actions = "noop",
    is_transition_cooldown = "false",
  })
end

local function board(state_name)
  base_board(state_name)
  forces, results, wire = {}, {}, {}
  local live = {}
  G.NEURO = Helpers.orch_neuro({ dispatcher = Dispatcher, actions = Actions, state = state_name,
    send_context = "written" })
  function G.NEURO:register_actions(defs)
    local names = {}
    for i = 1, #defs do names[i] = type(defs[i]) == "table" and defs[i].name or defs[i] end
    table.sort(names)
    local set = {}
    for _, n in ipairs(names) do set[n] = true end
    local stale = {}
    for n in pairs(live) do
      if not set[n] then stale[#stale + 1] = n end
    end
    table.sort(stale)
    if #stale > 0 then
      wire[#wire + 1] = { op = "unregister", t = G.TIMERS.REAL, names = stale }
      require("core.action_registry").note_unregistered(stale, G.TIMERS.REAL)
      for _, n in ipairs(stale) do live[n] = nil end
    end
    wire[#wire + 1] = { op = "register", t = G.TIMERS.REAL, names = names }
    require("core.action_registry").note_registered(names)
    for _, n in ipairs(names) do live[n] = "sig" end
  end
  G.NEURO._registered_sigs = live
  function G.NEURO:withdraw_actions(names)
    local copy = {}
    for i = 1, #names do copy[i] = names[i] end
    table.sort(copy)
    wire[#wire + 1] = { op = "unregister", t = G.TIMERS.REAL, names = copy }
    require("core.action_registry").note_unregistered(copy, G.TIMERS.REAL)
    for _, n in ipairs(copy) do live[n] = nil end
    return true
  end

  function G.NEURO:force_actions(_ctx, _query, actions)
    local copy = {}
    for i = 1, #actions do copy[i] = actions[i] end
    forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
    wire[#wire + 1] = { op = "force", t = G.TIMERS.REAL, names = copy }
  end
  Win.reset()
  require("core.validate").reset_run_state()
  require("core.action_registry").reset()
  require("core.bridge").tx.reset()
  Dispatcher.reset_tx()
end


local answer_n = 0
local function answer_raw(bridge, name, payload)
  answer_n = answer_n + 1
  local id = "live-" .. answer_n
  Dispatcher.handle_message({ command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = name, data = payload } }, bridge)
  return id
end

local function answer(bridge, name, payload)
  Helpers.stage_registered(nil, { name })
  return answer_raw(bridge, name, payload)
end

local function results_for(id)
  local n = 0
  for i = 1, #results do if results[i].id == id then n = n + 1 end end
  return n
end

local TIMEOUT = Win.liveness_timeout(nil)
local function timed_out() local w = G.NEURO.force_window return w and w.ended_by == "liveness_timeout" end

local function last_wire(op)
  for i = #wire, 1, -1 do if wire[i].op == op then return wire[i] end end
  return nil
end

local function wire_index(frame)
  for i = #wire, 1, -1 do if wire[i] == frame then return i end end
  return nil
end

local function readmitted_after(frame, name)
  local from = wire_index(frame)
  if not from then return false end
  for i = from + 1, #wire do
    if wire[i].op == "register" then
      for _, n in ipairs(wire[i].names) do
        if n == name then return true end
      end
    end
  end
  return false
end

local function names_include(frame, name)
  for _, n in ipairs(frame and frame.names or {}) do
    if n == name then return true end
  end
  return false
end

check("the bound clears the slowest answer the archives ever recorded",
  TIMEOUT > SLOWEST_LIVE_ANSWER, TIMEOUT)

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("fixture: the game asked and is waiting on the wire",
    #forces == 1 and phase() == Window.FORCED,
    #forces .. "/" .. phase())
  local offered = forces[1].actions

  tick_for(SLOWEST_LIVE_ANSWER)
  check("a slow thinker is not punished: the archives' worst answer still lands in its own offer",
    phase() == Window.FORCED and #forces == 1, phase() .. "/" .. #forces)

  local id = answer(b, "play_hand", '{"indices":[1,2]}')
  check("and it is accepted as the answer to that offer, not to a torn-down one",
    results_for(id) == 1 and results[#results].ok == true, tostring(results[#results].ok))
  check("fixture: the offer really contained the answered action",
    offered:find("play_hand", 1, true) ~= nil, offered)
end

do
  board("SELECTING_HAND")
  bridge_stub()
  tick_for(10)
  local window = G.NEURO.force_window
  local sent_at = window.sent_at
  tick_for(TIMEOUT - 20)
  check("just under the bound the game is still honestly waiting",
    phase() == Window.FORCED and #forces == 1, phase() .. "/" .. #forces)

  local fired = tick_until(timed_out, 40)
  local withdrawn = last_wire("unregister")
  check("past the bound withdraws the delivered offer by unregistering its names (README.md:27)",
    fired and window.phase == Window.ENDED and withdrawn ~= nil and names_include(withdrawn, "play_hand"),
    phase() .. "/" .. tostring(window.ended_by))
  check("and says why, so a dead broadcast is diagnosable",
    window.ended_by == "liveness_timeout", tostring(window.ended_by))
  check("the watchdog fingerprints repeated timeouts of one unchanged decision",
    G.NEURO.force_liveness and G.NEURO.force_liveness.repeats == 1
      and type(G.NEURO.force_liveness.fingerprint) == "string")
  check("the withdrawal comes only once the bound has passed",
    fired and (G.TIMERS.REAL - sent_at) >= TIMEOUT, G.TIMERS.REAL - sent_at)

  tick_for(5)
  check("the next offer replaces the old window",
    #forces == 2 and phase() == Window.FORCED, #forces .. "/" .. phase())
end


do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local fired = tick_until(timed_out, TIMEOUT + 40)
  check("fixture: the watchdog withdrew the delivered offer",
    fired and phase() == Window.ENDED, phase())

  local id = answer_raw(b, "play_hand", '{"indices":[1,2]}')
  check("a late action after withdrawal receives one terminal verdict",
    results_for(id) == 1, results_for(id))
  local terminal = results[#results]
  check("the late action verdict is complete",
    terminal ~= nil and type(terminal.ok) == "boolean" and type(terminal.code) == "string"
      and type(terminal.message) == "string" and terminal.code ~= "",
    terminal and (tostring(terminal.ok) .. "/" .. tostring(terminal.code)
      .. "/" .. tostring(terminal.message)) or "no result")
  Dispatcher.handle_message({ command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("a duplicate late delivery cannot emit a second result", results_for(id) == 1,
    results_for(id))
end


do
  board("SELECTING_HAND")
  tick_for(10)
  local win = G.NEURO.force_window
  win.phase = Window.REGISTERED
  local unregisters = 0
  for _, f in ipairs(wire) do if f.op == "unregister" then unregisters = unregisters + 1 end end
  tick_for(TIMEOUT * 3)
  local after = 0
  for _, f in ipairs(wire) do if f.op == "unregister" then after = after + 1 end end
  check("an offer that never reached the wire is not the liveness watchdog's business",
    win.phase == Window.REGISTERED and after == unregisters, tostring(win.phase))
end

do
  board("SELECTING_HAND")
  tick_for(10)
  G.NEURO.llm_paused = true
  tick_for(TIMEOUT + 30)
  check("pausing the model does not spend the offer's liveness bound",
    phase() == Window.FORCED and not timed_out(), phase())
end

done()