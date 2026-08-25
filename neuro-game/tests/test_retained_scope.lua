_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("retained-scope")
local Delivery = require("core.context_delivery")
local Rewards = require("core.rewards")
local Metrics = require("util.metrics")

local sent

local function session(generation)
  Delivery.reset_transport()
  sent = {}
  _G.G = { NEURO = { run_generation = generation } }
  function G.NEURO:send_context(message, silent)
    sent[#sent + 1] = { text = tostring(message), silent = not not silent }
    return true
  end
end

-- The delivery half is core/orchestrator.lua:392-396; mirrored here, and pinned to the source below
-- so the mirror cannot drift away from the caller it stands in for.
local function clear_small_blind()
  G.GAME = { blind = { name = "Small Blind" }, chips = 300, round = 1,
    round_resets = { ante = 1 }, current_round = { hands_left = 2 }, win_ante = 8 }
  local msg, spoken = Rewards.outcome("SELECTING_HAND", "ROUND_EVAL")
  if not msg then return nil end
  if spoken then Delivery.prompt_at("outcome", {}, msg) else Delivery.event_at("outcome", {}, msg) end
  return msg
end

do
  session(1)
  local first = clear_small_blind()
  check("run 1 narrates its blind clear", first ~= nil and #sent == 1, tostring(#sent))

  G.NEURO.run_generation = 2
  local second = clear_small_blind()
  check("run 2 produces its own outcome message", second ~= nil, tostring(second))
  check("run 2's outcome reaches the wire", #sent == 2, tostring(#sent))
  check("raw reward prose has one owner and is stable across runs", second == first,
    tostring(second) .. " != " .. tostring(first))
  check("R4b delivery adds exactly one visible run stamp to each outcome",
    sent[1].text:match("^%[run 1%] [^%[]") ~= nil
      and sent[2].text:match("^%[run 2%] [^%[]") ~= nil,
    tostring(sent[1] and sent[1].text) .. " | " .. tostring(sent[2] and sent[2].text))
  check("both still say what happened",
    sent[1] and sent[1].text:find("cleared the Small Blind", 1, true) ~= nil
      and sent[2] and sent[2].text:find("cleared the Small Blind", 1, true) ~= nil,
    sent[2] and sent[2].text)
end

do
  session(7)
  Metrics._counters.context_duplicate_text = 0
  check("the first copy is delivered", Delivery.event("dup:a", "Exactly the same sentence.") == true)
  local ok, reason = Delivery.event("dup:b", "Exactly the same sentence.")
  check("a true duplicate is still refused", #sent == 1, tostring(#sent))
  check("and the caller is told, instead of being handed a 'delivered' it cannot act on",
    ok == false, tostring(ok))
  check("and the refusal names itself", reason == "duplicate_text", tostring(reason))
  check("and it is counted", (Metrics._counters.context_duplicate_text or 0) >= 1,
    tostring(Metrics._counters.context_duplicate_text))
end

done()
