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
local dotenv = require("util.dotenv")

local neuro_now = Utils.now

local NEURO_PERSONA, _persona_explicit = dotenv.normalize_persona(dotenv.get("NEURO_PERSONA"))
local NEURO_PERSONA_FORCE = _persona_explicit and NEURO_PERSONA or nil

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
  local pk = (G and G.NEURO and G.NEURO.persona) or NEURO_PERSONA
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
  G.NEURO.rules_sent        = nil
  G.NEURO.seed_pasted       = nil
  G.NEURO.login_anim        = nil
  G.NEURO.game_over_hooked  = nil
  G.NEURO.persona           = NEURO_PERSONA_FORCE or "hiyori"
  G.NEURO.actions           = NeuroActions
  G.NEURO.dispatcher        = NeuroDispatcher
end

local function setup_neuro_bridge()
  if not G then
    return
  end
  if G.SETTINGS then
    G.SETTINGS.tutorial_complete = true
    G.SETTINGS.tutorial_progress = nil
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
  Paths.write_ipc_marker(ipc_dir)
  if G.NEURO and G.NEURO.send_startup then
    return
  end
  G.NEURO = NeuroBridge:new({ game = "Balatro", enabled = true, fs_dir = ipc_dir })
  init_neuro_fields()
  G.NEURO:set_state_provider(NeuroState.build)
  G.NEURO:set_state_name_provider(NeuroState.get_state_name)
  G.NEURO:set_message_handler(function(msg)
    NeuroDispatcher.route_message(msg, G.NEURO)
  end)
  G.NEURO:send_startup()
  _mark_force_dirty()

  local state_name = NeuroState and NeuroState.get_state_name and NeuroState.get_state_name() or "MENU"
  _register_valid_actions(state_name)
end

local _seeded_unlocks_hooked = false
local function hook_seeded_unlocks()
  -- guard: a second run would nest the pcall wrappers indefinitely
  if _seeded_unlocks_hooked then return end
  _seeded_unlocks_hooked = true
  if _G.unlock_card then
    local _orig = _G.unlock_card
    _G.unlock_card = function(card)
      if not (G and G.GAME and G.GAME.seeded) then return _orig(card) end
      local prev = G.GAME.seeded   -- restore whatever it was, not a hardcoded `true`
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

local function hook_game_over_screen()
  if not Utils.neuro_ready() then return end
  if G.NEURO.game_over_hooked then return end
  if not _G.create_UIBox_game_over then return end
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
end

-- the bridge is a process singleton, so clear run-scoped history when a new run starts or it carries over
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

-- setup_text_input must run after setup_neuro_bridge (fresh G.NEURO) or first keystroke crashes on nil input_buffer
function BridgeInit.run(deps)
  deps = deps or {}
  _mark_force_dirty = deps.mark_force_dirty or _mark_force_dirty
  _register_valid_actions = deps.register_valid_actions or _register_valid_actions
  setup_neuro_bridge()
  setup_text_input()
  hook_seeded_unlocks()
  hook_game_over_screen()
  hook_run_reset()
  DebugStats.setup()
end

return BridgeInit
