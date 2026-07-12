package.path = "./?.lua;;" .. package.path
love = setmetatable({ timer = { getTime = function() return 0 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = {
  P_CENTER_POOLS = { Planet = {}, Tarot = {}, Spectral = {}, Booster = {}, Voucher = {} },
  P_CENTERS = {}, GAME = {}, NEURO = {},
}
_G.SMODS = { Mods = {} }

local Cases = require("core.selftest_cases")

local fails = {}
local ok, cases = pcall(Cases.build)
if not ok then
  print("BUILD THREW: " .. tostring(cases))
  print("SELFTEST_BUILD_FAILS=1 (0 = clean)")
  os.exit(1)
end

local MIN_CASES = 120
if #cases < MIN_CASES then
  fails[#fails + 1] = string.format("only %d cases (expected >= %d)", #cases, MIN_CASES)
end

local names = {}
for i, c in ipairs(cases) do
  local where = "case #" .. i .. " (" .. tostring(c and c.name) .. ")"
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

print("====================================================")
print(string.format("[selftest_build] %d cases constructed and validated", #cases))
if #fails == 0 then
  print("==== selftest_build: 0 FAIL ====")
else
  print(string.format("==== selftest_build: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("SELFTEST_BUILD_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
