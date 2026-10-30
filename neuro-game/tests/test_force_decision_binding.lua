-- A force lives only as long as its decision; a reconnect between screens re-registers the last screen's set at once.
require("tests.stubs").setup({ love = "timers", localize = true })
local H = require("tests.helpers")
local check, done = H.harness("force-decision-binding")
local Window = require("core.window")
local Execute = require("core.execute")

H.base_G()
H.selecting_hand_env({ time = 100 })
G.NEURO.enabled, G.NEURO.persona = true, "neuro"
local unreg = {}
G.NEURO.withdraw_actions = function(_, names) unreg[#unreg + 1] = table.concat(names, ","); return true end
G.NEURO.send_action_result = function() return true end

H.open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
Execute.answer(G.NEURO, "off-1", "buy_from_shop", false, "Not on this screen.", "ACTION_UNAVAILABLE")
check("a refused action outside the open force does not arm the refusal re-ask clock (SPECIFICATION.md:188)",
  Window.current() and Window.current().answered_at == nil)
G.TIMERS.REAL = G.TIMERS.REAL + 31
Window.step("SELECTING_HAND")
check("so the force outlives the 30 s refusal clock", Window.current() ~= nil and #unreg == 0, tostring(#unreg))
Execute.answer(G.NEURO, "in-1", "play_hand", false, "Index 9 is out of range.", "INVALID_SELECTION")
check("a refused member arms it", Window.current() and Window.current().answered_at ~= nil)

G.NEURO.llm_paused = true
G.STATE = G.STATES.HAND_PLAYED
Window.step("HAND_PLAYED")
check("a hand played without her withdraws the force at HAND_PLAYED, though it has no screen of its own",
  Window.current() == nil and #unreg == 1 and unreg[1]:find("play_hand", 1, true) ~= nil, tostring(unreg[1]))

local ES = require("tests.engine_cards").states()
local ipc_dir = require("tests.tmp_workdir").open("force_decision_binding")
require("core.mod_paths").read_ipc_dir = function() return ipc_dir end
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 },
  GAME = { current_round = {} }, FUNCS = {}, STATES = ES, STATE = ES.MENU, SETTINGS = {} }
require("core.orchestrator")._step_bridge_init()
G.STATE = ES.BLIND_SELECT
Window.register_catalogue()
local before = {}
for name in pairs(G.NEURO._registered_sigs) do before[#before + 1] = name end
table.sort(before)
G.STATE = ES.HAND_PLAYED
require("core.bridge_init").handle_transport_reconnect("77")
local after = {}
for name in pairs(G.NEURO._registered_sigs) do after[#after + 1] = name end
table.sort(after)
check("a reconnect in a transitional state re-registers the last screen's set at once (BEST_PRACTICES.md:44)",
  #before > 0 and table.concat(after, ",") == table.concat(before, ","),
  table.concat(before, ",") .. " / " .. table.concat(after, ","))

done()
