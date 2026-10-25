_G.NEURO_TEST = true

local Bridge = require("core.bridge")
local TmpWork = require("tests.tmp_workdir")
local check, done = require("tests.helpers").harness("stable-action-protocol")

local ipc_dir = TmpWork.open("stable_action_protocol")
local bridge = Bridge:new({ enabled = true, fs_dir = ipc_dir })
G = { NEURO = bridge, TIMERS = { REAL = 100 } }
bridge.run_generation = 1
bridge:send_startup()

local defs = {
  { name = "play_hand", description = "Play the selected hand.", schema = { type = "object" } },
  { name = "resolve_play", description = "Resolve the current play proposal.", schema = { type = "object" } },
}

local Execute = require("core.execute")



bridge.transport_session = "stable-action-protocol"
bridge.transport_epoch = 1
bridge.decision_serial = 1

local function offer(name, state, query)
  local names = { name }
  local sent = bridge:force_actions(state, query, names)
  if sent then require("tests.helpers").open_force(state, names) end
  return sent == true
end

local function frames()
  return require("tests.helpers").outbox_frames(ipc_dir .. "/" .. bridge.outbox_file, { must = true })
end

local function last_frame(command)
  local found
  for _, frame in ipairs(frames()) do
    if frame.command == command then found = frame end
  end
  return found
end

local function count_command(command)
  local count = 0
  for _, frame in ipairs(frames()) do
    if frame.command == command then count = count + 1 end
  end
  return count
end

check("a launch with no relay session to answer writes no startup_answer tag",
  count_command("neuro-bridge/startup_answer") == 0 and frames()[1].command == "startup")

check("canonical definitions register under stable names",
  bridge:register_actions(defs) == true
    and last_frame("actions/register").data.actions[1].name == "play_hand"
    and last_frame("actions/register").data.actions[2].name == "resolve_play")

local force_state = "SELECTING_HAND"
local force_query = "Choose the next hand action."
check("ordinary force uses the canonical action name",
  offer("play_hand", force_state, force_query))
local ordinary_force = last_frame("actions/force")
check("ordinary force keeps state, query, and canonical action",
  ordinary_force and ordinary_force.data.state == force_state
    and ordinary_force.data.query == force_query
    and ordinary_force.data.action_names[1] == "play_hand")
check("the force advertises exactly the requested canonical action",
  ordinary_force and #ordinary_force.data.action_names == 1)
check("the registered catalogue contains no generated force names",
  bridge._registered_sigs.play_hand ~= nil and bridge._registered_sigs.resolve_play ~= nil)
check("ordinary force does not manufacture an alias registration",
  count_command("actions/register") == 1)

bridge:set_message_handler(function(msg)
  Execute.answer(bridge, msg.data.id, msg.data.name, true, "accepted")
end)
bridge:_deliver_inbox_message({ command = "action", data = {
  id = "canonical-force-answer", name = "play_hand", data = "{}",
} })
local successful_result = last_frame("action/result")
check("successful result preserves the action id and status",
  successful_result and successful_result.data.id == "canonical-force-answer"
    and successful_result.data.success == true)
check("successful result preserves the handler message",
  successful_result and successful_result.data.message == "accepted")
check("a successful canonical force answer closes the force",
  bridge._force_open == nil and last_frame("action/result").data.id == "canonical-force-answer")
check("its answer unregistered the forced action before the result (ActionWindowResponse.cs:20)",
  bridge._registered_sigs.play_hand == nil and frames()[#frames() - 1].command == "actions/unregister")

check("a second canonical force can be offered once the next offer registers it",
  bridge:register_actions(defs) == true and offer("play_hand", force_state, force_query))
bridge:set_message_handler(function(msg)
  Execute.answer(bridge, msg.data.id, msg.data.name, false, "retry")
end)
bridge:_deliver_inbox_message({ command = "action", data = {
  id = "canonical-force-retry", name = "play_hand", data = "{}",
} })
check("a failed canonical answer leaves the force open for retry",
  bridge._force_open == true and bridge._registered_sigs.play_hand ~= nil)
local failed_result = last_frame("action/result")
check("failed canonical result preserves the retry action id",
  failed_result and failed_result.data.id == "canonical-force-retry"
    and failed_result.data.success == false)
check("failed canonical result carries the retry message",
  failed_result and failed_result.data.message == "retry")

bridge:reset_delivery_memory()
check("resetting delivery memory clears only the force lock",
  bridge._force_open == nil and bridge._registered_sigs.play_hand ~= nil)
check("resetting delivery memory requests full canonical registration",
  bridge:register_actions(defs) == true and count_command("actions/register") == 3)

local BridgeInit = require("core.bridge_init")
local Paths = require("core.mod_paths")
local old_read_ipc_dir = Paths.read_ipc_dir
Paths.read_ipc_dir = function() return ipc_dir end
G.GAME = { current_round = {} }
local Window = require("core.window")
local real_register = Window.register_catalogue
Window.register_catalogue = function() return bridge:register_actions(defs) end
local init_ok = BridgeInit.run()
Paths.read_ipc_dir = old_read_ipc_dir
check("bridge init completes with a registered canonical catalogue", init_ok == true)

local before_reconnect_count = #frames()
local reconnect_ok = BridgeInit.handle_transport_reconnect(2)
local reset_frames = frames()
local reconnect_start
for i = #reset_frames, 1, -1 do
  if reset_frames[i].command == "startup"
      and (i > before_reconnect_count or #reset_frames < before_reconnect_count) then
    reconnect_start = i
    break
  end
end
local reconnect_frames = {}
for i = reconnect_start or (#reset_frames + 1), #reset_frames do
  reconnect_frames[#reconnect_frames + 1] = reset_frames[i]
end
local restored
for _, frame in ipairs(reconnect_frames) do
  if frame.command == "actions/register" then restored = frame end
end
local answer_tag = reconnect_start and reset_frames[reconnect_start - 1]
check("the reconnect startup is written right after a tag naming the session it answers",
  answer_tag and answer_tag.command == "neuro-bridge/startup_answer"
    and answer_tag.transport_session == "2"
    and count_command("neuro-bridge/startup_answer") == 1)
check("reconnect startup replaces the old wire session",
  reconnect_ok == true and #reconnect_frames >= 2 and reconnect_frames[1].command == "startup")
check("reconnect restores canonical definitions before manual registration",
  restored and #restored.data.actions == #defs
    and restored.data.actions[1].name == "play_hand"
    and restored.data.actions[2].name == "resolve_play")

check("manual registration remains idempotent after reconnect restoration",
  bridge:register_actions(defs) == true)
Window.register_catalogue = real_register

TmpWork.close()
done()