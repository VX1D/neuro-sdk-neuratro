_G.__RT_CLOCK = 0
love = { timer = { getTime = function() return _G.__RT_CLOCK or 0 end } }
require("tests.helpers").run_module("tests.test_force_roundtrip", "ROUNDTRIP", "timed")
