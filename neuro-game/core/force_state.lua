local M = {}

local Lifecycle = require("core.neuro_lifecycle")
local Actions = require("core.actions")
local Window = require("core.force_window")
local Metrics = require("util.metrics")
local ContextDelivery = require("core.context_delivery")

function M.is_forced_action(name)
  if not (G and G.NEURO and name) then return false end
  local window = G.NEURO.force_window
  if not Window.is_open(window) then return false end
  return Window.owns(window, name)
end
function M.is_active_action(name, state_name)
  return not not (G and G.NEURO
    and G.NEURO.force_state == state_name
    and M.is_forced_action(name))
end

function M.set_action_phase(name, at)
  if not (G and G.NEURO) then return end
  G.NEURO.action_phase = name
  G.NEURO.action_phase_at = at or require("util.utils").now()
end

function M.clear_force_state()
  if not (G and G.NEURO) then return end
  if G.NEURO.force_window then Window.finish(G.NEURO.force_window) end
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_sent_at = nil
end

local function is_inflight()
  return not not (G and G.NEURO and G.NEURO.force_inflight)
end

function M.window()
  return G and G.NEURO and G.NEURO.force_window or nil
end

function M.window_is_open()
  return Window.is_open(M.window())
end

local function window_owns(name)
  return Window.owns(M.window(), name)
end

M.ACK_LIMIT = 2

local Tuning = require("core.config")

local Utils = require("util.utils")

local function tuned(gate_id, key, fallback)
  local ok, value = pcall(Utils.gate_seconds, gate_id, key)
  return (ok and tonumber(value)) or fallback
end

M.ACK_IDLE_REASK = Tuning.default("NEURO_ACK_IDLE_REASK")

M.FORCE_LIVENESS_TIMEOUT = Tuning.default("NEURO_FORCE_LIVENESS_TIMEOUT")

-- Settle gap between withdrawing an offer the client may still hold and letting its names back on
-- the wire (API/README.md:23 -- unregistering is what makes Neuro drop the cancelled force).
M.CANCEL_SETTLE = Tuning.default("NEURO_FORCE_CANCEL_SETTLE")

M.CANCEL_IDLE_CAP = Tuning.default("NEURO_FORCE_CANCEL_IDLE")

M.LIVENESS_ESCALATE_AT = 2

local function ack_scope_reset()
  if not (G and G.NEURO) then return end
  G.NEURO.decision_ack_count = 0
  G.NEURO.decision_ack_serial = nil
  G.NEURO.decision_ack_level = nil
  G.NEURO.decision_ack_at = nil
  G.NEURO.force_liveness_fingerprint = nil
  G.NEURO.force_liveness_repeat = 0
  G.NEURO.force_liveness_state = nil
end

M.ack_scope_reset = ack_scope_reset

local function ack_scope_live()
  if not (G and G.NEURO) then return false end
  return G.NEURO.decision_ack_serial == (G.NEURO.decision_serial or 0)
end

local function ack_budget(level)
  local budget = M.ACK_LIMIT
  for _ = 1, (tonumber(level) or 0) do budget = budget * 2 end
  return budget
end

function M.arm(state, action_names, action_set, _now, payload)
  if not (G and G.NEURO) or G.NEURO.force_inflight then
    return false
  end
  local pending = G.NEURO.force_cancel_pending
  if type(pending) == "table" then return false end
  local window = Window.build(state, G.NEURO.decision_serial)
  if not Window.register(window, action_names, action_set, payload) then return false end
  G.NEURO.force_window = window
  G.NEURO.force_last_result = "pending"
  G.NEURO.force_state = state
  G.NEURO.force_inflight = true
  return true
end

function M.mark_sent(now)
  local window = M.window()
  if not Window.mark_forced(window) then return false end
  if G and G.NEURO then
    G.NEURO.force_sent_at = tonumber(now) or Utils.gate_now("force_liveness_timeout")
    G.NEURO.force_generation = tonumber(G.NEURO.run_generation)
  end
  return true
end

function M.mark_queued()
  local window = M.window()
  if not Window.mark_forced(window) then return false end
  if G and G.NEURO then G.NEURO.force_sent_at = nil end
  return true
end

function M.mark_written(now)
  local window = M.window()
  if not (G and G.NEURO and type(window) == "table" and window.phase == Window.FORCED) then
    return false
  end
  G.NEURO.force_sent_at = tonumber(now) or Utils.gate_now("force_liveness_timeout")
  G.NEURO.force_generation = tonumber(G.NEURO.run_generation)
  return true
