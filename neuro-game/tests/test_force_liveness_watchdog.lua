_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-liveness-watchdog")

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7 }
local CLOCK = 5000

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Helpers = require("tests.helpers")
local Orch = require("core.orchestrator")

local SLOWEST_LIVE_ANSWER = 83.3

local forces, results, wire = {}, {}, {}

local play_card = require("tests.helpers").play_card

local function bridge_stub()
  return {
    send_action_result = function(_, id, ok, message, code)
      results[#results + 1] = { id = id, ok = ok, message = message, code = code }
    end,
    replay_action_result = function() return false end,
    send_context = function() end,
    register_actions = function() end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

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

  forces, results, wire = {}, {}, {}
  local live = {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = state_name,
    update = function() end,
    send_context = function() end,
  }
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
  G.NEURO._desired_action_names = require("core.orchestrator").desired_action_names
  G.NEURO.retract_undesired = require("core.bridge").retract_undesired
  function G.NEURO:_unregister_now(names)
    local copy = {}
    for i = 1, #names do copy[i] = names[i] end
    table.sort(copy)
    wire[#wire + 1] = { op = "unregister", t = G.TIMERS.REAL, names = copy }
    require("core.action_registry").note_unregistered(copy, G.TIMERS.REAL)
    for _, n in ipairs(copy) do live[n] = nil end
  end

  function G.NEURO:unregister_actions(names)
    local copy = {}
    for i = 1, #names do copy[i] = names[i] end
    table.sort(copy)
    wire[#wire + 1] = { op = "unregister", t = G.TIMERS.REAL, names = copy }
    require("core.action_registry").note_unregistered(names, G.TIMERS.REAL)
    for _, n in ipairs(copy) do live[n] = nil end
  end
  function G.NEURO:force_actions(_ctx, _query, actions)
    local copy = {}
    for i = 1, #actions do copy[i] = actions[i] end
    forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
    wire[#wire + 1] = { op = "force", t = G.TIMERS.REAL, names = copy }
  end
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("force-liveness")
  require("core.action_registry").reset()
  require("core.tx_cache").reset()
  Dispatcher.reset_tx()
end

local function tick_for(seconds)
  for _ = 1, math.floor(seconds / 0.1) do
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) break end
  end
end

local function tick_until(pred, max_seconds)
  local budget = math.floor((max_seconds or 60) / 0.1)
  for _ = 1, budget do
    if pred() then return true end
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) return false end
  end
  return pred()
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

local function phase() return require("tests.helpers").force_phase(FS) end

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
  FS.FORCE_LIVENESS_TIMEOUT > SLOWEST_LIVE_ANSWER, FS.FORCE_LIVENESS_TIMEOUT)

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("fixture: the game asked and is waiting on the wire",
    #forces == 1 and phase() == Window.FORCED and G.NEURO.force_inflight == true,
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
  local sent_at = G.NEURO.force_sent_at
  tick_for(FS.FORCE_LIVENESS_TIMEOUT - 20)
  check("just under the bound the game is still honestly waiting",
    phase() == Window.FORCED and #forces == 1, phase() .. "/" .. #forces)

  local fired = tick_until(function() return G.NEURO.force_last_result == "liveness_timeout" end, 40)
  check("past the bound the game stops waiting forever", fired
    and phase() == Window.ENDED and G.NEURO.force_inflight == false,
    phase() .. "/" .. tostring(G.NEURO.force_inflight))
  check("and says why, so a dead broadcast is diagnosable",
    G.NEURO.force_last_result == "liveness_timeout", tostring(G.NEURO.force_last_result))
  check("the watchdog fingerprints repeated timeouts of one unchanged decision",
    G.NEURO.force_liveness_repeat == 1 and type(G.NEURO.force_liveness_fingerprint) == "string")
  check("the withdrawal fires once the wait exceeds the bound, not earlier",
    fired and (G.TIMERS.REAL - sent_at) >= FS.FORCE_LIVENESS_TIMEOUT, G.TIMERS.REAL - sent_at)

  -- API/README.md:23: the client only drops a force she already holds when its names leave the wire,
  -- so re-registering them in the same breath would resurrect the offer the watchdog just cancelled.
  local withdrawal = last_wire("unregister")
  check("the offer's names are withdrawn from the wire", withdrawal ~= nil
    and table.concat(withdrawal.names, ","):find("play_hand", 1, true) ~= nil,
    withdrawal and table.concat(withdrawal.names, ",") or "none")
  local readmit = last_wire("register")
  check("and they stay off it while the cancellation settles",
    FS.cancel_pending(G.TIMERS.REAL) ~= nil
      and withdrawal ~= nil and not readmitted_after(withdrawal, "play_hand"),
    tostring(FS.cancel_pending(G.TIMERS.REAL) ~= nil))

  tick_for(5)
  check("then the game asks the same decision again",
    #forces == 2 and phase() == Window.FORCED, #forces .. "/" .. phase())
  readmit = last_wire("register")
  check("with its actions back on the wire ahead of the question",
    forces[2] ~= nil and readmit ~= nil and withdrawal ~= nil
      and names_include(readmit, "play_hand")
      and readmit.t <= forces[2].t and readmit.t > withdrawal.t,
    readmit and (table.concat(readmit.names, ",") .. " @" .. tostring(readmit.t)) or "no register")

  local settled = #forces
  tick_for(FS.FORCE_LIVENESS_TIMEOUT - 20)
  check("and the replacement gets the full bound of its own -- no re-ask storm",
    #forces == settled, #forces .. " forces after " .. settled)
end

do
  board("SELECTING_HAND")
  G.NEURO._force_open = true
  function G.NEURO:cancel_force_actions()
    return { status = "rejected", kind = "force_cancel_unregister" }
  end
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, G.TIMERS.REAL)
  FS.mark_sent(G.TIMERS.REAL)
  FS.invalidate("cancel_probe", G.TIMERS.REAL)
  check("failed cancellation enters the bounded CANCELLING phase",
    phase() == Window.CANCELLING and FS.cancel_pending(G.TIMERS.REAL) ~= nil)
  FS.cancel_pending(G.TIMERS.REAL + FS.CANCEL_IDLE_CAP + 0.1)
  check("an unwritable cancellation fails closed instead of cancelling forever",
    phase() == Window.ENDED and FS.cancel_pending(G.TIMERS.REAL + FS.CANCEL_IDLE_CAP + 0.1) == nil
      and G.NEURO.llm_paused == true and G.NEURO.force_transport_fault ~= nil)
  check("fail-closed recovery retains the bridge's old-force debt",
    G.NEURO._force_open == true)
  FS.reconnect()
  check("a reconnect releases only the pause owned by the transport fault",
    not G.NEURO.llm_paused and G.NEURO.force_transport_fault == nil
      and G.NEURO.force_transport_paused == nil)
end

-- The race the watchdog creates: an answer to the force it just closed. SPECIFICATION.md:165-167
-- obliges exactly one result per action, so a closed window must never make one disappear.
do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  tick_until(function() return G.NEURO.force_last_result == "liveness_timeout" end,
    FS.FORCE_LIVENESS_TIMEOUT + 40)
  check("fixture: the watchdog closed the window before the answer arrived",
    G.NEURO.force_last_result == "liveness_timeout", tostring(G.NEURO.force_last_result))

  check("fixture: and did it by taking the offer's names off the wire",
    require("core.action_registry").is_registered("play_hand") == false)

  local id = answer_raw(b, "play_hand", '{"indices":[1,2]}')
  check("an answer to the closed window is still answered, exactly once",
    results_for(id) == 1, results_for(id))
  check("and it is not silently dropped -- the result carries a verdict",
    results[#results] ~= nil and results[#results].ok == true,
    results[#results] and tostring(results[#results].ok) or "no result")
  check("the SDK-friendly verdict closes the obsolete force without claiming execution",
    results[#results].code == "FORCE_EXPIRED"
      and results[#results].message:find("expired force", 1, true)
      and results[#results].message:find("not executed", 1, true),
    tostring(results[#results].code))
  check("the expired action cannot mutate the hand before the replacement is offered",
    #G.hand.highlighted == 0, #G.hand.highlighted)
  Dispatcher.handle_message({ command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("a duplicate late delivery cannot emit a second real result", results_for(id) == 1,
    results_for(id))

  local after = #forces
  tick_for(30)
  check("the late answer leaves the game asking, not hanging on a window it already closed",
    #forces >= after and phase() ~= Window.ENDED, #forces .. "/" .. phase())
  check("and never two live offers at once",
    not (G.NEURO.force_inflight and phase() == Window.ACKNOWLEDGED),
    phase() .. "/" .. tostring(G.NEURO.force_inflight))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  tick_until(function() return #forces == 2 end, FS.FORCE_LIVENESS_TIMEOUT + 40)
  check("fixture: the replacement force is already on the wire",
    #forces == 2 and phase() == Window.FORCED, #forces .. "/" .. phase())

  local stale_id = "stale-wire-window"
  Dispatcher.handle_message({ command = "action", data = {
    id = stale_id, name = "play_hand", force_wire_name = "play_hand_force_1",
    force_wire_stale = true, data = '{"indices":[1,2]}',
  } }, b)
  check("an answer carrying an expired wire-window id is acknowledged without execution",
    results_for(stale_id) == 1 and results[#results].ok == true
      and results[#results].code == "FORCE_EXPIRED" and #G.hand.highlighted == 0,
    results[#results] and tostring(results[#results].code) or "no result")

  local id = answer(b, "play_hand", '{"indices":[1,2]}')
  check("the overtaken answer gets exactly one result", results_for(id) == 1, results_for(id))

  local seen = {}
  for i = 1, #results do
    check("no action id is answered twice", seen[results[i].id] == nil, tostring(results[i].id))
    seen[results[i].id] = true
  end

  local after = #forces
  tick_for(FS.FORCE_LIVENESS_TIMEOUT + 30)
  check("and the game keeps its liveness afterwards", #forces > after, #forces .. " after " .. after)
end

do
  board("SELECTING_HAND")
  tick_for(10)
  local win = FS.window()
  win.phase = Window.ACKNOWLEDGED
  G.TIMERS.REAL = G.TIMERS.REAL + FS.FORCE_LIVENESS_TIMEOUT * 3
  check("a parked offer is not the liveness watchdog's business",
    FS.liveness_expired(G.TIMERS.REAL) == false)
  win.phase = Window.REGISTERED
  check("nor is one that never reached the wire",
    FS.liveness_expired(G.TIMERS.REAL) == false)
end

do
  board("SELECTING_HAND")
  tick_for(10)
  G.NEURO.llm_paused = true
  tick_for(FS.FORCE_LIVENESS_TIMEOUT + 30)
  check("pausing the model does not spend the offer's liveness bound",
    phase() == Window.FORCED and G.NEURO.force_last_result ~= "liveness_timeout",
    phase() .. "/" .. tostring(G.NEURO.force_last_result))
end

done()
