local Utils = require("util.utils")

local M = {}

local RETRY, TERMINAL, WAIT = "retry", "terminal", "wait"

M.CODES = {
  CONFIRMATION_REQUIRED = TERMINAL,
  POLICY_ACKNOWLEDGED = TERMINAL,
  UNCHANGED = RETRY,
  TRANSITION_PENDING = WAIT,
  SCHEMA_INVALID = RETRY,
  ACTION_UNAVAILABLE = RETRY,
  ACTION_UNREGISTERED = RETRY,
  ACTION_UNKNOWN = RETRY,
  TARGET_UNAVAILABLE = RETRY,
  PRECONDITION_FAILED = RETRY,
  POLICY_REJECTED = RETRY,
  INTERNAL_ERROR = RETRY,
  ACTION_REJECTED = RETRY,
  INSUFFICIENT_FUNDS = RETRY,
  NO_SLOT = RETRY,
  STALE_TARGET = RETRY,
  INVALID_SELECTION = RETRY,
}

M.SDK = {
  NO_NAME = "Action failed. Missing command field 'name'. (This is probably not your fault, blame Vedal.)",
  INVALID_JSON = "Action failed. Could not parse action parameters from JSON.",
  UNREGISTERED = "This action has been recently unregistered and can no longer be used.",
  UNKNOWN_ACTION = "Action failed. Unknown action '%s'.",
}

local INTERNAL_ERROR_TEXT = "Something failed on the game side, so nothing ran. Choose again from the actions you are offered."

function M.error(code, message, opts)
  assert(M.CODES[code], "unknown action result code: " .. tostring(code))
  local err = {}
  for k, v in pairs(type(opts) == "table" and opts or {}) do err[k] = v end
  err.__action_error = true
  err.reason_code = code
  err.message = tostring(message or "Action rejected.")
  return err
end

function M.internal_error()
  return M.error("INTERNAL_ERROR", INTERNAL_ERROR_TEXT)
end

function M.reject(code, message, opts)
  return nil, M.error(code, message, opts)
end

local WAIT_RETRY = "Wait a moment, then choose again."
local WAIT_REASKED = "This decision will be offered again once the game settles."

function M.wait(fact, retry, reasked)
  return M.error("TRANSITION_PENDING", fact .. " " .. (retry or WAIT_RETRY),
    { fact = fact, reasked = reasked or WAIT_REASKED })
end

function M.reasked_message(err)
  return err.fact .. " " .. err.reasked
end

function M.unchanged(fact)
  return M.reject("UNCHANGED", fact .. "; nothing changed. Pick a different value or another offered action.")
end

function M.terminal(code, forced)
  local kind = M.CODES[code]
  return kind == TERMINAL or (kind == WAIT and forced == true)
end

local UNRECOGNISED = { ACTION_UNKNOWN = true, ACTION_UNREGISTERED = true }
function M.unrecognised(code)
  return UNRECOGNISED[code] == true
end

function M.is_error(value)
  return type(value) == "table" and value.__action_error == true
    and M.CODES[value.reason_code] ~= nil and type(value.message) == "string"
end

function M.normalize(value, fallback_code)
  if M.is_error(value) then return value end
  if type(value) == "table" and M.CODES[value.reason_code] and type(value.message) == "string" then
    return M.error(value.reason_code, value.message, value)
  end
  if type(value) ~= "string" then return M.internal_error() end
  return M.error(fallback_code or "ACTION_REJECTED", value)
end

function M.now() return Utils.gate_now("receipt_deadline") end

local FINAL = { applied = true, failed = true, ambiguous = true }
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