end

function M.acknowledge_offer()
  if not (G and G.NEURO) then return false end
  local window = M.window()
  if type(window) ~= "table" then return false end
  if window.phase ~= Window.FORCED and window.phase ~= Window.ACKNOWLEDGED then return false end

  local cur_serial = G.NEURO.decision_serial or 0
  if G.NEURO.decision_ack_serial ~= cur_serial then
    G.NEURO.decision_ack_serial = cur_serial
    G.NEURO.decision_ack_count = 0
    G.NEURO.decision_ack_level = 0
  end
  local ack_count = (G.NEURO.decision_ack_count or 0) + 1
  G.NEURO.decision_ack_count = ack_count
  G.NEURO.decision_ack_at = Utils.gate_now("ack_idle_reask")

  if ack_count >= ack_budget(G.NEURO.decision_ack_level) then
    G.NEURO.decision_ack_level = (tonumber(G.NEURO.decision_ack_level) or 0) + 1
    G.NEURO.decision_ack_count = 0
    M.invalidate("ack_exhausted")
    return true
  end

  if not Window.mark_acknowledged(window) then return false end
  G.NEURO.force_inflight = false
  G.NEURO.force_sent_at = nil
  G.NEURO.force_last_result = "acknowledged"
  return true
end

local function quarantine(names, now, result)
  if not (G and G.NEURO) or type(names) ~= "table" or #names == 0 then return nil end
  local set = {}
  local list = {}
  for i = 1, #names do
    set[names[i]] = true
    list[i] = names[i]
  end
  local pending = {
    names = list, set = set, at = nil, started_at = now,
    phase = "sending", result = result or "invalidated", attempts = 0,
  }
  G.NEURO.force_cancel_pending = pending
  return pending
end

local function finish_cancellation(pending, now)
  if not (G and G.NEURO) or type(pending) ~= "table" then return false end
  local receipt = pending.receipt
  if type(receipt) == "table" and receipt.status ~= "written" then return false end
  if G.NEURO.complete_force_cancellation then
    local ok, accepted = pcall(G.NEURO.complete_force_cancellation, G.NEURO, pending.names)
    if not ok or accepted == false then
      Metrics.incr("force_cancel_commit_error")
      return false
    end
  end
  M.clear_force_state()
  G.NEURO.force_last_result = pending.result
  pending.phase = "settling"
  pending.at = (type(receipt) == "table" and tonumber(receipt.written_at))
    or tonumber(now) or Utils.gate_now("cancel_settle")
  pending.receipt = nil
  Metrics.incr("force_cancel_written")
  Lifecycle.mark_force_dirty()
  return true
end

local function attempt_cancellation(pending, now)
  if not (G and G.NEURO) or type(pending) ~= "table" then return false end
  now = tonumber(now) or Utils.gate_now("cancel_settle")
  if tonumber(pending.next_attempt_at) and now < pending.next_attempt_at then return false end
  pending.attempts = (pending.attempts or 0) + 1
  pending.next_attempt_at = now + math.min(1, 0.05 * (2 ^ math.min(pending.attempts - 1, 5)))
  Metrics.incr("force_cancel_attempt")
  if G.NEURO.cancel_force_actions then
    local ok, receipt = pcall(G.NEURO.cancel_force_actions, G.NEURO, pending.names)
    if not ok then
      pending.last_error = tostring(receipt)
      Metrics.incr("force_cancel_send_error")
      return false
    end
    if receipt == true then
      receipt = { status = "written", written_at = tonumber(now) or Utils.gate_now("cancel_settle") }
    elseif receipt == false or receipt == nil then
      Metrics.incr("force_cancel_rejected")
      return false
    end
    pending.receipt = receipt
    if type(receipt) == "table" and receipt.status == "buffered" then
      Metrics.incr("force_cancel_buffered")
    elseif type(receipt) == "table" and receipt.status == "rejected" then
      pending.receipt = nil
      Metrics.incr("force_cancel_rejected")
      return false
    end
    return finish_cancellation(pending, now)
  end

  local method = G.NEURO.unregister_actions or G.NEURO.retract_undesired
  if method then
    local ok, accepted
    if method == G.NEURO.unregister_actions then
      ok, accepted = pcall(method, G.NEURO, pending.names)
    else
      ok, accepted = pcall(method, G.NEURO)
    end
    if not ok or accepted == false then
      Metrics.incr("force_cancel_send_error")
      return false
    end
  end
  pending.receipt = { status = "written", written_at = tonumber(now) or Utils.gate_now("cancel_settle") }
  return finish_cancellation(pending, now)
