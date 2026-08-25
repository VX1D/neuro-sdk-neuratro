_G.NEURO_TEST = true  -- reaches module internals published only behind the test seam

G = { NEURO = { run_generation = 3 } }

local Config = require("core.config")
local Protocol = require("core.bridge_protocol")
local Bridge = require("core.bridge")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")
local Utils = require("util.utils")

local check, done = require("tests.helpers").harness("bridge_register_reset")

if Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off") == nil then
  print("FAIL  could not disable outbox truncation")
  os.exit(1)
end

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("bridge_register_reset")
local ACTIONS = { { name = "play_hand", description = "play", schema = { type = "object" } } }

local function fresh_bridge()
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  return Bridge:new({ enabled = true, fs_dir = IPC_DIR })
end

local function outbox_commands(bridge)
  local f = io.open(IPC_DIR .. "/" .. bridge.outbox_file, "rb")
  if not f then return {} end
  local data = f:read("*a")
  f:close()
  local out = {}
  for line in data:gmatch("[^\n]+") do
    local ok, msg = pcall(json.decode, line)
    if ok and msg then out[#out + 1] = msg end
  end
  return out
end

local function count_command(bridge, command)
  local n = 0
  for _, msg in ipairs(outbox_commands(bridge)) do
    if msg.command == command then n = n + 1 end
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
  local real_send = b.send
  b.send = function() error("injected startup transport failure") end
  local ok = pcall(function() b:send_startup() end)
  check("a thrown startup send does not commit the startup-complete latch",
    ok == false and b._startup_complete == nil)
  b.send = real_send
  b:send_startup()
  check("startup can be retried after the transient throw",
    b._startup_complete == true and count_command(b, "startup") == 1,
    tostring(count_command(b, "startup")))
end

do
  local b = fresh_bridge()
  b.append_file = function() return false end
  for i = 1, Bridge.OUTBOX_BACKLOG_HARD - 1 do
    b:send(Protocol.result("atomic-fill-" .. i, true, "queued"))
  end
  b._registered_set.play_hand = true
  b._canonical_defs.play_hand = {
    name = "play_hand", description = "play", schema = { type = "object" },
  }
  local before = #b._outbox_backlog
  local accepted, receipt = b:force_actions("SELECTING_HAND", "Choose", { "play_hand" })
  check("HARD-1 rejects the two-frame force transaction before registering an orphan alias",
    accepted == false and receipt and receipt.kind == "force_atomic_reservation"
      and #b._outbox_backlog == before and next(b._registered_force_aliases) == nil,
    tostring(#b._outbox_backlog) .. "/" .. tostring(before))
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b.run_generation = 1
  b:send_startup()
  b:register_actions({ { name = "sell_card", description = "sell", schema = { type = "object" } } })
  check("a non-disposable canonical action can be forced through a scoped identifier",
    b:force_actions("SHOP", "Choose", { "sell_card" }) == true)
  local frames = outbox_commands(b)
  local alias
  for _, frame in ipairs(frames) do
    if frame.command == "actions/force" then alias = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg)
    b:send_action_result(msg.data.id, true, "done")
  end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "scoped-nondisposable", name = alias, data = "{}",
  } })
  frames = outbox_commands(b)
  local unregister_at, result_at
  for i, frame in ipairs(frames) do
    if frame.command == "actions/unregister"
        and frame.data.action_names[1] == alias then unregister_at = i end
    if frame.command == "action/result"
        and frame.data.id == "scoped-nondisposable" then result_at = i end
  end
  check("the scoped identifier is disposable and leaves before its result",
    unregister_at ~= nil and result_at ~= nil and unregister_at < result_at,
    tostring(unregister_at) .. "/" .. tostring(result_at))
  check("disposing the force alias keeps the reusable canonical action registered",
    b._registered_set.sell_card == true and b._force_open == nil)
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions({
    { name = "cash_out", description = "Call cash_out to continue.", schema = { type = "object" } },
  })
  check("a scoped cash-out force is accepted",
    b:force_actions("State cash_out", "Your move: cash_out|{}.", { "cash_out" }) == true)
  local register, force
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/register"
        and frame.data.actions[1].name:match("^cash_out_force_%d+$") then register = frame end
    if frame.command == "actions/force" then force = frame end
  end
  local alias = force and force.data.action_names[1]
  check("force query names the exact action offered in action_names",
    alias ~= nil and force.data.query == "Your move: " .. alias .. "|{}.",
    force and force.data.query)
  check("force state and definition do not contradict the scoped identifier",
    alias ~= nil and force.data.state == "State " .. alias
      and register.data.actions[1].description == "Call " .. alias .. " to continue.",
    alias)
