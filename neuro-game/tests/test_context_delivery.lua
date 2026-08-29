_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("context-delivery")
local Delivery = require("core.context_delivery")

local function reset(sender)
  Delivery.reset_transport()
  _G.G = { NEURO = { send_context = sender } }
end

do
  local calls, committed = 0, 0
  reset(function(_, _, silent, receipt)
    calls = calls + 1
    check("rules are silent", silent == true)
    receipt.status = "written"
    return true, false, receipt
  end)
  check("immediate rule write is accepted", Delivery.rule("mechanic", "Always true.", {
    on_written = function() committed = committed + 1 end,
  }) == true)
  check("immediate write commits once", committed == 1 and calls == 1, committed .. "/" .. calls)
  Delivery.rule("mechanic", "Always true.")
  check("delivered rule is deduplicated", calls == 1, calls)
  check("a delivered rule identity cannot change",
    pcall(function() Delivery.rule("mechanic", "Now different.") end) == false)
end

do
  local receipt, committed, calls = nil, 0, 0
  reset(function(_, _, _, r)
    calls = calls + 1
    receipt = r
    r.status = "buffered"
    return true, true, r
  end)
  check("buffered rule is accepted", Delivery.rule("buffered", "Rule.", {
    on_written = function() committed = committed + 1 end,
  }) == true)
  Delivery.step()
  check("buffered is not committed", committed == 0 and calls == 1, committed .. "/" .. calls)
  receipt.status = "written"
  Delivery.step()
  check("physical write commits exact candidate", committed == 1, committed)
end

do
  local calls, receipts = 0, {}
  reset(function(_, _, _, r)
    calls = calls + 1
    receipts[#receipts + 1] = r
    r.status = calls == 1 and "rejected" or "written"
    return calls ~= 1, false, r
  end)
  check("rejected first attempt reports no acceptance",
    Delivery.event("event-1", "A past event happened.") == false)
  Delivery.step()
  check("rejected event retries and writes", calls == 2
    and Delivery._delivered()["event\1event-1"] == "A past event happened.", calls)
end

do
  local old_receipt
  reset(function(_, _, _, r)
    old_receipt = r
    r.status = "buffered"
    return true, true, r
  end)
  Delivery.rule("old", "Old transport rule.")
  Delivery.reset_transport()
  old_receipt.status = "written"
  Delivery.step()
  check("old transport receipt cannot commit after reset",
    Delivery._delivered()["rule\1old"] == nil)
end

do
  reset(function(_, _, _, r) r.status = "written"; return true, false, r end)
  Delivery.rule("gloss:readable_common", "Glossary body.")
  for i = 1, 2500 do
    Delivery.rule("hint:k" .. i .. "@" .. i, "Hint body " .. i)
  end
  local remembered = 0
  for _ in pairs(Delivery._delivered()) do remembered = remembered + 1 end
  check("hint rules are capped, so delivery memory stops growing with the run",
    remembered == 2049, tostring(remembered))
  check("a fixed-key rule is never evicted, or the glossary would be sent to the model twice",
    Delivery._delivered()["rule\1gloss:readable_common"] ~= nil)
end

done()
