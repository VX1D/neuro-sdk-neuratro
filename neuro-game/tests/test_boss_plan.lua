local ES = require("tests.engine_cards").states()
_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("boss-plan")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local json = require("util.neuro_json")
local PlanGate = require("core.gate")

local card = require("tests.fake_cards").five_of_spades

local function bridge()
  return require("tests.helpers").fake_bridge({ context = "contexts", context_ack = false, cooldown = true })
end

local function base(opts)
  opts = opts or {}
  clock = clock + 10
  _G.G = {
    STATE = ES.SELECTING_HAND,
    STATES = ES,
    hand = require("tests.helpers").card_area({ cards = { card(1), card(2) }, highlighted = {} }),
    GAME = {
      chips = 0,
      round = 1,
      round_resets = { ante = opts.ante or 1 },
      current_round = { hands_left = 4, discards_left = 3 },
      blind = opts.blind or { key = "bl_flint", name = "The Flint", boss = true },
    },
    NEURO = {
      run_generation = 7, state_enter_serial = 11, once_serials = {},
    },
    FUNCS = {
      discard_cards_from_highlighted = function()
        local selected = {}
        for _, item in ipairs(G.hand.highlighted) do selected[item] = true end
        local kept = {}
        for _, item in ipairs(G.hand.cards) do if not selected[item] then kept[#kept + 1] = item end end
        G.hand.cards, G.hand.highlighted = kept, {}
        G.GAME.current_round.discards_left = G.GAME.current_round.discards_left - 1
      end,
      play_cards_from_highlighted = function()
        local selected = {}
        for _, item in ipairs(G.hand.highlighted) do selected[item] = true end
        local kept = {}
        for _, item in ipairs(G.hand.cards) do if not selected[item] then kept[#kept + 1] = item end end
        G.hand.cards, G.hand.highlighted = kept, {}
        G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
      end,
      get_poker_hand_info = require("tests.helpers").poker_hand_info("Pair"),
    },
  }
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand" })
end

local function send(name, id, data, b)
  local payload = type(data) == "table" and (next(data) and json.encode(data) or "{}") or data
  Dispatcher.handle_message({
    command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = name, data = payload },
  }, b)
end

do
  base()
  local b = bridge()
  send("discard_hand", "d1", { indices = { 1 } }, b)
  check("missing boss_plan is a negative precondition", b.results[1] and b.results[1].ok == false
    and b.results[1].reason_code == "PRECONDITION_FAILED", b.results[1] and b.results[1].reason_code)
  check("missing boss_plan does not mutate the game/plan", G.NEURO.plan == nil)
end

do
  base()
  local b = bridge()
  send("discard_hand", "d1b", { indices = { 1 }, plan = { boss_plan = "   " } }, b)
  check("a blank boss_plan where one is required is refused", b.results[1] and b.results[1].ok == false
    and b.results[1].reason_code == "PRECONDITION_FAILED", b.results[1] and b.results[1].reason_code)
  check("a blank boss_plan mutates neither the game nor the plan", G.NEURO.plan == nil
    and #G.hand.cards == 2, G.NEURO.plan)
end

do
  base()
  local b = bridge()
  send("discard_hand", "d2", { indices = { 1 }, plan = { boss_plan = "Chip through with pairs; save discards for the back half." } }, b)
  check("first discard with boss_plan succeeds", b.results[1] and b.results[1].ok == true, b.results[1])
  check("boss_plan is committed to G.NEURO.plan", G.NEURO.plan and G.NEURO.plan.boss
    == "Chip through with pairs; save discards for the back half.", G.NEURO.plan and G.NEURO.plan.boss)
  check("boss scope is current after commit", PlanGate.boss_plan_is_current(G.NEURO.plan))
end

do
  base()
  local b = bridge()
  send("discard_hand", "d3", { indices = { 1 }, plan = { boss_plan = "Grind Pairs, hold discards for a Close hand." } }, b)
  check("first action in round commits boss_plan", b.results[1] and b.results[1].ok == true)
  local scope_after_first = G.NEURO.plan.boss_scope
  send("discard_hand", "d4", { indices = { 1 } }, b)
  check("second action without boss_plan inherits the standing plan",
    b.results[2] and b.results[2].ok == true, b.results[2])
  check("inherited boss scope is unchanged", G.NEURO.plan.boss_scope == scope_after_first)
end

do
  base({ ante = 1 })
  local b = bridge()
  send("discard_hand", "d5", { indices = { 1 }, plan = { boss_plan = "Grind Pairs against The Flint." } }, b)
  check("ante 1 boss plan commits", b.results[1] and b.results[1].ok == true)

  base({ ante = 2 })
  local b2 = bridge()
  send("discard_hand", "d6", { indices = { 1 } }, b2)
  check("new boss round (ante changed) re-requires boss_plan without a fresh statement",
    b2.results[1] and b2.results[1].ok == false and b2.results[1].reason_code == "PRECONDITION_FAILED",
    b2.results[1] and b2.results[1].reason_code)
end

do
  base({ blind = { key = "bl_small", name = "Small Blind", boss = false } })
  local b = bridge()
  send("discard_hand", "d7", { indices = { 1 } }, b)
  check("non-boss blind never requires boss_plan", b.results[1] and b.results[1].ok == true, b.results[1])
end

do
  local Registry = require("core.action_registry")
  require("core.actions")
  local function plan_props(name)
    local action = Registry.get(name)
    local plan = action and action.schema and action.schema.properties and action.schema.properties.plan
    return plan and plan.properties or {}
  end
  check("select_blind advertises plan.boss_plan, because that is where the rule is stated",
    plan_props("select_blind").boss_plan ~= nil)
  for _, name in ipairs({ "buy_from_shop", "sell_card", "use_consumable", "reroll_shop", "leave_shop" }) do
    check(name .. " no longer advertises plan.boss_plan", plan_props(name).boss_plan == nil)
  end
  local record_plan = Registry.get("record_plan")
  check("record_plan no longer advertises boss_plan", record_plan.schema.properties.boss_plan == nil)
  for _, name in ipairs({ "play_hand", "discard_hand" }) do
    local props = plan_props(name)
    check(name .. " still advertises plan.boss_plan",
      props.boss_plan ~= nil and props.boss_plan.type == "string", props.boss_plan)
  end
end

do
  local function small_blind(ante, boss_key)
    base({ ante = ante, blind = { key = "bl_small", name = "Small Blind", boss = false } })
    G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = boss_key }
    G.GAME.round_resets.blind_states = { Small = "Current", Big = "Upcoming", Boss = "Upcoming" }
  end
  small_blind(1, "bl_flint")
  local b = bridge()
  send("discard_hand", "d9", { indices = { 1 }, plan = { boss_plan = "Grind Pairs anyway." } }, b)
  check("boss_plan supplied on a non-boss blind still succeeds",
    b.results[1] and b.results[1].ok == true, b.results[1])
  check("boss_plan supplied with a discard on a non-boss blind is not saved",
    not (G.NEURO.plan and G.NEURO.plan.boss), G.NEURO.plan and tostring(G.NEURO.plan.boss))

  local plan = { boss = "Grind Pairs anyway.", boss_scope = "1|bl_flint" }
  base({ ante = 1 })
  G.NEURO.plan = plan
  check("the plan written ahead is current once that boss is being played",
    PlanGate.boss_plan_is_current(G.NEURO.plan))
  local b2 = bridge()
  send("discard_hand", "d10", { indices = { 1 } }, b2)
  check("so the boss requirement is met by the plan written ahead",
    b2.results[1] and b2.results[1].ok == true, b2.results[1])

  base({ ante = 1, blind = { key = "bl_hook", name = "The Hook", boss = true } })
  G.NEURO.plan = plan
  check("a different boss (rerolled) does not inherit it", not PlanGate.boss_plan_is_current(G.NEURO.plan))
end

do
  _G.G = {
    STATE = ES.BLIND_SELECT, STATES = ES,
    GAME = { blind_on_deck = "Boss", dollars = 10, current_round = {}, starting_params = {},
      round_resets = { ante = 3,
        blind_states = { Small = "Defeated", Big = "Defeated", Boss = "Select" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_head" } } },
    NEURO = { once_serials = {}, plan = nil }, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local scope_before = PlanGate.current_boss_scope()
  local tx = require("core.plan_transaction").prepare("select_blind", { blind = "boss", plan = {
    boss_plan = "Hearts score 0, do not build on Hearts",
    hand_plan = "Play the strongest visible hand.", build_plan = "Keep the current build.",
  } })
  local commit = tx and tx.plan_commit
  check("a boss rule stated at blind select prepares", type(commit) == "function")

  G.GAME.round_resets.blind_states.Boss = "Current"
  if type(commit) == "function" then commit() end

  check("it survives the action that consumed the blind it was written for",
    G.NEURO.plan and G.NEURO.plan.boss == "Hearts score 0, do not build on Hearts",
    G.NEURO.plan and tostring(G.NEURO.plan.boss))
  check("stamped with the boss it was written about, so the round reads it as current",
    G.NEURO.plan and G.NEURO.plan.boss_scope == scope_before,
    tostring(G.NEURO.plan and G.NEURO.plan.boss_scope) .. " vs " .. tostring(scope_before))
end

do
  local PlanHandlers = require("handlers.plan_handlers")
  _G.G = {
    STATE = ES.BLIND_SELECT, STATES = ES,
    GAME = { blind_on_deck = "Small", dollars = 10, current_round = {}, starting_params = {},
      round_resets = { ante = 3,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_head" } } },
    NEURO = { once_serials = {}, plan = nil }, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local commit = PlanHandlers.handle_record_plan({ boss_plan = "should not stick" })
  if type(commit) == "function" then commit() end
  check("selecting a non-boss blind does not write a boss rule",
    not (G.NEURO.plan and G.NEURO.plan.boss), G.NEURO.plan and tostring(G.NEURO.plan.boss))
end

done()
