_G.NEURO_TEST = true
local clock = { t = 1000 }
love = { timer = { getTime = function() return clock.t end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = clock.t, TOTAL = clock.t } }
local Utils = require("util.utils"); Utils.now = function() return clock.t end

local check, done = require("tests.helpers").harness("missing_action_name")
local Harness = require("tests.inbound_harness")
local Dispatcher = require("core.dispatcher")
local json = require("util.neuro_json")

local H = Harness.new({ clock = clock, registered = { "play_hand", "discard_hand" } })
H.fresh()

local id = "noname-1"

local ok1, err1 = pcall(function()
  Dispatcher.route_message({ command = "action", data = { id = id } }, H.bridge)
end)
check("the dispatcher does not crash on an action with no name key at all", ok1 == true,
  tostring(err1))
H.frames(10)

local ok2, err2 = pcall(function()
  Dispatcher.route_message({ command = "action", data = { id = id } }, H.bridge)
end)
check("redelivery of the same nameless id does not crash either", ok2 == true, tostring(err2))
H.frames(10)

local ok3, err3 = pcall(function()
  Dispatcher.route_message({ command = "action", data = { id = "noname-2", name = "" } }, H.bridge)
end)
check("an action with an empty-string name does not crash", ok3 == true, tostring(err3))
H.frames(10)

local function results_for(target_id)
  local matches = {}
  local f = io.open(H.outbox, "r")
  if not f then return matches end
  for line in f:lines() do
    local dok, frame = pcall(json.decode, line)
    if dok and type(frame) == "table" and frame.command == "action/result"
      and frame.data and tostring(frame.data.id) == target_id then
      matches[#matches + 1] = frame.data
    end
  end
  f:close()
  return matches
end

if ok1 and ok2 then
  local results = results_for(id)
  check("exactly one terminal action/result was emitted for the nameless action",
    #results == 1, #results)
  check("that result reports failure, since nothing was executed",
    results[1] and results[1].success == false, results[1] and tostring(results[1].success))
  check("the redelivery produced no second result for the same id",
    #results == 1, #results)
else
  check("skipped result-shape checks because the drive crashed (already failed above)", false)
end

if ok3 then
  local results2 = results_for("noname-2")
  check("an empty-string name also gets exactly one failed result",
    #results2 == 1 and results2[1].success == false,
    #results2 .. "/" .. tostring(results2[1] and results2[1].success))
end

H.cleanup()
done()
