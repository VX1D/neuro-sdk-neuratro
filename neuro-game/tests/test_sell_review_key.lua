require("tests.stubs").setup({ love = "lazy" })
_G.G = require("tests.helpers").base_G()

local check, done = require("tests.helpers").harness("sell-review-key")
local H = require("tests.helpers")
local V = require("tests.fixtures.vanilla_jokers")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx

local function neuro(state)
  G.NEURO = H.started_bridge({ state = state, state_enter_serial = 1, decision_serial = 1, run_generation = 1,
    enabled = true, persona = "neuro", dispatcher = Dispatcher, actions = Actions, shop_visit_epoch = 1,
    register_actions = H.noop, send_context = H.yes, is_transition_cooldown = H.no })
end

local n = 0
local function send(name, payload)
  n = n + 1
  local id = "fi-" .. n
  local b = H.fake_bridge({ reason = "reason_code" })
  require("core.validate").reset_run_state()
  assert(TxCache.open(id, name, G.TIMERS.REAL))
  Dispatcher.handle_message({ command = "action", data = { id = id, name = name, data = payload } }, b)
  return b.results[#b.results] or {}
end
local function sale(between)
  H.shop_env(); neuro("SHOP"); require("core.gate").reset(); Dispatcher.reset_run_state("sell review key")
  local j = V.card_played("j_luchador", 701); j.sell_cost, j.facing = 5, "front"
  G.jokers = { cards = { j }, config = { card_limit = 5 } }; j.area = G.jokers
  H.stage_registered("SHOP", { "sell_card", "record_joker_roles", "record_plan" })
  local sell = [[{"area":"jokers","index":1,"name":"Luchador","plan":{"build_plan":"sell it","money_plan":"hold"}}]]
  local first = send("sell_card", sell)
  if between then between() end
  for _ = 1, 200 do
    if not require("core.execute").busy() then break end
    G.TIMERS.REAL = G.TIMERS.REAL + 0.1
    require("core.execute").step(G.TIMERS.REAL)
    G.E_MANAGER:run()
  end
  return first, send("sell_card", sell)
end

local first, second = sale()
check("the first joker sale opens a review", first.reason_code == "CONFIRMATION_REQUIRED", tostring(first.reason_code))
check("the next sale is final", second.reason_code == "ACTION_ACCEPTED", tostring(second.reason_code))

_, second = sale(function() send("record_joker_roles", [[{"intents":[{"index":1,"tag":"CORE"}]}]]) end)
check("recording joker roles in between does not reopen the review", second.reason_code == "ACTION_ACCEPTED",
  tostring(second.reason_code))

_, second = sale(function() send("record_plan", [[{"build_plan":"keep it"}]]) end)
check("recording a plan in between does not reopen the review", second.reason_code == "ACTION_ACCEPTED",
  tostring(second.reason_code))

_, second = sale(function() G.GAME.dollars = G.GAME.dollars + 7 end)
check("a change in the game itself still reopens the review", second.reason_code == "CONFIRMATION_REQUIRED",
  tostring(second.reason_code))

done()