end

function M.invalidate(result, now)
  if not (G and G.NEURO) then return false end
  local existing = G.NEURO.force_cancel_pending
  if type(existing) == "table" and existing.phase == "sending" then
    if type(existing.receipt) == "table" and existing.receipt.status == "written" then
      return finish_cancellation(existing, now)
    end
    if existing.receipt == nil or existing.receipt.status == "rejected" then
      return attempt_cancellation(existing, now)
    end
    return false
  end
  if result == "unsent" then
    local sent = M.window()
    if type(sent) == "table" and sent.phase == Window.FORCED then return end
  end
  local window = M.window()
  if G.NEURO.force_inflight or Window.is_open(window) then
    local sent_names
    if type(window) == "table" and type(window.names) == "table" and #window.names > 0
      and (window.phase == Window.FORCED or window.phase == Window.ACKNOWLEDGED) then
      sent_names = window.names
    end
    if sent_names and type(G.NEURO.force_cancel_pending) ~= "table" then
      local stamp = tonumber(now) or Utils.gate_now("cancel_settle")
      local pending = quarantine(sent_names, stamp, result)
      Window.mark_cancelling(window)
      G.NEURO.force_last_result = "cancelling"
      Metrics.incr("force_cancel_started")
      return attempt_cancellation(pending, stamp)
    end
    G.NEURO.force_last_result = result or "invalidated"
    M.clear_force_state()
  end
  Lifecycle.mark_force_dirty()
  return true
end

function M.reask_due(now)
  if not (G and G.NEURO) then return false end
  if G.NEURO.enabled == false or G.NEURO.llm_paused then return false end
  local window = M.window()
  if type(window) ~= "table" or window.phase ~= Window.ACKNOWLEDGED then return false end
  if not ack_scope_live() then return false end
  local at = tonumber(G.NEURO.decision_ack_at)
  if not at then return false end
  return ((tonumber(now) or Utils.gate_now("ack_idle_reask")) - at)
    >= tuned("ack_idle_reask", "NEURO_ACK_IDLE_REASK", M.ACK_IDLE_REASK)
end

function M.reask()
  if not (G and G.NEURO) then return false end
  G.NEURO.decision_ack_level = (tonumber(G.NEURO.decision_ack_level) or 0) + 1
  G.NEURO.decision_ack_count = 0
  G.NEURO.decision_ack_at = nil
  M.invalidate("ack_idle")
  return true
end

function M.liveness_expired(now)
  if not (G and G.NEURO) then return false end
  if G.NEURO.enabled == false or G.NEURO.llm_paused then return false end
  local window = M.window()
  if type(window) ~= "table" or window.phase ~= Window.FORCED then return false end
  local at = tonumber(G.NEURO.force_sent_at)
  if not at then return false end
  return ((tonumber(now) or Utils.gate_now("force_liveness_timeout")) - at)
    >= tuned("force_liveness_timeout", "NEURO_FORCE_LIVENESS_TIMEOUT", M.FORCE_LIVENESS_TIMEOUT)
end

function M.delivery_queued_at()
  return Utils.gate_now("force_liveness_timeout")
end

function M.delivery_liveness_expired(queued_at, now)
  local at = tonumber(queued_at)
  if not at then return false end
  local current = tonumber(now) or Utils.gate_now("force_liveness_timeout")
  return (current - at)
    >= tuned("force_liveness_timeout", "NEURO_FORCE_LIVENESS_TIMEOUT", M.FORCE_LIVENESS_TIMEOUT)
end

