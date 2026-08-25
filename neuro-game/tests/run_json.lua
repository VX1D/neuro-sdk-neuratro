local ok_t, JW = pcall(require, "tests.test_json_wire")
if not ok_t then print("REQUIRE test_json_wire FAIL: " .. tostring(JW)); os.exit(3) end
local ok_r, fails, checks = pcall(JW.run)
if not ok_r then print("RUN ERROR: " .. tostring(fails)); os.exit(4) end
if type(fails) ~= "number" or type(checks) ~= "number" then
  print("RUN ERROR: non-numeric fail or check count"); os.exit(4)
end
print("JSON_FAILS=" .. fails .. " (0 = clean) JSON_CHECKS=" .. checks)
os.exit(fails == 0 and 0 or 1)
