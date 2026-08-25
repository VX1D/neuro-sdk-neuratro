local Utils = require("util.utils")

local M = {}
local active = {}

function M.now() return Utils.gate_now("receipt_deadline") end

local TERMINAL = { applied = true, failed = true, ambiguous = true }
local NEXT = {
  prepared = { acknowledged = true },
  acknowledged = { executing = true },
  executing = { verifying = true },
}

local function safe_call(fn, ...)
  if type(fn) ~= "function" then return true end
  return pcall(fn, ...)
end

local safe_tostring = Utils.safe_tostring

local function clean_value(value, depth)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then return value end
  if kind ~= "table" or depth >= 4 then return safe_tostring(value) end
  local out = {}
  for key, child in pairs(value) do
    local key_kind = type(key)
    if key_kind == "string" or key_kind == "number" then
      out[key] = clean_value(child, depth + 1)
    end
  end
  return out
end

local function finish(receipt, outcome, details, suppress_callback)
  if not receipt or TERMINAL[receipt.phase] then return receipt, false end
  assert(TERMINAL[outcome], "invalid receipt outcome: " .. tostring(outcome))
  receipt.phase = outcome
  receipt.finished_at = M.now()
  receipt.details = clean_value(details, 0)
  active[receipt.id] = nil
  local callback = not suppress_callback and (outcome == "applied" and receipt.on_applied or receipt.on_failed) or nil
  local callback_ok, callback_err = safe_call(callback, receipt, receipt.details)
  receipt.callback_error = callback_ok and nil or safe_tostring(callback_err)
  local cleanup_ok, cleanup_err = safe_call(receipt.cleanup, receipt, outcome)
  receipt.cleanup_error = cleanup_ok and nil or safe_tostring(cleanup_err)
  receipt.cleanup = nil
  receipt.on_applied = nil
  receipt.on_failed = nil
  receipt.probe = nil
  return receipt, true
end

function M.create(opts)
  assert(type(opts) == "table", "receipt options required")
  assert(type(opts.id) == "string" and opts.id ~= "", "receipt id required")
  assert(type(opts.name) == "string" and opts.name ~= "", "receipt action name required")
  assert(type(opts.probe) == "function", "receipt probe required")
  assert(active[opts.id] == nil, "active receipt already exists: " .. opts.id)
  local started_at = tonumber(opts.started_at) or M.now()
  local deadline = tonumber(opts.deadline)
  assert(deadline and deadline >= started_at, "receipt deadline must not precede start")
  local timeout_outcome = opts.timeout_outcome or "ambiguous"
  assert(timeout_outcome == "failed" or timeout_outcome == "ambiguous",
    "receipt timeout outcome must be failed or ambiguous")
  local receipt = {
    __action_receipt = true,
    id = opts.id,
    name = opts.name,
    run_generation = tonumber(opts.run_generation) or 0,
    started_at = started_at,
    deadline = deadline,
    timeout_outcome = timeout_outcome,
    allow_generation_change = opts.allow_generation_change == true,
    correction = tostring(opts.correction or "The accepted action could not be verified; inspect the current state and choose again."),
    applied_message = type(opts.applied_message) == "string" and opts.applied_message or nil,
    debug = clean_value(opts.debug, 0),
    phase = "prepared",
    probe = opts.probe,
    on_applied = opts.on_applied,
    on_failed = opts.on_failed,
    cleanup = opts.cleanup,
  }
  active[receipt.id] = receipt
  return receipt
end

function M.is_receipt(value)
  return type(value) == "table" and value.__action_receipt == true
end

function M.transition(receipt, phase)
  assert(M.is_receipt(receipt), "action receipt required")
  if TERMINAL[receipt.phase] then return receipt, false end
  assert(NEXT[receipt.phase] and NEXT[receipt.phase][phase],
    "invalid receipt transition: " .. tostring(receipt.phase) .. " -> " .. tostring(phase))
  receipt.phase = phase
  return receipt, true
end

function M.complete(receipt, outcome, details)
  assert(M.is_receipt(receipt), "action receipt required")
  return finish(receipt, outcome, details)
end

function M.abandon(receipt, outcome, details)
  assert(M.is_receipt(receipt), "action receipt required")
  return finish(receipt, outcome or "ambiguous", details, true)
end

