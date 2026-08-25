local TX = require("core.tx_cache")

local check, fails, checks = require("tests.helpers").collector()

TX.reset()
check("miss on empty", TX.get("a") == nil)
check("nil id stores nothing", (function() TX.store(nil, true, "x") return TX.get(nil) end)() == nil)

TX.store("a", true, "hello", "play_hand")
local got = TX.get("a")
check("store/get roundtrip ok", got.ok == true)
check("store/get message", got.message == "hello")
check("store/get name", got.name == "play_hand")
check("success coerced to boolean", TX.get("a").ok == true and (function() TX.store("b", 1) return TX.get("b").ok end)() == true)
TX.reset()
TX.store(7, false, "num")
check("numeric id 7 stores and reads back on its own slot", TX.get(7).ok == false and TX.get(7).message == "num")
check("string id \"7\" is not discharged by storing numeric id 7", TX.get("7") == nil)
TX.store("7", true, "str")
check("numeric id 7 and string id \"7\" hold independent verdicts",
  TX.get(7).message == "num" and TX.get("7").message == "str")

TX.invalidate("a")
check("invalidate drops the entry", TX.get("a") == nil)
check("invalidate of absent id is a no-op", (function() TX.invalidate("zzz") return true end)())

local CAP = TX.CAP
check("cap is published by the module", type(CAP) == "number" and CAP > 0, tostring(CAP))
local OVER = CAP + 44
TX.reset()
for i = 1, OVER do TX.store("k" .. i, true, "m") end
check("FIFO cap holds newest", TX.get("k" .. OVER) ~= nil)
check("FIFO cap evicts oldest past the cap", TX.get("k1") == nil)
check("FIFO keeps within-cap", TX.get("k" .. (OVER - 10)) ~= nil)
local live = 0
for i = 1, OVER do if TX.get("k" .. i) then live = live + 1 end end
check("live entries bounded at cap", live == CAP, live)

TX.reset()
TX.store("same", true, "old")
TX.invalidate("same")
TX.store("same", true, "new")
for i = 1, TX.CAP - 1 do TX.store("new" .. i, true, "m") end
check("stale ring slot cannot evict a newer same-id entry", TX.get("same") and TX.get("same").message == "new")

TX.reset()
check("reset clears all", TX.get("k1") == nil)

TX.reset()
TX.store("s", true, "m", "play_hand")
TX.note_result_session("s", 7)
check("no replay to the session that already received the result", TX.replay_due("s", 7) == false)
check("a later session is owed the replay", TX.replay_due("s", 8) == true)
check("session 7 and session \"7\" are different connections", TX.replay_due("s", "7") == true)
TX.note_result_session("s", true)
check("session true and session \"true\" are different connections", TX.replay_due("s", "true") == true)

TX.reset()
TX.store("t", true, "m", "play_hand")
TX.note_result_session("t", nil)
check("having no transport session is not the session named \"nil\"", TX.replay_due("t", "nil") == true)
check("and no-session still matches itself, so a result is not re-sent forever",
  TX.replay_due("t", nil) == false)

print("====================================================")
if #fails == 0 then
  print("==== tx_cache: get/store/invalidate/reset + FIFO cap hold, 0 FAIL ====")
else
  print(string.format("==== tx_cache: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("TX_CACHE_FAILS=" .. #fails .. " (0 = clean) TX_CACHE_CHECKS=" .. checks())
os.exit(#fails == 0 and 0 or 1)
