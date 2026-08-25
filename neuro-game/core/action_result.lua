local M = {}

M.CODES = {
  CONFIRMATION_REQUIRED = { safe_to_retry = true, transient = false, acknowledge = true },
  SCHEMA_INVALID = { safe_to_retry = false, transient = false },
  ACTION_UNAVAILABLE = { safe_to_retry = false, transient = false },
  ACTION_UNREGISTERED = { safe_to_retry = false, transient = false, acknowledge = true },
  FORCE_EXPIRED = { safe_to_retry = false, transient = false, acknowledge = true },
  ACTION_UNKNOWN = { safe_to_retry = false, transient = true },
  TARGET_UNAVAILABLE = { safe_to_retry = false, transient = false },
  PRECONDITION_FAILED = { safe_to_retry = false, transient = false },
  TRANSITION_PENDING = { safe_to_retry = true, transient = true },
  TRANSITION_ACKNOWLEDGED = { safe_to_retry = false, transient = true, acknowledge = true },
  STALE_GENERATION = { safe_to_retry = false, transient = false, acknowledge = true },
  POLICY_REJECTED = { safe_to_retry = false, transient = false },
  POLICY_ACKNOWLEDGED = { safe_to_retry = false, transient = false, acknowledge = true },
  INTERNAL_ERROR = { safe_to_retry = false, transient = false },
  ACTION_REJECTED = { safe_to_retry = false, transient = false },
  INSUFFICIENT_FUNDS = { safe_to_retry = false, transient = false },
  NO_SLOT = { safe_to_retry = false, transient = false },
  STALE_TARGET = { safe_to_retry = false, transient = false },
  INVALID_SELECTION = { safe_to_retry = false, transient = false },
}

local function copy_fields(src, dst)
  if type(src) ~= "table" then return dst end
  for k, v in pairs(src) do dst[k] = v end
  return dst
end

function M.error(code, message, opts)
  local policy = M.CODES[code]
  assert(policy, "unknown action result code: " .. tostring(code))
  local err = copy_fields(opts, {
    __action_error = true,
    reason_code = code,
    message = tostring(message or "Action rejected."),
    transient = policy.transient,
    safe_to_retry = policy.safe_to_retry,
    state_mutated = false,
  })
  err.reason_code = code
  err.message = tostring(message or err.message or "Action rejected.")
  if err.transient == nil then err.transient = policy.transient end
  if err.safe_to_retry == nil then err.safe_to_retry = policy.safe_to_retry end
  if err.state_mutated == nil then err.state_mutated = false end
  return err
end

function M.reject(code, message, opts)
  return nil, M.error(code, message, opts)
end

function M.acknowledges(code, opts)
  if type(opts) == "table" and opts.acknowledged == true then return true end
  local policy = code ~= nil and M.CODES[code] or nil
  return not not (policy and policy.acknowledge)
end

function M.safe_to_retry(code, opts)
  if type(opts) == "table" and opts.safe_to_retry ~= nil then return not not opts.safe_to_retry end
  local policy = code ~= nil and M.CODES[code] or nil
  return not not (policy and policy.safe_to_retry)
end

function M.is_transient(code, opts)
  if type(opts) == "table" and opts.transient ~= nil then return not not opts.transient end
  local policy = code ~= nil and M.CODES[code] or nil
  return not not (policy and policy.transient)
end

function M.is_error(value)
  return type(value) == "table"
    and value.__action_error == true
    and M.CODES[value.reason_code] ~= nil
    and type(value.message) == "string"
end

function M.normalize(value, fallback_code)
  if M.is_error(value) then return value end
  if type(value) == "table" and M.CODES[value.reason_code] then
    return M.error(value.reason_code, value.message, value)
  end
  return M.error(fallback_code or "ACTION_REJECTED", value)
end

function M.validate(value)
  if not M.is_error(value) then return false, "not a typed action error" end
  if type(value.transient) ~= "boolean" then return false, "transient must be boolean" end
  if type(value.safe_to_retry) ~= "boolean" then return false, "safe_to_retry must be boolean" end
  if type(value.state_mutated) ~= "boolean" then return false, "state_mutated must be boolean" end
  return true
end

return M
