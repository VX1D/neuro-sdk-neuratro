_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("inbound-obligation")

local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local Actions = require("core.actions")
local Staging = require("core.staging")
local TxCache = require("core.bridge").tx
local ActionRegistry = require("core.action_registry")
local json = require("util.neuro_json")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("inbound_obligation")

local Harness = require("tests.inbound_harness")
local H = Harness.new({ dir = dir, clock = CLOCK })
local id_slot = Harness.id_slot
local feed, frames, run, action_line = H.feed, H.frames, H.run, H.action_line

local PLAY = '{"indices":[1,2]}'

local CASES = {
  { "a spec-exact action frame carrying no run_generation",
    function() feed({ action_line("spec-1") }); H.bridge:poll_inbox() end,
    { ["spec-1"] = 1 } },
  { "D1 a foreign top-level session_id",
    function()
      feed({ '{"command":"action","session_id":"OLD","data":{"id":"sess-1","name":"play_hand","data":' .. json.encode(PLAY) .. '}}' })
      H.bridge:poll_inbox()
    end, { ["sess-1"] = 1 } },
  { "D1 a foreign session_id inside data",
    function()
      feed({ '{"command":"action","data":{"id":"sess-2","session_id":"OLD","name":"play_hand","data":' .. json.encode(PLAY) .. '}}' })
      H.bridge:poll_inbox()
    end, { ["sess-2"] = 1 } },
  { "D2 a numeric id is silently dropped", function() feed({ action_line(42, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    {} },
  { "D2 a boolean id is silently dropped", function() feed({ action_line(true, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    {} },
  { "D2 an empty-string id is silently dropped", function() feed({ action_line("", "play_hand", "{}") }); H.bridge:poll_inbox() end,
    {} },
  { "D2 no id at all, which cannot be addressed",
    function() feed({ '{"command":"action","data":{"name":"play_hand","data":"{}"}}' }); H.bridge:poll_inbox() end,
    {}, 0 },
  { "D3 an action frame with no data",
    function() feed({ '{"command":"action"}' }); H.bridge:poll_inbox() end, {}, 0 },
  { "D3 an action frame whose data is a string",
    function() feed({ '{"command":"action","data":"not-a-table"}' }); H.bridge:poll_inbox() end, {}, 0 },
  { "D3 an action frame whose data is an array",
    function() feed({ '{"command":"action","data":[1,2,3]}' }); H.bridge:poll_inbox() end, {}, 0 },
  { "D4 an abandon frame cannot silence a later id",
    function()
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":["poison-1"]}}', action_line("poison-1") })
      H.bridge:poll_inbox()
    end, { ["poison-1"] = 1 } },
  { "D4 an abandon list above the cap abandons nothing",
    function()
      local ids = {}
      for i = 1, 65 do ids[i] = '"over-' .. i .. '"' end
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":[' .. table.concat(ids, ",") .. ']}}',
        action_line("over-1") })
      H.bridge:poll_inbox()
    end, { ["over-1"] = 1 } },
  { "D4 an abandon frame carrying an extra key is ignored",
    function()
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":["extra-1"],"why":"x"}}', action_line("extra-1") })
      H.bridge:poll_inbox()
    end, { ["extra-1"] = 1 } },
  { "D5 an abandon frame whose ids is a string",
    function()
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":"not-a-list"}}', action_line("after-5") })
      H.bridge:poll_inbox()
    end, { ["after-5"] = 1 } },
  { "D5 an abandon frame whose ids is a number",
    function()
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":7}}', action_line("after-5b") })
      H.bridge:poll_inbox()
    end, { ["after-5b"] = 1 } },
  { "a numeric id is dropped without consuming the equal string id",
    function() feed({ action_line(7, "play_hand", "{}"), action_line("7") }); H.bridge:poll_inbox() end,
    { ["7"] = 1 } },
  { "a string id is answered while the equal numeric id is dropped",
    function() feed({ action_line("8"), action_line(8, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    { ["8"] = 1 } },
  { "a boolean id is dropped without consuming the string \"true\"",
    function() feed({ action_line(true, "play_hand", "{}"), action_line("true") }); H.bridge:poll_inbox() end,
    { ["true"] = 1 } },
  { "an unregistered action name",
    function() feed({ action_line("unreg-1", "no_such_action", "{}") }); H.bridge:poll_inbox() end,
    { ["unreg-1"] = 1 } },
  { "a payload that is not valid JSON",
    function() feed({ '{"command":"action","data":{"id":"badjson-1","name":"play_hand","data":"{oops"}}' }); H.bridge:poll_inbox() end,
    { ["badjson-1"] = 1 } },
  { "a payload that is a JSON array",
    function() feed({ action_line("arr-1", "play_hand", "[1,2]") }); H.bridge:poll_inbox() end,
    { ["arr-1"] = 1 } },
  { "an action frame with no name",
    function() feed({ '{"command":"action","data":{"id":"noname-1","data":"{}"}}' }); H.bridge:poll_inbox() end,
    { ["noname-1"] = 1 } },
  { "the same id delivered twice is answered once",
    function() feed({ action_line("dup-1"), action_line("dup-1") }); H.bridge:poll_inbox() end,
    { ["dup-1"] = 1 } },
  { "an action arriving while the operator has the model paused",
    function() H.bridge.llm_paused = true; feed({ action_line("pause-1") }); H.bridge:poll_inbox() end,
    { ["pause-1"] = 1 } },
  { "a reconnect cancels a staged action without replaying it",
    function()
      feed({ action_line("recon-1") }); H.bridge:poll_inbox(); frames(2)
      feed({ '{"command":"neuro-bridge/reregister_all","transport_session":2}' }); H.bridge:poll_inbox()
    end, { ["recon-1"] = 1 } },
  { "a second action replacing a staged one",
    function() feed({ action_line("rep-1"), action_line("rep-2") }); H.bridge:poll_inbox() end,
    { ["rep-1"] = 1, ["rep-2"] = 1 } },
  { "the game state changing under a staged action",
    function()
      feed({ action_line("state-1") }); H.bridge:poll_inbox(); frames(2); G.STATE = G.STATES.HAND_PLAYED
    end, { ["state-1"] = 1 } },
  { "an abandon frame for an id already staged",
    function()
      feed({ action_line("ab-1") }); H.bridge:poll_inbox(); frames(2)
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":["ab-1"]}}' }); H.bridge:poll_inbox()
    end, { ["ab-1"] = 1 } },
  { "D7 an outbox that refuses writes while the result is produced",
    function()
      feed({ action_line("io-1") })
      H.bridge._append = function() return 0 end
      H.bridge:poll_inbox(); frames(10)
      H.bridge._append = nil
      H.bridge:update(0)
    end, { ["io-1"] = 1 } },
  { "an id 4000 bytes long",
    function() feed({ action_line(string.rep("z", 4000)) }); H.bridge:poll_inbox() end,
    { [string.rep("z", 4000)] = 1 } },
  { "an id within the frame bound",
    function() feed({ action_line(string.rep("x", 17000)) }); H.bridge:poll_inbox() end,
    { [string.rep("x", 17000)] = 1 } },
  { "a receipt still in flight when the next action arrives",
    function()
      feed({ action_line("rc-1") }); H.bridge:poll_inbox(); frames(6)
      feed({ action_line("rc-2", "help", "{}") }); H.bridge:poll_inbox()
    end, { ["rc-1"] = 1, ["rc-2"] = 1 } },
  { "non-action frames owe nothing",
    function()
      feed({ '{"command":"startup","data":{"session":{"sessionId":"s","characterId":"neuro"}}}',
        '{"command":"neuro-bridge/reregister_all","transport_session":1}',
        '{"command":"neuro-bridge/nonsense"}', '{"command":"context","data":{"message":"hi"}}', '{}' })
      H.bridge:poll_inbox()
    end, {}, 0 },
}

for _, case in ipairs(CASES) do
  local label, scenario, want, want_total = case[1], case[2], case[3], case[4]
  local r = run(scenario)
  check("no throw: " .. label, r.ok, tostring(r.err))
  local expected_total = want_total
  if expected_total == nil then
    expected_total = 0
    for _, n in pairs(want) do expected_total = expected_total + n end
  end
  local seen = 0
  local wrong = {}
  for id, n in pairs(want) do
    local got = r.counts[id_slot(id)] or 0
    seen = seen + got
    if got ~= n then
      wrong[#wrong + 1] = string.format("%s(%s) want=%d got=%d", tostring(id):sub(1, 24), type(id), n, got)
    end
  end
  check("every delivered id is answered exactly once: " .. label,
    #wrong == 0, table.concat(wrong, " | "))
  local total = 0
  for _, n in pairs(r.counts) do total = total + n end
  check("no result for an id that was never delivered: " .. label,
    total == expected_total, "want " .. expected_total .. ", outbox has " .. total)
  check("the dispatcher owes nothing once its own frames are done: " .. label,
    r.owed == 0, r.owed)
  check("the deadline sweep pays nothing, so no drop path leans on it: " .. label,
    r.swept == 0, r.swept)
end

do
  local names = {}
  for _, contract in ipairs(require("tests.helpers").registry_contracts()) do names[#names + 1] = contract.name end
  table.sort(names)
  check("the conforming sweep has an action catalog", #names > 10, #names)
  local payloads = { "{}", '{"indices":[1,2]}', '{"index":1}', '{"area":"jokers","index":1,"name":"Mock"}' }
  local offenders, combinations = {}, 0
  for _, state in ipairs({ "SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL", "MENU" }) do
    for _, name in ipairs(names) do
      for pi, payload in ipairs(payloads) do
        combinations = combinations + 1
        local id = string.format("%s-%s-%d", state, name, pi)
        local r = run(function()
          require("tests.helpers").stage_registered(state, names)
          feed({ action_line(id, name, payload) })
          H.bridge:poll_inbox()
        end)
        local got = r.counts[id_slot(id)] or 0
        if got ~= 1 or r.owed ~= 0 or r.swept ~= 0 or not r.ok then
          offenders[#offenders + 1] = string.format("%s/%s/p%d results=%d owed=%d swept=%d",
            state, name, pi, got, r.owed, r.swept)
        end
      end
    end
  end
  check("the conforming sweep covered every action in every state", combinations > 500, combinations)
  check("every conforming action is answered once by the dispatcher, never by the deadline",
    #offenders == 0, table.concat(offenders, " | "))
end

do
  for _, pair in ipairs({ { 7, "7" }, { true, "true" }, { 1.5, "1.5" } }) do
    local a, b = pair[1], pair[2]
    TxCache.reset()
    check("a non-string id " .. tostring(a) .. " books nothing",
      TxCache.open(a, "play_hand", 0) == false
        and TxCache.store(a, true, "for-a", "play_hand", nil) == false
        and #TxCache.outstanding(0) == 0 and TxCache.get(a) == nil)
    check("and the addressable string id " .. string.format("%q", b) .. " is unaffected",
      TxCache.open(b, "play_hand", 0) == true and #TxCache.outstanding(0) == 1)
  end
  TxCache.reset()
  TxCache.open("9", "play_hand", 0)
  local due = TxCache.outstanding(0)
  check("the sweep echoes the id exactly as the frame carried it",
    #due == 1 and due[1].key == "9" and type(due[1].key) == "string",
    #due == 1 and tostring(due[1].key) .. "/" .. type(due[1].key) or #due)
  TxCache.reset()
end

local function result_ids(path)
  local out = {}
  for _, frame in ipairs(require("tests.helpers").outbox_frames(path, { command = "action/result" })) do
    out[#out + 1] = frame.data.id
  end
  return out
end

do
  TxCache.reset()
  local sub = dir .. "/sweep"
  os.execute("mkdir -p '" .. sub .. "'")
  local b = Bridge:new({ enabled = true, fs_dir = sub })
  b:set_message_handler(function() end)
  CLOCK.t = 2000
  G.TIMERS.REAL = CLOCK.t
  b:_deliver_inbox_message({ command = "action", data = { id = "late-1", name = "play_hand", data = "{}" } })
  b:answer_owed_results(Bridge.RESULT_DEADLINE_SECS)
  check("an unanswered action is not paid before its deadline", #result_ids(sub .. "/neuro_outbox.jsonl") == 0)
  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS
  G.TIMERS.REAL = CLOCK.t
  b:answer_owed_results(Bridge.RESULT_DEADLINE_SECS)
  b:answer_owed_results(Bridge.RESULT_DEADLINE_SECS)
  local ids = result_ids(sub .. "/neuro_outbox.jsonl")
  check("the deadline sweep answers it exactly once", #ids == 1 and ids[1] == "late-1", #ids)
  check("and a handler answering afterwards cannot add a second result",
    b:send_action_result("late-1", false, "late") == false
      and #result_ids(sub .. "/neuro_outbox.jsonl") == 1)
  local prior = G.NEURO
  G.NEURO = b
  b._registered_sigs = b._registered_sigs or {}
  b._registered_sigs.play_hand, b._registered_sigs.discard_hand = true, true
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  b:_deliver_inbox_message({ command = "action", data = { id = "late-2", name = "play_hand", data = "{}" } })
  CLOCK.t = CLOCK.t + Bridge.RESULT_DEADLINE_SECS
  G.TIMERS.REAL = CLOCK.t
  b:answer_owed_results(Bridge.RESULT_DEADLINE_SECS)
  local f = io.open(sub .. "/neuro_outbox.jsonl", "rb")
  local raw = f and f:read("*a") or ""
  if f then f:close() end
  local unreg = raw:find('"actions/unregister"', 1, true)
  local paid = raw:find('"late-2"', 1, true)
  check("a swept success on the open force takes its whole offer off first (ActionWindowResponse.cs:20)",
    unreg ~= nil and paid ~= nil and unreg < paid
      and raw:find('"discard_hand"', unreg, true) ~= nil and require("core.window").current() == nil)
  G.NEURO = prior
  local wide = string.rep("\1", math.floor((Bridge.MAX_ACTION_ID_BYTES - 2) / 6))
  check("the widest addressable id is still answered with its own verdict",
    b:send_action_result(wide, false, "verdict") == true
      and result_ids(sub .. "/neuro_outbox.jsonl")[3] == wide)
  TxCache.reset()
end

do
  local handled, window = 0, nil
  local r = run(function()
    feed({ action_line("dup-1", "help", "{}") }); H.bridge:poll_inbox(); frames(4)
    local route = H.bridge.on_message
    H.bridge:set_message_handler(function(msg) handled = handled + 1; return route(msg) end)
    window = { phase = "forced", names = { "play_hand" }, set = { play_hand = true }, state = "SELECTING_HAND" }
    H.bridge.force_window = window
    feed({ action_line("dup-1", "help", "{}") }); H.bridge:poll_inbox()
    feed({ action_line("dup-1", "help", "{}") }); H.bridge:poll_inbox()
    H.bridge.force_window = nil
  end)
  check("a redelivered answered id gets no second result",
    r.ok and (r.counts[id_slot("dup-1")] or 0) == 1, tostring(r.counts[id_slot("dup-1")]))
  check("without re-executing or touching the open window",
    handled == 0 and window.phase == "forced" and window.ended_by == nil, handled)
end

do
  TxCache.reset()
  local sub = dir .. "/owed_dup"
  os.execute("mkdir -p '" .. sub .. "'")
  local b = Bridge:new({ enabled = true, fs_dir = sub })
  local handled = 0
  b:set_message_handler(function() handled = handled + 1 end)
  local frame = { command = "action", data = { id = "owed-dup", name = "help", data = "{}" } }
  b:_deliver_inbox_message(frame)
  b:_deliver_inbox_message(frame)
  check("a redelivered id still owed its result reaches the dispatcher once", handled == 1, handled)
  TxCache.reset()
end

do
  TxCache.reset()
  local sub = dir .. "/quit"
  os.execute("mkdir -p '" .. sub .. "'")
  local b = Bridge:new({ enabled = true, fs_dir = sub })
  b:set_message_handler(function() end)
  G.NEURO = b
  b:register_actions({ { name = "play_hand", description = "play", schema = { type = "object" } } })
  b:_deliver_inbox_message({ command = "action", data = { id = "quit-1", name = "play_hand", data = "{}" } })
  b:_deliver_inbox_message({ command = "action", data = { id = "quit-2", name = "play_hand", data = "{}" } })
  local quit_called = false
  love.quit = function() quit_called = true end
  require("core.bridge_init").hook_love_quit()
  love.quit()
  local ids = result_ids(sub .. "/neuro_outbox.jsonl")
  table.sort(ids)
  check("quit answers every outstanding action exactly once",
    #ids == 2 and ids[1] == "quit-1" and ids[2] == "quit-2", #ids)
  local f = io.open(sub .. "/neuro_outbox.jsonl", "rb")
  local raw = f:read("*a")
  f:close()
  check("and withdraws the catalogue before the original quit runs",
    raw:find('"actions/unregister"', 1, true) ~= nil and quit_called)
  G.NEURO = H.bridge
  TxCache.reset()
end

do
  TxCache.reset()
  local handlerless = Bridge:new({ enabled = true, fs_dir = dir })
  handlerless.on_message = nil
  handlerless:_deliver_inbox_message({ command = "action",
    data = { id = "no-handler-1", name = "play_hand", data = "{}" } })
  local due = TxCache.outstanding(0)
  check("119: an action delivered with no handler installed still books its obligation",
    #due == 1 and due[1].key == "no-handler-1", #due == 1 and tostring(due[1].key) or #due)

  local paid = {}
  handlerless.send_action_result = require("tests.helpers").result_log(paid, { "id", "ok", "message" }, true)
  handlerless:answer_owed_results(0, "swept")
  check("119: and the deadline sweep acknowledges it, so the client is never left waiting",
    #paid == 1 and paid[1].id == "no-handler-1" and paid[1].ok == true,
    #paid == 1 and tostring(paid[1].id) or #paid)
  TxCache.reset()
end

H.cleanup()
TmpWork.close()
done()
