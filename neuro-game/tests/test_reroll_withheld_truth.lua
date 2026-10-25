require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })
local check, done = require("tests.helpers").harness("reroll-withheld-truth")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local function offered(payload, name)
  for _, a in ipairs(payload.actions or {}) do if a == name then return true end end
  return false
end

local function reroll_line(state) return tostring(state):match("Can reroll:[^\n]*") or "" end

local function shop(dollars)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.GAME.dollars, G.GAME.current_round.reroll_cost = dollars, 5
  for _, area in ipairs({ G.shop_booster, G.shop_vouchers }) do
    for _, c in ipairs((area and area.cards) or {}) do c.cost = 5 end
  end
  return FP.build("SHOP")
end

do
  local payload = shop(9)
  local line = reroll_line(payload.state)
  check("withheld: the policy is unchanged, reroll_shop is not offered", not offered(payload, "reroll_shop"))
  check("withheld: the line says the game allows the $5 reroll",
    line:find("the game allows this $5 reroll", 1, true) ~= nil, line)
  check("withheld: and that this mod withholds it",
    line:find("this mod withholds it", 1, true) ~= nil, line)
end

do
  local payload = shop(3)
  local line = reroll_line(payload.state)
  check("unaffordable: reroll_shop is not offered", not offered(payload, "reroll_shop"))
  check("unaffordable: the line does not claim the game would allow it",
    line:find("game allows", 1, true) == nil and line:find("$5", 1, true) ~= nil, line)
end

done()
