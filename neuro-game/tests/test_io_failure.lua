local check, done = require("tests.helpers").harness("io-failure")

local full = io.open("/dev/full", "a")
if full then
  local w = full:write("x\n")
  local fl = full:flush()
  full:close()
  check("/dev/full: write does not signal an error (a bare pcall would miss it)", w ~= nil)
  check("/dev/full: flush signals the error as nil, not a thrown exception", fl == nil)
else
  require("tests.skip_ledger").note("io-failure/dev-full", 2,
    "/dev/full unavailable, the empirical write()/flush() proof did not run")
end
done()
