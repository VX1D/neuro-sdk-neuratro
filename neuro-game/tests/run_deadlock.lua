love = { timer = { getTime = function() return 0 end } }
require("tests.helpers").run_module("tests.test_deadlock", "DEADLOCK", "plain")
