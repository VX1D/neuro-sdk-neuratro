local Helpers = require("tests.helpers")
local check, done = Helpers.harness("harness-hygiene")

local TMP_LITERAL_OK = { ["tests/tmp_workdir.lua"] = true }

local OS_TIME_OK = {
  ["tests/test_action_registry.lua"] = "asserts the registry's own os.time() stamp, not a path",
}

local EXIT0_OK = {
  ["tests/skip_ledger.lua"] = "the skip channel itself",
  ["../scripts/raster.lua"] = "offline rasteriser CLI",
  ["tests/dump_context.lua"] = "context dump CLI",
  ["tests/dump_dup_scan.lua"] = "duplicate-section scan CLI",
}

local SKIP_PRINT_OK = { ["tests/skip_ledger.lua"] = true }

local function scanned_files()
  local out, p = {}, io.popen("find tests -name '*.lua'; ls ../scripts/*.lua 2>/dev/null || ls scripts/*.lua; ls tests/*.sh")
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  table.sort(out)
  return out
end

local function stripped(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local src = fh:read("*a")
  fh:close()
  if path:match("%.lua$") then return Helpers.strip_lua_comments(src) end
  return (src:gsub("#[^\n]*", ""))
end

local SELF = "tests/test_harness_hygiene.lua"

local EXIT_OK_PATTERNS = { "os%.exit%s*%(%s*0%s*%)", "os%.exit%s*%(%s*%)", "os%.exit%s*%(%s*true" }
local function exits_ok(src)
  for _, pat in ipairs(EXIT_OK_PATTERNS) do
    if src:find(pat) then return true end
  end
  return false
end

local files = scanned_files()
check("the hygiene scan sees every file run_all.sh can execute (" .. #files .. " files)",
  #files >= 375, #files)
do
  local dirs = {}
  for _, path in ipairs(files) do dirs[path:match("^(.-)/[^/]+$") or "."] = true end
  local sh = false
  for _, path in ipairs(files) do if path:match("%.sh$") then sh = true end end
  check("the scan reaches fixtures, scripts/ and the shell entries, not just tests/*.lua",
    dirs["tests/fixtures"] ~= nil and (dirs["scripts"] ~= nil or dirs["../scripts"] ~= nil) and dirs["tests"] ~= nil and sh,
    table.concat({ tostring(dirs["tests/fixtures"]), tostring(dirs["../scripts"] or dirs["scripts"]),
      tostring(sh) }, "/"))
end

local tmp_hits, time_hits, exit_hits, print_hits = {}, {}, {}, {}
for _, path in ipairs(files) do
  local src = (path ~= SELF) and stripped(path) or nil
  if src then
    if not TMP_LITERAL_OK[path] and src:find("/tmp", 1, true) then
      tmp_hits[#tmp_hits + 1] = path
    end
    if not OS_TIME_OK[path] and src:find("os%.time%s*%(") then
      time_hits[#time_hits + 1] = path
    end
    if not EXIT0_OK[path] and exits_ok(src) then
      exit_hits[#exit_hits + 1] = path
    end
    if not SKIP_PRINT_OK[path] then
      for call in src:gmatch("[%w_%.]*print%s*%(%s*[\"'][^\"'\n]*") do
        local lit = call:match("[\"'](.*)$") or ""
        if lit:match("^%s*[Ss][Kk][Ii][Pp]") or lit:match("^%s*note%s") then
          print_hits[#print_hits + 1] = path
        end
      end
      for call in src:gmatch("io%.write%s*%(%s*[\"'][^\"'\n]*") do
        local lit = call:match("[\"'](.*)$") or ""
        if lit:match("^%s*[Ss][Kk][Ii][Pp]") or lit:match("^%s*note%s") then
          print_hits[#print_hits + 1] = path
        end
      end
    end
  end
end

check("no test hard-codes a /tmp path (use tests.tmp_workdir)",
  #tmp_hits == 0, table.concat(tmp_hits, ", "))
check("no test derives a scratch path from os.time() (one-second resolution collides)",
  #time_hits == 0, table.concat(time_hits, ", "))
check("no test ends its run early with os.exit(0)/os.exit()/os.exit(true) (it would drop every "
  .. "later check)", #exit_hits == 0, table.concat(exit_hits, ", "))
check("no test announces a skip by printing (use tests.skip_ledger, which run_all.sh counts)",
  #print_hits == 0, table.concat(print_hits, ", "))

local rs = io.open("tests/run_all.sh", "r")
local runner = rs and rs:read("*a") or ""
if rs then rs:close() end
check("run_all.sh greps stdout for the skip ledger's marker",
  runner:find("==SKIP==", 1, true) ~= nil)
check("run_all.sh folds a Lua-side skip into the same counter REQUIRE_COMPLETE reads",
  runner:find("record_skip", 1, true) ~= nil and runner:find("lost_checks", 1, true) ~= nil)
check("a run that lost checks cannot print ok",
  runner:find('elif %[ "%$lost" %-ne 0 %]') ~= nil)

local declared = 0
for _, set in ipairs({ TMP_LITERAL_OK, OS_TIME_OK, EXIT0_OK, SKIP_PRINT_OK }) do
  for path in pairs(set) do
    declared = declared + 1
    local fh = io.open(path, "r")
    check("the declared exception " .. path .. " still exists", fh ~= nil)
    if fh then fh:close() end
  end
end
check("every exception is spelled out (" .. declared .. ")", declared >= 7, declared)

done()
