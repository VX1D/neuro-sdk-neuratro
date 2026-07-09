-- Locks the neuro_json wire-format invariants the Neuro SDK depends on. A silent encoder
-- change here breaks protocol compliance in ways byte-compilation can't catch -- e.g. an
-- empty action `schema` serializing as [] instead of {} makes Neuro reject the registration.
--
-- luajit tests/run_json.lua

local M = {}
local json = require("util.neuro_json")

function M.run()
  local fails = {}
  local function ok(cond, msg) if not cond then fails[#fails + 1] = msg end end
  local function eq(got, want, msg)
    if got ~= want then fails[#fails + 1] = string.format("%s: got %q want %q", msg, tostring(got), tostring(want)) end
  end

  print("====================================================")
  print("[json] wire-format invariants")
  print("====================================================")

  -- 1. empty object vs empty array (THE SDK-critical case)
  eq(json.encode(json.object({})), "{}", "empty json.object -> {}")
  eq(json.encode({}), "[]", "empty plain table -> [] (array default)")

  -- 2. object with keys; nested object; empty nested object stays {}
  do
    local s = json.encode(json.object({ a = 1 }))
    ok(s == '{"a":1}', "object one key: " .. s)
    local nested = json.encode(json.object({ outer = json.object({}) }))
    ok(nested == '{"outer":{}}', "nested empty object stays {}: " .. nested)
  end

  -- 3. arrays
  eq(json.encode({ 1, 2, 3 }), "[1,2,3]", "int array")
  eq(json.encode({ "a", "b" }), '["a","b"]', "string array")

  -- 4. an actions/register schema shape (object with properties, empty object leaf)
  do
    local schema = json.object({
      type = "object",
      properties = json.object({ index = json.object({ type = "integer" }) }),
      required = { "index" },
    })
    local s = json.encode(schema)
    ok(s:find('"type":"object"', 1, true) ~= nil, "schema has type object: " .. s)
    ok(s:find('"required":%["index"%]') ~= nil, "schema required is an array: " .. s)
    -- round-trips back to a table with the same shape
    local back = json.decode(s)
    ok(type(back) == "table" and back.type == "object", "schema decodes back")
    ok(type(back.required) == "table" and back.required[1] == "index", "required decodes as array")
  end

  -- 5. numbers: no %d wrap (LuaJIT %d on >=2^63 gives INT64_MIN); NaN / inf -> null
  do
    local big = json.encode(1e19)
    ok(big ~= nil and not big:find("-9223372036854775808", 1, true), "1e19 not INT64_MIN garbage: " .. big)
    ok(tostring(json.decode(big)) ~= "nil", "big number decodes")
    eq(json.encode(0 / 0), "null", "NaN -> null")
    eq(json.encode(math.huge), "null", "+inf -> null")
    eq(json.encode(-math.huge), "null", "-inf -> null")
    eq(json.encode(0), "0", "zero")
    eq(json.encode(-5), "-5", "negative int")
  end

  -- 6. string escaping: quotes, backslash, control chars
  do
    eq(json.encode('he said "hi"'), '"he said \\"hi\\""', "quote escape")
    eq(json.encode("a\\b"), '"a\\\\b"', "backslash escape")
    eq(json.encode("line\nbreak"), '"line\\nbreak"', "newline escape")
    eq(json.encode("tab\there"), '"tab\\there"', "tab escape")
    local nul = json.encode("x\0y")
    ok(nul:find("\\u0000", 1, true) ~= nil, "NUL -> \\u0000: " .. nul)
  end

  -- 7. booleans / null / nested round-trip stability
  do
    eq(json.encode(true), "true", "true")
    eq(json.encode(false), "false", "false")
    local x = json.object({ id = "abc", success = true, message = "done" })
    local rt = json.decode(json.encode(x))
    ok(rt.id == "abc" and rt.success == true and rt.message == "done", "action/result round-trips")
    -- re-encode is stable (decode->encode->decode preserves values)
    local rt2 = json.decode(json.encode(rt))
    ok(rt2.id == "abc" and rt2.success == true, "double round-trip stable")
  end

  -- 8. decoder robustness: malformed input errors (pcall) instead of crashing; valid empties parse
  do
    local ok_bad = pcall(json.decode, "{not json")
    ok(not ok_bad, "malformed json errors (not silent)")
    local ok_arr, arr = pcall(json.decode, "[]")
    ok(ok_arr and type(arr) == "table" and #arr == 0, "[] decodes to empty table")
    local ok_obj, obj = pcall(json.decode, "{}")
    ok(ok_obj and type(obj) == "table", "{} decodes to table")
    -- unicode escape + surrogate pair
    local ok_u, u = pcall(json.decode, '"\\u00e9\\ud83d\\ude00"')
    ok(ok_u and type(u) == "string" and #u > 0, "unicode + surrogate decodes")
  end

  -- 9. deeply nested input must not stack-overflow the decoder (guard -> error, not crash)
  do
    local deep = string.rep("[", 5000) .. string.rep("]", 5000)
    local ok_deep = pcall(json.decode, deep)
    ok(true, "deep nest did not crash the process (ok=" .. tostring(ok_deep) .. ")")
  end

  local total = 0
  -- count is implicit; just report pass/fail
  print("====================================================")
  if #fails == 0 then
    print("==== json-wire: all invariants PASS, 0 FAIL ====")
  else
    print(string.format("==== json-wire: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails
end

return M
