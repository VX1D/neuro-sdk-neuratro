-- Moves that leave the decision where it was are bounded per decision, including the run setup open/close round trip.
require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })
local check, done = require("tests.helpers").harness("decision-budget")
local Helpers = require("tests.helpers")
local LB = require("tests.fixtures.live_board")
local Actions = require("core.actions")
local Budget = require("core.decision_budget")
local Router = require("force.force_router")
local State = require("core.state")
local TxCache = require("core.bridge").tx

LB.load("MENU", "Normal: has G.GAME")
G.NEURO.persona = "evil"
G.TIMERS = G.TIMERS or { REAL = 100, TOTAL = 100 }
G.FUNCS, G.SETTINGS = G.FUNCS or {}, G.SETTINGS or {}
local MH = require("handlers.menu_handlers")
MH.open_new_run_setup = function() G.OVERLAY_MENU = Helpers.run_setup_overlay() end
MH.sync_run_select = function() end
G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
require("core.validate").reset_run_state()

local n = 0
local function send(name)
  n = n + 1
  local results = {}
  G.NEURO.send_action_result = Helpers.result_log(results, { "id", "ok", "message" }, true)
  G.NEURO.withdraw_actions = function() return true end
  G.TIMERS.REAL = G.TIMERS.REAL + 5
  Helpers.stage_registered(nil, { name })
  TxCache.open("db-" .. n, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, "db-" .. n, "{}"), G.NEURO)
  for _ = 1, 100 do G.TIMERS.REAL = G.TIMERS.REAL + 0.05; require("core.execute").step(G.TIMERS.REAL) end
  return results[1] or {}
end

local function listed(force, name)
  for _, member in ipairs((force or {}).actions or {}) do
    if member == name then return true end
  end
  return false
end

local round_trips = 0
for _ = 1, Budget.CAP + 2 do
  if not send("open_run_setup").ok or State.get_state_name() ~= "RUN_SETUP" then break end
  if not Actions.is_action_valid("exit_overlay_menu") then break end
  if not send("exit_overlay_menu").ok or State.get_state_name() ~= "MENU" then break end
  round_trips = round_trips + 1
end
check("open and close run setup round-trips stop at the cap", round_trips == Budget.CAP, tostring(round_trips))
local force = Router.get_force_for_state("RUN_SETUP")
check("closing run setup is then neither usable nor registrable",
  not Actions.is_action_valid("exit_overlay_menu") and Actions.registrable("exit_overlay_menu") == false)
check("and the run setup force drops it but still offers starting the run",
  not listed(force, "exit_overlay_menu") and listed(force, "start_run"),
  table.concat((force or {}).actions or {}, ","))
check("closing it in another overlay is not bounded by the run setup budget",
  not Budget.spent("exit_overlay_menu", "MENU"))
local names = Actions.get_action_names_for_state("RUN_SETUP")
local note, told = Budget.pending_note("RUN_SETUP", names)
check("the force says why", note == Budget.reason("exit_overlay_menu"), tostring(note))
told()
check("once", Budget.pending_note("RUN_SETUP", names) == nil)

require("core.validate").reset_run_state()
local Execute = require("core.execute")
local function answer(name, success, code)
  Execute.answer({ send_action_result = function() return true end }, "db-answer", name, success, "x", code)
end
for _, code in ipairs({ "TRANSITION_PENDING", "POLICY_ACKNOWLEDGED" }) do
  for _ = 1, Budget.CAP do answer("record_plan", true, code) end
end
answer("record_plan", true, nil)
check("a success that applied nothing (wait, acknowledged, owed) does not spend the budget",
  not Budget.spent("record_plan", "SHOP"))
for _ = 1, Budget.CAP do answer("record_plan", true, "ACTION_ACCEPTED") end
check("a non-progress tool is withheld after the cap", Budget.spent("record_plan", "SHOP"))
answer("open_run_setup", true, "ACTION_ACCEPTED")
check("navigating does not restore it", Budget.spent("record_plan", "SHOP"))
answer("buy_from_shop", true, "POLICY_ACKNOWLEDGED")
check("a success that was not an accepted move does not restore it", Budget.spent("record_plan", "SHOP"))
answer("buy_from_shop", true, "ACTION_ACCEPTED")
check("an accepted move that moves the game on does", not Budget.spent("record_plan", "SHOP"))
for _ = 1, Budget.CAP do answer("select_challenge", true, "ACTION_ACCEPTED") end
check("selecting a challenge is a menu selection bounded like selecting a deck", Budget.spent("select_challenge", "MENU"))
answer("select_deck", true, "ACTION_ACCEPTED")
check("and it does not reset the other menu selections", Budget.spent("select_challenge", "MENU"))

done()
