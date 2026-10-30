local BridgeInit = {}

local NeuroBridge = require("core.bridge")
local NeuroState = require("core.state")
local NeuroDispatcher = require("core.dispatcher")
local NeuroActions = require("core.actions")
local NeuroFilter = require("core.filtered")
local Palette = require("render.palette")
local Paths = require("core.mod_paths")
local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")
local Config = require("core.config")
local Metrics = require("util.metrics")
local Lifecycle = require("core.neuro_lifecycle")

local _ipc_dir_missing_reported = false

local unpack_values = rawget(table, "unpack") or unpack

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

local function setup_text_input()
  if not (G and G.FUNCS and G.FUNCS.text_input_key and G.NEURO) or G.NEURO.input_hooked then return end
  G.NEURO.input_hooked = true
  G.NEURO.egg_input = ""
  G.NEURO.input_buffer = ""

  local original_text_input_key = G.FUNCS.text_input_key
  G.FUNCS.text_input_key = function(args)
    local key = args and args.key or ""
    if key == "return" then
      local current = G.NEURO.input_buffer
      local hook = G.CONTROLLER and G.CONTROLLER.text_input_hook
      local hc = hook and hook.config and hook.config.ref_table
      local text = type(hc) == "table" and hc.text or nil
      if type(text) == "table" and type(text.ref_table) == "table" and text.ref_value ~= nil
        and type(text.ref_table[text.ref_value]) == "string" then
        current = text.ref_table[text.ref_value]
      end
      local sanitized = NeuroFilter.sanitize(current)
      if sanitized ~= current then
        for _ = 1, #current do
          original_text_input_key({ key = "backspace" })
        end
        for i = 1, #sanitized do
          local ch = sanitized:sub(i, i)
          original_text_input_key({ key = ch == " " and "space" or ch })
        end
      end
      G.NEURO.input_buffer, G.NEURO.egg_input = "", ""
    elseif key == "backspace" then
      G.NEURO.input_buffer = G.NEURO.input_buffer:sub(1, -2)
      G.NEURO.egg_input = G.NEURO.egg_input:sub(1, -2)
    elseif key == "space" then
      G.NEURO.input_buffer = G.NEURO.input_buffer .. " "
    elseif #key == 1 then
      G.NEURO.input_buffer = G.NEURO.input_buffer .. key
      G.NEURO.egg_input = G.NEURO.egg_input .. key
    end
    local normalized = G.NEURO.egg_input:lower():gsub("%s+", ""):gsub("%-", "")
    if normalized == "neuro" or normalized == "neurosama" then
      local now = Utils.now()
      G.NEURO.egg = {
        expires_at = now + 3,
        text = "Nuero is a cutest little cookie"
      }
      G.NEURO.egg_input = ""
    end
    return original_text_input_key(args)
  end
end

function BridgeInit.retry_pending_reconnect()
  if not (G and G.NEURO) then return false end
  local bridge = G.NEURO
  if bridge._reconnect_pending == nil then return true end
  if not require("core.window").register_catalogue() then return false end
  bridge._reconnect_pending = nil
  bridge._bridge_init_complete = true
  return true
end

function BridgeInit.handle_transport_reconnect(transport_session)
  if not (G and G.NEURO and G.NEURO.send_startup) or transport_session == nil then return false end
  local session = tostring(transport_session)
  if session == "" then return false end
  local bridge = G.NEURO
  if tostring(bridge.transport_session) == session
      and (bridge._bridge_init_complete or bridge._reconnect_pending == session) then
    return BridgeInit.retry_pending_reconnect()
  end
  bridge.transport_session = session
  bridge._bridge_init_complete = nil
  bridge._reconnect_pending = session
  if bridge:send_startup({ reconnect = true }) == false then return false end
  pcall(require("core.dispatcher").reset_transport_state, "transport reconnected")
  Lifecycle.bump_run_generation("transport reconnected")
  Lifecycle.reconnect_context_delivery()
  pcall(function() require("core.orchestrator").reset_run_state() end)
  return BridgeInit.retry_pending_reconnect()
end

local function setup_neuro_bridge()
  if not G then return end
  local ipc_dir = Paths.read_ipc_dir()
  local lower = (os.getenv("NEURO_ENABLE") or ""):lower()
  if lower == "0" or lower == "false" or lower == "no" then return end
  if not ipc_dir then
    if not _ipc_dir_missing_reported then
      _ipc_dir_missing_reported = true
      Metrics.incr("ipc_dir_missing")
      print("[neuro-game] No IPC dir was found; nothing will reach Neuro. "
        .. "Set NEURO_IPC_DIR or create neuro_ipc_dir.txt.")
    end
    return
  end
  if G.SETTINGS then
    G.SETTINGS.tutorial_complete = true
    G.SETTINGS.tutorial_progress = nil
  end
  Paths.write_ipc_marker(ipc_dir)
  if G.NEURO and G.NEURO.send_startup and G.NEURO._bridge_init_complete then
    return
  end
  if not (G.NEURO and G.NEURO.send_startup) then
    G.NEURO = NeuroBridge:new({ game = "Balatro", enabled = true, fs_dir = ipc_dir })
    G.NEURO.run_generation = G.NEURO.run_generation or 0
    Lifecycle.reset_run_state()
    G.NEURO.persona = Config.get_raw("NEURO_PERSONA")
    G.NEURO.actions = NeuroActions
    G.NEURO.dispatcher = NeuroDispatcher
    G.NEURO:set_state_name_provider(NeuroState.get_state_name)
    G.NEURO:set_message_handler(function(msg)
      NeuroDispatcher.route_message(msg, G.NEURO)
    end)
  end
  if not G.NEURO._startup_complete then
    Lifecycle.reset_context_delivery()
    if G.NEURO:send_startup() == false then return false end
  end

  if not require("core.window").register_catalogue() then
    G.NEURO._bridge_init_complete = nil
    return false
  end
  G.NEURO._bridge_init_complete = true
  return true
