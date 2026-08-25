_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("protocol-fuzz")

local Harness = require("tests.inbound_harness")
local ActionRegistry = require("core.action_registry")
local json = require("util.neuro_json")

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

local function assert_obligation(label, want_ids, scenario)
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
  check("no result for an id that was never delivered: " .. label,
    total == #want_ids, "want " .. #want_ids .. ", outbox has " .. total)
  check("the deadline sweep pays nothing: " .. label, r.swept == 0 and r.owed == 0,
    "swept=" .. r.swept .. " owed=" .. r.owed)
end

local schema_actions = {}
for _, contract in ipairs(ActionRegistry.all()) do
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

-- An action that belongs to no open force: the SDK permits one at any time (SPECIFICATION.md), and
-- the mod owes it a result whether it accepts it, refuses it or has withdrawn the name.
do
  local names = {}
  for _, contract in ipairs(ActionRegistry.all()) do names[#names + 1] = contract.name end
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
  local lines = {}
  for line in fh:lines() do
    if line:match("%S") then lines[#lines + 1] = line end
  end
  fh:close()
  check("the frozen corpus is the archived one, not a stub", #lines >= 500, #lines)

  local commands, action_frames = {}, 0
  for _, line in ipairs(lines) do
    local ok, frame = pcall(json.decode, line)
    if ok and type(frame) == "table" then
      commands[frame.command or "<none>"] = (commands[frame.command or "<none>"] or 0) + 1
      if frame.command == "action" then action_frames = action_frames + 1 end
    end
  end
  check("the corpus is real inbound traffic: actions, reregisters and abandons",
    action_frames >= 500 and commands["actions/reregister_all"] ~= nil
      and commands["neuro-bridge/abandon"] ~= nil,
    action_frames .. " actions")

  local names = {}
  for _, contract in ipairs(ActionRegistry.all()) do names[#names + 1] = contract.name end
  local BATCH = 20
  local i = 1
  while i <= #lines do
    local batch, ids, seen = {}, {}, {}
    local stop = math.min(i + BATCH - 1, #lines)
    for k = i, stop do
      batch[#batch + 1] = lines[k]
      local ok, frame = pcall(json.decode, lines[k])
      if ok and type(frame) == "table" and frame.command == "action"
        and type(frame.data) == "table" and frame.data.id ~= nil then
        local slot = id_slot(frame.data.id)
        if not seen[slot] then
          seen[slot] = true
          ids[#ids + 1] = frame.data.id
        end
      end
    end
    assert_obligation("archived frames " .. i .. "-" .. stop, ids, function()
      require("tests.helpers").stage_registered(nil, names)
      H.feed(batch)
      H.bridge:poll_inbox()
    end)
    i = stop + 1
  end
end

H.cleanup()
TmpWork.close()
done()
