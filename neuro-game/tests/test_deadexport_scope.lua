local check, done = require("tests.helpers").harness("deadexport_scope")

local p = io.popen("env FAIL_ON_FINDINGS=1 luajit tests/dump_deadexport_scan.lua 2>&1")
local output = p:read("*all")
local ok, exit_type, exit_code = p:close()

check("the scanner exits successfully", ok and (exit_code == nil or exit_code == 0),
  tostring(ok) .. " / " .. tostring(exit_type) .. " / " .. tostring(exit_code))

local function extract_metric(name)
  local val = output:match(name .. "=(%d+)")
  return val and tonumber(val)
end

check("DEADEXPORT_PRODUCTION_ONLY=0",
  extract_metric("DEADEXPORT_PRODUCTION_ONLY") == 0,
  tostring(extract_metric("DEADEXPORT_PRODUCTION_ONLY")))
check("DEADEXPORT_BASELINE_MISMATCH=0",
  extract_metric("DEADEXPORT_BASELINE_MISMATCH") == 0,
  tostring(extract_metric("DEADEXPORT_BASELINE_MISMATCH")))
check("the test-only baseline is empty", output:find("production-dead but consumed by tests", 1, true) == nil)
check("the scanner reports no dead exports", output:find("exports with no dotted call", 1, true) == nil)

local strip = require("tests.helpers").strip_lua_comments

check("a mention inside a comment does not count as a use",
  strip("-- Scoring.hand_ceiling counts guaranteed only\nlocal x = 1"):find("hand_ceiling", 1, true) == nil,
  strip("-- Scoring.hand_ceiling counts guaranteed only\nlocal x = 1"))
check("a trailing line comment is stripped, the code on the line remains",
  strip("Scoring.live_call() -- Scoring.dead_call") == "Scoring.live_call() ",
  strip("Scoring.live_call() -- Scoring.dead_call"))
check("two dashes inside a double-quoted string are not a comment",
  strip('local s = "a -- b"'):find("a -- b", 1, true) ~= nil,
  strip('local s = "a -- b"'))
check("two dashes inside a single-quoted string are not a comment either",
  strip("local s = 'x -- y'"):find("x -- y", 1, true) ~= nil,
  strip("local s = 'x -- y'"))
check("an escaped quote does not close the string early",
  strip('local s = "a\\" -- b" print(1)'):find("print(1)", 1, true) ~= nil,
  strip('local s = "a\\" -- b" print(1)'))
check("the line count is preserved",
  select(2, strip("a\n-- b\nc"):gsub("\n", "")) == 2,
  strip("a\n-- b\nc"))

local block = "local a = 1 --[==[ note ]==] local b = Zz.after_block()"
check("a block comment with = signs does not eat the code after it",
  strip(block):find("Zz.after_block()", 1, true) ~= nil, strip(block))
check("and the block comment itself is removed",
  strip(block):find("note", 1, true) == nil, strip(block))

local longstr = "local s = [[ -- not a comment ]]"
check("a long string is not cut on a double dash",
  strip(longstr) == longstr, strip(longstr))
local longstr_eq = "local s = [==[ -- still not a comment ]==] Zz.tail()"
check("a long string with = signs is not cut either",
  strip(longstr_eq) == longstr_eq, strip(longstr_eq))

local multi = "--[[\nZz.inside_block()\n]]\nlocal b = 1"
check("the body of a multiline block comment does not survive",
  strip(multi):find("Zz.inside_block", 1, true) == nil, strip(multi))
check("code after a multiline block comment remains",
  strip(multi):find("local b = 1", 1, true) ~= nil, strip(multi))
check("a multiline block comment preserves the line count",
  select(2, strip(multi):gsub("\n", "")) == 3, select(2, strip(multi):gsub("\n", "")))

done()
