_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("plan-tx-stale")

local PlanTransaction = require("core.plan_transaction")
local Receipt = require("core.action_receipt")
local Metrics = require("util.metrics")

local function base()
  clock = clock + 10
  _G.G = {
    STATE = 2,
    STATES = { BLIND_SELECT = 1, SHOP = 2 },
    GAME = {
      dollars = 20,
      round_resets = { ante = 2, blind_states = {}, blind_choices = {} },
      current_round = { reroll_cost = 5, free_rerolls = 0 },
      modifiers = {},
    },
    NEURO = {
      state = "SHOP", run_generation = 7, shop_visit_epoch = 3, economy_epoch = 2,
      state_enter_serial = 11, once_serials = {}, plan_revision = 0,
    },
    FUNCS = {}, shop = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
end

local function drive(id, mutate)
  local data = { plan = { money_plan = "Bank the reroll money for the boss." } }
  local tx = assert(PlanTransaction.prepare("reroll_shop", data))
  local wrapped = PlanTransaction.wrap("reroll_shop", data, function()
    return Receipt.create({
      id = id, name = "reroll_shop", run_generation = G.NEURO.run_generation,
      started_at = clock, deadline = clock + 5, probe = function() return "applied" end,
    })
  end, tx)
  local receipt = wrapped()
  if mutate then mutate() end
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  Receipt.update(clock + 1, G.NEURO.run_generation)
end

local lines = {}
local real_print = print
_G.print = function(...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  local s = table.concat(parts, "\t")
  if s:find("plan_tx", 1, true) then lines[#lines + 1] = s else real_print(...) end
end

Metrics._counters["plan_tx_stale"] = nil

local before = PlanTransaction._test.stale_drops()

Receipt.reset("stale-obs-1")
base()
drive("fresh-receipt")
check("fresh token commits and leaves the drop tally untouched",
  PlanTransaction._test.stale_drops() == before and G.NEURO.plan ~= nil,
  "tally=" .. PlanTransaction._test.stale_drops())

Receipt.reset("stale-obs-2")
base()
drive("stale-receipt", function()
  G.NEURO.plan_revision = 1
  G.NEURO.plan = { money = "newer plan" }
end)
check("stale token still refuses to overwrite the newer plan", G.NEURO.plan.money == "newer plan")
check("stale drop is tallied and Metrics records it unconditionally",
  PlanTransaction._test.stale_drops() == before + 1 and Metrics._counters["plan_tx_stale"] == 1,
  "tally=" .. PlanTransaction._test.stale_drops())
check("stale drop reaches the owner log on first occurrence", #lines == 1, "lines=" .. #lines)
check("the log line names the action, the stale token field and the lost plan fields",
  lines[1] ~= nil and lines[1]:find("reroll_shop", 1, true) ~= nil
    and lines[1]:find("plan_revision", 1, true) ~= nil
    and lines[1]:find("money_plan", 1, true) ~= nil,
  lines[1])

Receipt.reset("stale-obs-3")
base()
drive("stale-epoch-receipt", function() G.NEURO.shop_visit_epoch = 4 end)
check("a stale shop_visit_epoch is tallied too",
  PlanTransaction._test.stale_drops() == before + 2, "tally=" .. PlanTransaction._test.stale_drops())
check("repeat drops back off instead of spamming the log", #lines == 1, "lines=" .. #lines)

_G.print = real_print
done()
