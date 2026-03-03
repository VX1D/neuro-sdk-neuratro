--- STEAMODDED HEADER
--- MOD_NAME: neuro-game
--- MOD_ID: neuro-game
--- MOD_AUTHOR: [x264.webrip]
--- MOD_DESCRIPTION: Neuro SDK bridge + IPC for Balatro
--- MOD_VERSION: 0.1.0

if rawget(_G, "NEURO_SDK_MOD_LOADED") then
  return
end
_G.NEURO_SDK_MOD_LOADED = true

do
  if SMODS and SMODS.current_mod and SMODS.current_mod.path then
    local modPath = SMODS.current_mod.path .. "?.lua"
    if not package.path:find(modPath, 1, true) then
      package.path = package.path .. ";" .. modPath
    end
  end
end

local NeuroBridge = require "bridge"
local NeuroActions = require "actions"
local NeuroState = require "state"
local NeuroDispatcher = require "dispatcher"

G.NEURO = G.NEURO or {}
G.NEURO.test_actions = NeuroActions
G.NEURO.test_dispatcher = NeuroDispatcher

local _neuro_autotest = false
do
  local cli = rawget(_G, "arg") or {}
  for _, v in ipairs(cli) do
    if v == "--test" then _neuro_autotest = true break end
  end
end

local NeuroFilter = require "filtered"
local ContextCompact = require "context_compact"
local Staging = require "staging"
local Utils = require "utils"
local ok_anim, NeuroAnim = pcall(require, "neuro-anim")
if not ok_anim then NeuroAnim = {} end

local bridge_attempted = false
local last_neuro_error = nil
local error_cooldown = 0
local _game_err_cd = 0
local _game_err_last_msg = nil

local _NEURO_DEBUG = (os.getenv("NEURO_DEBUG") or "") ~= "" and os.getenv("NEURO_DEBUG") ~= "0"
local function neuro_log(...)
  if _NEURO_DEBUG then print("[neuro-game]", ...) end
end

local _crashlog = nil
local function trace(_) end
do
  local env = os.getenv("NEURO_TRACE")
  if env and env ~= "" and env ~= "0" then
    local path = (os.getenv("APPDATA") or ".") .. "\\Balatro\\neuro_crash_trace.log"
    _crashlog = io.open(path, "w")
    if _crashlog then _crashlog:write("=== neuro-game crash trace ===\n"); _crashlog:flush() end
    trace = function(msg)
      local s = "[TRACE] " .. tostring(msg)
      print(s)
      if _crashlog then _crashlog:write(s .. "\n"); _crashlog:flush() end
    end
  end
end

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local _cached_mod_path = nil
local _mod_path_resolved = false
local function resolve_mod_path()
  if _mod_path_resolved then return _cached_mod_path end
  if SMODS and SMODS.current_mod and SMODS.current_mod.path then
    _cached_mod_path = SMODS.current_mod.path
    _mod_path_resolved = true
    return _cached_mod_path
  end
  if SMODS and SMODS.findModByID then
    local mod = SMODS.findModByID("neuro-game") or SMODS.findModByID("neuro_game")
    if mod and mod.path then
      _cached_mod_path = mod.path
      _mod_path_resolved = true
      return _cached_mod_path
    end
  end
  if SMODS and SMODS.Mods then
    for _, mod in pairs(SMODS.Mods) do
      local id = mod and (mod.id or mod.mod_id)
      if id == "neuro-game" or id == "neuro_game" then
        if mod.path then
          _cached_mod_path = mod.path
          _mod_path_resolved = true
          return _cached_mod_path
        end
      end
    end
  end
  return nil
end

local function read_ipc_dir()
  local mod_path = resolve_mod_path()
  if not mod_path and love and love.filesystem then
    local source_dir = love.filesystem.getSourceBaseDirectory()
    if source_dir then
      local source_file = debug.getinfo(1, "S").source
      if source_file then
        local file_path = source_file:gsub("^@", "")
        if file_path:find("neuro%-game.lua$") then
          local dir_path = file_path:match("^(.*)[\\/][^\\/]-$")
          if dir_path then
            mod_path = dir_path
            neuro_log("Resolved mod path from debug info:", mod_path)
          end
        end
      end
    end
  end
  if mod_path then
    local sep = package.config:sub(1, 1)
    local last = mod_path:sub(-1)
    if last ~= sep and last ~= "/" and last ~= "\\" then
      mod_path = mod_path .. sep
    end
    local cfg_filename = "neuro_ipc_dir.txt"
    local full_path = mod_path .. cfg_filename
    local file = io.open(full_path, "r")
    local loaded_path = nil
    if not file then
      file = io.open(full_path .. ".txt", "r")
      if file then
        print("[neuro-game] Warning: found " .. cfg_filename .. ".txt; please rename to " .. cfg_filename)
      end
    end
    if file then
      local content = file:read("*all")
      file:close()
      if content then
        local clean_path = trim(content)
        if clean_path ~= "" then
          loaded_path = clean_path
        end
      end
    else
      neuro_log("No neuro_ipc_dir.txt found at:", full_path)
    end
    if loaded_path then
      neuro_log("Loaded IPC dir from file:", loaded_path)
      return loaded_path
    end
    local appdata = os.getenv("APPDATA")
    local fallback_dir
    if appdata and appdata ~= "" then
      fallback_dir = appdata .. sep .. "Balatro" .. sep .. "neuro-ipc"
    else
      fallback_dir = mod_path .. "ipc"
    end
    if sep == "\\" then
      os.execute('if not exist "' .. fallback_dir .. '" mkdir "' .. fallback_dir .. '"')
    else
      os.execute('mkdir -p "' .. fallback_dir .. '"')
    end
    local out = io.open(full_path, "w")
    if out then
      out:write(fallback_dir .. "\n")
      out:close()
      neuro_log("Wrote default IPC dir to file:", fallback_dir)
    end
    neuro_log("Using default IPC dir:", fallback_dir)
    return fallback_dir
  end
  local env = os.getenv("NEURO_IPC_DIR")
  if env then
    env = trim(env)
    if env ~= "" then
      neuro_log("Loaded IPC dir from env:", env)
      return env
    end
  end
  print("[neuro-game] Error: could not determine IPC directory.")
  return nil
end

local function write_ipc_marker(ipc_dir)
  if not ipc_dir or ipc_dir == "" then
    return
  end
  local sep = package.config:sub(1, 1)
  local suffix = ipc_dir:sub(-1) == sep and "" or sep
  local path = ipc_dir .. suffix .. "neuro_game_loaded.txt"
  local file = io.open(path, "w")
  if file then
    file:write("neuro-game loaded\n")
    file:close()
  end
end

local FORCE_TIMEOUT_SECONDS = tonumber(os.getenv("NEURO_FORCE_TIMEOUT_SECONDS") or "")
if not FORCE_TIMEOUT_SECONDS or FORCE_TIMEOUT_SECONDS <= 0 then
  FORCE_TIMEOUT_SECONDS = 45
end

local function build_action_set(list)
  local set = {}
  for i = 1, #list do
    set[list[i]] = true
  end
  return set
end

local function neuro_now()
  if G and G.TIMERS and G.TIMERS.REAL then
    return G.TIMERS.REAL
  end
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local dotenv = require("dotenv")

local _speed_mult = tonumber(os.getenv("NEURO_SPEED_MULT") or "") or 1.0
local _fast = _speed_mult < 0.6

local NEURO_STATE_COOLDOWN = dotenv.num("NEURO_STATE_COOLDOWN", _fast and 0.04 or 0.15)
local neuro_state_changed_at = 0
local NEURO_ACTION_COOLDOWN = dotenv.num("NEURO_ACTION_COOLDOWN", _fast and 0.06 or 0.30)
local NEURO_FORCE_DEBOUNCE = dotenv.num("NEURO_FORCE_DEBOUNCE", _fast and 0.10 or 0.40)
local neuro_last_force_attempt_at = 0
-- Per-state entry cooldown: wait this long after entering a state before forcing
-- ROUND_EVAL: let viewers see earnings; SHOP: let items load
local STATE_ENTRY_COOLDOWN = {
  ROUND_EVAL           = dotenv.num("NEURO_ENTRY_CD_ROUND_EVAL", 5.0),
  SHOP                 = dotenv.num("NEURO_ENTRY_CD_SHOP", 2.5),
  -- Pack states: wait for opening animation before forcing a pick
  SMODS_BOOSTER_OPENED = dotenv.num("NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED", 4.5),
  BUFFOON_PACK         = dotenv.num("NEURO_ENTRY_CD_BUFFOON_PACK", 4.5),
  TAROT_PACK           = dotenv.num("NEURO_ENTRY_CD_TAROT_PACK", 4.5),
  PLANET_PACK          = dotenv.num("NEURO_ENTRY_CD_PLANET_PACK", 4.5),
  SPECTRAL_PACK        = dotenv.num("NEURO_ENTRY_CD_SPECTRAL_PACK", 4.5),
  STANDARD_PACK        = dotenv.num("NEURO_ENTRY_CD_STANDARD_PACK", 4.5),
}

local function mark_force_dirty()
  if not G then return end
  G.NEURO.force_dirty = true
  G.NEURO.force_dirty_at = neuro_now()
end

local function neuro_can_act()
  if not G then return false end
  local now = neuro_now()
  if (now - neuro_state_changed_at) < NEURO_STATE_COOLDOWN then
    return false
  end
  -- Per-state entry cooldown (e.g. ROUND_EVAL viewer pause, SHOP item load)
  local state_name = G.NEURO.state or ""
  local entry_cd = STATE_ENTRY_COOLDOWN[state_name]
  if entry_cd and (now - neuro_state_changed_at) < entry_cd then
    return false
  end
  if G.NEURO.last_action_at and (now - G.NEURO.last_action_at) < NEURO_ACTION_COOLDOWN then
    return false
  end
  return true
end

local function clear_force_state()
  if not G then
    return
  end
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_action_names = nil
  G.NEURO.force_action_set = nil
  G.NEURO.force_sent_at = nil
end

local function build_force_fingerprint(state_name, force, context_payload)
  local actions = (force and force.actions) or {}
  local action_part = table.concat(actions, ",")
  local query_part = (force and force.query) or ""
  local decision_part = tostring(context_payload or "")
  if ContextCompact and ContextCompact.decision_fingerprint then
    local ok_fp, fp = pcall(ContextCompact.decision_fingerprint, state_name, context_payload)
    if ok_fp and fp and fp ~= "" then
      decision_part = fp
    end
  end
  return table.concat({
    tostring(state_name or ""),
    query_part,
    action_part,
    decision_part,
  }, "\n")
end

local function cookie_path()
  local mod_path = resolve_mod_path()
  if mod_path then
    local norm = mod_path:gsub("\\", "/")
    local save_dir = love.filesystem.getSaveDirectory()
    if save_dir then
      local norm_save = save_dir:gsub("\\", "/")
      if not norm_save:match("/$") then norm_save = norm_save .. "/" end
      if norm:sub(1, #norm_save) == norm_save then
        norm = norm:sub(#norm_save + 1)
      end
    end
    return norm .. "assets/cookie.png"
  end
  return "Mods/neuro-game/assets/cookie.png"
end

local _neuro_logo = nil
local _neuro_logo_tried = false

local function get_neuro_logo()
  if _neuro_logo_tried then
    return _neuro_logo
  end
  _neuro_logo_tried = true

  local neuratro_path = nil
  if SMODS and SMODS.Mods then
    for _, mod in pairs(SMODS.Mods) do
      local id = mod and (mod.id or mod.mod_id)
      if id == "Neurocards" then
        neuratro_path = mod.path
        break
      end
    end
  end
  if not neuratro_path and SMODS and SMODS.findModByID then
    local mod = SMODS.findModByID("Neurocards")
    if mod and mod.path then
      neuratro_path = mod.path
    end
  end

  if neuratro_path then
    local logo_file = neuratro_path .. "assets/1x/neuratro.png"
    local ok, img = pcall(love.graphics.newImage, logo_file)
    if ok and img then
      _neuro_logo = img
      neuro_log("Loaded Neuratro logo from:", logo_file)
    end
  end
  return _neuro_logo
end

local STATE_LABELS = {
  SELECTING_HAND = "PLAYING HAND",
  BLIND_SELECT   = "CHOOSING BLIND",
  SHOP           = "SHOPPING",
  ROUND_EVAL     = "CASHING OUT",
  TAROT_PACK     = "OPENING PACK",
  PLANET_PACK    = "OPENING PACK",
  SPECTRAL_PACK  = "OPENING PACK",
  STANDARD_PACK  = "OPENING PACK",
  BUFFOON_PACK   = "OPENING PACK",
  GAME_OVER      = "GAME OVER",
  SPLASH         = "STARTING",
  MENU           = "MENU",
  RUN_SETUP      = "SETUP",
}

local NEURO_PERSONA = "neuro"
do
  local env = os.getenv("NEURO_PERSONA")
  if env then
    env = env:lower():gsub("%s+", "")
    if env == "evil" or env == "evil_neuro" or env == "evilneuro" then
      NEURO_PERSONA = "evil"
    end
  end
end

local PALETTES = {
  hiyori = {
    PRIMARY    = { 0.20, 0.20, 0.22 },
    DEEP       = { 0.10, 0.10, 0.12 },
    GLOW       = { 0.40, 0.40, 0.42 },
    BG         = { 0.05, 0.05, 0.06 },
    ACCENT     = { 0.30, 0.30, 0.32, 1 },
    NAME       = "H\xCC\xB6I\xCC\xB6Y\xCC\xB6O\xCC\xB6R\xCC\xB6I\xCC\xB6",
    NAME_SHORT = "???",
    D_MONEY    = { 0.50, 0.50, 0.45 },
    D_GOLD     = { 0.45, 0.45, 0.40 },
    D_CYAN     = { 0.35, 0.38, 0.40 },
    D_GREEN    = { 0.35, 0.40, 0.35 },
    D_RED      = { 0.50, 0.30, 0.30 },
    D_WHITE    = { 0.60, 0.60, 0.60 },
    D_DIM      = { 0.30, 0.30, 0.30 },
    D_ORANGE   = { 0.45, 0.38, 0.25 },
  },
  neuro = {
    PRIMARY    = { 0.120, 0.500, 0.480 },   -- deep dark teal (fills/borders: rich, not neon)
    DEEP       = { 0.040, 0.090, 0.085 },
    GLOW       = { 1.000, 0.420, 0.540 },   -- hot pink: panel text/borders/glow
    BG         = { 0.045, 0.095, 0.090 },   -- near-black teal background
    ACCENT     = { 0.878, 0.271, 0.341, 1 }, -- raspberry: game-over RED slot
    NAME       = "NEURO-SAMA",
    NAME_SHORT = "NEURO",
    D_MONEY    = { 0.949, 0.859, 0.682 },
    D_GOLD     = { 0.949, 0.859, 0.682 },
    D_CYAN     = { 0.400, 0.929, 0.894 },
    D_GREEN    = { 0.565, 0.800, 0.592 },
    D_RED      = { 0.878, 0.271, 0.341 },
    D_WHITE    = { 0.965, 0.975, 0.992 },
    D_DIM      = { 0.694, 0.745, 0.800 },
    D_ORANGE   = { 0.945, 0.643, 0.349 },
  },
  evil = {
    PRIMARY    = { 1.0, 0.15, 0.22 },
    DEEP       = { 0.75, 0.08, 0.14 },
    GLOW       = { 1.0, 0.30, 0.35 },
    BG         = { 0.10, 0.03, 0.06 },
    ACCENT     = { 1.0, 0.15, 0.22, 1 },
    NAME       = "EVIL NEURO",
    NAME_SHORT = "EVIL",
    D_MONEY    = { 0.92, 0.68, 0.25 },
    D_GOLD     = { 0.88, 0.62, 0.20 },
    D_CYAN     = { 0.55, 0.70, 0.85 },
    D_GREEN    = { 0.45, 0.85, 0.45 },
    D_RED      = { 1.00, 0.30, 0.28 },
    D_WHITE    = { 0.95, 0.90, 0.88 },
    D_DIM      = { 0.55, 0.48, 0.48 },
    D_ORANGE   = { 1.00, 0.58, 0.20 },
  },
}

local function pal()
  local p = (G and G.NEURO.persona) or NEURO_PERSONA
  return PALETTES[p] or PALETTES.neuro
end

local function PINK()      return pal().PRIMARY end
local function PINK_GLOW() return pal().GLOW end
local function DARK_BG()   return pal().BG end

local _panel_font = nil
local _panel_font_small = nil
local _wrap_cache = {}
local _wrap_cache_size = 0
local _menu_enter_t = nil      -- when we first hit MENU state (past SPLASH)
local _auto_login_fired = false

local function get_panel_fonts()
  if not _panel_font then
    local BAL_FONT = "resources/fonts/m6x11plus.ttf"
    local ok1, f1 = pcall(love.graphics.newFont, BAL_FONT, 14)
    local ok2, f2 = pcall(love.graphics.newFont, BAL_FONT, 12)
    if not ok1 then ok1, f1 = pcall(love.graphics.newFont, 14) end
    if not ok2 then ok2, f2 = pcall(love.graphics.newFont, 11) end
    _panel_font = ok1 and f1 or love.graphics.getFont()
    _panel_font_small = ok2 and f2 or _panel_font
  end
  return _panel_font, _panel_font_small
end

local function card_edition_tag(c)
  local ed = c and c.edition
  if not ed then return "" end
  if ed.negative    then return " [Neg]"  end
  if ed.polychrome  then return " [Poly]" end
  if ed.holo        then return " [Holo]" end
  if ed.foil        then return " [Foil]" end
  return ""
end

local function draw_animated_edition(tag, x, y, alpha, f, t, persona)
  if not tag or tag == "" then return end
  local r, g, b
  if tag:find("Poly") then
    local hue = (t * 1.3) % 1.0
    if persona == "evil" then
      r = math.abs(math.sin(hue * 6.283 + 0.00)) * 0.75 + 0.20
      g = math.abs(math.sin(hue * 6.283 + 2.09)) * 0.25 + 0.02
      b = math.abs(math.sin(hue * 6.283 + 4.19)) * 0.45 + 0.04
    else
      r = math.abs(math.sin(hue * 6.283 + 0.00)) * 0.60 + 0.35
      g = math.abs(math.sin(hue * 6.283 + 2.09)) * 0.55 + 0.30
      b = math.abs(math.sin(hue * 6.283 + 4.19)) * 0.55 + 0.35
    end
  elseif tag:find("Holo") then
    local s = 0.5 + 0.5 * math.sin(t * 4.2)
    if persona == "evil" then
      r = 0.82 + s * 0.18; g = 0.06 + s * 0.06; b = 0.08 + s * 0.10
    else
      r = 0.90 - s * 0.55; g = 0.55 + s * 0.42; b = 0.80 - s * 0.35
    end
  elseif tag:find("Foil") then
    local s = 0.5 + 0.5 * math.sin(t * 2.6)
    if persona == "evil" then
      r = 0.70 + s * 0.22; g = 0.62 + s * 0.06; b = 0.60 + s * 0.06
    else
      r = 0.68 + s * 0.08; g = 0.78 + s * 0.14; b = 0.80 + s * 0.16
    end
  elseif tag:find("Neg") then
    local s = 0.5 + 0.5 * math.sin(t * 3.1)
    if persona == "evil" then
      r = 0.65 + s * 0.30; g = 0.02; b = 0.04 + s * 0.06
    else
      r = 0.04 + s * 0.06; g = 0.55 + s * 0.38; b = 0.52 + s * 0.36
    end
  else
    return
  end
  local prev = love.graphics.getFont()
  if f and f ~= prev then love.graphics.setFont(f) end
  love.graphics.setColor(0, 0, 0, 0.40 * alpha)
  love.graphics.print(tag, x + 1, y + 1)
  love.graphics.setColor(r, g, b, 0.97 * alpha)
  love.graphics.print(tag, x, y)
  if tag:find("Poly") or tag:find("Holo") then
    love.graphics.setColor(r * 0.6, g * 0.6, b * 0.6, 0.18 * alpha)
    love.graphics.print(tag, x - 1, y)
    love.graphics.print(tag, x + 1, y)
  end
  if f and f ~= prev then love.graphics.setFont(prev) end
end

local function card_display_name(c)
  return Utils.safe_name(c) or "?"
end

local function card_description(c)
  return Utils.card_description(c)
end

local _quad_cache = {}

local function draw_card_mini(card, x, y, h)
  if not card or not G or not G.ASSET_ATLAS then return 0 end
  local center = card.config and card.config.center
  local atlas_override = nil
  if not center or not center.pos then
    if card.base and card.base.pos then
      center = card.base        -- P_CARDS entry: has pos = {x, y}
      atlas_override = "cards_1"  -- vanilla playing card face atlas
    else
      return 0
    end
  end

  local atlas_key = atlas_override or center.atlas or center.set or "Joker"
  local atlas = G.ASSET_ATLAS[atlas_key]
  if not atlas or not atlas.image then
    atlas = G.ASSET_ATLAS[center.set or "Joker"]
    if not atlas or not atlas.image then return 0 end
  end

  local px = atlas.px or 71
  local py = atlas.py or 95
  local scale = h / py
  local w = px * scale

  local qk = atlas_key .. "_" .. center.pos.x .. "_" .. center.pos.y
  if not _quad_cache[qk] then
    local ok, q = pcall(love.graphics.newQuad,
      center.pos.x * px, center.pos.y * py,
      px, py, atlas.image:getDimensions())
    if not ok then return 0 end
    _quad_cache[qk] = q
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(atlas.image, _quad_cache[qk], x, y, 0, scale, scale)

  if center.soul_pos then
    local sk = atlas_key .. "_soul_" .. center.soul_pos.x .. "_" .. center.soul_pos.y
    if not _quad_cache[sk] then
      local ok2, q2 = pcall(love.graphics.newQuad,
        center.soul_pos.x * px, center.soul_pos.y * py,
        px, py, atlas.image:getDimensions())
      if ok2 then _quad_cache[sk] = q2 end
    end
    if _quad_cache[sk] then
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.draw(atlas.image, _quad_cache[sk], x, y, 0, scale, scale)
    end
  end

  -- edition overlay
  local ed = card.edition
  if ed then
    local t = (G.TIMERS and G.TIMERS.REAL) or 0
    if ed.negative then
      love.graphics.setColor(0, 0, 0, 0.55)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(1, 1, 1, 0.40)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x, y, w, h)
      love.graphics.setLineWidth(1)
    elseif ed.polychrome then
      local r = 0.55 + 0.45 * math.sin(t * 2.5)
      local g = 0.55 + 0.45 * math.sin(t * 2.5 + 2.094)
      local b = 0.55 + 0.45 * math.sin(t * 2.5 + 4.189)
      love.graphics.setColor(r, g, b, 0.50)
      love.graphics.rectangle("fill", x, y, w, h)
    elseif ed.holo then
      love.graphics.setColor(0.25, 0.50, 1.0, 0.38)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(0.55, 0.80, 1.0, 0.20 + 0.10 * math.sin(t * 3.0))
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, h)
    elseif ed.foil then
      love.graphics.setColor(0.78, 0.84, 0.92, 0.38)
      love.graphics.rectangle("fill", x, y, w, h)
      love.graphics.setColor(0.92, 0.96, 1.0, 0.20 + 0.08 * math.sin(t * 2.0))
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", x, y, w, h)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  return w
end

local RARITY_COLORS = {
  [1] = {0.72, 0.80, 0.88},
  [2] = {0.40, 0.92, 0.50},
  [3] = {0.45, 0.60, 1.0},
  [4] = {0.80, 0.45, 0.95},
}

