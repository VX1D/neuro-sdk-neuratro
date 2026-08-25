love = setmetatable({ timer = { getTime = function() return 0 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = {
  P_CENTER_POOLS = { Planet = {}, Tarot = {}, Spectral = {}, Booster = {}, Voucher = {} },
  P_CENTERS = {}, GAME = {}, NEURO = {},
}
_G.SMODS = { Mods = {} }

rawset(_G, "NEURO_TEST", true)
local Cases = require("core.selftest_cases")

local fails = {}

do
  local AR = require("core.action_result")
  local T = Cases._test
  local calls
  local function dispatch_ok() calls = calls + 1 return true, nil end
  local function dispatch_confirm_then_ok()
    calls = calls + 1
    if calls == 1 then return nil, AR.error("CONFIRMATION_REQUIRED", "confirm it") end
    return true, nil
  end
  local function dispatch_always_confirm()
    calls = calls + 1
    return nil, AR.error("CONFIRMATION_REQUIRED", "confirm it")
  end
  local function dispatch_other_error()
    calls = calls + 1
    return nil, AR.error("INSUFFICIENT_FUNDS", "too poor")
  end

  calls = 0
  local res = T.confirm_retry(dispatch_ok, "a", {})
  if not (res == true and calls == 1) then
    fails[#fails + 1] = "confirm_retry: a clean action must dispatch exactly once, got " .. calls
  end

  calls = 0
  local res2, err2 = T.confirm_retry(dispatch_confirm_then_ok, "a", {})
  if not (res2 == true and err2 == nil and calls == 2) then
    fails[#fails + 1] = "confirm_retry: a confirmation must be answered once, got calls=" .. calls
  end

  calls = 0
  local _, err3 = T.confirm_retry(dispatch_always_confirm, "a", {})
  if not (calls == 2 and err3 and err3.reason_code == "CONFIRMATION_REQUIRED") then
    fails[#fails + 1] = "confirm_retry: a repeated confirmation must surface, got calls=" .. calls
  end

  calls = 0
  local _, err4 = T.confirm_retry(dispatch_other_error, "a", {})
  if not (calls == 1 and err4 and err4.reason_code == "INSUFFICIENT_FUNDS") then
    fails[#fails + 1] = "confirm_retry: a non-confirmation error must not be retried, got calls=" .. calls
  end
end

local function validate(cases, label, min_cases)
  local names = {}
  if min_cases and #cases < min_cases then
    fails[#fails + 1] = string.format("%s: only %d cases (expected >= %d)", label, #cases, min_cases)
  end
  for i, c in ipairs(cases) do
    local where = label .. " case #" .. i .. " (" .. tostring(c and c.name) .. ")"
    if type(c) ~= "table" then
      fails[#fails + 1] = where .. ": not a table"
    else
      if type(c.name) ~= "string" or c.name == "" then
        fails[#fails + 1] = where .. ": missing/empty name"
      elseif names[c.name] then
        fails[#fails + 1] = where .. ": duplicate name"
      else
        names[c.name] = true
      end
      local drivable = type(c.act) == "function" or type(c.setup) == "function"
      local concludes = type(c.assert) == "function" or type(c.wait_for) == "function"
      if not drivable then fails[#fails + 1] = where .. ": no act/setup function" end
      if not concludes then fails[#fails + 1] = where .. ": no assert/wait_for function" end
      if c.timeout_s ~= nil and type(c.timeout_s) ~= "number" then
        fails[#fails + 1] = where .. ": non-numeric timeout_s"
      end
    end
  end
  return #cases
end

local ok, cases = pcall(Cases.build)
if not ok then
  print("BUILD THREW: " .. tostring(cases))
  print("SELFTEST_BUILD_FAILS=1 (0 = clean)")
  os.exit(1)
end
local n_default = validate(cases, "build", 120)

local ok_pack, pack_cases = pcall(Cases.build_pack)
if not ok_pack then
  print("BUILD_PACK THREW: " .. tostring(pack_cases))
  print("SELFTEST_BUILD_FAILS=1 (0 = clean)")
  os.exit(1)
end
local n_pack = validate(pack_cases, "build_pack")

print("====================================================")
print(string.format("[selftest_build] %d default + %d pack cases constructed and validated", n_default, n_pack))
if #fails == 0 then
  print("==== selftest_build: 0 FAIL ====")
else
  print(string.format("==== selftest_build: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("SELFTEST_BUILD_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
