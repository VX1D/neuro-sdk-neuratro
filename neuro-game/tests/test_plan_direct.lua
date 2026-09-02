_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("handlers.plan_handlers").handle_record_plan

local check, done = require("tests.helpers").harness("plan-direct")

local function base()
  _G.G = { STATE = 2, STATES = { SHOP = 2 }, GAME = { round_resets = { ante = 2 } }, NEURO = {}, jokers = { cards = {} } }
end

base()
local exec = H({ build_plan = "low mult, no scaling" })
check("verb-less plan is accepted first try", type(exec) == "function", type(exec))

base()
local exec2 = H({ build_plan = "buy an xMult joker; level Two Pair" })
check("plan with decision verbs is accepted first try", type(exec2) == "function", type(exec2))

base()
local exec3 = H({ hand_plan = "Play Full House; discard non-hearts" })
check("hand plan is accepted first try", type(exec3) == "function", type(exec3))
done()
