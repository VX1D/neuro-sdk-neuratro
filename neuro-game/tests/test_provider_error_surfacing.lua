_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("provider-error-surfacing")

do
  local Registry = require("core.action_registry")
  local Metrics = require("util.metrics")

  local function counter()
    return Metrics._counters["action_registry_provider_error"] or 0
  end

  Registry.register({ name = "probe_action_avail", description = "d", schema = { type = "object" } })
  Registry.bind_availability("probe_action_avail", function() error("boom-throw") end)
  local before = counter()
  local avail = Registry.available("probe_action_avail")
  check("a throwing availability predicate still reads as unavailable, not as a crash",
    avail == false, tostring(avail))
  check("the throw increments the provider-error metric",
    counter() == before + 1, counter() .. " vs " .. (before + 1))

  Registry.available("probe_action_avail")
  check("a repeated throw keeps incrementing the metric (only the print is one-shot)",
    counter() == before + 2, counter() .. " vs " .. (before + 2))

  Registry.register({ name = "probe_action_cand", description = "d", schema = { type = "object" } })
  Registry.bind_candidates("probe_action_cand", function() error("boom-candidates") end)
  local before_cand = counter()
  local candidates = Registry.candidates("probe_action_cand")
  check("a throwing candidate provider returns an empty list, not a crash",
    type(candidates) == "table" and #candidates == 0, type(candidates))
  check("the candidate throw also increments the provider-error metric",
    counter() == before_cand + 1, counter() .. " vs " .. (before_cand + 1))
end

do
  local TD = require("tests.test_deadlock")
  local Router = require("force.force_router")
  local Metrics = require("util.metrics")
  local Registry = require("core.action_registry")
  local CardUtil = require("facts.card_util")

  local function base_game()
    return {
      dollars = 0,
      bankrupt_at = 0,
      round = 7,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = {
        ante = 3,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" },
        boss_rerolled = false,
      },
      blind = { chips = 300, mult = 1 },
      blind_on_deck = "Boss",
      chips = 0,
      used_vouchers = {},
      stake = 1,
      pack_choices = 1,
    }
  end

  local function make_card(overrides)
    local c = { cost = 0, sell_cost = 1, sort_id = 9001,
      ability = { set = "Default", name = "Mock" },
      config = { center = {} }, base = { value = "10", suit = "Hearts" } }
    if overrides then for k, v in pairs(overrides) do c[k] = v end end
    return c
  end

  local function untagged_joker()
    return { cost = 4, sell_cost = 2, sort_id = 9002,
      ability = { set = "Joker", name = "Untagged Joker" },
      config = { center = { key = "j_untagged", name = "Untagged Joker", set = "Joker" } } }
  end

  _G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }
  G.NEURO = { dispatcher = require("core.dispatcher"), actions = require("core.actions"),
    persona = "neuro", reserved_dollars = 0, _reservation_epoch = 0, shop_reroll_count = 0,
    _decision_windows = {}, once_serials = {}, decision_serial = 1, state_enter_serial = 1,
    run_generation = 1 }
  require("core.transition_guard").reset()

  TD.apply_mock({
    GAME = base_game(),
    shop = {},
    hand = { cards = {}, highlighted = {} },
    jokers = { cards = { untagged_joker() }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { make_card({ cost = 5 }) } },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
    OVERLAY_MENU = nil,
    NEURO_PERSONA = "neuro",
    NEURO_SHOP_REROLL_COUNT = 0,
    NEURO_RESERVED_DOLLARS = 0,
  })
  G.STATES = { SHOP = 1 }
  G.STATE = 1

  check("fixture: the untagged joker really is untagged",
    CardUtil.untagged_joker_count() == 1, CardUtil.untagged_joker_count())
  Registry.bind_availability("sell_card", function() return false end)
  check("fixture: with sell_card neutralised, leave_shop is the only other SHOP action valid at all",
    require("core.actions").is_action_valid("leave_shop") == false
      and require("core.actions").is_action_valid("buy_from_shop") == false
      and require("core.actions").is_action_valid("use_consumable") == false
      and require("core.actions").is_action_valid("reroll_shop") == false
      and require("core.actions").is_action_valid("sell_card") == false
      and require("core.actions").is_action_valid("record_joker_roles") == true)

  local real_untagged_joker_count = CardUtil.untagged_joker_count
  local calls = 0
  CardUtil.untagged_joker_count = function(...)
    calls = calls + 1
    if calls >= 3 then error("boom-tag-count-throw") end
    return real_untagged_joker_count(...)
  end

  local before = Metrics._counters["force_tag_count_error"] or 0
  local ok_force, force = pcall(Router.get_force_for_state, "SHOP")
  CardUtil.untagged_joker_count = real_untagged_joker_count

  check("fixture: force_router.lua's own call was really the one that threw (3rd of exactly 3)",
    calls == 3, calls)
  check("get_force_for_state does not crash when the tag-count observation throws",
    ok_force, tostring(force))
  check("the throw is reported through the metric, not swallowed",
    (Metrics._counters["force_tag_count_error"] or 0) == before + 1,
    tostring(Metrics._counters["force_tag_count_error"]))
  check("a shop whose only way out is tagging still gets a force, not nil",
    type(force) == "table" and type(force.actions) == "table", tostring(force))
  if type(force) == "table" and type(force.actions) == "table" then
    local has_intents = false
    for _, name in ipairs(force.actions) do
      if name == "record_joker_roles" then has_intents = true end
    end
    check("record_joker_roles survives as the shop's only progressing action",
      has_intents, table.concat(force.actions, ","))
  end
end

done()
