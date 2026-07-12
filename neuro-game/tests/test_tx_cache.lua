package.path = "./?.lua;;" .. package.path
local TX = require("core.tx_cache")

local fails = {}
local function check(name, cond)
  if not cond then fails[#fails + 1] = name end
end

TX.reset()
check("miss on empty", TX.get("a") == nil)
check("nil id stores nothing", (function() TX.store(nil, true, "x") return TX.get(nil) end)() == nil)

TX.store("a", true, "hello", "play_hand")
local got = TX.get("a")
check("store/get roundtrip ok", got.ok == true)
check("store/get message", got.message == "hello")
check("store/get name", got.name == "play_hand")
check("success coerced to boolean", TX.get("a").ok == true and (function() TX.store("b", 1) return TX.get("b").ok end)() == true)
check("numeric id keyed as string", (function() TX.store(7, false, "n") return TX.get("7") end)().ok == false)

TX.invalidate("a")
check("invalidate drops the entry", TX.get("a") == nil)
check("invalidate of absent id is a no-op", (function() TX.invalidate("zzz") return true end)())

TX.reset()
for i = 1, 300 do TX.store("k" .. i, true, "m") end
check("FIFO cap holds newest", TX.get("k300") ~= nil)
check("FIFO cap evicts oldest past 256", TX.get("k1") == nil)
check("FIFO keeps within-cap", TX.get("k45") ~= nil)
local live = 0
for i = 1, 300 do if TX.get("k" .. i) then live = live + 1 end end
check("live entries bounded at cap", live == 256)

TX.reset()
check("reset clears all", TX.get("k300") == nil)

print("====================================================")
if #fails == 0 then
  print("==== tx_cache: get/store/invalidate/reset + FIFO cap hold, 0 FAIL ====")
else
  print(string.format("==== tx_cache: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("TX_CACHE_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
