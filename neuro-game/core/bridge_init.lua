local BridgeInit = {}

local NeuroBridge = require("core.bridge")
local NeuroState = require("core.state")
local NeuroDispatcher = require("core.dispatcher")
local NeuroActions = require("core.actions")
local NeuroFilter = require("core.filtered")
local Palette = require("render.palette")
local DebugStats = require("render.debug_stats")
local Paths = require("core.mod_paths")
local Utils = require("util.utils")
local Config = require("core.config")
local ContextDelivery = require("core.context_delivery")

local neuro_now = Utils.now

local _mark_force_dirty = function() end
local _register_valid_actions = function(_state_name) end

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
  local pk = (G and G.NEURO and G.NEURO.persona) or Config.get_raw("NEURO_PERSONA")
  if pk ~= "evil" and pk ~= "neuro" then
    pk = "neuro"
  end
  return GAME_OVER_MESSAGES[pk] or GAME_OVER_MESSAGES.neuro
end

local function setup_text_input()
  if not (G and G.FUNCS and G.FUNCS.text_input_key and G.NEURO) then
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
      local now = neuro_now()
      G.NEURO.egg = {
        expires_at = now + 3,
        text = "Nuero is a cutest little cookie"
      }
      G.NEURO.egg_input = ""
    end
    return original_text_input_key(args)
  end
end

local function init_neuro_fields()
  require("core.neuro_lifecycle").reset_run_state()
  G.NEURO.ai_highlighted    = setmetatable({}, { __mode = "k" })
  G.NEURO.ai_glow           = setmetatable({}, { __mode = "k" })
  G.NEURO.seed_pasted       = nil
  G.NEURO.login_anim        = nil
  G.NEURO.game_over_hooked  = nil
  G.NEURO.persona           = Config.get_raw("NEURO_PERSONA")
  G.NEURO.actions           = NeuroActions
  G.NEURO.dispatcher        = NeuroDispatcher
end

local UNANSWERED_PHASE = "prepared"

function BridgeInit._recover_interrupted_action(bridge, entry)
  if not (bridge and type(entry) == "table") then return false end
  local id = entry.id
  if id ~= nil then id = tostring(id) end
  local name = tostring(entry.name or "action")
  local answered = false
  if entry.phase == UNANSWERED_PHASE and type(id) == "string" and id ~= "" then
    -- SPECIFICATION.md:167 -- an action left without a result blocks Neuro forever
    bridge:send_action_result(id, true,
      "The game restarted before your action '" .. name
        .. "' could run. It was not executed and the current game state does not include it.")
    answered = true
  end
  bridge.recovered_action_journal = entry
  require("core.force_state").rearm()
  local context
  if entry.phase == UNANSWERED_PHASE then
    context = "Recovered an action '" .. name
      .. "' that had not executed before restart. Re-check the current game state and choose again."
  else
    context = "Recovered an accepted action '" .. name
      .. "' at phase " .. tostring(entry.phase)
      .. "; its execution outcome is unknown and it was not replayed. Inspect the current game state and choose again."
  end
  ContextDelivery.event_at("recovered_action:" .. tostring(id or "unknown") .. ":"
    .. tostring(entry.phase or "unknown"), ContextDelivery.here(), context)
  return answered
end

local function setup_neuro_bridge()
  if not G then
    return
  end
  local enabled_env = os.getenv("NEURO_ENABLE")
  local ipc_dir = Paths.read_ipc_dir()
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
    init_neuro_fields()
    G.NEURO._startup_interrupted_action = G.NEURO:recover_action_journal()
    G.NEURO:set_state_name_provider(NeuroState.get_state_name)
    G.NEURO:set_message_handler(function(msg)
      NeuroDispatcher.route_message(msg, G.NEURO)
    end)
  end
  local interrupted_action = G.NEURO._startup_interrupted_action
  if not G.NEURO._startup_complete then
    ContextDelivery.reset_transport()
    if G.NEURO:send_startup() == false then return false end
  end
  BridgeInit._recover_interrupted_action(G.NEURO, interrupted_action)
  G.NEURO._startup_interrupted_action = nil
  _mark_force_dirty()

  local state_name = NeuroState and NeuroState.get_state_name and NeuroState.get_state_name() or "MENU"
  _register_valid_actions(state_name)
  G.NEURO._bridge_init_complete = true
  return true
end

