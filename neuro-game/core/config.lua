local dotenv = require("util.dotenv")
local Palette = require("render.palette")

-- Config owner. Precedence: OS env > neuro.conf > built-in default.
local Config = {}

local _speed_seed = math.max(0.1, math.min(2.0, dotenv.num("NEURO_SPEED_MULT", 1.0)))
local _fast = _speed_seed < 0.6

local function overlay_mode(v)
  v = tostring(v or ""):lower()
  if v == "2" or v == "expanded" then return "expanded" end
  if v == "1" or v == "true" or v == "yes" or v == "compact" then return "compact" end
  return "off"
end

local function onoff(b) return b and "on" or "off" end

-- NEURO_SPEED_MULT must stay DEFS[1]; test_anti_regress asserts entries()[1] is it
local DEFS = {
  { key = "NEURO_SPEED_MULT",          label = "SPEED MULT",          group = "MASTER", min = 0.1, max = 2.0, step = 0.05, default = 1.0, unit = "x" },
  { key = "NEURO_COOLDOWN_SCALE",      label = "COOLDOWN SCALE (ALL)", group = "MASTER", min = 0.25, max = 3.0, step = 0.05, default = 1.0, unit = "x" },
  -- CD OVERRIDE off: cooldowns auto-track the game-speed slider; on: sliders are literal, game speed ignored
  { key = "NEURO_CD_OVERRIDE",         label = "CD OVERRIDE (MANUAL)", group = "MASTER", values = { "off", "on" }, default = "off" },
  { key = "NEURO_CD_PRESET",           label = "CD SPEED PRESET",     group = "MASTER", values = { "auto", "0.5x", "1x", "2x", "4x" }, default = "auto" },

  { key = "NEURO_REDUCED_MOTION", label = "REDUCED MOTION", group = "FLAGS", values = { "off", "on" }, default = onoff((function() local v = tostring(dotenv.get("NEURO_REDUCED_MOTION", "")):lower(); return v == "1" or v == "true" or v == "on" end)()) },
  { key = "NEURO_CTX_SPLIT",      label = "CONTEXT SPLIT",  group = "FLAGS", values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_CTX_SPLIT", true)) },
  { key = "NEURO_STATE_VERBOSE",  label = "STATE VERBOSE",  group = "FLAGS", values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_STATE_VERBOSE", false)) },
  { key = "NEURO_FORCE_ONLY",     label = "FORCE ONLY",     group = "FLAGS", values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_FORCE_ONLY", false)) },

  { key = "NEURO_STATE_COOLDOWN",      label = "STATE COOLDOWN",      group = "COOLDOWNS", cd = true, min = 0, max = 1.0, step = 0.01, default = _fast and 0.04 or 0.05, unit = "s" },
  { key = "NEURO_ACTION_COOLDOWN",     label = "ACTION COOLDOWN",     group = "COOLDOWNS", cd = true, min = 0, max = 2.0, step = 0.01, default = _fast and 0.06 or 0.08, unit = "s" },
  { key = "NEURO_ENFORCE_COOLDOWN",    label = "PER-ACTION COOLDOWN", group = "COOLDOWNS", cd = true, min = 0, max = 5,   step = 0.05, default = _fast and 0.18 or 0.60, unit = "s" },
  { key = "NEURO_GLOBAL_COOLDOWN",     label = "GLOBAL ACTION GAP",   group = "COOLDOWNS", cd = true, min = 0, max = 10,  step = 0.1,  default = _fast and 0.65 or 2.0, unit = "s" },
  { key = "NEURO_FORCE_DEBOUNCE",      label = "FORCE DEBOUNCE",      group = "COOLDOWNS", cd = true, min = 0, max = 2.0, step = 0.02, default = _fast and 0.10 or 0.12, unit = "s" },
  { key = "NEURO_TRANSITION_COOLDOWN", label = "TRANSITION COOLDOWN", group = "COOLDOWNS", cd = true, min = 0, max = 2.0, step = 0.01, default = 0.15, unit = "s" },

  { key = "NEURO_THROTTLE_SHOP",       label = "SHOP COOLDOWN",       group = "THROTTLES", cd = true, min = 0, max = 10, step = 0.1,  default = _fast and 0.30 or 1.20, unit = "s" },
  { key = "NEURO_THROTTLE_PACK",       label = "PACK COOLDOWN",       group = "THROTTLES", cd = true, min = 0, max = 10, step = 0.1,  default = _fast and 0.35 or 1.20, unit = "s" },
  { key = "NEURO_GLOBAL_THROTTLE_SELECTING_HAND", label = "GLOBAL HAND GAP",  group = "THROTTLES", cd = true, min = 0, max = 15, step = 0.1,  default = _fast and 0.55 or 1.8, unit = "s" },
  { key = "NEURO_GLOBAL_THROTTLE_SHOP",           label = "GLOBAL SHOP GAP",  group = "THROTTLES", cd = true, min = 0, max = 20, step = 0.25, default = _fast and 2.20 or 6.0, unit = "s" },
  { key = "NEURO_GLOBAL_THROTTLE_BLIND_SELECT",   label = "GLOBAL BLIND GAP", group = "THROTTLES", cd = true, min = 0, max = 15, step = 0.1,  default = _fast and 0.80 or 3.0, unit = "s" },
  { key = "NEURO_GLOBAL_THROTTLE_PACK",           label = "GLOBAL PACK GAP",  group = "THROTTLES", cd = true, min = 0, max = 15, step = 0.25, default = _fast and 1.40 or 4.5, unit = "s" },

  { key = "NEURO_POST_PLAY",           label = "POST PLAY",           group = "POST-ACTION", cd = true, min = 0, max = 4, step = 0.1,  default = 1.4, unit = "s" },
  { key = "NEURO_POST_DISCARD",        label = "POST DISCARD",        group = "POST-ACTION", cd = true, min = 0, max = 4, step = 0.05, default = 0.9, unit = "s" },
  { key = "NEURO_POST_BUY",            label = "POST BUY",            group = "POST-ACTION", cd = true, min = 0, max = 4, step = 0.05, default = 0.8, unit = "s" },
  -- event = true rows already scale via the TOTAL clock (add_event); keep them out of the gate factor
  { key = "NEURO_SHOP_BUY_DELAY",      label = "SHOP BUY DELAY",      group = "POST-ACTION", cd = true, event = true, min = 0, max = 8, step = 0.1,  default = 2.2, unit = "s" },
  { key = "NEURO_SHOP_BUY_BLOCK",      label = "SHOP BUY BLOCK",      group = "POST-ACTION", cd = true, min = 0, max = 8, step = 0.1,  default = 2.2, unit = "s" },
  { key = "NEURO_PACK_PICK_DELAY",     label = "PACK PICK DELAY",     group = "POST-ACTION", cd = true, event = true, min = 0, max = 8, step = 0.1,  default = 2.2, unit = "s" },
  { key = "NEURO_PACK_PICK_BLOCK",     label = "PACK PICK BLOCK",     group = "POST-ACTION", cd = true, min = 0, max = 8, step = 0.1,  default = 3.0, unit = "s" },

  { key = "NEURO_ENTRY_CD_SHOP",                 label = "ENTRY: SHOP",          group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 2.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_ROUND_EVAL",           label = "ENTRY: ROUND EVAL",    group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 5.0, unit = "s" },
  { key = "NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED", label = "ENTRY: SMODS BOOSTER", group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_BUFFOON_PACK",         label = "ENTRY: BUFFOON PACK",  group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_TAROT_PACK",           label = "ENTRY: TAROT PACK",    group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_PLANET_PACK",          label = "ENTRY: PLANET PACK",   group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_SPECTRAL_PACK",        label = "ENTRY: SPECTRAL PACK", group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },
  { key = "NEURO_ENTRY_CD_STANDARD_PACK",        label = "ENTRY: STANDARD PACK", group = "ENTRY COOLDOWNS", cd = true, min = 0, max = 15, step = 0.5, default = 4.5, unit = "s" },

  { key = "NEURO_FORCE_STALL_SECONDS", label = "FORCE STALL WATCHDOG", group = "WATCHDOGS", min = 3, max = 60, step = 1,   default = 12, unit = "s" },
  { key = "NEURO_STAGING_FAILSAFE",    label = "STAGING FAILSAFE",    group = "WATCHDOGS", min = 5, max = 60,  step = 1,   default = 12.0, unit = "s" },
  { key = "NEURO_GAMEOVER_COOLDOWN",   label = "GAME OVER STATS HOLD", group = "WATCHDOGS", min = 0, max = 120, step = 1,  default = 5, unit = "s" },
  { key = "NEURO_SHOP_BUY_WATCHDOG_GRACE", label = "SHOP BUY GRACE",  group = "WATCHDOGS", min = 0, max = 5, step = 0.1,  default = 1.5, unit = "s" },
  { key = "NEURO_PACK_PICK_WATCHDOG_GRACE", label = "PACK PICK GRACE", group = "WATCHDOGS", min = 0, max = 5, step = 0.1, default = 1.5, unit = "s" },

  { key = "NEURO_STATE_INTERVAL",      label = "STATE WRITE INTERVAL", group = "CADENCE", min = 0.2, max = 10, step = 0.1, default = 1.0, unit = "s" },
  { key = "NEURO_HOVER_PER_CARD",      label = "HOVER PER CARD",      group = "CADENCE", min = 0.05, max = 3, step = 0.05, default = 0.95, unit = "s" },
  { key = "NEURO_HOVER_SHOP",          label = "HOVER SHOP",          group = "CADENCE", min = 0, max = 3, step = 0.05, default = 1.0, unit = "s" },

  { key = "NEURO_OVERLAY_SCALE_RIGHT", label = "OVERLAY SCALE RIGHT", group = "LAYOUT", min = 0.5, max = 1.5, step = 0.05, default = 1.0, unit = "x" },
  { key = "NEURO_OVERLAY_SCALE_LEFT",  label = "OVERLAY SCALE LEFT",  group = "LAYOUT", min = 0.5, max = 1.5, step = 0.05, default = 1.0, unit = "x" },
  { key = "NEURO_DEBUG_OVERLAY",       label = "DEBUG OVERLAY",       group = "LAYOUT", values = { "off", "compact", "expanded" }, default = overlay_mode(dotenv.get("NEURO_DEBUG_OVERLAY", "")) },
}

local RUNTIME = {
  { key = "NEURO_PERSONA",       label = "PERSONA",         group = "RUNTIME", runtime = true, values = { "neuro", "evil" }, default = (dotenv.normalize_persona(dotenv.get("NEURO_PERSONA", ""))), note = "reload to reskin" },
  { key = "NEURO_ENABLE",        label = "SDK ENABLE",      group = "RUNTIME", runtime = true, panel = false, readonly = true, kind = "flag" },
  { key = "NEURO_IPC_DIR",       label = "IPC DIR",         group = "RUNTIME", runtime = true, panel = false, readonly = true, kind = "string" },
  { key = "NEURO_DEBUG",         label = "DEBUG LOG",       group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_DEBUG", false)) },
  { key = "NEURO_TRACE",         label = "CRASH TRACE",     group = "RUNTIME", runtime = true, panel = false, readonly = true, kind = "flag" },
  { key = "NEURO_PERF_LOG",      label = "PERF LOG",        group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_PERF_LOG", false)) },
  { key = "NEURO_AI_CARD_GLOW",  label = "AI CARD GLOW",    group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_AI_CARD_GLOW", true)) },
  { key = "NEURO_OVERLAY_DEV",   label = "OVERLAY DEV",     group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_OVERLAY_DEV", false)) },
  { key = "NEURO_STAGING_DEBUG", label = "STAGING DEBUG",   group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_STAGING_DEBUG", false)) },
  { key = "NEURO_OUTBOX_TRUNCATE_ON_STARTUP", label = "OUTBOX TRUNCATE", group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", true)) },
  { key = "NEURO_INBOX_TRUNCATE_ON_STARTUP",  label = "INBOX TRUNCATE",  group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_INBOX_TRUNCATE_ON_STARTUP", false)) },
  { key = "NEURO_SELFTEST_ON_BOOT", label = "SELFTEST ON BOOT", group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_SELFTEST_ON_BOOT", false)) },
  { key = "NEURO_SELFTEST_PACK",    label = "SELFTEST PACK",    group = "RUNTIME", runtime = true, values = { "off", "on" }, default = onoff(dotenv.bool("NEURO_SELFTEST_PACK", false)) },
  { key = "NEURO_SELFTEST_FILTER",  label = "SELFTEST FILTER",  group = "RUNTIME", runtime = true, panel = false, kind = "string", default = dotenv.get("NEURO_SELFTEST_FILTER", "") },
}

local index = {}
local values = {}
local env_pinned = {}

local function env_raw(key)
  local v = os.getenv(key)
  if v == nil or v == "" then return nil end
  return v
end

local function in_values(def, v)
  for i = 1, #def.values do
    if def.values[i] == v then return true end
  end
  return false
end

local function clamp(def, v)
  if def.values then
    return in_values(def, v) and v or def.default
  end
  if v < def.min then return def.min end
  if v > def.max then return def.max end
  return v
end

local function seed_one(d)
  index[d.key] = d
  if d.readonly then
    values[d.key] = nil
    return
  end
  local pinned = env_raw(d.key)
  env_pinned[d.key] = pinned ~= nil
  if d.values then
    if pinned ~= nil and in_values(d, pinned) then
      values[d.key] = pinned
    else
      values[d.key] = d.default    -- default already folded OS env in via dotenv for the FLAGS rows
    end
  elseif d.kind == "string" then
    values[d.key] = pinned ~= nil and pinned or (d.default or "")
  else
    values[d.key] = clamp(d, dotenv.num(d.key, d.default))
  end
end

local function reseed()
  index = {}
  values = {}
  env_pinned = {}
  for i = 1, #DEFS do seed_one(DEFS[i]) end
  for i = 1, #RUNTIME do seed_one(RUNTIME[i]) end
end
reseed()

local CONF_FILE = "neuro.conf"
local LEGACY_TUNING = "neuro_tuning.env"
local LEGACY_ENV = ".env"

local function default_path()
  return dotenv.dir() .. "/" .. CONF_FILE
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- guards against a bad/zero NEURO_COOLDOWN_SCALE value zeroing out every cooldown
local function cooldown_scale()
  local s = values.NEURO_COOLDOWN_SCALE
  return (type(s) == "number" and s > 0) and s or 1
end
Config.cooldown_scale = cooldown_scale

-- Balatro's speed slider {0.5,1,2,4}: TOTAL clock (animations) runs GAMESPEED x faster, our gates run on REAL clock
local function game_speed()
  local s = G and G.SETTINGS and G.SETTINGS.GAMESPEED
  if type(s) ~= "number" or s <= 0 then return 1 end
  if s < 0.5 then return 0.5 end
  if s > 4 then return 4 end
  return s
end
Config.game_speed = game_speed

-- factor = 1/target-speed so cooldowns track animation length; CD OVERRIDE on pins it to 1 (manual sliders)
local PRESET_SPEED = { ["0.5x"] = 0.5, ["1x"] = 1, ["2x"] = 2, ["4x"] = 4 }
local function cd_gate_factor()
  if values.NEURO_CD_OVERRIDE == "on" then return 1 end
  local preset = values.NEURO_CD_PRESET
  local sp = PRESET_SPEED[preset] or game_speed()
  if sp == 1 then return 1 end
  local f = 1 / sp
  return (type(f) == "number" and f > 0) and f or 1
end
Config.cd_gate_factor = cd_gate_factor

-- unlike Config.get, this is never scaled -- used by the panel display/edit/save
function Config.get_raw(key)
  return values[key]
end

-- cd rows are scaled by NEURO_COOLDOWN_SCALE, and (unless event = true) also by the real-clock gate factor
function Config.get(key)
  local v = values[key]
  local d = index[key]
  if d and d.cd and type(v) == "number" then
    if d.event then return v * cooldown_scale() end
    return v * cooldown_scale() * cd_gate_factor()
  end
  return v
end

function Config.bool(key)
  return values[key] == "on"
end

function Config.set(key, v)
  local d = index[key]
  if not d or d.readonly then return nil end
  if d.values then
    if not in_values(d, v) then return nil end
    values[key] = v
    return v
  end
  if d.kind == "string" then
    values[key] = tostring(v)
    return values[key]
  end
  if type(v) ~= "number" then return nil end
  values[key] = clamp(d, v)
  return values[key]
end

function Config.reset(key)
  local d = index[key]
  if not d or d.readonly then return nil end
  values[key] = d.default
  return d.default
end

function Config.entries()
  return DEFS
end

function Config.runtime_entries()
  return RUNTIME
end

-- watchdog must outlast the largest active cooldown multiplier, or a stretched cooldown trips stall recovery
function Config.force_stall_seconds()
  local v = values.NEURO_FORCE_STALL_SECONDS
  if not v or v <= 0 then v = 12 end
  local m = math.max(values.NEURO_SPEED_MULT or 1.0, cooldown_scale(), cd_gate_factor())
  if m > 1 then v = v * m end
  return v
end

local function serialize_def(d)
  local v = values[d.key]
  if d.values or d.kind == "string" then
    return d.key .. "=" .. tostring(v)
  end
  return d.key .. "=" .. string.format("%.4g", v)
end

function Config.serialize()
  local lines = {}
  for i = 1, #DEFS do lines[#lines + 1] = serialize_def(DEFS[i]) end
  for i = 1, #RUNTIME do
    local d = RUNTIME[i]
    if not d.readonly then lines[#lines + 1] = serialize_def(d) end
  end
  return table.concat(lines, "\n") .. "\n" .. Palette.serialize_overrides()
end

-- OS-env-pinned keys are never overridden (env wins over file)
local function apply_vars(vars)
  local applied = 0
  for k, v in pairs(vars) do
    local d = index[k]
    if d and not d.readonly and not env_pinned[k] then
      if d.values then
        if in_values(d, v) then values[k] = v; applied = applied + 1 end
      elseif d.kind == "string" then
        values[k] = v; applied = applied + 1
      elseif tonumber(v) then
        values[k] = clamp(d, tonumber(v)); applied = applied + 1
      end
    end
  end
  Palette.apply_overrides(vars)
  return applied
end

-- dispatches NEURO_COLOR_* to Palette; legacy .env + neuro_tuning.env fallback (tuning wins on overlap)
function Config.load(path)
  path = path or default_path()
  if file_exists(path) then
    return apply_vars(dotenv.parse_file(path))
  end
  if path == default_path() then
    local dir = dotenv.dir()
    local merged = dotenv.parse_file(dir .. "/" .. LEGACY_ENV)
    for k, v in pairs(dotenv.parse_file(dir .. "/" .. LEGACY_TUNING)) do merged[k] = v end
    if next(merged) then return apply_vars(merged) end
  end
  return 0
end

function Config.save(path)
  local f, err = io.open(path or default_path(), "w")
  if not f then return false, err end
  f:write(Config.serialize())
  f:close()
  return true
end

Config.default_path = default_path
Config.reseed = reseed
Config.DEFS = DEFS
Config.RUNTIME = RUNTIME
Config.load_overrides = Config.load   -- legacy name (core.tuning alias, tests)

Config.load()

return Config
