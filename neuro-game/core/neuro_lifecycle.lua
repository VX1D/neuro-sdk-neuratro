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

local RUN_SCOPED_NIL = {
  "force_state", "force_action_names", "force_action_set",
  "force_sent_at", "force_dirty_at", "force_last_result",
  "action_phase", "action_phase_at",
  "action_history", "recent_actions", "once_serials", "hand_level_snapshot",
  "last_failed_action", "last_failed_reason", "last_failed_at",
  "last_action_at", "last_action_name", "last_play",
  "shop_reroll_count", "reserved_dollars", "purchase_showcase_queue",
  "stable_ctx_sig", "stable_refresh_due", "stable_sig_cheap",
}

function M.reset_run_state()
  if not Utils.neuro_ready() then return end
  local N = G.NEURO
  for i = 1, #RUN_SCOPED_NIL do N[RUN_SCOPED_NIL[i]] = nil end
  N.force_inflight     = false
  N.force_dirty        = false
  N.reforce_count      = 0
  N.state_enter_serial = 0
end

return M
