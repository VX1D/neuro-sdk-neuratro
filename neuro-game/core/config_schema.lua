local function toggle(key, label, group, default, extra)
  local d = { key = key, label = label, group = group, kind = "enum", values = { "off", "on" }, default = default and "on" or "off" }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

local function enum(key, label, group, values, default, extra)
  local d = { key = key, label = label, group = group, kind = "enum", values = values, default = default }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

local function number(key, label, group, min, max, step, default, unit, extra)
  local d = { key = key, label = label, group = group, kind = "number", min = min, max = max, step = step, default = default, unit = unit }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

local function string_value(key, label, group, default, extra)
  local d = { key = key, label = label, group = group, kind = "string", default = default or "" }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end

local entries = {
  number("NEURO_SPEED_MULT", "SPEED MULT", "MASTER", 0.1, 2.0, 0.05, 1.0, "x"),
  number("NEURO_COOLDOWN_SCALE", "COOLDOWN SCALE (ALL)", "MASTER", 0.25, 3.0, 0.05, 1.0, "x"),
  toggle("NEURO_AUTO_TUNE", "AUTO-TUNE (SPEED)", "MASTER", true),
  enum("NEURO_CD_PRESET", "CD SPEED PRESET", "MASTER", { "auto", "0.5x", "1x", "2x", "4x" }, "auto"),

  enum("NEURO_DEBUG_OVERLAY", "DEBUG OVERLAY", "DISPLAY", { "off", "compact", "expanded" }, "off"),
  number("NEURO_PANEL_SCALE", "TUNING PANEL SIZE", "DISPLAY", 0.5, 1.5, 0.05, 1.0, "x"),

  number("NEURO_STATE_COOLDOWN", "STATE COOLDOWN", "COOLDOWNS", 0, 1.0, 0.01, 0.05, "s", { cd = true }),
  number("NEURO_ACTION_COOLDOWN", "ACTION COOLDOWN", "COOLDOWNS", 0, 2.0, 0.01, 0.08, "s", { cd = true }),
  number("NEURO_ENFORCE_COOLDOWN", "PER-ACTION COOLDOWN", "COOLDOWNS", 0, 5, 0.05, 0.60, "s", { cd = true }),
  number("NEURO_GLOBAL_COOLDOWN", "GLOBAL ACTION GAP", "COOLDOWNS", 0, 10, 0.1, 2.0, "s", { cd = true }),
  number("NEURO_FORCE_DEBOUNCE", "FORCE DEBOUNCE", "COOLDOWNS", 0, 2.0, 0.02, 0.12, "s", { cd = true }),
  number("NEURO_TRANSITION_COOLDOWN", "TRANSITION COOLDOWN", "COOLDOWNS", 0, 2.0, 0.01, 0.15, "s", { cd = true }),
  number("NEURO_REFRESH_COOLDOWN", "CTX REFRESH COOLDOWN", "COOLDOWNS", 0, 3, 0.05, 0.35, "s", { cd = true }),

  number("NEURO_THROTTLE_SHOP", "SHOP COOLDOWN", "THROTTLES", 0, 10, 0.1, 1.20, "s", { cd = true }),
  number("NEURO_THROTTLE_PACK", "PACK COOLDOWN", "THROTTLES", 0, 10, 0.1, 1.20, "s", { cd = true }),
  number("NEURO_GLOBAL_THROTTLE_SELECTING_HAND", "GLOBAL HAND GAP", "THROTTLES", 0, 15, 0.1, 1.8, "s", { cd = true }),
  number("NEURO_GLOBAL_THROTTLE_SHOP", "GLOBAL SHOP GAP", "THROTTLES", 0, 20, 0.25, 6.0, "s", { cd = true }),
  number("NEURO_GLOBAL_THROTTLE_BLIND_SELECT", "GLOBAL BLIND GAP", "THROTTLES", 0, 15, 0.1, 3.0, "s", { cd = true }),
  number("NEURO_GLOBAL_THROTTLE_PACK", "GLOBAL PACK GAP", "THROTTLES", 0, 15, 0.25, 4.5, "s", { cd = true }),

  number("NEURO_POST_PLAY", "POST PLAY", "POST-ACTION", 0, 4, 0.1, 1.4, "s", { cd = true }),
  number("NEURO_POST_DISCARD", "POST DISCARD", "POST-ACTION", 0, 4, 0.05, 0.9, "s", { cd = true }),
  number("NEURO_POST_BUY", "POST BUY", "POST-ACTION", 0, 4, 0.05, 0.8, "s", { cd = true }),
  number("NEURO_SHOP_BUY_DELAY", "SHOP BUY DELAY", "POST-ACTION", 0, 2, 0.05, 0.4, "s"),
  number("NEURO_SHOP_BUY_BLOCK", "SHOP BUY BLOCK", "POST-ACTION", 0, 8, 0.1, 2.2, "s", { cd = true }),
  number("NEURO_PACK_PICK_DELAY", "PACK PICK DELAY", "POST-ACTION", 0, 2, 0.05, 0.4, "s"),
  number("NEURO_PACK_PICK_BLOCK", "PACK PICK BLOCK", "POST-ACTION", 0, 8, 0.1, 3.0, "s", { cd = true }),
  number("NEURO_POST_SELL", "POST SELL", "POST-ACTION", 0, 4, 0.05, 0.6, "s", { cd = true }),
  number("NEURO_POST_DEFAULT", "POST DEFAULT", "POST-ACTION", 0, 4, 0.05, 0.5, "s", { cd = true }),

  number("NEURO_ENTRY_CD_SHOP", "ENTRY: SHOP", "ENTRY COOLDOWNS", 0, 15, 0.5, 2.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_ROUND_EVAL", "ENTRY: ROUND EVAL", "ENTRY COOLDOWNS", 0, 15, 0.5, 5.0, "s", { cd = true }),
  number("NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED", "ENTRY: SMODS BOOSTER", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_BUFFOON_PACK", "ENTRY: BUFFOON PACK", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_TAROT_PACK", "ENTRY: TAROT PACK", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_PLANET_PACK", "ENTRY: PLANET PACK", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_SPECTRAL_PACK", "ENTRY: SPECTRAL PACK", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),
  number("NEURO_ENTRY_CD_STANDARD_PACK", "ENTRY: STANDARD PACK", "ENTRY COOLDOWNS", 0, 15, 0.5, 4.5, "s", { cd = true }),

  number("NEURO_STAGING_FAILSAFE", "STAGING FAILSAFE", "WATCHDOGS", 5, 60, 1, 12.0, "s"),
  number("NEURO_SHOP_BUY_WATCHDOG_GRACE", "SHOP BUY GRACE", "WATCHDOGS", 0, 5, 0.1, 1.5, "s"),
  number("NEURO_DEFER_WINDOW_MIN", "DEFER WINDOW MIN", "WATCHDOGS", 0, 10, 0.5, 3, "s"),
  number("NEURO_LOGIN_ANIM_BLOCK", "LOGIN ANIM BLOCK", "WATCHDOGS", 0, 15, 0.5, 6.0, "s"),
  number("NEURO_ENGINE_GATE_FAILSAFE", "ENGINE GATE FAILSAFE", "WATCHDOGS", 1, 30, 0.5, 8.0, "s"),
  number("NEURO_VOUCHER_DRAWER_SAFETY", "VOUCHER DRAWER SAFETY", "WATCHDOGS", 3, 60, 0.5, 12.0, "s"),
  number("NEURO_ACK_IDLE_REASK", "ACK IDLE RE-ASK", "WATCHDOGS", 10, 600, 5, 90, "s"),
  number("NEURO_FORCE_LIVENESS_TIMEOUT", "FORCE LIVENESS TIMEOUT", "WATCHDOGS", 30, 900, 5, 180, "s"),
  number("NEURO_FORCE_CANCEL_SETTLE", "FORCE CANCEL SETTLE", "WATCHDOGS", 0, 5, 0.05, 0.5, "s"),
  number("NEURO_FORCE_CANCEL_IDLE", "FORCE CANCEL IDLE CAP", "WATCHDOGS", 1, 60, 0.5, 8.0, "s"),
  number("NEURO_FORCE_STALL", "FORCE STALL", "WATCHDOGS", 5, 300, 1, 12.0, "s"),

  number("NEURO_HOVER_PER_CARD", "HOVER PER CARD", "CADENCE", 0.05, 3, 0.05, 0.95, "s"),
  number("NEURO_HOVER_SHOP", "HOVER SHOP", "CADENCE", 0, 3, 0.05, 0.6, "s"),
  number("NEURO_HOVER_USE", "HOVER USE", "CADENCE", 0, 3, 0.05, 1.0, "s"),
  number("NEURO_HOVER_DEFAULT", "HOVER DEFAULT", "CADENCE", 0, 3, 0.05, 0.5, "s"),
  number("NEURO_HOLD_ALL_SELECTED", "HOLD ALL SELECTED", "CADENCE", 0, 5, 0.05, 1.1, "s"),
  number("NEURO_CTX_CACHE_TTL", "CONTEXT CACHE TTL", "CADENCE", 0, 2, 0.01, 0.20, "s"),
  number("NEURO_ROUTER_DEFER_FAILSAFE", "ROUTER DEFER FAILSAFE", "CADENCE", 1, 30, 0.5, 8.0, "s"),

  enum("NEURO_OVERLAY_ANCHOR", "HUD POSITION", "LAYOUT", { "auto", "top-left", "middle-left", "bottom-left", "top-right", "middle-right", "bottom-right" }, "auto"),
  number("NEURO_OVERLAY_OFFSET_X", "HUD HORIZONTAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_OVERLAY_OFFSET_Y", "HUD VERTICAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_OVERLAY_SCALE_RIGHT", "MAIN HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),
  number("NEURO_OVERLAY_SCALE_LEFT", "SHOP HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),
  enum("NEURO_SHOP_ANCHOR", "SHOP HUD POSITION", "LAYOUT", { "auto", "top-left", "middle-left", "bottom-left", "top-right", "middle-right", "bottom-right" }, "auto"),
  number("NEURO_SHOP_OFFSET_X", "SHOP HORIZONTAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_SHOP_OFFSET_Y", "SHOP VERTICAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_CENTER_SCALE", "ACQUIRE HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),

  enum("NEURO_PERSONA", "PERSONA", "SYSTEM", { "neuro", "evil", "hiyori" }, "hiyori", { runtime = true, session = true }),
  toggle("NEURO_DEBUG", "DEBUG LOG", "SYSTEM", false, { runtime = true }),
  toggle("NEURO_PERF_LOG", "PERF LOG", "SYSTEM", false, { runtime = true }),
  toggle("NEURO_AI_CARD_GLOW", "AI CARD GLOW", "SYSTEM", true, { runtime = true, restart_required = true }),
  toggle("NEURO_OVERLAY_DEV", "OVERLAY DEV", "SYSTEM", false, { runtime = true, restart_required = true, readonly = true }),
  toggle("NEURO_STAGING_DEBUG", "STAGING DEBUG", "SYSTEM", false, { runtime = true }),
  toggle("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "OUTBOX TRUNCATE", "SYSTEM", true, { runtime = true, restart_required = true }),
  toggle("NEURO_INBOX_TRUNCATE_ON_STARTUP", "INBOX TRUNCATE", "SYSTEM", false, { runtime = true, restart_required = true }),
  toggle("NEURO_SELFTEST_ON_BOOT", "SELFTEST ON BOOT", "SYSTEM", false, { runtime = true, restart_required = true }),
  toggle("NEURO_CARD_DEX_ON_BOOT", "CARD DEX ON BOOT", "SYSTEM", false, { runtime = true, restart_required = true }),
  toggle("NEURO_SELFTEST_PACK", "SELFTEST PACK", "SYSTEM", false, { runtime = true, restart_required = true }),
  string_value("NEURO_SELFTEST_FILTER", "SELFTEST FILTER", "SYSTEM", "", { runtime = true, panel = false }),
  toggle("NEURO_SMALL_REGRESSION", "SMALL REGRESSION", "SYSTEM", false, { runtime = true, restart_required = true }),
  toggle("NEURO_CRASH_GUARDS", "CRASH GUARDS", "SYSTEM", true, { runtime = true, restart_required = true }),
}

local by_key = {}
local regular, runtime = {}, {}
for i = 1, #entries do
  local d = entries[i]
  assert(not by_key[d.key], "duplicate config key: " .. d.key)
  by_key[d.key] = d
  if d.runtime then runtime[#runtime + 1] = d else regular[#regular + 1] = d end
end

return {
  entries = entries,
  regular = regular,
  runtime = runtime,
  by_key = by_key,
}
