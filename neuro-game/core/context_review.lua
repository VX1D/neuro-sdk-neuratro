local M = {}

local SUPPORTED = { sell_joker = true, buy_voucher = true }

local function neuro()
  return G and G.NEURO
end

local function records(create)
  local n = neuro()
  if not n then return nil end
  if create and type(n.context_reviews) ~= "table" then n.context_reviews = {} end
  return type(n.context_reviews) == "table" and n.context_reviews or nil
end

local function valid_candidate(candidate)
  local n = neuro()
  return n ~= nil and type(candidate) == "table"
    and SUPPORTED[candidate.kind] == true
    and type(candidate.context_key) == "string" and candidate.context_key ~= ""
    and tonumber(candidate.run_generation) == (tonumber(n.run_generation) or 0)
    and tonumber(candidate.state_enter_serial) == (tonumber(n.state_enter_serial) or 0)
end

function M.candidate(kind, context_key, details)
  local n = neuro()
  if not n or not SUPPORTED[kind] or type(context_key) ~= "string" or context_key == "" then
    return nil
  end
  return {
    kind = kind,
    context_key = context_key,
    details = type(details) == "table" and details or {},
    run_generation = tonumber(n.run_generation) or 0,
    state_enter_serial = tonumber(n.state_enter_serial) or 0,
  }
end

function M.stage(candidate, receipt)
  if not valid_candidate(candidate) or type(receipt) ~= "table" then return false end
  local rs = records(true)
  local old = rs[candidate.kind]
  if old and old.phase == "publishing" then return false end
  rs[candidate.kind] = {
    kind = candidate.kind,
    phase = "publishing",
    context_key = candidate.context_key,
    reviewed_target = candidate.details and candidate.details.target or nil,
    result_receipt = receipt,
    run_generation = candidate.run_generation,
    state_enter_serial = candidate.state_enter_serial,
  }
  return true
end

function M.has_staged_delivery()
  for _, record in pairs(records(false) or {}) do
    if record.phase == "publishing" then return true end
  end
  return false
end

function M.step_delivery()
  local n, changed = neuro(), false
  local rs = records(false)
  if not (n and rs) then return false end
  for kind, record in pairs(rs) do
    if record.phase == "publishing" then
      local receipt = record.result_receipt
      local status = type(receipt) == "table" and receipt.status or nil
      if status ~= "sending" and status ~= "buffered" then
        if status == "written"
            and record.run_generation == (tonumber(n.run_generation) or 0)
            and record.state_enter_serial == (tonumber(n.state_enter_serial) or 0) then
          record.phase = "reviewed"
          record.result_receipt = nil
        else
          rs[kind] = nil
        end
        changed = true
      end
    end
  end
  if changed then
    local ok, Lifecycle = pcall(require, "core.neuro_lifecycle")
    if ok and Lifecycle and Lifecycle.mark_force_dirty then Lifecycle.mark_force_dirty() end
  end
  return changed
end

function M.is_reviewed(kind, live_context_key)
  local rs = records(false)
  local record = rs and rs[kind]
  if not record then return false end
  if not valid_candidate({
      kind = record.kind, context_key = record.context_key,
      run_generation = record.run_generation,
      state_enter_serial = record.state_enter_serial,
    }) or record.context_key ~= live_context_key then
    rs[kind] = nil
    return false
  end
  return record.phase == "reviewed"
end

function M.note(kind, live_context_key)
  if not M.is_reviewed(kind, live_context_key) then return nil end
  return records(false)[kind].reviewed_target
end

function M.clear(kind, expected_context_key)
  local rs = records(false)
  local record = rs and rs[kind]
  if not record then return false end
  if expected_context_key ~= nil and record.context_key ~= expected_context_key then return false end
  rs[kind] = nil
  return true
end

function M.reset()
  local n = neuro()
  if n then n.context_reviews = nil end
end

return M
