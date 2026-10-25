require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("reroll-price-channel")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local function shop_state(cost, free, base)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.GAME.dollars = 40
  G.GAME.current_round.reroll_cost = cost
  G.GAME.current_round.free_rerolls = free
  G.GAME.current_round.reroll_cost_increase = 0
  G.GAME.round_resets = G.GAME.round_resets or {}
  G.GAME.round_resets.reroll_cost = base
  local f = FP.build("SHOP")
  return f and f.state or ""
end

local paid = shop_state(5, 0, 5)
check("a paid reroll shows its price and the $1 rise", paid:find("Reroll costs $5, next $6", 1, true) ~= nil, paid)

-- D6 Tag makes the reroll free without granting a free reroll; the following price still rises.
local d6 = shop_state(0, 0, 5)
check("a D6 $0 reroll still shows the next price rising", d6:find("Reroll costs $0, next $1", 1, true) ~= nil, d6)

local chaos = shop_state(0, 1, 5)
check("a Chaos free reroll shows the price unchanged after it",
  chaos:find("Reroll costs $0, next $5", 1, true) ~= nil and chaos:find("1 free", 1, true) ~= nil, chaos)

done()
