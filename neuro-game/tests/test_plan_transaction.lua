_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("plan-transaction")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local PlanTransaction = require("core.plan_transaction")
local function joker(key, name)
  return require("tests.engine_cards").card({
    ability = { set = "Joker", name = name or key },
    config = { center = { key = key, set = "Joker", loc_txt = { name = name or key } } },
    cost = 4, sell_cost = 2, sort_id = key,
  })
end

local function bridge()
  return {
    results = {}, contexts = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
      return true, { status = "written", written_at = clock }
    end,
    send_context = function(self, message) self.contexts[#self.contexts + 1] = message return true end,
    withdraw_actions = function() return true end,
    is_transition_cooldown = function() return false end,
  }
end

local function base(state, actions)
  clock = clock + 10
  local states = require("tests.engine_cards").states()
  _G.G = {
    STATE = states[state],
    STATES = states,
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
      state_enter_serial = 11, once_serials = {}, decision_serial = 1,
      transport_session = "plan-transaction", transport_epoch = 1,
    },
    FUNCS = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
  if state == "SHOP" then G.shop = {} end
  require("tests.helpers").event_manager()
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  local names = {}
  for n in pairs(actions or {}) do names[#names + 1] = n end
  table.sort(names)
  require("tests.helpers").open_force(state, names)
  require("tests.helpers").stage_registered(state, names)
end

local send = require("tests.helpers").dispatch
local function send_buy(...)
  send(...)
  G.E_MANAGER:run()
  require("core.execute").step(clock)
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
  send_buy("buy_from_shop", "buy-one", payload, b)
  check("buy sends exactly one positive action result", #b.results == 1 and b.results[1].ok == true, #b.results)
  check("buy base closure executes exactly once", buys == 1, buys)
  check("buy leaves nothing held after applied", G.NEURO.held_plan_write == nil)
  check("buy writes post-action money scope", G.NEURO.plan and G.NEURO.plan.money == payload.plan.money_plan
    and require("core.gate").money_plan_is_current(G.NEURO.plan))
  send_buy("buy_from_shop", "buy-one", payload, b)
  check("same-session redelivery is suppressed without second execution", #b.results == 1 and buys == 1,
    tostring(#b.results) .. "/" .. tostring(buys))
end

do
  base("SHOP", { buy_from_shop = true })
  local card = joker("j_blue", "Blue Joker")
  G.shop_jokers.cards = { card }
  G.FUNCS.buy_from_shop = function() G.shop_jokers.cards = {}; G.jokers.cards = { card } end
  local b = bridge()
  send_buy("buy_from_shop", "buy-stray-plan", { area = "shop_jokers", index = 1,
    plan = { money_plan = "Spend $5 on Blue Joker.", primary = "Two Pair", fallback = "Pair" } }, b)
  local told = tostring(b.results[1] and b.results[1].message)
  check("the buy with stray plan keys still applies", b.results[1] and b.results[1].ok == true,
    b.results[1] and b.results[1].reason_code)
  check("its result is the only report: no context frame follows",
    #b.contexts == 0, told .. " / contexts " .. #b.contexts)
  check("the valid plan field is still saved", G.NEURO.plan and G.NEURO.plan.money == "Spend $5 on Blue Joker.")
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
  local long_plan = string.rep("x", require("core.plan_limits").PLAN_TEXT_MAX)
  send_buy("buy_from_shop", "buy-long", { area = "shop_jokers", index = 1,
    plan = { money_plan = long_plan } }, b)
  check("a plan at the shared inline text cap is accepted",
    b.results[1] and b.results[1].ok == true, b.results[1] and b.results[1].reason_code)
  check("the capped inline plan field is committed verbatim",
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
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SHOP", { "sell_card" })
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
  local Gate = require("core.gate")
  local real_acknowledge = Gate.acknowledge
  local order = {}
  Gate.acknowledge = function(snapshot)
    order[#order + 1] = "acknowledge:" .. tostring(snapshot and snapshot[1] and snapshot[1].id)
    return real_acknowledge(snapshot)
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
  Gate.acknowledge = real_acknowledge
  check("gates acknowledge after the handler ran, not before",
    order[1] == "exec" and order[2] == "acknowledge:interest_engine_off", table.concat(order, ","))
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
    hand_scope = require("core.gate").current_blind_scope(),
    build = "Keep the current build.",
    build_scope = require("core.gate").current_build_scope(),
  }
  local before_hand, before_scope = G.NEURO.plan.hand, G.NEURO.plan.hand_scope
  G.GAME.blind = { boss = true, config = { blind = { key = "bl_test_boss" } } }
  local play_tx = PlanTransaction.prepare("play_hand", { plan = {
    hand_plan = "Transient cards QQQ plus 333.",
    boss_plan = "Pace discards through this boss.",
  } })
  G.GAME.blind = nil
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
    discard_err == nil and (discard_tx == nil or discard_tx.note_only == true), discard_err and discard_err.message)
  check("discard preparation leaves blind plan unchanged",
    G.NEURO.plan.hand == before_hand and G.NEURO.plan.hand_scope == before_scope)

  G.GAME.round_resets = G.GAME.round_resets or {}
  local saved_choices = G.GAME.round_resets.blind_choices
  G.GAME.round_resets.blind_choices = { Boss = "bl_test_boss" }
  local off_boss_tx, off_boss_err = PlanTransaction.prepare("discard_hand", { plan = {
    boss_plan = "Pace discards through this boss.",
  } })
  check("a boss_plan with a discard outside the Boss blind is not saved, and the result says so",
    off_boss_err == nil and (off_boss_tx == nil or not (off_boss_tx.plan_values and off_boss_tx.plan_values.boss_plan))
      and PlanTransaction.ignored_note("discard_hand", { plan = { boss_plan = "Pace discards through this boss." } }) ~= nil,
    off_boss_tx and tostring(off_boss_tx.ignored_note) or (off_boss_err and off_boss_err.message))
  G.GAME.round_resets.blind_choices = saved_choices

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

do
  base("SELECTING_HAND", { play_hand = true })
  G.GAME.blind = { boss = true, config = { blind = { key = "bl_test_boss" } } }
  local tx, err = PlanTransaction.prepare("play_hand", { plan = { boss_plan = "" } })
  check("required blank boss_plan is refused by the transaction as a malformed write",
    tx == nil and err ~= nil, err and err.message)

  local missing_tx, missing_err = PlanTransaction.prepare("play_hand", {})
  check("the transaction refuses a required field with nothing to inherit, in its own words",
    missing_tx == nil and missing_err ~= nil,
    missing_err and missing_err.message)

  PlanTransaction.hold({ plan_values = { boss_plan = "Held rule from a refused action." } })
  local held_tx, held_err = PlanTransaction.prepare("play_hand", { plan = { boss_plan = " \t " } })
  check("a blank required field is not answered by a held write either",
    held_tx == nil and held_err ~= nil,
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
  local PlanGate = require("core.gate")
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
    blank_tx == nil and blank_err ~= nil,
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
  check("throw path keeps one explicit admission result and records failure privately",
    #b.results == 1 and b.results[1].ok == true
      and b.results[1].reason_code == "ACTION_ACCEPTED"
      and b.results[1].message == nil
      and G.NEURO.last_failed_action == "reroll_shop",
    tostring(#b.results) .. "/" .. tostring(b.results[1] and b.results[1].ok)
      .. "/" .. tostring(b.results[1] and b.results[1].reason_code))
  local told = false
  for _, text in ipairs(b.contexts) do
    if tostring(text):find("(reroll the shop)", 1, true) then told = true end
  end
  check("and the failure after admission is not sent to her at all",
    not told and #b.contexts == 0, table.concat(b.contexts, " || "))
  check("throw path commits no plan", G.NEURO.plan == nil)
end

do
  base("SHOP", { reroll_shop = true })
  local Receipt = require("core.action_result")
  local Execute = require("core.execute")
  local function admit(id, data, tx, probe)
    Execute.admit({ id = id, name = "reroll_shop", data = data, tx = tx, bridge = bridge(),
      run_generation = G.NEURO.run_generation, state = "SHOP",
      exec = function()
        return Receipt.create({ id = id, name = "reroll_shop", run_generation = G.NEURO.run_generation,
          started_at = clock, deadline = clock + 5, probe = probe })
      end }, false)
  end
  local data = { plan = { money_plan = "Spend once only after the reroll is observed." } }
  local applied = false
  admit("plan-receipt", data, assert(PlanTransaction.prepare("reroll_shop", data)),
    function() return applied and "applied" or "pending" end)
  Execute.step(clock + 1)
  check("receipt plan remains uncommitted while execution is pending", G.NEURO.plan == nil)
  applied = true
  Execute.step(clock + 2)
  check("receipt plan commits only after applied", G.NEURO.plan and G.NEURO.plan.money == data.plan.money_plan)

  base("SHOP", { reroll_shop = true, record_plan = true })
  data = { plan = { money_plan = "The action's own plan." } }
  local verified = false
  admit("pending-plan-receipt", data, assert(PlanTransaction.prepare("reroll_shop", data)),
    function() return verified and "applied" or "pending" end)
  local b = bridge()
  send("record_plan", "newer-plan", { money_plan = "A newer plan." }, b)
  check("a plan write during a pending action is told to wait (success=false)",
    b.results[1] and b.results[1].ok == false and b.results[1].reason_code == "TRANSITION_PENDING",
    b.results[1] and tostring(b.results[1].reason_code))
  verified = true
  Execute.step(clock + 1)
  check("so the pending action's plan commits in order", G.NEURO.plan and G.NEURO.plan.money == data.plan.money_plan)
end

do
  base("SHOP", { reroll_shop = true })
  G.FUNCS.reroll_shop = function() end
  local b = bridge()
  G.NEURO.force_window = nil
  send("reroll_shop", "late", { plan = { money_plan = "Spend once, then hold." } }, b)
  check("a late action outside any force is judged on its merits: one result, never a stale refusal",
    #b.results == 1 and b.results[1].reason_code ~= "STALE_GENERATION",
    b.results[1] and tostring(b.results[1].reason_code))
end

do
  base("BLIND_SELECT", { record_plan = true })
  G.NEURO.plan = { boss = "Old boss rule.", boss_scope = "kept" }
  local b = bridge()
  send("record_plan", "rp-boss-and-hand", { hand_plan = "Play pairs.", boss_plan = "Flush this boss." }, b)
  require("core.execute").step(clock)
  local r = b.results[1]
  check("record_plan with boss_plan beside a real field applies",
    r and r.ok == true,
    r and tostring(r.message))
  check("the hand plan is saved and the boss rule is untouched",
    G.NEURO.plan and G.NEURO.plan.hand == "Play pairs." and G.NEURO.plan.boss == "Old boss rule.")

  b = bridge()
  local before = G.NEURO.plan_revision
  send("record_plan", "rp-boss-only", { plan = { boss_plan = "Flush this boss." } }, b)
  r = b.results[1]
  check("record_plan with only boss_plan is refused, not a silent success",
    r and r.ok == false and G.NEURO.plan_revision == before, r and tostring(r.message))

  b = bridge()
  send("record_plan", "rp-empty", {}, b)
  r = b.results[1]
  check("the empty record_plan refusal names only the fields record_plan takes",
    r and r.ok == false and tostring(r.message):find("boss_plan", 1, true) == nil, r and tostring(r.message))
end

done()
