_G.NEURO_TEST = true

G = { NEURO = { run_generation = 3 } }
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local Config = require("core.config")
local Protocol = require("core.bridge").wire
local Bridge = require("core.bridge")
local TxCache = require("core.bridge").tx
local json = require("util.neuro_json")
local Dispatcher = require("core.dispatcher")
local Utils = require("util.utils")

local check, done = require("tests.helpers").harness("bridge_register_reset")


local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("bridge_register_reset")
local ACTIONS = { { name = "play_hand", description = "play", schema = { type = "object" } } }

local function fresh_bridge() return require("tests.helpers").fs_bridge(IPC_DIR) end

local function outbox_commands(bridge)
  return require("tests.helpers").outbox_frames(IPC_DIR .. "/" .. bridge.outbox_file)
end

local function count_command(bridge, command)
  local n = 0
  for _, msg in ipairs(outbox_commands(bridge)) do
    if msg.command == command then n = n + 1 end
  end
  return n
end

local function count_in_session(bridge, command)
  local frames = outbox_commands(bridge)
  local start_at = #frames + 1
  for i = #frames, 1, -1 do
    if frames[i].command == "startup" then start_at = i break end
  end
  local n = 0
  for i = start_at, #frames do
    if frames[i].command == command then n = n + 1 end
  end
  return n
end

local function append_inbox(bridge, line)
  local f = io.open(IPC_DIR .. "/" .. bridge.inbox_file, "ab")
  f:write(line .. "\n")
  f:close()
end

do
  local b = fresh_bridge()
  G.NEURO = b
  G.TIMERS = { REAL = 100 }
  b.run_generation = 1
  b.decision_serial = 7
  b.transport_session = "canonical-session"
  b.transport_epoch = 1
  b:send_startup()
  b:register_actions({ { name = "leave_shop", description = "leave", schema = { type = "object" } } })
  check("a registered canonical action can be forced directly",
    b:force_actions("SHOP", "Choose", { "leave_shop" }) == true)
  require("tests.helpers").open_force("SHOP", { "leave_shop" })
  local frames = outbox_commands(b)
  local action_name
  for _, frame in ipairs(frames) do
    if frame.command == "actions/force" then action_name = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg)
    require("core.execute").answer(b, msg.data.id, msg.data.name, true, "done")
  end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "canonical-answer", name = action_name, data = "{}",
  } })
  frames = outbox_commands(b)
  local result_at
  for i, frame in ipairs(frames) do
    if frame.command == "action/result"
        and frame.data.id == "canonical-answer" then result_at = i end
  end
  check("a force answer uses the registered canonical action",
    action_name == "leave_shop" and result_at ~= nil,
    tostring(action_name) .. "/" .. tostring(result_at))
  check("the canonical force closes after its successful result, its offer unregistered",
    b._registered_sigs.leave_shop == nil and b._force_open == nil)
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions({
    { name = "cash_out", description = "Call cash_out to continue.", schema = { type = "object" } },
  })
  check("a canonical cash-out force is accepted",
    b:force_actions("State cash out", "Your move: choose cash out.", { "cash_out" }) == true)
  local register, force
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/register" then register = frame end
    if frame.command == "actions/force" then force = frame end
  end
  local action_name = force and force.data.action_names[1]
  check("force query remains prose while state uses the canonical action",
    action_name == "cash_out"
      and force.data.query == "Your move: choose cash out.",
    force and force.data.query)
  check("force state and definition use the canonical action",
    action_name and force.data.state == "State cash out"
      and register.data.actions[1].name == "cash_out"
      and register.data.actions[1].description == "Call cash_out to continue.",
    tostring(action_name))
end

