local M = {}

local TD = require("tests.test_deadlock")
local SCENARIOS = TD.SCENARIOS
local function apply_mock(mock)
  TD.apply_mock(mock)
  if type(G.hand) == "table" then require("tests.helpers").card_area(G.hand) end
end
local TxCache = require("core.bridge").tx
local ActionRegistry = require("core.action_registry")
local Staging = require("core.staging")
local Protocol = require("core.bridge").wire

local function make_bridge()
  local neuro = G and G.NEURO or {}
  local b = {
    session_id = neuro.transport_session,
    results = {}, contexts = {},
    registered = {}, forces = {},
  }
  function b:send_action_result(id, ok, message, reason_code)
    if not Protocol.valid_action_id(id)
        or type(ok) ~= "boolean"
        or (message ~= nil and type(message) ~= "string") then
      return false
    end
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
    return true
  end
  function b:send_context(message, silent)
    self.contexts[#self.contexts + 1] = { message = message, silent = silent }
    return true
  end
  function b:register_actions(defs)
    for _, def in ipairs(defs or {}) do
      if type(def) == "table" and type(def.name) == "string" then
        self.registered[def.name] = true
      end
    end
    return true, { status = "written", kind = "actions_register" }
  end
  function b:force_actions(state, query, names)
    self.forces[#self.forces + 1] = { state = state, query = query, names = names }
    return true, { status = "written", kind = "actions_force" }
  end
  function b:send(_) return true end
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
  function(n) return "id with spaces & symbols !@#-" .. n end,
  function(n) return "\240\159\152\128-emoji-id-" .. n end,
  function(n) return string.rep("x", 300) .. n end,
}

local function id_for(counter, shape_idx)
  local f = ID_SHAPES[((shape_idx - 1) % #ID_SHAPES) + 1]
  return f(counter)
end

local function probe(Dispatcher, state, name, payload, id, label, fails)
  local bridge = make_bridge()
  local msg = {
    command = "action",
    data = { id = id, name = name, data = payload },
  }
  local valid_id = Protocol.valid_action_id(id)
  if valid_id then
    local opened = TxCache.open(id, name, G.TIMERS and G.TIMERS.REAL)
    if not opened then
      fails[#fails + 1] = string.format(
        "ADMISSION REJECTED [%s] action=%s payload=%s id=%s",
        state, tostring(name), label, tostring(id))
      return false
    end
  end

  local ok_call, err = pcall(Dispatcher.handle_message, msg, bridge)
  require("core.execute").step((G.TIMERS and G.TIMERS.REAL or 0) + 10)

  if not ok_call then
    fails[#fails + 1] = string.format(
      "THREW [%s] action=%s payload=%s id=%s\n      -> %s",
      state, tostring(name), label, tostring(id), tostring(err))
    return false
  end
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

local function set_state(state, engine_state)
  require("tests.helpers").in_engine_state(engine_state or state)
  G.CONTROLLER = { locked = false }
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
  local scenario_pass, scenario_fail, scenario_xfail, scenario_xpass, scenario_skip = 0, 0, 0, 0, 0
  local expected_xfails, expected_skips = 0, 0
  local expected_no_force = {}
  for _, sc in ipairs(SCENARIOS) do
    expected_no_force[sc] = sc.no_force == true
    if sc.xfail then expected_xfails = expected_xfails + 1 end
    if expected_no_force[sc] then expected_skips = expected_skips + 1 end
  end
  local scenarios_seen = 0

  local ALWAYS = { "exit_overlay_menu", "cash_out", "florblegorb_not_real" }

  for si, sc in ipairs(SCENARIOS) do
    scenarios_seen = scenarios_seen + 1
    local scenario_start = #fails
    local force_missing = false
    local ok_setup, setup_err = pcall(function()
      Dispatcher.reset_tx()
      G.NEURO = {
        dispatcher = Dispatcher, actions = Actions, enabled = true,
        run_generation = 1, decision_serial = si,
        transport_session = "roundtrip-" .. tostring(si),
        transport_epoch = si, register_actions = function() end,
      }
      G.FUNCS = G.FUNCS or {}
      apply_mock(sc.mock())
      G.NEURO.state = sc.state
      set_state(sc.state, sc.engine_state)
    end)

    if not ok_setup then
      fails[#fails + 1] = string.format("SETUP THREW [%s] %s -> %s",
        sc.state, sc.desc, tostring(setup_err))
    else
      local action_names, seen = {}, {}
      local force_names, force_set = {}, {}
      local function add(nm)
        if type(nm) == "string" and not seen[nm] then
          seen[nm] = true
          action_names[#action_names + 1] = nm
        end
      end

      local has_force = false
      local ok_force, force = pcall(require("force.force_router").get_force_for_state, sc.state)
      if not ok_force then
        fails[#fails + 1] = string.format(
          "FORCE THREW [%s] %s -> %s", sc.state, sc.desc, tostring(force))
      elseif type(force) == "table" then
        if type(force.actions) ~= "table" then
          fails[#fails + 1] = string.format(
            "FORCE ACTIONS INVALID [%s] %s -> %s", sc.state, sc.desc, type(force.actions))
        else
          for _, nm in ipairs(force.actions) do
            add(nm)
            force_names[#force_names + 1] = nm
            force_set[nm] = true
          end
          has_force = true
        end
      elseif sc.no_force then
        force_missing = true
        if not expected_no_force[sc] then
          fails[#fails + 1] = string.format(
            "FORCE SKIP [%s] %s was not marked no_force before execution", sc.state, sc.desc)
        end
      else
        fails[#fails + 1] = string.format(
          "FORCE MISSING [%s] %s (scenario is not marked no_force)", sc.state, sc.desc)
      end
      local ok_valid, valid = pcall(Actions.get_valid_actions_for_state, sc.state)
      if not ok_valid then
        fails[#fails + 1] = string.format(
          "ACTION SET THREW [%s] %s -> %s", sc.state, sc.desc, tostring(valid))
      elseif type(valid) ~= "table" then
        fails[#fails + 1] = string.format(
          "ACTION SET INVALID [%s] %s -> %s", sc.state, sc.desc, type(valid))
      else
        for _, nm in ipairs(valid) do add(nm) end
      end
      for _, nm in ipairs(ALWAYS) do add(nm) end
      local registered_names, definitions = {}, {}
      for _, nm in ipairs(action_names) do
        local contract = ActionRegistry.get(nm)
        if contract then
          registered_names[#registered_names + 1] = nm
          definitions[#definitions + 1] = contract
        end
      end
      ActionRegistry.note_registered(registered_names)
      local transport = make_bridge()
      transport:register_actions(definitions)

      if has_force then
        local forced, force_receipt = transport:force_actions(sc.state, force.query, force_names)
        if not forced then
          fails[#fails + 1] = string.format(
            "FORCE TRANSPORT FAILED [%s] %s -> %s", sc.state, sc.desc,
            tostring(force_receipt and force_receipt.status))
        else
          require("tests.helpers").open_force(sc.state, force_names)
        end
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

    local case_failures = #fails - scenario_start
    if sc.xfail then
      if case_failures > 0 then
        for _ = 1, case_failures do table.remove(fails) end
        scenario_xfail = scenario_xfail + 1
        print(string.format("[rt] XFAIL #%02d [%s] %s", si, sc.state, sc.desc))
      else
        scenario_xpass = scenario_xpass + 1
        fails[#fails + 1] = string.format(
          "XPASS #%02d [%s] %s -- remove xfail tag", si, sc.state, sc.desc)
      end
    elseif sc.no_force and force_missing and case_failures == 0 then
      scenario_skip = scenario_skip + 1
      scenario_pass = scenario_pass + 1
      print(string.format("[rt] SKIP #%02d [%s] %s -- no_force", si, sc.state, sc.desc))
    elseif case_failures > 0 then
      scenario_fail = scenario_fail + 1
    else
      scenario_pass = scenario_pass + 1
    end
  end

  G.NEURO = {
    dispatcher = Dispatcher, actions = Actions, enabled = true,
    run_generation = 1, decision_serial = 1,
    transport_session = "roundtrip-duplicates", transport_epoch = 1,
  }
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
    local first = { command = "action", data = { id = dup_id, name = "exit_overlay_menu", data = nil } }
    TxCache.open(dup_id, "exit_overlay_menu", G.TIMERS and G.TIMERS.REAL)
    local ok1, err1 = pcall(Dispatcher.handle_message, first, b1)
    if #b1.results == 0 then
      require("core.execute").step((G.TIMERS and G.TIMERS.REAL or 0) + 10)
    end
    local b2 = make_bridge()
    local second = { command = "action", data = { id = dup_id, name = "exit_overlay_menu", data = nil } }
    local ok2, err2 = pcall(Dispatcher.handle_message, second, b2)
    if not ok1 or not ok2 then
      fails[#fails + 1] = "dup-id replay: handle_message threw: " .. tostring(err1 or err2)
    elseif #b1.results ~= 1 or #b2.results ~= 0 then
      fails[#fails + 1] = string.format("dup-id replay: want 1+0 same-session results, got %d+%d",
        #b1.results, #b2.results)
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
    local Validate = require("core.validate")
    local real_busy = Validate.busy_reason

    local function inject()
      Validate.busy_reason = function() error("INJECTED throw during validation") end
    end
    local function restore() Validate.busy_reason = real_busy end

    do
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = {}
      apply_mock(SCENARIOS[1].mock())
      set_state("SELECTING_HAND"); tick(20)
      inject()
      local bridge = make_bridge()
      local ok_call = pcall(Dispatcher.handle_message,
        { command = "action", data = { id = "inj-before", name = "exit_overlay_menu", data = nil } }, bridge)
      if #bridge.results == 0 then
        require("core.execute").step((G.TIMERS and G.TIMERS.REAL or 0) + 10)
      end
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
      local EF = require("core.neuro_lifecycle")
      local real_post = EF.record_failure
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = {}
      apply_mock(SCENARIOS[1].mock())
      set_state("SELECTING_HAND"); tick(20)
      EF.record_failure = function(_, _) error("INJECTED throw in a finalizer (after answer)") end
      local bridge = make_bridge()
      local ok_call = pcall(Dispatcher.handle_message,
        { command = "action", data = { id = "inj-after", name = "exit_overlay_menu", data = nil } }, bridge)
      if #bridge.results == 0 then
        require("core.execute").step((G.TIMERS and G.TIMERS.REAL or 0) + 10)
      end
      EF.record_failure = real_post
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
    G.NEURO = {
      dispatcher = Dispatcher, actions = Actions,
      run_generation = 1, transport_session = "SES-1", transport_epoch = 1,
    }
    G.FUNCS = {}
    apply_mock(SCENARIOS[1].mock())
    set_state("SELECTING_HAND"); tick(20)
    ActionRegistry.note_registered({ "exit_overlay_menu" })
    G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
    local function admitted_route(id, name, public_session)
      local msg = {
        command = "action", session_id = public_session,
        data = { id = id, name = name, data = nil },
      }
      TxCache.open(id, name, G.TIMERS and G.TIMERS.REAL)
      return msg
    end
    local function flush_route_result(bridge)
      if #bridge.results == 0 then
        tick(0.25)
        Staging.update()
        tick(0.25)
        Staging.update()
        require("core.execute").step(G.TIMERS.REAL)
      end
    end

    do
      G.OVERLAY_MENU = require("tests.helpers").options_overlay()
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        admitted_route("rt-match", "exit_overlay_menu", "SES-1"), b)
      flush_route_result(b)
      if not ok or #b.results ~= 1 then
        fail_route(fails, "session match: want 1 result, no throw")
      end
      probes = probes + 1
    end
    do
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        admitted_route("rt-stale", "exit_overlay_menu", "SES-OLD"), b)
      flush_route_result(b)
      if not ok then fail_route(fails, "session mismatch: threw")
      elseif #b.results ~= 1 then fail_route(fails, "foreign session_id: want 1 result, got " .. #b.results) end
      probes = probes + 1
    end
    do
      G.OVERLAY_MENU = require("tests.helpers").options_overlay()
      local b = sess_bridge("SES-1")
      local ok = pcall(Dispatcher.route_message,
        admitted_route("rt-nosess", "exit_overlay_menu", nil), b)
      flush_route_result(b)
      if not ok or #b.results ~= 1 then fail_route(fails, "no-session msg: want 1 result") end
      probes = probes + 1
    end
    do
      G.NEURO.llm_paused = true
      local b = sess_bridge(nil)
      local ok = pcall(Dispatcher.route_message,
        admitted_route("rt-paused", "exit_overlay_menu", nil), b)
      G.NEURO.llm_paused = nil
      if not ok then fail_route(fails, "pause: threw")
      elseif #b.results ~= 1 then fail_route(fails, "pause: want exactly 1 (transient) result, got " .. #b.results)
      elseif b.results[1].ok ~= true then fail_route(fails, "pause: result should be ok=true (spec: false retries the force)") end
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

  if scenarios_seen ~= #SCENARIOS then
    fails[#fails + 1] = string.format("scenario corpus incomplete: visited %d of %d",
      scenarios_seen, #SCENARIOS)
  end
  if scenario_xfail ~= expected_xfails then
    fails[#fails + 1] = string.format("xfail accounting incomplete: got %d expected %d",
      scenario_xfail, expected_xfails)
  end
  if scenario_fail ~= 0 then
    fails[#fails + 1] = string.format("scenario failures were not accounted for: %d", scenario_fail)
  end
  if scenario_xpass ~= 0 then
    fails[#fails + 1] = string.format("unexpected XFAIL passes: %d", scenario_xpass)
  end
  if scenario_skip > expected_skips then
    fails[#fails + 1] = string.format(
      "no_force skip accounting exceeded immutable allowance: got %d allowed %d",
      scenario_skip, expected_skips)
  end
  print(string.format("[rt] scenarios: %d pass, %d fail, %d XFAIL, %d XPASS, %d explicit SKIP / %d total",
    scenario_pass, scenario_fail, scenario_xfail, scenario_xpass, scenario_skip, #SCENARIOS))
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
