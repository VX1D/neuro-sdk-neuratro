_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("plan-transaction")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local PlanTransaction = require("core.plan_transaction")

local function joker(key, name)
  return {
    ability = { set = "Joker", name = name or key },
    config = { center = { key = key, set = "Joker", loc_txt = { name = name or key } } },
    cost = 4, sell_cost = 2, sort_id = key,
  }
end

local function bridge()
  return {
    results = {}, contexts = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
      return true, { status = "written", written_at = clock }
    end,
    send_context = function(self, message) self.contexts[#self.contexts + 1] = message end,
    unregister_actions = function() end,
    consume_actions = function() return true end,
    withdraw_actions_exact = function(_, names)
      return { status = "written", names = names, written_at = clock }
    end,
    complete_action_withdrawal = function() return true end,
    is_transition_cooldown = function() return false end,
  }
end

local function base(state, actions)
  clock = clock + 10
  local state_id = state == "SHOP" and 2 or 1
  _G.G = {
    STATE = state_id,
    STATES = { BLIND_SELECT = 1, SHOP = 2 },
    P_BLINDS = {
      bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_boss = { key = "bl_boss", name = "Boss Blind" },
    },
    GAME = {
      dollars = 20,
      round_resets = {
        ante = 2,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
      },
      current_round = { reroll_cost = 5, free_rerolls = 0 },
      modifiers = {},
    },
    NEURO = {
      state = state, run_generation = 7, shop_visit_epoch = 3, economy_epoch = 2,
      state_enter_serial = 11, once_serials = {},
    },
    FUNCS = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
  if state == "SHOP" then G.shop = {} end
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  local names = {}
  for n in pairs(actions or {}) do names[#names + 1] = n end
  table.sort(names)
  require("core.force_state").arm(state, names, actions or {}, 1)
  require("tests.helpers").stage_registered(state, names)
end

local function send(name, id, data, b, stale_generation)
  if stale_generation then
    local FS = require("core.force_state")
    FS.arm(G.NEURO.state or "SHOP", { name }, { [name] = true }, clock)
    FS.mark_sent(clock)
    G.NEURO.force_generation = stale_generation
  end
  Dispatcher.handle_message({
    command = "action",
    data = { id = id, name = name, data = data },
  }, b)
end

do
  base("SHOP", { buy_from_shop = true })
  local card = joker("j_wrathful", "Wrathful Joker")
  G.shop_jokers.cards = { card }
  local buys = 0
  G.FUNCS.buy_from_shop = function()
    buys = buys + 1
    G.shop_jokers.cards = {}
    G.jokers.cards = { card }
  end
  local b = bridge()
  local payload = { area = "shop_jokers", index = 1, plan = { money_plan = "Spend for this upgrade, then hold." } }
  send("buy_from_shop", "buy-one", payload, b)
  check("buy sends exactly one positive action result", #b.results == 1 and b.results[1].ok == true, #b.results)
  check("buy base closure executes exactly once", buys == 1, buys)
  check("buy plan commits only after the observed transfer", G.NEURO.plan ~= nil)
  check("buy leaves nothing held after applied", G.NEURO.held_plan_write == nil)
  check("buy writes post-action money scope", G.NEURO.plan and G.NEURO.plan.money == payload.plan.money_plan
    and require("core.plan_gate").money_plan_is_current(G.NEURO.plan))
  send("buy_from_shop", "buy-one", payload, b)
  check("redelivery replays one result without second execution", #b.results == 2 and buys == 1, buys)
end

do
  base("SHOP", { buy_from_shop = true })
  G.shop_jokers.cards = { joker("j_a", "Joker A") }
  local buys = 0
  G.FUNCS.buy_from_shop = function() buys = buys + 1 end
  local b = bridge()
  send("buy_from_shop", "buy-missing", { area = "shop_jokers", index = 1 }, b)
  check("missing required plan field is a negative precondition", #b.results == 1 and b.results[1].ok == false
    and b.results[1].reason_code == "PRECONDITION_FAILED", b.results[1] and b.results[1].reason_code)
  check("missing plan does not mutate game or plan state", buys == 0 and G.NEURO.plan == nil)

  base("SHOP", { buy_from_shop = true })
  local long_card = joker("j_a", "Joker A")
  G.shop_jokers.cards = { long_card }
  G.FUNCS.buy_from_shop = function()
    buys = buys + 1
    G.shop_jokers.cards = {}
    G.jokers.cards = { long_card }
  end
  b = bridge()
  local long_plan = string.rep("x", 3000)
  send("buy_from_shop", "buy-long", { area = "shop_jokers", index = 1,
    plan = { money_plan = long_plan } }, b)
  check("a long inline plan field is accepted, not refused by the schema",
    b.results[1] and b.results[1].ok == true, b.results[1] and b.results[1].reason_code)
  check("the long inline plan field is committed verbatim",
    G.NEURO.plan and G.NEURO.plan.money == long_plan,
    G.NEURO.plan and #tostring(G.NEURO.plan.money))
end

do
  base("SHOP", { sell_card = true })
  local card = joker("j_popcorn", "Popcorn")
  G.jokers.cards = { card }
  local sells = 0
  G.FUNCS.sell_card = function(e)
    sells = sells + 1
    for i, item in ipairs(G.jokers.cards) do
      if item == e.config.ref_table then table.remove(G.jokers.cards, i) break end
    end
  end
  local b = bridge()
  local sell_payload = { area = "jokers", index = 1,
    plan = { build_plan = "Sell Popcorn and replace it with scaling.", money_plan = "Bank the proceeds." } }
  send("sell_card", "sell-inline", sell_payload, b)
  check("complete explicit plan still confirms before the first sell",
    b.results[1] and b.results[1].ok == true
    and b.results[1].reason_code == "CONFIRMATION_REQUIRED" and sells == 0,
    b.results[1] and b.results[1].reason_code)
  check("the rejected sell commits no plan", G.NEURO.plan == nil)
  check("the rejected sell holds its plan for the confirming resend",
    G.NEURO.held_plan_write ~= nil
      and G.NEURO.held_plan_write.values.build_plan == sell_payload.plan.build_plan
      and G.NEURO.held_plan_write.values.money_plan == sell_payload.plan.money_plan)
  require("core.context_review").step_delivery()
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SHOP", { "sell_card" }, { sell_card = true }, 1)
  send("sell_card", "sell-inline-2", sell_payload, b)
  check("repeating the same envelope sells", b.results[2] and b.results[2].ok == true and sells == 1, sells)
  check("sell plan commits after action", G.NEURO.plan and G.NEURO.plan.build ~= nil and G.NEURO.plan.money ~= nil)
  check("the committing sell releases the held plan", G.NEURO.held_plan_write == nil)

  base("SHOP", { sell_card = true })
  G.jokers.cards = { joker("j_popcorn", "Popcorn") }
  local _, guard_err = require("handlers.shop_handlers").handle_sell_card({ area = "jokers", index = 1,
    plan = { build_plan = "Sell it." } })
  check("incomplete plan does not bypass legacy sell confirm", guard_err and guard_err.reason_code == "CONFIRMATION_REQUIRED")
end

do
  base("SHOP", { leave_shop = true })
  G.jokers.cards = { joker("j_core", "Core Joker") }
  G.NEURO.joker_intents = { j_core = { tag = "CORE" } }
  G.NEURO.shop_plan_revision_required = { build = true, money = true }
  local leaves = 0
  G.FUNCS.toggle_shop = function()
    leaves = leaves + 1
    G.shop = nil
    G.STATE = G.STATES.BLIND_SELECT
    G.NEURO.state = "BLIND_SELECT"
  end
  local b = bridge()
  send("leave_shop", "leave-inline", {
    plan = { build_plan = "Keep Core Joker and add xMult.", money_plan = "Hold for interest." },
  }, b)
  check("toggle commits plan and executes once", b.results[1] and b.results[1].ok == true and leaves == 1
    and G.NEURO.plan and G.NEURO.plan.build ~= nil, leaves)
end

do
  base("SHOP", { leave_shop = true })
  G.jokers.cards = { joker("j_core", "Core Joker") }
  G.NEURO.joker_intents = { j_core = { tag = "CORE" } }
  G.NEURO.shop_plan_revision_required = { build = true, money = true }
  local DW = require("core.decision_window")
  local real_acknowledge = DW.acknowledge
  local order = {}
  DW.acknowledge = function(name)
    order[#order + 1] = "acknowledge:" .. tostring(name)
    return real_acknowledge(name)
  end
  G.FUNCS.toggle_shop = function()
    order[#order + 1] = "exec"
    G.shop = nil
    G.STATE = G.STATES.BLIND_SELECT
    G.NEURO.state = "BLIND_SELECT"
  end
  local b = bridge()
  send("leave_shop", "ack-order", {
    plan = { build_plan = "Keep Core Joker and add xMult.", money_plan = "Hold for interest." },
  }, b)
  DW.acknowledge = real_acknowledge
  check("decision windows acknowledge after the handler ran, not before",
    order[1] == "exec" and order[2] == "acknowledge:leave_shop", table.concat(order, ","))
end

do
  base("BLIND_SELECT", { select_blind = true })
  G.blind_select = {}
  local selected = 0
  G.FUNCS.select_blind = function()
    selected = selected + 1
    G.GAME.round_resets.blind_states.Small = "Current"
  end
  local b = bridge()
  send("select_blind", "blind-inline", { blind = "small", plan = {
    hand_plan = "Play Two Pair; discard isolated ranks.",
    build_plan = "Add multiplicative scaling next.",
  } }, b)
  check("select_blind executes on first inline-plan call", b.results[1] and b.results[1].ok == true and selected == 1, selected)
  check("select_blind commits both fields", G.NEURO.plan and G.NEURO.plan.hand ~= nil and G.NEURO.plan.build ~= nil)
end

do
  base("SELECTING_HAND", { play_hand = true, discard_hand = true })
  G.NEURO.plan = {
    hand = "Play the blind-scoped pair line.",
    hand_scope = require("core.plan_gate").current_blind_scope(),
    build = "Keep the current build.",
    build_scope = require("core.plan_gate").current_build_scope(),
  }
  local before_hand, before_scope = G.NEURO.plan.hand, G.NEURO.plan.hand_scope
  local play_tx = PlanTransaction.prepare("play_hand", { plan = {
    hand_plan = "Transient cards QQQ plus 333.",
    boss_plan = "Pace discards through this boss.",
  } })
  check("per-hand play ignores hand_plan mechanically", play_tx ~= nil
    and play_tx.plan_values.hand_plan == nil, play_tx and play_tx.plan_values.hand_plan)
  check("per-hand play retains boss_plan", play_tx ~= nil
    and play_tx.plan_values.boss_plan == "Pace discards through this boss.")
  check("preparing per-hand plan does not overwrite blind plan",
    G.NEURO.plan.hand == before_hand and G.NEURO.plan.hand_scope == before_scope)

  local discard_tx, discard_err = PlanTransaction.prepare("discard_hand", { plan = {
    hand_plan = "Discard these exact live indices.",
  } })
  check("per-hand discard ignores a filtered-only plan without manufacturing a rejection",
    discard_tx == nil and discard_err == nil, discard_err and discard_err.message)
  check("discard preparation leaves blind plan unchanged",
    G.NEURO.plan.hand == before_hand and G.NEURO.plan.hand_scope == before_scope)

  local blank_tx, blank_err = PlanTransaction.prepare("play_hand", { plan = {
    boss_plan = "",
  } })
  check("optional blank boss_plan is absent rather than an invalid plan",
    blank_tx == nil and blank_err == nil, blank_err and blank_err.message)

  local whitespace_tx, whitespace_err = PlanTransaction.prepare("discard_hand", { plan = {
    boss_plan = " \t\n\r",
  } })
  check("optional whitespace-only boss_plan is absent",
    whitespace_tx == nil and whitespace_err == nil, whitespace_err and whitespace_err.message)
end

local BLANK_REQUIRED = "Provide plan.boss_plan with this action: an empty value is not a plan."
local MISSING_REQUIRED = "Provide plan.boss_plan with this action."

do
  base("SELECTING_HAND", { play_hand = true })
  G.STATES.SELECTING_HAND = 3
  G.STATE = 3
  G.GAME.blind = { boss = true, config = { blind = { key = "bl_test_boss" } } }
  local tx, err = PlanTransaction.prepare("play_hand", { plan = { boss_plan = "" } })
  check("required blank boss_plan is refused by the transaction as a malformed write",
    tx == nil and err ~= nil and tostring(err.message) == BLANK_REQUIRED, err and err.message)

  local missing_tx, missing_err = PlanTransaction.prepare("play_hand", {})
  check("the transaction refuses a required field with nothing to inherit, in its own words",
    missing_tx == nil and missing_err ~= nil and tostring(missing_err.message) == MISSING_REQUIRED,
    missing_err and missing_err.message)

  PlanTransaction.hold({ plan_values = { boss_plan = "Held rule from a refused action." } })
  local held_tx, held_err = PlanTransaction.prepare("play_hand", { plan = { boss_plan = " \t " } })
  check("a blank required field is not answered by a held write either",
    held_tx == nil and held_err ~= nil and tostring(held_err.message) == BLANK_REQUIRED,
    held_err and held_err.message)
  local resumed_tx = PlanTransaction.prepare("play_hand", {})
  check("the same hold still resumes when the field is genuinely omitted",
    resumed_tx ~= nil and resumed_tx.plan_values.boss_plan == "Held rule from a refused action.",
    resumed_tx and resumed_tx.plan_values.boss_plan)
  PlanTransaction.release()
end

do
  base("BLIND_SELECT", { select_blind = true })
  G.blind_select = {}
  G.GAME.blind_on_deck = "Boss"
  G.GAME.round_resets.blind_states = { Small = "Defeated", Big = "Defeated", Boss = "Select" }
  local PlanGate = require("core.plan_gate")
  local selected = 0
  G.FUNCS.select_blind = function()
    selected = selected + 1
    G.GAME.round_resets.blind_states.Boss = "Current"
  end
  G.NEURO.plan = {
    hand = "Play the pair line.", hand_scope = PlanGate.current_blind_scope(),
    build = "Add xMult next.", build_scope = PlanGate.current_build_scope(),
    boss = "Hearts score 0, so do not build on Hearts.", boss_scope = PlanGate.current_boss_scope(),
  }
  check("the standing boss rule is current for this very boss, so inheritance is available",
    PlanGate.boss_plan_is_current(G.NEURO.plan))
  local blank_tx, blank_err = PlanTransaction.prepare("select_blind",
    { blind = "boss", plan = { boss_plan = "   " } })
  check("a blank REQUIRED boss_plan is not satisfied by the standing rule for the same boss",
    blank_tx == nil and blank_err ~= nil and tostring(blank_err.message) == BLANK_REQUIRED,
    blank_err and blank_err.message)

  local b = bridge()
  send("select_blind", "blind-blank-boss", { blind = "boss", plan = { boss_plan = "  " } }, b)
  check("and the blind is not selected on a blank required plan",
    b.results[1] and b.results[1].ok == false
      and b.results[1].reason_code == "PRECONDITION_FAILED" and selected == 0,
    tostring(b.results[1] and b.results[1].reason_code) .. "/" .. tostring(selected))

  local absent_tx, absent_err = PlanTransaction.prepare("select_blind", { blind = "boss" })
  check("an omitted boss_plan still inherits the standing rule, as designed",
    absent_tx ~= nil and absent_err == nil
      and absent_tx.plan_values.boss_plan == "Hearts score 0, so do not build on Hearts.",
    absent_err and absent_err.message)
end

do
  base("SHOP", { reroll_shop = true })
  G.FUNCS.reroll_shop = function() error("boom") end
  local b = bridge()
  send("reroll_shop", "reroll-throw", { plan = { money_plan = "Spend once, then hold." } }, b)
  check("throw path sends only the existing optimistic result", #b.results == 1 and b.results[1].ok == true, #b.results)
  check("throw path commits no plan", G.NEURO.plan == nil)
end

do
  base("SHOP", { reroll_shop = true })
  local Receipt = require("core.action_receipt")
  Receipt.reset("plan-test")
  local data = { plan = { money_plan = "Spend once only after the reroll is observed." } }
  local tx = assert(PlanTransaction.prepare("reroll_shop", data))
  local applied = false
  local wrapped = PlanTransaction.wrap("reroll_shop", data, function()
    return Receipt.create({
      id = "plan-receipt",
      name = "reroll_shop",
      run_generation = G.NEURO.run_generation,
      started_at = clock,
      deadline = clock + 5,
      probe = function() return applied and "applied" or "pending" end,
    })
  end, tx)
  local receipt = wrapped()
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  Receipt.update(clock + 1, G.NEURO.run_generation)
  check("receipt plan remains uncommitted while execution is pending", G.NEURO.plan == nil)
  applied = true
  Receipt.update(clock + 2, G.NEURO.run_generation)
  check("receipt plan commits only after applied", G.NEURO.plan and G.NEURO.plan.money == data.plan.money_plan)

  Receipt.reset("plan-test-2")
  base("SHOP", { reroll_shop = true })
  data = { plan = { money_plan = "This older plan must not overwrite a newer revision." } }
  tx = assert(PlanTransaction.prepare("reroll_shop", data))
  wrapped = PlanTransaction.wrap("reroll_shop", data, function()
    return Receipt.create({
      id = "stale-plan-receipt",
      name = "reroll_shop",
      run_generation = G.NEURO.run_generation,
      started_at = clock,
      deadline = clock + 5,
      probe = function() return "applied" end,
    })
  end, tx)
  receipt = wrapped()
  G.NEURO.plan_revision = (tonumber(G.NEURO.plan_revision) or 0) + 1
  G.NEURO.plan = { money = "newer plan" }
  Receipt.transition(receipt, "acknowledged")
  Receipt.transition(receipt, "executing")
  Receipt.transition(receipt, "verifying")
  Receipt.update(clock + 1, G.NEURO.run_generation)
  check("older receipt never overwrites a newer plan revision", G.NEURO.plan.money == "newer plan")
end

do
  base("SHOP", { reroll_shop = true })
  G.FUNCS.reroll_shop = function() end
  local b = bridge()
  send("reroll_shop", "stale", { plan = { money_plan = "Spend once, then hold." } }, b, 6)
  check("stale generation rejected before plan preparation (plan untouched)",
    b.results[1] and b.results[1].reason_code == "STALE_GENERATION" and G.NEURO.plan == nil)
  check("a stale generation does not retry force after success=true per SPECIFICATION.md:188",
    b.results[1] and b.results[1].ok == true, b.results[1] and tostring(b.results[1].ok))

end

done()
