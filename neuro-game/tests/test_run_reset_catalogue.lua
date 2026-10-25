require("tests.stubs").setup({ love = "timers", localize = true })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("run-reset-catalogue")
local TmpWork = require("tests.tmp_workdir")
local ipc_dir = TmpWork.open("run_reset_catalogue")
require("core.mod_paths").read_ipc_dir = function() return ipc_dir end
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 }, GAME = { current_round = {} }, FUNCS = {},
  STATES = ES, STATE = ES.MENU, SETTINGS = {} }
local engine_runs = 0
G.FUNCS.start_run = function() engine_runs = engine_runs + 1 end

local Orchestrator = require("core.orchestrator")
local Lifecycle = require("core.neuro_lifecycle")
local Registry = require("core.action_registry")
local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }
Orchestrator._step_bridge_init()
assert(G.NEURO and G.NEURO._bridge_init_complete, "bridge init")
local bridge = G.NEURO

local function frames()
  return require("tests.helpers").outbox_frames(ipc_dir .. "/" .. bridge.outbox_file, { must = true })
end
local function since(mark)
  local all, out = frames(), {}
  for i = mark + 1, #all do out[#out + 1] = all[i] end
  return out
end
local function catalogue_frames(list)
  local out = {}
  for _, f in ipairs(list) do
    if f.command == "actions/register" then
      out[#out + 1] = "register:" .. #f.data.actions
    elseif f.command == "actions/unregister" then
      out[#out + 1] = "unregister:" .. table.concat(f.data.action_names, ",")
    end
  end
  return out
end
local function registered_count()
  local n = 0
  for _ in pairs(bridge._registered_sigs or {}) do n = n + 1 end
  return n
end

local full = registered_count()
check("the boot registered the whole catalogue", full >= 20, tostring(full))

do
  local mark = #frames()
  Lifecycle.reset_run_state()
  require("core.window").register_catalogue()
  local changes = catalogue_frames(since(mark))
  check("a new run with no force open leaves the catalogue alone", #changes == 0,
    table.concat(changes, " | "))
  check("and every action is still registered and accepted",
    registered_count() == full and Registry.is_registered("play_hand"), tostring(registered_count()))
end

do
  G.NEURO.force_window = { names = { "play_hand", "discard_hand" }, phase = Window.FORCED }
  local mark = #frames()
  Lifecycle.reset_run_state()
  require("core.window").register_catalogue()
  local changes = catalogue_frames(since(mark))
  check("an open force from the old run is cancelled by withdrawing exactly its actions",
    changes[1] == "unregister:play_hand,discard_hand" or changes[1] == "unregister:discard_hand,play_hand",
    table.concat(changes, " | "))
  check("and they stay off until a force offers them again (README.md:27)", #changes == 1,
    table.concat(changes, " | "))
  check("leaving the rest of the catalogue registered",
    registered_count() == full - 2 and not Registry.is_registered("play_hand"), tostring(registered_count()))
end

for _, case in ipairs({
  { "an open force's whole offer", function()
    G.NEURO.force_window = { names = { "select_deck", "open_run_setup" }, phase = Window.FORCED }
  end, { "open_run_setup", "select_deck" } },
}) do
  local label, arrange, want = case[1], case[2], case[3]
  arrange()
  local mark = #frames()
  local runs = engine_runs
  G.FUNCS.start_run(nil, { stake = 1 })
  local withdrawn = {}
  for _, f in ipairs(since(mark)) do
    if f.command == "actions/unregister" then
      for _, n in ipairs(f.data.action_names) do withdrawn[#withdrawn + 1] = n end
    end
  end
  table.sort(withdrawn)
  check("a restart through start_run withdraws " .. label .. " of the old run",
    engine_runs == runs + 1 and table.concat(withdrawn, ",") == table.concat(want, ","),
    table.concat(withdrawn, ","))
  require("core.window").register_catalogue()
end

do
  require("core.window").reset()
  bridge:withdraw_actions({ "choose_persona" })
  local mark = #frames()
  require("core.window").register_catalogue()
  check("a catalogue sync leaves a withdrawn disposable action withdrawn",
    #catalogue_frames(since(mark)) == 0 and bridge._registered_sigs.choose_persona == nil,
    table.concat(catalogue_frames(since(mark)), " | "))
  for _ = 1, 20 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.5; G.TIMERS.TOTAL = G.TIMERS.REAL
    pcall(Orchestrator.update, 0.5)
  end
  local after, register_at, force_at = since(mark), nil, nil
  for i, f in ipairs(after) do
    if f.command == "actions/register" and not register_at then register_at = i end
    if f.command == "actions/force" and not force_at then force_at = i end
  end
  check("the next force that offers it registers it first",
    register_at ~= nil and force_at ~= nil and register_at < force_at
      and #after[register_at].data.actions == 1
      and after[register_at].data.actions[1].name == "choose_persona",
    table.concat(catalogue_frames(after), " | "))
end

do
  bridge:withdraw_actions({ "start_run" })
  bridge:send_startup({ reconnect = true })
  require("core.window").register_catalogue()
  check("a new startup brings the whole catalogue back",
    bridge._registered_sigs.start_run ~= nil and registered_count() == full, tostring(registered_count()))
end

TmpWork.close()
done()
