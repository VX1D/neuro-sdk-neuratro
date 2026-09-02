local M = {}

-- Confirmation state belongs to the active transaction.
local ROLLBACK_FIELDS = { "weak_fired_serial" }

local function neuro()
  return G and G.NEURO
end

local function release_hand_plan(transaction_id)
  if transaction_id == nil then return end
  local ok, PlanTransaction = pcall(require, "core.plan_transaction")
  if ok and PlanTransaction and PlanTransaction.release_hand_proposal then
    pcall(PlanTransaction.release_hand_proposal, transaction_id)
  end
end

local function copy_indices(indices)
  local out = {}
  for i, value in ipairs(indices or {}) do out[i] = value end
  return out
end

local function copy_candidate(candidate)
  return {
    signature = candidate.signature,
    content = candidate.content,
    indices = copy_indices(candidate.indices),
    hand_type = candidate.hand_type,
    transaction_id = candidate.transaction_id,
    context_revision = candidate.context_revision,
    state_enter_serial = candidate.state_enter_serial,
    decision_serial = candidate.decision_serial,
    run_generation = candidate.run_generation,
  }
end

local function copy_rollback(snapshot)
  if type(snapshot) ~= "table" then return nil end
  local out = {}
  for i = 1, #ROLLBACK_FIELDS do
    local key = ROLLBACK_FIELDS[i]
    out[key] = snapshot[key]
  end
  return out
end

local function restore_rollback(snapshot)
  local n = neuro()
  if not (n and type(snapshot) == "table") then return end
  for i = 1, #ROLLBACK_FIELDS do
    local key = ROLLBACK_FIELDS[i]
    n[key] = snapshot[key]
  end
end

local function identity_matches(candidate)
  local n = neuro()
  if not (n and type(candidate) == "table") then return false end
  if candidate.transaction_id ~= nil then
    local ok, HandTx = pcall(require, "core.hand_transaction")
    if not ok or not HandTx or not HandTx.is_current_id(candidate.transaction_id) then return false end
    local tx = HandTx.current()
    if not tx or (tx.phase ~= "publishing" and tx.phase ~= "ready") then return false end
    if tonumber(candidate.state_enter_serial) ~= (tonumber(n.state_enter_serial) or 0) then return false end
    if tonumber(candidate.context_revision) ~= HandTx.context_revision() then return false end
  end
  if tonumber(candidate.state_enter_serial) ~= (tonumber(n.state_enter_serial) or 0) then return false end
  if tonumber(candidate.run_generation) ~= (tonumber(n.run_generation) or 0) then return false end
  if tonumber(candidate.decision_serial) ~= (tonumber(n.decision_serial) or 0) then return false end
  return true
end

function M.candidate(signature, content, indices, hand_type, transaction_id, context_revision)
  local n = neuro()
  if not n then return nil end
  if type(signature) ~= "string" or signature == "" then return nil end
  if transaction_id == nil then
    local ok, HandTx = pcall(require, "core.hand_transaction")
    if ok and HandTx and HandTx.current then
      local tx = HandTx.current()
      transaction_id = tx and tx.id or nil
      context_revision = context_revision or (tx and tx.context_revision)
    end
  end
  return {
    signature = signature,
    content = content,
    indices = copy_indices(indices),
    hand_type = type(hand_type) == "string" and hand_type ~= "" and hand_type or nil,
    transaction_id = tonumber(transaction_id),
    context_revision = tonumber(context_revision),
    state_enter_serial = tonumber(n.state_enter_serial) or 0,
    decision_serial = tonumber(n.decision_serial) or 0,
    run_generation = tonumber(n.run_generation) or 0,
  }
end

