love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local FS = require("core.force_state")
local raw_arm = FS.arm
FS.arm = function(state, names, set, now, payload)
  local armed = raw_arm(state, names, set, now, payload)
  if armed then require("tests.helpers").stage_registered(state, names) end
  return armed
end
local check, done = require("tests.helpers").harness("sdk-force-lifecycle")

local function bridge_neuro(over)
  local N = { enabled = true, persona = "neuro", unreg_log = {}, reg_calls = 0 }
  function N:unregister_actions(names)
    local copy = {}
    for i, v in ipairs(names or {}) do copy[i] = v end
    self.unreg_log[#self.unreg_log + 1] = copy
  end
  function N:register_actions(_) self.reg_calls = self.reg_calls + 1 end
  function N:send_context() end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

do
  G.NEURO = bridge_neuro()
  FS.arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, 100)
  FS.mark_sent(100)
  FS.supersede(100)
  check("supersede: force closed", G.NEURO.force_inflight == false)
  -- API/README.md:23 -- the exact force-owned names must be withdrawn before replacement. This is
  -- an explicit cancellation transaction, independent of reconciliation and registry shadow state.
  check("supersede: teardown explicitly withdraws the sent force",
    #G.NEURO.unreg_log == 1, #G.NEURO.unreg_log)
  check("supersede: the sent offer's names are quarantined, so the computed set stops offering them",
    FS.cancel_blocks("play_hand", 100) == true and FS.cancel_blocks("discard_hand", 100) == true)
  check("supersede: and the quarantine is what withdraws them -- cancel_blocks refuses them",
    FS.cancel_blocks("play_hand", 100) == true and FS.cancel_blocks("discard_hand", 100) == true)
  check("supersede: result recorded", G.NEURO.force_last_result == "superseded")
end

do
  G.NEURO = bridge_neuro()
  FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 100)
  FS.supersede(100)
  check("supersede: an offer that never reached the wire is not quarantined",
    G.NEURO.force_cancel_pending == nil and #G.NEURO.unreg_log == 0)
end

do
  G.NEURO = bridge_neuro()
  FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 100)
  FS.mark_sent(100)
  FS.invalidate("run_reset", 100)
  check("invalidate: exact withdrawal and quarantine describe the same sent offer",
    #G.NEURO.unreg_log == 1 and FS.cancel_blocks("sell_card", 100) == true)
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Staging = require("core.staging")

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

local function content_of(cards)
  local parts = {}
  for _, c in ipairs(cards) do
    local base = c.base or {}
    local center = c.config and c.config.center
    parts[#parts + 1] = table.concat({
      tostring(c.sort_id or "?"), tostring(base.value or "?"),
      tostring(base.suit or "?"), tostring(center and center.key or "?"),
    }, "/")
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function result_bridge()
  local b = { results = {}, contexts = {} }
  function b:send_action_result(id, ok, msg, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
  end
  function b:send_context(msg) self.contexts[#self.contexts + 1] = tostring(msg) end
  function b:register_actions(_) end
  return b
end

do
  selecting_hand_env(300)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b = result_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "keep-1", name = "play_hand", data = { indices = { 99 } } } }, b)
  check("in-set failure: wire result is success=false",
    b.results[1] and b.results[1].ok == false)
  check("in-set failure: the force stays open (Neuro retries it herself)",
    G.NEURO.force_inflight == true)
  check("in-set failure: no re-force armed alongside the open force",
    G.NEURO.force_dirty ~= true)
end