function M.liveness_timeout(now)
  if not (G and G.NEURO) then return false end
  local window = M.window()
  local actions = {}
  for i, name in ipairs((type(window) == "table" and window.names) or {}) do
    actions[i] = tostring(name)
  end
  table.sort(actions)
  local HandTx = Utils.lazy_require("core.hand_transaction")
  local hand_transaction_id = HandTx and HandTx.transaction_id and HandTx.transaction_id() or ""
  local fingerprint = table.concat({
    tostring(G.NEURO.decision_serial or 0),
    tostring(type(window) == "table" and window.state or ""),
    table.concat(actions, ","),
    tostring(hand_transaction_id),
  }, "|")
  if G.NEURO.force_liveness_fingerprint == fingerprint then
    G.NEURO.force_liveness_repeat = (tonumber(G.NEURO.force_liveness_repeat) or 0) + 1
  else
    G.NEURO.force_liveness_fingerprint = fingerprint
    G.NEURO.force_liveness_repeat = 1
  end
  G.NEURO.force_liveness_state = type(window) == "table" and window.state or nil
  local repeats = G.NEURO.force_liveness_repeat
  Metrics.set("force_liveness_repeat", repeats)
  local superseded = not not M.supersede(now, "liveness_timeout")
  if repeats == M.LIVENESS_ESCALATE_AT then
    Metrics.incr("force_liveness_repeat_escalated")
    print("[neuro-game] The same decision force timed out " .. tostring(repeats)
      .. " times without game progress; escalating the re-ask instead of repeating it verbatim")
    ContextDelivery.prompt_at("force_liveness",
      ContextDelivery.here("decision " .. tostring(G.NEURO.decision_serial or 0)),
      "The question the game asked you went unanswered and the offer was withdrawn. Nothing on the board changed. "
        .. "The game is about to ask the same decision again -- please answer it with one of the actions it lists.")
  end
  return superseded
end

function M.liveness_stall_repeats(state_name)
  if not (G and G.NEURO) or G.NEURO.force_liveness_fingerprint == nil then return 0 end
  if state_name ~= nil and G.NEURO.force_liveness_state ~= state_name then return 0 end
  return tonumber(G.NEURO.force_liveness_repeat) or 0
end

function M.cancel_pending(now)
  if not (G and G.NEURO) then return nil end
  local pending = G.NEURO.force_cancel_pending
  if type(pending) ~= "table" then return nil end
  now = tonumber(now) or Utils.gate_now("cancel_settle")
  if pending.phase == "sending" then
    if type(pending.receipt) == "table" and pending.receipt.status == "written" then
      finish_cancellation(pending, now)
    elseif pending.receipt == nil or pending.receipt.status == "rejected" then
      attempt_cancellation(pending, now)
    end
    local age = now - (tonumber(pending.started_at) or now)
    if age >= tuned("cancel_settle", "NEURO_FORCE_CANCEL_IDLE", M.CANCEL_IDLE_CAP) then
      if not pending.stalled then
        pending.stalled = true
        Metrics.incr("force_cancel_stalled")
        print("[neuro-game] Force cancellation could not reach the transport; pausing Neuro until the withdrawal is durable rather than risking an overlapping force")
        ContextDelivery.prompt_at("force_cancel_stalled",
          ContextDelivery.here("decision " .. tostring(G.NEURO.decision_serial or 0)),
          "The transport failed while withdrawing the previous action force here. Play was held at that point until the withdrawal became durable, and no overlapping force was sent.")
      end
      local window = M.window()
      if type(window) == "table" then Window.finish(window) end
      G.NEURO.force_inflight = false
      G.NEURO.force_state = nil
      G.NEURO.force_sent_at = nil
      G.NEURO.force_cancel_pending = nil
      G.NEURO.force_transport_fault = {
        reason = "cancel_not_durable", at = now, attempts = pending.attempts or 0,
        pending = pending,
      }
      G.NEURO.force_transport_pause_prior = G.NEURO.llm_paused
      G.NEURO.force_transport_paused = true
      G.NEURO.llm_paused = true
      Metrics.incr("force_cancel_fail_closed")
      return nil
    end
    return G.NEURO.force_cancel_pending
  end
  local at = tonumber(pending.at) or 0
  if (tonumber(G.NEURO.last_action_real_at) or -1) > at then
    G.NEURO.force_cancel_pending = nil
    return nil
  end
  if (now - at) >= tuned("cancel_settle", "NEURO_FORCE_CANCEL_SETTLE", M.CANCEL_SETTLE) then
    G.NEURO.force_cancel_pending = nil
    Metrics.incr("force_cancel_settled")
    return nil
  end
  if (now - at) >= tuned("cancel_settle", "NEURO_FORCE_CANCEL_IDLE", M.CANCEL_IDLE_CAP) then
    G.NEURO.force_cancel_pending = nil
    Metrics.incr("force_cancel_idle_released")
    return nil
  end
  return pending
end

function M.cancel_blocks(name, now)
  local pending = M.cancel_pending(now)
  return not not (pending and name and pending.set[name])
end

function M.clear_cancel_pending()
  if G and G.NEURO then G.NEURO.force_cancel_pending = nil end
end

function M.supersede(now, result)
  return M.invalidate(result or "superseded", now)
end

