_G.NEURO_TEST = true
_G.G = { NEURO = {}, GAME = {
  blind_on_deck = "Small",
  round_resets = {
    ante = 3,
    blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
    blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
  },
} }

local Plan = require("handlers.plan_handlers")
local Actions = require("core.actions")
local FactHints = require("facts.fact_hints")

local check, done = require("tests.helpers").harness("self-plan")

do
  local fn, err = Plan.handle_set_plan({})
  check("both-empty rejected as PRECONDITION_FAILED, not SCHEMA_INVALID",
    fn == nil and type(err) == "table" and err.reason_code == "PRECONDITION_FAILED"
      and type(err.message) == "string" and err.message ~= "",
    type(err) == "table" and tostring(err.reason_code) or type(err))

  local fn_nested, err_nested = Plan.handle_set_plan({ plan = { hand_plan = "test" } })
  check("nested plan is accepted and returns executor",
    type(fn_nested) == "function" and err_nested == nil,
    err_nested and tostring(err_nested.reason_code))
end

do
  local fn = Plan.handle_set_plan({ hand_plan = "flush\nbuild\t  x", build_plan = "  no xMult yet  ", money_plan = "  bank $25  " })
  check("returns executor", type(fn) == "function")
  fn()
  check("hand sanitized", G.NEURO.plan.hand == "flush build x", G.NEURO.plan.hand)
  check("build sanitized", G.NEURO.plan.build == "no xMult yet", G.NEURO.plan.build)
  check("money trimmed", G.NEURO.plan.money == "bank $25", G.NEURO.plan.money)
  check("ante recorded", G.NEURO.plan.ante == 3, G.NEURO.plan.ante)
end

