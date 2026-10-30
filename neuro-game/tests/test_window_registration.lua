require("tests.stubs").setup({ love = "timers", localize = true })
local ES = require("tests.engine_cards").states()

-- Every board of the deadlock corpus, built as a window: registered = usable at build, and the force lists them all.
local check, done = require("tests.helpers").harness("window-registration")
local TmpWork = require("tests.tmp_workdir")
local ipc_dir = TmpWork.open("window_registration")
require("core.mod_paths").read_ipc_dir = function() return ipc_dir end
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 },
  GAME = { current_round = {} }, FUNCS = {}, STATES = ES, STATE = ES.MENU, SETTINGS = {} }

local Orchestrator = require("core.orchestrator")
Orchestrator._step_bridge_init()
assert(G.NEURO and G.NEURO._bridge_init_complete, "bridge init")
local bridge = G.NEURO
bridge.dispatcher, bridge.actions = require("core.dispatcher"), require("core.actions")

local Actions = require("core.actions")
local Window = require("core.window")
local Router = require("force.force_router")
local Validate = require("core.validate")
local TD = require("tests.test_deadlock")
local H = require("tests.helpers")
local Utils = require("util.utils")

local unusable, unregistered, unlisted, missing, boards = {}, {}, {}, {}, 0
for _, sc in ipairs(TD.SCENARIOS) do
  local ok, err = pcall(function()
    G.OVERLAY_MENU, G.screenwipe = nil, nil
    TD.apply_mock(sc.mock())
    H.in_scenario_state(sc)
    G.NEURO = bridge
    bridge.persona = bridge.persona or "neuro"
    bridge._registered_sigs, bridge._withdrawn_held, bridge._static_actions_registration_key = {}, nil, nil
    bridge._catalogue_wanted = nil
    Validate.reset_run_state()
    local state = require("core.state").get_state_name()
    local screen = Actions.screen_action_set(state)
    if not screen then return end
    boards = boards + 1
    local key = string.format("%s/%s", sc.state, sc.desc)
    local force = Router.get_force_for_state(state)
    Window.register_catalogue(force and force.actions or nil)
    for name in pairs(bridge._registered_sigs) do
      if not Actions.is_action_valid(name) then unusable[#unusable + 1] = key .. ": " .. name end
    end
    local listed = Utils.list_to_set(force and force.actions or {})
    for name in pairs(screen) do
      if Actions.is_action_valid(name) then
        if not bridge._registered_sigs[name] then unregistered[#unregistered + 1] = key .. ": " .. name end
        if force and not listed[name] and not Validate.settling(name) then unlisted[#unlisted + 1] = key .. ": " .. name end
      end
    end
    for _, name in ipairs(force and force.actions or {}) do
      if not bridge._registered_sigs[name] then missing[#missing + 1] = key .. ": " .. name end
    end
  end)
  if not ok then unusable[#unusable + 1] = sc.desc .. ": ERROR " .. tostring(err) end
end

check("the corpus covers the screens", boards >= 100, tostring(boards))
check("no action is registered on a board where it cannot be used (action_window.gd add_action)",
  #unusable == 0, table.concat(unusable, "; "))
check("every usable action of the screen is registered", #unregistered == 0, table.concat(unregistered, "; "))
check("every force lists every usable action of its window (action_window.gd _send_force)",
  #unlisted == 0, table.concat(unlisted, "; "))
check("every action a force lists is registered when it is sent", #missing == 0, table.concat(missing, "; "))

done()
