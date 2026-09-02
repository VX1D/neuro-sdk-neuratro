-- Contract comes from the reference implementation (Unity ActionWindow.cs, Godot action_window.gd, API/SPECIFICATION.md ~131-190); a red check means the clause isn't honored yet, don't weaken it to pass.

_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local FS = require("core.force_state")
local raw_arm = FS.arm
FS.arm = function(state, names, set, now, payload)
  local armed = raw_arm(state, names, set, now, payload)
  if armed then require("tests.helpers").stage_registered(state, names) end
  return armed
end

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

local function order_bridge()
  local log = {}
  local b = {}
  function b:send_action_result(id, ok, msg, reason)
    log[#log + 1] = { kind = "result", id = id, ok = ok, reason = reason }
  end
  function b:send_context(_) end
  function b:register_actions(_) end
  function b:unregister_actions(names)
    log[#log + 1] = { kind = "unregister", names = names }
  end
  return b, log
end

local Bridge = require("core.bridge")

local function reconciling_bridge(over)
  local log = {}
  local b = setmetatable({
    enabled = true, persona = "neuro", reg_calls = 0,
    _registered_set = { play_hand = true, discard_hand = true },
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
  function b:send_context(_) return true end
  function b:write_file(_, _) return true end
  function b:register_actions(_) self.reg_calls = self.reg_calls + 1 end
  b:set_desired_action_names(function()
    local want = {}
    for _, name in ipairs(Actions.get_valid_actions_for_state("SELECTING_HAND")) do want[name] = true end
    return want
  end)
  return b, log
end

local function log_index(log, pred)
  for i, entry in ipairs(log) do
    if pred(entry) then return i end
  end
  return nil
end

do
  G.NEURO = {}
  check("one-window: idle before any force (SPECIFICATION.md:136 precondition)",
    FS._test.is_inflight() == false)

  local armed_first = FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 100)
  check("one-window: first window is allowed to enter Forced (ActionWindow.cs Force())",
    armed_first == true)

  local armed_second = FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 101)
  check("one-window: SPECIFICATION.md:136-137 forbids a second actions/force while one is in progress",
    armed_second == false)
  check("one-window: refused second arm does not touch the in-progress window's state",
    G.NEURO.force_state == "SELECTING_HAND")
  check("one-window: refused second arm does not touch the in-progress window's action set",
    G.NEURO.force_window.set.play_hand == true and G.NEURO.force_window.set.sell_card == nil)

  FS.clear_force_state()
  check("one-window: after the window ends, the gate reopens (ActionWindow is Building again, not stuck Forced)",
    FS._test.is_inflight() == false)
  local armed_third = FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 102)
  check("one-window: a closed window's slot can be taken by a fresh one",
    armed_third == true)
end

do
  selecting_hand_env(300)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b, _log = order_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "fail-1", name = "play_hand", data = { indices = { 99 } } } }, b)
  check("window-close: action_window.gd:83-84 -- a failed in-set action leaves the window Forced, not Ended",
    G.NEURO.force_inflight == true)
end