end

do
  local defs = {
    { name = "play_hand", description = "play", schema = { type = "object" } },
    { name = "discard_hand", description = "discard", schema = { type = "object" } },
  }
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions(defs)
  b:force_actions("SELECTING_HAND", "Choose", { "play_hand", "discard_hand" })
  local offered
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then offered = frame.data.action_names end
  end
  b:set_message_handler(function(msg) b:send_action_result(msg.data.id, true, "done") end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "sibling-close", name = offered[1], data = "{}",
  } })
  local removed = {}
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do removed[name] = true end
    end
  end
  check("successful force answer unregisters every scoped sibling before its result",
    removed[offered[1]] and removed[offered[2]])
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions({
    { name = "cash_out", description = "cash", schema = { type = "object" } },
  })
  check("reconnect fixture opens a scoped force",
    b:force_actions("ROUND_EVAL", "Choose", { "cash_out" }) == true)
  local alias
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then alias = frame.data.action_names[1] end
  end
  b:set_message_handler(function() end)
  b:_deliver_inbox_message({ command = "actions/reregister_all", transport_session = 2 })
  local unregister_at
  for i, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" and frame.data.action_names[1] == alias then
      unregister_at = i
    end
  end
  check("reregister_all retires the previous websocket's force alias",
    unregister_at ~= nil and b._registered_force_aliases[alias] == nil, alias)
  check("a retired reconnect force cannot keep the transport force lock",
    b._force_open == nil and b._active_force_wire_by_canonical == nil)
end

do
  local b = fresh_bridge()
  G.NEURO = b
  b:register_actions(ACTIONS)
  b:force_actions("SELECTING_HAND", "Choose", { "play_hand" })
  local alias
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/force" then alias = frame.data.action_names[1] end
  end
  b:set_message_handler(function(msg) b:send_action_result(msg.data.id, false, "try again") end)
  b:_deliver_inbox_message({ command = "action", data = {
    id = "force-retry", name = alias, data = "{}",
  } })
  local removed = false
  for _, frame in ipairs(outbox_commands(b)) do
    if frame.command == "actions/unregister" then
      for _, name in ipairs(frame.data.action_names or {}) do
        if name == alias then removed = true end
      end
    end
  end
  check("success=false preserves the forced alias for the SDK retry",
    not removed and b._force_open == true and b._registered_force_aliases[alias] == true)
end

