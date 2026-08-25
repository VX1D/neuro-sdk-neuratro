local M = {}

M.MARK = "==SKIP=="
M.EXIT_INCOMPLETE = 3

local function require_complete()
  return os.getenv("REQUIRE_COMPLETE") == "1"
end

function M.note(label, count, reason)
  count = tonumber(count) or 0
  io.write(string.format("%s %d %s -- %s\n", M.MARK, count, tostring(label), tostring(reason)))
  io.flush()
  if require_complete() then
    io.write(string.format("INCOMPLETE  %s -- REQUIRE_COMPLETE=1 and %d check(s) could not run\n",
      tostring(label), count))
    io.flush()
    os.exit(M.EXIT_INCOMPLETE)
  end
end

function M.bail(label, count, reason)
  M.note(label, count, reason)
  io.write(string.format("==== %s: 0/0 PASS, 0 FAIL -- SKIPPED (%s) ====\n",
    tostring(label), tostring(reason)))
  io.flush()
  os.exit(0)
end

return M
