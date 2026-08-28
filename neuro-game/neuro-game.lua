--- STEAMODDED HEADER
--- MOD_NAME: neuro-game
--- MOD_ID: neuro-game
--- MOD_AUTHOR: [x264.webrip]
--- MOD_DESCRIPTION: Neuro SDK bridge + IPC for Balatro
--- MOD_VERSION: 1.1.0

if rawget(_G, "NEURO_SDK_MOD_LOADED") then
  local src = debug.getinfo(1, "S").source
  print("[neuro-game] WARNING: a second copy of this mod was loaded from "
    .. tostring(src and src:gsub("^@", "") or "?")
    .. " and was skipped. Remove stale copies from the Mods directory -- whichever copy "
    .. "loads first wins, and require() can still pull modules from the other one.")
  return
end
_G.NEURO_SDK_MOD_LOADED = true

do
  local sep = package.config:sub(1, 1)
  local function appdata_mod_dir(appdata)
    return table.concat({ appdata, "Balatro", "Mods", "neuro-game", "" }, sep)
  end
  local function add_path(p)
    if p and not package.path:find(p, 1, true) then
      package.path = package.path .. ";" .. p
    end
  end
  if SMODS and SMODS.current_mod and SMODS.current_mod.path then
    add_path(SMODS.current_mod.path .. "?.lua")
  end
  local _appdata = os.getenv("APPDATA")
  if _appdata then
    local _d = appdata_mod_dir(_appdata)
    add_path(_d .. "?.lua")
  end
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
local trace = require("core.trace")
local SelfTest = require("core.selftest")
local DebugStats, StagingDebug, TuningPanel
local function _get_debug()
  if not DebugStats then
    DebugStats = require("render.debug_stats")
    StagingDebug = require("render.staging_debug")
  end
  return DebugStats
end
local function _get_tuning()
  TuningPanel = TuningPanel or require("hud.tuning_panel")
  return TuningPanel
end

local CardDex = nil
local function _get_card_dex()
  CardDex = CardDex or require("hud.card_dex")
  return CardDex
end

if not G then G = {} end
G.NEURO = G.NEURO or {}
G.NEURO.actions = NeuroActions
G.NEURO.dispatcher = NeuroDispatcher
G.NEURO.ai_highlighted = G.NEURO.ai_highlighted or setmetatable({}, {__mode = "k"})
G.NEURO.ai_glow = G.NEURO.ai_glow or setmetatable({}, {__mode = "k"})

local function _NEURO_DEBUG() return require("core.config").bool("NEURO_DEBUG") end
local function neuro_log(...)
  if _NEURO_DEBUG() then print("[neuro-game]", ...) end
end

local function _env_flag(name)
  local v = os.getenv(name)
  if not v then return nil end
  v = tostring(v):lower()
  if v == "1" or v == "on" or v == "true" or v == "yes" then return true end
  if v == "0" or v == "off" or v == "false" or v == "no" then return false end
  return nil
end

local _overlay_dev = _env_flag("NEURO_OVERLAY_DEV")
if _overlay_dev == nil then _overlay_dev = require("core.config").bool("NEURO_OVERLAY_DEV") end
local _overlay_isolate = false
local _dev_autostart = false

local HotReload = require("core.hot_reload")
local _reload_ready = false

local DevScenario = nil
local function _load_dev_scenario()
  if DevScenario then return DevScenario end
  local ok, dev = pcall(require, "hud.dev_scenario")
  if ok then
    DevScenario = dev
  else
    print("[neuro-game] dev harness failed to load: " .. tostring(dev))
  end
  return DevScenario
end

local function _warn_stale_copy()
  local own = debug.getinfo(1, "S").source
  own = own and own:gsub("^@", "") or nil
  local declared = SMODS and SMODS.current_mod and SMODS.current_mod.path
  if not (own and declared) then return end
  local here = own:gsub("\\", "/"):lower():match("^(.*)/[^/]*$")
  local there = declared:gsub("\\", "/"):lower():gsub("/+$", "")
  if here and there ~= "" and here ~= there then
    print("[neuro-game] WARNING: this chunk runs from " .. own .. " but SMODS registered "
      .. declared .. " -- a stale copy is installed and require() may mix versions")
  end
end

if _overlay_dev then
  _reload_ready = HotReload.init()
  _load_dev_scenario()
  _dev_autostart = (_env_flag("NEURO_OVERLAY_DEV_AUTOSTART") == true) and DevScenario ~= nil
  local iso = _env_flag("NEURO_OVERLAY_DEV_ISOLATE")
  _overlay_isolate = (iso == nil) and _dev_autostart or (iso == true)
  _warn_stale_copy()
  print("[neuro-game] OVERLAY DEV on -- F5 harness, F6 reload, shift+F6 reload all, F7 isolate, auto-reload on save"
    .. (_reload_ready and ("  [watch: " .. tostring(HotReload.base()) .. "]")
      or "  [watch path unresolved -> reload disabled]"))