end

local _seeded_unlocks_hooked = false
local function hook_seeded_unlocks()
  if _seeded_unlocks_hooked or not Utils.neuro_ready() then return end
  _seeded_unlocks_hooked = true
  for _, name in ipairs({ "unlock_card", "inc_career_stat", "win_game" }) do
    local orig = _G[name]
    if orig then
      _G[name] = function(...)
        if not (G and G.GAME and G.GAME.seeded) then return orig(...) end
        local prev = G.GAME.seeded
        G.GAME.seeded = nil
        local ok, r = pcall(orig, ...)
        G.GAME.seeded = prev
        if not ok then error(r) end
        return r
      end
    end
  end
end

local _installed_game_over = nil
local function hook_game_over_screen()
  if not Utils.neuro_ready() or not _G.create_UIBox_game_over or _G.create_UIBox_game_over == _installed_game_over then
    return
  end
  local _orig_create_UIBox_game_over = _G.create_UIBox_game_over
  _G.create_UIBox_game_over = function()
    local go_msgs = GAME_OVER_MESSAGES[(G and G.NEURO and G.NEURO.persona) or Config.get_raw("NEURO_PERSONA")]
      or GAME_OVER_MESSAGES.neuro
    local msg = go_msgs[math.random(#go_msgs)]

    local saved_red = G.C.RED
    local accent = Palette.pal().ACCENT

    local _orig_localize = _G.localize
    _G.localize = function(key, ...)
      if key == "ph_game_over" then
        return msg
      end
      return _orig_localize(key, ...)
    end
    G.C.RED = { accent[1], accent[2], accent[3], accent[4] or 1 }

    local ok, t = pcall(_orig_create_UIBox_game_over)

    _G.localize = _orig_localize
    G.C.RED = saved_red

    if not ok then
      local ok2, t2 = pcall(_orig_create_UIBox_game_over)
      if ok2 then return t2 end
      error(t)
    end
    return t
  end
  _installed_game_over = _G.create_UIBox_game_over
end

local _run_reset_hooked = false
local function hook_run_reset()
  if _run_reset_hooked or not (G and G.FUNCS) then return end
  local resetting, pending = false, false
  local function reset()
    Lifecycle.withdraw_open_force()
    Lifecycle.bump_run_generation("run restarted")
    Lifecycle.reset_run_state(true)
  end
  local function guarded(orig, before)
    return function(...)
      local args = { ... }
      local argc = select("#", ...)
      local results = { xpcall(function()
        if not resetting then
          resetting = true
          before()
        end
        return orig(unpack_values(args, 1, argc))
      end, debug.traceback) }
      resetting = false
      local ok = results[1]
      if not ok then
        pending = false
        error(results[2], 0)
      end
      return unpack_values(results, 2)
    end
  end
  for _, name in ipairs({ "start_run", "start_challenge_run" }) do
    if type(G.FUNCS[name]) == "function" then
      G.FUNCS[name] = guarded(G.FUNCS[name], function() reset(); pending = true end)
    end
  end
  local game = rawget(_G, "Game")
  local game_start_run = type(game) == "table" and game.start_run
  if type(game_start_run) == "function" then
    game.start_run = function(...)
      if pending then pending = false elseif not resetting then reset() end
      return game_start_run(...)
    end
  end
  _run_reset_hooked = true
end

local _blind_defeat_hooked = false
local function hook_blind_defeat()
  if _blind_defeat_hooked or type(_G.Blind) ~= "table" or type(_G.Blind.defeat) ~= "function" then return end
  _blind_defeat_hooked = true
  local orig = _G.Blind.defeat
  _G.Blind.defeat = function(self, ...)
    if self and G and G.NEURO then
      local result = GameFacts.round_outcome()
      G.NEURO.blind_reward_cache = (result and result.beaten) and (tonumber(self.dollars) or 0) or 0
      G.NEURO.blind_reward_round = tonumber(G.GAME and G.GAME.round) or 0
    end
    return orig(self, ...)
  end
end

local _love_quit_hooked = false
local function hook_love_quit()
  if _love_quit_hooked or not _G.love then return end
  _love_quit_hooked = true
  local original_love_quit = _G.love.quit
  _G.love.quit = function()
    if G and G.NEURO then
      pcall(G.NEURO.answer_owed_results, G.NEURO, nil, NeuroBridge.OWED_SHUTDOWN_MESSAGE)
      pcall(G.NEURO.unregister_all, G.NEURO)
      pcall(G.NEURO.flush_outbox, G.NEURO)
    end
    if original_love_quit then return original_love_quit() end
  end
end
if _G.NEURO_TEST then
  BridgeInit.hook_love_quit = hook_love_quit
  BridgeInit.hook_run_reset = hook_run_reset
end

function BridgeInit.run()
  if setup_neuro_bridge() == false then return false end
  setup_text_input()
  hook_seeded_unlocks()
  hook_game_over_screen()
  hook_run_reset()
  hook_blind_defeat()
  hook_love_quit()
  require("core.crash_guards").install_pack_area_guard()
  pcall(function() require("core.destruction_log").install() end)
  pcall(function() require("core.joker_recorder").install() end)
  pcall(function() require("core.joker_hits").install() end)
  if Config.bool("NEURO_CRASH_GUARDS") then
    pcall(function() require("core.crash_guards").install() end)
  end
  return true
end

return BridgeInit