do
  local b = fresh_bridge()
  local malformed = {
    name = "nested_bad",
    description = "Bad nested schema",
    schema = {
      type = "object",
      properties = {
        payload = { type = "array", items = { type = "not-a-json-type" } },
      },
    },
  }
  check("nested-invalid schema is rejected before the Lua catalogue shadow changes",
    b:register_actions({ malformed }) == false
      and b._registered_sigs.nested_bad == nil)
  check("nested-invalid schema cannot create a phantom force",
    b:force_actions("SELECTING_HAND", "Choose", { "nested_bad" }) == false
      and count_command(b, "actions/force") == 0)
end

do
  local defs = {
    { name = "play_hand", description = "play", schema = { type = "object" } },
    { name = "discard_hand", description = "discard", schema = { type = "object" } },
  }
  local b = fresh_bridge()
  G.NEURO = b
  G.TIMERS = { REAL = 100 }
  b.run_generation = 1
  b.decision_serial = 8
  b.transport_session = "sibling-session"
  b.transport_epoch = 1
  b:register_actions(defs)
  check("sibling fixture puts the force on the wire",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand", "discard_hand" }) == true)
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  local offered
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then offered = frame.data.action_names end
  end
  b:set_message_handler(function(msg)
    require("core.execute").answer(b, msg.data.id, msg.data.name, true, "done")
  end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "sibling-close", name = offered[1], data = "{}",
  } })
  local removed = {}
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do removed[name] = true end
    end
  end
  check("successful canonical force answer unregisters the whole offer and closes the force",
    removed.play_hand and removed.discard_hand and b._registered_sigs[offered[1]] == nil and b._force_open == nil)
end
do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions({
    { name = "cash_out", description = "cash", schema = { type = "object" } },
  })
  check("reconnect fixture opens a canonical force",
    b:force_actions("ROUND_EVAL", "Choose", { "cash_out" }) == true)
  local action_name
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then action_name = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg) Dispatcher.route_message(msg, b) end)
  b:_deliver_inbox_message({ command = "neuro-bridge/reregister_all", transport_session = 2 })
  check("reregister_all resets the canonical force lock",
    action_name == "cash_out" and b._force_open == nil, tostring(action_name))
end
do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions(ACTIONS)
  b:force_actions("SELECTING_HAND", "Choose", { "play_hand" })
  local action_name
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then action_name = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg) b:send_action_result(msg.data.id, false, "try again") end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "force-retry", name = action_name, data = "{}",
  } })
  local removed = false
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do
        if name == action_name then removed = true end
      end
    end
  end
  check("success=false preserves the canonical force for the SDK retry",
    not removed and b._force_open == true and b._registered_sigs[action_name] ~= nil)
end


