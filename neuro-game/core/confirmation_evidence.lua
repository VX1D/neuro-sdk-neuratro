local M = {}

local ROLLBACK_FIELDS = { "weak_fired_serial", "pending_confirmation", "play_confirm" }

local function neuro()
  return G and G.NEURO
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
  if tonumber(candidate.run_generation) ~= (tonumber(n.run_generation) or 0) then return false end
  if tonumber(candidate.decision_serial) ~= (tonumber(n.decision_serial) or 0) then return false end
  return true
end

function M.candidate(signature, content, indices, hand_type)
  local n = neuro()
  if not n then return nil end
  if type(signature) ~= "string" or signature == "" then return nil end
  return {
    signature = signature,
    content = content,
    indices = copy_indices(indices),
    hand_type = type(hand_type) == "string" and hand_type ~= "" and hand_type or nil,
    decision_serial = tonumber(n.decision_serial) or 0,
    run_generation = tonumber(n.run_generation) or 0,
  }
end

function M.stage(candidate, final_wire_text, receipt, rollback_snapshot)
  local n = neuro()
  if not (n and identity_matches(candidate)) then return false end
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
    if still_current then restore_rollback(delivery.rollback_snapshot) end
    return false
  end
  if not still_current then return false end
  local c = delivery.candidate
  n.pending_confirmation = {
    signature = c.signature,
    content = c.content,
    indices = copy_indices(c.indices),
    hand_type = c.hand_type,
    rendered_verdict = delivery.final_wire_text,
    decision_serial = c.decision_serial,
    run_generation = c.run_generation,
  }
  return true
end

function M.current()
  local n = neuro()
  local committed = n and n.pending_confirmation
  if not identity_matches(committed) then return nil end
  if type(committed.rendered_verdict) ~= "string" or committed.rendered_verdict == "" then return nil end
  return committed
end

function M.render()
  local committed = M.current()
  return committed and committed.rendered_verdict or nil, committed
end

function M.clear()
  local n = neuro()
  if not n then return end
  n.confirmation_delivery = nil
  n.pending_confirmation = nil
end

if rawget(_G, "NEURO_TEST") then M._test = { identity_matches = identity_matches } end

return M
