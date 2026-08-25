_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local ShopHandlers = require("handlers.shop_handlers")
local FactHints = require("facts.fact_hints")
local ActionResult = require("core.action_result")
local check, done = require("tests.helpers").harness("sell-guardrail")

local function jk(key)
  return { ability = { set = "Joker", name = key }, config = { center = { key = key, set = "Joker", loc_txt = { name = key } } },
    sell_cost = 3, sort_id = key }
end
local function tarot(key)
  return { ability = { set = "Tarot", name = key, consumeable = true }, config = { center = { key = key, set = "Tarot", loc_txt = { name = key } } },
    sell_cost = 1, sort_id = key }
end

local STATE_ID = { BLIND_SELECT = 1, SHOP = 2, BUFFOON_PACK = 3, SELECTING_HAND = 4,
  TAROT_PACK = 5, PLANET_PACK = 6, SPECTRAL_PACK = 7, STANDARD_PACK = 8, SMODS_BOOSTER_OPENED = 9 }
local function base(state, jokers, consumables)
  _G.G = {
    STATE = STATE_ID[state] or 0,
    STATES = STATE_ID,
    GAME = { round_resets = { ante = 2 }, current_round = {} },
    NEURO = { shop_visit_epoch = 1, state = state, state_enter_serial = 1 },
    jokers = { cards = jokers or {}, config = { card_limit = 5 } },
    consumeables = { cards = consumables or {}, config = { card_limit = 2 } },
    FUNCS = { sell_card = function() end },
  }
end

local function sell(area, index) return ShopHandlers.handle_sell_card({ area = area, index = index }) end
local function is_confirm(err) return ActionResult.is_error(err) and err.reason_code == "CONFIRMATION_REQUIRED" end

base("SHOP", { jk("j_a"), jk("j_b") })
local exec1, err1 = sell("jokers", 1)
check("first joker sell -> CONFIRMATION_REQUIRED", exec1 == nil and is_confirm(err1), err1 and err1.reason_code)
check("message states the exact roster consequence + how to confirm",
  err1 and err1.message:find("removes this joker's listed effect", 1, true)
    and err1.message:find("again to confirm", 1, true), err1 and err1.message)

local exec2 = sell("jokers", 1)
check("second identical joker sell returns exec (confirmed)", type(exec2) == "function", type(exec2))

base("SHOP", { jk("j_a"), jk("j_b") })
G.NEURO.last_sell_reject = "sell:1:j_a"
local _, err3 = sell("jokers", 2)
check("different joker (j_b) is independently gated", is_confirm(err3), err3 and err3.reason_code)

base("SHOP", { jk("j_a") })
G.NEURO.plan = { build = "keep Sock and Buskin for retrigger" }
local _, err4 = sell("jokers", 1)
check("message echoes build plan", err4 and err4.message:find("keep Sock and Buskin", 1, true) ~= nil, err4 and err4.message)

base("SHOP", { jk("j_a") })
G.NEURO.jokers_sold = { epoch = 1, count = 2 }
local _, err5 = sell("jokers", 1)
check("message surfaces churn count", err5 and err5.message:find("already sold 2 joker", 1, true) ~= nil, err5 and err5.message)
check("joker_churn_note surfaces churn", FactHints.joker_churn_note():find("sold 2 joker", 1, true) ~= nil, FactHints.joker_churn_note())
G.NEURO.jokers_sold = nil
check("churn note empty when nothing sold", FactHints.joker_churn_note() == "", FactHints.joker_churn_note())

base("SHOP", { jk("j_a") }, { tarot("c_t") })
local exec6 = sell("consumeables", 1)
check("consumable sell is NOT gated (returns exec)", type(exec6) == "function", type(exec6))

base("BUFFOON_PACK", { jk("j_a") })
local exec7, err7 = sell("jokers", 1)
check("joker sell inside a pack is gated", exec7 == nil and is_confirm(err7), err7 and err7.reason_code)
local exec7b = sell("jokers", 1)
check("resend inside a pack confirms the sell", type(exec7b) == "function", type(exec7b))

base("SHOP", { jk("j_a") })
G.NEURO._candidate_probe = true
local exec8 = sell("jokers", 1)
G.NEURO._candidate_probe = nil
check("offer-probe returns exec (sell_card stays offerable)", type(exec8) == "function", type(exec8))
check("offer-probe did NOT set the confirm flag (no pre-confirm)", G.NEURO.last_sell_reject == nil, G.NEURO.last_sell_reject)

