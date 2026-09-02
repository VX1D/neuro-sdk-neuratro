local M = {}
local Utils = require("util.utils")
local LifecycleRegistry = require("core.lifecycle_registry")

function M.action_now() return Utils.gate_now("action_cooldown") end
function M.action_cooldown() return Utils.gate_seconds("action_cooldown", "NEURO_ACTION_COOLDOWN") end
function M.force_debounce_now() return Utils.gate_now("force_debounce") end
function M.force_debounce() return Utils.gate_seconds("force_debounce", "NEURO_FORCE_DEBOUNCE") end
function M.failure_now() return Utils.gate_now("failure_defer_window") end
function M.failure_defer_window()
  return math.max(
    Utils.gate_seconds("failure_defer_window", "NEURO_DEFER_WINDOW_MIN"),
    Utils.gate_seconds("failure_defer_window", "NEURO_SHOP_BUY_DELAY") + 1,
    Utils.gate_seconds("failure_defer_window", "NEURO_PACK_PICK_DELAY") + 1)
end

function M.mark_action_at(at)
  if not Utils.neuro_ready() then return end
  at = tonumber(at) or M.action_now()
  if not G.NEURO.last_action_at or at > G.NEURO.last_action_at then
    G.NEURO.last_action_at = at
  end
  G.NEURO.last_action_real_at = Utils.now()
end

function M.record_failure(name, reason, correction)
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = name
  G.NEURO.last_failed_reason = reason
  G.NEURO.last_failed_correction = type(correction) == "string" and correction ~= "" and correction or nil
  G.NEURO.last_failed_at = M.failure_now()
end

function M.clear_failure()
  if not Utils.neuro_ready() then return end
  G.NEURO.last_failed_action = nil
  G.NEURO.last_failed_reason = nil
  G.NEURO.last_failed_correction = nil
  G.NEURO.last_failed_at = nil
end

function M.clear_pending_confirm()
  if not Utils.neuro_ready() then return end
  pcall(function()
    local HandTx = require("core.hand_transaction")
    HandTx.invalidate(nil, "lifecycle_reset")
  end)
  pcall(require("core.context_review").reset)
  G.NEURO.weak_fired_serial = nil
  G.NEURO.pending_confirmation = nil
  G.NEURO.confirmation_delivery = nil
end

function M.reset_context_delivery()
  if not Utils.neuro_ready() then return end
  if type(G.NEURO.discard_backlog_context) == "function" then
    G.NEURO:discard_backlog_context()
  end
  require("core.context_delivery").reset_transport()
  local N = G.NEURO
  N.once_serials = {}
  N.session_once_serials = {}
end

function M.bump_run_generation(reason)
  local current = Utils.neuro_ready() and tonumber(G.NEURO.run_generation) or nil
  pcall(function()
    require("core.hand_transaction").invalidate(nil, reason or "run generation changed")
  end)
  require("core.dispatcher").reset_transport_state(reason or "run generation changed")
  require("core.staging").on_reconnect()
  if current == nil then return nil end
  G.NEURO.run_generation = current + 1
  return G.NEURO.run_generation
end

function M.mark_force_dirty()
  if not Utils.neuro_ready() then return end
  G.NEURO.force_dirty = true
  G.NEURO.force_dirty_at = M.force_debounce_now()
end

