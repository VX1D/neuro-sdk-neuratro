local M = {}
local json = require("util.neuro_json")

function M.run()
  local fails = {}
  local checks = 0
  local function ok(cond, msg)
    checks = checks + 1
    if not cond then fails[#fails + 1] = msg end
  end
  local function eq(got, want, msg)
    checks = checks + 1
    if got ~= want then fails[#fails + 1] = string.format("%s: got %q want %q", msg, tostring(got), tostring(want)) end
  end

  print("====================================================")
  print("[json] wire-format invariants")
  print("====================================================")

  eq(json.encode(json.object({})), "{}", "empty json.object -> {}")
  eq(json.encode({}), "[]", "empty plain table -> [] (array default)")
  ok(next(json.object({})) == nil, "json.object adds no data fields")

  do
    local s = json.encode(json.object({ a = 1 }))
    ok(s == '{"a":1}', "object one key: " .. s)
    local nested = json.encode(json.object({ outer = json.object({}) }))
    ok(nested == '{"outer":{}}', "nested empty object stays {}: " .. nested)
  end

  do
    local valid = "caf\195\169 \226\130\172 \240\159\152\128"
    local enc = json.encode(valid)
    ok(enc:find("\195\169", 1, true) ~= nil and enc:find("\240\159\152\128", 1, true) ~= nil,
      "valid multibyte UTF-8 preserved")
    ok(json.decode(enc) == valid, "valid multibyte round-trips")
    local bad = json.encode("caf\233 x\128")
    ok(bad:find("\239\191\189", 1, true) ~= nil, "invalid byte replaced with U+FFFD")
    ok(bad:find("\233", 1, true) == nil and bad:find("\128", 1, true) == nil, "no raw invalid byte on the wire")
  end

  eq(json.encode({ 1, 2, 3 }), "[1,2,3]", "int array")
  eq(json.encode({ "a", "b" }), '["a","b"]', "string array")

  do
    local schema = json.object({
      type = "object",
      properties = json.object({ index = json.object({ type = "integer" }) }),
      required = { "index" },
    })
    local s = json.encode(schema)
    ok(s:find('"type":"object"', 1, true) ~= nil, "schema has type object: " .. s)
    ok(s:find('"required":%["index"%]') ~= nil, "schema required is an array: " .. s)
    local back = json.decode(s)
    ok(type(back) == "table" and back.type == "object", "schema decodes back")
    ok(type(back.required) == "table" and back.required[1] == "index", "required decodes as array")
  end

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

  do
    eq(json.encode('he said "hi"'), '"he said \\"hi\\""', "quote escape")
    eq(json.encode("a\\b"), '"a\\\\b"', "backslash escape")
    eq(json.encode("line\nbreak"), '"line\\nbreak"', "newline escape")
    eq(json.encode("tab\there"), '"tab\\there"', "tab escape")
    local nul = json.encode("x\0y")
    ok(nul:find("\\u0000", 1, true) ~= nil, "NUL -> \\u0000: " .. nul)
  end

  do
    eq(json.encode(true), "true", "true")
    eq(json.encode(false), "false", "false")
    local x = json.object({ id = "abc", success = true, message = "done" })
    local rt = json.decode(json.encode(x))
    ok(rt.id == "abc" and rt.success == true and rt.message == "done", "action/result round-trips")
    local rt2 = json.decode(json.encode(rt))
    ok(rt2.id == "abc" and rt2.success == true, "double round-trip stable")
  end

  do
    local ok_bad = pcall(json.decode, "{not json")
    ok(not ok_bad, "malformed json errors (not silent)")
    local ok_arr, arr = pcall(json.decode, "[]")
    ok(ok_arr and type(arr) == "table" and #arr == 0, "[] decodes to empty table")
    ok(not json.is_object(arr), "decoded [] is not an object")
    ok(json.is_array(arr), "decoded [] retains array type")
    eq(json.encode(arr), "[]", "decoded [] re-encodes as []")
    ok(next(arr) == nil, "decoded [] has no synthetic data fields")
    local ok_obj, obj = pcall(json.decode, "{}")
    ok(ok_obj and type(obj) == "table", "{} decodes to table")
    ok(json.is_object(obj), "decoded {} retains object type")
    ok(not json.is_array(obj), "decoded {} is not an array")
    eq(json.encode(obj), "{}", "decoded {} re-encodes as {}")
    ok(next(obj) == nil, "decoded {} has no synthetic data fields")
    local ok_u, u = pcall(json.decode, '"\\u00e9\\ud83d\\ude00"')
    ok(ok_u and type(u) == "string" and #u > 0, "unicode + surrogate decodes")
  end

  do
    local deep = string.rep("[", 5000) .. string.rep("]", 5000)
    pcall(json.decode, deep)
  end

  do
    local ok_arr, err_arr = pcall(json.decode, "[1,null,3]")
    ok(not ok_arr, "null array element still rejected")
    ok(type(err_arr) == "string" and err_arr:find("json semantic rejection", 1, true) ~= nil,
      "null-in-array error tagged as semantic, not a syntax error: " .. tostring(err_arr))
    local ok_syntax, err_syntax = pcall(json.decode, "[1,")
    ok(not ok_syntax and err_syntax:find("json semantic rejection", 1, true) == nil,
      "actual syntax error is not tagged as semantic: " .. tostring(err_syntax))
    local ok_field, field_obj = pcall(json.decode, '{"a":null,"b":1}')
    ok(ok_field and field_obj.a == nil and field_obj.b == 1, "null object field drops the key, siblings unaffected")
    eq(json.encode(json.decode("null")), "null", "top-level null decodes and re-encodes as null")
  end

  do
    local KEYS = { "zulu", "yankee", "xray", "whiskey", "victor", "uniform",
      "tango", "sierra", "romeo", "quebec", "papa", "oscar" }
    local a, b = json.object({}), json.object({})
    for i = 1, #KEYS do a[KEYS[i]] = i end
    for i = #KEYS, 1, -1 do b[KEYS[i]] = i end
    local enc_a = json.encode(a)
    eq(enc_a, json.encode(b), "insertion order does not change the encoding")
    eq(enc_a, json.encode(a), "re-encoding the same table is byte-identical")
    local order, last = {}, nil
    for key in enc_a:gmatch('"([%a]+)":') do order[#order + 1] = key end
    eq(#order, #KEYS, "every key survives the ordered encoding")
    local sorted = true
    for _, key in ipairs(order) do
      if last and key < last then sorted = false end
      last = key
    end
    ok(sorted, "object keys encode in ascending order: " .. enc_a)
    local frame = json.object({ command = "context", game = "Balatro",
      data = json.object({ message = "m", silent = true }), seq = 7 })
    eq(json.encode(frame),
      '{"command":"context","data":{"message":"m","silent":true},"game":"Balatro","seq":7}',
      "a wire frame encodes to one fixed byte string")
    local mixed = json.object({ [2] = "b", [1] = "a", alpha = "x" })
    eq(json.encode(mixed), '{"1":"a","2":"b","alpha":"x"}', "numeric keys sort before string keys")
  end

  print("====================================================")
  if #fails == 0 then
    print("==== json-wire: all invariants PASS, 0 FAIL ====")
  else
    print(string.format("==== json-wire: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails, checks
end

return M
