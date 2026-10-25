love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
require("tests.helpers").run_module("tests.test_force_fuzz", "FUZZ", "timed", tonumber(arg and arg[1]) or 4000)
