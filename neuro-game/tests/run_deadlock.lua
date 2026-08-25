love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, }
local ok_d, Dispatcher = pcall(require, "core.dispatcher")
if not ok_d then print("REQUIRE dispatcher FAIL: "..tostring(Dispatcher)); os.exit(3) end
local ok_a, Actions = pcall(require, "core.actions")
if not ok_a then print("REQUIRE actions FAIL: "..tostring(Actions)); os.exit(3) end
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions
local ok_t, TD = pcall(require, "tests.test_deadlock")
if not ok_t then print("REQUIRE test_deadlock FAIL: "..tostring(TD)); os.exit(3) end
local ok_r, fails = pcall(TD.run)
if not ok_r then print("RUN ERROR: "..tostring(fails)); os.exit(4) end
if type(fails) ~= "number" then print("RUN ERROR: non-numeric fail count: "..tostring(fails)); os.exit(4) end
print("FAILS="..fails.." (XFAILs excluded; 0 = clean, >=1 = regression)")
os.exit(fails == 0 and 0 or 1)
