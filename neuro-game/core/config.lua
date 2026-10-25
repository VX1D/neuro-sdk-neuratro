local Schema = require("core.config_schema")

local Config = {}

local backing
local persist
local dirty = false
local session = {}

local function notify_runtime_change(key, value)
  if key ~= "NEURO_CONFIRM_HAND" then return end
  local ok, Gate = pcall(require, "core.gate")
  if ok and Gate then pcall(Gate.confirmation_mode_changed, value == "on") end
end

local function validate(def, value)
  if def.kind == "enum" then
    for _, allowed in ipairs(def.values) do
      if allowed == value then return value end
    end
  elseif def.kind == "string" then
    return type(value) == "string" and value or nil
  elseif def.kind == "number" and type(value) == "number" and value == value
      and value ~= math.huge and value ~= -math.huge then
    return math.max(def.min, math.min(def.max, value))
  end
  return nil
end

local function ensure_initialized()
  if backing then return end
  local mod = rawget(_G, "SMODS") and SMODS.current_mod
  if mod and type(mod.config) == "table" then
    Config.init(mod.config, function() return SMODS.save_mod_config(mod) end)
    return
  end
  Config.init({ settings = {}, colours = {} }, function() return true end)
end

local function normalize_backing()
  local changed = false
  if type(backing.settings) ~= "table" then backing.settings = {}; changed = true end
  if type(backing.colours) ~= "table" then backing.colours = {}; changed = true end

  for key, value in pairs(backing.settings) do
    local def = Schema.by_key[key]
    local normalized = def and validate(def, value) or nil
    if (def and def.session) or normalized == nil or normalized == def.default then
      backing.settings[key] = nil
      changed = true
    elseif normalized ~= value then
      backing.settings[key] = normalized
      changed = true
    end
  end

  for persona, values in pairs(backing.colours) do
    if type(persona) ~= "string" or type(values) ~= "table" then
      backing.colours[persona] = nil
      changed = true
    else
      for key, value in pairs(values) do
        local hex = type(value) == "string" and value:upper() or nil
        if type(key) ~= "string" or not (hex and hex:match("^%x%x%x%x%x%x$")) then
          values[key] = nil
          changed = true
        elseif hex ~= value then
          values[key] = hex
          changed = true
        end
      end
      if next(values) == nil then backing.colours[persona] = nil; changed = true end
    end
  end

  dirty = dirty or changed
end

function Config.init(data, persist_fn)
  assert(type(data) == "table", "core.config requires a backing table")
  assert(type(persist_fn) == "function", "core.config requires a persist callback")
  backing = data
  persist = persist_fn
  dirty = false
  normalize_backing()
  return Config
end

function Config.definition(key)
  return Schema.by_key[key]
end

function Config.entries()
  return Schema.regular
end

function Config.runtime_entries()
  return Schema.runtime
end

function Config.get_raw(key)
  ensure_initialized()
  local def = Schema.by_key[key]
  if not def then return nil end
  local value
  if def.session then value = session[key] else value = backing.settings[key] end
  if value ~= nil then return value end
  return def.default
end

function Config.game_speed()
  local speed = G and G.SETTINGS and G.SETTINGS.GAMESPEED
  if type(speed) ~= "number" or speed <= 0 then return 1 end
  if speed < 0.5 then return 0.5 end
  if speed > 4 then return 4 end
  return speed
end
local function cooldown_scale()
  local scale = Config.get_raw("NEURO_COOLDOWN_SCALE")
  return type(scale) == "number" and scale > 0 and scale or 1
end

function Config.get(key)
  local value = Config.get_raw(key)
  local def = Schema.by_key[key]
  if def and def.cd and type(value) == "number" then
    return value * cooldown_scale()
  end
  return value
end

function Config.bool(key)
  return Config.get_raw(key) == "on"
end

local function store(def, key, value, stored)
  if def.session then
    local before = session[key] ~= nil and session[key] or def.default
    session[key] = stored
    if before ~= value then notify_runtime_change(key, value) end
  elseif backing.settings[key] ~= stored then
    backing.settings[key] = stored
    dirty = true
    notify_runtime_change(key, value)
  end
  return value
end

function Config.set(key, value)
  ensure_initialized()
  local def = Schema.by_key[key]
  if not def then return nil end
  local normalized = validate(def, value)
  if normalized == nil then return nil end
  local stored
  if normalized ~= def.default then stored = normalized end
  return store(def, key, normalized, stored)
end

function Config.reset(key)
  ensure_initialized()
  local def = Schema.by_key[key]
  if not def then return nil end
  return store(def, key, def.default, nil)
end

function Config.get_colours()
  ensure_initialized()
  return backing.colours
end

function Config.set_colour(persona, key, hex)
  ensure_initialized()
  if type(persona) ~= "string" or type(key) ~= "string" then return false end
  hex = type(hex) == "string" and hex:gsub("^#", ""):upper() or nil
  if not (hex and hex:match("^%x%x%x%x%x%x$")) then return false end
  local values = backing.colours[persona]
  if not values then values = {}; backing.colours[persona] = values end
  if values[key] == hex then return true end
  values[key] = hex
  dirty = true
  return true
end

function Config.reset_colour(persona, key)
  ensure_initialized()
  local values = backing.colours[persona]
  if not (values and values[key] ~= nil) then return true end
  values[key] = nil
  if next(values) == nil then backing.colours[persona] = nil end
  dirty = true
  return true
end

function Config.reset_colours(persona)
  ensure_initialized()
  if backing.colours[persona] == nil then return true end
  backing.colours[persona] = nil
  dirty = true
  return true
end

function Config.save()
  ensure_initialized()
  if not dirty then return true end
  local ok, saved, err = pcall(persist)
  if not ok then return false, tostring(saved) end
  if saved ~= true then return false, tostring(err or "Steamodded rejected the config write") end
  dirty = false
  return true
end

return Config