LifecycleRegistry.register_fields("run", {
  "force_state",
  "force_inflight", "force_dirty",
  "force_window",
  "force_sent_at", "force_dirty_at", "force_last_result",
  "force_cancel_pending",
  "force_liveness_fingerprint", "force_liveness_repeat", "force_liveness_state",
  "force_transport_fault", "force_transport_paused", "force_transport_pause_prior",
  "action_phase", "action_phase_at",
  "recent_actions", "once_serials", "decision_snapshot", "gameplay_journal",
  "pending_confirmation", "confirmation_delivery",
  "hand_transaction", "hand_last_transaction", "hand_decision", "hand_context_revision", "hand_context_key",
  "hand_transaction_id_generation", "hand_transaction_next_id", "context_reviews",
  "last_failed_action", "last_failed_reason", "last_failed_correction", "last_failed_at",
  "last_action_at", "last_action_real_at", "last_action_name", "last_play",
  "shop_pack_interrupt", "reserved_dollars", "purchase_showcase_queue", "held_plan_write",
  "joker_intents_ack_identity", "reward_joker_roster",
  "plan", "plan_revision", "joker_intent_revision", "econ_plan_ok", "blind_plan_ok", "blind_plan_scope", "shop_plan_revision_required",
  "economy_epoch", "shop_visit_epoch", "shop_entry_dollars", "shop_entry_pending", "joker_order_ack",
  "selected_back_key", "pack_exit_pending", "weak_fired_serial", "jokers_sold", "jokers_sold_run", "joker_intents", "joker_observations", "joker_hits", "joker_bought_cost", "last_reward_outcome_key", "rare_joker_announced", "blind_reward_cache", "blind_reward_round",
  "state", "state_enter_serial", "decision_serial", "decision_ack_count", "decision_ack_serial",
  "decision_ack_level", "decision_ack_at", "setup_acknowledged",
  "consumed_actions", "consumed_action_owner",
  "_prev_ante", "_reservation_epoch", "_decision_windows",
  "seed_pasted", "login_anim", "game_over_hooked",
  "deck_chosen", "ai_highlighted", "ai_glow",
})
LifecycleRegistry.register_hook("run", "transition_guard", function()
  require("core.transition_guard").reset()
end, 40)
LifecycleRegistry.register_hook("run", "dispatcher", function()
  require("core.dispatcher").reset_run_state()
end, 20)
LifecycleRegistry.register_hook("run", "enforce", function()
  require("core.enforce").reset_run_state()
end, 50)
LifecycleRegistry.register_hook("run", "crash_guards", function()
  require("core.crash_guards").reset_run_state()
end, 55)
LifecycleRegistry.register_hook("run", "orchestrator", function()
  require("core.orchestrator").reset_run_state()
end, 60)
LifecycleRegistry.register_hook("run", "joker_hits", function()
  require("core.joker_hits").reset_run_state()
end, 15)
LifecycleRegistry.register_hook("run", "staging", function()
  require("core.staging").reset_run_state()
end, 10)
LifecycleRegistry.register_hook("run", "showcase", function()
  require("hud.showcase").reset_run_state()
end, 70)
-- Loaded assets are filename-keyed with no per-run state, so they survive a run. Retry budgets
-- and `false` give-up markers must not, or a transient early-boot failure becomes permanent.
function M.reset_hud_state()
  local S = require("hud.state")
  local HUD_STATE_KEEP = S.PERSISTENT_KEYS
  if S.release_text_caches then S.release_text_caches() end
  local fresh = S.new_state()
  for k in pairs(S) do
    if not HUD_STATE_KEEP[k] and fresh[k] == nil then S[k] = nil end
  end
  for k, v in pairs(fresh) do
    if HUD_STATE_KEEP[k] then
      if S[k] == nil then S[k] = v end
    else
      S[k] = v
    end
  end
  if type(S.panel_emote_cache) == "table" then
    for name, emote in pairs(S.panel_emote_cache) do
      if emote == false then S.panel_emote_cache[name] = nil end
    end
  end
end

LifecycleRegistry.register_hook("run", "hud_state", function()
  M.reset_hud_state()
  local HudShared = require("render.hud_shared")
  if HudShared.carousel_reset then HudShared.carousel_reset() end
end, 75)
LifecycleRegistry.register_hook("run", "plan_transaction", function()
  require("core.plan_transaction").release()
end, 30)
LifecycleRegistry.register_hook("run", "action_receipt", function()
  require("core.action_receipt").reset("run_reset")
end, 5)

function M.reset_run_state()
  if not Utils.neuro_ready() then return end
  local N = G.NEURO
  local transport_paused = N.force_transport_paused
  local transport_pause_prior = N.force_transport_pause_prior
  pcall(function()
    require("core.force_state").invalidate("run_reset")
  end)
  if type(N.retire_run_force) == "function" then
    pcall(N.retire_run_force, N)
  end
  N.run_generation = (tonumber(N.run_generation) or 0) + 1
  LifecycleRegistry.reset("run", N, { generation = N.run_generation })
  if transport_paused then N.llm_paused = transport_pause_prior end
  N.force_inflight     = false
  N.force_dirty        = false
  N.state_enter_serial = 0
  N.decision_serial    = 0
  N.setup_acknowledged = false
  N._prev_ante         = 0
  N.economy_epoch      = 0
  N.shop_visit_epoch   = 0
  N.render_dirty_epoch = 0
  N.plan_revision      = 0
  N.joker_intent_revision = 0
  N._reservation_epoch = N.run_generation
  N._decision_windows = {}
  N.ai_highlighted = setmetatable({}, { __mode = "k" })
  N.ai_glow = setmetatable({}, { __mode = "k" })
end

M.registry = LifecycleRegistry
return M
