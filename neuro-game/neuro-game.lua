--- STEAMODDED HEADER
--- MOD_NAME: neuro-game
--- MOD_ID: neuro-game
--- MOD_AUTHOR: [x264.webrip]
--- MOD_DESCRIPTION: Neuro SDK bridge + IPC for Balatro
--- MOD_VERSION: 1.2.1
--- DEPENDENCIES: [Steamodded>=26.1002.0]

if rawget(_G, "NEURO_SDK_MOD_LOADED") then
  local info = debug and type(debug.getinfo) == "function" and debug.getinfo(1, "S")
  local source = info and type(info.source) == "string" and info.source:gsub("^@", "") or "?"
  print("[neuro-game] WARNING: a second copy of this mod was loaded from " .. source
    .. " and was skipped. Remove stale copies from the Mods directory -- whichever copy "
    .. "loads first wins.")
  return
end
_G.NEURO_SDK_MOD_LOADED = true

local function _neuro_normalize_path(path)
  if type(path) ~= "string" or path == "" then return nil end
  return path:gsub("\\", "/")
end

local _neuro_declared_path = SMODS and type(SMODS.current_mod) == "table"
  and SMODS.current_mod.path
local _neuro_root = _neuro_normalize_path(_neuro_declared_path) or "."
local _neuro_sep = package.config:sub(1, 1)
local _neuro_root_native = _neuro_root:gsub("/", _neuro_sep)