end

local original_love_load = love.load
love.load = function(...)
  neuro_log("love.load starting")
  if original_love_load then
    local ok, err = pcall(original_love_load, ...)
    if not ok then
      print("[neuro-game] LOAD ERROR (base game): " .. tostring(err))
    end
  end
  Orchestrator.init()
  neuro_log("love.load complete")
end

local original_love_update = love.update
love.update = function(dt)
  Orchestrator.update(dt, original_love_update)
  if _overlay_dev and _reload_ready then pcall(HotReload.poll, dt) end
end

local original_love_draw = love.draw
local _draw_error_last = nil
local _draw_err_seen = {}
local drain_gfx_leak = GfxGuard.drain
G.NEURO.drain_gfx_leak = drain_gfx_leak
local _draw_metric_keys = {}
local function _draw_metric_key(label)
  local key = _draw_metric_keys[label]
  if not key then
    key = "draw." .. tostring(label)
    _draw_metric_keys[label] = key
  end
  return key
end
local function guarded_draw(label, fn)
  local key = _draw_metric_key(label)
  Metrics.time_begin(key)
  local ok, err = xpcall(fn, debug.traceback)
  Metrics.time_end(key)
  if not ok then
    drain_gfx_leak()
    local msg = tostring(err)
    if _draw_err_seen[label] ~= msg then
      print("[neuro-game] DRAW ERROR (" .. label .. "): " .. msg)
      _draw_err_seen[label] = msg
    end
  end
  return ok
end
love.draw = function()
  local pal_ok, pal_err = pcall(PersonaPalette.apply_for_frame)
  if not pal_ok then
    local e = tostring(pal_err)
    if e ~= _draw_error_last then
      print("[neuro-game] DRAW ERROR (palette): " .. e)
      _draw_error_last = e
    end
  end
  trace("TRACE: palette block done, calling original_love_draw")

  if original_love_draw then
    Metrics.time_begin("draw.base game draw")
    local base_ok, base_err = xpcall(original_love_draw, debug.traceback)
    Metrics.time_end("draw.base game draw")
    if not base_ok then
      drain_gfx_leak()
      local e = tostring(base_err)
      if e ~= _draw_error_last then
        print("[neuro-game] DRAW ERROR (base game draw): " .. e)
        _draw_error_last = e
      end
    end
  end
  trace("TRACE: original_love_draw done")
  local overlay_state_saved = pcall(love.graphics.push, "all")

  if _dev_autostart and DevScenario and not DevScenario.active then
    _dev_autostart = false
    guarded_draw("dev autostart", function() DevScenario.set(true) end)
    print("[neuro-game] dev harness auto-started (F5 toggles it off)")
  end

  local dev_mounted = false
  if _overlay_dev and DevScenario and DevScenario.active then
    dev_mounted = true
    guarded_draw("dev mount", DevScenario.mount)
  end

  if _overlay_dev and _overlay_isolate then
    guarded_draw("dev isolate", function()
      local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
      love.graphics.setColor(0.92, 0.92, 0.94, 1)
      love.graphics.rectangle("fill", 0, 0, sw, sh)
      love.graphics.setColor(0, 0, 0, 0.05)
      for gx = 0, sw, 40 do love.graphics.rectangle("fill", gx, 0, 1, sh) end
      for gy = 0, sh, 40 do love.graphics.rectangle("fill", 0, gy, sw, 1) end
    end)
  end

  trace("TRACE: calling draw_neuro_indicator")
  guarded_draw("indicator panel", HUD.draw_indicator)

  trace("TRACE: calling draw_neuro_cookie")
  guarded_draw("cookie", HUD.draw_cookie)

  trace("TRACE: calling draw_login_animation")
  guarded_draw("login anim", HUD.draw_login)

  if DebugStats then guarded_draw("debug overlay", DebugStats.draw) end
  if StagingDebug then guarded_draw("staging debug", StagingDebug.draw) end
  if TuningPanel then guarded_draw("tuning panel", TuningPanel.draw) end

  if CardDex and CardDex.active then guarded_draw("card dex", CardDex.draw) end

  if dev_mounted then guarded_draw("dev unmount", DevScenario.unmount) end
  if _overlay_dev and DevScenario then guarded_draw("dev buttons", DevScenario.draw_buttons) end

  guarded_draw("selftest banner", SelfTest.draw_banner)

  if _overlay_dev then
    local rl = HotReload.status()
    if rl.err then
      guarded_draw("dev reload banner", function()
        local sw = love.graphics.getWidth()
        local msg = tostring(rl.err)
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", 8, 8, sw - 16, 44)
        love.graphics.setColor(1, 0.42, 0.42, 1)
        love.graphics.print("RELOAD ERROR (showing last good build):", 14, 14)
        love.graphics.printf(msg, 14, 30, sw - 36, "left")
      end)
    elseif #rl.ark_order > 0 then
      guarded_draw("dev restart banner", function()
        local sw = love.graphics.getWidth()
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", 8, 8, sw - 16, 26)
        love.graphics.setColor(1, 0.82, 0.35, 1)
        love.graphics.print("RESTART NEEDED -- edited outside the reloadable set: "
          .. table.concat(rl.ark_order, ", "), 14, 14)
      end)
    end
  end

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
  trace("TRACE: love.draw frame complete")