base("SHOP", { jk("j_a") })
G.NEURO.last_sell_reject = "sell:1:j_a"
local exec10 = sell("jokers", 1)
check("confirmed joker sell returns exec", type(exec10) == "function", type(exec10))
if type(exec10) == "function" then
  exec10()
  check("real joker sale records churn (epoch-keyed)",
    G.NEURO.jokers_sold and G.NEURO.jokers_sold.epoch == 1 and G.NEURO.jokers_sold.count == 1,
    G.NEURO.jokers_sold and G.NEURO.jokers_sold.count)
end

base("SHOP", { jk("j_a") })
sell("jokers", 1)
check("reject sets the confirm token", G.NEURO.last_sell_reject == "sell:1:j_a", G.NEURO.last_sell_reject)
require("core.plan_gate").enter_shop()
check("shop entry clears the stale confirm token", G.NEURO.last_sell_reject == nil, G.NEURO.last_sell_reject)
local _, err11 = sell("jokers", 1)
check("same joker re-gated in a later shop (no stale auto-confirm)", is_confirm(err11), err11 and err11.reason_code)

local function tagged(tag, note, state)
  base(state or "SHOP", { jk("j_a") })
  if tag ~= nil or note ~= nil then
    G.NEURO.joker_intents = { j_a = { tag = tag, note = note } }
  end
  return sell("jokers", 1)
end

for _, tag in ipairs({ "CORE", "SCALING", "HOLD", "CHANGE" }) do
  local _, e = tagged(tag)
  check("a " .. tag .. "-tagged joker still requires confirmation", is_confirm(e), e and e.reason_code)
end

do local _, e = tagged(nil); check("untagged joker confirms with the generic lead",
  is_confirm(e) and e.message:find("removes this joker's listed effect", 1, true) ~= nil
  and e.message:find("you tagged it", 1, true) == nil, e and e.message) end

local LEADS = {
  CORE = "you tagged it CORE.",
  SCALING = "you tagged it SCALING.",
  HOLD = "you tagged it HOLD.",
  CHANGE = "you tagged it CHANGE.",
}
for tag, lead in pairs(LEADS) do
  local _, e = tagged(tag)
  check(tag .. " lead sentence is present verbatim",
    is_confirm(e) and e.message:find(lead, 1, true) ~= nil, e and e.message)
  check(tag .. " confirmation still says how to confirm",
    is_confirm(e) and e.message:find("again to confirm", 1, true) ~= nil, e and e.message)
end

do local _, e = tagged("CORE", "core xmult piece"); check("confirm message echoes the stored note",
  is_confirm(e) and e.message:find("core xmult piece", 1, true) ~= nil, e and e.message) end

do
  base("SHOP", { jk("j_a") })
  G.NEURO.joker_intents = { j_a = { cut_epoch = 1 } }
  local exec12a, err12a = sell("jokers", 1)
  check("a legacy cut_epoch entry grants no pre-approval",
    exec12a == nil and is_confirm(err12a), err12a and err12a.reason_code)
end

local _, err12b = tagged("CHANGE", nil, "BLIND_SELECT")
check("CHANGE tag does not bypass confirmation outside SHOP", is_confirm(err12b), err12b and err12b.reason_code)
local exec12b = sell("jokers", 1)
check("resend in BLIND_SELECT confirms the sell", type(exec12b) == "function", type(exec12b))

base("SHOP", { jk("j_a") })
sell("jokers", 1)
check("token is scoped to the decision window", G.NEURO.last_sell_reject == "sell:1:j_a", G.NEURO.last_sell_reject)
G.NEURO.state_enter_serial = 2
local _, err12d = sell("jokers", 1)
check("stale token does not confirm a sell in the next state", is_confirm(err12d), err12d and err12d.reason_code)

base("SHOP", { jk("j_a") })
local explicit = {
  area = "jokers", index = 1,
  plan = { build_plan = "Sell this joker and replace it.", money_plan = "Bank the proceeds." },
}
local tx, tx_err = require("core.plan_transaction").prepare("sell_card", explicit)
local exec13, err13 = ShopHandlers.handle_sell_card(explicit)
check("complete inline build+money plan still requires confirmation",
  tx ~= nil and tx_err == nil and exec13 == nil and is_confirm(err13), err13 and err13.reason_code)
check("the mandatory plan envelope did not silently waive the guard",
  G.NEURO.last_sell_reject == "sell:1:j_a", tostring(G.NEURO.last_sell_reject))
local exec13b = ShopHandlers.handle_sell_card(explicit)
check("resending the same envelope confirms the sell", type(exec13b) == "function", type(exec13b))