function M.stage(candidate, final_wire_text, receipt, rollback_snapshot)
  local n = neuro()
  if not (n and identity_matches(candidate)) then return false end
  if candidate.transaction_id ~= nil then
    local ok_tx, HandTx = pcall(require, "core.hand_transaction")
    local tx = ok_tx and HandTx and HandTx.current()
    if not tx or tx.phase ~= "publishing" then return false end
  end
  if type(final_wire_text) ~= "string" or final_wire_text == "" then return false end
  if type(receipt) ~= "table" then return false end
  n.confirmation_delivery = {
    candidate = copy_candidate(candidate),
    final_wire_text = final_wire_text,
    result_receipt = receipt,
    rollback_snapshot = copy_rollback(rollback_snapshot),
  }
  return true
end

function M.has_staged_delivery()
  return neuro() and neuro().confirmation_delivery ~= nil or false
end

function M.step_delivery()
  local n = neuro()
  local delivery = n and n.confirmation_delivery
  if type(delivery) ~= "table" then return false end
  local receipt = delivery.result_receipt
  local status = type(receipt) == "table" and receipt.status or nil
  if status == "sending" or status == "buffered" then return false end
  local still_current = identity_matches(delivery.candidate)
  n.confirmation_delivery = nil
  if status ~= "written" then
    release_hand_plan(delivery.candidate and delivery.candidate.transaction_id)
    if still_current then
      restore_rollback(delivery.rollback_snapshot)
      local ok_tx, HandTx = pcall(require, "core.hand_transaction")
      if ok_tx and HandTx and HandTx.is_current_id(delivery.candidate.transaction_id) then
        HandTx.invalidate(HandTx.current(), "confirmation_result_not_written")
      end
    end
    return false
  end
  if not still_current then
    release_hand_plan(delivery.candidate and delivery.candidate.transaction_id)
    return false
  end
  local c = delivery.candidate
  local ok_tx, HandTx = pcall(require, "core.hand_transaction")
  if c.transaction_id ~= nil and (not ok_tx or not HandTx
      or not HandTx.promote_ready(HandTx.current(), c.context_revision)) then
    release_hand_plan(c.transaction_id)
    return false
  end
  n.pending_confirmation = {
    signature = c.signature,
    content = c.content,
    indices = copy_indices(c.indices),
    hand_type = c.hand_type,
    transaction_id = c.transaction_id,
    context_revision = c.context_revision,
    state_enter_serial = c.state_enter_serial,
    rendered_verdict = delivery.final_wire_text,
    decision_serial = c.decision_serial,
    run_generation = c.run_generation,
  }
  local ok_lifecycle, Lifecycle = pcall(require, "core.neuro_lifecycle")
  if ok_lifecycle and Lifecycle and Lifecycle.mark_force_dirty then Lifecycle.mark_force_dirty() end
  return true
end

function M.current()
  local n = neuro()
  local committed = n and n.pending_confirmation
  if not identity_matches(committed) then return nil end
  if committed.transaction_id ~= nil then
    local ok, HandTx = pcall(require, "core.hand_transaction")
    local tx = ok and HandTx and HandTx.current()
    if not tx or tx.phase ~= "ready" or tx.id ~= tonumber(committed.transaction_id) then return nil end
  end
  if type(committed.rendered_verdict) ~= "string" or committed.rendered_verdict == "" then return nil end
  return committed
end

function M.render()
  local committed = M.current()
  return committed and committed.rendered_verdict or nil, committed
end

function M.clear(transaction_id)
  local n = neuro()
  if not n then return end
  if transaction_id ~= nil then
    local committed = n.pending_confirmation
    local delivery = n.confirmation_delivery
    if type(committed) == "table" and tonumber(committed.transaction_id) == tonumber(transaction_id) then
      n.pending_confirmation = nil
    end
    if type(delivery) == "table" and type(delivery.candidate) == "table"
        and tonumber(delivery.candidate.transaction_id) == tonumber(transaction_id) then
      n.confirmation_delivery = nil
    end
    return
  end
  n.confirmation_delivery = nil
  n.pending_confirmation = nil
end

if rawget(_G, "NEURO_TEST") then M._test = { identity_matches = identity_matches } end

return M