end

local function finish_input_hook(label, ok, ...)
  if not ok then
    print("[neuro-game] " .. label .. " ERROR: " .. tostring((...)))
    return nil
  end
  return ...
end

local original_love_mousepressed = love.mousepressed
love.mousepressed = function(x, y, button, istouch, presses)
  if G and G.NEURO and G.NEURO.login_anim then return end
  return finish_input_hook("MOUSE", pcall(function()
    if CardDex and CardDex.active and CardDex.mousepressed(x, y, button) then return true end
    if _overlay_dev and DevScenario and DevScenario.mousepressed(x, y, button) then return true end
    if TuningPanel and TuningPanel.is_open() and TuningPanel.mousepressed(x, y, button) then return true end
    if original_love_mousepressed then
      return original_love_mousepressed(x, y, button, istouch, presses)
    end
  end))
end

local original_love_mousemoved = love.mousemoved
love.mousemoved = function(x, y, dx, dy, istouch)
  return finish_input_hook("MOUSE MOVE", pcall(function()
    if TuningPanel and TuningPanel.is_open() and TuningPanel.mousemoved(x, y, dx, dy) then return true end
    if original_love_mousemoved then return original_love_mousemoved(x, y, dx, dy, istouch) end
  end))
end

local original_love_mousereleased = love.mousereleased
love.mousereleased = function(x, y, button, istouch, presses)
  if G and G.NEURO and G.NEURO.login_anim then return end
  return finish_input_hook("MOUSE RELEASE", pcall(function()
    if TuningPanel and TuningPanel.is_open() and TuningPanel.mousereleased(x, y, button) then return true end
    if original_love_mousereleased then return original_love_mousereleased(x, y, button, istouch, presses) end
  end))
end

local original_love_wheelmoved = love.wheelmoved
love.wheelmoved = function(wx, wy)
  if G and G.NEURO and G.NEURO.login_anim then return end
  return finish_input_hook("WHEEL", pcall(function()
    if CardDex and CardDex.active and CardDex.wheelmoved(wx, wy) then return true end
    if TuningPanel and TuningPanel.is_open() and TuningPanel.wheelmoved(wx, wy) then return true end
    if original_love_wheelmoved then
      return original_love_wheelmoved(wx, wy)
    end
  end))
end

local original_love_keypressed = love.keypressed
love.keypressed = function(key, scancode, isrepeat)
  if G and G.NEURO and G.NEURO.login_anim then return end
  return finish_input_hook("KEY", pcall(function()
    if CardDex and CardDex.active and CardDex.keypressed(key) then return true end
    if key == "f4" then
      local dex = _get_card_dex()
      dex.toggle()
      print("[neuro-game] card dex: " .. (dex.active and "ON (E edition, S size, F filter, R report)" or "off"))
      return true
    end
    if _overlay_dev and key == "f7" then
      _overlay_isolate = not _overlay_isolate
      print("[neuro-game] overlay isolate: " .. (_overlay_isolate and "ON" or "off"))
      return true
    end
    if _overlay_dev and key == "f6" then
      local shift = love.keyboard and love.keyboard.isDown
        and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))
      HotReload.reload(shift and true or false)
      return true
    end
    if _overlay_dev and key == "f5" then
      local dev = _load_dev_scenario()
      if dev then
        dev.toggle()
        print("[neuro-game] dev harness: " .. (dev.active and "ON (bank at the bottom of the screen)" or "off"))
      end
      return true
    end
    if key == "f8" then
      _get_tuning().toggle()
      return true
    end
    if TuningPanel and TuningPanel.is_open() and TuningPanel.keypressed(key) then return true end
    if key == "f10" and _NEURO_DEBUG() then require("tests.test_deadlock").run() end
    if key == "f9" then _get_debug().toggle() end
    if key == "f11" then _get_debug().cycle_page(1) end
    if original_love_keypressed then
      return original_love_keypressed(key, scancode, isrepeat)
    end
  end))
end