do
  local long_build = string.rep("b", 2000)
  local fn, err = Plan.handle_set_plan({ build_plan = long_build })
  check("a long build_plan is accepted", type(fn) == "function" and err == nil, err)
  fn()
  check("a long build_plan is stored verbatim", G.NEURO.plan.build == long_build, #tostring(G.NEURO.plan.build))
  check("writing build leaves hand untouched", G.NEURO.plan.hand == "flush build x")
  check("writing build leaves money untouched", G.NEURO.plan.money == "bank $25")
end

do
  local utf8_400 = string.rep("ł", 400) -- 400 characters, 800 bytes
  local fn, err = Plan.handle_set_plan({ hand_plan = utf8_400 })
  check("a 400-character non-ASCII plan is accepted",
    type(fn) == "function" and err == nil, err)
  fn()
  check("a non-ASCII plan is stored byte-for-byte", G.NEURO.plan.hand == utf8_400)

  local ascii_5000 = string.rep("a", 5000)
  local fn_long = Plan.handle_set_plan({ hand_plan = ascii_5000 })
  check("a 5000-character ASCII plan is accepted", type(fn_long) == "function")
  if type(fn_long) == "function" then fn_long() end
  check("a 5000-character plan is stored verbatim", G.NEURO.plan.hand == ascii_5000,
    #tostring(G.NEURO.plan.hand))

  local utf8_1001 = string.rep("ł", 1001) -- 1001 characters, 2002 bytes
  local fn_u = Plan.handle_set_plan({ hand_plan = utf8_1001 })
  check("a 1001-character non-ASCII plan is accepted", type(fn_u) == "function")
  if type(fn_u) == "function" then fn_u() end
  check("a long non-ASCII plan preserves every byte",
    G.NEURO.plan.hand == utf8_1001 and #G.NEURO.plan.hand == 2002, #tostring(G.NEURO.plan.hand))
end

do
  local validate_value = require("util.schema_validate").validate_value
  local capped = { type = "string", minLength = 1, maxLength = 8 }
  check("eight multibyte characters (24 bytes) fit maxLength=8",
    validate_value(capped, "♠♥♦♣♠♥♦♣", "seed") == true)
  check("a ninth character exceeds maxLength=8",
    validate_value(capped, "♠♥♦♣♠♥♦♣♠", "seed") == false)
  check("four-byte characters count individually",
    validate_value(capped, "🃏🃏", "seed") == true)
  check("an empty string does not satisfy minLength=1",
    validate_value(capped, "", "seed") == false)
end

do
  G.NEURO.plan = {
    hand = "go flush",
    hand_scope = require("core.plan_gate").current_blind_scope(),
    build = "no xMult yet",
    build_scope = require("core.plan_gate").current_build_scope(),
    money = "bank until the upgrade appears",
    money_scope = require("core.plan_gate").current_economy_scope(),
    ante = 3,
  }
  local s = FactHints.plan_note("shop")
  check("shop note shows build read", s:find("Build focus: no xMult yet", 1, true) ~= nil, s)
  check("shop note shows current hand decision", s:find("go flush", 1, true) ~= nil, s)
  check("shop note shows economy decision", s:find("Economy decision: bank until the upgrade appears", 1, true) ~= nil, s)
  check("shop note framed as notes, not snapshot", s:find("do not treat them as a snapshot", 1, true) ~= nil, s)
end

do
  local k = FactHints.plan_note("pack")
  check("pack note shows build read", k:find("Build focus: no xMult yet", 1, true) ~= nil, k)
  check("pack note shows hand", k:find("go flush", 1, true) ~= nil, k)
  check("pack note omits economy", k:find("Economy", 1, true) == nil, k)
end

do
  local b = FactHints.plan_note("blind")
  check("blind note shows hand", b:find("go flush", 1, true) ~= nil, b)
  check("blind note shows build read", b:find("Build focus: no xMult yet", 1, true) ~= nil, b)
  check("blind note omits economy", b:find("Economy", 1, true) == nil, b)
end

do
  local h = FactHints.plan_note("hand")
  check("hand window shows the hand plan", h:find("go flush", 1, true) ~= nil, h)
  check("hand window shows build read", h:find("Build focus: no xMult yet", 1, true) ~= nil, h)
  check("hand window omits economy", h:find("Economy", 1, true) == nil, h)
  check("hand window offers no revision (set_plan is invalid in SELECTING_HAND)",
    h:find("set_plan", 1, true) == nil, h)
  check("an unrecognized window emits no plan echo", FactHints.plan_note("play") == "")
  check("blind window still shows the hand plan", FactHints.plan_note("blind"):find("go flush", 1, true) ~= nil)
end

do
  local CardUtil = require("facts.card_util")
  G.jokers = { cards = {
    { config = { center = { key = "j_a" } } },
    { config = { center = { key = "j_b" } } },
  } }
  G.NEURO.plan = {
    hand = "go",
    hand_scope = require("core.plan_gate").current_blind_scope(),
    build = "no xMult",
    build_scope = require("core.plan_gate").current_build_scope(),
    money = "bank",
    money_scope = require("core.plan_gate").current_economy_scope(),
    ante = 3,
  }
  local fresh = FactHints.plan_note("shop")
  check("build read NOT flagged stale when jokers unchanged",
    fresh:find("Your build last shop", 1, true) == nil and fresh:find("Build focus", 1, true) ~= nil, fresh)
  G.jokers.cards[3] = { config = { center = { key = "j_c" } } }
  local stale = FactHints.plan_note("shop")
  check("stale build is surfaced as prior context, not as current 'Build focus'",
    stale:find("Build focus", 1, true) == nil and stale:find("Your build last shop", 1, true) ~= nil, stale)
  local pack = FactHints.plan_note("pack")
  check("stale build surfaced read-only in pack (set_plan invalid there)",
    pack:find("Build focus", 1, true) == nil
      and pack:find("Your earlier build plan", 1, true) ~= nil
      and pack:find("set_plan", 1, true) == nil, pack)
  local hand = FactHints.plan_note("hand")
  check("stale build surfaced read-only in hand too (set_plan invalid in SELECTING_HAND)",
    hand:find("Build focus", 1, true) == nil
      and hand:find("Your earlier build plan", 1, true) ~= nil
      and hand:find("set_plan", 1, true) == nil, hand)
  check("play window emits nothing regardless of roster changes (agnostic)", FactHints.plan_note("play") == "")
  G.jokers = nil
end

do
  G.GAME.round_resets.ante = 5
  local s = FactHints.plan_note("shop")
  check("fully stale note surfaces prior build for continuity, never as current",
    s:find("Build focus", 1, true) == nil and s:find("Your build last shop", 1, true) ~= nil, s)
  G.GAME.round_resets.ante = 3
end

do
  check("set_plan in SHOP action set", Actions.get_state_action_set("SHOP").set_plan == true)
  check("set_plan in ROUND_EVAL action set", Actions.get_state_action_set("ROUND_EVAL").set_plan == true)
  check("set_plan in BLIND_SELECT action set", Actions.get_state_action_set("BLIND_SELECT").set_plan == true)
end

do
  local PlanGate = require("core.plan_gate")
  G.STATES = { SHOP = 5, BLIND_SELECT = 6, ROUND_EVAL = 7 }; G.STATE = 5
  G.GAME.round_resets = G.GAME.round_resets or {}; G.GAME.round_resets.ante = 2
  G.NEURO.econ_plan_ok = nil; G.NEURO.blind_plan_ok = nil
  check("shop buy locked until economy plan written", PlanGate.buy_locked() == true)
  G.NEURO.plan = {
    money = "bank",
    money_scope = PlanGate.current_economy_scope(),
  }
  PlanGate.mark_written(false, false, true)
  check("money_plan unlocks shop buying", PlanGate.buy_locked() == false)
  check("money_plan does NOT satisfy the blind build gate", (function() G.STATE = 6; return PlanGate._test.blind_needs_plan() end)() == true)
  G.NEURO.plan.hand = "play current blind"
  G.NEURO.plan.hand_scope = PlanGate.current_blind_scope()
  PlanGate.mark_written(true, false, false)
  check("hand_plan satisfies the blind build gate", PlanGate._test.blind_needs_plan() == false)
  G.STATE = 5
  check("hand_plan alone does NOT unlock the shop", (function() G.NEURO.econ_plan_ok = nil; return PlanGate.buy_locked() end)() == true)
  G.GAME.round_resets.ante = 3
  PlanGate.begin_cycle()
  check("begin_cycle re-locks both econ and build", PlanGate.buy_locked() == true
    and (function() G.STATE = 6; return PlanGate._test.blind_needs_plan() end)() == true)
  G.NEURO.plan = {
    hand = "never",
    hand_scope = PlanGate.current_blind_scope(),
    money = "hoard",
    money_scope = PlanGate.current_economy_scope(),
    ante = 3,
  }
  PlanGate.mark_written(true, false, true)
  check("gates are content-agnostic", (function() G.STATE = 5; return PlanGate.buy_locked() end)() == false
    and (function() G.STATE = 6; return PlanGate._test.blind_needs_plan() end)() == false)
end

do
  local PlanGate = require("core.plan_gate")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  local FIELDS = { "hand", "build", "money" }
  local AGED_BEYOND_PAYLOAD = {
    buy_from_shop = { build = true },
    reroll_shop = {},
    sell_card = {},
    use_card = {},
  }
  for _, action_name in ipairs({ "buy_from_shop", "reroll_shop", "sell_card", "use_card" }) do
    G.NEURO.shop_plan_revision_required = nil
    PlanGate.mark_shop_changed(action_name)
    local marked = G.NEURO.shop_plan_revision_required or {}
    local inline = PlanGate.action_requirements("SHOP", action_name).plan
    local expected = AGED_BEYOND_PAYLOAD[action_name]
    local matches, overlaps = true, false
    for _, field in ipairs(FIELDS) do
      if (marked[field] == true) ~= (expected[field] == true) then matches = false end
      if marked[field] == true and inline[field] == true then overlaps = true end
    end
    check("shop revision of " .. action_name .. " marks only what its payload cannot carry", matches,
      "marked=" .. tostring(marked.hand) .. "/" .. tostring(marked.build) .. "/" .. tostring(marked.money)
        .. " expected=" .. tostring(expected.hand) .. "/" .. tostring(expected.build) .. "/" .. tostring(expected.money))
    check("shop revision of " .. action_name .. " never repeats its own inline requirement", not overlaps,
      "marked=" .. tostring(marked.hand) .. "/" .. tostring(marked.build) .. "/" .. tostring(marked.money)
        .. " inline=" .. tostring(inline.hand) .. "/" .. tostring(inline.build) .. "/" .. tostring(inline.money))
  end
  G.NEURO.shop_plan_revision_required = nil
end

do
  local PlanGate = require("core.plan_gate")
  local CardUtil = require("facts.card_util")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  local function joker(key) return { config = { center = { key = key } } } end
  G.jokers = { cards = { joker("j_bull") } }
  local function refresh_build()
    G.NEURO.plan.build = "keep the scaling core"
    G.NEURO.plan.build_scope = CardUtil.joker_build_signature()
  end
  G.NEURO.plan = { ante = 3 }
  refresh_build()

  G.NEURO.shop_plan_revision_required = nil
  PlanGate.mark_shop_changed("buy_from_shop")
  check("a purchase that leaves the roster alone asks for nothing at the exit",
    PlanGate.shop_needs_revision() == false
      and PlanGate.action_requirements("SHOP", "toggle_shop").plan.build == nil)

  G.jokers.cards[#G.jokers.cards + 1] = joker("j_juggler")
  check("a purchase that changes the roster asks for the build plan at the exit",
    PlanGate.shop_needs_revision() == true
      and PlanGate.action_requirements("SHOP", "toggle_shop").plan.build == true)
  check("the exit asks for the build plan alone",
    PlanGate.action_requirements("SHOP", "toggle_shop").plan.money == nil
      and PlanGate.action_requirements("SHOP", "toggle_shop").plan.hand == nil)

  refresh_build()
  PlanGate.mark_written(false, true, false)
  check("a rewritten build plan clears the exit requirement",
    PlanGate.shop_needs_revision() == false
      and PlanGate.action_requirements("SHOP", "toggle_shop").plan.build == nil)

  for _, action_name in ipairs({ "reroll_shop", "sell_card", "use_card" }) do
    G.NEURO.shop_plan_revision_required = nil
    G.jokers.cards[#G.jokers.cards + 1] = joker("j_" .. action_name)
    PlanGate.mark_shop_changed(action_name)
    check(action_name .. " restates its own aged fields and asks nothing at the exit",
      PlanGate.shop_needs_revision() == false
        and next(PlanGate.action_requirements("SHOP", "toggle_shop").plan) == nil)
  end

  G.NEURO.shop_plan_revision_required = nil
  PlanGate.mark_shop_changed("buy_from_shop")
  G.jokers.cards[#G.jokers.cards + 1] = joker("j_blueprint")
  check("a stale build requirement survives until it is rewritten",
    PlanGate.shop_needs_revision() == true)
  PlanGate.enter_shop()
  check("a fresh shop visit starts with no outstanding revision",
    PlanGate.shop_needs_revision() == false and G.NEURO.shop_plan_revision_required == nil)
  G.jokers = nil
end

do
  local PT = require("core.plan_transaction")
  _G.G = { NEURO = { run_generation = 1, plan = {} }, GAME = {} }
  PT.hold({ plan_values = { hand_plan = "held from a refusal" }, plan_scopes = {} })
  check("hold: a refused action parks its plan for the next attempt",
    G.NEURO.held_plan_write ~= nil)

  local fn = Plan.handle_set_plan({ hand_plan = "written on purpose" })
  check("hold: set_plan is accepted", type(fn) == "function")
  if type(fn) == "function" then pcall(fn) end
  check("hold: an explicit plan write releases what a refusal was holding",
    G.NEURO.held_plan_write == nil,
    G.NEURO.held_plan_write and tostring(G.NEURO.held_plan_write.values.hand_plan))

  _G.G = { NEURO = { run_generation = 1, plan = {} }, GAME = {} }
  PT.hold({ plan_values = { hand_plan = "parked hand", build_plan = "parked build" }, plan_scopes = {} })
  local fn2 = Plan.handle_set_plan({ hand_plan = "rewritten hand" })
  if type(fn2) == "function" then pcall(fn2) end
  local held = G.NEURO.held_plan_write
  check("hold: a partial write frees only the field it names",
    held ~= nil and held.values.hand_plan == nil and held.values.build_plan == "parked build",
    held and (tostring(held.values.hand_plan) .. "/" .. tostring(held.values.build_plan)) or "nil")
end

done()