function M.create(opts)
  assert(type(opts) == "table", "receipt options required")
  assert(type(opts.id) == "string" and opts.id ~= "", "receipt id required")
  assert(type(opts.name) == "string" and opts.name ~= "", "receipt action name required")
  assert(type(opts.probe) == "function", "receipt probe required")
  local started_at = tonumber(opts.started_at) or M.now()
  local deadline = tonumber(opts.deadline)
  assert(deadline and deadline >= started_at, "receipt deadline must not precede start")
  local timeout_outcome = opts.timeout_outcome or "ambiguous"
  assert(timeout_outcome == "failed" or timeout_outcome == "ambiguous",
    "receipt timeout outcome must be failed or ambiguous")
  return {
    __action_receipt = true,
    id = opts.id,
    name = opts.name,
    run_generation = tonumber(opts.run_generation) or 0,
    started_at = started_at,
    deadline = deadline,
    timeout_outcome = timeout_outcome,
    allow_generation_change = opts.allow_generation_change == true,
    correction = tostring(opts.correction or "It could not be verified. Inspect the current state and choose again."),
    applied_message = type(opts.applied_message) == "string" and opts.applied_message or nil,
    debug = clean_value(opts.debug, 0),
    probe = opts.probe,
    on_applied = opts.on_applied,
    on_failed = opts.on_failed,
    cleanup = opts.cleanup,
  }
end

function M.is_receipt(value)
  return type(value) == "table" and value.__action_receipt == true
end

local function hook_failed(receipt, hook, err)
  print("[neuro-game] receipt " .. safe_tostring(receipt.name) .. " " .. hook .. " failed: " .. safe_tostring(err))
end

function M.finish(receipt, outcome, details, quiet)
  if not M.is_receipt(receipt) or receipt.phase then return false end
  assert(FINAL[outcome], "invalid receipt outcome: " .. tostring(outcome))
  receipt.phase = outcome
  receipt.details = clean_value(details, 0)
  local callback = not quiet and (outcome == "applied" and receipt.on_applied or receipt.on_failed) or nil
  if callback then
    local ok, err = pcall(callback, receipt, receipt.details)
    if not ok then hook_failed(receipt, "outcome callback", err) end
  end
  if receipt.cleanup then
    local ok, err = pcall(receipt.cleanup, receipt, outcome)
    if not ok then hook_failed(receipt, "cleanup", err) end
  end
  receipt.probe, receipt.on_applied, receipt.on_failed, receipt.cleanup = nil, nil, nil, nil
  return true
end

function M.settle(receipt, now, run_generation)
  if receipt.phase then return true end
  now = tonumber(now) or M.now()
  if now < receipt.started_at then
    receipt.deadline = now + (receipt.deadline - receipt.started_at)
    receipt.started_at = now
  end
  local stale = tonumber(run_generation) ~= nil and receipt.run_generation ~= tonumber(run_generation)
  if stale and not receipt.allow_generation_change then
    return M.finish(receipt, "ambiguous", { reason = "stale_generation" }, true)
  end
  local ok, outcome, details = pcall(receipt.probe, receipt)
  if stale then
    if ok and outcome == "applied" then return M.finish(receipt, "applied", details) end
    return M.finish(receipt, "ambiguous", { reason = "stale_generation" }, true)
  end
  if not ok then return M.finish(receipt, "ambiguous", { reason = "probe_error", error = tostring(outcome) }) end
  if FINAL[outcome] then return M.finish(receipt, outcome, details) end
  if outcome ~= "pending" then
    return M.finish(receipt, "ambiguous", { reason = "invalid_probe_outcome", value = tostring(outcome) })
  end
  if now >= receipt.deadline then return M.finish(receipt, receipt.timeout_outcome, { reason = "deadline" }) end
  return false
end

function M.outcome(status, message, details)
  assert(FINAL[status], "invalid action outcome: " .. tostring(status))
  return { __action_outcome = true, status = status, message = message, details = clean_value(details, 0) }
end

function M.is_outcome(value)
  return type(value) == "table" and value.__action_outcome == true and FINAL[value.status] == true
end


function M.done()
  return { __execution_done = true }
end

function M.is_done(value)
  return type(value) == "table" and value.__execution_done == true
end

return M
