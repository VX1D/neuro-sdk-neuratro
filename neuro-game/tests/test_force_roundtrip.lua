local M = {}

local TD = require("tests.test_deadlock")
local SCENARIOS = TD.SCENARIOS
local apply_mock = TD.apply_mock

local function make_bridge()
  local b = { session_id = nil, results = {}, contexts = {} }
  function b:send_action_result(id, ok, message)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message }
  end
  function b:send_context(message, silent)
    self.contexts[#self.contexts + 1] = { message = message, silent = silent }
    return true
  end
  function b:register_actions(_) end
  function b:force_actions(_, _, _, _) end
  function b:send(_) end
  return b
end

local PAYLOADS = {
  { tag = "absent",       data = nil },
  { tag = "empty",        data = "" },
  { tag = "obj_empty",    data = "{}" },
  { tag = "index_1",      data = '{"index":1}' },
  { tag = "index_0",      data = '{"index":0}' },
  { tag = "index_neg",    data = '{"index":-1}' },
  { tag = "index_big",    data = '{"index":999999}' },
  { tag = "index_float",  data = '{"index":1.5}' },
  { tag = "index_str",    data = '{"index":"1"}' },
  { tag = "index_ovf",    data = '{"index":1e19}' },
  { tag = "bad_json",     data = "not json {{{" },
  { tag = "json_array",   data = "[1,2,3]" },
  { tag = "json_number",  data = "42" },
  { tag = "json_bool",    data = "true" },
  { tag = "json_null",    data = "null" },
  { tag = "json_string",  data = '"hello"' },
  { tag = "area_cons",    data = '{"area":"consumables","index":1}' },
  { tag = "area_hand",    data = '{"area":"hand","index":1}' },
  { tag = "seed",         data = '{"seed":"ABCD1234"}' },
  { tag = "deck",         data = '{"deck":"b_red","key":"b_red"}' },
  { tag = "name",         data = '{"name":"Test Name"}' },
  { tag = "highlight",    data = '{"indices":[1,2,3]}' },
  { tag = "nested",       data = '{"a":{"b":[1,null,true,{"c":"d"}]}}' },
  { tag = "extra_keys",   data = '{"index":1,"bogus":true,"x":[1,2]}' },
  { tag = "unicode",      data = '{"name":"\\u00e9\\u4e2d\\ud83d\\ude00"}' },
  { tag = "tbl_obj",      data = { index = 1 } },
  { tag = "tbl_empty",    data = {} },
  { tag = "tbl_array",    data = { 1, 2, 3 } },
  { tag = "tbl_nested",   data = { a = { b = { 1, 2 } }, index = 2 } },
}

local ID_SHAPES = {
  function(n) return "id-" .. n end,
  function(n) return tostring(n) end,
  function(_) return "" end,
  function(_) return "id with spaces & symbols !@#" end,
  function(_) return "\240\159\152\128-emoji-id" end,
  function(n) return string.rep("x", 300) .. n end,
}

local function id_for(counter, shape_idx)
  local f = ID_SHAPES[((shape_idx - 1) % #ID_SHAPES) + 1]
  return f(counter)
end

local function probe(Dispatcher, state, name, payload, id, label, fails)
  local bridge = make_bridge()
  local msg = { command = "action", data = { id = id, name = name, data = payload } }

  local ok_call, err = pcall(Dispatcher.handle_message, msg, bridge)

  if not ok_call then
    fails[#fails + 1] = string.format(
      "THREW [%s] action=%s payload=%s id=%s\n      -> %s",
      state, tostring(name), label, tostring(id), tostring(err))
    return false
  end

  local valid_id = id ~= nil
  local want_n = valid_id and 1 or 0
  local n = #bridge.results
  if n ~= want_n then
    fails[#fails + 1] = string.format(
      "RESULT COUNT=%d (want %d) [%s] action=%s payload=%s id=%s",
      n, want_n, state, tostring(name), label, tostring(id))
    return false
  end
  if not valid_id then
    return true
  end

  local got_id = bridge.results[1].id
  if got_id ~= id then
    fails[#fails + 1] = string.format(
      "ID NOT ECHOED got=%s want=%s [%s] action=%s payload=%s",
      tostring(got_id), tostring(id), state, tostring(name), label)
    return false
  end

  return true
end

local _clock = 0
local function tick(dt)
  _clock = _clock + (dt or 5)
  G.TIMERS = G.TIMERS or {}
  G.TIMERS.REAL = _clock
end

local function set_state(state)
  G.STATES = G.STATES or {}
  if G.STATES[state] == nil then
    local nextv = 0
    for _, v in pairs(G.STATES) do if v > nextv then nextv = v end end
    G.STATES[state] = nextv + 1
  end
  G.STATE = G.STATES[state]
end

function M.run()
  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  local Actions = G.NEURO and G.NEURO.actions
  if not Dispatcher or not Actions then
    error("test_force_roundtrip: wire G.NEURO.dispatcher/actions before run")
  end

  print("====================================================")
  print("[rt] Force round-trip invariant suite (" .. #SCENARIOS .. " scenarios)")
  print("     assert: never-throw + exactly-one-result + id-echoed")
  print("====================================================")

  local fails = {}
  local function fail_route(f, m) f[#f + 1] = m end
  local probes = 0
  local counter = 0

  local ALWAYS = { "exit_overlay_menu", "cash_out", "florblegorb_not_real" }

  for si, sc in ipairs(SCENARIOS) do
    if not sc.xfail then
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = G.FUNCS or {}
      apply_mock(sc.mock())

      set_state(sc.state)

      local action_names, seen = {}, {}
      local function add(nm)
        if type(nm) == "string" and not seen[nm] then
          seen[nm] = true
          action_names[#action_names + 1] = nm
        end
      end

      local has_force = false
      local ok_force, force = pcall(Dispatcher.get_force_for_state, sc.state)
      if ok_force and type(force) == "table" then
        for _, nm in ipairs(force.actions or {}) do add(nm) end
        has_force = true
      end
      local ok_valid, valid = pcall(Actions.get_valid_actions_for_state, sc.state)
      if ok_valid and type(valid) == "table" then
        for _, nm in ipairs(valid) do add(nm) end
      end
      for _, nm in ipairs(ALWAYS) do add(nm) end
      if has_force then
        require("core.force_state").arm(sc.state, action_names, seen, 1)
      end

      for _, name in ipairs(action_names) do
        for pi, p in ipairs(PAYLOADS) do
          tick(5)
          counter = counter + 1
          probe(Dispatcher, sc.state, name, p.data, id_for(counter, pi), p.tag, fails)
          probes = probes + 1
        end
      end
    end
  end

  G.NEURO = { dispatcher = Dispatcher, actions = Actions }
  G.FUNCS = G.FUNCS or {}
  apply_mock(SCENARIOS[1].mock())
  set_state("SELECTING_HAND")

  do
    tick(5)
    local bridge = make_bridge()
    local ok_call = pcall(Dispatcher.handle_message,
      { command = "action", data = { id = nil, name = "exit_overlay_menu", data = nil } }, bridge)
    if not ok_call or #bridge.results ~= 0 then
      fails[#fails + 1] = "nil-id probe: expected zero results (dropped, no wire frame), no throw"
    end
    probes = probes + 1
  end

  do
    tick(5)
    local dup_id = "dup-replay-id-777"
    local b1 = make_bridge()
    pcall(Dispatcher.handle_message,
      { command = "action", data = { id = dup_id, name = "exit_overlay_menu", data = nil } }, b1)
    local b2 = make_bridge()
    pcall(Dispatcher.handle_message,
      { command = "action", data = { id = dup_id, name = "exit_overlay_menu", data = nil } }, b2)
    if #b1.results ~= 1 or #b2.results ~= 1 then
      fails[#fails + 1] = string.format("dup-id replay: want 1+1 results, got %d+%d",
        #b1.results, #b2.results)
    elseif b1.results[1].ok ~= b2.results[1].ok then
      fails[#fails + 1] = "dup-id replay: ok flag not stable across replay"
    end
    probes = probes + 2
  end

  local ENVELOPES = {
    { command = "action" },
    { command = "action", data = {} },
    { command = "action", data = { id = "x" } },
    { command = "context", data = {} },
    { data = { id = "x", name = "exit_overlay_menu" } },
    {},
  }
  for _, env in ipairs(ENVELOPES) do
    tick(5)
    local bridge = make_bridge()
    local ok_call, err = pcall(Dispatcher.handle_message, env, bridge)
    if not ok_call then
      fails[#fails + 1] = "malformed envelope THREW: " .. tostring(err)
    end
    probes = probes + 1
  end

  do
    local FH = require("force.force_helpers")
    local real_phase = FH.set_action_phase

    local function inject(throw_on_phase)
      FH.set_action_phase = function(phase)
        if phase == throw_on_phase then error("INJECTED throw at phase=" .. tostring(phase)) end
        return real_phase(phase)
      end
    end
    local function restore() FH.set_action_phase = real_phase end

    do
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = {}
      apply_mock(SCENARIOS[1].mock())
      set_state("SELECTING_HAND"); tick(20)
      inject("validating")
      local bridge = make_bridge()
      local ok_call = pcall(Dispatcher.handle_message,
        { command = "action", data = { id = "inj-before", name = "exit_overlay_menu", data = nil } }, bridge)
      restore()
      if not ok_call then
        fails[#fails + 1] = "inject before-answer: handle_message PROPAGATED throw (would hang/dup)"
      elseif #bridge.results ~= 1 then
        fails[#fails + 1] = string.format("inject before-answer: want 1 result, got %d", #bridge.results)
      elseif bridge.results[1].id ~= "inj-before" then
        fails[#fails + 1] = "inject before-answer: id not echoed on terminal result"
      end
      probes = probes + 1
    end

    do
      local EF = require("core.enforce")
      local real_post = EF.post_action
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = {}
      apply_mock(SCENARIOS[1].mock())
      set_state("SELECTING_HAND"); tick(20)
      EF.post_action = function(_, _) error("INJECTED throw in post_action (after answer)") end
      local bridge = make_bridge()
      local ok_call = pcall(Dispatcher.handle_message,
        { command = "action", data = { id = "inj-after", name = "exit_overlay_menu", data = nil } }, bridge)
      EF.post_action = real_post
      restore()
      if not ok_call then
        fails[#fails + 1] = "inject after-answer: handle_message PROPAGATED throw (Staging would emit a 2nd result)"
      elseif #bridge.results ~= 1 then
        fails[#fails + 1] = string.format("inject after-answer: want exactly 1 result, got %d (double-result bug)", #bridge.results)
      end
      probes = probes + 1
    end
  end

  do
    local function sess_bridge(sid)
      local b = make_bridge(); b.session_id = sid; return b
    end
    G.NEURO = { dispatcher = Dispatcher, actions = Actions }
    G.FUNCS = {}
    apply_mock(SCENARIOS[1].mock())
    set_state("SELECTING_HAND"); tick(20)

    do
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        { command = "action", session_id = "SES-1", data = { id = "rt-match", name = "exit_overlay_menu", data = nil } }, b)
      if not ok or #b.results ~= 1 then fail_route(fails, "session match: want 1 result, no throw") end
      probes = probes + 1
    end
    do
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        { command = "action", session_id = "SES-OLD", data = { id = "rt-stale", name = "exit_overlay_menu", data = nil } }, b)
      if not ok then fail_route(fails, "session mismatch: threw")
      elseif #b.results ~= 1 then fail_route(fails, "foreign session_id: want 1 result, got " .. #b.results) end
      probes = probes + 1
    end
    do
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        { command = "action", data = { id = "rt-nosess", name = "exit_overlay_menu", data = nil } }, b)
      if not ok or #b.results ~= 1 then fail_route(fails, "no-session msg: want 1 result") end
      probes = probes + 1
    end
    do
      G.NEURO.llm_paused = true
      local b = sess_bridge(nil)
      local ok = pcall(Dispatcher.route_message,
        { command = "action", data = { id = "rt-paused", name = "exit_overlay_menu", data = nil } }, b)
      G.NEURO.llm_paused = nil
      if not ok then fail_route(fails, "pause: threw")
      elseif #b.results ~= 1 then fail_route(fails, "pause: want exactly 1 (transient) result, got " .. #b.results)
      elseif b.results[1].ok ~= true then fail_route(fails, "pause: result should be ok=true (spec: false retries the force)")
      elseif not tostring(b.results[1].message or ""):find("Paused") then fail_route(fails, "pause: message should explain the pause") end
      probes = probes + 1
    end
    do
      local b = sess_bridge(nil)
      local ok = pcall(Dispatcher.route_message, { command = "actions/reregister_all" }, b)
      if not ok then fail_route(fails, "reregister_all: threw")
      elseif #b.results ~= 0 then fail_route(fails, "reregister_all: must not emit action/result") end
      probes = probes + 1
    end
  end

  print(string.format("[rt] probes run: %d", probes))
  print("====================================================")
  if #fails == 0 then
    print(string.format("==== force-roundtrip: %d probes, 0 FAIL ====", probes))
  else
    print(string.format("==== force-roundtrip: %d FAIL / %d probes ====", #fails, probes))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails
end

return M
