require("tests.stubs").setup({ love = "timers", G = "timed" })

local Window = require("core.window")
local H = require("tests.helpers")
local function open_force(state, names)
  H.stage_registered(state, names)
  return H.open_force(state, names)
end
local check, done = H.harness("sdk-force-lifecycle")

local function bridge_neuro(over)
  local N = require("tests.helpers").started_bridge({ enabled = true, persona = "neuro", cancel_log = {}, reg_calls = 0 })
  function N:withdraw_actions(names)
    local copy = {}
    for i, v in ipairs(names or {}) do copy[i] = v end
    self.cancel_log[#self.cancel_log + 1] = copy
    return true
  end
  function N:register_actions(_) self.reg_calls = self.reg_calls + 1 end
  function N:send_context(_, _, receipt)
    if receipt then receipt.status = "written" end
    return true
  end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

do
  G.NEURO = bridge_neuro()
  local w = open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  Window.withdraw("superseded")
  check("supersede: the delivered force ends", w.phase == "ended" and Window.current() == nil)
  check("supersede: the withdrawal unregisters exactly the delivered names (README.md:27)",
    #G.NEURO.cancel_log == 1
      and G.NEURO.cancel_log[1][1] == "play_hand"
      and G.NEURO.cancel_log[1][2] == "discard_hand")
  check("supersede: the reason is recorded", w.ended_by == "superseded")
end

do
  G.NEURO = bridge_neuro()
  G.NEURO.force_window = { phase = "registered", state = "SHOP", names = { "sell_card" }, set = { sell_card = true } }
  Window.withdraw("superseded")
  check("supersede: an offer that never reached the wire is discarded without an unregister",
    G.NEURO.force_window.phase == "ended" and #G.NEURO.cancel_log == 0)
end

do
  G.NEURO = bridge_neuro()
  local w = open_force("SHOP", { "buy_from_shop", "sell_card" })
  Window.withdraw("run_reset")
  check("withdraw: the sent offer ends", w.phase == "ended")
  check("withdraw: the whole sent offer is unregistered, tool included (README.md:27)",
    #G.NEURO.cancel_log == 1 and table.concat(G.NEURO.cancel_log[1], ",") == "buy_from_shop,sell_card",
    table.concat(G.NEURO.cancel_log[1] or {}, ","))
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Staging = require("core.staging")
local Gate = require("core.gate")

local play_card = require("tests.helpers").play_card

local function selecting_hand_env(t) require("tests.helpers").receipt_selecting_hand_env(t) end

local function apply_play()
  local selected = {}
  for _, card in ipairs(G.hand.highlighted or {}) do selected[card] = true end
  local kept = {}
  for _, card in ipairs(G.hand.cards or {}) do
    if not selected[card] then kept[#kept + 1] = card end
  end
  G.hand.cards = kept
  G.hand.highlighted = {}
  G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
end

local function result_bridge()
  local b = H.stub_bridge({ results = {}, contexts = {}, register_actions = "noop",
    send_action_result = H.result_log("results", { "id", "ok", "msg", "reason" }, "written") })
  function b:send_context(msg) self.contexts[#self.contexts + 1] = tostring(msg) end
  return b
end

do
  selecting_hand_env(300)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b = result_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "keep-1", name = "play_hand", data = '{"indices":[99]}' } }, b)
  check("in-set failure: wire result is success=false",
    b.results[1] and b.results[1].ok == false)
  check("in-set failure: the force stays open (Neuro retries it herself)",
    Window.current() ~= nil and #G.NEURO.cancel_log == 0)
end

do
  selecting_hand_env(320)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b = result_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "confirm-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local r = b.results[1]
  check("confirm: wire result is success=true (force closes without a retry)",
    r and r.ok == true)
  check("confirm: reason code kept", r and r.reason == "CONFIRMATION_REQUIRED")
  check("confirm: the result is only the brief (SPECIFICATION.md:189)",
    r and r.msg == require("handlers.hand_handlers").PLAY_REVIEW_BRIEF, r and tostring(r.msg))
  local p = require("core.gate").proposal() or {}
  local verdict, facts = p.verdict or "", p.facts or ""
  local force = require("force.force_router").get_force_for_state("SELECTING_HAND")
  check("confirm: the review rides the resolve_play force, its Selection [ix] = ... facts in state",
    facts:match("^Selection %[") ~= nil and force and force.query:find(verdict, 1, true) ~= nil
      and tostring(force.state_extra):find(facts, 1, true) ~= nil and not force.query:find("Selection [", 1, true),
    facts .. " || " .. tostring(force and force.query))
  check("confirm: the force ends as answered, so the resolution is asked next",
    Window.current() == nil and G.NEURO.force_window.ended_by == "answered")
  check("confirm: decision serial untouched (resend latch stays valid)",
    G.NEURO.decision_serial == 5)
  check("confirm: play latch survives the force closure",
    Gate.proposal() and Gate.proposal().signature == "1,2"
      and Gate.proposal().decision_serial == 5)

  G.TIMERS.REAL = 322
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  Dispatcher.handle_message({ command = "action",
    data = { id = "confirm-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local r2 = b.results[2]
  check("confirm resend: same indices do not commit the play",
    r2 and r2.ok == true and r2.reason == "POLICY_ACKNOWLEDGED"
      and played == false,
    r2 and r2.msg)
  check("confirm resend: the explicit confirm path remains pending and does not advance the serial",
    Window.current() == nil and G.NEURO.decision_serial == 5)
end

do
  selecting_hand_env(340)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  local hand_tx = assert(require("tests.helpers").open_proposal({ 1, 2 },
    "Committing Pair -- Call resolve_play with answer yes to commit this play."))
  check("staged: the delivered confirmation is awaiting its answer before queueing",
    hand_tx.phase == "ready" and require("handlers.hand_handlers").confirm_ready(), "phase=" .. tostring(hand_tx.phase))
  G.NEURO.weak_fired_serial = 0
  Staging.reset_run_state()
  require("core.bridge").tx.reset()
  local b = result_bridge()
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  require("tests.helpers").stage_registered(nil, { "resolve_play" })
  Dispatcher.route_message({ command = "action",
    data = { id = "early-1", name = "resolve_play", data = '{"answer":"yes"}' } }, b)
  check("staged: the action was admitted and staged", require("core.execute").busy() == "staged")
  check("staged: action admission result precedes execution",
    b.results[1] and b.results[1].ok == true
      and b.results[1].reason == "ACTION_ACCEPTED"
      and b.results[1].msg == nil,
    b.results[1] and b.results[1].msg)
  check("staged: execution has not run yet", played == false)
  for _ = 1, 200 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.25
    Staging.update()
    require("core.execute").step()
    if played then break end
  end
  check("staged: execution ran after admission", played == true)
  check("staged: still exactly one result for the id", #b.results == 1)
end

do
  selecting_hand_env(400)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  require("core.neuro_lifecycle").reset_run_state()
  check("run reset: force closed", Window.current() == nil)
  check("run reset: nothing re-registers the dying run's actions",
    G.NEURO.reg_calls == 0, G.NEURO.reg_calls)
end

do
  selecting_hand_env(420)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  local ok_panel, Panel = pcall(require, "hud.tuning_panel")
  if ok_panel and Panel and Panel.toggle then
    Panel.toggle()
    require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
    local still_open = Panel.toggle()
    check("panel close: panel actually closed", still_open == false)
    check("panel close: the force is torn down", Window.current() == nil)
  else
    check("panel close: tuning panel loads headless", false, tostring(Panel))
  end
end

do
  selecting_hand_env(3000)
  G.STATE_COMPLETE = true
  G.SETTINGS = { GAMESPEED = 1 }
  G.OVERLAY_MENU = nil
  G.E_MANAGER = { queues = { base = { { blocking = true } } } }
  Staging.reset_run_state()
  require("core.bridge").tx.reset()
  local mid_transition = true
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    force_dirty = false,
    state = "SELECTING_HAND", last_action_at = 0,
    update = function() end,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local forces = 0
  function G.NEURO:force_actions(_ctx, _query, _actions) forces = forces + 1 end
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true end
  local b = result_bridge()
  function b:is_transition_cooldown() return mid_transition end
  local Orch = require("core.orchestrator")

  Dispatcher.handle_message({ command = "action",
    data = { id = "busy-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  local r = b.results[1]
  check("mid-transition answer: wire result is success=true (the force is not retried into the transition)",
    r and r.ok == true, r and tostring(r.reason) or "no result")
  check("mid-transition answer: the action did not execute", played == false)
  check("mid-transition answer: the force ends", Window.current() == nil)

  for _ = 1, 100 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.05
    pcall(Orch.update, 0.05)
  end
  check("no force storm: 5 s of ticks emit nothing while the engine is still transitioning",
    forces == 0, tostring(forces))

  mid_transition = false
  G.E_MANAGER = { queues = {} }
  for _ = 1, 100 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.05
    pcall(Orch.update, 0.05)
  end
  check("no force storm: exactly one replacement force once the engine settles",
    forces == 1, tostring(forces))
  G.E_MANAGER = nil
end

done()
