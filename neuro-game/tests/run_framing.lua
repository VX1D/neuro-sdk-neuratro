_G.NEURO_TEST = true  -- must be set before any require or the _test export seams never install
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 } }

local ok_d, Dispatcher = pcall(require, "core.dispatcher")
if not ok_d then print("REQUIRE dispatcher FAIL: " .. tostring(Dispatcher)); os.exit(3) end
local ok_a, Actions = pcall(require, "core.actions")
if not ok_a then print("REQUIRE actions FAIL: " .. tostring(Actions)); os.exit(3) end
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local ok_t, FC = pcall(require, "tests.test_framing_consistency")
if not ok_t then print("REQUIRE test_framing_consistency FAIL: " .. tostring(FC)); os.exit(3) end
local ok_r, fails, checks = pcall(FC.run)
if not ok_r then print("RUN ERROR: " .. tostring(fails)); os.exit(4) end
if type(fails) ~= "number" or type(checks) ~= "number" then
  print("RUN ERROR: non-numeric fail or check count"); os.exit(4)
end
print("FRAMING_FAILS=" .. fails .. " (0 = clean) FRAMING_CHECKS=" .. checks)
os.exit(fails == 0 and 0 or 1)
