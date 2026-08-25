love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 } }

local ok_d, Dispatcher = pcall(require, "core.dispatcher")
if not ok_d then print("REQUIRE dispatcher FAIL: " .. tostring(Dispatcher)); os.exit(3) end
local ok_a, Actions = pcall(require, "core.actions")
if not ok_a then print("REQUIRE actions FAIL: " .. tostring(Actions)); os.exit(3) end
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local iters = tonumber(arg and arg[1]) or 4000
local ok_t, FZ = pcall(require, "tests.test_force_fuzz")
if not ok_t then print("REQUIRE test_force_fuzz FAIL: " .. tostring(FZ)); os.exit(3) end
local ok_r, fails = pcall(FZ.run, iters)
if not ok_r then print("RUN ERROR: " .. tostring(fails)); os.exit(4) end
if type(fails) ~= "number" then print("RUN ERROR: non-numeric fail count"); os.exit(4) end
print("FUZZ_FAILS=" .. fails .. " (0 = clean)")
os.exit(fails == 0 and 0 or 1)
