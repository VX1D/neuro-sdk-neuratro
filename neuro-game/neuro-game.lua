--- STEAMODDED HEADER
--- MOD_NAME: neuro-game
--- MOD_ID: neuro-game
--- MOD_AUTHOR: [x264.webrip]
--- MOD_DESCRIPTION: Neuro SDK bridge + IPC for Balatro
--- MOD_VERSION: 1.0.0

if rawget(_G, "NEURO_SDK_MOD_LOADED") then
  return
end
_G.NEURO_SDK_MOD_LOADED = true

do
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
    local _d = _appdata .. "\\Balatro\\Mods\\neuro-game\\"
    add_path(_d .. "?.lua")
  end
end

local NeuroActions = require "core.actions"
local NeuroDispatcher = require "core.dispatcher"
local PersonaPalette = require "render.persona_palette"
local HUD = require "render.hud_overlay"
local Orchestrator = require "core.orchestrator"
local trace = require "core.trace"
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

if not G then G = {} end
G.NEURO = G.NEURO or {}
G.NEURO.actions = NeuroActions
G.NEURO.dispatcher = NeuroDispatcher
G.NEURO.ai_highlighted = G.NEURO.ai_highlighted or setmetatable({}, {__mode = "k"})

local _NEURO_DEBUG = require("core.config").bool("NEURO_DEBUG")
local function neuro_log(...)
  if _NEURO_DEBUG then print("[neuro-game]", ...) end
end