base("SHOP", { jk("j_a") })
local _, partial_err = ShopHandlers.handle_sell_card({
  area = "jokers", index = 1, plan = { build_plan = "Sell this joker." },
})
check("partial inline plan preserves first sell warning", is_confirm(partial_err), partial_err and partial_err.reason_code)

do
  base("SHOP", { jk("j_a"), jk("j_b") })
  check("run-wide sold counter starts unset", G.NEURO.jokers_sold_run == nil)
  sell("jokers", 1)
  local exec14a = sell("jokers", 1)
  if type(exec14a) == "function" then exec14a() end
  check("first confirmed sell sets the run-wide counter to 1", G.NEURO.jokers_sold_run == 1, G.NEURO.jokers_sold_run)

  G.NEURO.shop_visit_epoch = 2
  sell("jokers", 2)
  local exec14b = sell("jokers", 2)
  if type(exec14b) == "function" then exec14b() end
  check("a sell in a later shop visit keeps accumulating, not resetting", G.NEURO.jokers_sold_run == 2, G.NEURO.jokers_sold_run)
end

do
  local EXPECTED = {
    CORE = "you tagged it CORE.",
    SCALING = "you tagged it SCALING.",
    HOLD = "you tagged it HOLD.",
    CHANGE = "you tagged it CHANGE.",
  }
  local n = 0
  for tag, expected in pairs(EXPECTED) do
    check("TAG_SELL_LEAD." .. tag .. " is exactly the neutral definitional sentence",
      ShopHandlers.TAG_SELL_LEAD[tag] == expected, ShopHandlers.TAG_SELL_LEAD[tag])
    n = n + 1
  end
  for _ in pairs(ShopHandlers.TAG_SELL_LEAD) do n = n - 1 end
  check("TAG_SELL_LEAD has exactly 4 entries (no silent additions)", n == 0)
end

do
  local function reason(jokers, prep)
    base("SHOP", jokers)
    if prep then prep() end
    local _, e = sell("jokers", 1)
    return e and e.message
  end

  local GOLDEN = {
    { label = "S-GOLD1 untagged joker, one left",
      jokers = { jk("j_a"), jk("j_b") },
      text = "Selling j_a for $3 leaves 1 joker and removes this joker's listed effect from the roster. Send sell_card again to"
        .. " confirm, or keep the joker and act elsewhere." },
    { label = "S-GOLD2 untagged joker, none left (plural agreement)",
      jokers = { jk("j_a") },
      text = "Selling j_a for $3 leaves 0 jokers and removes this joker's listed effect from the roster. Send sell_card again to"
        .. " confirm, or keep the joker and act elsewhere." },
    { label = "S-GOLD3 tagged joker takes the lead instead of the generic sentence",
      jokers = { jk("j_a"), jk("j_b") },
      prep = function() G.NEURO.joker_intents = { j_a = { tag = "CORE" } } end,
      text = "Selling j_a for $3, leaving 1 joker: you tagged it CORE. Send sell_card again to confirm, or keep the joker and act elsewhere." },
    { label = "S-GOLD4 churn line at one prior sale this shop",
      jokers = { jk("j_a"), jk("j_b") },
      prep = function() G.NEURO.jokers_sold = { epoch = 1, count = 1 } end,
      text = "Selling j_a for $3 leaves 1 joker and removes this joker's listed effect from the roster. You have already sold 1 joker"
        .. " this shop -- you are dismantling your build. Send sell_card again to confirm, or keep"
        .. " the joker and act elsewhere." },
    { label = "S-GOLD5 churn line pluralises past one prior sale",
      jokers = { jk("j_a"), jk("j_b") },
      prep = function() G.NEURO.jokers_sold = { epoch = 1, count = 3 } end,
      text = "Selling j_a for $3 leaves 1 joker and removes this joker's listed effect from the roster. You have already sold 3 jokers"
        .. " this shop -- you are dismantling your build. Send sell_card again to confirm, or keep"
        .. " the joker and act elsewhere." },
  }
  for _, g in ipairs(GOLDEN) do
    local got = reason(g.jokers, g.prep)
    check(g.label .. " is exactly the golden string", got == g.text, tostring(got))
  end
end

