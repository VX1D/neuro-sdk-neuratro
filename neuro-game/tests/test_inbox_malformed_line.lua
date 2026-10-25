require("tests.stubs").setup({ love = "zero" })
_G.G = { NEURO = {}, TIMERS = { REAL = 0 } }

local Bridge = require("core.bridge")
local check, done = require("tests.helpers").harness("inbox-malformed-line")

local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("ibx_malformed")

local function fresh_bridge()
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  local seen = {}
  local handler_calls = 0
  b:set_message_handler(function(msg)
    handler_calls = handler_calls + 1
    seen[#seen + 1] = msg.command
  end)
  return b, seen, function() return handler_calls end
end

local function append(text)
  local f = io.open(dir .. "/neuro_inbox.jsonl", "a")
  f:write(text); f:close()
end

local GOOD_LINE = '{"command":"context","data":{"message":"ok","silent":true}}'

local cases = {
  { name = "bare number scalar", line = "42" },
  { name = "bare JSON array", line = "[1,2,3]" },
  { name = "bare JSON string", line = '"hello"' },
  { name = "bare JSON true", line = "true" },
  { name = "object with no command field", line = '{"data":{"x":1}}' },
}

for _, case in ipairs(cases) do
  local b, seen, calls = fresh_bridge()
  append(case.line .. "\n")
  local ok = pcall(function() b:poll_inbox() end)
  check(case.name .. ": poll_inbox does not throw", ok, case.line)
  check(case.name .. ": the message handler is never invoked for a non-message",
    calls() == 0, calls())

  append(GOOD_LINE .. "\n")
  local ok2 = pcall(function() b:poll_inbox() end)
  check(case.name .. ": a following legitimate message is still delivered",
    ok2 and calls() == 1 and seen[1] == "context", table.concat(seen, ","))
end

do
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b:set_message_handler(function() end)
  local original_deliver = b._deliver_inbox_message
  b._deliver_inbox_message = function(self, msg)
    if msg.command == "boom" then
      error("synthetic delivery failure")
    end
    return original_deliver(self, msg)
  end

  append('{"command":"boom"}' .. "\n")
  local pos_before = b.inbox_pos
  local ok = pcall(function() b:poll_inbox() end)
  check("a throw in delivery does not propagate out of poll_inbox", ok)
  check("the line that threw is still consumed (cursor advanced)", b.inbox_pos > pos_before, b.inbox_pos)

  local seen = {}
  b:set_message_handler(function(msg) seen[#seen + 1] = msg.command end)
  append(GOOD_LINE .. "\n")
  b:poll_inbox()
  check("a subsequent line after a throw in delivery is still delivered",
    #seen == 1 and seen[1] == "context", table.concat(seen, ","))
end

do
  local b, seen, calls = fresh_bridge()
  append("42\n[1,2,3]\n" .. GOOD_LINE .. "\n")
  b:poll_inbox()
  check("multiple malformed lines in one chunk are all skipped, good line still delivered",
    calls() == 1 and seen[1] == "context", table.concat(seen, ","))
end

local function capture_poll(fn)
  local captured = {}
  local original_print = print
  print = function(...)
    local args = { ... }
    for i = 1, #args do args[i] = tostring(args[i]) end
    captured[#captured + 1] = table.concat(args, " ")
  end
  local ok, err = pcall(fn)
  print = original_print
  return ok, err, captured
end

do
  local marker = "IPC_REDACTION_SECRET_NOT_MESSAGE_2c81"
  local b = fresh_bridge()
  append('{"data":{"marker":"' .. marker .. '"}}' .. "\n")
  local ok, err, captured = capture_poll(function() b:poll_inbox() end)
  local diagnostics = table.concat(captured, "\n")
  check("a captured malformed object does not throw", ok, tostring(err))
  check("a malformed object emits the not-a-message diagnostic",
    diagnostics:find("not a message", 1, true) ~= nil, diagnostics)
  check("a malformed object diagnostic omits its payload marker",
    diagnostics:find(marker, 1, true) == nil, diagnostics)
end

do
  local inbox_cap = 10 * 1024 * 1024
  local marker = "IPC_REDACTION_SECRET_COMPLETE_7f3a"
  local b, seen, calls = fresh_bridge()
  append(marker .. string.rep("c", inbox_cap) .. "\n" .. GOOD_LINE .. "\n")

  local ok, err, captured = capture_poll(function()
    for _ = 1, 256 do
      b:poll_inbox()
      if calls() == 1 then break end
    end
  end)
  local diagnostics = table.concat(captured, "\n")
  check("an oversized complete line does not throw", ok, tostring(err))
  check("an oversized complete line never prints its payload marker",
    diagnostics:find(marker, 1, true) == nil, #captured)
  check("an oversized complete line emits a bounded diagnostic",
    diagnostics:find("line discarded", 1, true) ~= nil, diagnostics)
  check("a good line after an oversized complete line is delivered",
    ok and calls() == 1 and seen[1] == "context", table.concat(seen, ","))
end

do
  local inbox_cap = 10 * 1024 * 1024
  local marker = "IPC_REDACTION_SECRET_UNTERMINATED_b91c"
  local b, seen, calls = fresh_bridge()
  append(marker .. string.rep("u", inbox_cap))

  local ok_partial, err_partial, partial_captured =
    capture_poll(function()
      for _ = 1, 161 do b:poll_inbox() end
    end)
  check("an oversized unterminated remainder does not throw", ok_partial, tostring(err_partial))
  check("an oversized unterminated remainder emits a bounded diagnostic",
    ok_partial and table.concat(partial_captured, "\n"):find("line discarded", 1, true) ~= nil,
    #partial_captured)

  append("\n" .. GOOD_LINE .. "\n")
  local ok_finish, err_finish, finish_captured = capture_poll(function()
    for _ = 1, 256 do
      b:poll_inbox()
      if calls() == 1 then break end
    end
  end)
  local diagnostics = table.concat(partial_captured, "\n") .. "\n"
    .. table.concat(finish_captured, "\n")
  check("an oversized unterminated remainder never prints its payload marker",
    diagnostics:find(marker, 1, true) == nil, #partial_captured + #finish_captured)
  check("a good line after the discarded remainder is delivered",
    ok_finish and calls() == 1 and seen[1] == "context", tostring(err_finish))
end

TmpWork.close()
done()