do
  local b = fresh_bridge()
  G.NEURO = b
  G.TIMERS = { REAL = 500 }
  b.run_generation = 10
  b:send_startup()
  b:register_actions(ACTIONS)
  local ForceState = require("core.force_state")
  check("run retirement fixture arms the old force",
    ForceState.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 500))
  check("run retirement fixture sends the old force",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand" }) == true)
  ForceState.mark_sent(500)

  local real_append = b.append_file
  b.append_file = function() return false end
  local saved_love = _G.love
  _G.love = { timer = { getTime = function() return G.TIMERS.REAL end } }
  require("core.neuro_lifecycle").reset_run_state()
  _G.love = saved_love
  check("run reset clears only the run-owned cancellation quarantine",
    b.force_cancel_pending == nil and b.force_inflight == false)
  check("the old force is retired into the protected FIFO instead of blocking the new run",
    b._force_open == nil and b._outbox_backlog and #b._outbox_backlog >= 1,
    tostring(b._force_open) .. "/" .. tostring(b._outbox_backlog and #b._outbox_backlog))

  b.append_file = real_append
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
  b.append_file = function() return false end
  for i = 1, Bridge.OUTBOX_BACKLOG_HARD do
    b:send(Protocol.result("hard-fill-" .. i, true, "queued"))
  end
  check("protected backlog reaches but never exceeds its hard RAM bound",
    #b._outbox_backlog == Bridge.OUTBOX_BACKLOG_HARD, #b._outbox_backlog)
  b._registered_set.play_hand = true
  check("a force rejected at the hard bound is not misreported as accepted",
    b:force_actions("SELECTING_HAND", "Choose", { "play_hand" }) == false
      and #b._outbox_backlog == Bridge.OUTBOX_BACKLOG_HARD)
  TxCache.reset()
  TxCache.open("hard-result", "play_hand", 0)
  check("a result rejected at the hard bound remains an outstanding obligation",
    b:send_action_result("hard-result", true, "later") == false
      and #b._outbox_backlog == Bridge.OUTBOX_BACKLOG_HARD
      and #TxCache.outstanding(0) == 1)
  b.append_file = function() return true end
  b:_outbox_flush()
  b:answer_owed_results(nil, "paid after hard backlog recovery")
  check("the hard-bound rejection is paid after transport recovery",
    #TxCache.outstanding(0) == 0)
end

do
  local b = fresh_bridge()
  b.enabled = false
  check("a disabled register is rejected without advancing the catalogue shadow",
    b:register_actions(ACTIONS) == false
      and not b._registered_set.play_hand and b._last_register_key == nil)
  b.enabled = true
  check("the rejected registration is retried after enable",
    b:register_actions(ACTIONS) == true and b._registered_set.play_hand == true
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
  Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "on")
  local b = fresh_bridge()
  local pending_receipt = { status = "buffered" }
  local pending_backlog = { { line = "pending-result\n", tier = 2, receipt = pending_receipt } }
  b._outbox_backlog = pending_backlog
  local real_write = b.write_file
  b.write_file = function(self, file, data)
    if file == self.outbox_file and data == "" then return false end
    return real_write(self, file, data)
  end
  local started = b:send_startup()
  check("a failed outbox truncation prevents a non-first startup frame",
    started == false and b._startup_complete == nil and count_command(b, "startup") == 0)
  check("a failed startup truncation does not orphan the prior protected backlog",
    b._outbox_backlog == pending_backlog and pending_receipt.status == "buffered")
  Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
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
    count_command(b, "actions/register") == 2, count_command(b, "actions/register"))
  check("send_startup does not leave stale signatures behind (no unregister frame)",
    count_command(b, "actions/unregister") == 0, count_command(b, "actions/unregister"))
  check("two startup frames present", count_command(b, "startup") == 2)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:send_startup()
  b:register_actions({ { name = "select_blind", description = "pick", schema = { type = "object" } } })
  check("a different action set after send_startup unregisters nothing from the dead session",
    count_command(b, "actions/unregister") == 0, count_command(b, "actions/unregister"))
  check("the new session registers its own set",
    count_command(b, "actions/register") == 2, count_command(b, "actions/register"))
end
do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:send_context("hello", false)
  b:send(Protocol.result("live-1", true, "ok"))
  check("a healthy transport buffers nothing, so a hard kill has nothing to lose",
    (b._outbox_backlog == nil or #b._outbox_backlog == 0)
      and b:is_transport_saturated() == false,
    b._outbox_backlog and #b._outbox_backlog)
end

do
  local b = fresh_bridge()
  b.append_file = function() return false end
  b:send(Protocol.result("dead-session", true, "old"))
  check("failed result is buffered before the new session",
    b._outbox_backlog and #b._outbox_backlog == 1)
  b.append_file = Bridge.append_file
  b:send_startup()
  local messages = outbox_commands(b)
  check("startup drops the dead session backlog",
    #messages == 1 and messages[1].command == "startup", #messages)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  local seen = 0
  b:set_message_handler(function(msg)
    if msg.command == "actions/reregister_all" then
      seen = seen + 1
      b:register_actions(ACTIONS)
    end
  end)
  append_inbox(b, '{"command":"actions/reregister_all"}')
  b:poll_inbox()
  check("reregister_all reached the message handler", seen == 1, seen)
  check("reregister_all re-emits the identical action set",
    count_command(b, "actions/register") == 2, count_command(b, "actions/register"))
  check("reregister_all does not fabricate an unregister",
    count_command(b, "actions/unregister") == 0, count_command(b, "actions/unregister"))
  check("reregister_all keeps the signature cache",
    b._registered_sigs and b._registered_sigs["play_hand"] ~= nil)
end

do
  local b = fresh_bridge()
  b:send_startup()
  b:register_actions(ACTIONS)
  b:unregister_actions({ "play_hand" })
  b:register_actions(ACTIONS)
  check("unregister then re-register emits both frames",
    count_command(b, "actions/unregister") == 1 and count_command(b, "actions/register") == 2,
    count_command(b, "actions/unregister") .. "/" .. count_command(b, "actions/register"))
end

do
  local expected = { "session_id", "run_generation", "seq", "reason_code", "transport_session_unattributed" }
  check("TRANSPORT_FIELDS length", #Protocol.TRANSPORT_FIELDS == #expected, #Protocol.TRANSPORT_FIELDS)
  for i, field in ipairs(expected) do
    check("TRANSPORT_FIELDS[" .. i .. "] == " .. field, Protocol.TRANSPORT_FIELDS[i] == field,
      tostring(Protocol.TRANSPORT_FIELDS[i]))
  end

  local b = fresh_bridge()
  b:send_startup()
  local decorated = b:_decorate(Protocol.result("id-1", false, "no"))
  for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
    check("_decorate stamps nothing outside the envelope: " .. field, decorated[field] == nil,
      tostring(decorated[field]))
  end
  check("_decorate stamps game", decorated.game == "Balatro", tostring(decorated.game))

  local wire = Protocol.sanitize_for_wire(decorated)
  for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
    check("sanitize_for_wire drops top-level " .. field, wire[field] == nil)
  end
  check("sanitize_for_wire drops data.reason_code", wire.data.reason_code == nil)
  check("sanitize_for_wire keeps id/success/message",
    wire.data.id == "id-1" and wire.data.success == false and wire.data.message == "no")
  local kept = 0
  for _ in pairs(wire) do kept = kept + 1 end
  check("sanitize_for_wire keeps only command/game/data", kept == 3, kept)

  local ctx = Protocol.sanitize_for_wire(b:_decorate(Protocol.context("hi", true)))
  check("sanitize_for_wire keeps non-result data untouched",
    ctx.data.message == "hi" and ctx.data.silent == true)
end

do
  local f = io.open("../neuro-bridge-rs/src/main.rs", "rb")
  check("bridge source reachable for the wire contract", f ~= nil)
  if f then
    local src = f:read("*a")
    f:close()
    local top = {}
    for field in src:match('for key in %[([^%]]+)%]'):gmatch('"([^"]+)"') do top[#top + 1] = field end
    local result_fields = {}
    for field in src:match('data%.retain%(|k, _| matches!%(k%.as_str%(%), ([^%)]+)%)'):gmatch('"([^"]+)"') do
      result_fields[#result_fields + 1] = field
    end
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
    local command_block = src:match("const SUPPORTED_C2S_COMMANDS.-= &%[(.-)%];")
    local commands = {}
    for command in tostring(command_block):gmatch('"([^"]+)"') do
      commands[#commands + 1] = command
    end
    check("mod and bridge share the complete C2S command set",
      table.concat(commands, ",") == table.concat(Protocol.C2S_COMMANDS, ","),
      table.concat(commands, ",") .. " vs " .. table.concat(Protocol.C2S_COMMANDS, ","))
    check("bridge injects reregister_all on a new websocket session",
      src:find('REREGISTER_ALL_LINE', 1, true) ~= nil
      and src:find('actions/reregister_all', 1, true) ~= nil
      and src:find('request_action_reregistration(&cfg.inbox, transport_session).await;', 1, true) ~= nil)
    check("bridge stamps the reregister request with an IPC-only transport session",
      src:find('fn next_transport_session', 1, true) ~= nil
      and src:find('"transport_session".to_string()', 1, true) ~= nil)
    check("the transport session is seeded from the bridge process, so a restart cannot repeat a stamp",
      src:find('AtomicU64::new(process_session_base())', 1, true) ~= nil)
    check("bridge bootstrap cache tracks unregister",
      src:find('Some("actions/unregister")', 1, true) ~= nil)

    local sanitize = src:match("fn sanitize_for_wire%(.-\n}\n") or ""
    local pos, mismatched, compared = 1, {}, 0
    while true do
      local _, stop, command = sanitize:find('command == "([^"]+)"', pos)
      if not stop then break end
      local next_start = sanitize:find('command == "', stop + 1) or (#sanitize + 1)
      local list = sanitize:sub(stop + 1, next_start - 1)
        :match('data%.retain%(|k, _| matches!%(k%.as_str%(%), ([^%)]+)%)')
      if list then
        local fields = {}
        for field in list:gmatch('"([^"]+)"') do fields[#fields + 1] = field end
        compared = compared + 1
        local mod_fields = Protocol.DATA_FIELDS[command] or {}
        if table.concat(fields, ",") ~= table.concat(mod_fields, ",") then
          mismatched[#mismatched + 1] = command .. ": " .. table.concat(fields, ",")
            .. " vs " .. table.concat(mod_fields, ",")
        end
      end
      pos = stop + 1
    end
    check("mod DATA_FIELDS matches every bridge per-command data whitelist",
      compared == 5 and #mismatched == 0, compared .. " compared; " .. table.concat(mismatched, " | "))
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

  local reg = Protocol.register({})
  local reg_extra = extra_keys(reg.data, UNFILTERED_DATA_SHAPE["actions/register"])
  check("actions/register data carries only spec fields (bridge does not filter this command's data)",
    #reg_extra == 0, table.concat(reg_extra, ","))

  local unreg = Protocol.unregister({})
  local unreg_extra = extra_keys(unreg.data, UNFILTERED_DATA_SHAPE["actions/unregister"])
  check("actions/unregister data carries only spec fields (bridge does not filter this command's data)",
    #unreg_extra == 0, table.concat(unreg_extra, ","))

  local force = Protocol.force("state", "query", {}, { ephemeral_context = true, priority = "low" })
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
  function b:append_file(_, line)
    if not writable then return false end
    written[#written + 1] = json.decode(line)
    return true
  end

  check("send returns false when the current frame is buffered",
    b:send(Protocol.result("buffered", true, "ok")) == false)
  writable = true
  check("send returns true after flushing the backlog and appending the current frame",
    b:send(Protocol.result("current", true, "ok")) == true)
  check("recovery writes both the buffered and current protocol frames",
    #written == 2
    and written[1].data.id == "buffered"
    and written[2].data.id == "current", #written)
end
do
  local b = fresh_bridge()
  b.session_id = "journal-session"
  check("action journal persists the executing phase",
    b:record_action_phase("action-7", "play_hand", "executing") == true)
  local restarted = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
  local recovered = restarted:recover_action_journal()
  check("restart reports an interrupted action without executing it",
    recovered and recovered.id == "action-7" and recovered.name == "play_hand"
      and recovered.phase == "executing")
  check("interrupted action recovery is consumed once",
    restarted:recover_action_journal() == nil)
  check("action journal persists a terminal phase",
    restarted:record_action_phase("action-8", "play_hand", "completed", { success = true }) == true)
  local clean_restart = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
  check("restart ignores completed actions",
    clean_restart:recover_action_journal() == nil)
end

do
  local b = fresh_bridge()
  local writable = false
  local written = {}
  function b:append_file(_, line)
    if not writable then return false end
    written[#written + 1] = json.decode(line)
    return true
  end

  check("a context buffered after a failed append still reports acceptance",
    b:send_context("buffer me", true) == true)
  check("the buffered context frame is held in the backlog",
    b._outbox_backlog and #b._outbox_backlog == 1)
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
  local DEAD_DIR = IPC_DIR .. "/no_such_dir"
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  local b = Bridge:new({ enabled = true, fs_dir = DEAD_DIR })

  local function backlog_lines(bridge)
    local out = {}
    for _, entry in ipairs(bridge._outbox_backlog or {}) do
      local line = type(entry) == "table" and entry.line or entry
      local ok, msg = pcall(json.decode, line)
      if ok and msg then out[#out + 1] = msg end
    end
    return out
  end

  local function backlog_counts(bridge)
    local counts = {
      startup = 0,
      result = 0,
      register = 0,
      unregister = 0,
      force = 0,
      silent = 0,
      spoken = 0,
      total = 0,
    }
    for _, msg in ipairs(backlog_lines(bridge)) do
      counts.total = counts.total + 1
      if msg.command == "startup" then
        counts.startup = counts.startup + 1
      elseif msg.command == "action/result" then
        counts.result = counts.result + 1
      elseif msg.command == "actions/register" then
        counts.register = counts.register + 1
      elseif msg.command == "actions/unregister" then
        counts.unregister = counts.unregister + 1
      elseif msg.command == "actions/force" then
        counts.force = counts.force + 1
      elseif msg.command == "context" then
        if msg.data and msg.data.silent then
          counts.silent = counts.silent + 1
        else
          counts.spoken = counts.spoken + 1
        end
      end
    end
    return counts
  end

  b:send_startup()
  check("an unwritable outbox buffers instead of writing", b._send_failed == true)
  for i = 1, 5 do
    b:send(Protocol.result("r" .. i, true, "ok"))
  end
  for i = 1, 300 do
    b:send(Protocol.context("silent " .. i, true))
  end
  for i = 1, 20 do
    b:send(Protocol.context("spoken " .. i, false))
  end

  local counts = backlog_counts(b)
  check("backlog stays at the soft cap", counts.total == 256, counts.total)
  check("the startup frame is never trimmed out of the backlog", counts.startup == 1, counts.startup)
  check("no action/result is trimmed out of the backlog", counts.result == 5, counts.result)
  check("spoken context outlives silent context", counts.spoken == 20, counts.spoken)
  check("silent context absorbs the whole trim", counts.silent == 230, counts.silent)

  for i = 1, 1200 do
    b:send(Protocol.result("late" .. i, false, "no"))
  end
  local protected = backlog_counts(b)
  check("protected frames may exceed the old hard ceiling", protected.total == 1206, protected.total)
  check("all protected frames survive while context is removed",
    protected.startup == 1
    and protected.result == 1205
    and protected.silent == 0
    and protected.spoken == 0,
    protected.startup .. "/" .. protected.result .. "/"
      .. protected.silent .. "/" .. protected.spoken)

  local saved_neuro = G.NEURO
  G.NEURO = b
  check("protected backlog saturation pauses model-facing sends",
    b:is_transport_saturated() and Utils.can_send() == false)
  b:register_actions(ACTIONS)
  b:force_actions("SELECTING_HAND", "Choose", { "play_hand" })
  b:unregister_actions({ "play_hand" })
  local all_protected = backlog_counts(b)
  check("canonical register, scoped force register, force, and unregister remain protected beyond 1024",
    all_protected.total == 1210
    and all_protected.startup == 1
    and all_protected.result == 1205
    and all_protected.register == 2
    and all_protected.force == 1
    and all_protected.unregister == 1,
    all_protected.total .. "/" .. all_protected.register .. "/"
      .. all_protected.force .. "/" .. all_protected.unregister)
  b.append_file = function() return true end
  check("flushing protected frames succeeds", b:_outbox_flush() == true)
  check("flushing below the soft cap resumes model-facing sends",
    not b:is_transport_saturated() and Utils.can_send() == true)
  G.NEURO = saved_neuro
  os.execute("rm -rf " .. IPC_DIR)
end

do
  local b = fresh_bridge()
  b.append_file = function() return false end
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
  b.append_file = function() return true end
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
  Paths.read_ipc_dir = function() return nil end -- keep setup_neuro_bridge() from touching G.NEURO

  local saved_love = _G.love
  local saved_neuro = G.NEURO
  local original_quit_called = false
  _G.love = { quit = function() original_quit_called = true end }
  local original_love_quit = _G.love.quit

  G.NEURO = fresh_bridge()
  G.NEURO:register_actions({ { name = "select_blind" } })
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
  b:register_actions({ { name = "play_hand" }, { name = "discard_hand" }, { name = "buy_from_shop" } })

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
  G.NEURO:register_actions({ { name = "select_blind" } })
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

  G.NEURO:register_actions({ { name = "select_blind" } })
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
