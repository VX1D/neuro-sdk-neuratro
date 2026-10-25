require("tests.stubs").setup({ love = "timers" })
require("tests.helpers").run_module("tests.test_staging_roundtrip", "STAGING", "timed")