do
  selecting_hand_env(320)
  Config.set("NEURO_CONFIRM_HAND", "off")
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 5,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b = order_bridge()
  Dispatcher.handle_message({ command = "action",
    data = { id = "close-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

  G.TIMERS.REAL = 322
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end
  Dispatcher.handle_message({ command = "action",
    data = { id = "close-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

  check("window-close: USAGE.md 'automatically ended when an action is received and is executed successfully' -- setup precondition (execution actually ran)",
    played == true)
  check("window-close: USAGE.md -- the window is Ended (force_inflight cleared) once that action succeeded",
    G.NEURO.force_inflight == false)
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  G.NEURO = {}
  local armed_1 = FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 200)
  check("new-window: window #1 opens", armed_1 == true)
  local window_1 = FS.window()
  FS.clear_force_state()
  check("new-window: ActionWindow.cs End() -- window #1 is now Ended (terminal), not revivable in place",
    G.NEURO.force_state == nil and G.NEURO.force_inflight == false)

  local armed_2 = FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 205)
  check("new-window: USAGE.md -- since window #1 is Ended, the game gets a NEW window, not a resend of #1",
    armed_2 == true)
  check("new-window: the new window is a distinct instance, not window #1 revived",
    FS.window() ~= window_1 and FS.window().phase == "registered")
  check("new-window: the new window starts its own pending result, not #1's stale one",
    G.NEURO.force_last_result == "pending")
end

do
  selecting_hand_env(500)
  Config.set("NEURO_CONFIRM_HAND", "off")
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 9,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b, log = order_bridge()
  local played = false
  G.FUNCS.play_cards_from_highlighted = function() played = true apply_play() end

  Dispatcher.handle_message({ command = "action",
    data = { id = "ord-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

  G.TIMERS.REAL = 502
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  Dispatcher.handle_message({ command = "action",
    data = { id = "ord-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

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
    FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
    Dispatcher.handle_message({ command = "action",
      data = { id = "ord2a-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b2)
    G.TIMERS.REAL = 522
    G.NEURO.force_inflight = false
    G.NEURO.force_window = nil
    FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
    G.FUNCS.play_cards_from_highlighted = function()
      probe_seen_before_result = log_index(log2, function(e) return e.kind == "result" and e.id == "ord2a-2" end) ~= nil
      probe_seen_after_result = true
      apply_play()
    end
    Dispatcher.handle_message({ command = "action",
      data = { id = "ord2a-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b2)
  end
  check("result-before-exec: setup precondition -- the probe fired (execution ran)",
    probe_seen_after_result == true)
  check("result-before-exec: API/README.md 'sent after validating... before it is actually executed in-game' -- action/result for this id had already landed when execution ran",
    probe_seen_before_result == true)
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  check("ack-flag: SPECIFICATION.md:188 Tip -- CONFIRMATION_REQUIRED is acknowledge-flagged (a confirmation prompt must not retry the whole force)",
    ActionResult.acknowledges("CONFIRMATION_REQUIRED") == true)
  check("ack-flag: SPECIFICATION.md:188 Tip -- TRANSITION_ACKNOWLEDGED is acknowledge-flagged",
    ActionResult.acknowledges("TRANSITION_ACKNOWLEDGED") == true)
  check("ack-flag: SPECIFICATION.md:188 Tip -- POLICY_ACKNOWLEDGED is acknowledge-flagged",
    ActionResult.acknowledges("POLICY_ACKNOWLEDGED") == true)
  check("ack-flag: SPECIFICATION.md:184 -- an ordinary rejection (INVALID_SELECTION) is NOT acknowledge-flagged, so success=false really does go out and the whole force is retried by Neuro",
    ActionResult.acknowledges("INVALID_SELECTION") == false)
  check("ack-flag: unknown/absent reason code is never treated as acknowledge-flagged (fail closed)",
    ActionResult.acknowledges(nil) == false and ActionResult.acknowledges("NOT_A_REAL_CODE") == false)
end

do
  selecting_hand_env(600)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 11,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b = order_bridge()
  local results = {}
  function b:send_action_result(id, ok, msg, reason)
    results[#results + 1] = { id = id, ok = ok, reason = reason }
  end
  Dispatcher.handle_message({ command = "action",
    data = { id = "ack-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)
  check("ack-flag pipeline: SPECIFICATION.md:188 -- a CONFIRMATION_REQUIRED verdict reaches the wire as success=true despite validation logically rejecting the play",
    results[1] and results[1].ok == true and results[1].reason == "CONFIRMATION_REQUIRED",
    results[1] and (tostring(results[1].ok) .. "/" .. tostring(results[1].reason)))
  check("ack-flag pipeline: action_window.gd:81-82 -- success=true (via the acknowledge flip) ends this window, same as any other successful result",
    G.NEURO.force_inflight == false)
  check("ack-flag pipeline: USAGE.md 'new window' model -- a fresh window is queued immediately so the re-ask isn't lost",
    G.NEURO.force_dirty == true)
end

do
  selecting_hand_env(620)
  G.NEURO = bridge_neuro({
    dispatcher = Dispatcher, actions = Actions,
    decision_serial = 12,
  })
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  local b = order_bridge()
  local results = {}
  function b:send_action_result(id, ok, msg, reason)
    results[#results + 1] = { id = id, ok = ok, reason = reason }
  end
  Dispatcher.handle_message({ command = "action",
    data = { id = "ack-2", name = "play_hand", data = { indices = { 99 } } } }, b)
  check("ack-flag pipeline: SPECIFICATION.md:184 -- a plain out-of-range rejection (INVALID_SELECTION, not acknowledge-flagged) really does reach the wire as success=false",
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
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-1", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

  G.TIMERS.REAL = 702
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  G.NEURO.consumed_actions = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  Dispatcher.handle_message({ command = "action",
    data = { id = "disp-2", name = "play_hand", data = { indices = { 1, 2 } } } }, b)

  local unregister_ix = log_index(log, function(e)
    if e.kind ~= "unregister" then return false end
    for _, n in ipairs(e.names or {}) do if n == "play_hand" then return true end end
    return false
  end)
  local result_ix = log_index(log, function(e) return e.kind == "result" and e.id == "disp-2" end)
  check("unregister-before-result: README.md:19-23 -- the disposable action's name was unregistered at all",
    unregister_ix ~= nil)
  check("unregister-before-result: README.md:19-23 -- action/result for the same call had not been sent yet",
    result_ix ~= nil)
  check("unregister-before-result: README.md:21 'you should unregister them before sending back the action result' -- unregister happened strictly before that result",
    unregister_ix ~= nil and result_ix ~= nil and unregister_ix < result_ix,
    tostring(unregister_ix) .. " vs " .. tostring(result_ix))
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  _G.G = { NEURO = { decision_serial = 1 }, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }
  local dropped = {}
  G.NEURO.unregister_actions = function(_, names)
    for _, n in ipairs(names) do dropped[#dropped + 1] = n end
  end

  check("one-force: a window arms and reaches the wire",
    raw_arm("SPLASH", { "choose_persona" }, { choose_persona = true }, 0, { query = "q" })
      and FS.mark_sent(1) == true)

  FS.invalidate("unsent")
  check("one-force: SPECIFICATION.md -- a delivered window is not dropped as 'unsent'",
    G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))
  check("one-force: its actions stay registered, so the client can still answer",
    #dropped == 0, table.concat(dropped, ","))
  check("one-force: the offer it still owns is not quarantined either",
    G.NEURO.force_cancel_pending == nil)

  _G.G = { NEURO = { decision_serial = 2 }, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }
  G.NEURO.unregister_actions = function(_, names)
    for _, n in ipairs(names) do dropped[#dropped + 1] = n end
  end
  raw_arm("MENU", { "open_run_setup" }, { open_run_setup = true }, 0, { query = "q" })
  FS.invalidate("unsent")
  check("one-force: a window still awaiting send is dropped as before",
    G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("one-force: an unsent window is torn down without a withdrawal or a settle gap",
    #dropped == 0 and G.NEURO.force_cancel_pending == nil,
    table.concat(dropped, ",") .. "/" .. tostring(G.NEURO.force_cancel_pending ~= nil))
end

done()
