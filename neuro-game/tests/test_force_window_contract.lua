require("tests.stubs").setup({ love = "timers" })
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local Window = require("core.window")
local function open_force(state, names)
  require("tests.helpers").stage_registered(state, names)
  return require("tests.helpers").open_force(state, names)
end
local function in_flight() return Window.current() ~= nil end

local ActionResult = require("core.action_result")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Config = require("core.config")

local check, done = require("tests.helpers").harness("force-window-contract")

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

local function bridge_neuro(over)
  local N = {
    enabled = true, persona = "neuro", reg_calls = 0,
    transport_session = "force-window-test", transport_epoch = 1,
    run_generation = 1, send_context = require("tests.helpers").receipt_written,
  }
  function N:register_actions(_) self.reg_calls = self.reg_calls + 1 end
  if over then for k, v in pairs(over) do N[k] = v end end
  return require("tests.helpers").started_bridge(N)
end

local TxCache = require("core.bridge").tx
local function order_bridge()
  local log = {}
  local b = {}
  function b:send_action_result(id, ok, message, reason)
    log[#log + 1] = { kind = "result", id = id, ok = ok, reason = reason }
    TxCache.store(id, ok, message, nil, reason)
    return true
  end
  b.send_context, b.register_actions = require("tests.helpers").receipt_written, require("tests.helpers").noop
  return require("tests.helpers").started_bridge(b), log
end

local Bridge = require("core.bridge")

local function open_action(id, name)
  assert(TxCache.open(id, name, G.TIMERS.REAL))
end

local function reconciling_bridge(over)
  local log = {}
  local b = setmetatable({
    enabled = true, persona = "neuro", reg_calls = 0,
    _registered_sigs = { play_hand = "sig", discard_hand = "sig" },
  }, { __index = Bridge })
  if over then for k, v in pairs(over) do b[k] = v end end
  function b:send(msg, receipt)
    if msg.command == "actions/unregister" then
      log[#log + 1] = { kind = "unregister", names = msg.data.action_names }
    end
    if receipt then
      receipt.status = "written"
      receipt.written_at = G.TIMERS.REAL
    end
    return true
  end
  function b:send_action_result(id, ok, msg, reason)
    log[#log + 1] = { kind = "result", id = id, ok = ok, reason = reason }
    return true
  end
  b.send_context, b.write_file = require("tests.helpers").yes, require("tests.helpers").yes
  function b:register_actions(_) self.reg_calls = self.reg_calls + 1 end
  return require("tests.helpers").started_bridge(b), log
end

local function log_index(log, pred)
  for i, entry in ipairs(log) do
    if pred(entry) then return i end
  end
  return nil
end

do
  G.NEURO = { decision_serial = 1, enabled = true, persona = "neuro" }
  check("one-window: idle before any force (SPECIFICATION.md:138-140 precondition)", not in_flight())
  local first = open_force("SELECTING_HAND", { "play_hand" })
  check("one-window: first window is allowed to enter Forced (ActionWindow.cs Force())",
    first.phase == "forced" and Window.current() == first)
  Window.step("SELECTING_HAND")
  check("one-window: SPECIFICATION.md:138-140 forbids a second actions/force while one is in progress",
    Window.current() == first)
  check("one-window: the in-progress window keeps its state and action set",
    Window.state_name() == "SELECTING_HAND" and first.set.play_hand == true and first.set.sell_card == nil)
  Window.reset()
  check("one-window: after the window ends, the gate reopens", not in_flight())
  local third = open_force("SHOP", { "sell_card" })
  check("one-window: a closed window's slot can be taken by a fresh one", Window.current() == third)
end

do
  selecting_hand_env(300)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b, _log = order_bridge()
  open_action("fail-1", "play_hand")
  Dispatcher.handle_message({ command = "action",
    data = { id = "fail-1", name = "play_hand", data = '{"indices":[99]}' } }, b)
  check("window-close: action_window.gd:83-84 -- a failed in-set action leaves the window Forced, not Ended",
    in_flight())
end

do
  selecting_hand_env(320)
  Config.set("NEURO_CONFIRM_HAND", "off")
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  local b = order_bridge()
  open_action("close-1", "play_hand")
  Dispatcher.handle_message({ command = "action",
    data = { id = "close-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  G.TIMERS.REAL = 322
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  open_action("close-2", "play_hand")
  Dispatcher.handle_message({ command = "action",
    data = { id = "close-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  check("window-close: USAGE.md 'automatically ended when an action is received and is executed successfully' -- setup precondition (execution actually ran)",
    played == true)
  check("window-close: USAGE.md -- the window is Ended once that action succeeded", not in_flight())
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  G.NEURO = { decision_serial = 1, withdraw_actions = function() return true end }
  local window_1 = open_force("SELECTING_HAND", { "play_hand" })
  Window.on_result("play_hand", true)
  check("new-window: ActionWindow.cs End() -- window #1 is now Ended (terminal), not revivable in place",
    window_1.phase == "ended" and not in_flight())
  local window_2 = open_force("SELECTING_HAND", { "play_hand" })
  check("new-window: USAGE.md -- since window #1 is Ended, the game gets a NEW window, not a resend of #1",
    window_2 ~= window_1 and window_2.phase == "forced" and window_1.phase == "ended")
end

do
  selecting_hand_env(500)
  Config.set("NEURO_CONFIRM_HAND", "off")
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 9,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b, log = order_bridge()
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  open_action("ord-1", "play_hand")
  Dispatcher.handle_message({ command = "action",
    data = { id = "ord-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  G.TIMERS.REAL = 502
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  open_action("ord-2", "play_hand")
  Dispatcher.handle_message({ command = "action",
    data = { id = "ord-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  local result_ix = log_index(log, function(e) return e.kind == "result" and e.id == "ord-2" end)
  local execute_ix = played and (#log + 1) or nil
  check("result-before-exec: setup precondition -- ord-2 actually committed the play",
    played == true)
  check("result-before-exec: action/result for ord-2 was sent on the wire at all",
    result_ix ~= nil)
  local probe_seen_before_result = false
  local probe_seen_after_result = false
  do
    selecting_hand_env(520)
    local b2, log2 = order_bridge()
    G.NEURO = bridge_neuro({
      dispatcher = Dispatcher, actions = Actions,
      decision_serial = 9,
    })
    open_action("ord2a-1", "play_hand")
    Dispatcher.handle_message({ command = "action",
      data = { id = "ord2a-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b2)
    G.TIMERS.REAL = 522
    G.NEURO.force_window = nil
    require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
    G.FUNCS.play_cards_from_highlighted = function()
      local seen = log_index(log2, function(e) return e.kind == "result" and e.id == "ord2a-2" end) ~= nil
      probe_seen_before_result = seen
      probe_seen_after_result = true
      apply_play()
    end
    open_action("ord2a-2", "play_hand")
    Dispatcher.handle_message({ command = "action",
      data = { id = "ord2a-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b2)
  end
  check("result-before-exec: setup precondition -- the probe fired (execution ran)",
    probe_seen_after_result == true)
  check("result-before-exec: SPECIFICATION.md:164-176 -- admission result is visible before execution",
    probe_seen_before_result == true)
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  check("ack-flag: SPECIFICATION.md:188 Tip -- CONFIRMATION_REQUIRED is terminal (a confirmation prompt must not retry the whole force)",
    ActionResult.terminal("CONFIRMATION_REQUIRED") == true)
  check("ack-flag: SPECIFICATION.md:188 Tip -- a wait that answers the force is terminal",
    ActionResult.terminal("TRANSITION_PENDING", true) == true)
  check("ack-flag: a wait outside the force stays a plain failure",
    ActionResult.terminal("TRANSITION_PENDING", false) == false)
  check("ack-flag: SPECIFICATION.md:188 Tip -- POLICY_ACKNOWLEDGED is terminal",
    ActionResult.terminal("POLICY_ACKNOWLEDGED") == true)
  check("ack-flag: SPECIFICATION.md:188 -- an ordinary rejection (INVALID_SELECTION) is NOT terminal, so success=false really does go out and the whole force is retried by Neuro",
    ActionResult.terminal("INVALID_SELECTION", true) == false)
  check("ack-flag: unknown/absent reason code is never terminal (fail closed)",
    ActionResult.terminal(nil) == false and ActionResult.terminal("NOT_A_REAL_CODE") == false)
end

do
  selecting_hand_env(600)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions, decision_serial = 11,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b = order_bridge()
  local results = {}
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "_", "reason" }, true)
  Dispatcher.handle_message({ command = "action",
    data = { id = "ack-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("ack-flag pipeline: SPECIFICATION.md:188 -- a CONFIRMATION_REQUIRED verdict reaches the wire as success=true despite validation logically rejecting the play",
    results[1] and results[1].ok == true and results[1].reason == "CONFIRMATION_REQUIRED",
    results[1] and (tostring(results[1].ok) .. "/" .. tostring(results[1].reason)))
  check("ack-flag pipeline: action_window.gd:81-82 -- success=true ends this window, same as any other successful result",
    not in_flight() and G.NEURO.force_window.ended_by == "answered")
end

do
  selecting_hand_env(620)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 12,
  })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local b = order_bridge()
  local results = {}
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "_", "reason" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "ack-2", name = "play_hand", data = '{"indices":[99]}' } }, b)
  check("ack-flag pipeline: SPECIFICATION.md:188 -- a plain out-of-range rejection (INVALID_SELECTION, not acknowledge-flagged) really does reach the wire as success=false",
    results[1] and results[1].ok == false and results[1].reason == "INVALID_SELECTION",
    results[1] and (tostring(results[1].ok) .. "/" .. tostring(results[1].reason)))
end

do
  selecting_hand_env(700)
  Config.set("NEURO_CONFIRM_HAND", "off")
  local b, log = reconciling_bridge({
    dispatcher = Dispatcher, actions = Actions, decision_serial = 20,
  })
  G.NEURO = b
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  G.TIMERS.REAL = 702
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-2", name = "play_hand", data = '{"indices":[1,2]}' } }, b)

  local unregister_ix = log_index(log, function(e)
    if e.kind ~= "unregister" then return false end
    for _, n in ipairs(e.names or {}) do if n == "play_hand" then return true end end
    return false
  end)
  local result_ix = log_index(log, function(e) return e.kind == "result" and e.id == "disp-2" end)
  check("unregister-before-result: README.md:23-25 -- the disposable action's name was unregistered at all",
    unregister_ix ~= nil)
  check("unregister-before-result: README.md:23-25 -- action/result for the same call had not been sent yet",
    result_ix ~= nil)
  check("unregister-before-result: README.md:25 'you should unregister them before sending back the action result' -- unregister happened strictly before that result",
    unregister_ix ~= nil and result_ix ~= nil and unregister_ix < result_ix,
    tostring(unregister_ix) .. " vs " .. tostring(result_ix))
  Config.set("NEURO_CONFIRM_HAND", "on")
end

done()
