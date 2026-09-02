_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {} }, hand = { cards = {} }, FUNCS = {}, NEURO = {} }

local check, done = require("tests.helpers").harness("sdk-compliance")

local Bridge = require("core.bridge")
local Actions = require("core.actions")

local function capture_bridge()
  local b = Bridge:new({ game = "Balatro", enabled = true })
  b.sent = {}
  b.send = function(self, message) self.sent[#self.sent + 1] = message end
  return b
end

do
  local D = require("core.dispatcher")
  local FS = require("core.force_state")
  require("core.tx_cache").reset()
  G.NEURO.llm_paused = true
  G.NEURO.force_dirty = false
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  FS.mark_sent(1)
  local results = {}
  local b = capture_bridge()
  b._force_answer_ids["pause-forced-1"] = "play_hand_force_1"
  b.send_action_result = function(_, id, success, message)
    results[#results + 1] = { id = id, success = success, message = message }
    return true
  end
  D.route_message({ command = "action",
    data = { id = "pause-forced-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("a paused answer to the active force is terminal on the wire",
    results[1] and results[1].success == true)
  check("the local force ends with the SDK force and rearms for unpause",
    G.NEURO.force_inflight == false and G.NEURO.force_dirty == true)
  G.NEURO.llm_paused = nil
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_window = nil
end

local function all_action_defs()
  return Actions.get_static_actions()
end

do
  local function find_desc(v, path)
    if type(v) ~= "table" then return nil end
    for k, child in pairs(v) do
      if k == "description" and type(child) == "string" then return path .. ".description" end
      local hit = find_desc(child, path .. "." .. tostring(k))
      if hit then return hit end
    end
    return nil
  end
  local b = capture_bridge()
  b:register_actions(all_action_defs())
  local reg
  for _, m in ipairs(b.sent) do
    if m.command == "actions/register" then reg = m end
  end
  check("register message captured", reg ~= nil and type(reg.data.actions) == "table")
  if reg then
    local bad
    for _, a in ipairs(reg.data.actions) do
      local hit = a.schema and find_desc(a.schema, a.name or "?")
      if hit then bad = hit break end
    end
    check("wire schemas carry no description keyword", bad == nil, bad)
    local kept = 0
    for _, a in ipairs(reg.data.actions) do
      if type(a.description) == "string" and #a.description > 0 then kept = kept + 1 end
    end
    check("top-level action descriptions survive", kept == #reg.data.actions,
      kept .. "/" .. #reg.data.actions)
  end
end

do
  for _, def in ipairs(all_action_defs()) do
    local props = def.schema and def.schema.properties
    if type(props) == "table" then
      for pname in pairs(props) do
        do
          check("" .. def.name .. " description mentions `" .. pname .. "`",
            def.description:find(pname, 1, true) ~= nil, def.description)
        end
      end
    end
  end
end

do
  local frames = {}
  local bridge = Bridge:new({ enabled = true })
  function bridge:send(message)
    frames[#frames + 1] = message
    return true
  end

  bridge:send_context("same automatic context", true)
  bridge:send_context("same automatic context", true)
  check("every context call produces a frame, repeats included", #frames == 2, #frames)

  bridge:send_context("requested information", true)
  bridge:send_context("requested information", true)
  check("a repeated context is delivered on every call",
    #frames == 4
      and frames[3].data.message == "requested information"
      and frames[4].data.message == "requested information", #frames)
end

do
  local b = capture_bridge()
  local defs = {
    { name = "use_consumable", description = "d", schema = { type = "object" } },
    { name = "skip_pack", description = "d", schema = { type = "object" } },
  }
  b:register_actions(defs)
  local before = #b.sent
  b:unregister_actions({ "use_consumable", "skip_pack", "never_registered" })
  local unreg = b.sent[#b.sent]
  check("unregister sent", unreg and unreg.command == "actions/unregister")
  check("only registered names included", unreg and #unreg.data.action_names == 2,
    unreg and table.concat(unreg.data.action_names, ","))
  check("unregistering nothing sends nothing",
    (function() b:unregister_actions({ "ghost" }); return #b.sent end)() == before + 1)
  b:register_actions(defs)
  local rereg = b.sent[#b.sent]
  check("same defs re-register after unregister (dedupe key invalidated)",
    rereg and rereg.command == "actions/register")
end

do
  local D = require("core.dispatcher")
  G.NEURO.llm_paused = true
  G.NEURO.force_dirty = false
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("MENU", { "exit_overlay_menu" }, { exit_overlay_menu = true }, 1)
  local results = {}
  local b = capture_bridge()
  b.send_action_result = function(_, id, success, message)
    results[#results + 1] = { id = id, success = success, message = message }
  end
  b.replay_action_result = b.send_action_result
  D.route_message({ command = "action",
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("exactly one result", #results == 1, #results)
  check("paused result is success=true (no force retry)",
    results[1] and results[1].success == true, results[1] and tostring(results[1].success))
  check("message explains the pause",
    results[1] and results[1].message and results[1].message:find("Paused", 1, true) ~= nil,
    results[1] and results[1].message)
  check("paused action outside the force leaves that force open",
    G.NEURO.force_inflight == true and G.NEURO.force_dirty == false)
  D.route_message({ command = "action",
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("redelivered paused id replays the paused reply (no execution)",
    #results == 2 and results[2].success == true
    and results[2].message and results[2].message:find("Paused", 1, true) ~= nil,
    #results >= 2 and tostring(results[2].message) or ("#results=" .. #results))
  G.NEURO.llm_paused = nil
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_window = nil
  G.NEURO.force_window = nil
end
do
  local D = require("core.dispatcher")
  local Enforce = require("core.enforce")
  local Registry = require("core.action_registry")
  local saved_pre_action = Enforce.pre_action
  local saved_definitions = Registry.definitions
  local old_states, old_state = G.STATES, G.STATE
  Enforce.pre_action = function() return true end
  G.STATES = { MENU = 1, SHOP = 2 }

  local function arm_foreign_force(state)
    G.STATE = G.STATES[state]
    G.NEURO.state = state
    G.NEURO.force_inflight = false
    G.NEURO.force_window = nil
    require("core.force_state").arm(state, { "play_hand" }, { play_hand = true }, 1)
  end

  arm_foreign_force("MENU")
  D.handle_message({
    command = "action",
    data = { id = "foreign-setup", name = "exit_overlay_menu", data = "{}" },
  }, capture_bridge())
  check("successful foreign setup action leaves the force open",
    G.NEURO.force_inflight == true)

  arm_foreign_force("SHOP")
  D.handle_message({
    command = "action",
    data = { id = "foreign-general", name = "exit_overlay_menu", data = "{}" },
  }, capture_bridge())
  check("successful foreign in-run action leaves the force open",
    G.NEURO.force_inflight == true)

  arm_foreign_force("SHOP")
  Registry.definitions = function() error("forced execution failure") end
  D.handle_message({
    command = "action",
    data = { id = "foreign-failure", name = "exit_overlay_menu", data = "{}" },
  }, capture_bridge())
  check("failed foreign action leaves the force open",
    G.NEURO.force_inflight == true)

  Registry.definitions = saved_definitions
  Enforce.pre_action = saved_pre_action
  G.STATES, G.STATE = old_states, old_state
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_window = nil
  G.NEURO.force_window = nil
end

do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  local results = {}
  b.send_action_result = function(_, id, success, message)
    results[#results + 1] = { id = id, success = success, message = message }
  end

  local ok_nil, accepted_nil = pcall(D.validate_message,
    { command = "action", data = { name = "exit_overlay_menu", data = nil } }, b)
  check("validate_message never throws on missing id", ok_nil == true, tostring(accepted_nil))
  check("validate_message rejects action with missing id", accepted_nil == false, tostring(accepted_nil))
  check("missing id never emits a wire frame", #results == 0, #results)

  local ok_empty, accepted_empty = pcall(D.validate_message,
    { command = "action", data = { id = "", name = "exit_overlay_menu", data = nil } }, b)
  check("validate_message never throws on empty-string id", ok_empty == true, tostring(accepted_empty))
  check("validate_message rejects action with empty-string id", accepted_empty == false, tostring(accepted_empty))
  check("an empty-string id is answered exactly once", #results == 1, #results)
  check("and the empty id is echoed byte for byte",
    results[1] and results[1].id == "", results[1] and tostring(results[1].id))
end
do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  local results = {}
  b.send_action_result = function(_, id, success, message, reason_code)
    results[#results + 1] = {
      id = id, success = success, message = message, reason_code = reason_code,
    }
  end
  local generation_before = G.NEURO.run_generation
  G.NEURO.run_generation = 5
  local ok_route = pcall(D.route_message, {
    command = "action",
    run_generation = 1,
    data = { name = "exit_overlay_menu" },
  }, b)
  check("stale-generation action without id never throws", ok_route == true)
  check("stale-generation action without id emits no invalid result", #results == 0, #results)
  G.NEURO.run_generation = generation_before
end

do
  local D = require("core.dispatcher")
  local results = {}
  local b = capture_bridge()
  b.send_action_result = function(_, id, success, message, reason_code)
    results[#results + 1] = { id = id, success = success, message = message, reason_code = reason_code }
  end
  local generation_before = G.NEURO.run_generation
  G.NEURO.run_generation = 5

  local ok_route = pcall(D.route_message, { command = "action", run_generation = 1 }, b)
  check("action with no data wrapper never throws", ok_route == true)
  check("action with no data wrapper emits no wire frame (would need id=nil)",
    #results == 0, #results)

  local ok_handle = pcall(D.handle_message, { command = "action" }, b)
  check("handle_message with no data wrapper never throws", ok_handle == true)
  check("handle_message with no data wrapper emits no wire frame",
    #results == 0, #results)

  G.NEURO.run_generation = generation_before
end

do
  local D = require("core.dispatcher")
  local Enforce = require("core.enforce")
  local saved_pre_action = Enforce.pre_action
  Enforce.pre_action = function() return true end
  local old_states, old_state = G.STATES, G.STATE
  G.STATES = { MENU = 1 }
  G.STATE = 1
  local old_overlay = G.OVERLAY_MENU
  G.OVERLAY_MENU = {}

  local results, phases, contexts = {}, {}, {}
  local b = capture_bridge()
  b.is_transition_cooldown = function() return false end
  b.send_action_result = function(_, id, success, message, reason_code)
    results[#results + 1] = { id = id, success = success, message = message, reason_code = reason_code }
  end
  b.record_action_phase = function(_, id, name, phase)
    phases[#phases + 1] = id .. ":" .. name .. ":" .. phase
    return true
  end
  G.NEURO.send_context = function(_, message, silent)
    contexts[#contexts + 1] = { message = message, silent = silent }
  end

  Enforce.reset_run_state()
  local generation_before = G.NEURO.run_generation
  local last_action_name_before = G.NEURO.last_action_name
  G.NEURO.run_generation = 1
  local msg = {
    command = "action",
    run_generation = 1,
    data = { id = "genmis-1", name = "exit_overlay_menu", data = "{}" },
  }
  local accepted = D.validate_message(msg, b)
  check("prepared-job generation mismatch: initial validate accepts and answers once",
    accepted == true and #results == 1 and results[1].success == true, accepted)
  check("prepared-job generation mismatch: the optimistic result carries no reason yet",
    results[1] and results[1].message == nil, tostring(results[1] and results[1].message))

  local FS = require("core.force_state")
  FS.arm("SELECTING_HAND", { "exit_overlay_menu" }, { exit_overlay_menu = true }, G.TIMERS and G.TIMERS.REAL or 0)
  FS.mark_sent(G.TIMERS and G.TIMERS.REAL or 0)
  G.NEURO.force_generation = 1
  G.NEURO.run_generation = 2
  D.handle_message(msg, b)

  check("prepared-job generation mismatch: no second action/result is sent (already answered once)",
    #results == 1, #results)
  check("prepared-job generation mismatch: the job is corrected, not silently executed",
    G.NEURO.last_action_name == last_action_name_before, tostring(G.NEURO.last_action_name))
  check("prepared-job generation mismatch: force_state is told the optimistic result was wrong",
    G.NEURO.last_failed_action == "exit_overlay_menu", tostring(G.NEURO.last_failed_action))
  check("prepared-job generation mismatch: correction reason names the run generation",
    type(G.NEURO.last_failed_reason) == "string"
      and G.NEURO.last_failed_reason:find("run generation", 1, true) ~= nil,
    tostring(G.NEURO.last_failed_reason))
  check("prepared-job generation mismatch: force is marked dirty so a fresh force can be resent",
    G.NEURO.force_dirty == true)
  check("prepared-job generation mismatch: journal records prepare, ack, then abort (not execute)",
    table.concat(phases, ",")
      == "genmis-1:exit_overlay_menu:prepared,genmis-1:exit_overlay_menu:acknowledged,"
        .. "genmis-1:exit_overlay_menu:aborted",
    table.concat(phases, ","))
  check("prepared-job generation mismatch: the correction reaches Neuro on the force query",
    require("force.force_helpers").failed_action_warning()
      :find("the game state is unchanged -- choose again", 1, true) ~= nil,
    require("force.force_helpers").failed_action_warning())
  check("prepared-job generation mismatch: and spends nothing on the permanent context channel",
    #contexts == 0, contexts[1] and tostring(contexts[1].message) or "none")

  G.NEURO.run_generation = generation_before
  G.NEURO.send_context = nil
  Enforce.pre_action = saved_pre_action
  G.OVERLAY_MENU = old_overlay
  G.STATES, G.STATE = old_states, old_state
  Enforce.reset_run_state()
end

do
  local D = require("core.dispatcher")
  local Enforce = require("core.enforce")
  local saved_pre_action = Enforce.pre_action
  Enforce.pre_action = function() return true end
  local old_states, old_state = G.STATES, G.STATE
  G.STATES = { MENU = 1 }
  G.STATE = 1
  local old_overlay = G.OVERLAY_MENU
  G.OVERLAY_MENU = {}

  local array_results = {}
  local array_bridge = capture_bridge()
  array_bridge.is_transition_cooldown = function() return false end
  array_bridge.send_action_result = function(_, id, success, message, reason_code)
    array_results[#array_results + 1] = {
      id = id, success = success, message = message, reason_code = reason_code,
    }
  end
  Enforce.reset_run_state()
  local array_accepted = D.validate_message({
    command = "action",
    data = { id = "json-array-payload", name = "exit_overlay_menu", data = "[]" },
  }, array_bridge)
  check("JSON type: dispatcher rejects string [] payload", array_accepted == false,
    tostring(array_accepted))
  check("JSON type: string [] rejection is SCHEMA_INVALID",
    array_results[1] and array_results[1].reason_code == "SCHEMA_INVALID",
    array_results[1] and tostring(array_results[1].reason_code))

  local object_results = {}
  local object_bridge = capture_bridge()
  object_bridge.is_transition_cooldown = function() return false end
  object_bridge.send_action_result = function(_, id, success, message, reason_code)
    object_results[#object_results + 1] = {
      id = id, success = success, message = message, reason_code = reason_code,
    }
  end
  local phases = {}
  object_bridge.record_action_phase = function(_, id, name, phase)
    phases[#phases + 1] = id .. ":" .. name .. ":" .. phase
    return true
  end
  Enforce.reset_run_state()
  local object_accepted = D.validate_message({
    command = "action",
    data = { id = "json-object-payload", name = "exit_overlay_menu", data = "{}" },
  }, object_bridge)
  check("JSON type: dispatcher accepts string {} for empty-object schema",
    object_accepted == true, tostring(object_accepted))
  check("JSON type: accepted string {} receives optimistic success",
    object_results[1] and object_results[1].success == true,
    object_results[1] and tostring(object_results[1].success))
  check("JSON type: and it is the sole result, sent after validation and before execution",
    #object_results == 1 and object_results[1].message == nil,
    #object_results .. "/" .. tostring(object_results[1] and object_results[1].message))
  if object_accepted then D.abort_prepared("json-object-payload", "test cleanup") end
  check("action journal records prepare, acknowledgement, and cancellation in order",
    table.concat(phases, ",")
      == "json-object-payload:exit_overlay_menu:prepared,json-object-payload:exit_overlay_menu:acknowledged,"
        .. "json-object-payload:exit_overlay_menu:aborted",
    table.concat(phases, ","))
  Enforce.pre_action = saved_pre_action

  G.OVERLAY_MENU = old_overlay
  G.STATES, G.STATE = old_states, old_state
  Enforce.reset_run_state()
end

do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  G.NEURO.startup_session = nil
  local persona_before = G.NEURO.persona
  local ok_call = pcall(D.route_message, {
    command = "startup",
    data = { session = { sessionId = "sess-77", characterId = "neuro", displayName = "Neuro" } },
  }, b)
  check("startup ack never throws", ok_call == true)
  check("startup ack captures sessionId",
    G.NEURO.startup_session and G.NEURO.startup_session.session_id == "sess-77",
    G.NEURO.startup_session and G.NEURO.startup_session.session_id)
  check("startup ack captures characterId",
    G.NEURO.startup_session and G.NEURO.startup_session.character_id == "neuro",
    G.NEURO.startup_session and G.NEURO.startup_session.character_id)
  check("startup ack captures displayName",
    G.NEURO.startup_session and G.NEURO.startup_session.display_name == "Neuro",
    G.NEURO.startup_session and G.NEURO.startup_session.display_name)
  check("startup ack does not touch persona selection", G.NEURO.persona == persona_before,
    tostring(G.NEURO.persona))
  check("startup ack emits no wire frame", #b.sent == 0, #b.sent)

  local ok_malformed = pcall(D.route_message, { command = "startup", data = {} }, b)
  check("startup ack without session table never throws", ok_malformed == true)
  check("startup ack without session table leaves prior metadata untouched",
    G.NEURO.startup_session and G.NEURO.startup_session.session_id == "sess-77")
end

do
  local D = require("core.dispatcher")
  local Enforce = require("core.enforce")
  local saved_pre_action = Enforce.pre_action
  Enforce.pre_action = function() return true end
  local old_states, old_state = G.STATES, G.STATE
  G.STATES = { MENU = 1 }
  G.STATE = 1
  local old_overlay = G.OVERLAY_MENU
  G.OVERLAY_MENU = {}
  require("core.force_state").clear_cancel_pending()
  require("tests.helpers").stage_registered("MENU", { "exit_overlay_menu" })

  local function decode_message(id, payload)
    local out = {}
    local b = capture_bridge()
    b.is_transition_cooldown = function() return false end
    b.send_action_result = function(_, rid, success, message, reason_code)
      out[#out + 1] = { id = rid, success = success, message = message, reason_code = reason_code }
    end
    Enforce.reset_run_state()
    D.validate_message({ command = "action", data = { id = id, name = "exit_overlay_menu", data = payload } }, b)
    return out[1]
  end

  local syn = decode_message("json-syntax", '{"a":')
  check("JSON prose: a real syntax error still tells Neuro to fix the JSON",
    syn and syn.success == false and tostring(syn.message):find("invalid JSON", 1, true) ~= nil,
    syn and tostring(syn.message))

  local sem = decode_message("json-null-array", '{"a":[1,null,3]}')
  check("JSON prose: null-in-array is not reported to Neuro as invalid JSON",
    sem and sem.success == false and tostring(sem.message):find("invalid JSON", 1, true) == nil,
    sem and tostring(sem.message))
  check("JSON prose: null-in-array names the actual reason",
    sem and tostring(sem.message):lower():find("null", 1, true) ~= nil,
    sem and tostring(sem.message))
  check("JSON prose: null-in-array still reports SCHEMA_INVALID",
    sem and sem.reason_code == "SCHEMA_INVALID", sem and tostring(sem.reason_code))

  Enforce.pre_action = saved_pre_action
  G.OVERLAY_MENU = old_overlay
  G.STATES, G.STATE = old_states, old_state
  Enforce.reset_run_state()
end

done()
