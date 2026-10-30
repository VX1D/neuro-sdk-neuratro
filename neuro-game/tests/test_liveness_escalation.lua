require("tests.stubs").setup({ love = "timers" })
local TmpWork = require("tests.tmp_workdir")
local MOD_PATH = TmpWork.open("liveness_escalation_mod")
require("tests.engine_cards").install_smods({ current_mod = { path = MOD_PATH }, Mods = {},
  findModByID = function() return nil end })

local H = require("tests.helpers")
local check, done = H.harness("liveness-escalation")

local STATES = require("tests.engine_cards").states()
local CLOCK = 5000

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Window = require("core.window")
local Router = require("force.force_router")
require("core.orchestrator")

local forces, contexts, wire

local function board()
  H.orch_board({ state = "ROUND_EVAL", clock = CLOCK, states = STATES, edit = function(g)
    g.round_eval = {}
    g.P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" } }
    g.FUNCS = { cash_out = H.noop }
  end })
  H.cash_out_ready(G)

  forces, contexts, wire = {}, {}, {}
  local live = {}
  G.NEURO = H.orch_neuro({
    transport_session = "live-test", _bridge_init_complete = true, _startup_complete = true,
    dispatcher = Dispatcher, actions = Actions, state = "ROUND_EVAL", send_startup = "true",
  })
  function G.NEURO:send_context(message, silent, receipt)
    contexts[#contexts + 1] = { message = tostring(message), silent = not not silent }
    if receipt then receipt.status = "written" end
    return true
  end
  function G.NEURO:register_actions(defs)
    local names = {}
    for i = 1, #(defs or {}) do names[i] = type(defs[i]) == "table" and defs[i].name or defs[i] end
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
    wire[#wire + 1] = { op = "withdraw", t = G.TIMERS.REAL, names = copy }
    require("core.action_registry").note_unregistered(copy, G.TIMERS.REAL)
    for _, n in ipairs(copy) do live[n] = nil end
    return true
  end
  function G.NEURO:force_actions(state, query, actions)
    local copy = {}
    for i = 1, #actions do copy[i] = actions[i] end
    forces[#forces + 1] = {
      t = G.TIMERS.REAL, state = tostring(state), query = tostring(query),
      actions = table.concat(actions, ","),
    }
    wire[#wire + 1] = { op = "force", t = G.TIMERS.REAL, names = copy }
    return true
  end
  require("core.validate").reset_run_state()
  require("core.action_registry").reset()
  require("core.bridge").tx.reset()
  Dispatcher.reset_tx()
  require("core.context_delivery").reset_transport()
  Window.reset()
  Window.emit_rules("SHOP")
end

local T = require("tests.helpers").orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for, tick_until = T.tick_for, T.tick_until



local function nonsilent_contexts()
  local n = 0
  for i = 1, #contexts do if not contexts[i].silent then n = n + 1 end end
  return n
end
local function unregisters()
  local n = 0
  for _, entry in ipairs(wire) do if entry.op == "withdraw" then n = n + 1 end end
  return n
end
local LIVENESS = require("core.config").get("NEURO_FORCE_LIVENESS_TIMEOUT")

do
  board()
  tick_for(12)
  check("fixture: ROUND_EVAL asks and waits on the wire", #forces == 1 and Window.current() ~= nil, #forces)
  local q1, a1 = forces[1].query, forces[1].actions
  check("fixture: the offer lists every usable action -- cash_out and record_plan", a1 == "cash_out,record_plan", a1)
  check("fixture: the handler supplies the live query", Router.get_force_for_state("ROUND_EVAL").query == q1)

  local serial_before = G.NEURO.decision_serial
  local before_contexts = nonsilent_contexts()
  tick_for(LIVENESS - 13)
  check("the decision is not withdrawn before the liveness timeout", unregisters() == 0 and #forces == 1)
  tick_until(function() return unregisters() > 0 end, 5)
  check("the liveness timeout unregisters the unanswered decision's actions (README.md:27)",
    unregisters() == 1 and wire[#wire].op == "withdraw" and wire[#wire].names[1] == "cash_out",
    tostring(unregisters()))
  check("the first timeout does not spend the escalation diagnostic budget",
    nonsilent_contexts() == before_contexts, nonsilent_contexts() - before_contexts)
  check("withdrawal does not spend the decision", G.NEURO.decision_serial == serial_before)
  check("the decision is asked again, re-registering what the withdrawal took off",
    tick_until(function() return #forces == 2 end, 30) and forces[2].actions == "cash_out,record_plan"
      and Window.current() ~= nil and wire[#wire].op == "force" and wire[#wire - 1].op == "register",
    tostring(#forces))
  check("the re-ask keeps the same decision serial", G.NEURO.decision_serial == serial_before)
end

do
  board()
  local attempts = 0
  function G.NEURO:force_actions()
    attempts = attempts + 1
    return false
  end
  tick_for(12)
  check("a force the transport refused leaves no window holding the single-force lock",
    attempts >= 1 and Window.current() == nil, attempts)
  local first = attempts
  tick_for(2)
  check("and the decision is tried again rather than stranded", attempts > first, attempts)
end

do
  board()
  G.NEURO.force_liveness = { fingerprint = "x", repeats = 5, state = "SHOP" }
  check("a streak stalled in another state does not annotate this one's question",
    Window.liveness_repeats("ROUND_EVAL") == 0
      and Router.get_force_for_state("ROUND_EVAL").query:find("unanswered", 1, true) == nil)
end

do
  board()
  tick_for(12)
  local timeouts = 0
  while timeouts < Window.LIVENESS_ESCALATE_AT do
    local before = unregisters()
    tick_until(function() return unregisters() > before end, LIVENESS * 4 + 30)
    timeouts = timeouts + 1
    tick_until(function() return #forces == timeouts + 1 end, 30)
  end
  local note
  for _, frame in ipairs(contexts) do
    if frame.message:find("unanswered", 1, true) then note = frame.message end
  end
  local query = forces[#forces] and forces[#forces].query or ""
  check("fixture: the escalation produced a context and a re-asked force",
    note ~= nil and #forces == Window.LIVENESS_ESCALATE_AT + 1, tostring(#forces))
  local sentence = Window.liveness_note(Window.LIVENESS_ESCALATE_AT)
  check("context and query carry the same account of the withdrawal",
    note ~= nil and note:find(sentence, 1, true) ~= nil and query:find(sentence, 1, true) ~= nil,
    tostring(note) .. " || " .. query)
end

do
  local Metrics = require("util.metrics")
  local PACK_STATES = require("tests.engine_cards").states()
  board()
  G.STATE = PACK_STATES.SMODS_BOOSTER_OPENED
  G.STATES = PACK_STATES
  G.round_eval = nil
  G.booster_pack = nil
  G.pack_cards = nil
  G.NEURO.state = "SMODS_BOOSTER_OPENED"
  G.NEURO.pack_exit_pending = true
  Metrics._counters.pack_transition_stalled = 0
  local before = nonsilent_contexts()

  tick_for(2)
  check("the transition is given its grace period before anything is diagnosed",
    G.NEURO.pack_transition_stalled == nil and G.NEURO.pack_exit_pending == true)

  tick_for(20)
  check("a pack state the engine never leaves is diagnosed through the real arming loop",
    type(G.NEURO.pack_transition_stalled) == "table",
    tostring(G.NEURO.pack_transition_stalled))
  check("and it counts, so a dead pack is visible without reading the log",
    (Metrics._counters.pack_transition_stalled or 0) > 0,
    Metrics._counters.pack_transition_stalled)
  local told = false
  for _, frame in ipairs(contexts) do
    if frame.silent and frame.message:find("Engine transition stalled", 1, true) then told = true end
  end
  check("and it tells her silently, because no action on this screen is executable (SPECIFICATION.md:96)",
    told and nonsilent_contexts() == before, nonsilent_contexts() - before)
  check("the stale optimistic gate is released so the next pack starts clean",
    G.NEURO.pack_exit_pending == nil, tostring(G.NEURO.pack_exit_pending))
  check("no force names a pack action on a pack that no longer exists", #forces == 0, #forces)
end

TmpWork.close()
done()