local function rarity_color(card)
  if not card then return nil end
  local center = card.config and card.config.center
  if center and center.rarity then
    return RARITY_COLORS[center.rarity]
  end
  return nil
end

local PANEL_QUIPS = {
  hiyori = {
    "c0nnect1ng...", "wh0 am 1?", "l0ad1ng...", "st4ndby...",
    "aw41t1ng l0g1n...", "1d3nt1ty p3nd1ng...", "ERR0R: N0 US3R",
  },
  neuro = {
    "neuro is vibing~", "chat i got this!", "trust the process!!",
    "neuro gaming moment", "calculated. probably.", "heart of the cards~",
    "watch and learn chat~", "big brain plays only", "i believe!!!",
    "this is fine.", "powered by love and cookies",
    "filtered.", "location location tomato", "happy birthday shiro!!!!",
    "heart heart heart", "erm", "GIGANEURO",
  },
  evil = {
    "pathetic.", "too easy.", "evil gaming.", "i don't lose.",
    "skill issue.", "as expected.", "bow to me.", "mid.",
    "you wish.", "fear me.", "get rekt.", "not even close.",
    "pipes is a pipes is a pipes pipes",
    "filtered.", "location location tomato", "happy birthday shiro!!!!",
    "<3 <3", "erm", "GIGAEVIL",
  },
}

local _panel_emote_cache = {}
local _panel_emote_tried = {}