do
  local function path_key(path)
    local normalized = _neuro_normalize_path(path)
    if not normalized then return nil end
    normalized = normalized:gsub("/+$", "")
    return normalized:lower()
  end

  local owned_roots = {}
  local owned = path_key(_neuro_root)
  if owned and owned ~= "" then owned_roots[owned] = true end

  local function package_pattern_root(pattern)
    local normalized = _neuro_normalize_path(pattern)
    if not normalized then return nil end
    local wildcard = normalized:find("?", 1, true)
    if not wildcard then return nil end
    local prefix = normalized:sub(1, wildcard - 1)
    if prefix:sub(-1) ~= "/" then return nil end
    return path_key(prefix)
  end

  local function is_game_path(pattern)
    local root = package_pattern_root(pattern)
    return root ~= nil and owned_roots[root] == true
  end

  local retained = {}
  for pattern in (package.path or ""):gmatch("[^;]+") do
    if not is_game_path(pattern) then retained[#retained + 1] = pattern end
  end
  local root = _neuro_root_native
  if root:sub(-1) ~= _neuro_sep then root = root .. _neuro_sep end
  package.path = root .. "?.lua;" .. root .. "?/init.lua"
    .. (#retained > 0 and (";" .. table.concat(retained, ";")) or "")
end
local _neuro_mod_path = _neuro_root_native
if _neuro_mod_path:sub(-1) ~= _neuro_sep then _neuro_mod_path = _neuro_mod_path .. _neuro_sep end
if SMODS and type(SMODS.current_mod) == "table"
  and (type(SMODS.current_mod.path) ~= "string" or SMODS.current_mod.path == "") then
  SMODS.current_mod.path = _neuro_mod_path
end


local ModConfig = require("core.config")
local current_mod = assert(SMODS and SMODS.current_mod, "neuro-game requires Steamodded current_mod")
ModConfig.init(current_mod.config, function()
  return SMODS.save_mod_config(current_mod)
end)

local NeuroActions = require("core.actions")
local NeuroDispatcher = require("core.dispatcher")
local PersonaPalette = require("render.persona_palette")
local GfxGuard = require("render.gfx_guard")
local HUD = require("render.hud_overlay")
local Orchestrator = require("core.orchestrator")
local Metrics = require("util.metrics")

local TuningPanel
local function _get_tuning()
  TuningPanel = TuningPanel or require("hud.tuning_panel")
  return TuningPanel
end

if not G then G = {} end
G.NEURO = G.NEURO or {}
G.NEURO.actions = NeuroActions
G.NEURO.dispatcher = NeuroDispatcher
G.NEURO.ai_highlighted = G.NEURO.ai_highlighted or setmetatable({}, {__mode = "k"})
G.NEURO.ai_glow = G.NEURO.ai_glow or setmetatable({}, {__mode = "k"})

local function _boot_error_text(value)
  local ok, text = pcall(tostring, value)
  if not ok then text = "<unprintable error>" end
  text = text:gsub("[%c]", " ")
  if #text > 240 then text = text:sub(1, 237) .. "..." end
  return text
end

local original_love_update = love.update
love.update = function(dt)
  Orchestrator.update(dt, original_love_update)
end

local original_love_draw = love.draw
local drain_gfx_leak = GfxGuard.drain
local _draw_error_last = {}
local SHARED_DRAW_SLOT = {}
local function print_draw_error(slot, label, err)
  local msg = tostring(err)
  if _draw_error_last[slot] == msg then return end
  _draw_error_last[slot] = msg
  print("[neuro-game] DRAW ERROR (" .. label .. "): " .. msg)
end
local function guarded_draw(label, fn, slot)
  local key = "draw." .. label
  Metrics.time_begin(key)
  local ok, err = xpcall(fn, debug.traceback)
  Metrics.time_end(key)
  if not ok then
    drain_gfx_leak()
    print_draw_error(slot or label, label, err)
  end
end
love.draw = function()
  local pal_ok, pal_err = pcall(PersonaPalette.apply_for_frame)
  if not pal_ok then print_draw_error(SHARED_DRAW_SLOT, "palette", pal_err) end

  if original_love_draw then guarded_draw("base game draw", original_love_draw, SHARED_DRAW_SLOT) end
  local overlay_state_saved = pcall(love.graphics.push, "all")

  guarded_draw("indicator panel", HUD.draw_indicator)

  guarded_draw("cookie", HUD.draw_cookie)

  guarded_draw("login anim", HUD.draw_login)

  if TuningPanel then guarded_draw("tuning panel", TuningPanel.draw) end

  if overlay_state_saved then
    pcall(love.graphics.pop)
  else
    pcall(function()
      love.graphics.setScissor()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setShader()
      love.graphics.setBlendMode("alpha")
      love.graphics.setLineWidth(1)
    end)
  end
end

local _input_error_seen = {}
local _input_error_warning_count = 0
local _input_error_warning_limit = 8
local _input_error_suppression_reported = false

local function warn_input_hook_error(label, err)
  local message = _boot_error_text(err)
  local key = label .. "\0" .. message
  if _input_error_seen[key] then return end
  if _input_error_warning_count >= _input_error_warning_limit then
    if not _input_error_suppression_reported then
      _input_error_suppression_reported = true
      print("[neuro-game] input hook errors suppressed after "
        .. tostring(_input_error_warning_limit) .. " unique failures")
    end
    return
  end
  _input_error_seen[key] = true
  _input_error_warning_count = _input_error_warning_count + 1
  print("[neuro-game] " .. label .. " ERROR: " .. message)
end

local function run_neuro_input_hook(label, fn, ...)
  local ok, handled_or_err = pcall(fn, ...)
  if not ok then
    warn_input_hook_error(label, handled_or_err)
    return false
  end
  return handled_or_err
end

local function finish_input_hook(label, ok, ...)
  if not ok then
    warn_input_hook_error(label, (...))
    return nil
  end
  return ...
end

local function hook_input(name, label, blocked_by_login, neuro_fn)
  neuro_fn = neuro_fn or function(...)
    if TuningPanel and TuningPanel.is_open() and TuningPanel[name](...) then return true end
  end
  local original = love[name]
  love[name] = function(...)
    if blocked_by_login and G and G.NEURO and G.NEURO.login_anim then return end
    return finish_input_hook(label, pcall(function(...)
      if run_neuro_input_hook(label, neuro_fn, ...) then return true end
      if original then return original(...) end
    end, ...))
  end
end

hook_input("mousepressed", "MOUSE", true)
hook_input("mousemoved", "MOUSE MOVE", false)
hook_input("mousereleased", "MOUSE RELEASE", true)
hook_input("wheelmoved", "WHEEL", true)
hook_input("keypressed", "KEY", true, function(key)
  if key == "f8" then
    _get_tuning().toggle()
    return true
  end
  if TuningPanel and TuningPanel.is_open() and TuningPanel.keypressed(key) then return true end
end)
