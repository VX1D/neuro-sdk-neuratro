-- Authoritative runtime-state operations on G.NEURO.
local M = {}
local Utils = require("util.utils")

-- stamp a rejected action: always set all three fields so no consumer reads a stale reason (reason may be nil)
function M.record_failure(name, reason)
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = name
  G.NEURO.last_failed_reason = reason
  G.NEURO.last_failed_at = Utils.now()
end

function M.clear_failure()
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = nil
  G.NEURO.last_failed_reason = nil
  G.NEURO.last_failed_at = nil
end

-- drop_fingerprint (default) also clears the dedup fingerprint; pass false to bump only force_dirty/at
function M.mark_force_dirty(drop_fingerprint)
  if not Utils.neuro_ready() then return end
  if drop_fingerprint ~= false then G.NEURO.last_force_fingerprint = nil end
  G.NEURO.force_dirty = true
  G.NEURO.force_dirty_at = Utils.now()
end

function M.reset_run_state()
  if not Utils.neuro_ready() then return end
  G.NEURO.action_history      = nil
  G.NEURO.recent_actions      = nil
  G.NEURO.once_serials        = nil
  G.NEURO.hand_level_snapshot = nil
  G.NEURO.last_failed_action  = nil
  G.NEURO.last_failed_reason  = nil
  G.NEURO.last_failed_at      = nil
  G.NEURO.shop_reroll_count   = nil
  G.NEURO.state_enter_serial  = 0
end

return M