do
  local b = fresh_bridge()
  G.NEURO = b
  G.TIMERS = { REAL = 500 }
  b.run_generation = 10
  b:send_startup()
  b:register_actions(ACTIONS)
  check("run retirement fixture sends the old force",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand" }) == true)
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })

  b._append = function() return 0 end
  local saved_love = _G.love
  _G.love = { timer = { getTime = function() return G.TIMERS.REAL end } }
  require("core.neuro_lifecycle").reset_run_state()
  _G.love = saved_love
  check("run reset ends the old run's force window",
    require("core.window").current() == nil)
  check("the old force is retired into the outbox FIFO instead of blocking the new run",
    b._force_open == nil and #b._fifo >= 1, tostring(b._force_open) .. "/" .. #b._fifo)

  b._append = nil
  b:register_actions(ACTIONS)
  check("the first force in the new run follows the buffered retirement and is admitted",
    b:force_actions("SELECTING_HAND", "Choose again", { "play_hand" }) == true)
  local seen_unregister, force_count, ordered = false, 0, false
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" then seen_unregister = true end
    if frame.command == "actions/force" then
      force_count = force_count + 1
      if force_count == 2 then ordered = seen_unregister end
    end
  end
  check("the SDK sees an unregister before the successor force",
    force_count == 2 and ordered, tostring(force_count) .. "/" .. tostring(ordered))
end

do
  local b = fresh_bridge()
  b:send_startup()
  TxCache.reset()
  TxCache.open("oversized-wire-result", "play_hand", 0)
  local sent = b:send_action_result(
    "oversized-wire-result", true, string.rep("x", Bridge.MAX_OUTBOUND_LINE_BYTES + 1))
  local result
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "action/result" then result = frame end
  end
  check("a result beyond the frame bound is replaced by bounded terminal text",
    sent == true and result and type(result.data.message) == "string"
      and #result.data.message < 1024,
    tostring(sent) .. "/" .. tostring(result and result.data.message and #result.data.message))
  TxCache.reset()
end

do
  local b = fresh_bridge()
  b.enabled = false
  check("a disabled register is rejected without advancing the catalogue shadow",
    b:register_actions(ACTIONS) == false
      and not b._registered_sigs.play_hand and b._last_register_key == nil
      and next(b._registered_sigs) == nil)
  b.enabled = true
  check("the rejected registration is retried after enable",
    b:register_actions(ACTIONS) == true and b._registered_sigs.play_hand ~= nil
      and count_command(b, "actions/register") == 1)

  check("force boundary rejects an empty action list",
    b:force_actions("SELECTING_HAND", "Choose", {}) == false)
  check("force boundary rejects names absent from the delivered catalogue",
    b:force_actions("SELECTING_HAND", "Choose", { "discard_hand" }) == false)
  check("force boundary accepts a registered non-empty action set",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand" }) == true
      and count_command(b, "actions/force") == 1)
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions(ACTIONS)
  b:withdraw_actions({ "play_hand" })
  local before = count_command(b, "actions/force")
  check("force refuses an explicitly withdrawn action",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand" }) == false)
  check("force refusal does not resurrect a withdrawn action",
    b._registered_sigs.play_hand == nil
      and count_command(b, "actions/force") == before)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:register_actions(ACTIONS)
  check("identical register within one session is deduped to one frame",
    count_command(b, "actions/register") == 1, count_command(b, "actions/register"))

  TxCache.store("dead-session-id", true, "old session")
  b:send_startup()
  check("send_startup clears settled action ids from the dead SDK session",
    TxCache.get("dead-session-id") == nil)
  check("send_startup clears _last_register_key", b._last_register_key == nil,
    tostring(b._last_register_key))
  check("send_startup clears _registered_sigs",
    type(b._registered_sigs) == "table" and next(b._registered_sigs) == nil)
  b:register_actions(ACTIONS)
  check("register after send_startup reaches the outbox again",
    count_in_session(b, "actions/register") == 1, count_in_session(b, "actions/register"))
  check("send_startup does not leave stale signatures behind (no unregister frame)",
    count_in_session(b, "actions/unregister") == 0, count_in_session(b, "actions/unregister"))
  check("the current startup frame opens the live session's segment",
    count_in_session(b, "startup") == 1, count_in_session(b, "startup"))
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:send_startup()
  b:register_actions({ { name = "select_blind", description = "pick", schema = { type = "object" } } })
  check("a different action set after send_startup unregisters nothing from the dead session",
    count_in_session(b, "actions/unregister") == 0, count_in_session(b, "actions/unregister"))
  check("the new session registers its own set",
    count_in_session(b, "actions/register") == 1, count_in_session(b, "actions/register"))
end
do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:send_context("hello", false)
  b:send(Protocol.result("live-1", true, "ok"))
  check("a healthy transport buffers nothing, so a hard kill has nothing to lose",
    #b._fifo == 0 and b:is_transport_saturated() == false, #b._fifo)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  local seen = 0
  b:set_message_handler(function(msg)
    if msg.command == "neuro-bridge/reregister_all" then
      seen = seen + 1
      b:register_actions(ACTIONS)
    end
  end)
  append_inbox(b, '{"command":"neuro-bridge/reregister_all"}')
  b:poll_inbox()
  check("reregister_all reached the message handler", seen == 1, seen)
  check("reregister_all does not re-emit an identical action set",
    count_command(b, "actions/register") == 1, count_command(b, "actions/register"))
  check("reregister_all does not fabricate an unregister",
    count_command(b, "actions/unregister") == 0, count_command(b, "actions/unregister"))
  check("reregister_all keeps the signature cache",
    b._registered_sigs and b._registered_sigs["play_hand"] ~= nil)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:withdraw_actions({ "play_hand" })
  b:register_actions(ACTIONS)
  check("withdrawal then re-register emits both frames",
    count_command(b, "actions/unregister") == 1 and count_command(b, "actions/register") == 2,
    count_command(b, "actions/unregister") .. "/" .. count_command(b, "actions/register"))
end

do
  local expected = { "session_id", "run_generation", "seq", "reason_code", "transport_session" }
  check("TRANSPORT_FIELDS length", #Protocol.TRANSPORT_FIELDS == #expected, #Protocol.TRANSPORT_FIELDS)
  for i, field in ipairs(expected) do
    check("TRANSPORT_FIELDS[" .. i .. "] == " .. field, Protocol.TRANSPORT_FIELDS[i] == field,
      tostring(Protocol.TRANSPORT_FIELDS[i]))
  end
end

do
  local RELAY_SRC = "../neuro-bridge-rs/src"
  local function read_relay(name)
    local f = io.open(RELAY_SRC .. "/" .. name, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
  end
  local wire_src = read_relay("wire.rs")
  check("bridge source reachable for the wire contract", wire_src ~= nil)
  if wire_src then
    local top = {}
    for field in (wire_src:match('for key in %[([^%]]+)%]') or ""):gmatch('"([^"]+)"') do
      top[#top + 1] = field
    end
    local relay_keys, relay_order = {}, {}
    local keys_body = wire_src:match("fn data_keys%(command: &str%).-\n}\n") or ""
    for command, list in keys_body:gmatch('"([^"]+)"%s*=>%s*&%[(.-)%]') do
      local fields = {}
      for field in list:gmatch('"([^"]+)"') do fields[#fields + 1] = field end
      relay_keys[command] = fields
      relay_order[#relay_order + 1] = command
    end
    local result_fields = relay_keys[Protocol.COMMANDS.RESULT] or {}
    check("mod WIRE_FIELDS matches the bridge top-level whitelist",
      table.concat(top, ",") == table.concat(Protocol.WIRE_FIELDS, ","),
      table.concat(top, ",") .. " vs " .. table.concat(Protocol.WIRE_FIELDS, ","))
    check("mod RESULT_DATA_FIELDS matches the bridge action/result whitelist",
      table.concat(result_fields, ",") == table.concat(Protocol.RESULT_DATA_FIELDS, ","),
      table.concat(result_fields, ",") .. " vs " .. table.concat(Protocol.RESULT_DATA_FIELDS, ","))

    local transport_on_wire = {}
    for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
      for _, allowed in ipairs(top) do
        if allowed == field then transport_on_wire[#transport_on_wire + 1] = field end
      end
      for _, allowed in ipairs(result_fields) do
        if allowed == field then transport_on_wire[#transport_on_wire + 1] = field end
      end
    end
    check("no Protocol.TRANSPORT_FIELDS entry is allow-listed onto the wire by the bridge",
      #transport_on_wire == 0, table.concat(transport_on_wire, ","))
    local C = Protocol.COMMANDS
    local C2S = { C.STARTUP, C.CONTEXT, C.REGISTER, C.UNREGISTER, C.FORCE, C.RESULT }
    local command_block = wire_src:match("const SUPPORTED_C2S_COMMANDS.-= &%[(.-)%];")
    local commands = {}
    for command in tostring(command_block):gmatch('"([^"]+)"') do
      commands[#commands + 1] = command
    end
    check("mod and bridge share the complete C2S command set",
      table.concat(commands, ",") == table.concat(C2S, ","),
      table.concat(commands, ",") .. " vs " .. table.concat(C2S, ","))
    local mismatched, compared, expected = {}, 0, 0
    for command, mod_fields in pairs(Protocol.DATA_FIELDS) do
      expected = expected + 1
      local fields = relay_keys[command]
      if fields then compared = compared + 1 end
      if table.concat(fields or {}, ",") ~= table.concat(mod_fields, ",") then
        mismatched[#mismatched + 1] = command .. ": " .. table.concat(fields or { "<missing>" }, ",")
          .. " vs " .. table.concat(mod_fields, ",")
      end
    end
    for _, command in ipairs(relay_order) do
      if not Protocol.DATA_FIELDS[command] then
        mismatched[#mismatched + 1] = command .. ": relay-only whitelist"
      end
    end
    table.sort(mismatched)
    check("mod DATA_FIELDS matches every bridge per-command data whitelist",
      expected == 5 and compared == expected and #mismatched == 0,
      compared .. "/" .. expected .. " compared; " .. table.concat(mismatched, " | "))
  end
end

do
  local UNFILTERED_DATA_SHAPE = {
    context = { message = true, silent = true },
    ["actions/register"] = { actions = true },
    ["actions/unregister"] = { action_names = true },
    ["actions/force"] = { state = true, query = true, ephemeral_context = true, priority = true, action_names = true },
  }

  local function extra_keys(data, allowed)
    if type(data) ~= "table" or next(data) == nil then return { "<no data payload to inspect>" } end
    local extra = {}
    for k in pairs(data) do
      if not allowed[k] then extra[#extra + 1] = k end
    end
    table.sort(extra)
    return extra
  end

  local ctx = Protocol.context("hi", true)
  local ctx_extra = extra_keys(ctx.data, UNFILTERED_DATA_SHAPE.context)
  check("context data carries only spec fields (bridge does not filter this command's data)",
    #ctx_extra == 0, table.concat(ctx_extra, ","))

  local reg = Protocol.register({ { name = "probe", description = "probe" } })
  local reg_extra = extra_keys(reg.data, UNFILTERED_DATA_SHAPE["actions/register"])
  check("actions/register data carries only spec fields (bridge does not filter this command's data)",
    #reg_extra == 0, table.concat(reg_extra, ","))

  local unreg = Protocol.unregister({ "probe" })
  local unreg_extra = extra_keys(unreg.data, UNFILTERED_DATA_SHAPE["actions/unregister"])
  check("actions/unregister data carries only spec fields (bridge does not filter this command's data)",
    #unreg_extra == 0, table.concat(unreg_extra, ","))

  local force = Protocol.force("state", "query", { "probe" }, { ephemeral_context = true, priority = "low" })
  local force_extra = extra_keys(force.data, UNFILTERED_DATA_SHAPE["actions/force"])
  check("actions/force data carries only spec fields (bridge does not filter this command's data)",
    #force_extra == 0, table.concat(force_extra, ","))
end

do
  local b = fresh_bridge()
  b.enabled = false
  check("send returns false while the bridge is disabled",
    b:send(Protocol.result("disabled", true, "ok")) == false)

  b.enabled = true
  local writable = false
  local written = {}
  function b:_append(line)
    if not writable then return 0 end
    written[#written + 1] = json.decode(line)
    return #line
  end

  check("send accepts a frame the disk refuses into the outbox FIFO",
    b:send(Protocol.result("buffered", true, "ok")) == true and #written == 0 and #b._fifo == 1)
  writable = true
  check("the next send flushes the FIFO before appending the current frame",
    b:send(Protocol.result("current", true, "ok")) == true)
  check("recovery writes both the queued and current protocol frames in order",
    #written == 2
    and written[1].data.id == "buffered"
    and written[2].data.id == "current", #written)
end
do
  local b = fresh_bridge()
  local writable = false
  local written = {}
  function b:_append(line)
    if not writable then return 0 end
    written[#written + 1] = json.decode(line)
    return #line
  end

  check("a context queued after a failed append still reports acceptance",
    b:send_context("buffer me", true) == true)
  check("the queued context frame is held in the FIFO", #b._fifo == 1, #b._fifo)
  check("nothing reached the outbox while the append was failing", #written == 0, #written)

  writable = true
  check("a later context flushes the backlog and appends its own frame",
    b:send_context("buffer me", true) == true)
  check("both frames are delivered in order -- Context.send does not merge or dedupe",
    #written == 2
    and written[1].command == "context" and written[1].data.message == "buffer me"
    and written[2].command == "context" and written[2].data.message == "buffer me", #written)
  check("a repeated identical context is sent again, exactly as the reference queue does",
    b:send_context("buffer me", true) == true and #written == 3, #written)
end

do
  local b = fresh_bridge()
  b._append = function() return 0 end
  b:send_startup()
  for i = 1, 300 do b:send(Protocol.context("silent " .. i, true)) end
  for i = 1, 1200 do b:send(Protocol.result("late" .. i, false, "no")) end
  check("an unwritable outbox keeps every frame, context included", #b._fifo == 1501, #b._fifo)
  local saved_neuro = G.NEURO
  G.NEURO = b
  check("a pending FIFO pauses model-facing sends",
    b:is_transport_saturated() and Utils.can_send() == false)
  b._append = nil
  check("flushing the FIFO succeeds", b:flush_outbox() == true and #b._fifo == 0)
  check("an empty FIFO resumes model-facing sends",
    not b:is_transport_saturated() and Utils.can_send() == true)
  G.NEURO = saved_neuro
end

do
  local b = fresh_bridge()
  b._append = function() return 0 end
  local handled = {}
  b:set_message_handler(function(msg)
    handled[#handled + 1] = msg.data.id
    if msg.data.id == "first" then
      for i = 1, 1024 do
        b:send(Protocol.result("queued-" .. i, true, "ok"))
      end
    end
  end)
  local f = assert(io.open(IPC_DIR .. "/" .. b.inbox_file, "wb"))
  f:write('{"command":"action","data":{"id":"first","name":"help"}}\n')
  f:write('{"command":"action","data":{"id":"second","name":"help"}}\n')
  f:close()

  local inbox_size = 0
  do
    local sf = assert(io.open(IPC_DIR .. "/" .. b.inbox_file, "rb"))
    inbox_size = sf:seek("end")
    sf:close()
  end

  b:poll_inbox()
  check("outbox saturation stops before accepting another result obligation",
    #handled == 1 and handled[1] == "first", table.concat(handled, ","))
  check("the unread action remains ahead of the inbox cursor",
    b.inbox_pos < inbox_size, b.inbox_pos .. "/" .. inbox_size)
  check("the send-side throttle remains raised",
    b:is_transport_saturated() == true)
  b._append = nil
  b:update(0)
  check("after the protected backlog flushes, polling resumes at the unread action",
    #handled == 2 and handled[2] == "second" and b.inbox_pos == inbox_size,
    table.concat(handled, ",") .. " " .. b.inbox_pos .. "/" .. inbox_size)
  os.execute("rm -rf " .. IPC_DIR)
end

do
  local BridgeInit = require("core.bridge_init")
  local saved_love = _G.love
  _G.love = nil
  BridgeInit.hook_love_quit()
  check("hook_love_quit with no LOVE runtime does not fabricate a global love table",
    _G.love == nil)
  _G.love = saved_love
end

do
  package.loaded["core.bridge_init"] = nil
  local BridgeInit = require("core.bridge_init")
  local Paths = require("core.mod_paths")
  local saved_read_ipc_dir = Paths.read_ipc_dir
  Paths.read_ipc_dir = function() return IPC_DIR end

  local saved_love = _G.love
  local saved_neuro = G.NEURO
  local original_quit_called = false
  _G.love = { quit = function() original_quit_called = true end }
  local original_love_quit = _G.love.quit

  G.NEURO = fresh_bridge()
  G.NEURO._startup_complete = true
  G.NEURO._bridge_init_complete = true
  G.NEURO:register_actions({ { name = "select_blind", description = "select", schema = { type = "object" } } })
  local unreg_count = 0
  G.NEURO.send = function(self, msg)
    if msg and msg.command == "actions/unregister" then
      unreg_count = unreg_count + 1
    end
  end

  BridgeInit.run({})

  check("BridgeInit.run installs the love.quit hook without a manual hook_love_quit call",
    type(_G.love.quit) == "function" and _G.love.quit ~= original_love_quit)
  _G.love.quit()
  check("love.quit installed by BridgeInit.run sends actions/unregister exactly once",
    unreg_count == 1, tostring(unreg_count))
  check("love.quit installed by BridgeInit.run still calls through to the original love.quit",
    original_quit_called == true)

  G.NEURO = saved_neuro
  _G.love = saved_love
  Paths.read_ipc_dir = saved_read_ipc_dir
  os.execute("rm -rf " .. IPC_DIR)
  package.loaded["core.bridge_init"] = nil
end

do
  local b = fresh_bridge()
  b:register_actions({
    { name = "play_hand", description = "play", schema = { type = "object" } },
    { name = "discard_hand", description = "discard", schema = { type = "object" } },
    { name = "buy_from_shop", description = "buy", schema = { type = "object" } },
  })

  local unregister_sent = nil
  b.send = function(self, msg)
    if msg and msg.command == "actions/unregister" then
      unregister_sent = msg
    end
  end

  b:unregister_all()
  check("unregister_all sends actions/unregister with the complete registered set",
    unregister_sent ~= nil and unregister_sent.data and type(unregister_sent.data.action_names) == "table",
    unregister_sent and tostring(unregister_sent.command))
  local names = unregister_sent and unregister_sent.data and unregister_sent.data.action_names or {}
  table.sort(names)
  check("unregister_all includes every action",
    table.concat(names, ",") == "buy_from_shop,discard_hand,play_hand",
    table.concat(names, ","))

  local BridgeInit = require("core.bridge_init")
  local saved_neuro = G.NEURO
  local saved_love = _G.love
  _G.love = { quit = function() end }
  G.NEURO = fresh_bridge()
  G.NEURO._startup_complete = true
  G.NEURO._bridge_init_complete = true
  G.NEURO:register_actions({ { name = "select_blind", description = "select", schema = { type = "object" } } })
  local unreg_count = 0
  local quit_unregister
  G.NEURO.send = function(self, msg)
    if msg and msg.command == "actions/unregister" then
      unreg_count = unreg_count + 1
      quit_unregister = msg
    end
  end

  BridgeInit.hook_love_quit()
  check("love.quit is a function", type(_G.love.quit) == "function")
  _G.love.quit()
  check("love.quit sends actions/unregister",
    quit_unregister ~= nil and quit_unregister.data and quit_unregister.data.action_names
      and quit_unregister.data.action_names[1] == "select_blind",
    quit_unregister and tostring(quit_unregister.command))
  check("love.quit sends actions/unregister exactly once", unreg_count == 1, tostring(unreg_count))

  local quit_before_second_hook = _G.love.quit
  BridgeInit.hook_love_quit()
  check("a second hook_love_quit call does not rewrap love.quit",
    _G.love.quit == quit_before_second_hook)

  G.NEURO:register_actions({ { name = "select_blind", description = "select", schema = { type = "object" } } })
  unreg_count = 0
  quit_unregister = nil
  _G.love.quit()
  check("love.quit still fires the unregister callback exactly once after a second hook attempt",
    unreg_count == 1, tostring(unreg_count))

  G.NEURO = saved_neuro
  _G.love = saved_love
  os.execute("rm -rf " .. IPC_DIR)
end

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