local _seeded_unlocks_hooked = false
local function hook_seeded_unlocks()
  if _seeded_unlocks_hooked or not Utils.neuro_ready() then return end
  _seeded_unlocks_hooked = true
  if _G.unlock_card then
    local _orig = _G.unlock_card
    _G.unlock_card = function(card)
      if not (G and G.GAME and G.GAME.seeded) then return _orig(card) end
      local prev = G.GAME.seeded
      G.GAME.seeded = nil
      local ok, r = pcall(_orig, card)
      G.GAME.seeded = prev
      if not ok then error(r) end
      return r
    end
  end
  if _G.inc_career_stat then
    local _orig = _G.inc_career_stat
    _G.inc_career_stat = function(stat, mod)
      if not (G and G.GAME and G.GAME.seeded) then return _orig(stat, mod) end
      local prev = G.GAME.seeded
      G.GAME.seeded = nil
      local ok, r = pcall(_orig, stat, mod)
      G.GAME.seeded = prev
      if not ok then error(r) end
      return r
    end
  end
  if _G.win_game then
    local _orig = _G.win_game
    _G.win_game = function()
      if not (G and G.GAME and G.GAME.seeded) then return _orig() end
      local prev = G.GAME.seeded
      G.GAME.seeded = nil
      local ok, r = pcall(_orig)
      G.GAME.seeded = prev
      if not ok then error(r) end
      return r
    end
  end
end

local _installed_game_over = nil
local function hook_game_over_screen()
  if not Utils.neuro_ready() then return end
  if G.NEURO.game_over_hooked then return end
  if not _G.create_UIBox_game_over then return end
  if _G.create_UIBox_game_over == _installed_game_over then
    -- The wrapper is still installed; re-wrapping would stack another layer every time the
    -- guard is cleared.
    G.NEURO.game_over_hooked = true
    return
  end
  G.NEURO.game_over_hooked = true

  local _orig_create_UIBox_game_over = _G.create_UIBox_game_over
  _G.create_UIBox_game_over = function()
    local go_msgs = get_game_over_messages()
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
  if _run_reset_hooked or not (G and G.FUNCS and type(G.FUNCS.start_run) == "function") then return end
  _run_reset_hooked = true
  local orig = G.FUNCS.start_run
  G.FUNCS.start_run = function(...)
    require("core.neuro_lifecycle").reset_run_state()
    return orig(...)
  end
end

local _blind_defeat_hooked = false
local function hook_blind_defeat()
  if _blind_defeat_hooked or type(_G.Blind) ~= "table" or type(_G.Blind.defeat) ~= "function" then return end
  _blind_defeat_hooked = true
  local orig = _G.Blind.defeat
  _G.Blind.defeat = function(self, ...)
    if self and G and G.NEURO then
      local cleared = (tonumber(G.GAME and G.GAME.chips) or 0) >= (tonumber(self.chips) or 0)
      G.NEURO.blind_reward_cache = cleared and (tonumber(self.dollars) or 0) or 0
      G.NEURO.blind_reward_round = tonumber(G.GAME and G.GAME.round) or 0
    end
    return orig(self, ...)
  end
end

local _love_quit_hooked = false
local function hook_love_quit()
  if _love_quit_hooked then return end
  if not _G.love then return end
  _love_quit_hooked = true
  local original_love_quit = _G.love.quit
  _G.love.quit = function()
    if G and G.NEURO then
      pcall(function()
        -- SPECIFICATION.md:165-167: a shutdown with actions in flight is the mod's last chance to pay
        -- them, and it is the only chance a conforming transport gives it.
        if type(G.NEURO.answer_owed_results) == "function" then
          G.NEURO:answer_owed_results(nil, NeuroBridge.OWED_SHUTDOWN_MESSAGE)
        end
      end)
      pcall(function()
        if type(G.NEURO._outbox_flush) == "function" then G.NEURO:_outbox_flush() end
      end)
      pcall(function() require("util.metrics").flush(true) end)
      pcall(function()
        if type(G.NEURO.unregister_all) == "function" then
          G.NEURO:unregister_all()
        end
      end)
    end
    if original_love_quit then
      return original_love_quit()
    end
    return nil
  end
end
if _G.NEURO_TEST then
  BridgeInit.hook_love_quit = hook_love_quit
end

function BridgeInit.run(deps)
  deps = deps or {}
  _mark_force_dirty = deps.mark_force_dirty or _mark_force_dirty
  _register_valid_actions = deps.register_valid_actions or _register_valid_actions
  if setup_neuro_bridge() == false then return false end
  setup_text_input()
  hook_seeded_unlocks()
  hook_game_over_screen()
  hook_run_reset()
  hook_blind_defeat()
  hook_love_quit()
  require("core.crash_guards").install_pack_area_guard()
  if Config.bool("NEURO_CRASH_GUARDS") then
    pcall(function() require("core.crash_guards").install() end)
  end
  DebugStats.setup()
  return true
end

return BridgeInit