local function release_transport_pause()
  if not (G and G.NEURO) then return end
  G.NEURO.force_transport_fault = nil
  if not G.NEURO.force_transport_paused then return end
  local prior_pause = G.NEURO.force_transport_pause_prior
  G.NEURO.force_transport_paused = nil
  G.NEURO.force_transport_pause_prior = nil
  G.NEURO.llm_paused = prior_pause
end

function M.transport_fault_step(now)
  if not (G and G.NEURO) then return false end
  local fault = G.NEURO.force_transport_fault
  if type(fault) ~= "table" or fault.reason ~= "cancel_not_durable" then return false end
  local pending = fault.pending
  if type(pending) ~= "table" then return false end
  now = tonumber(now) or Utils.gate_now("cancel_settle")
  local receipt = pending.receipt
  local durable = type(receipt) == "table" and receipt.status == "written"
  if durable then
    if not finish_cancellation(pending, now) then return false end
  else
    if type(receipt) == "table" and receipt.status ~= "rejected" then return false end
    if G.NEURO.is_transport_saturated and G.NEURO:is_transport_saturated() then return false end
    if not attempt_cancellation(pending, now) then return false end
  end
  G.NEURO.force_cancel_pending = pending
  release_transport_pause()
  Metrics.incr("force_cancel_fault_recovered")
  print("[neuro-game] Force cancellation reached the transport after all; resuming Neuro")
  Lifecycle.mark_force_dirty()
  return true
end

function M.reconnect()
  if not (G and G.NEURO) then return end
  if G.NEURO.force_inflight or Window.is_open(M.window()) then
    G.NEURO.force_last_result = "reconnect"
  end
  M.clear_force_state()
  Lifecycle.clear_pending_confirm()
  ack_scope_reset()
  M.clear_cancel_pending()
  release_transport_pause()
  local ok_enforce, Enforce = pcall(require, "core.enforce")
  if ok_enforce and Enforce and Enforce.reset_streaks then Enforce.reset_streaks() end
  Lifecycle.mark_force_dirty()
end

function M.mark_answered()
  if not (G and G.NEURO) then return end
  G.NEURO.force_liveness_fingerprint = nil
  G.NEURO.force_liveness_repeat = 0
  G.NEURO.force_liveness_state = nil
  if G.NEURO.force_inflight or Window.is_open(M.window()) then
    G.NEURO.force_last_result = "answered"
  end
end

function M.rearm()
  Lifecycle.mark_force_dirty()
end

local function copy_store(store)
  if type(store) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(store) do out[k] = v end
  return out
end

function M.snapshot_once_serials()
  if not (G and G.NEURO) then return nil end
  local run = copy_store(G.NEURO.once_serials)
  local session = copy_store(G.NEURO.session_once_serials)
  if not run and not session then return nil end
  return { run = run, session = session }
end

function M.restore_once_serials(snap)
  if not (G and G.NEURO) then return end
  if type(snap) ~= "table" then
    G.NEURO.once_serials = nil
    G.NEURO.session_once_serials = nil
    return
  end
  G.NEURO.once_serials = snap.run
  G.NEURO.session_once_serials = snap.session
end

M.record_failure = Lifecycle.record_failure

-- The correction is an imperative about one instant ("choose again"), so it rides the force that
-- carries the new offer -- every force declares ephemeral_context, and SPECIFICATION.md:156 makes
-- Neuro forget it when that force completes. context has no expiry, so it must never go there.
function M.correct_optimistic(action, reason, action_id, correction)
  if not (G and G.NEURO) then return end
  if (action == "choose_pack_card" or action == "choose_directional_pack_card") and (G.NEURO.pack_exit_pending == true
      or G.NEURO.pack_exit_pending == tostring(action_id)) then
    G.NEURO.pack_exit_pending = nil
  end
  Lifecycle.record_failure(action, reason, correction)
  Lifecycle.mark_force_dirty()
end

function M.force_is_stale(built_state, force)
  local ok_s, State = pcall(require, "core.state")
  if ok_s and State and type(State.get_state_name) == "function" then
    local ok_n, current = pcall(State.get_state_name)
    if ok_n and current and current ~= built_state then return true end
  end
  if built_state == "BLIND_SELECT" and type(force) == "table" and force.blind then
    local now_key = Actions.get_selectable_blind_key and Actions.get_selectable_blind_key() or nil
    if not now_key or string.lower(now_key) ~= tostring(force.blind) then return true end
  end
  return false
end

if rawget(_G, "NEURO_TEST") then
  M._test = {
    is_inflight = is_inflight,
    window_owns = window_owns,
  }
end

return M