function M.chain_callbacks(receipt, on_applied, on_failed)
  assert(M.is_receipt(receipt), "action receipt required")
  assert(not TERMINAL[receipt.phase], "cannot attach callbacks to terminal receipt")
  local prior_applied, prior_failed = receipt.on_applied, receipt.on_failed
  receipt.on_applied = function(...)
    local prior_ok, prior_err = safe_call(prior_applied, ...)
    local next_ok, next_err = safe_call(on_applied, ...)
    if not prior_ok then error(prior_err, 0) end
    if not next_ok then error(next_err, 0) end
  end
  receipt.on_failed = function(...)
    local prior_ok, prior_err = safe_call(prior_failed, ...)
    local next_ok, next_err = safe_call(on_failed, ...)
    if not prior_ok then error(prior_err, 0) end
    if not next_ok then error(next_err, 0) end
  end
  return receipt
end

function M.outcome(status, message, details)
  assert(TERMINAL[status], "invalid action outcome: " .. tostring(status))
  return {
    __action_outcome = true,
    status = status,
    message = message,
    details = clean_value(details, 0),
  }
end

function M.is_outcome(value)
  return type(value) == "table" and value.__action_outcome == true and TERMINAL[value.status] == true
end

function M.update(now, run_generation)
  now = tonumber(now) or M.now()
  local ids = {}
  for id in pairs(active) do ids[#ids + 1] = id end
  table.sort(ids)
  local completed = {}
  for _, id in ipairs(ids) do
    local receipt = active[id]
    if receipt then
      if now < receipt.started_at then
        receipt.deadline = now + (receipt.deadline - receipt.started_at)
        receipt.started_at = now
      end
      if tonumber(run_generation) ~= nil and receipt.run_generation ~= tonumber(run_generation) then
        local applied, details = false, nil
        if receipt.allow_generation_change and receipt.phase == "verifying" then
          local ok, outcome, probe_details = pcall(receipt.probe, receipt)
          applied, details = ok and outcome == "applied", probe_details
        end
        if applied then
          finish(receipt, "applied", details)
        else
          finish(receipt, "ambiguous", { reason = "stale_generation" }, true)
        end
        completed[#completed + 1] = receipt
      elseif receipt.phase == "verifying" then
        local ok, outcome, details = pcall(receipt.probe, receipt)
        if not ok then
          finish(receipt, "ambiguous", { reason = "probe_error", error = tostring(outcome) })
          completed[#completed + 1] = receipt
        elseif TERMINAL[outcome] then
          finish(receipt, outcome, details)
          completed[#completed + 1] = receipt
        elseif outcome ~= "pending" then
          finish(receipt, "ambiguous", { reason = "invalid_probe_outcome", value = tostring(outcome) })
          completed[#completed + 1] = receipt
        elseif now >= receipt.deadline then
          finish(receipt, receipt.timeout_outcome, { reason = "deadline" })
          completed[#completed + 1] = receipt
        end
      elseif now >= receipt.deadline then
        finish(receipt, receipt.timeout_outcome, { reason = "deadline", phase = receipt.phase })
        completed[#completed + 1] = receipt
      end
    end
  end
  return completed
end

function M.get(id)
  return active[tostring(id)]
end

function M.has_active()
  return M.active_count() > 0
end

function M.active_count()
  local count = 0
  for _ in pairs(active) do count = count + 1 end
  return count
end

function M.reset(reason)
  local ids = {}
  for id in pairs(active) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local receipt = active[id]
    if receipt then
      receipt.phase = "ambiguous"
      receipt.finished_at = M.now()
      receipt.details = { reason = reason or "reset" }
      active[id] = nil
      local cleanup_ok, cleanup_err = safe_call(receipt.cleanup, receipt, "ambiguous")
      receipt.cleanup_error = cleanup_ok and nil or safe_tostring(cleanup_err)
      receipt.cleanup = nil
      receipt.on_applied = nil
      receipt.on_failed = nil
      receipt.probe = nil
    end
  end
end

function M.debug_snapshot(receipt)
  assert(M.is_receipt(receipt), "action receipt required")
  return clean_value({
    id = receipt.id,
    name = receipt.name,
    run_generation = receipt.run_generation,
    started_at = receipt.started_at,
    deadline = receipt.deadline,
    phase = receipt.phase,
    timeout_outcome = receipt.timeout_outcome,
    allow_generation_change = receipt.allow_generation_change,
    details = receipt.details,
    debug = receipt.debug,
  }, 0)
end

return M
