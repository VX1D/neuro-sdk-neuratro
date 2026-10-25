-- Negative balances render as -$5, not $-5.
rawset(_G, "NEURO_TEST", true)
local H = require("tests.hand_pipeline_harness")
local Helpers = require("tests.helpers")
local Utils = require("util.utils")
local DecisionDelta = require("facts.decision_delta")
local check, done = Helpers.harness("negative-money-render")

check("formatter writes a negative amount as -$5", Utils.money(-5) == "-$5", Utils.money(-5))
check("formatter writes a positive amount as $5", Utils.money(5) == "$5", Utils.money(5))
check("a change is signed before the dollar sign", Utils.money_change(-3) == "-$3" and Utils.money_change(3) == "+$3",
  Utils.money_change(-3) .. " " .. Utils.money_change(3))

H.board({ blind = { name = "The Tooth", key = "bl_tooth", chips = 600, dollars = 5, boss = true, in_blind = true } })
G.GAME.dollars = 0
local board = DecisionDelta.capture()
G.NEURO.decision_snapshot = { window = -1, mint = 0, run_generation = G.NEURO.run_generation, board = board,
  journal = { through_sequence = 0 } }
G.GAME.dollars = -5
H.tick(12)

local state
for _, f in ipairs(H.frames()) do
  if f.command == "actions/force" then state = tostring(f.data.state) end
end
state = state or ""
check("a force was sent", state ~= "", state)
check("no money figure in the frame is written $-N", state:find("$-", 1, true) == nil, state)

do
  local UseCard = require("handlers.use_card")
  G.GAME.dollars = 0
  local before = UseCard.outcome_snapshot()
  G.GAME.dollars = -5
  local suffix = UseCard.outcome_suffix(before)
  check("the use result never writes $-N", suffix:find("$-", 1, true) == nil, suffix)
end

do
  G.STATE = H.STATES.SHOP
  G.NEURO.state = "SHOP"
  G.shop = {}
  G.GAME.dollars = -5
  G.GAME.bankrupt_at = -20
  G.GAME.current_round.reroll_cost = 20
  G.GAME.current_round.free_rerolls = 0
  G.shop_jokers = Helpers.area({ require("tests.engine_cards").card({
    config = { center = { key = "j_joker", set = "Joker", name = "Joker", rarity = 1 } },
    ability = { name = "Joker", set = "Joker" }, cost = 20, sell_cost = 10, sort_id = 901 }) })
  local _, err = require("handlers.shop_handlers").handle_buy_from_shop(
    { area = "shop_jokers", index = 1, _action_id = "neg-buy" })
  local refusal = tostring(err and err.message)
  check("the buy refusal never writes $-N", refusal:find("$-", 1, true) == nil, refusal)

  G.GAME.bankrupt_at = 0
  local reroll = tostring(require("core.actions").unavailable_reason("reroll_shop"))
  check("the reroll refusal never writes $-N", reroll:find("$-", 1, true) == nil, reroll)
end

H.finish(check, done)
