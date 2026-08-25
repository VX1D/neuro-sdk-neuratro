_G.NEURO_TEST = true

local CLOCK = { t = 1000 }
love = { timer = { getTime = function() return CLOCK.t end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1000 } }

local check, done = require("tests.helpers").harness("inbound-obligation")

local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local ForceState = require("core.force_state")
local Staging = require("core.staging")
local TxCache = require("core.tx_cache")
local ActionRegistry = require("core.action_registry")
local json = require("util.neuro_json")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("inbound_obligation")

local Harness = require("tests.inbound_harness")
local H = Harness.new({ dir = dir, clock = CLOCK })
local id_slot = Harness.id_slot
local feed, frames, run, action_line = H.feed, H.frames, H.run, H.action_line

local PLAY = '{"indices":[1,2]}'

local documented_drop_labels = {
  route_no_message = true,
  route_abandoned_id = true,
  route_missing_action_id = true,
  route_staged = true,
  handle_no_command = true,
  handle_abandon_command = true,
  handle_abandon_malformed = true,
  handle_abandoned_id = true,
  handle_missing_action_id = true,
  handle_prepared_generation_abort = true,
  handle_reregister_all = true,
  handle_reregister_no_state_actions = true,
  handle_startup = true,
  handle_non_action = true,
  validate_message_non_action = true,
  validate_message_abandoned_id = true,
  validate_message_missing_action_id = true,
}

local function key_diff(a, b)
  local out = {}
  for key in pairs(a) do if not b[key] then out[#out + 1] = key end end
  table.sort(out)
  return table.concat(out, ",")
end

check("every dispatcher drop label is covered by the inbound obligation model",
  key_diff(Dispatcher._test.drop_labels, documented_drop_labels) == "",
  key_diff(Dispatcher._test.drop_labels, documented_drop_labels))
check("the inbound obligation model names no obsolete dispatcher drop label",
  key_diff(documented_drop_labels, Dispatcher._test.drop_labels) == "",
  key_diff(documented_drop_labels, Dispatcher._test.drop_labels))

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
  { "D2 a numeric id", function() feed({ action_line(42, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    { ["42"] = 1 } },
  { "D2 a boolean id", function() feed({ action_line(true, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    { ["true"] = 1 } },
  { "D2 an empty-string id", function() feed({ action_line("", "play_hand", "{}") }); H.bridge:poll_inbox() end,
    { [""] = 1 } },
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
  { "a numeric id does not consume the ledger slot of the equal string id",
    function() feed({ action_line(7, "play_hand", "{}"), action_line("7") }); H.bridge:poll_inbox() end,
    { ["7"] = 2 } },
  { "a string id does not consume the ledger slot of the equal numeric id",
    function() feed({ action_line("8"), action_line(8, "play_hand", "{}") }); H.bridge:poll_inbox() end,
    { ["8"] = 2 } },
  { "a boolean id does not consume the ledger slot of the string \"true\"",
    function() feed({ action_line(true, "play_hand", "{}"), action_line("true") }); H.bridge:poll_inbox() end,
    { ["true"] = 2 } },
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
  { "a reconnect bumping the generation under a staged action",
    function()
      feed({ action_line("recon-1") }); H.bridge:poll_inbox(); frames(2)
      feed({ '{"command":"actions/reregister_all","transport_session":2}' }); H.bridge:poll_inbox()
    end, { ["recon-1"] = 1 } },
  { "a second action replacing a staged one",
    function() feed({ action_line("rep-1"), action_line("rep-2") }); H.bridge:poll_inbox() end,
    { ["rep-1"] = 1, ["rep-2"] = 1 } },
  { "the game state changing under a staged action",
    function()
      feed({ action_line("state-1") }); H.bridge:poll_inbox(); frames(2); G.STATE = 987
    end, { ["state-1"] = 1 } },
  { "an abandon frame for an id already staged",
    function()
      feed({ action_line("ab-1") }); H.bridge:poll_inbox(); frames(2)
      feed({ '{"command":"neuro-bridge/abandon","data":{"ids":["ab-1"]}}' }); H.bridge:poll_inbox()
    end, { ["ab-1"] = 1 } },
  { "D7 an outbox that refuses writes while the result is produced",
    function()
      feed({ action_line("io-1") })
      local real_append = H.bridge.append_file
      H.bridge.append_file = function() return false end
      H.bridge:poll_inbox(); frames(10)
      H.bridge.append_file = real_append
      H.bridge:update(0)
    end, { ["io-1"] = 1 } },
  { "an id 4000 bytes long",
    function() feed({ action_line(string.rep("z", 4000)) }); H.bridge:poll_inbox() end,
    { [string.rep("z", 4000)] = 1 } },
  { "a receipt still in flight when the next action arrives",
    function()
      feed({ action_line("rc-1") }); H.bridge:poll_inbox(); frames(6)
      feed({ action_line("rc-2", "help", "{}") }); H.bridge:poll_inbox()
    end, { ["rc-1"] = 1, ["rc-2"] = 1 } },
  { "non-action frames owe nothing",
    function()
      feed({ '{"command":"startup","data":{"session":{"sessionId":"s","characterId":"neuro"}}}',
        '{"command":"actions/reregister_all","transport_session":1}',
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
  for _, contract in ipairs(ActionRegistry.all()) do names[#names + 1] = contract.name end
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
    check("open/claim on " .. tostring(a) .. " leaves " .. tostring(b) .. " claimable",
      TxCache.open(a, "play_hand", 0) == true and TxCache.claim(a) == true
        and TxCache.open(b, "play_hand", 0) == true and TxCache.claim(b) == true)
    TxCache.reset()
    check("a verdict stored for " .. tostring(a) .. " is not replayed for " .. tostring(b),
      (function()
        TxCache.store(a, true, "for-a", "play_hand", nil)
        return TxCache.get(a) ~= nil and TxCache.get(b) == nil
      end)())
  end
  TxCache.reset()
  TxCache.open(9, "play_hand", 0)
  local due = TxCache.outstanding(0)
  check("the sweep echoes the id with the type the frame carried",
    #due == 1 and due[1].key == 9 and type(due[1].key) == "number",
    #due == 1 and tostring(due[1].key) .. "/" .. type(due[1].key) or #due)
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
  handlerless.send_action_result = function(_, id, ok, message)
    paid[#paid + 1] = { id = id, ok = ok, message = message }
    return true
  end
  handlerless:answer_owed_results(0, "swept")
  check("119: and the deadline sweep pays it, so the client is never left waiting",
    #paid == 1 and paid[1].id == "no-handler-1" and paid[1].ok == true,
    #paid == 1 and tostring(paid[1].id) or #paid)
  TxCache.reset()
end

H.cleanup()
TmpWork.close()
done()
