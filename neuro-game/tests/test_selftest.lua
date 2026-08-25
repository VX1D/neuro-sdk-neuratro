if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = {
  NEURO = {}, FUNCS = {}, GAME = { current_round = {} },
  STATES = { MENU = 1, SPLASH = 2, BLIND_SELECT = 3, SELECTING_HAND = 4 },
  STATE = 1,
  STAGES = { MAIN_MENU = 0, RUN = 1 },
  STAGE = 0,
}

local ST = require("core.selftest")

local check, done = require("tests.helpers").harness("selftest")

local function drain(max_ticks, dt)
  for _ = 1, max_ticks or 200 do
    if not ST.running() then return true end
    ST.tick(dt or 0.5)
  end
  return not ST.running()
end

check("available in MENU", ST.available())
G.STATE = 99
check("not available in unknown state", not ST.available())
G.STATE = G.STATES.MENU
G.STAGE = G.STAGES.RUN
check("not available with active run stage", not ST.available())
G.STAGE = G.STAGES.MAIN_MENU
check("available again from menu", ST.available())

do
  local stat_calls, teardown_ran, reset_count = 0, false, 0
  _G.inc_career_stat = function() stat_calls = stat_calls + 1 end
  _G.save_run = function() stat_calls = stat_calls + 100 end

  local order = {}
  local cases = {
    {
      name = "t/pass",
      setup = function(ctx) order[#order + 1] = "setup1"; ctx.v = 41 end,
      act = function(ctx) ctx.v = ctx.v + 1; _G.inc_career_stat("x", 1); _G.save_run() end,
      wait_for = function() return true end,
      assert = function(ctx) return ctx.v == 42, "v=" .. tostring(ctx.v) end,
    },
    {
      name = "t/act_crash",
      act = function() error("boom") end,
      teardown = function() teardown_ran = true end,
    },
    {
      name = "t/timeout",
      timeout_s = 1,
      act = function() end,
      wait_for = function() return false end,
    },
    {
      name = "t/after_failures",
      act = function() end,
      wait_for = function() return true end,
      assert = function() return true, "still running" end,
    },
  }

  local ok, err = ST.start({ sandbox = false, report = false, cases = cases, reset = function() reset_count = reset_count + 1 end })
  check("start ok offline", ok, err)
  check("LLM paused during suite", G.NEURO.llm_paused == true, tostring(G.NEURO.llm_paused))
  check("running() true after start", ST.running())
  check("not available while running", not ST.available())
  local ok2, err2 = ST.start({ sandbox = false, cases = cases })
  check("second start rejected while running", not ok2 and err2 ~= nil, tostring(err2))

  check("finishes", drain(300))

  local r = ST.results()
  check("4 results recorded", #r == 4, tostring(#r))
  check("case order preserved", r[1].name == "t/pass" and r[2].name == "t/act_crash" and r[3].name == "t/timeout" and r[4].name == "t/after_failures")
  check("pass case PASS", r[1].ok)
  check("crashing case FAIL with error text", not r[2].ok and r[2].detail:find("boom") ~= nil, r[2].detail)
  check("teardown ran after act crash", teardown_ran)
  check("timeout case FAIL mentions timeout", not r[3].ok and r[3].detail:find("timeout") ~= nil, r[3].detail)
  check("suite continues past failures", r[4].ok, r[4].detail)
  check("reset ran between every case", reset_count == 4, tostring(reset_count))

  check("guards suppressed engine stats/saves during run", stat_calls == 0, tostring(stat_calls))
  _G.inc_career_stat("x", 1)
  _G.save_run()
  check("guards restored after finish", stat_calls == 101, tostring(stat_calls))
  check("F_NO_SAVING restored", rawget(G, "F_NO_SAVING") == nil, tostring(rawget(G, "F_NO_SAVING")))
  check("llm_paused restored after finish", rawget(G.NEURO, "llm_paused") == nil, tostring(rawget(G.NEURO, "llm_paused")))
  check("running() false after finish", not ST.running())
  check("available again after finish", ST.available())
end

do
  local md = ST.render_report(ST.results())
  check("report is a string", type(md) == "string")
  check("report has header", md:find("self%-test report") ~= nil)
  check("report lists PASS", md:find("PASS") ~= nil)
  check("report lists FAIL", md:find("FAIL") ~= nil)
  check("report names cases", md:find("t/timeout", 1, true) ~= nil)
  check("report has totals line", md:find("Cases: 4") ~= nil, md:match("Cases:[^\n]*"))
end

do
  local s = ST.status()
  check("status is string", type(s) == "string")
  check("status has counters", s:find("pass:") ~= nil and s:find("fail:") ~= nil, s)
end

do
  local stat_calls = 0
  _G.inc_career_stat = function() stat_calls = stat_calls + 1 end
  local cases = {
    { name = "a/forever", timeout_s = 999, act = function() end, wait_for = function() return false end },
  }
  local ok = ST.start({ sandbox = false, report = false, cases = cases })
  check("abort-suite starts", ok)
  ST.tick(0.5)
  ST.tick(0.5)
  check("abort-suite running", ST.running())
  ST.abort()
  check("abort stops the run", not ST.running())
  local r = ST.results()
  check("abort recorded", not r[#r].ok and r[#r].name == "selftest/abort", r[#r] and r[#r].name)
  _G.inc_career_stat("x", 1)
  check("guards restored after abort", stat_calls == 1, tostring(stat_calls))
end

do
  local acted = false
  local cases = {
    { name = "c/wait_crash", act = function() end, wait_for = function() error("wboom") end },
    { name = "c/assert_crash", act = function() end, wait_for = function() return true end, assert = function() error("aboom") end },
    { name = "c/setup_crash", setup = function() error("sboom") end, act = function() acted = true end },
  }
  local ok = ST.start({ sandbox = false, report = false, cases = cases })
  check("crash-suite starts", ok)
  check("crash-suite finishes", drain(200))
  local r = ST.results()
  check("wait_for crash is FAIL", not r[1].ok and r[1].detail:find("wboom") ~= nil, r[1].detail)
  check("assert crash is FAIL", not r[2].ok and r[2].detail:find("aboom") ~= nil, r[2].detail)
  check("setup crash is FAIL", not r[3].ok and r[3].detail:find("sboom") ~= nil, r[3].detail)
  check("setup crash skips act", not acted)
end

do
  local ok, err = ST.start({ sandbox = false, report = false, cases = {} })
  check("empty case list rejected", not ok and err ~= nil, tostring(err))
end

do
  local AR = require("core.action_result")
  local function detail_for(thrower)
    ST.start({ sandbox = false, report = false, cases = {
      { name = "diag/case", timeout_s = 1, act = thrower, wait_for = function() return true end },
    } })
    drain(50, 0.5)
    local res = ST.results()
    return res[1] and res[1].detail or ""
  end

  local typed = detail_for(function()
    error(AR.error("PRECONDITION_FAILED", "no discards left"))
  end)
  check("diagnostics: a typed action error keeps its reason code",
    typed:find("PRECONDITION_FAILED", 1, true) ~= nil, typed)
  check("diagnostics: a typed action error keeps its message",
    typed:find("no discards left", 1, true) ~= nil, typed)
  check("diagnostics: a typed action error is never a bare table address",
    typed:find("table: 0x", 1, true) == nil, typed)

  local plain = detail_for(function() error({ code = 7, why = "raw" }) end)
  check("diagnostics: an untyped table error is still summarised, not an address",
    plain:find("table: 0x", 1, true) == nil
      and plain:find("why=raw", 1, true) ~= nil, plain)

  local str = detail_for(function() error("plain boom") end)
  check("diagnostics: a string error keeps its text",
    str:find("plain boom", 1, true) ~= nil, str)
end

done()
