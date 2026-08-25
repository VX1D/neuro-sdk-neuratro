_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("boss-plan")
local H = require("tests.helpers")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local PlanGate = require("core.plan_gate")

local function card(sort_id)
  return {
    base = { value = 5, suit = "Spades" }, sort_id = sort_id,
    config = { center = { key = "c_base", set = "Default" } },
  }
end

local function bridge()
  return {
    results = {}, contexts = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
    end,
    send_context = function(self, message) self.contexts[#self.contexts + 1] = message end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

local function base(opts)
  opts = opts or {}
  clock = clock + 10
  _G.G = {
    STATE = 1,
    STATES = { SELECTING_HAND = 1 },
    hand = { cards = { card(1), card(2) }, highlighted = {} },
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
      get_poker_hand_info = function() return "Pair" end,
    },
  }
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  require("core.force_state").arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, 1)
  require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand" })
end

local function send(name, id, data, b)
  Dispatcher.handle_message({
    command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = name, data = data },
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
  check("the refusal says which field was written empty", b.results[1]
    and tostring(b.results[1].message) == "Provide plan.boss_plan with this action: an empty value is not a plan.",
    b.results[1] and b.results[1].message)
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
  for _, name in ipairs({ "buy_from_shop", "sell_card", "use_card", "reroll_shop", "toggle_shop" }) do
    check(name .. " no longer advertises plan.boss_plan", plan_props(name).boss_plan == nil)
  end
  local set_plan = Registry.get("set_plan")
  check("set_plan no longer advertises boss_plan", set_plan.schema.properties.boss_plan == nil)
  check("set_plan description no longer mentions boss_plan",
    set_plan.description:find("boss_plan", 1, true) == nil, set_plan.description)
  for _, name in ipairs({ "play_hand", "discard_hand" }) do
    local props = plan_props(name)
    check(name .. " still advertises plan.boss_plan",
      props.boss_plan ~= nil and props.boss_plan.type == "string", props.boss_plan)
  end
end

do
  base({ blind = { key = "bl_small", name = "Small Blind", boss = false } })
  local b = bridge()
  send("discard_hand", "d9", { indices = { 1 }, plan = { boss_plan = "Grind Pairs anyway." } }, b)
  check("boss_plan supplied on a non-boss blind still succeeds",
    b.results[1] and b.results[1].ok == true, b.results[1])
  check("boss_plan supplied on a non-boss blind is not committed",
    not (G.NEURO.plan and G.NEURO.plan.boss), G.NEURO.plan and G.NEURO.plan.boss)
end

do
  local ForceSelectingHand = require("force.force_selecting_hand")
  local HINT = "State the rule this boss imposes on you in plan.boss_plan"
  local RID = require("tests.helpers").RID
  local VALN = require("tests.helpers").VALN
  local function hand_card(v, suit)
    local id = RID[v]
    return {
      base = { value = VALN[v] or v, suit = suit },
      config = { center = { key = "c_base", set = "Default" } },
      get_id = function() return id end,
      is_suit = function(_, s) return s == suit end,
    }
  end
  local function boss_state()
    _G.G = {
      STATES = { BLIND_SELECT = 1, SELECTING_HAND = 2 },
      STATE = 2,
      hand = {
        cards = { hand_card("3", "Spades"), hand_card("7", "Clubs"), hand_card("9", "Hearts") },
        config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {},
      },
      GAME = {
        chips = 0,
        round = 1,
        round_resets = { ante = 1 },
        current_round = { hands_left = 4, discards_left = 3 },
        blind = { chips = 1000, boss = true, name = "The Flint", debuff = {},
          config = { blind = { key = "bl_flint" } } },
        hands = {},
      },
      FUNCS = { get_poker_hand_info = function() return nil, nil, {} end },
      NEURO = { once_serials = {}, state_enter_serial = 1 },
    }
  end

  boss_state()
  local f1 = ForceSelectingHand.build()
  local q1 = f1 and ((f1.query or "") .. H.drain_hints())
  check("boss_plan hint appears while no plan is committed",
    q1 and q1:find(HINT, 1, true) ~= nil, q1)

  boss_state()
  G.NEURO.plan = { boss = "Grind Pairs, hold discards for the back half.",
    boss_scope = PlanGate.current_boss_scope() }
  local f2 = ForceSelectingHand.build()
  local q2 = f2 and ((f2.query or "") .. H.drain_hints())
  check("boss_plan hint is suppressed once the plan is current",
    q2 and q2:find(HINT, 1, true) == nil, q2)

  boss_state()
  G.NEURO.plan = { boss = "Grind Pairs against The Flint.", boss_scope = "0|bl_flint" }
  local f3 = ForceSelectingHand.build()
  local q3 = f3 and ((f3.query or "") .. H.drain_hints())
  check("boss_plan hint returns when the committed plan's scope is stale",
    q3 and q3:find(HINT, 1, true) ~= nil, q3)

  local function reforce()
    local f = ForceSelectingHand.build()
    return (f and ((f.query or "") .. H.drain_hints())) or ""
  end
  boss_state()
  check("boss_plan hint is taught once in the round", reforce():find(HINT, 1, true) ~= nil)
  G.NEURO.state_enter_serial = G.NEURO.state_enter_serial + 1
  check("boss_plan requirement repeats in each self-contained force until satisfied",
    reforce():find(HINT, 1, true) ~= nil)
  G.GAME.round = G.GAME.round + 1
  check("boss_plan hint returns in the next round", reforce():find(HINT, 1, true) ~= nil)
end

do
  local PlanHandlers = require("handlers.plan_handlers")
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2, SELECTING_HAND = 3 },
    GAME = { blind_on_deck = "Boss", dollars = 10, current_round = {}, starting_params = {},
      round_resets = { ante = 3,
        blind_states = { Small = "Defeated", Big = "Defeated", Boss = "Select" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_head" } } },
    NEURO = { once_serials = {}, plan = nil }, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local scope_before = PlanGate.current_boss_scope()
  local commit = PlanHandlers.handle_set_plan({ boss_plan = "Hearts score 0, do not build on Hearts" })
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
    STATE = 2, STATES = { BLIND_SELECT = 2, SELECTING_HAND = 3 },
    GAME = { blind_on_deck = "Small", dollars = 10, current_round = {}, starting_params = {},
      round_resets = { ante = 3,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_head" } } },
    NEURO = { once_serials = {}, plan = nil }, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local commit = PlanHandlers.handle_set_plan({ boss_plan = "should not stick" })
  if type(commit) == "function" then commit() end
  check("selecting a non-boss blind does not write a boss rule",
    not (G.NEURO.plan and G.NEURO.plan.boss), G.NEURO.plan and tostring(G.NEURO.plan.boss))
end

done()
