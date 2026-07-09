-- standalone runner for the force round-trip invariant suite (luajit tests/run_roundtrip.lua)
package.path = "./?.lua;;" .. package.path
_G.__RT_CLOCK = 0
love = { timer = { getTime = function() return _G.__RT_CLOCK or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 } }

local ok_d, Dispatcher = pcall(require, "core.dispatcher")
if not ok_d then print("REQUIRE dispatcher FAIL: " .. tostring(Dispatcher)); os.exit(3) end
local ok_a, Actions = pcall(require, "core.actions")
if not ok_a then print("REQUIRE actions FAIL: " .. tostring(Actions)); os.exit(3) end
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local ok_t, RT = pcall(require, "tests.test_force_roundtrip")
if not ok_t then print("REQUIRE test_force_roundtrip FAIL: " .. tostring(RT)); os.exit(3) end
local ok_r, fails = pcall(RT.run)
if not ok_r then print("RUN ERROR: " .. tostring(fails)); os.exit(4) end
if type(fails) ~= "number" then print("RUN ERROR: non-numeric fail count: " .. tostring(fails)); os.exit(4) end
print("ROUNDTRIP_FAILS=" .. fails .. " (0 = clean, >=1 = invariant violation)")
os.exit(fails == 0 and 0 or 1)
