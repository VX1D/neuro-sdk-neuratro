local function def(fields, extra)
  for k, v in pairs(extra or {}) do fields[k] = v end
  return fields
end

local function toggle(key, label, group, on, extra)
  return def({ key = key, label = label, group = group, kind = "enum", values = { "off", "on" },
    default = on and "on" or "off" }, extra)
end

local function enum(key, label, group, values, default, extra)
  return def({ key = key, label = label, group = group, kind = "enum", values = values, default = default }, extra)
end

local function number(key, label, group, min, max, step, default, unit, extra)
  return def({ key = key, label = label, group = group, kind = "number", min = min, max = max, step = step,
    default = default, unit = unit }, extra)
end

local ANCHORS = { "auto", "top-left", "middle-left", "bottom-left", "top-right", "middle-right", "bottom-right" }

local entries = {
  number("NEURO_SPEED_MULT", "SPEED MULT", "MASTER", 0.1, 2.0, 0.05, 1.0, "x"),
  number("NEURO_COOLDOWN_SCALE", "COOLDOWN SCALE (ALL)", "MASTER", 0.25, 3.0, 0.05, 1.0, "x"),

  number("NEURO_PANEL_SCALE", "TUNING PANEL SIZE", "DISPLAY", 0.5, 1.5, 0.05, 1.0, "x"),

  number("NEURO_STATE_COOLDOWN", "STATE COOLDOWN", "COOLDOWNS", 0, 1.0, 0.01, 0.05, "s", { cd = true }),
  number("NEURO_ACTION_COOLDOWN", "ACTION COOLDOWN", "COOLDOWNS", 0, 2.0, 0.01, 0.08, "s", { cd = true }),
  number("NEURO_FORCE_DEBOUNCE", "FORCE DEBOUNCE", "COOLDOWNS", 0, 2.0, 0.02, 0.12, "s", { cd = true }),
  number("NEURO_TRANSITION_COOLDOWN", "TRANSITION COOLDOWN", "COOLDOWNS", 0, 2.0, 0.01, 0.15, "s", { cd = true }),


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
  number("NEURO_LOGIN_ANIM_BLOCK", "LOGIN ANIM BLOCK", "WATCHDOGS", 0, 15, 0.5, 6.0, "s"),
  number("NEURO_ENGINE_GATE_FAILSAFE", "ENGINE GATE FAILSAFE", "WATCHDOGS", 1, 30, 0.5, 8.0, "s"),
  number("NEURO_VOUCHER_DRAWER_SAFETY", "VOUCHER DRAWER SAFETY", "WATCHDOGS", 3, 60, 0.5, 12.0, "s"),
  number("NEURO_FORCE_LIVENESS_TIMEOUT", "FORCE LIVENESS TIMEOUT", "WATCHDOGS", 30, 900, 5, 180, "s"),

  number("NEURO_HOVER_PER_CARD", "HOVER PER CARD", "CADENCE", 0.05, 3, 0.05, 0.95, "s"),
  number("NEURO_HOVER_SHOP", "HOVER SHOP", "CADENCE", 0, 3, 0.05, 0.6, "s"),
  number("NEURO_HOVER_USE", "HOVER USE", "CADENCE", 0, 3, 0.05, 1.0, "s"),
  number("NEURO_HOVER_DEFAULT", "HOVER DEFAULT", "CADENCE", 0, 3, 0.05, 0.5, "s"),
  number("NEURO_HOLD_ALL_SELECTED", "HOLD ALL SELECTED", "CADENCE", 0, 5, 0.05, 1.1, "s"),
  number("NEURO_ROUTER_DEFER_FAILSAFE", "ROUTER DEFER FAILSAFE", "CADENCE", 1, 30, 0.5, 8.0, "s"),

  enum("NEURO_OVERLAY_ANCHOR", "HUD POSITION", "LAYOUT", ANCHORS, "auto"),
  number("NEURO_OVERLAY_OFFSET_X", "HUD HORIZONTAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_OVERLAY_OFFSET_Y", "HUD VERTICAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_OVERLAY_SCALE_RIGHT", "MAIN HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),
  number("NEURO_OVERLAY_SCALE_LEFT", "SHOP HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),
  enum("NEURO_SHOP_ANCHOR", "SHOP HUD POSITION", "LAYOUT", ANCHORS, "auto"),
  number("NEURO_SHOP_OFFSET_X", "SHOP HORIZONTAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_SHOP_OFFSET_Y", "SHOP VERTICAL OFFSET", "LAYOUT", -40, 40, 1, 0, "%"),
  number("NEURO_CENTER_SCALE", "ACQUIRE HUD SCALE", "LAYOUT", 0.5, 1.5, 0.05, 1.0, "x"),

  enum("NEURO_PERSONA", "PERSONA", "SYSTEM", { "neuro", "evil", "hiyori" }, "hiyori", { runtime = true, session = true }),
  toggle("NEURO_DEBUG", "DEBUG LOG", "SYSTEM", false, { runtime = true }),
  toggle("NEURO_AI_CARD_GLOW", "AI CARD GLOW", "SYSTEM", true, { runtime = true, restart_required = true }),
  toggle("NEURO_CRASH_GUARDS", "CRASH GUARDS", "SYSTEM", true, { runtime = true, restart_required = true }),
  toggle("NEURO_CONFIRM_HAND", "HAND CONFIRMATION", "SYSTEM", true, { runtime = true }),
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