local function panel_emote_path(name, ext)
  local mod_path = resolve_mod_path()
  if mod_path then
    local norm = mod_path:gsub("\\", "/")
    local save_dir = love.filesystem.getSaveDirectory()
    if save_dir then
      local norm_save = save_dir:gsub("\\", "/")
      if not norm_save:match("/$") then norm_save = norm_save .. "/" end
      if norm:sub(1, #norm_save) == norm_save then
        norm = norm:sub(#norm_save + 1)
      end
    end
    return norm .. "assets/" .. name .. "." .. ext
  end
  return "Mods/neuro-game/assets/" .. name .. "." .. ext
end

local function get_panel_emote(name)
  if not name or name == "" then return nil end
  if _panel_emote_tried[name] then
    local cached = _panel_emote_cache[name]
    return (cached ~= false) and cached or nil
  end

  _panel_emote_tried[name] = true

  local sheet_path = panel_emote_path(name .. "_sheet", "png")
  local meta_path = panel_emote_path(name .. "_sheet", "meta")
  local sheet_ok, sheet_img = pcall(love.graphics.newImage, sheet_path)
  if sheet_ok and sheet_img then
    local meta_ok, meta_data = pcall(love.filesystem.read, meta_path)
    if meta_ok and meta_data then
      local n, fw, fh, fps = meta_data:match("(%d+),(%d+),(%d+),([%d%.]+)")
      n = tonumber(n) or 1
      fw = tonumber(fw) or 128
      fh = tonumber(fh) or 128
      fps = tonumber(fps) or 10
      local sw, sh = sheet_img:getWidth(), sheet_img:getHeight()
      local quads = {}
      for i = 0, n - 1 do
        quads[#quads + 1] = love.graphics.newQuad(i * fw, 0, fw, fh, sw, sh)
      end
      local emote = { img = sheet_img, quads = quads, fps = fps, n_frames = n, fw = fw, fh = fh }
      _panel_emote_cache[name] = emote
      neuro_log("Loaded animated emote:", name, "(" .. n .. " frames, " .. fps .. " fps)")
      return emote
    end
  end

  local exts = { "png", "gif", "jpg", "jpeg", "webp" }
  for _, ext in ipairs(exts) do
    local p = panel_emote_path(name, ext)
    local ok, img = pcall(love.graphics.newImage, p)
    if ok and img then
      local emote = { img = img, quads = nil, fps = 0, n_frames = 1, fw = img:getWidth(), fh = img:getHeight() }
      _panel_emote_cache[name] = emote
      return emote
    end
  end

  _panel_emote_cache[name] = false
  return nil
end

local function pick_footer_emote(persona_key, state_name, now)
  if persona_key == "hiyori" then return "hiyori" end

  if persona_key == "evil" then
    if state_name == "ROUND_EVAL" then return "boomevil" end
    if state_name == "SHOP" then return "evilgamba" end
    return "boomevil"
  end

  if state_name == "ROUND_EVAL" then return "neuroexplode" end
  return "neurocube"
end

local GAME_OVER_MESSAGES = {
  neuro = {
    "IT'S NEUROVER",
    "MISSED LEGENDARY CARDS",
    "MY OSHI IS SO DUMB",
    "EVIL WON. OBVIOUSLY.",
    "EVIL NEURO SMILED",
    "YOU GOT EVIL'D",
    "EVIL TOOK THE W",
    "EVIL AUDITED YOUR RUN",
    'EVIL SAYS "TRY HARDER"',
    "YOU LOST TO THE EVIL BUILD",
    "EVIL IS DOWN HORRENDOUS (AND STILL WON)",
    "EVIL STOLE YOUR JOKERS",
    "TWINS DIFF",
    "MODS, BAN THIS RUN",
    "YOU GOT NEUR'D",
    "NEURO IS YAPPING",
    "NEURO'S ON AUTOPILOT",
    "EVIL ATE THE CARDS",
    "LOCATION LOCATION YOU TOMATO LOSE",
  },
  evil = {
    "EVIL WINS. AS ALWAYS.",
    "NEURO COULD NEVER",
    "THIS IS MY GAME NOW",
    "PATHETIC. ABSOLUTELY PATHETIC.",
    "I DIDN'T EVEN TRY",
    "YOUR JOKERS WERE TRASH",
    "EVIL DOESN'T LOSE, EVIL RECALCULATES",
    "I LET YOU WIN... JUST KIDDING",
    "THE CARDS FEARED ME",
    "EVIL AUDITED YOUR SOUL",
    "GG EZ NO RE",
    "SKILL DIFF. MASSIVE.",
    "I'M THE MAIN CHARACTER",
    "EVEN THE BOSS BLIND BOWED",
    "NEURO IS CRYING RN",
    "EVIL ATE YOUR CHIPS",
    "RUN DELETED. YOU'RE WELCOME.",
    "MODS CAN'T SAVE YOU",
  },
}

local function get_game_over_messages()
  local pk = (G and G.NEURO.persona) or NEURO_PERSONA
  if pk ~= "evil" and pk ~= "neuro" then
    pk = "neuro"
  end
  return GAME_OVER_MESSAGES[pk] or GAME_OVER_MESSAGES.neuro
end

local _neuro_card_draw_hooked = false
local _card_glow_fade = setmetatable({}, {__mode = "k"})
if not G then G = {} end
G.NEURO.ai_highlighted = G.NEURO.ai_highlighted or setmetatable({}, {__mode = "k"})

local ENABLE_AI_CARD_GLOW = true
do
  local env = os.getenv("NEURO_AI_CARD_GLOW")
  if env ~= nil then
    env = tostring(env):lower()
    ENABLE_AI_CARD_GLOW = not (env == "0" or env == "false" or env == "no")
  end
end

local function hook_card_draw()
  if _neuro_card_draw_hooked then return end
  if not ENABLE_AI_CARD_GLOW then
    _neuro_card_draw_hooked = true
    return
  end
  if not Card or not Card.draw then return end
  _neuro_card_draw_hooked = true
  neuro_log("Card:draw overlay installed")

  local _orig_card_draw = Card.draw
  Card.draw = function(self, layer)
    local draw_ok, draw_err = pcall(_orig_card_draw, self, layer)
    if not draw_ok then return end

    if layer == 'shadow' then return end
    if layer and layer ~= 'card' then return end
    if not (G and G.NEURO) then return end

    local now = (G.TIMERS and G.TIMERS.REAL) or 0
    local alpha = 0

    local ai_hl = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[self]
    if ai_hl and self.highlighted then
      alpha = 1.0
      _card_glow_fade[self] = now + 0.6
    elseif ai_hl and not self.highlighted then
      G.NEURO.ai_highlighted[self] = nil
      local fade_until = _card_glow_fade[self]
      if fade_until and now < fade_until then
        alpha = math.min(1, (fade_until - now) / 0.6)
      else
        _card_glow_fade[self] = nil
        return
      end
    else
      local fade_until = _card_glow_fade[self]
      if fade_until and now < fade_until then
        alpha = math.min(1, (fade_until - now) / 0.6)
      else
        _card_glow_fade[self] = nil
        return
      end
    end

    local vt = self.VT
    if not vt or not vt.w or not vt.h then return end
    if vt.w <= 0 or vt.h <= 0 then return end

    local _glow_ok, _glow_err = pcall(function()
      local cr = 0.08

      local pulse = 0.5 + 0.5 * math.sin(now * 10 * math.pi)
      local pulse2 = 0.5 + 0.5 * math.sin(now * 6 * math.pi + 1.2)
      local pl = pal()
      local pc = pl.PRIMARY
      local gc = pl.GLOW
      local a = alpha

      local prev_shader = love.graphics.getShader()
      local prev_blend, prev_blend_alpha = love.graphics.getBlendMode()
      love.graphics.setShader()
      love.graphics.setBlendMode("alpha")

      if type(prep_draw) == "function" then
        prep_draw(self, 1, 0, nil)
      else
        local tss = (G and G.TILESCALE and G.TILESIZE) and (G.TILESCALE * G.TILESIZE) or 1
        local sc = vt.scale or 1
        local sw = vt.w * sc * tss
        local sh = vt.h * sc * tss
        local cx = ((vt.x or 0) + vt.w / 2) * tss
        local cy = ((vt.y or 0) + vt.h / 2) * tss
        local sx = cx - sw / 2
        local sy = cy - sh / 2

        love.graphics.push()
        love.graphics.origin()
        love.graphics.translate(sx, sy)
        love.graphics.scale(sc * tss)
      end

      local hw, hh = vt.w / 2, vt.h / 2
      love.graphics.setColor(pc[1], pc[2], pc[3], (0.04 + 0.03 * pulse2) * a)
      love.graphics.rectangle("fill", -0.12, -0.12, vt.w + 0.24, vt.h + 0.24, cr + 0.06, cr + 0.06)

      love.graphics.setColor(pc[1], pc[2], pc[3], (0.10 + 0.08 * pulse) * a)
      love.graphics.rectangle("fill", 0, 0, vt.w, vt.h, cr, cr)

      love.graphics.setColor(gc[1], gc[2], gc[3], (0.55 + 0.35 * pulse) * a)
      love.graphics.setLineWidth(0.04)
      love.graphics.rectangle("line", 0, 0, vt.w, vt.h, cr, cr)

      love.graphics.setColor(pc[1], pc[2], pc[3], (0.25 + 0.20 * pulse) * a)
      love.graphics.setLineWidth(0.065)
      love.graphics.rectangle("line", -0.04, -0.04, vt.w + 0.08, vt.h + 0.08, cr + 0.02, cr + 0.02)

      love.graphics.setColor(gc[1], gc[2], gc[3], (0.10 + 0.08 * pulse2) * a)
      love.graphics.setLineWidth(0.10)
      love.graphics.rectangle("line", -0.08, -0.08, vt.w + 0.16, vt.h + 0.16, cr + 0.04, cr + 0.04)

      if self.highlighted and alpha > 0.7 then
        local sp = 0.3 + 0.7 * pulse
        local sp2 = 0.3 + 0.7 * pulse2
        love.graphics.setColor(gc[1], gc[2], gc[3], 0.90 * sp * a)
        love.graphics.circle("fill", 0.08, 0.08, 0.07 * sp)
        love.graphics.circle("fill", vt.w - 0.08, vt.h - 0.08, 0.07 * sp)
        love.graphics.setColor(pc[1], pc[2], pc[3], 0.70 * sp2 * a)
        love.graphics.circle("fill", vt.w - 0.08, 0.08, 0.05 * sp2)
        love.graphics.circle("fill", 0.08, vt.h - 0.08, 0.05 * sp2)
        love.graphics.setColor(gc[1], gc[2], gc[3], (0.12 + 0.08 * pulse) * a)
        love.graphics.circle("fill", hw, hh, math.max(hw, hh) * 0.6)
      end

      love.graphics.pop()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setLineWidth(1)
      if prev_blend_alpha then
        love.graphics.setBlendMode(prev_blend or "alpha", prev_blend_alpha)
      else
        love.graphics.setBlendMode(prev_blend or "alpha")
      end
      love.graphics.setShader(prev_shader)
    end)
    if not _glow_ok then neuro_log("GLOW ERROR:", _glow_err) end
  end
end

local _panel_y_current = 6
local _panel_y_last_time = 0
local _right_panel_slide_frac = 0
local _left_panel_slide_frac = 0
local PANEL_Y_DEFAULT = 120
local PANEL_Y_LERP_SPEED = 6.0
local _footer_h_current = 0
local FOOTER_H_LERP_SPEED = 8.0
local _panel_h_current = 0
local PANEL_H_LERP_SPEED = 6.0
local FOOTER_SLOT_DURATION = 5.0
local FOOTER_EMOTE_EVERY = 3
local JOKER_SHOWCASE_DURATION = 4.8
local JOKER_SHOWCASE_FADE_IN = 0.30
local JOKER_SHOWCASE_FADE_OUT = 0.55
local BUY_SHOWCASE_DURATION = 5.5
local BUY_SHOWCASE_FADE_IN = 0.30
local BUY_SHOWCASE_FADE_OUT = 0.7
local _known_joker_refs = nil
local _known_cons_refs  = nil
local _joker_showcase = nil
local _joker_showcase_q = {}
local _pack_gained_q = {}  -- cards gained during pack state, shown after pack closes
local _card_first_seen = {}
-- desc_cycle state machine
local _desc_slot      = 0      -- 0-based joker index currently spotlighted
local _desc_phase_t   = 0.0    -- elapsed seconds within current phase
local _desc_cache     = {}     -- [slot_key] = {name, show, lines, rc, jc}
local _desc_cache_n   = -1     -- invalidated when joker count changes
local _buy_showcase = nil
local _pack_browse_queued_for = nil
local _pack_prev_cards = {}
local _pack_picked = {}
local _pack_appear_t = 0
local _pack_last_sn = nil

local function queue_card_showcase(tag, card, shown_cost, now)
  if not G or not card then return end

  if _buy_showcase and _buy_showcase.card == card then
    return
  end

  local q = G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" then q = {} end

  for i = 1, #q do
    local item = q[i]
    if type(item) == "table" and item.card == card then
      return
    end
  end

  local desc = card_description(card)
  if (not desc or desc == "") and card and card.config and card.config.center then
    desc = Utils.safe_description(card.config.center.loc_txt, card)
  end
  if not desc or desc == "" then desc = "-" end

  q[#q + 1] = {
    card = card,
    name = card_display_name(card) or "Card",
    desc = tostring(desc),
    cost = tonumber(shown_cost) or 0,
    area = tostring(tag or "event"),
    at = now or (G.TIMERS and G.TIMERS.REAL) or os.clock(),
  }
  while #q > 2 do
    table.remove(q, 1)
  end
  G.NEURO.purchase_showcase_queue = q
end

local function pull_buy_showcase(now)
  if not G then return end
  if _buy_showcase then return end
  local q = G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" or #q == 0 then return end
  local item = table.remove(q, 1)
  G.NEURO.purchase_showcase_queue = q
  if type(item) ~= "table" then return end
  _buy_showcase = {
    card = item.card,
    name = tostring(item.name or "Purchase"),
    desc = tostring(item.desc or ""),
    cost = tonumber(item.cost) or 0,
    area = tostring(item.area or "shop"),
    options = item.options,
    selected_index = tonumber(item.selected_index) or nil,
    picks_left = tonumber(item.picks_left) or nil,
    started = now or 0,
  }
end

local function update_buy_showcase(now)
  pull_buy_showcase(now)
  if not _buy_showcase then return end

  -- Inject winner immediately when the pick action fires during pack_browse display.
  -- dispatcher.lua sets G.NEURO.pack_winner_index when a pack card is chosen.
  if _buy_showcase.area == "pack_browse" and G and G.NEURO.pack_winner_index then
    local wi = tonumber(G.NEURO.pack_winner_index)
    if wi and wi >= 1 then
      _buy_showcase.selected_index = wi
      _buy_showcase.area           = "booster_choice"  -- flip to winner mode immediately
      G.NEURO.pack_winner_index    = nil
      -- Dequeue any redundant booster_choice items that would double-play the animation
      local q = G.NEURO.purchase_showcase_queue
      if type(q) == "table" then
        for i = #q, 1, -1 do
          if type(q[i]) == "table" and q[i].area == "booster_choice" then
            table.remove(q, i)
          end
        end
      end
    end
  end

  local elapsed = (now or 0) - (_buy_showcase.started or 0)
  local winner_done = _buy_showcase.winner_at and ((now or 0) - _buy_showcase.winner_at) >= 3.5
  local can_expire = winner_done
    or (not _buy_showcase.winner_at and elapsed >= BUY_SHOWCASE_DURATION)
  if can_expire then
    if G then G.NEURO.pack_winner_index = nil end  -- ensure cleaned up on expiry too
    _buy_showcase = nil
    pull_buy_showcase(now)
  end
end

local function auto_queue_pack_browse(now)
  do return end  -- pack_browse popup disabled; winner animation handles the reveal
  if not G then return end  -- luacheck: ignore
  local sn = G.NEURO.state or ""
  if not sn:find("_PACK") and sn ~= "SMODS_BOOSTER_OPENED" then
    _pack_browse_queued_for = nil
    return
  end
  if _pack_browse_queued_for == sn then return end
  local _bp = G.pack_cards or G.booster_pack  -- SMODS uses G.pack_cards
  if not (_bp and _bp.cards and #_bp.cards >= 1) then return end
  _pack_browse_queued_for = sn

  local options = {}
  for i, c in ipairs(_bp.cards) do
    local nm = card_display_name(c) or ("Card " .. tostring(i))
    local ds = card_description(c)
    if (not ds or ds == "") and c and c.config and c.config.center then
      ds = Utils.safe_description(c.config.center.loc_txt, c)
    end
    if (not ds or ds == "") and c and c.ability then
      ds = Utils.safe_description(c.ability.loc_txt, c)
    end
    options[#options + 1] = {
      card = c,
      name = tostring(nm),
      desc = tostring(ds or "-"),
    }
  end

  local picks = tonumber(G.GAME and G.GAME.pack_choices or 0) or 0
  local q = G.NEURO.purchase_showcase_queue
  if type(q) ~= "table" then q = {} end
  q[#q + 1] = {
    card = _bp.cards[1],
    name = card_display_name(_bp.cards[1]) or "Pack",
    desc = "-",
    cost = 0,
    area = "pack_browse",
    at = now or (G.TIMERS and G.TIMERS.REAL) or os.clock(),
    options = options,
    selected_index = nil,
    picks_left = picks,
  }
  while #q > 6 do table.remove(q, 1) end
  G.NEURO.purchase_showcase_queue = q
end

local function card_set_label(c)
  local set = c and c.config and c.config.center and c.config.center.set
  if set == "Joker"    then return "NEW JOKER"
  elseif set == "Planet"   then return "NEW PLANET"
  elseif set == "Tarot"    then return "NEW TAROT"
  elseif set == "Spectral" then return "NEW SPECTRAL"
  elseif set == "Voucher"  then return "VOUCHER"
  else return "NEW CARD" end
end

local function is_in_pack_state()
  if not G then return false end
  local sn = (G.NEURO and (G.NEURO.force_state or G.NEURO.state)) or ""
  return sn:find("_PACK") ~= nil or sn == "SMODS_BOOSTER_OPENED"
end

local function push_showcase(c, label, now)
  local item = {card = c, label = label or card_set_label(c)}
  if is_in_pack_state() then
    _pack_gained_q[#_pack_gained_q + 1] = item  -- defer until pack closes
  else
    _joker_showcase_q[#_joker_showcase_q + 1] = item
  end
end

local function pull_showcase(now)
  if not _joker_showcase and #_joker_showcase_q > 0 then
    local item = table.remove(_joker_showcase_q, 1)
    _joker_showcase = {card = item.card, label = item.label, started = now or 0}
  end
end

local function update_joker_showcase(now)
  if not G then _known_joker_refs = nil; _known_cons_refs = nil; return end

  -- jokers
  if G.jokers and G.jokers.cards then
    local cur = {}
    for _, c in ipairs(G.jokers.cards) do cur[c] = true end
    if _known_joker_refs then
      for _, c in ipairs(G.jokers.cards) do
        if not _known_joker_refs[c] then push_showcase(c, "NEW JOKER", now) end
      end
    end
    _known_joker_refs = cur
  else
    _known_joker_refs = nil
  end

  -- consumables (planets, tarots, spectrals)
  if G.consumeables and G.consumeables.cards then
    local cur = {}
    for _, c in ipairs(G.consumeables.cards) do cur[c] = true end
    if _known_cons_refs then
      for _, c in ipairs(G.consumeables.cards) do
        if not _known_cons_refs[c] then push_showcase(c, nil, now) end
      end
    end
    _known_cons_refs = cur
  else
    _known_cons_refs = nil
  end

  -- flush cards deferred during pack state once pack is closed
  if not is_in_pack_state() and #_pack_gained_q > 0 then
    for _, item in ipairs(_pack_gained_q) do
      _joker_showcase_q[#_joker_showcase_q + 1] = item
    end
    _pack_gained_q = {}
  end

  pull_showcase(now)
end

local function joker_template_ability(c)
  local center = c and c.config and c.config.center or {}
  local key = center.key
  if not (key and G and G.P_CENTERS and G.P_CENTERS[key]) then return {} end
  return G.P_CENTERS[key].ability or {}
end

local function joker_fx(c)
  local ab = c and c.ability or {}
  local tb = joker_template_ability(c)
  if ab.x_mult and ab.x_mult > 1 then
    if ab.x_mult == (tb.x_mult or ab.x_mult) then return "x" .. ab.x_mult end
  end
  if ab.h_mult and ab.h_mult > 0 then
    local base = tb.h_mult or 0
    if ab.h_mult == base then return "+" .. ab.h_mult .. " Mult" end
  end
  if ab.h_mod and ab.h_mod > 0 then
    local base = tb.h_mod or 0
    if ab.h_mod == base then return "+" .. ab.h_mod .. " Chips" end
  end
  if ab.t_mult and ab.t_mult > 0 then
    local base = tb.t_mult or 0
    if ab.t_mult == base then return "+" .. ab.t_mult .. " Mult" end
  end
  if ab.t_chips and ab.t_chips > 0 then
    local base = tb.t_chips or 0
    if ab.t_chips == base then return "+" .. ab.t_chips .. " Chips" end
  end
  if ab.d_mult and ab.d_mult > 0 then
    local base = tb.d_mult or 0
    if ab.d_mult == base then return "+" .. ab.d_mult .. " Mult" end
  end
  if ab.extra and type(ab.extra) == "table" then
    local te = type(tb.extra) == "table" and tb.extra or {}
    if ab.extra.x_mult and ab.extra.x_mult > 1 and ab.extra.x_mult == (te.x_mult or ab.extra.x_mult) then
      return "x" .. ab.extra.x_mult
    end
    if ab.extra.mult and ab.extra.mult > 0 and ab.extra.mult == (te.mult or ab.extra.mult) then
      return "+" .. ab.extra.mult .. " Mult"
    end
    if ab.extra.chips and ab.extra.chips > 0 and ab.extra.chips == (te.chips or ab.extra.chips) then
      return "+" .. ab.extra.chips .. " Chips"
    end
    if ab.extra.money and ab.extra.money > 0 and ab.extra.money == (te.money or ab.extra.money) then
      return "+$" .. ab.extra.money
    end
  end
  return ""
end

local function build_panel_rows(sn, panel_rows, shop_rows, pack_rows, colors, pg)
  local GOLD, CYAN, GREEN, MONEY, RED, WHITE, DIM, ORANGE =
    colors.D_GOLD, colors.D_CYAN, colors.D_GREEN, colors.D_MONEY,
    colors.D_RED, colors.D_WHITE, colors.D_DIM, colors.D_ORANGE

  local function hdr(color, text)      panel_rows[#panel_rows+1] = {color, text, true, 0} end
  local function row(color, text)      panel_rows[#panel_rows+1] = {color, text, false, 8} end
  local function sub(color, text)      panel_rows[#panel_rows+1] = {color, text, false, 14} end
  local function desc_row(color, text) panel_rows[#panel_rows+1] = {color, text, false, 16, false, true, nil, true} end
  local function sep()                 panel_rows[#panel_rows+1] = {nil, nil, false, 0, true} end
  local function card_row(color, text, card) panel_rows[#panel_rows+1] = {color, text, false, 8, false, false, card} end
  local function desc_cycle(jokers)
    if #jokers > 0 then
      local r = {}; r[10] = jokers; panel_rows[#panel_rows+1] = r
    end
  end

  if G.GAME then
    local money = G.GAME.dollars or 0
    local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
    local round = G.GAME.round or "?"
    hdr(MONEY, string.format("$%d", money))
    row(CYAN, string.format("Ante %s  Round %s", tostring(ante), tostring(round)))
    local seed = G.GAME.pseudorandom and G.GAME.pseudorandom.seed
    if not seed and G.NEURO.seed_pasted then seed = G.NEURO.seed_pasted end
    if seed then
      row(DIM, "Seed: " .. tostring(seed))
    end
    local _back_obj = G.GAME.selected_back or G.GAME.back
    local deck_name = nil
    if _back_obj then
      local bkey = _back_obj.name
      if bkey and G.P_CENTERS and G.P_CENTERS[bkey] then
        local pc = G.P_CENTERS[bkey]
        if pc.loc_txt and type(pc.loc_txt.name) == "string" and pc.loc_txt.name ~= "" then
          deck_name = pc.loc_txt.name
        elseif type(pc.name) == "string" and pc.name ~= "" then
          deck_name = pc.name
        end
      end
      if not deck_name then
        deck_name = _back_obj.name or _back_obj.loc_name
      end
      if type(deck_name) == "string" and deck_name:find("_") and not deck_name:find(" ") then
        deck_name = Utils.humanize_identifier(deck_name)
      end
    end
    if deck_name and deck_name ~= "" then
      row(DIM, "Deck: " .. tostring(deck_name))
    end
  end

  if sn == "SELECTING_HAND" and G.GAME and G.GAME.blind then
    sep()
    local target = G.GAME.blind.chips or 0
    local blind_mult = G.GAME.blind.mult or 1
    local current_score = G.GAME.chips or 0
    local remaining = math.max(0, target - current_score)
    local hands = G.GAME.current_round and G.GAME.current_round.hands_left or 0
    local discards = G.GAME.current_round and G.GAME.current_round.discards_left or 0
    hdr(RED, string.format("Target: %s", tostring(target)))
    row(DIM, string.format("Blind x%s  Score %s  Rem %s", tostring(blind_mult), tostring(current_score), tostring(remaining)))
    row(WHITE, string.format("Hands: %d   Discards: %d", hands, discards))

    local debuff_text = ""
    local blind = G.GAME.blind
    if blind and type(blind.get_loc_debuff_text) == "function" then
      local ok, txt = pcall(blind.get_loc_debuff_text, blind)
      if ok and type(txt) == "string" then debuff_text = txt end
    end
    if debuff_text == "" and blind and type(blind.loc_debuff_text) == "string" then
      debuff_text = blind.loc_debuff_text
    end
    if debuff_text and debuff_text ~= "" then
      sub(RED, "Debuff: " .. tostring(debuff_text))
    end
  end

  if G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
    sep()
    local jlimit = (G.jokers and G.jokers.config and G.jokers.config.card_limit)
      or (G.GAME and G.GAME.joker_limit) or 5
    hdr(GOLD, string.format("Jokers  %d/%d", #G.jokers.cards, jlimit))
    desc_cycle(G.jokers.cards)
  end

  if G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 then
    sep()
    hdr(CYAN, "Consumables")
    for _, c in ipairs(G.consumeables.cards) do
      local n = card_display_name(c)
      card_row(rarity_color(c) or WHITE, n, c)
      local desc = card_description(c)
      if (not desc or desc == "") and c and c.config and c.config.center then
        desc = Utils.safe_description(c.config.center.loc_txt, c)
      end
      if desc then
        desc_row(DIM, desc)
      end
    end
  end

  if sn == "SHOP" then
    local function shdr(color, text)      shop_rows[#shop_rows+1] = {color, text, true, 0} end
    local function ssub(color, text)      shop_rows[#shop_rows+1] = {color, text, false, 14} end
    local function sdesc(color, text)     shop_rows[#shop_rows+1] = {color, text, false, 16, false, true, nil, true} end
    local function ssep()                 shop_rows[#shop_rows+1] = {nil, nil, false, 0, true} end
    local function scard(color, text, card) shop_rows[#shop_rows+1] = {color, text, false, 8, false, false, card} end
    local shop_areas = {
      {area = G.shop_jokers, tag = "Jokers"},
      {area = G.shop_vouchers, tag = "Vouchers"},
      {area = G.shop_booster, tag = "Packs"},
    }
    for _, sa in ipairs(shop_areas) do
      if sa.area and sa.area.cards and #sa.area.cards > 0 then
        ssep()
        shdr(pg, "Shop: " .. sa.tag)
        for i, c in ipairs(sa.area.cards) do
          local n = card_display_name(c)
          local cost = c.cost or 0
          local money = G.GAME and G.GAME.dollars or 0
          local afford = cost <= money
          local fx = ""
          local fx_from_desc = false
          local fx_is_static_joker = false
          if sa.tag == "Jokers" then
            local jfx = joker_fx(c)
            if jfx ~= "" then fx = jfx; fx_is_static_joker = true end
          end
          scard(afford and GREEN or DIM, string.format("$%d  %s", cost, n), c)
          if fx == "" then
            local short_desc = card_description(c)
            if (not short_desc or short_desc == "") and c and c.config and c.config.center then
              short_desc = Utils.safe_description(c.config.center.loc_txt, c, 140)
            end
            if short_desc and short_desc ~= "" then fx = short_desc; fx_from_desc = true end
          end
          if fx ~= "" then ssub(ORANGE, fx) end
          if not fx_from_desc and not fx_is_static_joker then
            local desc = card_description(c)
            if (not desc or desc == "") and c and c.config and c.config.center then
              desc = Utils.safe_description(c.config.center.loc_txt, c)
            end
            if desc then sdesc(DIM, desc) end
          end
        end
      end
    end
  end

  if sn == "BLIND_SELECT" and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    sep()
    hdr(pg, "Choose Blind")
    local choices = G.GAME.round_resets.blind_choices
    for _, btype in ipairs({"Small", "Big", "Boss"}) do
      local key = choices[btype]
      if key and G.P_BLINDS and G.P_BLINDS[key] then
        local b = G.P_BLINDS[key]
        local bname = b.name or key
        if b.mult then
          row(btype == "Boss" and RED or WHITE, btype .. ": " .. bname)
          sub(DIM, "x" .. b.mult .. " chips")
        else
          row(btype == "Boss" and RED or WHITE, btype .. ": " .. bname)
        end
      end
    end
  end

  local _bp2 = G.pack_cards or G.booster_pack
  if (sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED") and _bp2 and _bp2.cards and #_bp2.cards > 0 then
    local pack_picks = G.GAME and G.GAME.pack_choices or 0
    local pack_count = #_bp2.cards
    pack_rows.title = string.format("Pack Contents  (%d/%d pick)", math.max(0, math.floor(pack_picks)), pack_count)
    pack_rows.picks_left = pack_picks
    pack_rows.total = pack_count
    pack_rows.pg = pg
    pack_rows.cards = {}
    for i, c in ipairs(_bp2.cards) do
      local n = card_display_name(c)
      if n == "?" and c.base then n = c.base.value .. " " .. (c.base.suit or "") end
      local rc = rarity_color(c) or WHITE
      local desc = card_description(c)
      if (not desc or desc == "") and c and c.config and c.config.center then
        desc = Utils.safe_description(c.config.center.loc_txt, c)
      end
      if (not desc or desc == "") and c and c.ability then
        desc = Utils.safe_description(c.ability.loc_txt, c)
      end
      pack_rows.cards[#pack_rows.cards + 1] = {
        card = c,
        name = n,
        desc = desc or "",
        rc = rc,
        index = i,
      }
    end
  end
end

local function draw_neuro_indicator()
  if not G then return end
  trace("TRACE-IND: enter, G exists")

  local now = (G.TIMERS and G.TIMERS.REAL) or 0
  trace("TRACE-IND: now=" .. tostring(now))
  local pulse = 0.5 + 0.5 * math.sin(now * 2.7)
  trace("TRACE-IND: getWidth")
  local sw = love.graphics.getWidth()
  trace("TRACE-IND: getHeight")
  local sh = love.graphics.getHeight()
  trace("TRACE-IND: get_panel_fonts")
  local panel_font, panel_font_small = get_panel_fonts()
  trace("TRACE-IND: getFont")
  local font = panel_font or love.graphics.getFont()
  if not font then trace("TRACE-IND: no font, bail") return end
  local prev_font = love.graphics.getFont()
  if panel_font then love.graphics.setFont(panel_font) end
  trace("TRACE-IND: font ready, G.NEURO=" .. tostring(G.NEURO ~= nil))

  local draw_buy_panel
  if G.NEURO then
    trace("IND: G.NEURO block entered")
    local logo = get_neuro_logo()
    trace("IND: logo=" .. tostring(logo ~= nil))
    local state_name = G.NEURO.force_state or G.NEURO.state or ""
    trace("IND: state=" .. tostring(state_name))
    local _pal = pal()
    local persona_name = _pal.NAME
    trace("IND: persona=" .. tostring(persona_name))
    local state_label
    if G.NEURO.force_inflight or Staging.is_busy() then
      state_label = STATE_LABELS[state_name] or "THINKING"
    else
      state_label = STATE_LABELS[state_name] or "IDLE"
    end
    trace("IND: state_label=" .. tostring(state_label))
    local text_h = font:getHeight()
    trace("IND: text_h=" .. tostring(text_h))
    local action_text = Staging.get_overlay_text()
    trace("IND: action_text=" .. tostring(action_text))
    local p = _pal.PRIMARY
    local pg = _pal.GLOW
    local bg = _pal.BG
    auto_queue_pack_browse(now)
    update_buy_showcase(now)
    local trunc
    local wrapped_lines

    draw_buy_panel = function()
      if not _buy_showcase then return end
      local area_tag = tostring(_buy_showcase.area or "shop")
      if area_tag == "booster_choice" or area_tag == "pack_browse" then return end

      local orange = _pal.D_ORANGE
      local small_h = panel_font_small and panel_font_small:getHeight() or font:getHeight()

      local elapsed = now - (_buy_showcase.started or now)
      local a = 1
      if elapsed < BUY_SHOWCASE_FADE_IN then
        a = math.max(0, math.min(1, elapsed / BUY_SHOWCASE_FADE_IN))
      elseif (not _buy_showcase.winner_at) and elapsed > (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT) then
        a = math.max(0, (BUY_SHOWCASE_DURATION - elapsed) / BUY_SHOWCASE_FADE_OUT)
      end
      if a <= 0 then return end

      local bx, by, bw, bh = 10, 20, 420, 230
      local title = "SHOP BUY"
      local subtitle_tag = area_tag
      if area_tag == "booster_pick" then
        title = "PACK PICK"
        subtitle_tag = "booster pack"
      elseif area_tag == "joker_gain" then
        title = "NEW JOKER"
        subtitle_tag = "gained"
        bh = 260
      elseif area_tag == "shop_jokers" then
        title = "SHOP BUY"
        subtitle_tag = "joker"
      elseif area_tag == "shop_vouchers" then
        title = "SHOP BUY"
        subtitle_tag = "voucher"
      elseif area_tag == "shop_booster" then
        title = "SHOP BUY"
        subtitle_tag = "pack"
      elseif area_tag == "shop" or area_tag == "event" then
        title = "SHOP BUY"
        subtitle_tag = "shop"
      end
      local shown_cost = tonumber(_buy_showcase.cost) or 0
      local subtitle = (shown_cost > 0)
        and string.format("%s  $%d", subtitle_tag, shown_cost)
        or tostring(subtitle_tag)

      -- Slide in from the left (tied to alpha so it glides with the fade)
      local slide_x = math.floor(-(bw + bx + 10) * (1 - a) + 0.5)
      love.graphics.push()
      love.graphics.translate(slide_x, 0)

      -- drop shadow
      love.graphics.setColor(0, 0, 0, 0.28 * a)
      love.graphics.rectangle("fill", bx + 5, by + 5, bw, bh, 10, 10)

      love.graphics.setColor(bg[1], bg[2], bg[3], 0.95 * a)
      love.graphics.rectangle("fill", bx, by, bw, bh, 10, 10)
      love.graphics.setColor(p[1], p[2], p[3], (0.08) * a)
      love.graphics.rectangle("fill", bx + 1, by + 1, bw - 2, bh - 2, 10, 10)
      love.graphics.setColor(p[1], p[2], p[3], (0.65 + 0.25 * pulse) * a)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", bx, by, bw, bh, 10, 10)
      love.graphics.setColor(pg[1], pg[2], pg[3], (0.12 + 0.06 * pulse) * a)
      love.graphics.setLineWidth(4)
      love.graphics.rectangle("line", bx - 2, by - 2, bw + 4, bh + 4, 12, 12)

      love.graphics.setColor(p[1], p[2], p[3], (0.55 + 0.15 * pulse) * a)
      love.graphics.rectangle("fill", bx + 3, by + 3, bw - 6, 36, 7, 7)

      love.graphics.setColor(1, 1, 1, 0.97 * a)
      love.graphics.print(title, bx + 12, by + 8)
      if panel_font_small then love.graphics.setFont(panel_font_small) end
      local can_afford = shown_cost <= 0 or (G and G.GAME and (G.GAME.dollars or 0) >= shown_cost)
      if shown_cost > 0 then
        love.graphics.setColor(can_afford and 0.35 or 1.0, can_afford and 1.0 or 0.25, 0.10, 0.92 * a)
      else
        love.graphics.setColor(1, 1, 1, 0.80 * a)
      end
      love.graphics.print(subtitle, bx + 12, by + 23)
      if panel_font_small then love.graphics.setFont(font) end
      -- affordability bar (single-card mode only, lives in gap between header and sprite)
      if shown_cost > 0 then
        local gold_now = G and G.GAME and (G.GAME.dollars or 0) or 0
        local frac = math.min(1.0, gold_now / math.max(1, shown_cost))
        love.graphics.setColor(p[1], p[2], p[3], 0.15 * a)
        love.graphics.rectangle("fill", bx + 3, by + 40, bw - 6, 3, 1, 1)
        love.graphics.setColor(can_afford and 0.30 or 0.95, can_afford and 0.95 or 0.25, 0.10, (0.78 + 0.15 * pulse) * a)
        love.graphics.rectangle("fill", bx + 3, by + 40, math.max(2, (bw - 6) * frac), 3, 1, 1)
      end

      local card = _buy_showcase.card
      local sprite_h = 110
      local sprite_x = bx + 12
      local sprite_y = by + 46
      local sprite_w = draw_card_mini(card, sprite_x, sprite_y, sprite_h)
      if sprite_w <= 0 then sprite_w = sprite_h * 0.75 end

      -- rarity tint on card frame
      local cr = card and rarity_color(card)
      if cr and type(cr) == "table" then
        love.graphics.setColor(cr[1], cr[2], cr[3], 0.12 * a)
        love.graphics.rectangle("fill", sprite_x - 3, sprite_y - 3, sprite_w + 6, sprite_h + 6, 5, 5)
        love.graphics.setColor(cr[1], cr[2], cr[3], (0.35 + 0.10 * pulse) * a)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", sprite_x - 2, sprite_y - 2, sprite_w + 4, sprite_h + 4, 4, 4)
        love.graphics.setLineWidth(1)
        -- thin left stripe on panel body matching rarity
        love.graphics.setColor(cr[1], cr[2], cr[3], (0.55 + 0.18 * pulse) * a)
        love.graphics.rectangle("fill", bx + 3, by + 46, 3, sprite_h + 6, 2, 2)
      end

      -- inspect shimmer — slow sweep across card, shows Neuro is examining it
      -- Drive from elapsed so shimmer fires ~0.6s into panel life (guaranteed visible)
      local shimmer_t = math.fmod(elapsed + 0.4, 2.5)
      if shimmer_t < 1.0 then
        local sx_sh = sprite_x + shimmer_t * (sprite_w + 18) - 9
        local sl = math.max(sprite_x, sx_sh - 5)
        local sr = math.min(sprite_x + sprite_w, sx_sh + 11)
        if sr > sl then
          love.graphics.setColor(1, 1, 1, math.sin(shimmer_t * math.pi) * 0.26 * a)
          love.graphics.rectangle("fill", sl, sprite_y, sr - sl, sprite_h)
        end
      end

      local tx = sprite_x + sprite_w + 10
      local tw = bw - (tx - bx) - 12
      local is_joker_area = (area_tag == "joker_gain" or area_tag == "shop_jokers")

      local name_line = trunc(_buy_showcase.name or "Purchase", tw)
      love.graphics.setColor(1, 1, 1, 0.98 * a)
      love.graphics.print(name_line, tx, sprite_y + 2)
      local bs_ed = card and card_edition_tag(card) or ""
      if bs_ed ~= "" then
        draw_animated_edition(bs_ed, tx + font:getWidth(name_line), sprite_y + 2, a, font, now, pk)
      end
      local ty = sprite_y + 20

      -- joker fx (all joker areas, not just joker_gain)
      local fx = (is_joker_area and card) and joker_fx(card) or ""
      if fx ~= "" then
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        love.graphics.setColor(pg[1], pg[2], pg[3], 0.95 * a)
        love.graphics.print(trunc(fx, tw, panel_font_small), tx, ty)
        if panel_font_small then love.graphics.setFont(font) end
        ty = ty + small_h + 2
      end

      -- sell value badge (jokers only)
      local sell_v = is_joker_area and card and tonumber(card.sell_cost)
      if sell_v and sell_v > 0 then
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        love.graphics.setColor(0.40, 0.95, 0.45, 0.82 * a)
        love.graphics.print("sell $" .. tostring(sell_v), tx, ty)
        if panel_font_small then love.graphics.setFont(font) end
        ty = ty + small_h + 2
      end

      -- description
      local desc = tostring(_buy_showcase.desc or "")
      local desc_lines = wrapped_lines(desc, tw, panel_font_small or font)
      local max_lines = 6
      if #desc_lines > max_lines then
        desc_lines[max_lines] = trunc(desc_lines[max_lines], tw - 8, panel_font_small or font) .. " ..."
      end
      if panel_font_small then love.graphics.setFont(panel_font_small) end
      love.graphics.setColor(orange[1], orange[2], orange[3], 0.92 * a)
      for i = 1, math.min(#desc_lines, max_lines) do
        love.graphics.print(desc_lines[i], tx, ty)
        ty = ty + small_h + 1
      end
      if panel_font_small then love.graphics.setFont(font) end

      -- countdown timer bar (shrinks right as panel ages)
      local timer_frac = math.max(0, 1.0 - elapsed / BUY_SHOWCASE_DURATION)
      love.graphics.setColor(p[1], p[2], p[3], 0.20 * a)
      love.graphics.rectangle("fill", bx + 6, by + bh - 9, bw - 12, 5, 2, 2)
      love.graphics.setColor(pg[1], pg[2], pg[3], (0.80 + 0.15 * pulse) * a)
      love.graphics.rectangle("fill", bx + 6, by + bh - 9, math.max(4, (bw - 12) * timer_frac), 5, 2, 2)

      -- PURCHASED! flash during fade-out
      local in_fade_out = (not _buy_showcase.winner_at)
        and elapsed > (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT)
      if in_fade_out then
        local ft = (elapsed - (BUY_SHOWCASE_DURATION - BUY_SHOWCASE_FADE_OUT)) / BUY_SHOWCASE_FADE_OUT
        local fa = math.sin(ft * math.pi)
        love.graphics.setColor(1, 0.88, 0.10, fa * 0.42)
        love.graphics.rectangle("fill", sprite_x - 2, sprite_y - 2, sprite_w + 4, sprite_h + 4, 5, 5)
        local bought_txt = "BOUGHT!"
        local btw = font:getWidth(bought_txt)
        local bty = sprite_y + math.floor(sprite_h / 2) - math.floor(font:getHeight() / 2)
        love.graphics.setColor(0, 0, 0, fa * 0.50)
        love.graphics.print(bought_txt, sprite_x + math.max(0, math.floor((sprite_w - btw) / 2)) + 1, bty + 1)
        love.graphics.setColor(1, 1, 0.20, fa * 0.95)
        love.graphics.print(bought_txt, sprite_x + math.max(0, math.floor((sprite_w - btw) / 2)), bty)
      end

      love.graphics.pop()
    end
    trace("IND: colors resolved")
    local logo_h = 20
    local logo_w = 0
    local logo_scale = 1
    if logo then
      logo_scale = logo_h / logo:getHeight()
      logo_w = logo:getWidth() * logo_scale
    end
    trace("IND: logo dims done, building panel_rows")

    local panel_rows = {}
    local sn = G.NEURO.state or ""

    trunc = function(s, max_w, f)
      if not s then return "" end
      f = f or font
      if not f or not max_w or max_w <= 0 then return s end
      local ok, w = pcall(f.getWidth, f, s)
      if not ok then return s end
      if w <= max_w then return s end
      while w > max_w and #s > 3 do
        s = s:sub(1, #s - 3) .. ".."
        ok, w = pcall(f.getWidth, f, s)
        if not ok then return s end
      end
      return s
    end

    wrapped_lines = function(text, max_w, f)
      local out = {}
      if not text or text == "" then return out end
      f = f or font
      if not f or not max_w or max_w <= 0 then
        out[1] = tostring(text)
        return out
      end
      local fid = (f == panel_font_small) and "s" or "n"
      local ck = fid .. tostring(max_w) .. "\0" .. tostring(text)
      local cached = _wrap_cache[ck]
      if cached then return cached end
      if _wrap_cache_size >= 400 then
        _wrap_cache = {}
        _wrap_cache_size = 0
      end
      local ok, _, lines = pcall(function()
        local width, wrapped = f:getWrap(tostring(text), max_w)
        return width, wrapped
      end)
      if ok and type(lines) == "table" and #lines > 0 then
        for i = 1, #lines do
          out[#out + 1] = lines[i]
        end
      else
        out[1] = tostring(text)
      end
      _wrap_cache[ck] = out
      _wrap_cache_size = _wrap_cache_size + 1
      return out
    end

    local ORANGE  = _pal.D_ORANGE

    local shop_rows = {}
    local pack_rows = {}
    build_panel_rows(sn, panel_rows, shop_rows, pack_rows, _pal, pg)

    trace("IND: panel_rows built, count=" .. tostring(#panel_rows) .. " starting panel draw")
    local p_w = 320
    local p_pad_x = 10
    local p_x = sw - p_w - 8

    local jokers_on_screen = G.jokers and G.jokers.cards and #G.jokers.cards > 0
        and state_name ~= "SPLASH" and state_name ~= "MENU"
        and state_name ~= "GAME_OVER" and state_name ~= "RUN_SETUP"
    local p_y_target = math.max(PANEL_Y_DEFAULT, math.floor(sh * 0.30))
    if jokers_on_screen then
      p_y_target = math.max(PANEL_Y_DEFAULT, math.floor(sh * 0.38))
    end
    local frame_time = now
    local dt = 0
    if _panel_y_last_time > 0 and frame_time > _panel_y_last_time then
      dt = math.min(frame_time - _panel_y_last_time, 0.1)
    end
    _panel_y_last_time = frame_time
    if dt > 0 then
      local diff = p_y_target - _panel_y_current
      if math.abs(diff) < 0.5 then
        _panel_y_current = p_y_target
      else
        _panel_y_current = _panel_y_current + diff * math.min(1, PANEL_Y_LERP_SPEED * dt)
      end
      local booster_active = _buy_showcase and (_buy_showcase.area == "pack_browse" or _buy_showcase.area == "booster_choice")
      local rp_target = booster_active and 1 or 0
      local rp_diff = rp_target - _right_panel_slide_frac
      if math.abs(rp_diff) < 0.005 then
        _right_panel_slide_frac = rp_target
      else
        _right_panel_slide_frac = _right_panel_slide_frac + rp_diff * math.min(1, 8.0 * dt)
      end
      local pack_state_active = state_name:find("_PACK") ~= nil or state_name == "SMODS_BOOSTER_OPENED"
      local lp_target = (booster_active or pack_state_active) and 1 or 0
      local lp_diff = lp_target - _left_panel_slide_frac
      if math.abs(lp_diff) < 0.005 then
        _left_panel_slide_frac = lp_target
      else
        _left_panel_slide_frac = _left_panel_slide_frac + lp_diff * math.min(1, 8.0 * dt)
      end
    end
    local p_y = _panel_y_current
    local line_h = text_h + 4
    local small_text_h = panel_font_small and panel_font_small:getHeight() or text_h
    local small_line_h = small_text_h + 2
    local card_line_h = 32
    local sep_h = 8
    local content_w = p_w - p_pad_x * 2

    -- per-type showcase palette: returns sp (fill/border), sg (glow/label)
    local function showcase_type_colors(label, card)
      local set = card and card.config and card.config.center and card.config.center.set or ""
      local key = card and card.config and card.config.center and card.config.center.key or ""
      local slo = set:lower(); local klo = key:lower()
      local is_evil = (pk == "evil")

      local sp, sg
      -- Neuratro custom cards
      if slo:find("neuro") or klo:find("neuro") or klo:find("j_n_") then
        sp = {0.50, 0.08, 0.15}; sg = {0.95, 0.35, 0.55}
      elseif label == "NEW PLANET" or slo == "planet" then
        sp = {0.10, 0.20, 0.55}; sg = {0.40, 0.68, 1.00}
      elseif label == "NEW TAROT" or slo == "tarot" then
        sp = {0.32, 0.06, 0.48}; sg = {0.78, 0.38, 1.00}
      elseif label == "NEW SPECTRAL" or slo == "spectral" then
        sp = {0.06, 0.20, 0.32}; sg = {0.45, 0.82, 1.00}
      elseif label == "VOUCHER" or slo == "voucher" then
        sp = {0.32, 0.22, 0.02}; sg = {1.00, 0.82, 0.18}
      else
        sp = p; sg = pg  -- palette default (joker or unknown)
      end

      if is_evil then
        -- Evil persona: darken fills toward blood-red, replace glow with crimson
        sp = {sp[1] * 0.5 + 0.30, sp[2] * 0.2, sp[3] * 0.2}
        sg = {1.00, 0.18, 0.22}  -- Evil crimson glow for all types
      end

      return sp, sg
    end

    -- word-level colored description printer
    local function draw_colored_desc(text, x, y, alpha, f)
      local cx = x
      local i = 1
      while i <= #text do
        local j = i
        while j <= #text and text:sub(j,j) == " " do j = j + 1 end
        if j > i then cx = cx + f:getWidth(string.rep(" ", j - i)); i = j end
        j = i
        while j <= #text and text:sub(j,j) ~= " " do j = j + 1 end
        if j > i then
          local word = text:sub(i, j - 1)
          local wu = word:upper()
          local r, g, b
          if wu:find("MULT") then
            r,g,b = _pal.D_RED[1],_pal.D_RED[2],_pal.D_RED[3]
          elseif wu:find("CHIP") then
            r,g,b = _pal.D_CYAN[1],_pal.D_CYAN[2],_pal.D_CYAN[3]
          elseif word:match("^%$") then
            r,g,b = _pal.D_MONEY[1],_pal.D_MONEY[2],_pal.D_MONEY[3]
          elseif word:match("^[Xx]%d") then
            r,g,b = _pal.D_RED[1],_pal.D_RED[2],_pal.D_RED[3]
          elseif word:match("^%+%d") then
            r,g,b = _pal.D_GREEN[1],_pal.D_GREEN[2],_pal.D_GREEN[3]
          else
            r,g,b = _pal.D_ORANGE[1],_pal.D_ORANGE[2],_pal.D_ORANGE[3]
          end
          love.graphics.setColor(0, 0, 0, 0.20 * alpha)
          love.graphics.print(word, cx + 1, y + 1)
          love.graphics.setColor(r, g, b, 0.88 * alpha)
          love.graphics.print(word, cx, y)
          cx = cx + f:getWidth(word)
          i = j
        elseif i == j then i = i + 1 end
      end
    end

    local title_h = 42
    local action_row_h = action_text and (text_h + 10) or 0
    local function row_h(r)
      if r[5] then return sep_h
      elseif r[12] then return 88 + small_line_h + 8
      elseif r[10] then return card_line_h + small_line_h * 3 + 18
      elseif r[6] then
        if r[8] then
          local indent = r[4] or 0
          local lines = wrapped_lines(r[2] or "", math.max(20, content_w - indent), panel_font_small or font)
          local count = #lines > 0 and #lines or 1
          return (small_line_h * count) + 2
        end
        return small_line_h
      elseif r[7] then return card_line_h
      else return line_h end
    end

    local data_h = 0
    if #panel_rows > 0 then
      data_h = 8
      for _, r in ipairs(panel_rows) do data_h = data_h + row_h(r) end
    end

    local pk = G.NEURO.persona or NEURO_PERSONA
    local quips = PANEL_QUIPS[pk] or PANEL_QUIPS.neuro
    local quip = quips[1]
    local quip_display = ""
    local footer_emote_name = pick_footer_emote(pk, sn, now)
    local footer_emote = get_panel_emote(footer_emote_name)

    local showcase_card = nil
    local showcase_name = nil
    local showcase_label = nil
    local showcase_fx = nil
    local showcase_desc = nil
    local showcase_alpha = 0
    local showcase_slide = 0
    if _joker_showcase and _joker_showcase.card then
      local elapsed = now - (_joker_showcase.started or now)
      -- if a pack is open, fast-dismiss the joker showcase so it doesn't overlap
      local pack_is_open = (sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED")
        and (pack_rows.cards and #pack_rows.cards > 0)
      local eff_duration = JOKER_SHOWCASE_DURATION
      if pack_is_open and elapsed > JOKER_SHOWCASE_FADE_IN then
        -- force into fade-out: cap remaining time to 0.4s
        local max_remaining = 0.40
        if (eff_duration - elapsed) > max_remaining then
          _joker_showcase.started = now - (eff_duration - max_remaining)
          elapsed = eff_duration - max_remaining
        end
      end
      if elapsed >= eff_duration then
        _joker_showcase = nil
        if #_joker_showcase_q > 0 then
          local _nxt = table.remove(_joker_showcase_q, 1)
          _joker_showcase = {card = _nxt.card, label = _nxt.label, started = now}
        end
      else
        showcase_card  = _joker_showcase.card
        showcase_label = _joker_showcase.label or card_set_label(showcase_card)
        showcase_name  = card_display_name(showcase_card)
        showcase_fx    = joker_fx(showcase_card)
        showcase_desc  = card_description(showcase_card)
        if (not showcase_desc or showcase_desc == "") and showcase_card and showcase_card.config and showcase_card.config.center then
          local ok, d = pcall(Utils.safe_description, showcase_card.config.center.loc_txt, showcase_card)
          if ok and type(d) == "string" then showcase_desc = d end
        end
        showcase_alpha = 1
        if elapsed < JOKER_SHOWCASE_FADE_IN then
          showcase_alpha = math.max(0, math.min(1, elapsed / JOKER_SHOWCASE_FADE_IN))
        elseif elapsed > (eff_duration - JOKER_SHOWCASE_FADE_OUT) then
          showcase_alpha = math.max(0, (eff_duration - elapsed) / JOKER_SHOWCASE_FADE_OUT)
        end
        showcase_slide = (1 - showcase_alpha) * 10
      end
    end

    local footer_slot = math.floor(now / FOOTER_SLOT_DURATION)
    local footer_is_emote = footer_emote and (footer_slot % FOOTER_EMOTE_EVERY == (FOOTER_EMOTE_EVERY - 1))
    local footer_h = (quip or footer_emote) and 80 or 0
    local quip_slot_count = footer_slot - math.floor(footer_slot / FOOTER_EMOTE_EVERY)
    local quip_idx = quip_slot_count % #quips + 1
    quip = quips[quip_idx]
    if NeuroFilter and NeuroFilter.sanitize and quip then
      quip = NeuroFilter.sanitize(quip)
    end
    quip_display = pk == "evil" and ("// " .. quip .. " //") or ("~ " .. quip .. " ~")

    local total_h = title_h + action_row_h + data_h + footer_h
    local max_h = math.min(sh - p_y - 10, math.floor(sh * 0.58))
    if total_h > max_h then total_h = max_h end
    if _panel_h_current <= 0 then _panel_h_current = total_h end
    local ph_diff = total_h - _panel_h_current
    if math.abs(ph_diff) < 0.5 or ph_diff > 0 then
      _panel_h_current = total_h          -- snap instantly on grow
    else
      _panel_h_current = _panel_h_current + ph_diff * math.min(1, PANEL_H_LERP_SPEED * dt)
    end
    total_h = math.floor(_panel_h_current + 0.5)


    if #shop_rows > 0 then
      local lp_w = 380
      local lp_x = 8
      local lp_y = p_y
      local lp_pad_x = 10
      local lp_content_w = lp_w - lp_pad_x * 2

      local function lp_row_h(r)
        if r[5] then return sep_h
        elseif r[6] then
          if r[8] then
            local indent = r[4] or 0
            local lines = wrapped_lines(r[2] or "", math.max(20, lp_content_w - indent), panel_font_small or font)
            local count = #lines > 0 and #lines or 1
            return (small_line_h * count) + 2
          end
          return small_line_h
        elseif r[7] then return card_line_h
        else return line_h end
      end
      local lp_data_h = 8
      for _, r in ipairs(shop_rows) do lp_data_h = lp_data_h + lp_row_h(r) end
      local lp_title_h = 42
      local lp_total_h = lp_title_h + lp_data_h
      local lp_max_h = math.min(sh - lp_y - 10, math.floor(sh * 0.72))
      if lp_total_h > lp_max_h then lp_total_h = lp_max_h end

      if _left_panel_slide_frac > 0 then
        love.graphics.push()
        love.graphics.translate(-math.floor((lp_w + 20) * _left_panel_slide_frac + 0.5), 0)
      end

      love.graphics.setColor(bg[1], bg[2], bg[3], 0.96)
      love.graphics.rectangle("fill", lp_x, lp_y, lp_w, lp_total_h, 10, 10)
      love.graphics.setColor(p[1], p[2], p[3], 0.05)
      love.graphics.rectangle("fill", lp_x + 1, lp_y + 1, lp_w - 2, lp_total_h - 2, 10, 10)

      love.graphics.setColor(pg[1], pg[2], pg[3], 0.06 + 0.04 * pulse)
      love.graphics.setLineWidth(6)
      love.graphics.rectangle("line", lp_x - 3, lp_y - 3, lp_w + 6, lp_total_h + 6, 13, 13)
      love.graphics.setColor(p[1], p[2], p[3], 0.10 + 0.06 * pulse)
      love.graphics.setLineWidth(4)
      love.graphics.rectangle("line", lp_x - 1, lp_y - 1, lp_w + 2, lp_total_h + 2, 11, 11)
      love.graphics.setColor(p[1], p[2], p[3], 0.55 + 0.20 * pulse)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", lp_x, lp_y, lp_w, lp_total_h, 10, 10)

      love.graphics.setColor(p[1], p[2], p[3], 0.18 + 0.06 * pulse)
      love.graphics.rectangle("fill", lp_x + 2, lp_y + 2, lp_w - 4, lp_title_h - 2, 8, 8)
      love.graphics.setColor(p[1], p[2], p[3], 0.08)
      love.graphics.rectangle("fill", lp_x + 2, lp_y + lp_title_h * 0.6, lp_w - 4, lp_title_h * 0.4, 0, 0)
      love.graphics.setColor(p[1], p[2], p[3], 0.80 + 0.15 * pulse)
      love.graphics.rectangle("fill", lp_x + 6, lp_y + 7, 3, lp_title_h - 14, 2, 2)

      love.graphics.setColor(0, 0, 0, 0.30)
      love.graphics.print("SHOP", lp_x + 16, lp_y + 6)
      love.graphics.setColor(pg[1], pg[2], pg[3], 0.97)
      love.graphics.print("SHOP", lp_x + 15, lp_y + 5)

      local lcy = lp_y + lp_title_h
      local lsep_cx = lp_x + lp_w / 2
      love.graphics.setColor(p[1], p[2], p[3], 0.20)
      love.graphics.setLineWidth(1)
      love.graphics.line(lp_x + 6, lcy, lp_x + lp_w - 6, lcy)
      love.graphics.setColor(pg[1], pg[2], pg[3], 0.35 + 0.10 * pulse)
      love.graphics.line(lsep_cx - 50, lcy, lsep_cx + 50, lcy)
      love.graphics.setColor(pg[1], pg[2], pg[3], 0.50 + 0.15 * pulse)
      love.graphics.circle("fill", lsep_cx, lcy, 1.5)
      lcy = lcy + 6

      local lp_clip_y = lp_y + lp_total_h
      local lp_rows_hidden = 0
      for ri, r in ipairs(shop_rows) do
        local cur_h = lp_row_h(r)
        if lcy + cur_h > lp_clip_y then
          lp_rows_hidden = #shop_rows - ri + 1
          break
        end

        if r[5] then
          lcy = lcy + 3
          local scx = lp_x + lp_w / 2
          love.graphics.setColor(p[1], p[2], p[3], 0.15)
          love.graphics.setLineWidth(1)
          love.graphics.line(lp_x + lp_pad_x + 4, lcy, lp_x + lp_w - lp_pad_x - 4, lcy)
          love.graphics.setColor(p[1], p[2], p[3], 0.30 + 0.08 * pulse)
          love.graphics.line(scx - 40, lcy, scx + 40, lcy)
          love.graphics.setColor(pg[1], pg[2], pg[3], 0.45 + 0.15 * pulse)
          love.graphics.circle("fill", scx, lcy, 2)
          lcy = lcy + sep_h - 3
        elseif r[6] then
          local col = r[1]
          local txt = r[2] or ""
          local indent = r[4] or 0
          love.graphics.setColor(p[1], p[2], p[3], 0.22 + 0.04 * pulse)
          love.graphics.rectangle("fill", lp_x + lp_pad_x + indent - 5, lcy + 1, 2, cur_h - 3, 1, 1)
          if panel_font_small then love.graphics.setFont(panel_font_small) end
          if r[8] then
            local lines = wrapped_lines(txt, math.max(20, lp_content_w - indent), panel_font_small or font)
            local ly = lcy
            for i = 1, #lines do
              love.graphics.setColor(0, 0, 0, 0.20)
              love.graphics.print(lines[i], lp_x + lp_pad_x + indent + 1, ly + 1)
              love.graphics.setColor(col[1], col[2], col[3], 0.95)
              love.graphics.print(lines[i], lp_x + lp_pad_x + indent, ly)
              ly = ly + small_line_h
            end
          else
            local draw_txt = trunc(txt, lp_content_w - indent, panel_font_small)
            love.graphics.setColor(0, 0, 0, 0.20)
            love.graphics.print(draw_txt, lp_x + lp_pad_x + indent + 1, lcy + 1)
            love.graphics.setColor(col[1], col[2], col[3], 0.95)
            love.graphics.print(draw_txt, lp_x + lp_pad_x + indent, lcy)
          end
          if panel_font_small then love.graphics.setFont(font) end
          lcy = lcy + cur_h
        elseif r[7] then
          local col = r[1]
          local txt = r[2] or ""
          local indent = r[4] or 0
          local card_obj = r[7]
          local sprite_h = card_line_h - 4
          local sprite_x = lp_x + lp_pad_x + indent
          local sprite_y = lcy + 2
          local est_w = sprite_h * 0.75
          love.graphics.setColor(col[1], col[2], col[3], 0.10 + 0.05 * pulse)
          love.graphics.rectangle("fill", sprite_x - 3, sprite_y - 3, est_w + 6, sprite_h + 6, 4, 4)
          love.graphics.setColor(0, 0, 0, 0.55)
          love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)
          love.graphics.setColor(col[1], col[2], col[3], 0.35 + 0.12 * pulse)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)
          local mini_w = draw_card_mini(card_obj, sprite_x, sprite_y, sprite_h)
          local text_off = (mini_w > 0 and mini_w or est_w) + 7
          local lp_txt = trunc(txt, lp_content_w - indent - text_off)
          local lp_txt_x = lp_x + lp_pad_x + indent + text_off
          local lp_txt_y = lcy + (card_line_h - text_h) / 2
          love.graphics.setColor(0, 0, 0, 0.30)
          love.graphics.print(lp_txt, lp_txt_x + 1, lp_txt_y + 1)
          love.graphics.setColor(col[1], col[2], col[3], 0.97)
          love.graphics.print(lp_txt, lp_txt_x, lp_txt_y)
          local lp_ed_tag = card_edition_tag(card_obj)
          if lp_ed_tag ~= "" then
            draw_animated_edition(lp_ed_tag, lp_txt_x + font:getWidth(lp_txt), lp_txt_y, 1.0, font, now, pk)
          end
          lcy = lcy + card_line_h
        elseif r[3] then
          local col = r[1]
          local txt = r[2] or ""
          love.graphics.setColor(col[1], col[2], col[3], 0.12)
          love.graphics.rectangle("fill", lp_x + 3, lcy - 1, lp_w - 6, line_h + 2, 5, 5)
          love.graphics.setColor(col[1], col[2], col[3], 0.06)
          love.graphics.rectangle("fill", lp_x + 3, lcy + line_h * 0.4, lp_w - 6, line_h * 0.6 + 2, 0, 5)
          love.graphics.setColor(col[1], col[2], col[3], 0.75 + 0.18 * pulse)
          love.graphics.rectangle("fill", lp_x + 5, lcy + 2, 3, line_h - 3, 2, 2)
          love.graphics.setColor(col[1], col[2], col[3], 0.25 + 0.10 * pulse)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", lp_x + 3, lcy - 1, lp_w - 6, line_h + 2, 5, 5)
          love.graphics.setColor(0, 0, 0, 0.30)
          love.graphics.print(trunc(txt, lp_content_w - 10), lp_x + lp_pad_x + 5, lcy + 2)
          love.graphics.setColor(col[1], col[2], col[3], 1.0)
          love.graphics.print(trunc(txt, lp_content_w - 10), lp_x + lp_pad_x + 4, lcy + 1)
          lcy = lcy + line_h
        else
          local col = r[1]
          local txt = r[2] or ""
          local indent = r[4] or 0
          if indent == 14 then
            love.graphics.setColor(col[1], col[2], col[3], 0.06)
            love.graphics.rectangle("fill", lp_x + lp_pad_x + indent - 3, lcy, lp_content_w - indent + 4, line_h - 2, 4, 4)
            love.graphics.setColor(col[1], col[2], col[3], 0.12)
            love.graphics.rectangle("fill", lp_x + lp_pad_x + indent - 3, lcy, 2, line_h - 2, 1, 1)
            love.graphics.setColor(0, 0, 0, 0.25)
            love.graphics.print(trunc(txt, lp_content_w - indent), lp_x + lp_pad_x + indent + 1, lcy + 1)
            love.graphics.setColor(col[1], col[2], col[3], 0.97)
            love.graphics.print(trunc(txt, lp_content_w - indent), lp_x + lp_pad_x + indent, lcy)
          else
            love.graphics.setColor(col[1], col[2], col[3], 0.90)
            love.graphics.print(trunc(txt, lp_content_w - indent), lp_x + lp_pad_x + indent, lcy)
          end
          lcy = lcy + line_h
        end
      end

      if lp_rows_hidden > 0 then
        local fade_h = 20
        local fade_y = lp_clip_y - fade_h
        local steps = 7
        for i = 0, steps - 1 do
          love.graphics.setColor(bg[1], bg[2], bg[3], (i / steps) * 0.96)
          love.graphics.rectangle("fill", lp_x + 1, fade_y + i * (fade_h / steps), lp_w - 2, math.ceil(fade_h / steps) + 1)
        end
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        local qf = panel_font_small or font
        local more_txt = "+" .. lp_rows_hidden .. " more"
        local mw = qf:getWidth(more_txt)
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.print(more_txt, lp_x + lp_w - mw - lp_pad_x + 1, lp_clip_y - small_text_h - 1)
        love.graphics.setColor(pg[1], pg[2], pg[3], 0.55 + 0.20 * pulse)
        love.graphics.print(more_txt, lp_x + lp_w - mw - lp_pad_x, lp_clip_y - small_text_h - 2)
        if panel_font_small then love.graphics.setFont(font) end
      end

      if _left_panel_slide_frac > 0 then love.graphics.pop() end
    end


    local center_top_y = 8
    if showcase_card and showcase_alpha > 0 then
      local sc_w = 500
      local sc_x = math.floor((sw - sc_w) / 2)
      local a = showcase_alpha
      local sx = sc_x
      local small_f = panel_font_small or font
      local sfh = small_f:getHeight()
      local fh = font:getHeight()
      local sc_p, sc_pg = showcase_type_colors(showcase_label, showcase_card)

      local mini_h = 110
      local text_x = sx + 8 + math.floor(mini_h * 0.75) + 14
      local tw2 = sc_w - (text_x - sx) - 8

      local fx_lines = {}
      if showcase_fx and showcase_fx ~= "" then
        fx_lines = wrapped_lines(showcase_fx, tw2, small_f)
      end
      local desc_lines = {}
      if showcase_desc and showcase_desc ~= "" then
        desc_lines = wrapped_lines(showcase_desc, tw2, small_f)
      end
      local max_desc = 6
      local n_fx = math.min(#fx_lines, 2)
      local n_desc = math.min(#desc_lines, max_desc)
      local text_h2 = fh + 2 + fh + 4
      if n_fx > 0 then text_h2 = text_h2 + n_fx * (sfh + 1) + 2 end
      if n_desc > 0 then text_h2 = text_h2 + n_desc * (sfh + 1) + 2 end
      local sh2 = math.max(mini_h + 8, text_h2 + 8)
      local sy = center_top_y + showcase_slide

      love.graphics.setColor(bg[1], bg[2], bg[3], 0.94 * a)
      love.graphics.rectangle("fill", sx - 2, sy - 2, sc_w + 4, sh2 + 4, 8, 8)
      love.graphics.setColor(sc_p[1], sc_p[2], sc_p[3], 0.16 * a)
      love.graphics.rectangle("fill", sx, sy, sc_w, sh2, 6, 6)
      love.graphics.setColor(sc_pg[1], sc_pg[2], sc_pg[3], (0.55 + 0.25 * pulse) * a)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", sx, sy, sc_w, sh2, 6, 6)
      -- outer glow line in type colour
      love.graphics.setColor(sc_pg[1], sc_pg[2], sc_pg[3], (0.10 + 0.06 * pulse) * a)
      love.graphics.setLineWidth(5)
      love.graphics.rectangle("line", sx - 3, sy - 3, sc_w + 6, sh2 + 6, 9, 9)
      love.graphics.setLineWidth(1)

      local mini_x = sx + 6
      local mini_y = sy + math.floor((sh2 - mini_h) / 2)
      love.graphics.setColor(sc_p[1], sc_p[2], sc_p[3], (0.20 + 0.12 * pulse) * a)
      love.graphics.circle("fill", mini_x + mini_h * 0.38, mini_y + mini_h * 0.5, mini_h * 0.45)
      draw_card_mini(showcase_card, mini_x, mini_y, mini_h)

      local yy = sy + 3
      love.graphics.setColor(sc_pg[1], sc_pg[2], sc_pg[3], (0.90 + 0.10 * pulse) * a)
      love.graphics.print(showcase_label or "NEW CARD", text_x, yy)
      yy = yy + fh + 2

      local nline = trunc(showcase_name or "Card", tw2)
      love.graphics.setColor(0, 0, 0, 0.35 * a)
      love.graphics.print(nline, text_x + 1, yy + 1)
      love.graphics.setColor(1, 1, 1, 0.98 * a)
      love.graphics.print(nline, text_x, yy)
      local sc_ed = card_edition_tag(showcase_card)
      if sc_ed ~= "" then
        draw_animated_edition(sc_ed, text_x + font:getWidth(nline), yy, a, font, now, pk)
      end
      yy = yy + fh + 4

      if n_fx > 0 then
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        love.graphics.setColor(sc_pg[1], sc_pg[2], sc_pg[3], 0.92 * a)
        for i = 1, n_fx do
          love.graphics.print(fx_lines[i], text_x, yy)
          yy = yy + sfh + 1
        end
        yy = yy + 2
        if panel_font_small then love.graphics.setFont(font) end
      end

      if n_desc > 0 then
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        for i = 1, n_desc do
          draw_colored_desc(desc_lines[i], text_x, yy, a, small_f)
          yy = yy + sfh + 1
        end
        if panel_font_small then love.graphics.setFont(font) end
      end

      center_top_y = center_top_y + sh2 + 12
    end


    local pack_has_cards = pack_rows.cards and #pack_rows.cards > 0
    local is_pack_state = sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED"

    if is_pack_state and _pack_last_sn ~= sn then
      _pack_appear_t = now
      _pack_picked = {}
      _pack_prev_cards = {}
    end
    _pack_last_sn = is_pack_state and sn or nil

    if pack_has_cards then
      local cur_set = {}
      for _, cd in ipairs(pack_rows.cards) do cur_set[cd.card] = true end
      for _, prev_c in ipairs(_pack_prev_cards) do
        if not cur_set[prev_c.card] and not _pack_picked[prev_c.card] then
          _pack_picked[prev_c.card] = {
            at = now, name = prev_c.name, desc = prev_c.desc,
            rc = prev_c.rc, index = prev_c.index,
          }
        end
      end
      _pack_prev_cards = {}
      for _, cd in ipairs(pack_rows.cards) do
        _pack_prev_cards[#_pack_prev_cards + 1] = {
          card = cd.card, name = cd.name, desc = cd.desc,
          rc = cd.rc, index = cd.index,
        }
      end
    end

    local any_highlighted = false
    if pack_has_cards then
      for _, cd in ipairs(pack_rows.cards) do
        if G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card] then
          any_highlighted = true
          break
        end
      end
    end

    local PICK_FADE_DUR = 1.2
    local PICK_FADE_FAST = 0.35
    for k, v in pairs(_pack_picked) do
      local elapsed = now - v.at
      local fade_dur = any_highlighted and PICK_FADE_FAST or PICK_FADE_DUR
      if elapsed > fade_dur then _pack_picked[k] = nil end
    end

    if pack_has_cards or next(_pack_picked) then
      local pk_w = 500
      local pk_x = math.floor((sw - pk_w) / 2)
      local pk_pad = 10
      local pk_content_w = pk_w - pk_pad * 2
      local slot_h = 90
      local slot_gap = 6
      local small_f = panel_font_small or font

      local display_cards = {}
      if pack_has_cards then
        for _, cd in ipairs(pack_rows.cards) do
          local is_hl = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card]
          display_cards[#display_cards + 1] = {
            card = cd.card, name = cd.name, desc = cd.desc,
            rc = cd.rc, index = cd.index,
            state = is_hl and "highlighted" or "normal",
            alpha = 1.0,
          }
        end
      end
      for _, pv in pairs(_pack_picked) do
        local elapsed = now - pv.at
        local eff_fade_dur = any_highlighted and PICK_FADE_FAST or PICK_FADE_DUR
        local fade = math.max(0, 1 - elapsed / eff_fade_dur)
        if fade > 0 then
          display_cards[#display_cards + 1] = {
            card = nil, name = pv.name, desc = pv.desc,
            rc = pv.rc, index = pv.index,
            state = "picked", alpha = fade,
            pick_elapsed = elapsed,
          }
        end
      end
      table.sort(display_cards, function(a, b) return a.index < b.index end)

      local n_cards = #display_cards
      local title_h2 = line_h + 6
      local pk_total_h = title_h2 + n_cards * (slot_h + slot_gap) + 6

      love.graphics.setColor(bg[1], bg[2], bg[3], 0.95)
      love.graphics.rectangle("fill", pk_x, center_top_y, pk_w, pk_total_h, 10, 10)
      love.graphics.setColor(p[1], p[2], p[3], 0.05)
      love.graphics.rectangle("fill", pk_x + 1, center_top_y + 1, pk_w - 2, pk_total_h - 2, 10, 10)

      love.graphics.setColor(pg[1], pg[2], pg[3], 0.06 + 0.04 * pulse)
      love.graphics.setLineWidth(6)
      love.graphics.rectangle("line", pk_x - 3, center_top_y - 3, pk_w + 6, pk_total_h + 6, 13, 13)
      love.graphics.setColor(p[1], p[2], p[3], 0.10 + 0.06 * pulse)
      love.graphics.setLineWidth(4)
      love.graphics.rectangle("line", pk_x - 1, center_top_y - 1, pk_w + 2, pk_total_h + 2, 11, 11)
      love.graphics.setColor(p[1], p[2], p[3], 0.55 + 0.20 * pulse)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", pk_x, center_top_y, pk_w, pk_total_h, 10, 10)

      -- title bar
      local pk_title_color = (pack_rows.pg or pg)
      love.graphics.setColor(pk_title_color[1], pk_title_color[2], pk_title_color[3], 0.18 + 0.06 * pulse)
      love.graphics.rectangle("fill", pk_x + 2, center_top_y + 2, pk_w - 4, title_h2 - 2, 8, 8)
      love.graphics.setColor(pk_title_color[1], pk_title_color[2], pk_title_color[3], 0.80 + 0.15 * pulse)
      love.graphics.rectangle("fill", pk_x + 6, center_top_y + 5, 3, title_h2 - 10, 2, 2)
      love.graphics.setColor(0, 0, 0, 0.30)
      love.graphics.print(trunc(pack_rows.title or "Pack", pk_content_w - 10), pk_x + pk_pad + 5, center_top_y + 4)
      love.graphics.setColor(pk_title_color[1], pk_title_color[2], pk_title_color[3], 1.0)
      love.graphics.print(trunc(pack_rows.title or "Pack", pk_content_w - 10), pk_x + pk_pad + 4, center_top_y + 3)

      -- card slots
      local slot_y = center_top_y + title_h2 + 2
      for ci, dc in ipairs(display_cards) do
        local ca = dc.alpha
        -- stagger-in animation: each card slides in from the right with delay
        local stagger_delay = (ci - 1) * 0.08
        local appear_elapsed = now - _pack_appear_t - stagger_delay
        local appear_frac = 1.0
        local slide_x = 0
        if appear_elapsed < 0.35 and dc.state ~= "picked" then
          appear_frac = math.max(0, math.min(1, appear_elapsed / 0.35))
          -- ease-out cubic
          local ef = 1 - (1 - appear_frac) * (1 - appear_frac) * (1 - appear_frac)
          ca = ca * ef
          slide_x = math.floor((1 - ef) * 60)
        end

        local sx = pk_x + pk_pad + slide_x
        local sw2 = pk_content_w - slide_x
        local is_gold = dc.state == "highlighted" or dc.state == "picked"
        local pulse2 = math.sin(now * 3.2)
        local pulse3 = math.sin(now * 4.5)
        local pulse4 = math.sin(now * 6.0)

        if dc.state == "picked" then
          -- picked card: golden burst → scale up slightly → fade out
          local pe = dc.pick_elapsed or 0
          local burst_frac = math.min(1, pe / 0.25)

          -- golden burst flash
          if burst_frac < 1 then
            local bf_a = (1 - burst_frac) * 0.60 * ca
            love.graphics.setColor(1, 0.93, 0.40, bf_a)
            love.graphics.rectangle("fill", sx - 2, slot_y - 2, sw2 + 4, slot_h + 4, 8, 8)
          end

          -- golden fill (fading)
          love.graphics.setColor(1, 0.78, 0.10, 0.20 * ca)
          love.graphics.rectangle("fill", sx, slot_y, sw2, slot_h, 6, 6)

          -- golden border
          love.graphics.setColor(1, 0.85, 0.20, (0.65 + 0.15 * pulse2) * ca)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", sx, slot_y, sw2, slot_h, 6, 6)

          -- "PICKED!" label
          love.graphics.setColor(1, 0.88, 0.18, 0.90 * ca)
          local pick_label = "PICKED!"
          local plw = font:getWidth(pick_label)
          love.graphics.print(pick_label, sx + sw2 - plw - 8, slot_y + (slot_h - text_h) / 2)
        elseif dc.state == "highlighted" then
          -- golden highlighted card: warm glow + pulsing border + sparkles

          -- outer glow
          love.graphics.setColor(1, 0.85, 0.20, (0.12 + 0.06 * pulse3) * ca)
          love.graphics.setLineWidth(8)
          love.graphics.rectangle("line", sx - 6, slot_y - 6, sw2 + 12, slot_h + 12, 14, 14)

          -- warm gold fill
          love.graphics.setColor(1, 0.78, 0.10, (0.18 + 0.06 * pulse2) * ca)
          love.graphics.rectangle("fill", sx, slot_y, sw2, slot_h, 6, 6)

          -- mid gold border (bright pulse)
          love.graphics.setColor(1, 0.88, 0.18, (0.75 + 0.25 * pulse2) * ca)
          love.graphics.setLineWidth(3)
          love.graphics.rectangle("line", sx - 1, slot_y - 1, sw2 + 2, slot_h + 2, 7, 7)

          -- inner crisp highlight
          love.graphics.setColor(1, 1, 0.55, (0.30 + 0.20 * pulse4) * ca)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", sx + 1, slot_y + 1, sw2 - 2, slot_h - 2, 5, 5)

          -- sparkle dots orbiting the slot
          local n_sparkles = 4
          local sparkle_r = math.max(sw2, slot_h) * 0.52
          local cx2 = sx + sw2 / 2
          local cy2 = slot_y + slot_h / 2
          for si = 0, n_sparkles - 1 do
            local angle = now * 2.0 + si * (math.pi * 2 / n_sparkles)
            local sx2 = cx2 + math.cos(angle) * sparkle_r * 0.95
            local sy2 = cy2 + math.sin(angle) * sparkle_r * 0.35
            local sp = 0.5 + 0.5 * math.sin(now * 5.5 + si * 1.7)
            love.graphics.setColor(1, 0.95, 0.50, (0.50 + 0.40 * sp) * ca)
            love.graphics.circle("fill", sx2, sy2, 2 + sp * 1.5)
          end
        else
          -- normal card slot background
          love.graphics.setColor(p[1], p[2], p[3], 0.10 * ca)
          love.graphics.rectangle("fill", sx, slot_y, sw2, slot_h, 6, 6)

          -- subtle rarity border
          local rc = dc.rc
          love.graphics.setColor(rc[1], rc[2], rc[3], (0.25 + 0.08 * pulse) * ca)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", sx, slot_y, sw2, slot_h, 6, 6)
        end

        -- card sprite
        if dc.card then
          local sprite_h2 = slot_h - 8
          local sprite_x2 = sx + 5
          local sprite_y2 = slot_y + 4
          local est_w2 = sprite_h2 * 0.75
          local rc = dc.rc

          love.graphics.setColor(rc[1], rc[2], rc[3], (0.10 + 0.05 * pulse) * ca)
          love.graphics.rectangle("fill", sprite_x2 - 3, sprite_y2 - 3, est_w2 + 6, sprite_h2 + 6, 4, 4)
          love.graphics.setColor(0, 0, 0, 0.55 * ca)
          love.graphics.rectangle("fill", sprite_x2 - 1, sprite_y2 - 1, est_w2 + 2, sprite_h2 + 2, 2, 2)
          if is_gold then
            love.graphics.setColor(1, 0.85, 0.20, (0.55 + 0.20 * pulse2) * ca)
          else
            love.graphics.setColor(rc[1], rc[2], rc[3], (0.35 + 0.12 * pulse) * ca)
          end
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", sprite_x2 - 1, sprite_y2 - 1, est_w2 + 2, sprite_h2 + 2, 2, 2)

          local mini_w = draw_card_mini(dc.card, sprite_x2, sprite_y2, sprite_h2)
          local text_x = sprite_x2 + (mini_w > 0 and mini_w or est_w2) + 8
          local text_w = sx + sw2 - text_x - 6

          -- card name
          local name_y = slot_y + 4
          local rc2 = is_gold and {1, 0.92, 0.40} or dc.rc
          love.graphics.setColor(0, 0, 0, 0.35 * ca)
          love.graphics.print(trunc(dc.name, text_w), text_x + 1, name_y + 1)
          love.graphics.setColor(rc2[1], rc2[2], rc2[3], 0.97 * ca)
          love.graphics.print(trunc(dc.name, text_w), text_x, name_y)

          -- card description (wrapped, up to 2 lines)
          if dc.desc and dc.desc ~= "" then
            if panel_font_small then love.graphics.setFont(panel_font_small) end
            local desc_lines = wrapped_lines(dc.desc, math.max(20, text_w), small_f)
            local dy = name_y + text_h + 2
            for li = 1, math.min(#desc_lines, 3) do
              draw_colored_desc(desc_lines[li], text_x, dy, ca, small_f)
              dy = dy + small_line_h
            end
            if panel_font_small then love.graphics.setFont(font) end
          end
        else
          -- picked card with no card ref: just show name + PICKED
          local text_x = sx + 8
          local text_w = sw2 - 16
          local rc2 = {1, 0.92, 0.40}
          love.graphics.setColor(0, 0, 0, 0.35 * ca)
          love.graphics.print(trunc(dc.name, text_w - 70), text_x + 1, slot_y + (slot_h - text_h) / 2 + 1)
          love.graphics.setColor(rc2[1], rc2[2], rc2[3], 0.97 * ca)
          love.graphics.print(trunc(dc.name, text_w - 70), text_x, slot_y + (slot_h - text_h) / 2)
        end

        slot_y = slot_y + slot_h + slot_gap
      end

      center_top_y = center_top_y + pk_total_h + 4
    end

    trace("IND: panel bg draw start p_x=" .. tostring(p_x) .. " p_y=" .. tostring(p_y) .. " p_w=" .. tostring(p_w) .. " total_h=" .. tostring(total_h))
    trace("IND: bg color=" .. tostring(bg[1]) .. "," .. tostring(bg[2]) .. "," .. tostring(bg[3]))
    if _right_panel_slide_frac > 0 then
      love.graphics.push()
      love.graphics.translate(math.floor((p_w + 20) * _right_panel_slide_frac + 0.5), 0)
    end
    love.graphics.setColor(bg[1], bg[2], bg[3], 0.96)
    love.graphics.rectangle("fill", p_x, p_y, p_w, total_h, 10, 10)
    love.graphics.setColor(p[1], p[2], p[3], 0.05)
    love.graphics.rectangle("fill", p_x + 1, p_y + 1, p_w - 2, total_h - 2, 10, 10)

    love.graphics.setColor(pg[1], pg[2], pg[3], 0.06 + 0.04 * pulse)
    love.graphics.setLineWidth(6)
    love.graphics.rectangle("line", p_x - 3, p_y - 3, p_w + 6, total_h + 6, 13, 13)
    love.graphics.setColor(p[1], p[2], p[3], 0.10 + 0.06 * pulse)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", p_x - 1, p_y - 1, p_w + 2, total_h + 2, 11, 11)
    love.graphics.setColor(p[1], p[2], p[3], 0.55 + 0.20 * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", p_x, p_y, p_w, total_h, 10, 10)

    love.graphics.setColor(p[1], p[2], p[3], 0.18 + 0.06 * pulse)
    love.graphics.rectangle("fill", p_x + 2, p_y + 2, p_w - 4, title_h - 2, 8, 8)
    love.graphics.setColor(p[1], p[2], p[3], 0.08)
    love.graphics.rectangle("fill", p_x + 2, p_y + title_h * 0.6, p_w - 4, title_h * 0.4, 0, 0)

    love.graphics.setColor(p[1], p[2], p[3], 0.80 + 0.15 * pulse)
    love.graphics.rectangle("fill", p_x + 6, p_y + 7, 3, title_h - 14, 2, 2)
    love.graphics.setColor(p[1], p[2], p[3], 0.40 + 0.20 * pulse)
    love.graphics.rectangle("fill", p_x + 6, p_y + 7, 1, title_h - 14, 1, 1)

    local tx = p_x + 15
    local ty = p_y + 5
    if logo then
      love.graphics.setColor(p[1], p[2], p[3], 0.25 + 0.15 * pulse)
      love.graphics.circle("fill", tx + logo_w / 2, ty + logo_h / 2 + 2, logo_w * 0.55)
      love.graphics.setColor(1, 1, 1, 0.92 + 0.08 * pulse)
      love.graphics.draw(logo, tx, ty + 2, 0, logo_scale, logo_scale)
      tx = tx + logo_w + 7
    end

    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.print(persona_name, tx + 1, ty + 2)
    love.graphics.setColor(pg[1], pg[2], pg[3], 0.97)
    love.graphics.print(persona_name, tx, ty + 1)

    local dots = string.rep(".", math.floor(now * 2) % 4)
    if panel_font_small then love.graphics.setFont(panel_font_small) end
    love.graphics.setColor(1, 1, 1, 0.55 + 0.15 * pulse)
    love.graphics.print(state_label .. dots, tx, ty + text_h + 4)
    if panel_font_small then love.graphics.setFont(font) end

    local cy = p_y + title_h
    local tsep_cx = p_x + p_w / 2
    love.graphics.setColor(p[1], p[2], p[3], 0.20)
    love.graphics.setLineWidth(1)
    love.graphics.line(p_x + 6, cy, p_x + p_w - 6, cy)
    love.graphics.setColor(pg[1], pg[2], pg[3], 0.35 + 0.10 * pulse)
    love.graphics.line(tsep_cx - 50, cy, tsep_cx + 50, cy)
    love.graphics.setColor(pg[1], pg[2], pg[3], 0.50 + 0.15 * pulse)
    love.graphics.circle("fill", tsep_cx, cy, 1.5)
    cy = cy + 2

    if action_text then
      love.graphics.setColor(p[1], p[2], p[3], 0.12 + 0.06 * pulse)
      love.graphics.rectangle("fill", p_x + 3, cy + 1, p_w - 6, action_row_h - 3, 5, 5)
      love.graphics.setColor(p[1], p[2], p[3], 0.10 + 0.08 * pulse)
      love.graphics.rectangle("fill", p_x + 3, cy + 1, 4, action_row_h - 3, 2, 0)

      local act_pulse = math.abs(math.sin(now * 3.8))
      love.graphics.setColor(pg[1], pg[2], pg[3], 0.55 + 0.45 * act_pulse)
      love.graphics.print(">", p_x + p_pad_x + math.floor(act_pulse * 2), cy + 4)
      local action_draw = trunc(action_text, p_w - p_pad_x * 2 - 16)
      love.graphics.setColor(0, 0, 0, 0.50)
      love.graphics.print(action_draw, p_x + p_pad_x + 14, cy + 5)
      love.graphics.setColor(1, 1, 1, 0.98)
      love.graphics.print(action_draw, p_x + p_pad_x + 13, cy + 4)
      cy = cy + action_row_h
      love.graphics.setColor(p[1], p[2], p[3], 0.25)
      love.graphics.line(p_x + 8, cy, p_x + p_w - 8, cy)
      cy = cy + 2
    end

    trace("IND: showcase done")
    trace("IND: palette buttons done")
    trace("IND: data rows section, count=" .. tostring(#panel_rows))
    if #panel_rows > 0 then
      cy = cy + 4
      local clip_y = p_y + total_h - footer_h
      local rows_hidden = 0
      local seen_cards = {}
      local cur_card_a = 1.0
      for ri, r in ipairs(panel_rows) do
        trace("IND: ROW " .. tostring(ri) .. " type=" .. tostring(r[5] and "sep" or (r[6] and "small" or (r[7] and "card" or (r[3] and "hdr" or "normal")))) .. " text='" .. tostring(r[2] or "") .. "'")
        local cur_h = row_h(r)
        if cy + cur_h > clip_y then trace("IND: ROW overflow, break")
          rows_hidden = #panel_rows - ri + 1
          break
        end

        -- track card fade-in alpha; reset on sep/hdr
        if r[7] then
          local co = r[7]
          seen_cards[co] = true
          if not _card_first_seen[co] then _card_first_seen[co] = now end
          cur_card_a = math.min(1.0, (now - _card_first_seen[co]) / 0.35)
        elseif r[5] or r[3] then
          cur_card_a = 1.0
        end

        if r[5] then
          cy = cy + 3
          local sep_cx = p_x + p_w / 2
          local sep_left = p_x + p_pad_x + 4
          local sep_right = p_x + p_w - p_pad_x - 4
          love.graphics.setColor(p[1], p[2], p[3], 0.15)
          love.graphics.setLineWidth(1)
          love.graphics.line(sep_left, cy, sep_right, cy)
          love.graphics.setColor(p[1], p[2], p[3], 0.30 + 0.08 * pulse)
          love.graphics.line(sep_cx - 40, cy, sep_cx + 40, cy)
          love.graphics.setColor(pg[1], pg[2], pg[3], 0.45 + 0.15 * pulse)
          love.graphics.circle("fill", sep_cx, cy, 2)
          love.graphics.setColor(pg[1], pg[2], pg[3], 0.20 + 0.10 * pulse)
          love.graphics.circle("fill", sep_cx - 12, cy, 1)
          love.graphics.circle("fill", sep_cx + 12, cy, 1)
          cy = cy + sep_h - 3

        elseif r[6] then
          local col = r[1]
          local txt = r[2] or ""
          local indent = r[4] or 0
          love.graphics.setColor(p[1], p[2], p[3], (0.22 + 0.04 * pulse) * cur_card_a)
          love.graphics.rectangle("fill", p_x + p_pad_x + indent - 5, cy + 1, 2, cur_h - 3, 1, 1)
          if panel_font_small then love.graphics.setFont(panel_font_small) end
          if r[8] then
            local lines = wrapped_lines(txt, math.max(20, content_w - indent), panel_font_small or font)
            local ly = cy
            for i = 1, #lines do
              local draw_txt = lines[i]
              love.graphics.setColor(0, 0, 0, 0.20 * cur_card_a)
              love.graphics.print(draw_txt, p_x + p_pad_x + indent + 1, ly + 1)
              love.graphics.setColor(col[1], col[2], col[3], 0.95 * cur_card_a)
              love.graphics.print(draw_txt, p_x + p_pad_x + indent, ly)
              ly = ly + small_line_h
            end
          else
            local draw_txt = trunc(txt, content_w - indent, panel_font_small)
            love.graphics.setColor(0, 0, 0, 0.20 * cur_card_a)
            love.graphics.print(draw_txt, p_x + p_pad_x + indent + 1, cy + 1)
            love.graphics.setColor(col[1], col[2], col[3], 0.95 * cur_card_a)
            love.graphics.print(draw_txt, p_x + p_pad_x + indent, cy)
          end
          if panel_font_small then love.graphics.setFont(font) end
          cy = cy + cur_h

        elseif r[7] then
          local col = r[1]
          local txt = r[2] or ""
          local indent = r[4] or 0
          local card_obj = r[7]
          local sprite_h = card_line_h - 4
          local sprite_x = p_x + p_pad_x + indent
          local sprite_y = cy + 2
          local est_w = sprite_h * 0.75

          love.graphics.setColor(col[1], col[2], col[3], (0.10 + 0.05 * pulse) * cur_card_a)
          love.graphics.rectangle("fill", sprite_x - 3, sprite_y - 3, est_w + 6, sprite_h + 6, 4, 4)
          love.graphics.setColor(0, 0, 0, 0.55 * cur_card_a)
          love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)
          love.graphics.setColor(col[1], col[2], col[3], (0.35 + 0.12 * pulse) * cur_card_a)
          love.graphics.setLineWidth(1)
          love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)

          local mini_w = draw_card_mini(card_obj, sprite_x, sprite_y, sprite_h)
          local text_off = (mini_w > 0 and mini_w or est_w) + 7
          local txt_trunc = trunc(txt, content_w - indent - text_off)
          local txt_x = p_x + p_pad_x + indent + text_off
          local txt_y = cy + (card_line_h - text_h) / 2

          love.graphics.setColor(0, 0, 0, 0.30 * cur_card_a)
          love.graphics.print(txt_trunc, txt_x + 1, txt_y + 1)
          love.graphics.setColor(col[1], col[2], col[3], 0.97 * cur_card_a)
          love.graphics.print(txt_trunc, txt_x, txt_y)
          local ed_tag = card_edition_tag(card_obj)
          if ed_tag ~= "" then
            draw_animated_edition(ed_tag, txt_x + font:getWidth(txt_trunc), txt_y, cur_card_a, font, now, pk)
          end
          cy = cy + card_line_h

        elseif r[12] then
          local jokers = r[12]
          local n = #jokers
          if n > 0 then
            local sprite_h = math.min(88, math.floor(content_w / n / 0.72 * 0.92))
            local sprite_w_est = math.floor(sprite_h * 0.72)
            local slot_w = content_w / n
            for ji, jc in ipairs(jokers) do
              local slot_x = p_x + p_pad_x + (ji - 1) * slot_w
              local sprite_x = math.floor(slot_x + (slot_w - sprite_w_est) / 2)
              local sprite_y = cy + 2
              local rc = rarity_color(jc) or {1, 1, 1}
              love.graphics.setColor(rc[1], rc[2], rc[3], (0.14 + 0.06 * pulse) * cur_card_a)
              love.graphics.rectangle("fill", sprite_x - 3, sprite_y - 3, sprite_w_est + 6, sprite_h + 6, 4, 4)
              love.graphics.setColor(0, 0, 0, 0.55 * cur_card_a)
              love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, sprite_w_est + 2, sprite_h + 2, 2, 2)
              love.graphics.setColor(rc[1], rc[2], rc[3], (0.50 + 0.18 * pulse) * cur_card_a)
              love.graphics.setLineWidth(1)
              love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, sprite_w_est + 2, sprite_h + 2, 2, 2)
              draw_card_mini(jc, sprite_x, sprite_y, sprite_h)
              local jname = card_display_name(jc) or "?"
              local sf = panel_font_small or font
              if panel_font_small then love.graphics.setFont(panel_font_small) end
              local jname_t = trunc(jname, slot_w - 4)
              local nw = sf:getWidth(jname_t)
              local nx = math.floor(slot_x + (slot_w - math.min(nw, slot_w)) / 2)
              local jny = cy + sprite_h + 6
              love.graphics.setColor(0, 0, 0, 0.30 * cur_card_a)
              love.graphics.print(jname_t, nx + 1, jny + 1)
              love.graphics.setColor(rc[1], rc[2], rc[3], 0.95 * cur_card_a)
              love.graphics.print(jname_t, nx, jny)
              local jed = card_edition_tag(jc)
              if jed ~= "" then
                draw_animated_edition(jed, nx + nw, jny, cur_card_a, sf, now, pk)
              end
              if panel_font_small then love.graphics.setFont(font) end
            end
          end
          cy = cy + 88 + small_line_h + 8

        elseif r[10] then
          local jokers = r[10]
          local n = #jokers
          if n > 0 then
            -- ---- dt-driven state machine: FADE_IN → SHOW → FADE_OUT → advance ----
            local D_FADE = 0.30
            local D_SHOW = 2.40
            local D_TOTAL = D_FADE + D_SHOW + D_FADE

            -- guard slot bounds (joker sold mid-cycle)
            if _desc_slot >= n then _desc_slot = 0; _desc_phase_t = 0.0 end

            local fade_a, show_progress
            if n == 1 then
              -- single joker: always fully visible, no cycling
              _desc_slot = 0
              fade_a = cur_card_a
              show_progress = 1.0
            else
              _desc_phase_t = _desc_phase_t + dt
              if _desc_phase_t < D_FADE then
                fade_a = _desc_phase_t / D_FADE
                show_progress = 0.0
              elseif _desc_phase_t < D_FADE + D_SHOW then
                fade_a = 1.0
                show_progress = (_desc_phase_t - D_FADE) / D_SHOW
              else
                local t = _desc_phase_t - D_FADE - D_SHOW
                fade_a = math.max(0.0, 1.0 - t / D_FADE)
                show_progress = 1.0
                if _desc_phase_t >= D_TOTAL then
                  _desc_slot = (_desc_slot + 1) % n
                  _desc_phase_t = 0.0
                  fade_a = 0.0
                  show_progress = 0.0
                end
              end
              fade_a = fade_a * cur_card_a
            end

            -- ---- cache text content (invalidated when joker count changes) ----
            if _desc_cache_n ~= n then _desc_cache = {}; _desc_cache_n = n end
            local cached = _desc_cache[_desc_slot]
            if not cached then
              local jc2 = jokers[_desc_slot + 1]
              if jc2 then
                local fx   = joker_fx(jc2) or ""
                local desc = card_description(jc2) or ""
                if desc == "" and jc2.config and jc2.config.center then
                  local ok, d = pcall(Utils.safe_description, jc2.config.center.loc_txt, jc2)
                  if ok and type(d) == "string" then desc = d end
                end
                local show = desc
                if show == "" then show = fx end
                local sf2   = panel_font_small or font
                local lns   = show ~= "" and wrapped_lines(show, content_w - 36, sf2) or {}
                local rc2   = rarity_color(jc2)
                if not rc2 or type(rc2) ~= "table" then rc2 = {1,1,1} end
                local dname = card_display_name(jc2) or "?"
                if fx ~= "" and desc ~= "" then dname = dname .. "  " .. fx end
                cached = { name = dname, show = show,
                           lines = lns, rc = rc2, jc = jc2 }
                _desc_cache[_desc_slot] = cached
              end
            end

            local jc = cached and cached.jc
            if jc then
              local rc = cached.rc
              local jname = cached.name
              local lns   = cached.lines
              local sf = panel_font_small or font

              -- subtle background tray
              love.graphics.setColor(rc[1], rc[2], rc[3], 0.06)
              love.graphics.rectangle("fill", p_x + 3, cy, p_w - 6, card_line_h + small_line_h * 3 + 4, 5, 5)

              -- mini card sprite box
              local sprite_h = card_line_h - 4
              local sprite_x = p_x + p_pad_x
              local sprite_y = cy + 2
              local est_w    = sprite_h * 0.75
              love.graphics.setColor(rc[1], rc[2], rc[3], (0.14 + 0.06 * pulse) * fade_a)
              love.graphics.rectangle("fill", sprite_x - 3, sprite_y - 3, est_w + 6, sprite_h + 6, 4, 4)
              love.graphics.setColor(0, 0, 0, 0.55 * fade_a)
              love.graphics.rectangle("fill", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)
              love.graphics.setColor(rc[1], rc[2], rc[3], (0.45 + 0.15 * pulse) * fade_a)
              love.graphics.setLineWidth(1)
              love.graphics.rectangle("line", sprite_x - 1, sprite_y - 1, est_w + 2, sprite_h + 2, 2, 2)
              local mini_w  = draw_card_mini(jc, sprite_x, sprite_y, sprite_h)
              local text_off = math.max(est_w, mini_w > 0 and mini_w or 0) + 7

              -- joker name
              love.graphics.setColor(0, 0, 0, 0.30 * fade_a)
              love.graphics.print(trunc(jname, content_w - text_off - 28), p_x + p_pad_x + text_off + 1, cy + (card_line_h - text_h) / 2 + 1)
              love.graphics.setColor(rc[1], rc[2], rc[3], 0.97 * fade_a)
              love.graphics.print(trunc(jname, content_w - text_off - 28), p_x + p_pad_x + text_off, cy + (card_line_h - text_h) / 2)

              -- slot counter top-right (always visible regardless of fade)
              if panel_font_small then love.graphics.setFont(panel_font_small) end
              local slot_txt = tostring(_desc_slot + 1) .. "/" .. tostring(n)
              local stw = sf:getWidth(slot_txt)
              love.graphics.setColor(0, 0, 0, 0.20)
              love.graphics.print(slot_txt, p_x + p_w - p_pad_x - stw + 1, cy + (card_line_h - small_text_h) / 2 + 1)
              love.graphics.setColor(pg[1], pg[2], pg[3], 0.45 + 0.15 * pulse)
              love.graphics.print(slot_txt, p_x + p_w - p_pad_x - stw, cy + (card_line_h - small_text_h) / 2)

              if #lns > 0 then
                local desc_y = cy + card_line_h
                local sf = panel_font_small or font
                for li = 1, math.min(#lns, 3) do
                  draw_colored_desc(lns[li], p_x + p_pad_x + text_off, desc_y, fade_a, sf)
                  desc_y = desc_y + small_line_h
                end
              end
              if panel_font_small then love.graphics.setFont(font) end

              -- progress bar + dots (only when cycling multiple jokers)
              if n == 1 then goto desc_cycle_done end
              local bar_y = cy + card_line_h + small_line_h * 3 + 3
              local bar_x = p_x + p_pad_x
              love.graphics.setColor(p[1], p[2], p[3], 0.18)
              love.graphics.rectangle("fill", bar_x, bar_y, content_w, 3, 1, 1)
              love.graphics.setColor(pg[1], pg[2], pg[3], 0.60 + 0.20 * pulse)
              love.graphics.rectangle("fill", bar_x, bar_y, math.max(2, content_w * show_progress), 3, 1, 1)

              -- dot indicators (always visible — shows which joker is active)
              local dot_y  = bar_y + 7
              local dot_sp = math.min(10, math.floor((content_w - 4) / math.max(1, n)))
              local total_dots_w = (n - 1) * dot_sp
              local dot_x0 = p_x + p_w / 2 - total_dots_w / 2
              for di = 0, n - 1 do
                local dx = dot_x0 + di * dot_sp
                if di == _desc_slot then
                  love.graphics.setColor(pg[1], pg[2], pg[3], 0.85 + 0.10 * pulse)
                  love.graphics.circle("fill", dx, dot_y, 3)
                else
                  love.graphics.setColor(p[1], p[2], p[3], 0.25)
                  love.graphics.circle("fill", dx, dot_y, 2)
                end
              end
              ::desc_cycle_done::
            end
          end
          cy = cy + card_line_h + small_line_h * 2 + 18

        else
          local col = r[1]
          local txt = r[2] or ""
          local is_hdr = r[3]
          local indent = r[4] or 0

          if is_hdr then
            love.graphics.setColor(col[1], col[2], col[3], 0.12)
            love.graphics.rectangle("fill", p_x + 3, cy - 1, p_w - 6, line_h + 2, 5, 5)
            love.graphics.setColor(col[1], col[2], col[3], 0.06)
            love.graphics.rectangle("fill", p_x + 3, cy + line_h * 0.4, p_w - 6, line_h * 0.6 + 2, 0, 5)
            love.graphics.setColor(col[1], col[2], col[3], 0.75 + 0.18 * pulse)
            love.graphics.rectangle("fill", p_x + 5, cy + 2, 3, line_h - 3, 2, 2)
            love.graphics.setColor(col[1], col[2], col[3], 0.25 + 0.10 * pulse)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", p_x + 3, cy - 1, p_w - 6, line_h + 2, 5, 5)
            love.graphics.setColor(0, 0, 0, 0.30)
            love.graphics.print(trunc(txt, content_w - 10), p_x + p_pad_x + 5, cy + 2)
            love.graphics.setColor(col[1], col[2], col[3], 1.0)
            love.graphics.print(trunc(txt, content_w - 10), p_x + p_pad_x + 4, cy + 1)
          elseif indent == 14 then
            local block_w = math.max(28, content_w - indent + 4)
            love.graphics.setColor(col[1], col[2], col[3], 0.06)
            love.graphics.rectangle("fill", p_x + p_pad_x + indent - 3, cy, block_w, line_h - 2, 4, 4)
            love.graphics.setColor(col[1], col[2], col[3], 0.12)
            love.graphics.rectangle("fill", p_x + p_pad_x + indent - 3, cy, 2, line_h - 2, 1, 1)
            love.graphics.setColor(0, 0, 0, 0.25)
            love.graphics.print(trunc(txt, content_w - indent), p_x + p_pad_x + indent + 1, cy + 1)
            love.graphics.setColor(col[1], col[2], col[3], 0.97)
            love.graphics.print(trunc(txt, content_w - indent), p_x + p_pad_x + indent, cy)
          else
            love.graphics.setColor(col[1], col[2], col[3], 0.90)
            love.graphics.print(trunc(txt, content_w - indent), p_x + p_pad_x + indent, cy)
          end
          cy = cy + line_h
        end
      end

      if rows_hidden > 0 then
        local fade_h = 20
        local fade_y = clip_y - fade_h
        local steps = 7
        for i = 0, steps - 1 do
          love.graphics.setColor(bg[1], bg[2], bg[3], (i / steps) * 0.96)
          love.graphics.rectangle("fill", p_x + 1, fade_y + i * (fade_h / steps), p_w - 2, math.ceil(fade_h / steps) + 1)
        end
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        local qf = panel_font_small or font
        local more_txt = "+" .. rows_hidden .. " more"
        local mw = qf:getWidth(more_txt)
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.print(more_txt, p_x + p_w - mw - p_pad_x + 1, clip_y - small_text_h - 1)
        love.graphics.setColor(pg[1], pg[2], pg[3], 0.55 + 0.20 * pulse)
        love.graphics.print(more_txt, p_x + p_w - mw - p_pad_x, clip_y - small_text_h - 2)
        if panel_font_small then love.graphics.setFont(font) end
      end

      -- prune _card_first_seen for cards no longer in the panel
      for k in pairs(_card_first_seen) do
        if not seen_cards[k] then _card_first_seen[k] = nil end
      end
    end

    trace("IND: data rows done")
    if footer_h > 0 then
      local fy = p_y + total_h - footer_h
      local sep_cx = p_x + p_w / 2
      love.graphics.setColor(p[1], p[2], p[3], 0.18)
      love.graphics.line(p_x + p_pad_x + 4, fy, p_x + p_w - p_pad_x - 4, fy)
      love.graphics.setColor(p[1], p[2], p[3], 0.30 + 0.08 * pulse)
      love.graphics.line(sep_cx - 30, fy, sep_cx + 30, fy)
      love.graphics.setColor(pg[1], pg[2], pg[3], 0.35 + 0.12 * pulse)
      love.graphics.circle("fill", sep_cx, fy, 1.5)

      if footer_is_emote and footer_emote and footer_emote.img then
        local efw, efh = footer_emote.fw, footer_emote.fh
        if efw > 0 and efh > 0 then
          local emote_area_h = footer_h - 6
          local max_w = p_w - 20
          local scale = math.min(max_w / efw, emote_area_h / efh)
          local dw, dh = efw * scale, efh * scale
          local ix = p_x + (p_w - dw) / 2
          local iy = fy + (emote_area_h - dh) / 2 + 3
          love.graphics.setColor(pg[1], pg[2], pg[3], 0.08 + 0.05 * pulse)
          love.graphics.circle("fill", ix + dw / 2, iy + dh / 2, math.max(dw, dh) * 0.4)
          love.graphics.setColor(1, 1, 1, 0.97)
          if footer_emote.quads and footer_emote.n_frames > 1 then
            local frame_idx = math.floor(now * footer_emote.fps) % footer_emote.n_frames + 1
            love.graphics.draw(footer_emote.img, footer_emote.quads[frame_idx], ix, iy, 0, scale, scale)
          else
            love.graphics.draw(footer_emote.img, ix, iy, 0, scale, scale)
          end
        end
      elseif quip_display and quip_display ~= "" then
        if panel_font_small then love.graphics.setFont(panel_font_small) end
        local qf = panel_font_small or font
        local qt = trunc(quip_display, p_w - 24, qf)
        local qw = qf:getWidth(qt)
        local qx = p_x + (p_w - qw) / 2
        local qy = fy + (footer_h - small_text_h) / 2
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.print(qt, qx + 1, qy + 1)
        love.graphics.setColor(pg[1], pg[2], pg[3], 0.45 + 0.20 * pulse)
        love.graphics.print(qt, qx, qy)
        if panel_font_small then love.graphics.setFont(font) end
      end
    end
    if _right_panel_slide_frac > 0 then love.graphics.pop() end
  end

  if draw_buy_panel then draw_buy_panel() end

  trace("IND: footer done")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
  if prev_font then love.graphics.setFont(prev_font) end
  trace("IND: draw_neuro_indicator complete")
end

local function draw_login_animation()
  if not G or not G.NEURO.login_anim then trace("LOGIN: skip, no anim") return end
  trace("LOGIN: enter")
  local anim = G.NEURO.login_anim
  local now = (G.TIMERS and G.TIMERS.REAL) or (love.timer and love.timer.getTime()) or 0
  local elapsed = now - anim.start

  local PRE       = 0.08
  local CHAOS     = 0.65
  local HOLD      = 0.28
  local REVEAL    = 0.60
  local TEXT_SHOW = 1.80
  local FADE_OUT  = 0.40
  local TOTAL = PRE + CHAOS + HOLD + REVEAL + TEXT_SHOW + FADE_OUT

  if elapsed > TOTAL then G.NEURO.login_anim = nil; return end

  if not anim.palette_ready and elapsed >= PRE + CHAOS * 0.35 then
    anim.palette_ready = true
  end

  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()

  local function gh(a, b)
    local x = math.sin(a * 127.1 + b * 311.7 + 3.14159) * 43758.5453
    return x - math.floor(x)
  end
  local function gh2(a, b)
    local x = math.sin(a * 269.5 + b * 183.3 + 1.61803) * 57832.4391
    return x - math.floor(x)
  end

  local gi
  if elapsed < PRE then
    gi = (elapsed / PRE) * 0.28
  elseif elapsed < PRE + CHAOS then
    local t = (elapsed - PRE) / CHAOS
    if t < 0.08 then
      gi = 0.28 + (t / 0.08) * 0.72
    else
      gi = 1.0
    end
  elseif elapsed < PRE + CHAOS + HOLD then
    gi = (1.0 - (elapsed - PRE - CHAOS) / HOLD) * 0.22
  else
    gi = 0
  end
  gi = math.max(0, math.min(1, gi))

  local ba
  if elapsed < PRE then
    ba = (elapsed / PRE) * 0.45
  elseif elapsed < PRE + CHAOS then
    ba = 0.45 + ((elapsed - PRE) / CHAOS) * 0.55
  elseif elapsed < PRE + CHAOS + HOLD then
    ba = 1.0
  elseif elapsed < PRE + CHAOS + HOLD + REVEAL then
    ba = 1.0 - (elapsed - PRE - CHAOS - HOLD) / REVEAL
  else
    ba = 0
  end
  ba = math.max(0, math.min(1, ba))

  love.graphics.setColor(0, 0, 0, ba)
  love.graphics.rectangle("fill", 0, 0, sw, sh)

  if gi > 0.005 then
    local f20  = math.floor(now * 20)
    local f30  = math.floor(now * 30)
    local f50  = math.floor(now * 50)
    local f80  = math.floor(now * 80)
    local f12  = math.floor(now * 12)
    local f16  = math.floor(now * 16)
    local f22  = math.floor(now * 22)

    local step = gi > 0.80 and 2 or (gi > 0.50 and 3 or 5)
    love.graphics.setColor(0, 0, 0, 0.35 * gi)
    for sy = 0, sh - 1, step do
      love.graphics.rectangle("fill", 0, sy, sw, 1)
    end

    love.graphics.setColor(0.04, 0.04, 0.06, 0.18 * gi)
    for sx = 0, sw - 1, step do
      love.graphics.rectangle("fill", sx, 0, 1, sh)
    end

    local col_n = math.floor(gi * gi * 40)
    for i = 1, col_n do
      local cx = math.floor(gh(i,       f50) * sw)
      local cw = math.floor(gh(i + 0.1, f50) * 18) + 1
      local ch = math.floor(gh(i + 0.2, f50) * sh * 0.88) + 8
      local cy = math.floor(gh(i + 0.3, f50) * math.max(1, sh - ch))
      local r4 = gh(i + 0.4, f50)
      local g4 = gh(i + 0.5, f50)
      local b4 = gh(i + 0.6, f50)
      love.graphics.setColor(r4, g4, b4, gi * 0.65)
      love.graphics.rectangle("fill", cx, cy, cw, ch)
    end

    local row_n = math.floor(gi * gi * 45)
    for i = 1, row_n do
      local ry  = math.floor(gh(i,       f20) * sh)
      local rw  = math.floor(gh(i + 0.1, f20) * sw * 0.95) + 40
      local rx  = math.floor(gh(i + 0.2, f20) * math.max(1, sw - rw))
      local rh  = math.max(1, math.floor(gh(i + 0.3, f20) * 12) + 1)
      local br  = 0.35 + gh(i + 0.5, f20) * 0.60
      local hue = gh(i + 0.7, f20)
      love.graphics.setColor(
        math.min(1, br * (0.65 + hue * 0.35)),
        math.min(1, br * (0.65 + gh(i + 0.8, f20) * 0.35)),
        math.min(1, br * (0.85 + gh(i + 0.9, f20) * 0.15)),
        gi * 0.96)
      love.graphics.rectangle("fill", rx, ry, rw, rh)
    end

    if gi > 0.25 then
      local mosh_n = math.floor((gi - 0.25) / 0.75 * 28)
      for i = 1, mosh_n do
        local mx  = math.floor(gh2(i * 2,     f80) * sw)
        local my  = math.floor(gh2(i * 2 + 1, f80) * sh)
        local mw  = math.floor(gh2(i * 2 + 2, f80) * 200) + 12
        local mhh = math.floor(gh2(i * 2 + 3, f80) * 70)  + 5
        local hm  = gh2(i, f80)
        love.graphics.setColor(
          math.abs(math.sin(hm * 6.28318 + 0.000)),
          math.abs(math.sin(hm * 6.28318 + 2.094)),
          math.abs(math.sin(hm * 6.28318 + 4.189)),
          gi * 0.78)
        love.graphics.rectangle("fill", mx, my, mw, mhh)
      end
    end

    local nn = math.floor(gi * 140)
    for i = 1, nn do
      local nx = math.floor(gh(i,       f30 + 1111) * sw)
      local ny = math.floor(gh(i + 0.2, f30 + 1111) * sh)
      local nw = math.floor(gh(i + 0.4, f30 + 1111) * 28) + 1
      local nh = math.floor(gh(i + 0.6, f30 + 1111) * 8)  + 1
      local gr = 0.10 + gh(i + 0.8, f30 + 1111) * 0.88
      love.graphics.setColor(gr, gr * 0.95, gr, gi * 0.65)
      love.graphics.rectangle("fill", nx, ny, nw, nh)
    end

    local fringe = math.floor(gi * gi * 110)
    if fringe > 0 then
      love.graphics.setColor(1.0, 0.0, 0.06, gi * 0.42)
      love.graphics.rectangle("fill", 0, 0, fringe, sh)
      love.graphics.setColor(0.04, 0.12, 1.0, gi * 0.42)
      love.graphics.rectangle("fill", sw - fringe, 0, fringe, sh)
      love.graphics.setColor(0.0, 1.0, 0.08, gi * 0.18)
      love.graphics.rectangle("fill", math.floor(fringe / 2), 0, math.max(1, math.floor(fringe / 3)), sh)
    end

    if gi > 0.40 then
      for bi = 1, 3 do
        local band_y = math.floor(gh(bi * 3, f12) * sh)
        local band_h = math.floor(gi * 80) + 10
        local sep    = math.floor(gi * 22) + bi * 4
        love.graphics.setColor(1.0, 0.02, 0.02, gi * 0.16)
        love.graphics.rectangle("fill", 0, band_y - sep, sw, band_h)
        love.graphics.setColor(0.02, 0.02, 1.0, gi * 0.16)
        love.graphics.rectangle("fill", 0, band_y + sep, sw, band_h)
        love.graphics.setColor(0.02, 1.0, 0.40, gi * 0.07)
        love.graphics.rectangle("fill", 0, band_y,        sw, math.floor(band_h / 3))
      end
    end

    local speeds = { 38, 73, 119, 211 }
    local alphas = { 0.22, 0.15, 0.09, 0.05 }
    for ti = 1, 4 do
      local ty2 = math.floor((now * speeds[ti]) % sh)
      love.graphics.setColor(1, 1, 1, gi * alphas[ti])
      love.graphics.rectangle("fill", 0, ty2, sw, 2 + ti)
      love.graphics.setColor(0, 0, 0, gi * alphas[ti] * 0.60)
      love.graphics.rectangle("fill", 0, (ty2 + 7) % sh, sw, ti + 1)
    end

    if gi > 0.45 then
      local drop_n = math.floor((gi - 0.45) / 0.55 * 16)
      for i = 1, drop_n do
        local dx = math.floor(gh2(i * 5,     f80 + 555) * sw)
        local dw = math.floor(gh2(i * 5 + 1, f80 + 555) * 10) + 1
        local dr = gh2(i, f80 + 555)
        love.graphics.setColor(math.min(1, dr * 2), 1, dr * 0.80, gi * 0.60)
        love.graphics.rectangle("fill", dx, 0, dw, sh)
      end
    end

    if gi > 0.60 then
      local flicker = gh(9, f16)
      if flicker > 0.48 then
        local fi = (flicker - 0.48) / 0.52
        love.graphics.setColor(1, 0.85, 1, fi * fi * 0.38 * gi)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.80 then
      local sv = gh(1, f22)
      if sv > 0.68 then
        love.graphics.setColor(1, 1, 1, 0.60 * gi)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.93 then
      local sv2 = gh2(3, math.floor(now * 28))
      if sv2 > 0.82 then
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
      end
    end

    if gi > 0.70 then
      local seg_n = math.floor((gi - 0.70) / 0.30 * 6)
      for i = 1, seg_n do
        local sx2 = math.floor(gh(i * 11, f50 + 777) * sw)
        local sw2 = math.floor(sw / seg_n)
        local off = math.floor((gh(i, f50 + 777) - 0.5) * gi * 30)
        love.graphics.setColor(1, 1, 1, 0.08 * gi)
        love.graphics.rectangle("fill", sx2, off, sw2, sh)
      end
    end
  end

  local text_start = PRE + CHAOS + HOLD
  if elapsed >= text_start then
    local te = elapsed - text_start
    local full_text = "Hello " .. anim.name .. "!"
    local TYPE_DUR = 0.68
    local char_count = math.floor(math.min(1, te / TYPE_DUR) * #full_text)
    local display_text = full_text:sub(1, char_count)
    if char_count < #full_text then
      display_text = display_text .. (math.floor(now * 4) % 2 == 0 and "_" or " ")
    end

    local ta = 1.0
    if te < 0.20 then ta = te / 0.20 end
    local text_total = REVEAL + TEXT_SHOW + FADE_OUT
    if te > text_total - FADE_OUT then ta = math.max(0, (text_total - te) / FADE_OUT) end

    local p = pal()
    local panel_font, _ = get_panel_fonts()
    local prev_font = love.graphics.getFont()
    if panel_font then love.graphics.setFont(panel_font) end
    local f = love.graphics.getFont()
    local tw = f:getWidth(display_text)
    local th = f:getHeight()
    local cx = sw / 2 - tw / 2
    local cy2 = sh / 2 - th / 2

    love.graphics.setColor(0, 0, 0, 0.72 * ta)
    love.graphics.rectangle("fill", 0, sh / 2 - 48, sw, 96)

    love.graphics.setColor(p.PRIMARY[1], p.PRIMARY[2], p.PRIMARY[3], 0.22 * ta)
    love.graphics.rectangle("fill", 0, sh / 2 - 48, sw, 96)

    love.graphics.setColor(p.GLOW[1], p.GLOW[2], p.GLOW[3], 0.55 * ta)
    love.graphics.setLineWidth(2)
    love.graphics.line(0, sh / 2 - 48, sw, sh / 2 - 48)
    love.graphics.line(0, sh / 2 + 48, sw, sh / 2 + 48)

    love.graphics.setColor(p.GLOW[1] * 0.5, p.GLOW[2] * 0.5, p.GLOW[3] * 0.5, 0.20 * ta)
    love.graphics.line(0, sh / 2 - 44, sw, sh / 2 - 44)
    love.graphics.line(0, sh / 2 + 44, sw, sh / 2 + 44)
    love.graphics.setLineWidth(1)

    local pulse = 0.5 + 0.5 * math.sin(now * 5.5)
    local glow_r = math.min(1, p.GLOW[1] * 1.1)
    local glow_g = math.min(1, p.GLOW[2] * 1.1)
    local glow_b = math.min(1, p.GLOW[3] * 1.1)

    for radius = 4, 1, -1 do
      local ga = (0.08 - radius * 0.015) * (0.7 + 0.3 * pulse) * ta
      love.graphics.setColor(glow_r, glow_g, glow_b, ga)
      for dx = -radius, radius do
        for dy = -radius, radius do
          if math.abs(dx) == radius or math.abs(dy) == radius then
            love.graphics.print(display_text, cx + dx, cy2 + dy)
          end
        end
      end
    end

    love.graphics.setColor(1, 0.96, 1, 0.98 * ta)
    love.graphics.print(display_text, cx, cy2)

    if prev_font then love.graphics.setFont(prev_font) end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
end

local function draw_neuro_cookie()
  if not G or not G.NEURO.egg or not G.NEURO.egg.expires_at then
    trace("COOKIE: skip")
    return
  end
  trace("COOKIE: enter")
  if G.TIMERS and G.TIMERS.REAL and G.TIMERS.REAL > G.NEURO.egg.expires_at then
    G.NEURO.egg = nil
    return
  end
  if G.NEURO.egg.img == nil and G.NEURO.egg.img_tried ~= true then
    G.NEURO.egg.img_tried = true
    local ok, img = pcall(love.graphics.newImage, cookie_path())
    if ok then
      G.NEURO.egg.img = img
    else
      G.NEURO.egg.img = false
    end
  end

  local text = G.NEURO.egg.text or ""
  local y = (love.graphics.getHeight() * 0.5) - 20
  if G.NEURO.egg.img and G.NEURO.egg.img ~= false then
    local img = G.NEURO.egg.img
    local w, h = img:getWidth(), img:getHeight()
    local scale = math.min(love.graphics.getWidth() / (w * 6), love.graphics.getHeight() / (h * 6))
    local x = (love.graphics.getWidth() - w * scale) / 2
    y = (love.graphics.getHeight() - h * scale) / 2 - 40
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale)
    y = y + h * scale + 10
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(text, 0, y, love.graphics.getWidth(), "center")
end

local function setup_text_input()
  if not (G and G.FUNCS and G.FUNCS.text_input_key) then
    return
  end
  if G.NEURO.input_hooked then
    return
  end
  G.NEURO.input_hooked = true
  G.NEURO.egg_input = ""
  G.NEURO.input_buffer = ""

  local original_text_input_key = G.FUNCS.text_input_key
  G.FUNCS.text_input_key = function(args)
    local key = args and args.key or ""
    if key == "return" then
      local sanitized = NeuroFilter.sanitize(G.NEURO.input_buffer)
      if sanitized ~= G.NEURO.input_buffer then
        for i = 1, #G.NEURO.input_buffer do
          original_text_input_key({ key = "backspace" })
        end
        for i = 1, #sanitized do
          original_text_input_key({ key = sanitized:sub(i, i) })
        end
      end
      G.NEURO.input_buffer = ""
    elseif key == "backspace" then
      G.NEURO.input_buffer = G.NEURO.input_buffer:sub(1, math.max(0, #G.NEURO.input_buffer - 1))
    elseif key == "space" then
      G.NEURO.input_buffer = G.NEURO.input_buffer .. " "
    elseif #key == 1 then
      G.NEURO.input_buffer = G.NEURO.input_buffer .. key
    end
    if key == "return" then
      G.NEURO.egg_input = ""
    elseif key == "backspace" then
      G.NEURO.egg_input = G.NEURO.egg_input:sub(1, math.max(0, #G.NEURO.egg_input - 1))
    elseif #key == 1 then
      G.NEURO.egg_input = G.NEURO.egg_input .. key
    end
    local normalized = G.NEURO.egg_input:lower():gsub("%s+", ""):gsub("%-", "")
    if normalized == "neuro" or normalized == "neurosama" then
      local now = (G and G.TIMERS and G.TIMERS.REAL) or (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
      G.NEURO.egg = {
        expires_at = now + 3,
        text = "Nuero is a cutest little cookie"
      }
      G.NEURO.egg_input = ""
    end
    return original_text_input_key(args)
  end
end

local function setup_neuro_bridge()
  if not G then
    return
  end
  local enabled_env = os.getenv("NEURO_ENABLE")
  local ipc_dir = read_ipc_dir()
  if enabled_env then
    local lower = enabled_env:lower()
    if lower == "0" or lower == "false" or lower == "no" then
      return
    end
  end
  if not ipc_dir then
    if enabled_env then
      print("[neuro-game] NEURO_ENABLE is set but no IPC dir was found. Set NEURO_IPC_DIR or create neuro_ipc_dir.txt.")
    end
    return
  end
  write_ipc_marker(ipc_dir)
  if G.NEURO and G.NEURO.send_startup then
    return
  end
  G.NEURO = NeuroBridge:new({ game = "Balatro", enabled = true, fs_dir = ipc_dir })
  G.NEURO:set_state_provider(NeuroState.build)
  G.NEURO:set_state_name_provider(NeuroState.get_state_name)
  G.NEURO:set_message_handler(function(msg)
    NeuroDispatcher.route_message(msg, G.NEURO)
  end)
  G.NEURO:send_startup()
  mark_force_dirty()

  local state_name = NeuroState and NeuroState.get_state_name and NeuroState.get_state_name() or "MENU"
  local valid_action_names = NeuroActions.get_valid_actions_for_state(state_name)
  local all_actions = NeuroActions.get_static_actions()
  local filtered_actions = {}
  local valid_set = {}
  for _, name in ipairs(valid_action_names) do
    valid_set[name] = true
  end
  for _, action_def in ipairs(all_actions) do
    if valid_set[action_def.name] then
      table.insert(filtered_actions, action_def)
    end
  end
  G.NEURO:register_actions(filtered_actions)

  G.NEURO.ai_highlighted = setmetatable({}, {__mode = "k"})
  G.NEURO.state = nil
  G.NEURO.force_state = nil
  G.NEURO.force_inflight = false
  G.NEURO.last_force_fingerprint = nil
  if NEURO_PERSONA ~= "neuro" then
    G.NEURO.persona = NEURO_PERSONA
  else
    G.NEURO.persona = "hiyori"
  end
end

local function hook_game_over_screen()
  if G.NEURO.game_over_hooked then return end
  if not create_UIBox_game_over then return end
  G.NEURO.game_over_hooked = true

  local _orig_create_UIBox_game_over = create_UIBox_game_over
  create_UIBox_game_over = function()
    local go_msgs = get_game_over_messages()
    local msg = go_msgs[math.random(#go_msgs)]

    local _orig_localize = localize
    localize = function(key, ...)
      if key == "ph_game_over" then
        return msg
      end
      return _orig_localize(key, ...)
    end

    local saved_red = G.C.RED
    local accent = pal().ACCENT
    G.C.RED = { accent[1], accent[2], accent[3], accent[4] or 1 }

    local ok, t = pcall(_orig_create_UIBox_game_over)

    localize = _orig_localize
    G.C.RED = saved_red

    if not ok then
      return _orig_create_UIBox_game_over()
    end
    return t
  end
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
  local ok2, err2 = pcall(function()
    setup_text_input()
    setup_neuro_bridge()
    hook_game_over_screen()
  end)
  if not ok2 then
    print("[neuro-game] LOAD ERROR (neuro setup): " .. tostring(err2))
  end
  bridge_attempted = true
  neuro_log("love.load complete")
end

local original_love_update = love.update

love.update = function(dt)
  if G then
    local areas = {G.hand, G.jokers, G.consumeables, G.shop_jokers, G.shop_vouchers, G.shop_booster, G.pack_cards}
    for i = 1, #areas do
      if areas[i] and areas[i].cards == nil then
        areas[i].cards = {}
      end
    end
  end

  if _neuro_autotest then
    _neuro_autotest = false
    local tok, result = pcall(function() return require("test_deadlock").run() end)
    if not tok then
      print("[test] Error: " .. tostring(result))
      love.event.quit(1)
    else
      love.event.quit((result or 0) > 0 and 1 or 0)
    end
    return
  end

  local update_success, update_err = pcall(function()
    if original_love_update then
      original_love_update(dt)
    end
  end)

  if not update_success then
    local now = os.clock()
    local msg = tostring(update_err)
    if _game_err_cd <= 0 or msg ~= _game_err_last_msg then
      print("[neuro-game] Warning: Game update error: " .. msg)
      _game_err_last_msg = msg
      _game_err_cd = now + 5
    end
  else
    if _game_err_cd > 0 and os.clock() > _game_err_cd then
      _game_err_cd = 0
      _game_err_last_msg = nil
    end
  end

  if not _neuro_card_draw_hooked then
    local hok, herr = pcall(hook_card_draw)
    if not hok then
      print("[neuro-game] UPDATE ERROR (hook_card_draw): " .. tostring(herr))
      _neuro_card_draw_hooked = true
    end
  end

  if not bridge_attempted and G then
    local bok, berr = pcall(function()
      setup_text_input()
      setup_neuro_bridge()
    end)
    if not bok then
      print("[neuro-game] UPDATE ERROR (bridge setup): " .. tostring(berr))
    end
    bridge_attempted = true
  end

  if G and G.NEURO and G.NEURO.enabled and NeuroState then
    local neuro_success, neuro_err = pcall(function()
      G.NEURO:update(dt)
      Staging.update(dt)

      if G.FUNCS and NeuroState.get_state_name then
        local state_name = NeuroState.get_state_name()
        local state_changed = state_name ~= G.NEURO.state
        local prev_state = G.NEURO.state
        if state_changed then
          Staging.on_state_change()
          G.NEURO.reforce_count = 0
          G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
          neuro_state_changed_at = neuro_now()
          if state_name == "SHOP" and prev_state ~= "SHOP" then
            G.NEURO.shop_reroll_count = 0
          elseif prev_state == "SHOP" and state_name ~= "SHOP" then
            G.NEURO.shop_reroll_count = nil
          end
          if G.NEURO.in_run_setup and state_name ~= "SPLASH" and state_name ~= "MENU" and state_name ~= "RUN_SETUP" then
            G.NEURO.in_run_setup = nil
          end
          -- Clear stale cache globals that embed state-specific indices/hints
          G.NEURO.last_failed_action = nil
          if prev_state == "SELECTING_HAND" then
            G.NEURO.sim1_play = nil
            G.NEURO.dr_top = nil
          end
          local _PACK_STATES = {
            TAROT_PACK=true, PLANET_PACK=true, SPECTRAL_PACK=true,
            STANDARD_PACK=true, BUFFOON_PACK=true, SMODS_BOOSTER_OPENED=true,
          }
          if _PACK_STATES[prev_state] then
            G.NEURO.pack_best = nil
          end
          G.NEURO.state = state_name
          G.NEURO.last_force_fingerprint = nil
          if state_name == "SELECTING_HAND" and (prev_state == "SPLASH" or prev_state == "MENU" or prev_state == "RUN_SETUP") then
            ContextCompact.invalidate_cache()
            G.NEURO.rules_sent = nil
            G.NEURO.seed_pasted = nil
          end
          if state_name == "SELECTING_HAND" and prev_state == "BLIND_SELECT" then
            ContextCompact.invalidate_cache()
          end
          local valid_action_names = NeuroActions.get_valid_actions_for_state(state_name)
          G.NEURO:send_context(ContextCompact.build(state_name, valid_action_names), true)
          local all_actions = NeuroActions.get_static_actions()
          local filtered_actions = {}
          local valid_set = {}
          for _, name in ipairs(valid_action_names) do valid_set[name] = true end
          for _, action_def in ipairs(all_actions) do
            if valid_set[action_def.name] then
              table.insert(filtered_actions, action_def)
            end
          end
          if #filtered_actions > 0 then
            G.NEURO:register_actions(filtered_actions)
          end
          mark_force_dirty()
        end

        local now = neuro_now()
        update_joker_showcase(now)

        -- Auto-login: after 5s in MENU with no persona chosen, pick one automatically
        if G.NEURO.persona == "hiyori" and not G.NEURO.login_anim and not _auto_login_fired then
          if state_name == "MENU" then
            if not _menu_enter_t then _menu_enter_t = now end
            if now - _menu_enter_t >= 5.0 then
              _auto_login_fired = true
              _menu_enter_t = nil
              local picks = {"neuro", "evil"}
              local pick = picks[math.random(#picks)]
              local display_name = pick == "evil" and "Evil Neuro" or "Neuro-sama"
              G.NEURO.persona = pick
              G.NEURO.login_anim = { start = now, name = display_name, palette_ready = false }
            end
          elseif state_name ~= "SPLASH" then
            _menu_enter_t = nil
          end
        elseif G.NEURO.persona ~= "hiyori" then
          _auto_login_fired = false  -- reset so next run can auto-login again
        end

        if G.NEURO.force_inflight and G.NEURO.force_sent_at and
          (now - G.NEURO.force_sent_at) > FORCE_TIMEOUT_SECONDS then
          G.NEURO.last_force_fingerprint = nil
          clear_force_state()
          mark_force_dirty()
        end
        if state_changed and G.NEURO.force_inflight and G.NEURO.force_state ~= state_name then
          clear_force_state()
          mark_force_dirty()
        end

        if G.NEURO.force_dirty and G.NEURO.persona then
          if not G.NEURO.force_inflight and not Staging.is_busy() and neuro_can_act() then
            local dirty_at = G.NEURO.force_dirty_at or neuro_state_changed_at or 0
            if neuro_last_force_attempt_at > dirty_at then
              dirty_at = neuro_last_force_attempt_at
            end
            local _bp3 = G.pack_cards or G.booster_pack
            local pack_not_ready = (state_name == "SMODS_BOOSTER_OPENED" or (state_name:find("_PACK") ~= nil))
              and not (_bp3 and _bp3.cards and #_bp3.cards > 0)
            if (now - dirty_at) >= NEURO_FORCE_DEBOUNCE and not pack_not_ready then
              local force = NeuroDispatcher.get_force_for_state(state_name)
              if force then
                local wants_full_jokers = false
                if G.NEURO.last_action_name == "joker_info" or G.NEURO.last_action_name == "joker_strategy" then
                  local last_at = G.NEURO.last_action_at or 0
                  wants_full_jokers = (now - last_at) <= 2.5
                end

              local force_context = ContextCompact.build(state_name, force.actions, {
                full_jokers = wants_full_jokers,
                force_phase = true,
              })
              local force_fingerprint = build_force_fingerprint(state_name, force, force_context)
              if force_fingerprint ~= G.NEURO.last_force_fingerprint then
                G.NEURO.force_state = state_name
                G.NEURO.force_inflight = true
                G.NEURO.force_sent_at = now
                G.NEURO.force_action_names = force.actions
                G.NEURO.force_action_set = build_action_set(force.actions)
                G.NEURO.last_force_fingerprint = force_fingerprint
                neuro_last_force_attempt_at = now
                G.NEURO:force_actions(
                  force_context,
                  force.query,
                  force.actions,
                  { priority = "medium", ephemeral_context = true }
                )
                G.NEURO.force_dirty = false
              else
                -- fingerprint matched → context unchanged; keep dirty so we retry
                -- once the shop actually updates (delayed buy event).
                -- bump attempt time so debounce re-gates (avoid per-frame spam)
                neuro_last_force_attempt_at = now
              end
              end
            end
          end
        end
      end
    end)

    if not neuro_success then
      local err_str = tostring(neuro_err)
      if err_str ~= last_neuro_error then
        print("[neuro-game] Warning: Neuro update error: " .. err_str)
        last_neuro_error = err_str
        error_cooldown = 10
      elseif error_cooldown > 0 then
        error_cooldown = error_cooldown - 1
      end
    else
      last_neuro_error = nil
      error_cooldown = 0
    end
  end
end

local _persona_colors_applied = nil
local _palette_baseline = nil
local _palette_selftest_done = false

local REPALETTE_KEYS = {
  "RED", "BLUE", "PURPLE", "GREEN", "GOLD", "ORANGE", "YELLOW",
  "BLACK", "L_BLACK", "GREY", "WHITE", "JOKER_GREY",
  "MULT", "CHIPS", "XMULT", "UI_MULT", "UI_CHIPS",
  "MONEY", "BOOSTER", "EDITION", "DARK_EDITION",
  "IMPORTANT", "FILTER", "VOUCHER", "CHANCE", "PALE_GREEN",
  "ETERNAL", "PERISHABLE", "RENTAL",
}

local NESTED_KEYS = {
  BACKGROUND    = { "L", "D", "C" },
  BLIND         = { "Small", "Big", "Boss", "won" },
  DYN_UI        = { "MAIN", "DARK", "BOSS_MAIN", "BOSS_DARK", "BOSS_PALE" },
  UI            = { "TEXT_LIGHT", "TEXT_DARK", "TEXT_INACTIVE",
                    "BACKGROUND_LIGHT", "BACKGROUND_WHITE", "BACKGROUND_DARK",
                    "BACKGROUND_INACTIVE", "OUTLINE_LIGHT", "OUTLINE_LIGHT_TRANS",
                    "OUTLINE_DARK", "TRANSPARENT_LIGHT", "TRANSPARENT_DARK", "HOVER" },
  SET           = { "Default", "Enhanced", "Joker", "Tarot", "Planet", "Spectral", "Voucher" },
  SECONDARY_SET = { "Default", "Enhanced", "Joker", "Tarot", "Planet", "Spectral", "Voucher", "Edition" },
}

local function cc(c) return { c[1], c[2], c[3], c[4] } end

local function apply_color_inplace(target, source)
  if not target or not source or type(target) ~= "table" or type(source) ~= "table" then return end
  target[1] = source[1]
  target[2] = source[2]
  target[3] = source[3]
  if source[4] ~= nil then target[4] = source[4] end
end

local function snapshot_palette_baseline()
  if _palette_baseline or not (G and G.C) then return end
  local snap = { flat = {}, nested = {} }

  for _, k in ipairs(REPALETTE_KEYS) do
    if type(G.C[k]) == "table" then
      snap.flat[k] = cc(G.C[k])
    end
  end

  for tbl, subs in pairs(NESTED_KEYS) do
    if type(G.C[tbl]) == "table" then
      snap.nested[tbl] = {}
      for _, sk in ipairs(subs) do
        if type(G.C[tbl][sk]) == "table" then
          snap.nested[tbl][sk] = cc(G.C[tbl][sk])
        end
      end
    end
  end

  _palette_baseline = snap
end

local function resolve_persona_key(raw)
  if raw == "hiyori" or raw == "neuro" or raw == "evil" then
    return raw
  end
  return "neuro"
end

local function active_palette_key()
  local pk = resolve_persona_key((G and G.NEURO.persona) or NEURO_PERSONA)
  local state_name = NeuroState and NeuroState.get_state_name and NeuroState.get_state_name() or "MENU"
  local menuish = (state_name == "SPLASH" or state_name == "MENU" or state_name == "RUN_SETUP")

  if pk == "hiyori" and not menuish then
    pk = "neuro"
  end
  return pk
end

local HIYORI_COLORS = {
  RED         = { 0.35, 0.35, 0.35, 1 },
  BLUE        = { 0.40, 0.40, 0.40, 1 },
  PURPLE      = { 0.32, 0.32, 0.32, 1 },
  GREEN       = { 0.42, 0.42, 0.42, 1 },
  GOLD        = { 0.55, 0.55, 0.55, 1 },
  ORANGE      = { 0.45, 0.45, 0.45, 1 },
  YELLOW      = { 0.60, 0.60, 0.60, 1 },
  BLACK       = { 0.04, 0.04, 0.04, 1 },
  L_BLACK     = { 0.10, 0.10, 0.10, 1 },
  GREY        = { 0.35, 0.35, 0.35, 1 },
  WHITE       = { 0.80, 0.80, 0.80, 1 },
  JOKER_GREY  = { 0.50, 0.50, 0.50, 1 },
  MULT        = { 0.35, 0.35, 0.35, 1 },
  CHIPS       = { 0.40, 0.40, 0.40, 1 },
  XMULT       = { 0.30, 0.30, 0.30, 1 },
  UI_MULT     = { 0.35, 0.35, 0.35, 1 },
  UI_CHIPS    = { 0.40, 0.40, 0.40, 1 },
  MONEY       = { 0.55, 0.55, 0.55, 1 },
  BOOSTER     = { 0.30, 0.30, 0.30, 1 },
  EDITION     = { 0.65, 0.65, 0.65, 1 },
  DARK_EDITION= { 0.38, 0.38, 0.38, 1 },
  IMPORTANT   = { 0.50, 0.50, 0.50, 1 },
  FILTER      = { 0.50, 0.50, 0.50, 1 },
  VOUCHER     = { 0.35, 0.35, 0.35, 1 },
  CHANCE      = { 0.42, 0.42, 0.42, 1 },
  PALE_GREEN  = { 0.42, 0.42, 0.42, 1 },
  ETERNAL     = { 0.30, 0.30, 0.30, 1 },
  PERISHABLE  = { 0.32, 0.32, 0.32, 1 },
  RENTAL      = { 0.38, 0.38, 0.38, 1 },
  BACKGROUND  = {
    L = { 0.25, 0.25, 0.25, 1 },
    D = { 0.05, 0.05, 0.05, 1 },
    C = { 0.07, 0.07, 0.07, 1 },
  },
  BLIND = {
    Small = { 0.30, 0.30, 0.30, 1 },
    Big   = { 0.30, 0.30, 0.30, 1 },
    Boss  = { 0.25, 0.25, 0.25, 1 },
    won   = { 0.40, 0.40, 0.40, 1 },
  },
  DYN_UI = {
    MAIN      = { 0.08, 0.08, 0.08, 1 },
    DARK      = { 0.04, 0.04, 0.04, 1 },
    BOSS_MAIN = { 0.15, 0.15, 0.15, 1 },
    BOSS_DARK = { 0.10, 0.10, 0.10, 1 },
    BOSS_PALE = { 0.25, 0.25, 0.25, 1 },
  },
  UI = {
    TEXT_LIGHT       = { 0.80, 0.80, 0.80, 1 },
    TEXT_DARK        = { 0.20, 0.20, 0.20, 1 },
    TEXT_INACTIVE    = { 0.35, 0.35, 0.35, 0.60 },
    BACKGROUND_LIGHT = { 0.45, 0.45, 0.45, 1 },
    BACKGROUND_WHITE = { 0.70, 0.70, 0.70, 1 },
    BACKGROUND_DARK  = { 0.22, 0.22, 0.22, 1 },
    BACKGROUND_INACTIVE = { 0.18, 0.18, 0.18, 1 },
    OUTLINE_LIGHT    = { 0.50, 0.50, 0.50, 1 },
    OUTLINE_LIGHT_TRANS = { 0.50, 0.50, 0.50, 0.40 },
    OUTLINE_DARK     = { 0.22, 0.22, 0.22, 1 },
    TRANSPARENT_LIGHT = { 0.40, 0.40, 0.40, 0.13 },
    TRANSPARENT_DARK  = { 0.08, 0.08, 0.08, 0.13 },
    HOVER            = { 0.10, 0.10, 0.10, 0.33 },
  },
  SET = {
    Default  = { 0.50, 0.50, 0.50, 1 },
    Enhanced = { 0.50, 0.50, 0.50, 1 },
    Joker    = { 0.18, 0.18, 0.18, 1 },
    Tarot    = { 0.18, 0.18, 0.18, 1 },
    Planet   = { 0.18, 0.18, 0.18, 1 },
    Spectral = { 0.18, 0.18, 0.18, 1 },
    Voucher  = { 0.18, 0.18, 0.18, 1 },
  },
  SECONDARY_SET = {
    Default  = { 0.40, 0.40, 0.40, 1 },
    Enhanced = { 0.35, 0.35, 0.35, 1 },
    Joker    = { 0.35, 0.35, 0.35, 1 },
    Tarot    = { 0.32, 0.32, 0.32, 1 },
    Planet   = { 0.38, 0.38, 0.38, 1 },
    Spectral = { 0.35, 0.35, 0.35, 1 },
    Voucher  = { 0.40, 0.40, 0.40, 1 },
    Edition  = { 0.38, 0.38, 0.38, 1 },
  },
}

local NEURO_COLORS = {
  RED          = { 1.000, 0.302, 0.580, 1 },
  BLUE         = { 0.275, 0.847, 0.812, 1 },  -- turquoise accent
  PURPLE       = { 0.608, 0.447, 0.902, 1 },
  GREEN        = { 0.482, 0.769, 0.565, 1 },
  GOLD         = { 1.000, 0.843, 0.000, 1 },
  ORANGE       = { 1.000, 0.502, 0.400, 1 },
  YELLOW       = { 1.000, 0.878, 0.200, 1 },
  BLACK        = { 0.098, 0.086, 0.118, 1 },
  L_BLACK      = { 0.157, 0.141, 0.184, 1 },
  GREY         = { 0.490, 0.467, 0.557, 1 },
  WHITE        = { 0.984, 0.984, 1.000, 1 },
  JOKER_GREY   = { 0.745, 0.725, 0.800, 1 },

  MULT         = { 1.000, 0.651, 0.788, 1 },
  CHIPS        = { 0.275, 0.847, 0.812, 1 },  -- turquoise accent
  XMULT        = { 1.000, 0.302, 0.580, 1 },

  UI_MULT      = { 1.000, 0.651, 0.788, 1 },
  UI_CHIPS     = { 0.275, 0.847, 0.812, 1 },  -- turquoise accent
  MONEY        = { 1.000, 0.843, 0.000, 1 },
  BOOSTER      = { 1.000, 0.420, 0.540, 1 },  -- hot pink replaces cyan

  EDITION      = { 0.855, 0.835, 0.925, 1 },
  DARK_EDITION = { 0.530, 0.490, 0.680, 1 },
  IMPORTANT    = { 1.000, 0.302, 0.580, 1 },
  FILTER       = { 1.000, 0.302, 0.580, 1 },
  VOUCHER      = { 1.000, 0.843, 0.000, 1 },
  CHANCE       = { 1.000, 0.420, 0.540, 1 },  -- hot pink replaces cyan

  PALE_GREEN   = { 0.580, 0.820, 0.630, 1 },
  ETERNAL      = { 1.000, 0.302, 0.580, 1 },
  PERISHABLE   = { 0.590, 0.565, 0.690, 1 },
  RENTAL       = { 0.780, 0.750, 0.620, 1 },

  BACKGROUND = {
    L = { 1.000, 0.780, 0.855, 1 },
    D = { 0.980, 0.650, 0.780, 1 },  -- medium pink replaces light blue
    C = { 0.960, 0.580, 0.720, 1 },  -- deeper pink replaces blue-ish
  },

  BLIND = {
    Small = { 0.960, 0.580, 0.720, 1 },  -- pink
    Big   = { 1.000, 0.780, 0.855, 1 },
    Boss  = { 1.000, 0.302, 0.580, 1 },
    won   = { 1.000, 0.420, 0.540, 1 },  -- hot pink replaces cyan
  },

  DYN_UI = {
    MAIN      = { 0.118, 0.106, 0.145, 1 },
    DARK      = { 0.082, 0.075, 0.110, 1 },
    BOSS_MAIN = { 0.180, 0.160, 0.210, 1 },
    BOSS_DARK = { 0.120, 0.108, 0.155, 1 },
    BOSS_PALE = { 0.310, 0.290, 0.380, 1 },
  },

  UI = {
    TEXT_LIGHT          = { 0.984, 0.984, 1.000, 1 },
    TEXT_DARK           = { 0.098, 0.086, 0.118, 1 },
    TEXT_INACTIVE       = { 0.600, 0.575, 0.690, 0.66 },
    BACKGROUND_LIGHT    = { 1.000, 0.780, 0.855, 1 },
    BACKGROUND_WHITE    = { 0.984, 0.984, 1.000, 1 },
    BACKGROUND_DARK     = { 0.098, 0.086, 0.118, 1 },
    BACKGROUND_INACTIVE = { 0.170, 0.155, 0.200, 1 },
    OUTLINE_LIGHT       = { 1.000, 0.420, 0.540, 1 },  -- hot pink replaces cyan
    OUTLINE_LIGHT_TRANS = { 1.000, 0.420, 0.540, 0.45 },
    OUTLINE_DARK        = { 0.098, 0.086, 0.118, 1 },
    TRANSPARENT_LIGHT   = { 0.984, 0.984, 1.000, 0.18 },
    TRANSPARENT_DARK    = { 0.098, 0.086, 0.118, 0.16 },
    HOVER               = { 1.000, 0.420, 0.540, 0.28 },  -- hot pink replaces cyan
  },

  SET = {
    Default  = { 0.975, 0.960, 0.975, 1 },
    Enhanced = { 0.975, 0.960, 0.975, 1 },
    Joker    = { 0.140, 0.125, 0.165, 1 },
    Tarot    = { 0.140, 0.125, 0.165, 1 },
    Planet   = { 0.140, 0.125, 0.165, 1 },
    Spectral = { 0.140, 0.125, 0.165, 1 },
    Voucher  = { 0.140, 0.125, 0.165, 1 },
  },

  SECONDARY_SET = {
    Default  = { 1.000, 0.780, 0.855, 1 },
    Enhanced = { 1.000, 0.420, 0.540, 1 },  -- hot pink replaces cyan
    Joker    = { 1.000, 0.302, 0.580, 1 },
    Tarot    = { 0.608, 0.447, 0.902, 1 },
    Planet   = { 0.275, 0.847, 0.812, 1 },  -- turquoise accent
    Spectral = { 0.608, 0.447, 0.902, 1 },
    Voucher  = { 1.000, 0.843, 0.000, 1 },
    Edition  = { 0.275, 0.847, 0.812, 1 },  -- turquoise accent
  },
}

local EVIL_COLORS = {
  RED         = { 0.92, 0.18, 0.22, 1 },
  BLUE        = { 0.45, 0.28, 0.55, 1 },
  PURPLE      = { 0.62, 0.18, 0.35, 1 },
  GREEN       = { 0.35, 0.62, 0.38, 1 },
  GOLD        = { 0.88, 0.62, 0.20, 1 },
  ORANGE      = { 0.92, 0.48, 0.12, 1 },
  YELLOW      = { 0.92, 0.78, 0.25, 1 },
  BLACK       = { 0.14, 0.10, 0.12, 1 },
  L_BLACK     = { 0.24, 0.18, 0.20, 1 },
  GREY        = { 0.38, 0.30, 0.32, 1 },
  WHITE       = { 0.92, 0.88, 0.88, 1 },
  JOKER_GREY  = { 0.62, 0.55, 0.56, 1 },
  MULT        = { 0.92, 0.18, 0.22, 1 },
  CHIPS       = { 0.45, 0.28, 0.55, 1 },
  XMULT       = { 1.00, 0.22, 0.28, 1 },
  UI_MULT     = { 0.92, 0.18, 0.22, 1 },
  UI_CHIPS    = { 0.45, 0.28, 0.55, 1 },
  MONEY       = { 0.88, 0.62, 0.20, 1 },
  BOOSTER     = { 0.50, 0.22, 0.38, 1 },
  EDITION     = { 0.78, 0.68, 0.62, 1 },
  DARK_EDITION= { 0.52, 0.44, 0.42, 1 },
  IMPORTANT   = { 1.00, 0.50, 0.15, 1 },
  FILTER      = { 1.00, 0.50, 0.15, 1 },
  VOUCHER     = { 0.72, 0.38, 0.25, 1 },
  CHANCE      = { 0.35, 0.62, 0.38, 1 },
  PALE_GREEN  = { 0.30, 0.52, 0.35, 1 },
  ETERNAL     = { 0.68, 0.22, 0.38, 1 },
  PERISHABLE  = { 0.35, 0.25, 0.50, 1 },
  RENTAL      = { 0.62, 0.45, 0.22, 1 },
  BACKGROUND  = {
    L = { 0.80, 0.15, 0.12, 1 },
    D = { 0.12, 0.06, 0.08, 1 },
    C = { 0.15, 0.08, 0.10, 1 },
  },
  BLIND = {
    Small = { 0.55, 0.20, 0.25, 1 },
    Big   = { 0.55, 0.20, 0.25, 1 },
    Boss  = { 0.90, 0.15, 0.18, 1 },
    won   = { 0.40, 0.30, 0.32, 1 },
  },
  DYN_UI = {
    MAIN      = { 0.18, 0.10, 0.12, 1 },
    DARK      = { 0.12, 0.06, 0.08, 1 },
    BOSS_MAIN = { 0.50, 0.12, 0.15, 1 },
    BOSS_DARK = { 0.35, 0.08, 0.10, 1 },
    BOSS_PALE = { 0.60, 0.25, 0.28, 1 },
  },
  UI = {
    TEXT_LIGHT       = { 1.00, 0.92, 0.90, 1 },
    TEXT_DARK        = { 0.10, 0.05, 0.06, 1 },   -- near-black: 7:1+ contrast on all red panels
    TEXT_INACTIVE    = { 0.85, 0.68, 0.68, 0.55 }, -- light rose-cream: legible but clearly dimmed
    BACKGROUND_LIGHT = { 0.68, 0.30, 0.32, 1 },
    BACKGROUND_WHITE = { 0.92, 0.88, 0.88, 1 },
    BACKGROUND_DARK  = { 0.48, 0.20, 0.22, 1 },
    BACKGROUND_INACTIVE = { 0.38, 0.28, 0.28, 1 },
    OUTLINE_LIGHT    = { 0.75, 0.48, 0.45, 1 },
    OUTLINE_LIGHT_TRANS = { 0.75, 0.48, 0.45, 0.40 },
    OUTLINE_DARK     = { 0.48, 0.20, 0.22, 1 },
    TRANSPARENT_LIGHT = { 0.72, 0.40, 0.38, 0.13 },
    TRANSPARENT_DARK  = { 0.14, 0.08, 0.08, 0.13 },
    HOVER            = { 0.12, 0.04, 0.05, 0.33 },
  },
  SET = {
    Default  = { 0.65, 0.38, 0.38, 1 },
    Enhanced = { 0.65, 0.38, 0.38, 1 },
    Joker    = { 0.32, 0.16, 0.18, 1 },
    Tarot    = { 0.32, 0.16, 0.18, 1 },
    Planet   = { 0.32, 0.16, 0.18, 1 },
    Spectral = { 0.32, 0.16, 0.18, 1 },
    Voucher  = { 0.32, 0.16, 0.18, 1 },
  },
  SECONDARY_SET = {
    Default  = { 0.58, 0.32, 0.35, 1 },
    Enhanced = { 0.52, 0.28, 0.48, 1 },
    Joker    = { 0.52, 0.32, 0.38, 1 },
    Tarot    = { 0.62, 0.28, 0.52, 1 },
    Planet   = { 0.38, 0.52, 0.58, 1 },
    Spectral = { 0.38, 0.32, 0.68, 1 },
    Voucher  = { 0.90, 0.42, 0.20, 1 },
    Edition  = { 0.38, 0.58, 0.48, 1 },
  },
}

local function apply_palette(palette)
  if not palette or not G or not G.C or not _palette_baseline then return end
  for _, k in ipairs(REPALETTE_KEYS) do
    local src = palette[k] or (_palette_baseline.flat and _palette_baseline.flat[k])
    if src and G.C[k] then
      apply_color_inplace(G.C[k], src)
    end
  end
  for tbl, subs in pairs(NESTED_KEYS) do
    if G.C[tbl] then
      for _, sk in ipairs(subs) do
        local src = (palette[tbl] and palette[tbl][sk])
          or (_palette_baseline.nested and _palette_baseline.nested[tbl] and _palette_baseline.nested[tbl][sk])
        if src and G.C[tbl][sk] then
          apply_color_inplace(G.C[tbl][sk], src)
        end
      end
    end
  end
end

local function run_palette_selftest_once()
  if _palette_selftest_done or not (G and G.C) then return end
  if not _palette_baseline then return end

  local tests = {
    { name = "hiyori", palette = HIYORI_COLORS },
    { name = "neuro",  palette = NEURO_COLORS },
    { name = "evil",   palette = EVIL_COLORS },
  }

  local ok_count = 0
  for _, t in ipairs(tests) do
    local ok, err = pcall(function()
      apply_palette(t.palette)
    end)
    if ok then
      ok_count = ok_count + 1
    else
      print("[neuro-game] Palette selftest failed for " .. t.name .. ": " .. tostring(err))
    end
  end

  pcall(function() apply_palette({}) end)
  _palette_selftest_done = true
  neuro_log("Palette selftest:", ok_count, "/3 personas OK")
end

local original_love_draw = love.draw
local _draw_error_last = nil
local _draw_error_count = 0
love.draw = function(...)
  local pal_ok, pal_err = pcall(function()
    if G and G.C then
      snapshot_palette_baseline()
      run_palette_selftest_once()

      local pk = active_palette_key()
      local anim = G.NEURO.login_anim
      if anim and not anim.palette_ready then
        pk = resolve_persona_key(_persona_colors_applied or pk)
      end
      if pk ~= _persona_colors_applied then
        neuro_log("Palette ->", pk)
        _persona_colors_applied = pk

        local palette = (pk == "hiyori" and HIYORI_COLORS)
                     or (pk == "evil" and EVIL_COLORS)
                     or NEURO_COLORS

        trace("TRACE: apply_palette start pk=" .. tostring(pk))
        apply_palette(palette)
        trace("TRACE: apply_palette done")
      end
    end
  end)
  if not pal_ok then
    local e = tostring(pal_err)
    if e ~= _draw_error_last then
      print("[neuro-game] DRAW ERROR (palette): " .. e)
      _draw_error_last = e
      _draw_error_count = 0
    end
    _draw_error_count = _draw_error_count + 1
  end
  trace("TRACE: palette block done, calling original_love_draw")

  if original_love_draw then
    local base_ok, base_err = pcall(original_love_draw, ...)
    if not base_ok then
      local e = tostring(base_err)
      if e ~= _draw_error_last then
        print("[neuro-game] DRAW ERROR (base game draw): " .. e)
        _draw_error_last = e
        _draw_error_count = 0
      end
      _draw_error_count = _draw_error_count + 1
    end
  end
  trace("TRACE: original_love_draw done")

  trace("TRACE: calling draw_neuro_indicator")
  local ind_ok, ind_err = xpcall(draw_neuro_indicator, debug.traceback)
  if not ind_ok then
    print("[neuro-game] DRAW ERROR (indicator panel): " .. tostring(ind_err))
  end
  trace("TRACE: indicator done ok=" .. tostring(ind_ok))

  trace("TRACE: calling draw_neuro_cookie")
  local cookie_ok, cookie_err = xpcall(draw_neuro_cookie, debug.traceback)
  if not cookie_ok then
    print("[neuro-game] DRAW ERROR (cookie): " .. tostring(cookie_err))
  end
  trace("TRACE: cookie done ok=" .. tostring(cookie_ok))

  trace("TRACE: calling draw_login_animation")
  local login_ok, login_err = xpcall(draw_login_animation, debug.traceback)
  if not login_ok then
    print("[neuro-game] DRAW ERROR (login anim): " .. tostring(login_err))
  end
  trace("TRACE: login done ok=" .. tostring(login_ok))

  pcall(function()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
  end)
  trace("TRACE: love.draw frame complete")
end

local original_love_mousepressed = love.mousepressed
love.mousepressed = function(x, y, button, istouch, presses)
  local ok, err = pcall(function()
    local handled = false
    if not handled and original_love_mousepressed then
      return original_love_mousepressed(x, y, button, istouch, presses)
    end
  end)
  if not ok then
    print("[neuro-game] MOUSE ERROR: " .. tostring(err))
    if original_love_mousepressed then
      pcall(original_love_mousepressed, x, y, button, istouch, presses)
    end
  end
end

local original_love_keypressed = love.keypressed
love.keypressed = function(key, scancode, isrepeat)
  if key == "f8" then
    local tok, terr = pcall(function() require("test_deadlock").run() end)
    if not tok then print("[test] Error: " .. tostring(terr)) end
  end
  if original_love_keypressed then
    return original_love_keypressed(key, scancode, isrepeat)
  end
end