local _overlay_dev = require("core.config").bool("NEURO_OVERLAY_DEV")
local _overlay_isolate = _overlay_dev
local DevScenario = _overlay_dev and require("hud.dev_scenario") or nil
local _reload_err = nil
local function _detect_base()
  local cands = {}
  local ad = os.getenv("APPDATA")
  if ad then cands[#cands + 1] = ad .. "\\Balatro\\Mods\\neuro-game\\" end
  local sp = SMODS and SMODS.current_mod and SMODS.current_mod.path
  if sp and sp ~= "" then
    if not (sp:sub(-1) == "/" or sp:sub(-1) == "\\") then sp = sp .. "/" end
    cands[#cands + 1] = sp
  end
  for _, b in ipairs(cands) do
    local f = io.open(b .. "render/hud_overlay.lua", "rb")
    if f then f:close(); return b end
  end
  return cands[1]
end
local _mod_base = _overlay_dev and _detect_base() or nil
-- hud_overlay requires hud_shared + render.panels.* at require time; clear them too or edits won't hot-reload.
local _RELOAD_ORDER = {
  "hud.cards", "hud.emotes", "hud.prims", "render.palette", "hud.showcase",
  "hud.vouchers", "render.debug_stats", "hud.tuning_panel",
  "render.hud_shared", "hud.rows", "hud.text_colors",
  "render.panels.shop", "render.panels.pack", "render.panels.right_panel",
  "render.panels.buy_toast", "render.panels.center_showcase",
  "render.hud_overlay",
}
local _watch_files = {
  "render/hud_overlay.lua", "hud/prims.lua", "render/palette.lua", "hud/vouchers.lua",
  "hud/showcase.lua", "hud/cards.lua", "hud/emotes.lua", "render/debug_stats.lua", "hud/tuning_panel.lua",
  "render/hud_shared.lua", "hud/rows.lua", "hud/text_colors.lua",
  "render/panels/shop.lua", "render/panels/pack.lua", "render/panels/right_panel.lua",
  "render/panels/buy_toast.lua", "render/panels/center_showcase.lua",
}
local function _read(relpath)
  if not _mod_base then return nil end
  local f = io.open(_mod_base .. relpath, "rb"); if not f then return nil end
  local c = f:read("*a"); f:close(); return c
end
local function reload_overlay()
  for _, m in ipairs(_RELOAD_ORDER) do package.loaded[m] = nil end
  local ok, res = pcall(require, "render.hud_overlay")
  if ok and type(res) == "table" and res.draw_indicator then
    HUD = res
    if TuningPanel then local ok2, tp = pcall(require, "hud.tuning_panel"); if ok2 then TuningPanel = tp end end
    if DebugStats then local ok3, ds = pcall(require, "render.debug_stats"); if ok3 then DebugStats = ds end end
    _reload_err = nil
    print("[neuro-game] overlay reloaded")
  else
    _reload_err = tostring(res)
    print("[neuro-game] RELOAD FAILED (keeping last good): " .. _reload_err)
  end
end
local _watch, _watch_accum = {}, 0
if _overlay_dev then
  for _, rp in ipairs(_watch_files) do _watch[rp] = _read(rp) end
  print("[neuro-game] OVERLAY DEV MODE on -- F5: demo scenes (click the bottom button bank), F7: isolate, F6: reload, auto-reload on save"
    .. (_mod_base and ("  [watch: " .. _mod_base .. "]") or "  [watch path unresolved -> F6 only]"))
end
local function _poll_reload(dt)
  _watch_accum = _watch_accum + (dt or 0)
  if _watch_accum < 0.4 then return end
  _watch_accum = 0
  local dirty = false
  for _, rp in ipairs(_watch_files) do
    local c = _read(rp)
    if c and c ~= _watch[rp] then _watch[rp] = c; dirty = true end
  end
  if dirty then reload_overlay() end
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
  if _overlay_dev then pcall(_poll_reload, dt) end
end

local original_love_draw = love.draw
local _draw_error_last = nil
local _draw_err_seen = {}
-- LOVE's matrix stack and scissor persist across frames; an uncaught throw leaks them and compounds into a black-out within ~1s.
local function drain_gfx_leak()
  pcall(love.graphics.setScissor)
  for _ = 1, 16 do
    if not pcall(love.graphics.pop) then break end
  end
  pcall(love.graphics.origin)
  pcall(love.graphics.setColor, 1, 1, 1, 1)
  pcall(love.graphics.setLineWidth, 1)
end
local function guarded_draw(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
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
    local base_ok, base_err = xpcall(original_love_draw, debug.traceback)
    -- drains pushes leaked by the base render or a swallowed Card:draw error (hud/cards.lua); no-op on a balanced stack
    for _ = 1, 16 do
      if not pcall(love.graphics.pop) then break end
    end
    pcall(love.graphics.setScissor)
    if not base_ok then
      local e = tostring(base_err)
      if e ~= _draw_error_last then
        print("[neuro-game] DRAW ERROR (base game draw): " .. e)
        _draw_error_last = e
      end
    end
  end
  trace("TRACE: original_love_draw done")

  if _overlay_dev then pcall(DevScenario.apply) end

  if _overlay_dev and _overlay_isolate then
    pcall(function()
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

  if _overlay_dev then guarded_draw("dev buttons", DevScenario.draw_buttons) end

  if _overlay_dev and _reload_err then
    pcall(function()
      local sw = love.graphics.getWidth()
      love.graphics.setColor(0, 0, 0, 0.72)
      love.graphics.rectangle("fill", 8, 8, sw - 16, 44)
      love.graphics.setColor(1, 0.42, 0.42, 1)
      love.graphics.print("RELOAD ERROR (showing last good build):", 14, 14)
      love.graphics.print(_reload_err, 14, 30)
    end)
  end

  pcall(function()
    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
  end)
  trace("TRACE: love.draw frame complete")
end

local original_love_mousepressed = love.mousepressed
love.mousepressed = function(x, y, button, istouch, presses)
  if G and G.NEURO and G.NEURO.login_anim then return end
  -- no retry on error: handler may have applied a side effect, re-running would duplicate the click
  local ok, err = pcall(function()
    if _overlay_dev and DevScenario.mousepressed(x, y, button) then return end
    if TuningPanel and TuningPanel.is_open() and TuningPanel.mousepressed(x, y, button) then return end
    if original_love_mousepressed then
      return original_love_mousepressed(x, y, button, istouch, presses)
    end
  end)
  if not ok then
    print("[neuro-game] MOUSE ERROR: " .. tostring(err))
  end
end

local original_love_wheelmoved = love.wheelmoved
love.wheelmoved = function(wx, wy)
  if G and G.NEURO and G.NEURO.login_anim then return end
  local ok, err = pcall(function()
    if TuningPanel and TuningPanel.is_open() and TuningPanel.wheelmoved(wx, wy) then return end
    if original_love_wheelmoved then
      return original_love_wheelmoved(wx, wy)
    end
  end)
  if not ok then
    print("[neuro-game] WHEEL ERROR: " .. tostring(err))
  end
end

local original_love_keypressed = love.keypressed
love.keypressed = function(key, scancode, isrepeat)
  if G and G.NEURO and G.NEURO.login_anim then return end
  local ok, err = pcall(function()
    if _overlay_dev and key == "f7" then _overlay_isolate = not _overlay_isolate; return end
    if _overlay_dev and key == "f6" then reload_overlay(); return end
    if _overlay_dev and key == "f5" then
      DevScenario.toggle()
      print("[neuro-game] demo scenario: " .. (DevScenario.active and "ON (click the bottom button bank)" or "off"))
      return
    end
    if key == "f8" then
      _get_tuning().toggle()
      return
    end
    if TuningPanel and TuningPanel.is_open() and TuningPanel.keypressed(key) then return end
    if key == "f10" and _NEURO_DEBUG then require("tests.test_deadlock").run() end
    if key == "f9" then _get_debug().toggle() end
    if key == "f11" then _get_debug().cycle_page(1) end
    if original_love_keypressed then
      return original_love_keypressed(key, scancode, isrepeat)
    end
  end)
  if not ok then
    print("[neuro-game] KEY ERROR: " .. tostring(err))
  end
end
