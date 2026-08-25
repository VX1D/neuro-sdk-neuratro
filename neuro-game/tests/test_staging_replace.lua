_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 } }

local Staging = require("core.staging")
local check, done = require("tests.helpers").harness("staging-replace")

local function msg(id, name)
  return { command = "action", data = { id = id, name = name, data = "{}" } }
end
local bridge = { send_action_result = function() return true end, send_context = function() return true end }

local verdicts = { ["A1"] = true, ["A2"] = false }
Staging._test.set_validator(function(m) return verdicts[m.data.id] end)
Staging.set_executor(function() return true end)

local q1 = Staging.queue(msg("A1", "play_hand"), bridge)
check("the first action is accepted into staging", q1 ~= false)
check("the first action is staged", Staging.is_busy() == true)

local q2 = Staging.queue(msg("A2", "discard_hand"), bridge)
check("the successor is rejected during validation", q2 == false)
check("a rejected successor does not erase the staged action "
  .. "(Neuro already received success=true for A1 -- SPECIFICATION.md:184-188)",
  Staging.is_busy() == true)

verdicts["A3"] = true
local q3 = Staging.queue(msg("A3", "discard_hand"), bridge)
check("the validated successor is accepted", q3 ~= false)
check("a validated successor replaces the previous action", Staging.is_busy() == true)

Staging.reset_run_state()
G.NEURO.state = "SHOP"
verdicts["A4"] = true
local State = require("core.state")
local original_get_state_name = State.get_state_name
State.get_state_name = function() error("state snapshot exploded") end
local ok_state, q4 = pcall(Staging.queue, msg("A4", "play_hand"), bridge)
State.get_state_name = original_get_state_name
check("state snapshot failure after validation cannot orphan the staged action",
  ok_state and q4 ~= false and Staging.is_busy() == true,
  "pcall=" .. tostring(ok_state) .. " queue=" .. tostring(q4)
    .. " busy=" .. tostring(Staging.is_busy()))

done()
