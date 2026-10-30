require("tests.stubs").setup({ love = "timers" })
local STATES = require("tests.engine_cards").states()
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100, TOTAL = 100 }, STATES = STATES }

local check, done = require("tests.helpers").harness("no saved-run continue")
local Helpers = require("tests.helpers")
local Bridge = require("core.bridge")
local TmpWork = require("tests.tmp_workdir")
local Registry = require("core.action_registry")
local MenuFlow = require("force.menu_flow")
local MenuHandlers = require("handlers.menu_handlers")
local Window = require("core.window")

local SAVE = { VERSION = "1.0.1", BACK = { name = "Red Deck", key = "b_red" },
  GAME = { round = 12, stake = 2, dollars = 30, round_resets = { ante = 4 } } }

local function menu_with_save(bridge)
  G.NEURO = bridge or G.NEURO
  G.NEURO.persona = "neuro"
  G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
  G.STATE = STATES.MENU
  G.STAGES = { MAIN_MENU = 1, RUN = 2 }
  G.STAGE = G.STAGES.MAIN_MENU
  G.SETTINGS = { paused = false, profile = 1 }
  G.CONTROLLER = { locks = {} }
  G.OVERLAY_MENU = nil
  G.SAVED_GAME = SAVE
  G.FUNCS = { can_continue = function(e)
    if e and e.config and e.config.func then e.config.func = nil; return true end
  end }
  G.GAME = { round = 0, stake = 1, dollars = 0, round_resets = { ante = 1 } }
end

local dir = TmpWork.open("no_saved_run_continue")
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
local bridge = Bridge:new({ enabled = true, fs_dir = dir })
menu_with_save(bridge)
bridge.run_generation = 1
bridge:send_startup()
bridge._bridge_init_complete = true

local function registers()
  return Helpers.outbox_frames(dir .. "/" .. bridge.outbox_file, { command = "actions/register" })
end

check("setup: the catalogue registers with a save present", Window.register_catalogue() == true)
local frames, names, leaked = registers(), {}, {}
for _, frame in ipairs(frames) do
  for _, action in ipairs(frame.data.actions or {}) do
    names[action.name] = true
    if tostring(action.name):find("continue", 1, true) then leaked[#leaked + 1] = action.name end
  end
end
check("the registered catalogue offers a new run through run setup", #frames > 0 and names.open_run_setup == true, #frames)
check("no actions/register frame carries continue_run", #leaked == 0, table.concat(leaked, ","))
check("the local registry holds no continue_run", Registry.get("continue_run") == nil)

local function subset(actions, allowed)
  local stray = {}
  for _, name in ipairs(actions or {}) do
    if not allowed[name] then stray[#stray + 1] = name end
  end
  return #stray == 0, table.concat(stray, ",")
end
local MENU_OK = { open_run_setup = true, select_deck = true, select_stake = true, copy_seed = true,
  select_challenge = true, start_challenge_run = true }
local SETUP_OK = { start_run = true, select_deck = true, select_stake = true, toggle_seeded_run = true,
  paste_seed = true, copy_seed = true, exit_overlay_menu = true }

menu_with_save()
local menu = MenuFlow.menu()
local ok, stray = subset(menu.actions, MENU_OK)
check("save present: the menu force offers only new-run paths", ok, stray)
check("save present: the menu force leads to open_run_setup", Helpers.has(menu.actions, "open_run_setup"),
  table.concat(menu.actions, ","))

menu_with_save()
G.OVERLAY_MENU = Helpers.run_setup_overlay()
G.SETTINGS.paused = true
local setup = MenuFlow.run_setup()
ok, stray = subset(setup and setup.actions, SETUP_OK)
check("save present: the run setup force offers only new-run paths", setup ~= nil and ok, stray)
check("save present: the run setup force offers start_run", setup ~= nil and Helpers.has(setup.actions, "start_run"),
  setup and table.concat(setup.actions, ","))

menu_with_save()
local tab
G.FUNCS.setup_run = function()
  tab = G.FUNCS.can_continue({ config = { func = true } }) and "Continue" or "New Run"
  G.SETTINGS.current_setup = tab
end
MenuHandlers.open_new_run_setup()
check("save present: run setup opens on the New Run tab", tab == "New Run" and G.SETTINGS.current_setup == "New Run",
  tostring(tab) .. "/" .. tostring(G.SETTINGS.current_setup))
check("the game's own can_continue is restored after opening", G.FUNCS.can_continue({ config = { func = true } }) == true)

os.execute("rm -rf '" .. dir .. "'")
TmpWork.close()
done()
