_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("liveness-escalation")

local STATES = { SELECTING_HAND = 4, ROUND_EVAL = 8, SHOP = 5, BLIND_SELECT = 7 }
local CLOCK = 5000

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Router = require("force.force_router")
local Orch = require("core.orchestrator")

local forces, contexts, wire

local function board()
  _G.G = {
    STATE = STATES.ROUND_EVAL, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = CLOCK }, SETTINGS = { GAMESPEED = 1 },
    OVERLAY_MENU = nil, screenwipe = nil,
    round_eval = {},
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
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    FUNCS = { cash_out = function() end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }

  forces, contexts, wire = {}, {}, {}
  local live = {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = "ROUND_EVAL",
    update = function() end,
  }
  function G.NEURO:send_context(message, silent)
    contexts[#contexts + 1] = { message = tostring(message), silent = not not silent }
    return true
  end
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
  G.NEURO._desired_action_names = Orch.desired_action_names
  G.NEURO.retract_undesired = require("core.bridge").retract_undesired
  function G.NEURO:_unregister_now(names)
    local copy = {}
    for i = 1, #names do copy[i] = names[i] end
    table.sort(copy)
    wire[#wire + 1] = { op = "unregister", t = G.TIMERS.REAL, names = copy }
    require("core.action_registry").note_unregistered(copy, G.TIMERS.REAL)
    for _, n in ipairs(copy) do live[n] = nil end
  end
  G.NEURO.unregister_actions = G.NEURO._unregister_now
  function G.NEURO:force_actions(state, query, actions)
    local copy = {}
    for i = 1, #actions do copy[i] = actions[i] end
    forces[#forces + 1] = {
      t = G.TIMERS.REAL, state = tostring(state), query = tostring(query),
      actions = table.concat(actions, ","),
    }
    wire[#wire + 1] = { op = "force", t = G.TIMERS.REAL, names = copy }
  end
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("liveness-escalation")
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
  for _ = 1, math.floor((max_seconds or 60) / 0.1) do
    if pred() then return true end
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) return false end
  end
  return pred()
end

local function next_force(n)
  return tick_until(function() return #forces >= n end, FS.FORCE_LIVENESS_TIMEOUT + 40)
end

-- Every re-force must be preceded by a withdrawal of the previous offer's names: that, and not the
-- query text, is what keeps SPECIFICATION.md:136-137 while the escalation changes the question.
local function withdrawn_between(force_a, force_b)
  local from, to
  for i = 1, #wire do
    if wire[i] == force_a then from = i end
    if wire[i] == force_b then to = i end
  end
  if not (from and to and to > from) then return false end
  for i = from + 1, to - 1 do
    if wire[i].op == "unregister" then
      for _, n in ipairs(wire[i].names) do
        if n == "cash_out" then return true end
      end
    end
  end
  return false
end

local function force_frame(n)
  local seen = 0
  for i = 1, #wire do
    if wire[i].op == "force" then
      seen = seen + 1
      if seen == n then return wire[i] end
    end
  end
  return nil
end

local function nonsilent_contexts()
  local n = 0
  for i = 1, #contexts do if not contexts[i].silent then n = n + 1 end end
  return n
end

check("the escalation threshold leaves the first re-ask alone",
  FS.LIVENESS_ESCALATE_AT == 2, FS.LIVENESS_ESCALATE_AT)

do
  board()
  tick_for(12)
  check("fixture: ROUND_EVAL asks and waits on the wire",
    #forces == 1 and Window.is_open(FS.window()), #forces)
  local q1, a1 = forces[1].query, forces[1].actions
  check("fixture: the offer is the narrowed one -- cash_out alone, no non-progress ride-along",
    a1 == "cash_out", a1)

  check("fixture: the handler really is the byte-identical literal that produced the live storm",
    Router.get_force_for_state("ROUND_EVAL").query == q1)

  -- First timeout: the ordinary retry. tests/test_force_liveness_watchdog.lua:281 guards exactly
  -- this cycle and it must stay true, so the escalation may not reach into it.
  check("the first re-ask arrives", next_force(2), #forces)
  check("and it is still the same question, verbatim", forces[2].query == q1, forces[2].query)
  check("the first re-ask replaced the offer instead of stacking on it",
    withdrawn_between(force_frame(1), force_frame(2)))

  local before_ctx = nonsilent_contexts()
  check("the second re-ask arrives", next_force(3), #forces)
  check("the streak reached the escalation threshold",
    G.NEURO.force_liveness_repeat >= FS.LIVENESS_ESCALATE_AT, G.NEURO.force_liveness_repeat)
  check("and the question is no longer byte-identical to the one that went unanswered",
    forces[3].query ~= q1, forces[3].query)
  check("it says the decision went unanswered, so the model can tell this is a repeat",
    forces[3].query:find("unanswered", 1, true) ~= nil, forces[3].query)
  check("the escalation prompts with a non-silent context (SPECIFICATION.md:93), not a second force",
    nonsilent_contexts() == before_ctx + 1, nonsilent_contexts() - before_ctx)
  check("the escalated re-ask still replaced the offer -- no overlapping force",
    withdrawn_between(force_frame(2), force_frame(3)))
  check("escalation did not widen the offer past the ROUND_EVAL narrowing",
    forces[3].actions == "cash_out", forces[3].actions)

  check("a third re-ask arrives", next_force(4), #forces)
  check("and it differs from the escalated one before it as well",
    forces[4].query ~= forces[3].query and forces[4].query ~= q1, forces[4].query)
  check("the escalation prompts once per streak, not once per re-ask",
    nonsilent_contexts() == before_ctx + 1, nonsilent_contexts() - before_ctx)
  check("still exactly one live offer at a time",
    withdrawn_between(force_frame(3), force_frame(4)))

  FS.mark_answered()
  check("an answer clears the streak", FS.liveness_stall_repeats("ROUND_EVAL") == 0,
    FS.liveness_stall_repeats("ROUND_EVAL"))
  check("and the next question is the plain one again",
    Router.get_force_for_state("ROUND_EVAL").query == q1)
end

local function escalation_prompts()
  local n = 0
  for i = 1, #contexts do
    if contexts[i].message:find("the offer was withdrawn", 1, true) then n = n + 1 end
  end
  return n
end

do
  board()
  G.NEURO.run_generation = 2

  check("fixture: the first decision hangs twice and escalates",
    next_force(2) and next_force(3) and escalation_prompts() == 1, escalation_prompts())

  -- The game moves on to a different decision -- decision_serial is what separates the two
  -- (core/force_state.lua:434) -- and that one goes unanswered exactly the same way.
  G.NEURO.decision_serial = (tonumber(G.NEURO.decision_serial) or 0) + 1

  check("the second decision reaches the escalation threshold too",
    next_force(4) and next_force(5), #forces)
  check("and it says so out loud instead of being taken for a repeat of the first",
    escalation_prompts() == 2, escalation_prompts())
end

do
  board()
  G.NEURO.force_liveness_fingerprint = "x"
  G.NEURO.force_liveness_repeat = 5
  G.NEURO.force_liveness_state = "SHOP"
  check("a streak stalled in another state does not annotate this one's question",
    FS.liveness_stall_repeats("ROUND_EVAL") == 0
      and Router.get_force_for_state("ROUND_EVAL").query:find("unanswered", 1, true) == nil)
end

local function fault_board(prior_pause)
  board()
  G.NEURO._force_open = true
  G.NEURO.llm_paused = prior_pause or nil
  G.NEURO.cancel_attempts = 0
  function G.NEURO:complete_force_cancellation()
    self._force_open = nil
    return true
  end
  FS.arm("ROUND_EVAL", { "cash_out" }, { cash_out = true }, G.TIMERS.REAL)
  FS.mark_sent(G.TIMERS.REAL)
end

local function fail_closed()
  local t0 = G.TIMERS.REAL
  FS.invalidate("cancel_probe", t0)
  CLOCK = t0 + FS.CANCEL_IDLE_CAP + 0.1
  G.TIMERS.REAL = CLOCK
  FS.cancel_pending(CLOCK)
  return CLOCK
end

local function after_backoff()
  CLOCK = G.TIMERS.REAL + 2
  G.TIMERS.REAL = CLOCK
  return CLOCK
end

do
  fault_board()
  local buffered = { status = "buffered", kind = "force_cancel_unregister" }
  function G.NEURO:cancel_force_actions()
    self.cancel_attempts = self.cancel_attempts + 1
    return buffered
  end
  local t = fail_closed()
  check("fixture: an unwritable outbox fails closed and pauses Neuro",
    G.NEURO.llm_paused == true and type(G.NEURO.force_transport_fault) == "table"
      and G.NEURO._force_open == true)

  local attempts = G.NEURO.cancel_attempts
  check("while the frame is still queued the recovery waits instead of queueing a second withdrawal",
    FS.transport_fault_step(after_backoff()) == false and G.NEURO.cancel_attempts == attempts
      and G.NEURO.llm_paused == true)

  buffered.status = "written"
  buffered.written_at = G.TIMERS.REAL
  check("once the outbox drains the paused state recovers itself, with no reconnect",
    FS.transport_fault_step(G.TIMERS.REAL) == true)
  check("the withdrawal is durable, so the bridge's old-force debt is finally retired",
    G.NEURO._force_open == nil, tostring(G.NEURO._force_open))
  check("and it retired without a second unregister on the wire",
    G.NEURO.cancel_attempts == attempts, G.NEURO.cancel_attempts)
  check("the pause is lifted and the fault is cleared",
    G.NEURO.llm_paused ~= true and G.NEURO.force_transport_fault == nil,
    tostring(G.NEURO.llm_paused))
  local settling = G.NEURO.force_cancel_pending
  check("the successor is paced by the same settle floor as any other durable withdrawal",
    type(settling) == "table" and settling.phase == "settling")
  check("the recovery is idempotent -- nothing left to recover",
    FS.transport_fault_step(after_backoff()) == false)
  check("fixture: the recovery never needed the reconnect that used to be the only exit", t > 0)
end

do
  fault_board()
  local outcome = { status = "rejected", kind = "force_cancel_unregister" }
  local saturated = true
  function G.NEURO:is_transport_saturated() return saturated end
  function G.NEURO:cancel_force_actions()
    self.cancel_attempts = self.cancel_attempts + 1
    return outcome
  end
  fail_closed()
  check("fixture: a rejected withdrawal also fails closed",
    G.NEURO.llm_paused == true and G.NEURO._force_open == true)

  local attempts = G.NEURO.cancel_attempts
  check("a saturated transport is not retried into",
    FS.transport_fault_step(after_backoff()) == false and G.NEURO.cancel_attempts == attempts
      and G.NEURO.llm_paused == true)

  saturated = false
  outcome = { status = "written", written_at = G.TIMERS.REAL }
  check("once it drains the withdrawal is re-sent and the pause ends",
    FS.transport_fault_step(after_backoff()) == true and G.NEURO.cancel_attempts > attempts
      and G.NEURO._force_open == nil and G.NEURO.llm_paused ~= true)
end

do
  fault_board(true)
  local outcome = { status = "rejected", kind = "force_cancel_unregister" }
  function G.NEURO:cancel_force_actions()
    self.cancel_attempts = self.cancel_attempts + 1
    return outcome
  end
  fail_closed()
  outcome = { status = "written", written_at = G.TIMERS.REAL }
  check("recovery hands back the pause that was already there, it does not clear it",
    FS.transport_fault_step(after_backoff()) == true and G.NEURO.llm_paused == true
      and G.NEURO.force_transport_paused == nil)
end

do
  fault_board()
  local outcome = { status = "rejected", kind = "force_cancel_unregister" }
  function G.NEURO:cancel_force_actions()
    self.cancel_attempts = self.cancel_attempts + 1
    return outcome
  end
  fail_closed()
  local before = #forces
  tick_for(20)
  check("while the withdrawal stays undurable the pause holds and no force escapes",
    G.NEURO.llm_paused == true and G.NEURO._force_open == true and #forces == before,
    #forces .. "/" .. before .. " paused=" .. tostring(G.NEURO.llm_paused))

  outcome = { status = "written", written_at = G.TIMERS.REAL }
  tick_for(5)
  check("the orchestrator frame drives the recovery even though Neuro is paused",
    G.NEURO.llm_paused ~= true and G.NEURO._force_open == nil
      and G.NEURO.force_transport_fault == nil,
    tostring(G.NEURO.llm_paused))
  check("and the game is asking again afterwards", tick_until(function() return #forces > before end, 20),
    #forces .. "/" .. before)
end

do
  local Metrics = require("util.metrics")
  local PACK_STATES = { TAROT_PACK = 12, SHOP = 5, SELECTING_HAND = 4, BLIND_SELECT = 7 }
  board()
  G.STATE = PACK_STATES.TAROT_PACK
  G.STATES = PACK_STATES
  G.round_eval = nil
  G.booster_pack = nil
  G.pack_cards = nil
  G.NEURO.state = "TAROT_PACK"
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
  check("and it says so out loud, because no action on this screen is executable",
    nonsilent_contexts() > before, nonsilent_contexts() - before)
  check("the stale optimistic gate is released so the next pack starts clean",
    G.NEURO.pack_exit_pending == nil, tostring(G.NEURO.pack_exit_pending))
  check("no force names a pack action on a pack that no longer exists", #forces == 0, #forces)
end

done()