do
  selecting_hand_env(320)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b = result_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "confirm-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  local r = b.results[1]
  check("confirm: wire result is success=true (force closes without a retry)",
    r and r.ok == true)
  check("confirm: reason code kept", r and r.reason == "CONFIRMATION_REQUIRED")
  check("confirm: verdict text delivered in the result message (opens with the Selection [ix] = ... line, not just any text mentioning the word)",
    r and tostring(r.msg):match("^Selection %[") ~= nil, r and tostring(r.msg))
  check("confirm: force closed", G.NEURO.force_inflight == false)
  check("confirm: new force armed immediately", G.NEURO.force_dirty == true)
  check("confirm: decision serial untouched (resend latch stays valid)",
    G.NEURO.decision_serial == 5)
  check("confirm: play latch survives the force closure",
    G.NEURO.play_confirm and G.NEURO.play_confirm.signature == "1,2"
      and G.NEURO.play_confirm.decision_serial == 5)

  G.TIMERS.REAL = 322
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  Dispatcher.handle_message({ command = "action",
    data = { id = "confirm-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  local r2 = b.results[2]
  check("confirm resend: same indices commit the play",
    r2 and r2.ok == true and r2.reason == nil and played == true)
  check("confirm resend: progress closes the force with a serial bump",
    G.NEURO.force_inflight == false and G.NEURO.decision_serial == 6)
end

do
  selecting_hand_env(340)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  G.NEURO.play_confirm = {
    signature = "1,2",
    content = content_of({ G.hand.cards[1], G.hand.cards[2] }),
    indices = { 1, 2 }, decision_serial = 0, run_generation = 0,
  }
  G.NEURO.weak_fired_serial = 0
  Staging.reset_run_state()
  require("core.tx_cache").reset()
  local b = result_bridge()
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  local queued = Staging.queue({ command = "action",
    data = { id = "early-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("staged: queue accepted the action", queued == true)
  check("staged: action/result sent at queue time, before any update tick",
    #b.results == 1 and b.results[1].id == "early-1" and b.results[1].ok == true)
  check("staged: execution has not run yet", played == false)
  for _ = 1, 200 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.25
    Staging.update()
    if not Staging.is_busy() then break end
  end
  check("staged: execution ran after the ack", played == true)
  check("staged: still exactly one result for the id", #b.results == 1)
end

do
  selecting_hand_env(400)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 400)
  FS.mark_sent(400)
  require("core.neuro_lifecycle").reset_run_state()
  check("run reset: the dying run's quarantine cannot survive into the new run",
    G.NEURO.force_cancel_pending == nil and FS.cancel_blocks("play_hand", 400) == false)
  check("run reset: force closed", G.NEURO.force_inflight == false)
  check("run reset: nothing re-registers the dying run's actions",
    G.NEURO.reg_calls == 0, G.NEURO.reg_calls)
end

do
  selecting_hand_env(420)
  G.NEURO = bridge_neuro({ dispatcher = Dispatcher, actions = Actions })
  local ok_panel, Panel = pcall(require, "hud.tuning_panel")
  if ok_panel and Panel and Panel.toggle then
    Panel.toggle()
    FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 420)
    local still_open = Panel.toggle()
    check("panel close: panel actually closed", still_open == false)
    check("panel close: the force is torn down without the teardown touching the registry",
      G.NEURO.force_inflight == false and #G.NEURO.unreg_log == 0, #G.NEURO.unreg_log)
    check("panel close: re-arm requested", G.NEURO.force_dirty == true)
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
  require("core.tx_cache").reset()
  local mid_transition = true
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    force_dirty = false,
    state = "SELECTING_HAND", last_action_at = 0,
    update = function() end,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local forces = 0
  function G.NEURO:force_actions(_ctx, _query, _actions) forces = forces + 1 end
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true end
  local b = result_bridge()
  function b:is_transition_cooldown() return mid_transition end
  local Orch = require("core.orchestrator")

  Dispatcher.handle_message({ command = "action",
    data = { id = "busy-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  local r = b.results[1]
  check("mid-transition answer: wire result is success=true (the force is not retried into the transition)",
    r and r.ok == true and r.reason == "TRANSITION_ACKNOWLEDGED", r and tostring(r.reason) or "no result")
  check("mid-transition answer: the message says nothing applied and to choose again",
    r and tostring(r.msg):find("nothing was applied", 1, true) ~= nil
      and tostring(r.msg):find("choose again", 1, true) ~= nil, r and tostring(r.msg))
  check("mid-transition answer: the action did not execute", played == false)
  check("mid-transition answer: force closed and re-arm requested",
    G.NEURO.force_inflight == false and G.NEURO.force_dirty == true)

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

do
  local Bridge = require("core.bridge")
  local prev = G.NEURO
  local b = setmetatable({ enabled = true, _registered_set = { sell_card = true } }, { __index = Bridge })
  function b:send() return true end
  G.NEURO = b
  b.run_generation = 5
  b:register_actions({ { name = "sell_card", description = "sell", schema = { type = "object" } } })
  b:force_actions("SHOP", "q", { "sell_card" })
  check("106: the force records the generation its question was asked in",
    G.NEURO.force_generation == 5, tostring(G.NEURO.force_generation))

  FS.clear_force_state()
  check("106: and the record outlives the window -- it names the last question asked, not the open one",
    G.NEURO.force_generation == 5, tostring(G.NEURO.force_generation))

  b.llm_paused = true
  b.run_generation = 6
  b:force_actions("SHOP", "q", { "sell_card" })
  check("106: a question that never went out does not become the one being answered",
    G.NEURO.force_generation == 5, tostring(G.NEURO.force_generation))
  G.NEURO = prev
end

done()
