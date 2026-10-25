_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("protocol-fuzz")

local Harness = require("tests.inbound_harness")
local ActionRegistry = require("core.action_registry")
local json = require("util.neuro_json")

local ARCHIVE_TRANSPORT_SESSION = "1"
local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("protocol_fuzz")
local H = Harness.new({ dir = dir, clock = CLOCK })
local id_slot = Harness.id_slot

local function rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 16807) % 2147483647
    return (state % n) + 1
  end
end

local function assert_obligation(label, want_ids, scenario, previously_delivered)
  local r = H.run(scenario)
  check("no throw: " .. label, r.ok, tostring(r.err))
  local wrong = {}
  for _, id in ipairs(want_ids) do
    local got = r.counts[id_slot(id)] or 0
    if got ~= 1 then wrong[#wrong + 1] = tostring(id):sub(1, 32) .. "=" .. got end
  end
  check("every delivered id is answered exactly once: " .. label,
    #wrong == 0, table.concat(wrong, " | "))
  local total = 0
  for _, n in pairs(r.counts) do total = total + n end
  local extras, allowed_prior = {}, 0
  for slot, n in pairs(r.counts) do
    local wanted = false
    for _, id in ipairs(want_ids) do
      if slot == id_slot(id) then wanted = true; break end
    end
    if not wanted then
      if previously_delivered and previously_delivered[slot] then
        allowed_prior = allowed_prior + n
      else
        extras[#extras + 1] = tostring(slot) .. "=" .. tostring(n)
      end
    end
  end
  local expected_total = #want_ids + allowed_prior
  check("no result for an id that was never delivered: " .. label,
    total == expected_total, "want " .. expected_total .. ", outbox has " .. total
      .. (#extras > 0 and " extras=" .. table.concat(extras, ",") or ""))
  check("the deadline sweep pays nothing: " .. label, r.swept == 0 and r.owed == 0,
    "swept=" .. r.swept .. " owed=" .. r.owed)
end

local schema_actions = {}
for _, contract in ipairs(require("tests.helpers").registry_contracts()) do
  local props = contract.schema and contract.schema.properties
  if type(props) == "table" and next(props) ~= nil then
    schema_actions[#schema_actions + 1] = contract
  end
end
table.sort(schema_actions, function(a, b) return a.name < b.name end)
check("the payload axis has a schema-carrying catalog to draw from", #schema_actions >= 15,
  #schema_actions)

local function fuzz_value(next_int, depth)
  local pick = next_int(11)
  if pick == 1 then return "null" end
  if pick == 2 then return tostring(next_int(20) - 10) end
  if pick == 3 then return tostring((next_int(1000) - 500) / 7) end
  if pick == 4 then return next_int(2) == 1 and "true" or "false" end
  if pick == 5 then return '""' end
  if pick == 6 then return '"' .. string.rep("x", next_int(64)) .. '"' end
  if pick == 7 then return "[]" end
  if pick == 8 then return "{}" end
  if pick == 9 then return "[" .. tostring(next_int(9)) .. "," .. tostring(next_int(9)) .. "]" end
  if pick == 10 or depth > 2 then return '"' .. tostring(next_int(9)) .. '"' end
  return "{\"k\":" .. fuzz_value(next_int, depth + 1) .. "}"
end

local function fuzz_payload(contract, next_int)
  local keys = {}
  for key in pairs(contract.schema.properties) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    if next_int(4) > 1 then
      parts[#parts + 1] = string.format("%q:%s", key, fuzz_value(next_int, 0))
    end
  end
  if next_int(5) == 1 then
    parts[#parts + 1] = string.format("%q:%s", "unexpected_key", fuzz_value(next_int, 0))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

do
  local next_int = rng(20260820)
  local names = {}
  for _, contract in ipairs(schema_actions) do names[#names + 1] = contract.name end
  local BATCH = 12
  local batch, ids, generated = {}, {}, 0
  local function flush(tag)
    if #batch == 0 then return end
    local lines, want = batch, ids
    assert_obligation("payload axis " .. tag, want, function()
      require("tests.helpers").stage_registered(nil, names)
      H.feed(lines)
      H.bridge:poll_inbox()
    end)
    batch, ids = {}, {}
  end
  for round = 1, 8 do
    for _, contract in ipairs(schema_actions) do
      generated = generated + 1
      local id = string.format("fuzz-%s-%d", contract.name, round)
      batch[#batch + 1] = H.action_line(id, contract.name, fuzz_payload(contract, next_int))
      ids[#ids + 1] = id
      if #batch >= BATCH then flush(tostring(generated)) end
    end
  end
  flush("tail")
  check("the payload axis generated a corpus, not a handful", generated >= 100, generated)
end

do
  local names = {}
  for _, contract in ipairs(require("tests.helpers").registry_contracts()) do names[#names + 1] = contract.name end
  table.sort(names)
  local next_int = rng(57057)
  local BATCH = 10
  local batch, ids = {}, {}
  local function flush(tag)
    if #batch == 0 then return end
    local lines, want = batch, ids
    assert_obligation("spontaneous axis " .. tag, want, function()
      require("tests.helpers").stage_registered(nil, { "play_hand", "help" })
      H.feed(lines)
      H.bridge:poll_inbox()
    end)
    batch, ids = {}, {}
  end
  for round = 1, 4 do
    for i = 1, #names do
      local name = names[((next_int(#names) + i) % #names) + 1]
      local id = string.format("spont-%d-%d", round, i)
      batch[#batch + 1] = H.action_line(id, name, "{}")
      ids[#ids + 1] = id
      if #batch >= BATCH then flush(round .. "." .. i) end
    end
  end
  flush("tail")
end

do
  assert_obligation("a name withdrawn between offer and answer", { "withdrawn-1" }, function()
    require("tests.helpers").stage_registered(nil, { "play_hand", "help" })
    H.feed({ H.action_line("withdrawn-1", "play_hand", '{"indices":[1,2]}') })
    require("tests.helpers").stage_registered(nil, { "help" })
    H.bridge:poll_inbox()
  end)
end

do
  local fh = assert(io.open("tests/fixtures/s2c_archive.jsonl", "r"),
    "the frozen inbound corpus is missing")
  local lines, commands, action_frames = {}, {}, 0
  local action_by_id = {}
  local private_records, malformed, private_frames = 0, {}, {}
  local historical_records, historical_valid_records = {}, {}
  local function valid_session(v)
    if type(v) == "number" then return v >= 0 and v == math.floor(v) end
    return type(v) == "string" and v:match("^%d+$") ~= nil
  end
  local function valid_private(frame)
    local command = frame.command
    if command == "neuro-bridge/reregister_all" then
      for key in pairs(frame) do if key ~= "command" and key ~= "transport_session" then return false end end
      return valid_session(frame.transport_session)
        and tostring(frame.transport_session) == ARCHIVE_TRANSPORT_SESSION
    end
    if command == "neuro-bridge/abandon" then
      for key in pairs(frame) do
        if key ~= "command" and key ~= "transport_session" and key ~= "data" then return false end
      end
      if not valid_session(frame.transport_session)
          or tostring(frame.transport_session) ~= ARCHIVE_TRANSPORT_SESSION
          or type(frame.data) ~= "table"
          or type(frame.data.ids) ~= "table" then return false end
      local count, max, seen = 0, 0, {}
      for key, id in pairs(frame.data.ids) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
            or type(id) ~= "string" or id == "" or seen[id] then return false end
        count, max, seen[id] = count + 1, math.max(max, key), true
      end
      if count == 0 or count ~= max or count > 64 then return false end
      for key in pairs(frame.data) do if key ~= "ids" and key ~= "message" then return false end end
      if frame.data.message ~= nil and type(frame.data.message) ~= "string" then return false end
      return true
    end
    return true
  end
  local line_no = 0
  for line in fh:lines() do
    line_no = line_no + 1
    if line:match("%S") then
      lines[#lines + 1] = line
      local ok, frame = pcall(json.decode, line)
      if not ok or type(frame) ~= "table" then
        malformed[#malformed + 1] = line_no
      else
        local command = frame.command
        commands[command or "<none>"] = (commands[command or "<none>"] or 0) + 1
        if command == "actions/reregister_all" then
          historical_records[#historical_records + 1] = line
          if type(frame.transport_session) == "number"
              and valid_session(frame.transport_session) then
            historical_valid_records[#historical_valid_records + 1] = frame
          end
        end
        if command == "action" then
          action_frames = action_frames + 1
          if type(frame.data) == "table" and frame.data.id ~= nil then
            action_by_id[id_slot(frame.data.id)] = frame
          end
        end
        if command == "neuro-bridge/reregister_all" or command == "neuro-bridge/abandon" then
          private_records = private_records + 1
          private_frames[#private_frames + 1] = frame
          if not valid_private(frame) then malformed[#malformed + 1] = line_no end
        end
      end
    end
  end
  fh:close()
  local mismatched_session = false
  if private_frames[1] then
    local mutant = {}
    for key, value in pairs(private_frames[1]) do mutant[key] = value end
    mutant.transport_session = "999"
    mismatched_session = not valid_private(mutant)
  end
  check("the frozen corpus is the archived one, not a stub", #lines >= 500, #lines)
  check("every archived line is valid JSON", #malformed == 0, table.concat(malformed, ","))
  check("private reconnect and abandon records retain their valid wire shapes and session",
    private_records >= 2 and commands["neuro-bridge/reregister_all"] ~= nil
      and commands["neuro-bridge/abandon"] ~= nil and mismatched_session, tostring(private_records))
  check("the corpus is real inbound traffic: actions, private controls, and proposed records",
    action_frames >= 500 and commands["neuro-bridge/reregister_all"] ~= nil
      and commands["neuro-bridge/abandon"] ~= nil and #historical_records > 0,
    action_frames .. " actions; " .. #historical_records .. " proposed records")
  check("proposed reconnect records carry numeric sessions but remain non-private",
    #historical_valid_records == #historical_records and #historical_records > 0,
    tostring(#historical_valid_records) .. "/" .. tostring(#historical_records))

  local names = {}
  for _, contract in ipairs(require("tests.helpers").registry_contracts()) do names[#names + 1] = contract.name end
  local BATCH = 20
  local archive_seen = {}
  local i = 1
  while i <= #lines do
    local batch, ids, seen = {}, {}, {}
    local stop = math.min(i + BATCH - 1, #lines)
    for k = i, stop do
      local line = lines[k]
      local ok, frame = pcall(json.decode, line)
      local command = ok and type(frame) == "table" and frame.command or nil
      if command ~= "neuro-bridge/reregister_all" and command ~= "neuro-bridge/abandon"
        and command ~= "actions/reregister_all" then
        batch[#batch + 1] = line
      end
      if command == "action" and type(frame.data) == "table" and frame.data.id ~= nil then
        local slot = id_slot(frame.data.id)
        if not seen[slot] then seen[slot] = true; ids[#ids + 1] = frame.data.id end
      end
    end
    assert_obligation("archived frames " .. i .. "-" .. stop, ids, function()
      require("tests.helpers").stage_registered(nil, names)
      H.bridge.transport_session = ARCHIVE_TRANSPORT_SESSION
      H.feed(batch)
      H.bridge:poll_inbox()
    end, archive_seen)
    for _, id in ipairs(ids) do archive_seen[id_slot(id)] = true end
    i = stop + 1
  end

  local legacy_ignored, legacy_failures = 0, {}
  for _, frame in ipairs(historical_valid_records) do
    local prior_session
    legacy_ignored = legacy_ignored + 1
    assert_obligation("proposed public reconnect control " .. legacy_ignored, {}, function()
      prior_session = tostring(G.NEURO.transport_session)
      H.feed({ json.encode(frame) })
      H.bridge:poll_inbox()
      if tostring(G.NEURO.transport_session) ~= prior_session then
        legacy_failures[#legacy_failures + 1] =
          "proposed control changed session from " .. tostring(prior_session)
      end
    end)
  end
  check("proposed actions/reregister_all controls are ignored by the private relay",
    legacy_ignored == #historical_valid_records and #legacy_failures == 0,
    tostring(legacy_ignored) .. "/" .. tostring(#historical_valid_records) .. " "
      .. table.concat(legacy_failures, " | "))
  local invalid_legacy_seen = false
  assert_obligation("malformed and missing-session legacy reconnect controls", {}, function()
    local prior_session = tostring(G.NEURO.transport_session)
    H.feed({
      '{"command":"actions/reregister_all"}',
      '{"command":"actions/reregister_all","transport_session":true}',
      '{"command":"actions/reregister_all","transport_session":{}}',
      '{"command":"actions/reregister_all","transport_session":""}',
      '{"command":"actions/reregister_all"',
    })
    H.bridge:poll_inbox()
    invalid_legacy_seen = tostring(G.NEURO.transport_session) == prior_session
  end)
  check("invalid proposed reconnect controls are ignored without changing session",
    invalid_legacy_seen, tostring(G.NEURO.transport_session))

  local prestartup_legacy_seen = false
  assert_obligation("pre-startup legacy reconnect control", {}, function()
    local prior_session = tostring(G.NEURO.transport_session)
    H.feed({ historical_records[1] })
    H.bridge:poll_inbox()
    prestartup_legacy_seen = tostring(G.NEURO.transport_session) == prior_session
  end)
  check("pre-startup proposed reconnect controls are ignored",
    prestartup_legacy_seen, tostring(G.NEURO.transport_session))

  local private_replayed, private_failures = 0, {}
  for _, control in ipairs(private_frames) do
    private_replayed = private_replayed + 1
    if control.command == "neuro-bridge/reregister_all" then
      assert_obligation("archived reregister control", {}, function()
        H.bridge.transport_session = nil
        H.feed({ json.encode(control) })
        H.bridge:poll_inbox()
        if tostring(G.NEURO.transport_session) ~= ARCHIVE_TRANSPORT_SESSION then
          private_failures[#private_failures + 1] =
            "reregister_all did not bind session " .. ARCHIVE_TRANSPORT_SESSION
        end
        if G.NEURO._bridge_init_complete ~= true then
          private_failures[#private_failures + 1] =
            "reregister_all did not complete reconnect startup"
        end
      end)
    else
      local abandoned_id = control.data.ids[1]
      local action = action_by_id[id_slot(abandoned_id)]
      if not action then
        private_failures[#private_failures + 1] =
          "archive abandon has no preceding action " .. tostring(abandoned_id)
      else
        assert_obligation("archived abandon control " .. tostring(abandoned_id),
          { abandoned_id }, function()
            require("tests.helpers").stage_registered(nil, names)
            H.bridge.transport_session = ARCHIVE_TRANSPORT_SESSION
            H.feed({ json.encode(action), json.encode(control) })
            H.bridge:poll_inbox()
          end)
      end
    end
  end
  check("archived private controls were replayed through the real dispatcher",
    private_replayed == private_records and #private_failures == 0,
    tostring(private_replayed) .. "/" .. tostring(private_records) .. " "
      .. table.concat(private_failures, " | "))
end

H.cleanup()
TmpWork.close()
done()
