_G.NEURO_TEST = true
love = { timer = { getTime = function() return 0 end } }

local check, done = require("tests.helpers").harness("context-review-architecture")
local ActionResult = require("core.action_result")
local Review = require("core.context_review")
local Shop = require("handlers.shop_handlers")

local function card(id, set, cost)
  return {
    sort_id = id, cost = cost or 4, sell_cost = 3,
    ability = { name = id, set = set },
    config = { center = { key = id, set = set, loc_txt = { name = id } } },
  }
end

local function board()
  G = {
    STATE = 2, STATES = { SHOP = 2 },
    NEURO = { state = "SHOP", state_enter_serial = 3, run_generation = 1,
      decision_serial = 7, shop_visit_epoch = 2 },
    GAME = { dollars = 30, current_round = {}, round_resets = {}, used_vouchers = {} },
    jokers = { cards = { card("Alpha", "Joker"), card("Beta", "Joker") },
      config = { card_limit = 5 } },
    consumeables = { cards = { card("Death", "Tarot") }, config = { card_limit = 2 } },
    shop_vouchers = { cards = { card("Blank", "Voucher", 10), card("Paint Brush", "Voucher", 10) } },
    shop_jokers = { cards = { card("Jolly Joker", "Joker", 4) } },
    shop_booster = { cards = {} },
    FUNCS = { sell_card = function() end, use_card = function() end,
      buy_from_shop = function() end },
    P_CENTERS = {},
  }
end

local function deliver(err, status)
  check("review rejection carries a delivery candidate",
    ActionResult.is_error(err) and type(err.context_review_candidate) == "table")
  local receipt = { status = status or "written" }
  local staged = Review.stage(err.context_review_candidate, receipt)
  Review.step_delivery()
  return staged, receipt
end

board()
local _, sell_err = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
local sell_key = sell_err.context_review_candidate.context_key
check("first joker sale is review-only", sell_err and sell_err.reason_code == "CONFIRMATION_REQUIRED")
check("handler does not pre-arm review before delivery",
  not Review.is_reviewed("sell_joker", sell_key))
deliver(sell_err)
check("durable delivery promotes sale context", Review.is_reviewed("sell_joker", sell_key))
local sell_b = Shop.handle_sell_card({ area = "jokers", index = 2, name = "Beta" })
check("A review makes B final in the unchanged context", type(sell_b) == "function")
check("final prompt names the semantic privilege",
  Shop.pending_confirmation_note({ sell_card = true }):find("FINAL SELL CHOICE", 1, true) ~= nil)

board()
local _, rejected_err = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
deliver(rejected_err, "rejected")
check("rejected result delivery does not consume review",
  not Review.is_reviewed("sell_joker", rejected_err.context_review_candidate.context_key))
local _, retry_err = Shop.handle_sell_card({ area = "jokers", index = 2, name = "Beta" })
check("after failed delivery another target is reviewed, not committed",
  retry_err and retry_err.reason_code == "CONFIRMATION_REQUIRED")

board()
local _, buffered_err = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
local receipt = { status = "buffered" }
check("buffered review stages", Review.stage(buffered_err.context_review_candidate, receipt))
Review.step_delivery()
local buffered_key = buffered_err.context_review_candidate.context_key
check("buffered review is not final yet", not Review.is_reviewed("sell_joker", buffered_key))
receipt.status = "written"
Review.step_delivery()
check("buffered review becomes final only after write",
  Review.is_reviewed("sell_joker", buffered_key))
G.GAME.dollars = 31
local _, money_changed = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
check("relevant money change invalidates and re-arms sale review",
  money_changed and money_changed.reason_code == "CONFIRMATION_REQUIRED")

board()
local _, voucher_err = Shop.handle_buy_from_shop({ area = "shop_vouchers", index = 1, name = "Blank" })
check("first voucher buy is review-only", voucher_err and voucher_err.reason_code == "CONFIRMATION_REQUIRED")
deliver(voucher_err)
local voucher_b = Shop.handle_buy_from_shop({ area = "shop_vouchers", index = 2, name = "Paint Brush" })
check("voucher A review makes voucher B final", type(voucher_b) == "function")
check("voucher final choice is restated",
  Shop.pending_confirmation_note({ buy_from_shop = true }):find("FINAL VOUCHER CHOICE", 1, true) ~= nil)
local ordinary_buy = Shop.handle_buy_from_shop({ area = "shop_jokers", index = 1, name = "Jolly Joker" })
check("soft voucher review does not block another action family", type(ordinary_buy) == "function")

board()
local _, one = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
local one_key = one.context_review_candidate.context_key
deliver(one)
G.NEURO.state_enter_serial = 4
check("state transition invalidates a reviewed privilege",
  not Review.is_reviewed("sell_joker", one_key))
local _, next_state = Shop.handle_sell_card({ area = "jokers", index = 1, name = "Alpha" })
check("new state gets exactly one fresh review", next_state and next_state.reason_code == "CONFIRMATION_REQUIRED")

done()
