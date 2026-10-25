require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("hold-confirmation-transport")
local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Window = require("core.window")
local TxCache = require("core.bridge").tx
local Helpers = require("tests.helpers")
local TmpWork = require("tests.tmp_workdir")

local ipc_dir = TmpWork.open("hold_confirmation_transport")
os.execute("rm -rf " .. ipc_dir)
os.execute("mkdir -p " .. ipc_dir)

G = {
  TIMERS = { REAL = 100 },
  STATE_COMPLETE = true,
  GAME = { dollars = 3, current_round = {} },
  FUNCS = {},
  shop = {},
  jokers = { cards = {} },
}
Helpers.in_engine_state("SHOP")

local bridge = Bridge:new({ enabled = true, fs_dir = ipc_dir })
G.NEURO = bridge
bridge.run_generation = 1
bridge.transport_session = "hold-confirmation"
bridge.transport_epoch = 1
bridge.decision_serial = 1
bridge.state = "SHOP"
bridge.shop_visit_epoch = 1
bridge.shop_entry_dollars = 14
bridge:send_startup()
Helpers.stage_registered(nil, { "leave_shop" })

local offered = { "leave_shop" }
local function arm(opts)
  return bridge:register_actions({
    { name = "leave_shop", description = "Exit the shop and continue the run.", schema = { type = "object" } },
  }) == true and bridge:force_actions("SHOP", "Leave the shop.", offered, opts) == true
    and Helpers.open_force("SHOP", offered) ~= nil
end
check("the shop force can be armed and written", arm())

local id = "hold-confirmation-1"
check("the held action is admitted to the result ledger",
  TxCache.open(id, "leave_shop", G.TIMERS.REAL) == true)
bridge.is_transition_cooldown = function() return false end
require("core.validate").reset_run_state()
Dispatcher.handle_message({
  command = "action",
  data = { id = id, name = "leave_shop", data = "{}" },
}, bridge)

local result
local force_count = 0
for _, frame in ipairs(Helpers.outbox_frames(ipc_dir .. "/" .. bridge.outbox_file, { must = true })) do
  if frame.command == "actions/force" then force_count = force_count + 1 end
  if frame.command == "action/result" and frame.data.id == id then result = frame.data end
end

check("the hold is an SDK terminal acknowledgement",
  result and result.success == true
    and type(result.message) == "string",
  result and tostring(result.message))
check("hold settlement closes both force lifecycles and unregisters the offer",
  bridge._force_open == nil and Window.current() == nil and bridge._registered_sigs.leave_shop == nil)

check("the next shop force can be offered exactly once",
  arm({ confirmation_proposal_ref = "hold-proposal" }) and force_count + 1 == 2)

G.NEURO.llm_paused = true
local paused_id = "hold-paused-queued"
check("the paused action is booked", TxCache.open(paused_id, "leave_shop", G.TIMERS.REAL) == true)
bridge._append = function() return 0 end
Dispatcher.handle_message({
  command = "action",
  data = { id = paused_id, name = "leave_shop", data = "{}" },
}, bridge)
check("a queued terminal answer settles both lifecycles at send time",
  bridge._force_open == nil and Window.current() == nil)
bridge._append = nil
bridge:flush_outbox()
G.NEURO.llm_paused = nil

check("successor force can be armed after the settlement", arm())
local stale_id = "hold-stale-result"
check("stale result is admitted to the ledger", TxCache.open(stale_id, "leave_shop", G.TIMERS.REAL) == true)
bridge:send_action_result(stale_id, true, "old")
check("stale delayed result cannot close the successor",
  bridge._force_open == true and Window.current() ~= nil)
done()
