love = { timer = { getTime = function() return 0 end } }

local Shop = require("handlers.shop_handlers")
local check, done = require("tests.helpers").harness("voucher-confirm")

local function card(id, set, cost)
  return {
    sort_id = id, cost = cost or 10, sell_cost = 1,
    ability = { name = "Card " .. tostring(id), set = set },
    config = { center = { key = "c_" .. tostring(id), set = set } },
    base = { value = "5", suit = "Spades" },
  }
end

local function board()
  _G.G = {
    STATE = 2, STATES = { SHOP = 2 },
    NEURO = { state = "SHOP", run_generation = 1, decision_serial = 7, state_enter_serial = 3 },
    GAME = { dollars = 20, current_round = {}, round_resets = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = { card(1, "Voucher", 10) } },
    shop_jokers = { cards = { card(2, "Joker", 4) } },
    shop_booster = { cards = { card(3, "Booster", 4) } },
    FUNCS = {}, P_CENTERS = {},
  }
end

local function buy(area, index)
  return Shop.handle_buy_from_shop({ area = area, index = index })
end

do
  board()
  local exec, err = buy("shop_vouchers", 1)
  check("a voucher does not buy on the first send",
    exec == nil and type(err) == "table" and err.reason_code == "CONFIRMATION_REQUIRED",
    type(err) == "table" and tostring(err.reason_code) or type(err))
  check("the confirmation states the cost, what is left, and that it cannot be undone",
    type(err) == "table" and err.message:find("$10", 1, true)
      and err.message:find("cannot be sold or undone", 1, true) ~= nil,
    type(err) == "table" and err.message or "")

  local exec2 = buy("shop_vouchers", 1)
  check("an identical resend goes through", type(exec2) == "function",
    type(exec2))
end

do
  board()
  for _, spec in ipairs({ { "shop_jokers", 1 }, { "shop_booster", 1 } }) do
    local exec = buy(spec[1], spec[2])
    check("no confirmation for " .. spec[1] .. " -- the beat is for vouchers only",
      type(exec) == "function", type(exec))
  end
end

do
  board()
  G.NEURO._candidate_probe = true
  buy("shop_vouchers", 1)
  check("an availability probe never arms the confirmation",
    G.NEURO.last_voucher_reject == nil, tostring(G.NEURO.last_voucher_reject))
end

do
  board()
  buy("shop_vouchers", 1)
  G.NEURO.decision_serial = 8
  local exec, err = buy("shop_vouchers", 1)
  check("a board that moved under the model re-asks instead of committing",
    exec == nil and type(err) == "table" and err.reason_code == "CONFIRMATION_REQUIRED",
    type(err) == "table" and tostring(err.reason_code) or type(err))
end

do
  board()
  local Registry = require("core.action_registry")
  require("core.dispatcher")
  local first = #Registry.candidates("buy_from_shop")
  local armed_after_first = G.NEURO.last_voucher_reject
  local second = #Registry.candidates("buy_from_shop")
  check("enumerating the shop twice yields the same offer both times",
    first == second, tostring(first) .. " vs " .. tostring(second))
  check("enumerating the shop never arms the confirmation",
    armed_after_first == nil and G.NEURO.last_voucher_reject == nil,
    tostring(armed_after_first))
end

done()
