require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("joker-order-reforce")
local H = require("tests.helpers")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local Gate = require("core.gate")

LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
local constellation = Vanilla.card("j_constellation", 804)
constellation.ability.x_mult = 1.9
G.jokers = { cards = { constellation, Vanilla.card("j_jolly", 805) }, config = { card_limit = 5 } }
G.NEURO.gates = nil

local first = FP.build("SHOP")
check("the shop force is offered with leave_shop", first ~= nil and table.concat(first.actions, ","):find("leave_shop", 1, true) ~= nil)
check("the roster has an order gap", Gate.pending("joker_order"))

local seen = {}
G.NEURO.send_action_result = function(_, id, success, message, code)
  seen[#seen + 1] = { id = id, success = success, message = tostring(message), code = code }
  return true
end
local review = Gate.text("joker_order")
H.stage_registered("SHOP")
H.dispatch("leave_shop", "jo-1", '{"intents":[{"index":1,"tag":"CORE"},{"index":2,"tag":"CORE"}]}', G.NEURO)
local r = seen[1] or {}
check("the hold answers success:true, so the stale force is not retried",
  r.success == true and r.code == "CONFIRMATION_REQUIRED", tostring(r.success) .. " " .. tostring(r.code) .. " " .. tostring(r.message))
check("the result names the way out", r.message ~= nil and r.message:find("joker_order_confirmed", 1, true) ~= nil,
  tostring(r.message))
check("the gate still holds a plain leave_shop", Gate.pending("joker_order"))

local after = FP.next()
local query = after and after.query or ""
check("the orchestrator sends a replacement shop force", after ~= nil
  and table.concat(after.actions, ","):find("leave_shop", 1, true) ~= nil, query)
local _, copies = query:gsub(review:gsub("%p", "%%%0"), "")
check("the replacement force carries the review exactly once", copies == 1, tostring(copies) .. " " .. query)
check("and offers the confirmation parameter on leave_shop", query:find("joker_order_confirmed", 1, true) ~= nil, query)

check("leave_shop with joker_order_confirmed true passes the gate",
  Gate.check("plan", "leave_shop", { joker_order_confirmed = true }) == nil)

done()
