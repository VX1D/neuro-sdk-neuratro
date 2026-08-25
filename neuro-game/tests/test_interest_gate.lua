_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local DW = require("core.decision_window")

local check, done = require("tests.helpers").harness("interest-gate")

local function shop(entry, now, game_over)
  local game = { round_resets = { ante = 2 }, dollars = now, modifiers = {} }
  for k, v in pairs(game_over or {}) do game[k] = v end
  _G.G = {
    STATE = 2, STATES = { SHOP = 2 },
    GAME = game,
    NEURO = { _decision_windows = {}, shop_entry_dollars = entry, shop_visit_epoch = 1, run_generation = 1 },
  }
  DW.reset_field("interest_engine_off")
end

shop(12, 4)
local lvl, msg = DW.evaluate("toggle_shop")
check("entered $12, leaving $4 -> soft reject", lvl == "soft_reject", tostring(lvl))
check("prose states both banks", msg and msg:find("with $4", 1, true) and msg:find("with $12", 1, true), msg)
check("prose says the leftover is not lost", msg and msg:find("carry to the next shop", 1, true) ~= nil, msg)
check("immediate resend commits (never a trap)", DW.evaluate("toggle_shop") == false)

shop(12, 4)
DW.evaluate("toggle_shop")
DW.acknowledge("set_plan")
check("rewriting the money plan also clears it", DW.would_reject("toggle_shop") == false)

shop(12, 6)
check("leaving with a full step -> silent", DW.evaluate("toggle_shop") == false)
shop(12, 9)
check("remainder above a step ($9) -> silent, not a remainder nag",
  DW.evaluate("toggle_shop") == false)
shop(4, 4)
check("arrived poor and stayed poor -> silent (nothing was forfeited)",
  DW.evaluate("toggle_shop") == false)
shop(12, 4, { modifiers = { no_interest = true } })
check("no_interest run -> silent", DW.evaluate("toggle_shop") == false)
shop(12, -3, { bankrupt_at = -20 })
check("Credit Card overdraft -> silent (never pressure a buy under water)",
  DW.evaluate("toggle_shop") == false)
shop(12, 4, { interest_amount = 0 })
check("B6a interest_amount 0 -> silent (claim would be untrue)", DW.evaluate("toggle_shop") == false)
shop(12, 4, { interest_cap = 0 })
check("B6b interest_cap below one step -> silent", DW.evaluate("toggle_shop") == false)
shop(12, 0)
check("leaving broke still fires (0 is below the step, and this shop caused it)",
  DW.evaluate("toggle_shop") == "soft_reject")

shop(12, 4)
DW.evaluate("toggle_shop")
DW.evaluate("toggle_shop")
G.NEURO.shop_visit_epoch = 2
check("next shop visit re-arms", DW.evaluate("toggle_shop") == "soft_reject")

shop(12, 4, { interest_amount = 2, interest_cap = 50 })
local _, m2 = DW.evaluate("toggle_shop")
check("rate follows interest_amount", m2 and m2:find("+$2 per full $5", 1, true) ~= nil, m2)
check("cap follows interest_cap", m2 and m2:find("up to +$20 at $50", 1, true) ~= nil, m2)
check("no hardcoded +$1 rate", m2 and m2:find("+$1 per full", 1, true) == nil, m2)
for _, word in ipairs({ "prefer", "should", "best", "you must" }) do
  check("bare fact: no '" .. word .. "'", not m2:lower():find(word, 1, true), m2)
end
for _, tok in ipairs({ "name=", "state=", "throttle", "decision_window" }) do
  check("no internal token '" .. tok .. "'", not m2:find(tok, 1, true), m2)
end

shop(11, 4)
check("entered $11 -> below the entry threshold, no gate", DW.evaluate("toggle_shop") == false)
shop(12, 4)
check("entered $12 -> at the entry threshold, gate arms",
  DW.evaluate("toggle_shop") == "soft_reject")
shop(30, 4)
check("entered $30 -> well above, gate arms", DW.evaluate("toggle_shop") == "soft_reject")

done()
