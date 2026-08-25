_G.NEURO_TEST = true
_G.G = { NEURO = {}, GAME = {}, FUNCS = {} }
_G.save_run = function() return true end

local Metrics = require("util.metrics")
local CrashGuards = require("core.crash_guards")
local check, done = require("tests.helpers").harness("crash-guard-save")
CrashGuards.install()

local before_skip = CrashGuards._test.save_skip_total()
local before_metric = Metrics._counters.crash_guard_save_skip or 0
_G.save_run()
local after_skip = CrashGuards._test.save_skip_total()
local after_metric = Metrics._counters.crash_guard_save_skip or 0

check("an incomplete game save increments the crash-guard skip counter",
  after_skip == before_skip + 1, "before=" .. before_skip .. " after=" .. after_skip)
check("an incomplete game save increments the crash_guard_save_skip metric",
  after_metric == before_metric + 1, "before=" .. before_metric .. " after=" .. after_metric)

G.GAME = { blind = {}, current_scoring_calculation = {}, selected_back = {} }
_G.save_run()
check("a complete game save proceeds without incrementing the skip counter",
  CrashGuards._test.save_skip_total() == after_skip,
  "skip=" .. CrashGuards._test.save_skip_total())

done()
