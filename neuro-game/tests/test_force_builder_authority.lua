_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = {} }

-- One authority decides whether a state asks anything: force_router.lua:248, which runs after
-- TransitionGuard pruning, after absorb_fallback and after the settling failsafe. A state builder
-- that answers the same question from a narrower predicate shadows it and drops every action the
-- builder's predicate does not know about.

local check, done = require("tests.helpers").harness("force-builder-authority")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Builder = require("force.force_selecting_hand")
local ActionPolicy = require("core.action_policy")
local TD = require("tests.test_deadlock")

G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local function scenario(desc)
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SELECTING_HAND" and sc.desc == desc then return sc end
  end
  error("test_force_builder_authority: scenario not found: " .. desc)
end

local EMPTY_HAND_CONSUMABLE = scenario("Has consumable but hand is empty")
local DEALT = scenario("Normal: 5 cards, 4 hands, 3 discards")

local function stage(sc, mutate)
  local mock = sc.mock()
  if mutate then mutate(mock) end
  G.OVERLAY_MENU = nil
  G.NEURO.consumed_actions = nil
  TD.apply_mock(mock)
  G.NEURO.state_entry_hints = nil
  G.NEURO.blind_info_sig = nil
  G.NEURO.blind_info_seen = nil
  require("core.transition_guard").reset()
end

local function offered(force)
  local set = {}
  for _, name in ipairs(force and force.actions or {}) do set[name] = true end
  return set
end

local function has_progress(names)
  for _, name in ipairs(names or {}) do
    if not ActionPolicy.NON_PROGRESS[name] then return true end
  end
  return false
end

local function progression_overlay(mock)
  mock.OVERLAY_MENU = {
    get_UIE_by_ID = function(_, id) return id == "from_game_over" and {} or nil end,
  }
end

-- A: force_router.lua:99 deliberately stands down for a progression overlay, so the state handler
-- is the only path that can carry exit_overlay_menu there.
do
  stage(EMPTY_HAND_CONSUMABLE, function(mock)
    mock.consumeables = { cards = {}, config = { card_limit = 2 } }
    mock.jokers = { cards = {}, config = { card_limit = 5 } }
    progression_overlay(mock)
  end)
  check("the overlay is a progression overlay, so the router will not carry the exit",
    require("core.state_kinds").is_progression_overlay() == true)
  check("exit_overlay_menu is the one action the registry accepts here",
    Actions.is_action_valid("exit_overlay_menu") == true
      and Actions.is_action_valid("play_hand") == false
      and Actions.is_action_valid("discard_hand") == false)
  local force = Dispatcher.get_force_for_state("SELECTING_HAND")
  check("the escape hatch is offered", offered(force)["exit_overlay_menu"] == true,
    force and table.concat(force.actions, ",") or "NO FORCE")
end

-- B: dump game.lua:2678-2685 -- an empty hand leaves SELECTING_HAND only while G.deck still holds
-- cards, so empty hand plus empty deck is a board the engine never exits on its own. A Planet needs
-- no hand target, so use_card is a legal move out of it.
do
  stage(EMPTY_HAND_CONSUMABLE, function(mock) mock.deck = { cards = {} } end)
  check("the registry accepts use_card on the empty hand",
    Actions.is_action_valid("use_card") == true)
  local force = Dispatcher.get_force_for_state("SELECTING_HAND")
  check("the model is asked for the one move that leaves the state",
    offered(force)["use_card"] == true,
    force and table.concat(force.actions, ",") or "NO FORCE")
end

do
  local MATRIX = {
    { label = "dealt, hands and discards", base = DEALT },
    { label = "dealt, banner blocks play", base = DEALT,
      mutate = function(mock) mock.GAME.blind.block_play = true end },
    { label = "dealt, no hands and no discards", base = DEALT,
      mutate = function(mock)
        mock.GAME.current_round.hands_left = 0
        mock.GAME.current_round.discards_left = 0
      end },
    { label = "undealt, hands and discards", base = EMPTY_HAND_CONSUMABLE },
    { label = "undealt, play_hand held by a commit", base = EMPTY_HAND_CONSUMABLE,
      mutate = function(mock) mock.NEURO_CONSUMED_ACTIONS = { play_hand = true } end },
    { label = "undealt, nothing owned", base = EMPTY_HAND_CONSUMABLE,
      mutate = function(mock)
        mock.consumeables = { cards = {}, config = { card_limit = 2 } }
        mock.jokers = { cards = {}, config = { card_limit = 5 } }
      end },
    { label = "undealt, progression overlay", base = EMPTY_HAND_CONSUMABLE,
      mutate = progression_overlay },
  }
  local silent, asked, seen_valid, seen_empty = {}, 0, false, false
  for _, case in ipairs(MATRIX) do
    stage(case.base, case.mutate)
    local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
    local built = Builder.build()
    if #valid > 0 then
      seen_valid = true
      if built == nil then silent[#silent + 1] = case.label end
    else
      seen_empty = true
    end
    if Dispatcher.get_force_for_state("SELECTING_HAND") then asked = asked + 1 end
  end
  check("the matrix covers both a populated and an empty action set", seen_valid and seen_empty)
  check("the builder never answers nothing while the registry accepts an action",
    #silent == 0, table.concat(silent, "; "))
  check("the matrix is not vacuous -- most of it reaches the wire", asked >= 4, tostring(asked))
end

do
  stage(EMPTY_HAND_CONSUMABLE, function(mock)
    mock.consumeables = { cards = {}, config = { card_limit = 2 } }
    mock.jokers = { cards = {}, config = { card_limit = 5 } }
  end)
  local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
  check("no SELECTING_HAND action is accepted on this board", not has_progress(valid),
    table.concat(valid, ","))
  check("the router answers nothing, and it is the router that does it",
    Dispatcher.get_force_for_state("SELECTING_HAND") == nil)
  check("the builder still built -- it offered what it had and left the verdict to the router",
    type(Builder.build()) == "table")
end

done()