do
  base("SHOP", { jk("j_a") })
  local _, arm_err = sell("jokers", 1)
  check("arming records the decision it was armed in",
    is_confirm(arm_err) and G.NEURO.last_sell_review_serial == 0, tostring(G.NEURO.last_sell_review_serial))
  check("the armed sell shows in the force state while it stands",
    ShopHandlers.pending_sell_card_name() ~= nil, tostring(ShopHandlers.pending_sell_card_name()))

  G.NEURO.decision_serial = 1
  check("an action resolved in between drops the armed sell from the force state",
    ShopHandlers.pending_sell_card_name() == nil, tostring(ShopHandlers.pending_sell_card_name()))
  local exec_after, err_after = sell("jokers", 1)
  check("a sell resent after an action in between is re-gated, not committed",
    exec_after == nil and is_confirm(err_after), err_after and err_after.reason_code)
  check("the re-gate re-arms on the current decision",
    G.NEURO.last_sell_reject == "sell:1:j_a" and G.NEURO.last_sell_review_serial == 1,
    tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))

  local exec_now = sell("jokers", 1)
  check("an immediate resend inside the same decision still confirms",
    type(exec_now) == "function", type(exec_now))
  check("confirming consumes the whole agreement",
    G.NEURO.last_sell_reject == nil and G.NEURO.last_sell_review_serial == nil,
    tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))
end

do
  base("SHOP", { jk("j_a") })
  sell("jokers", 1)
  require("core.neuro_lifecycle").clear_pending_confirm()
  check("clearing a pending confirmation drops the recorded decision with the token",
    G.NEURO.last_sell_reject == nil and G.NEURO.last_sell_review_serial == nil,
    tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))

  local registered = false
  for _, key in ipairs(require("core.lifecycle_registry").describe().run.fields) do
    if key == "last_sell_review_serial" then registered = true end
  end
  check("the recorded decision is run-scoped, like the token itself", registered)
end

do
  for _, state in ipairs({ "BUFFOON_PACK", "TAROT_PACK", "PLANET_PACK", "SPECTRAL_PACK",
    "STANDARD_PACK", "SMODS_BOOSTER_OPENED" }) do
    base(state, { jk("j_a"), jk("j_b") })
    local exec, err = sell("jokers", 1)
    check(state .. ": first joker sell is gated", exec == nil and is_confirm(err), err and err.reason_code)
    check(state .. ": the gate arms both axes of the token",
      G.NEURO.last_sell_reject == "sell:1:j_a" and G.NEURO.last_sell_review_serial == 0,
      tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))
    check(state .. ": the armed sell shows in the force state",
      ShopHandlers.pending_sell_card_name() == "j_a", tostring(ShopHandlers.pending_sell_card_name()))
    check(state .. ": identical resend confirms", type(sell("jokers", 1)) == "function")
  end

  base("BUFFOON_PACK", { jk("j_a") })
  G.NEURO._candidate_probe = true
  local probe = sell("jokers", 1)
  G.NEURO._candidate_probe = nil
  check("pack offer-probe still returns exec and arms nothing",
    type(probe) == "function" and G.NEURO.last_sell_reject == nil, G.NEURO.last_sell_reject)

  base("BUFFOON_PACK", { jk("j_a") }, { tarot("c_t") })
  check("a consumable sell inside a pack stays ungated",
    type(sell("consumeables", 1)) == "function")

  base("BUFFOON_PACK", { jk("j_a") })
  sell("jokers", 1)
  G.NEURO.decision_serial = 1
  local _, lapsed = sell("jokers", 1)
  check("a pack agreement lapses with the decision it was armed in",
    is_confirm(lapsed), lapsed and lapsed.reason_code)
end

do
  require("core.dispatcher")
  local Actions = require("core.actions")
  local Legality = require("facts.boss.legality")
  local function offered()
    for _, n in ipairs(Actions.get_valid_actions_for_state(require("core.state").get_state_name())) do
      if n == "sell_card" then return true end
    end
    return false
  end

  base("SELECTING_HAND", { jk("j_a") })
  G.GAME.blind = { key = "bl_psychic", name = "The Psychic", debuff = { h_size_ge = 5 } }
  check("mid-round selling is blocked", Legality.sell_blocked_now() == true)
  check("a sell that can only be refused is not offered", Actions.is_action_valid("sell_card") == false)
  check("sell_card leaves the SELECTING_HAND action list", offered() == false)

  base("SELECTING_HAND", { jk("j_a") })
  G.GAME.blind = { key = "bl_final_leaf", name = "Verdant Leaf", debuff = {} }
  check("Verdant Leaf reopens selling inside the round", Legality.sell_blocked_now() == false)
  check("under Verdant Leaf sell_card stays offered", Actions.is_action_valid("sell_card") == true)
  check("under Verdant Leaf sell_card stays in the action list", offered() == true)

  base("BUFFOON_PACK", { jk("j_a") })
  check("a pack keeps sell_card offered", Actions.is_action_valid("sell_card") == true and offered() == true)

  base("SHOP", { jk("j_a") })
  check("the shop keeps sell_card offered", Actions.is_action_valid("sell_card") == true and offered() == true)
end

done()
