local REAL, TOTAL, WALL = "REAL", "TOTAL", "WALL"

local gates = {
  engine_gate_failsafe = { TOTAL, "NEURO_ENGINE_GATE_FAILSAFE" },
  controller_lock_leak = { TOTAL },
  action_settle_latch = { TOTAL },
  router_pack_exit_defer = { TOTAL, "NEURO_ROUTER_DEFER_FAILSAFE" },
  router_guard_defer = { TOTAL, "NEURO_ROUTER_DEFER_FAILSAFE" },
  staging_failsafe = { TOTAL, "NEURO_STAGING_FAILSAFE" },
  staging_hover = { TOTAL, "NEURO_HOVER_PER_CARD" },
  staging_hold = { TOTAL, "NEURO_HOLD_ALL_SELECTED" },
  staging_commit = { TOTAL, "NEURO_SHOP_BUY_DELAY" },
  staging_engine_floor = { REAL },
  glow_window = { REAL },
  staging_post = { TOTAL, "NEURO_POST_PLAY" },
  state_cooldown = { TOTAL, "NEURO_STATE_COOLDOWN" },
  state_entry_cooldown = { TOTAL },
  anim_card_beat = { REAL },
  anim_engine_settle = { TOTAL },
  anim_commit_lead = { TOTAL },
  login_anim_block = { REAL, "NEURO_LOGIN_ANIM_BLOCK" },
  game_error_log_cooldown = { REAL },
  neuro_error_log_cooldown = { REAL },
  staging_error_log_cooldown = { REAL },
  ui_text_cache_ttl = { REAL },
  force_liveness_timeout = { REAL, "NEURO_FORCE_LIVENESS_TIMEOUT" },
  action_dying_grace = { WALL },
  inbox_poll = { WALL },
  game_heartbeat = { WALL },
  result_deadline = { WALL },
  bridge_transition_cooldown = { WALL, "NEURO_TRANSITION_COOLDOWN" },
  showcase_grace = { REAL },
  voucher_drawer_safety = { REAL, "NEURO_VOUCHER_DRAWER_SAFETY" },
  action_cooldown = { TOTAL, "NEURO_ACTION_COOLDOWN" },
  force_debounce = { TOTAL, "NEURO_FORCE_DEBOUNCE" },
  shop_buy_block = { TOTAL, "NEURO_SHOP_BUY_BLOCK" },
  shop_buy_watchdog_grace = { TOTAL, "NEURO_SHOP_BUY_WATCHDOG_GRACE" },
  pack_pick_block = { TOTAL, "NEURO_PACK_PICK_BLOCK" },
  receipt_deadline = { TOTAL },
}

local by_id = {}
for id, gate in pairs(gates) do
  assert(gate[1] == REAL or gate[1] == TOTAL or gate[1] == WALL,
    "gate clock must be REAL, TOTAL or WALL: " .. tostring(id))
  by_id[id] = { clock = gate[1], knobs = gate[2] and { gate[2] } or nil }
end

return {
  REAL = REAL,
  TOTAL = TOTAL,
  WALL = WALL,
  by_id = by_id,
  clock_of = function(id)
    local gate = by_id[id]
    assert(gate, "unknown timing gate: " .. tostring(id))
    return gate.clock
  end,
}
