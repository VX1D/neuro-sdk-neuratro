require("tests.stubs").setup({ love = "lazy" })

local check, done = require("tests.helpers").harness("admission gates")

local EngineCards = require("tests.engine_cards")
local STATES = EngineCards.states()
_G.G = { NEURO = { persona = "neuro" }, FUNCS = {}, GAME = {}, STATES = STATES }

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Enforce = require("tests.helpers").enforce()
local Guard = require("core.validate")
local Registry = require("core.action_registry")
local StateKinds = require("core.state_kinds")

local sid = 0
local function card(value, suit)
  sid = sid + 1
  return { sort_id = sid, cost = 0, sell_cost = 1, ability = { set = "Default", name = "Default Base" },
    config = { center = {} }, base = { value = value, suit = suit, id = tonumber(value) or 11 } }
end
local function joker(name, key)
  sid = sid + 1
  return { sort_id = sid, sell_cost = 3, ability = { set = "Joker", name = name },
    config = { center = { key = key, set = "Joker", name = name } }, facing = "front" }
end

local function base_env(state)
  G.STATE = STATES[state]
  G.TIMERS = { TOTAL = 100, REAL = 100 }
  G.SETTINGS = { paused = false }
  G.OVERLAY_MENU = nil
  G.CONTROLLER = { locks = {} }
  G.play = { cards = {} }
  G.FUNCS = {}
  G.GAME = { dollars = 10, bankrupt_at = 0, round = 3, STOP_USE = 0, stake = 1, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 1, blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_pillar" },
      blind_states = { Small = "Current", Big = "Upcoming", Boss = "Upcoming" } },
    blind = { chips = 300, mult = 1 },
    starting_params = { play_limit = 5, discard_limit = 5 } }
  G.hand = { cards = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Spades"), card("9", "Clubs") },
    highlighted = {}, config = { card_limit = 8 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 }, highlighted = {} }
  G.NEURO = { persona = "neuro", state_enter_serial = (G.NEURO and G.NEURO.state_enter_serial or 0) + 1 }
  Guard.reset_run_state()
  Enforce.reset_run_state()
end

local function admits(name, payload)
  Enforce.reset_run_state()
  local ok, message, _, code = Enforce.pre_action(nil, name, payload)
  return ok == true, message, code
end

local contains = require("tests.helpers").has

do
  base_env("SELECTING_HAND")
  check("baseline: discard_hand is admitted with no popup", admits("discard_hand", { indices = { 1, 2 } }))
  G.SETTINGS.paused = true
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  local offer = Actions.get_valid_actions_for_state("SELECTING_HAND")
  check("pause menu: the offer is the popup's own action", #offer == 1 and offer[1] == "exit_overlay_menu",
    table.concat(offer, ","))
  local parity, worst = true, nil
  for _, name in ipairs(Actions.get_action_names_for_state("SELECTING_HAND")) do
    if Actions.is_action_valid(name) ~= contains(offer, name) then parity, worst = false, name end
  end
  check("pause menu: validity and offer agree for every action of the state", parity, worst)
  local ok, message, code = admits("discard_hand", { indices = { 1, 2 } })
  check("pause menu: discard_hand is refused at admission", not ok and code == "ACTION_UNAVAILABLE", code)
  check("pause menu: the refusal names the way out", type(message) == "string"
    and message:find("Close the overlay", 1, true) ~= nil, message)
  check("pause menu: exit_overlay_menu is admitted", admits("exit_overlay_menu"))
  G.SETTINGS.paused = false
  G.OVERLAY_MENU = nil
  check("popup closed: discard_hand is admitted again", admits("discard_hand", { indices = { 1, 2 } }))
end

do
  base_env("BLIND_SELECT")
  G.GAME.round_resets.blind_states = { Small = "Skipped", Big = "Select", Boss = "Upcoming" }
  G.GAME.blind_on_deck = "Big"
  local planet = EngineCards.consumable("c_pluto", { sort_id = 900, cost = 3, sell_cost = 1 })
  G.consumeables.cards = { planet }
  planet.area = G.consumeables
  local sell = { area = "consumables", index = 1 }
  check("unlocked: sell_card is admitted", admits("sell_card", sell))
  -- Charm Tag holds a controller lock while its pack is open.
  G.CONTROLLER = { locked = true, locks = { [42] = true } }
  local ok, _, code = admits("sell_card", sell)
  check("Charm Tag lock: sell_card is refused", not ok and code == "TRANSITION_PENDING", code)
  G.CONTROLLER = { locked = false, locks = { [42] = true } }
  Guard.reset_run_state()
  local lock_ok, lock_msg = admits("sell_card", sell)
  check("a lock taken this frame blocks before `locked` is derived", not lock_ok, lock_msg)
  check("bookkeeping is not an engine input", admits("record_plan", { hand_plan = "x" }))
  G.CONTROLLER = { locks = {} }
  Guard.reset_run_state()
  G.GAME.STOP_USE = 2
  check("STOP_USE: sell_card is refused like Card:can_sell_card", not admits("sell_card", sell))
  G.GAME.STOP_USE = 0
  Guard.reset_run_state()
  G.play.cards = { card("5", "Clubs") }
  check("cards in play: sell_card is refused like Card:can_sell_card", not admits("sell_card", sell))
  G.play.cards = {}
  Guard.reset_run_state()
  check("engine settled: sell_card is admitted again", admits("sell_card", sell))
end

do
  base_env("MENU")
  G.SETTINGS.paused = true
  G.OVERLAY_MENU = require("tests.helpers").unlock_overlay(nil)
  check("deck unlock: recognized without joker_unlock_table", StateKinds.is_unlock_popup())
  local offer = Actions.get_valid_actions_for_state("MENU")
  check("deck unlock: only exit_overlay_menu is offered", #offer == 1 and offer[1] == "exit_overlay_menu",
    table.concat(offer, ","))
  local force = require("force.force_router").get_force_for_state("MENU")
  check("deck unlock: the force offers only exit_overlay_menu", force and #force.actions == 1
    and force.actions[1] == "exit_overlay_menu", force and table.concat(force.actions, ","))
  check("deck unlock: open_run_setup is refused", not admits("open_run_setup"))
  local continued = false
  G.FUNCS.continue_unlock = function() continued = true end
  G.FUNCS.exit_overlay_menu = function() end
  local exec = Dispatcher.preflight("exit_overlay_menu", {})
  if type(exec) == "function" then exec() end
  check("deck unlock: dismissed through continue_unlock", continued)
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  check("an ordinary popup is not an unlock popup", not StateKinds.is_unlock_popup())
end

-- Selling Luchador disables the boss only after the sale.
do
  base_env("SELECTING_HAND")
  local blind = { name = "The Pillar", boss = true, disabled = false, debuff = {}, chips = 800,
    config = { blind = { key = "bl_pillar" } } }
  function blind:get_type() return self.boss and "Boss" or "Small" end
  G.GAME.blind = blind
  local plain, luchador = joker("Joker", "j_joker"), joker("Luchador", "j_luchador")
  G.jokers.cards = { plain, luchador }
  local candidates = Registry.candidates("sell_card")
  check("boss round: sell_card is offered", Actions.is_action_valid("sell_card"))
  check("boss round: Luchador is the only sale offered", #candidates == 1 and candidates[1].index == 2
    and candidates[1].name == "Luchador", #candidates)
  local exec, err = Dispatcher.preflight("sell_card", { area = "jokers", index = 1, name = "Joker" })
  check("boss round: selling an ordinary joker is refused", exec == nil and type(err) == "table"
    and err.reason_code == "ACTION_UNAVAILABLE", err and err.reason_code)
  luchador.facing = "back"
  check("face-down Luchador: nothing is offered", not Actions.is_action_valid("sell_card"))
  luchador.facing = "front"
  blind.disabled = true
  check("disabled boss: sell_card is not offered", not Actions.is_action_valid("sell_card"))
  blind.disabled, blind.boss = false, false
  check("small blind: sell_card is not offered", not Actions.is_action_valid("sell_card"))
end

do
  local function slot_board(boss_name, boss_key, jokers)
    base_env("SELECTING_HAND")
    local blind = { name = boss_name, boss = true, disabled = false, debuff = {}, chips = 800, in_blind = true,
      config = { blind = { key = boss_key } } }
    function blind:get_type() return "Boss" end
    G.GAME.blind = blind
    G.GAME.hands = {}
    G.GAME.round_resets.blind_states = { Small = "Defeated", Big = "Defeated", Boss = "Current" }
    G.jokers.cards = jokers
    local function cons(key)
      sid = sid + 1
      return EngineCards.consumable(key, { sort_id = sid, sell_cost = 1, facing = "front", area = G.consumeables })
    end
    G.jokers.config.card_limit = #G.jokers.cards
    G.consumeables.cards = { cons("c_judgement"), cons("c_hermit") }
  end
  local UseGate = require("facts.use_gate")
  slot_board("The Pillar", "bl_pillar", { joker("Joker", "j_joker") })
  local judgement = G.consumeables.cards[1]
  check("engine: Judgement is refused while joker slots are full", UseGate.usable(judgement) == false)
  G.consumeables.cards = { judgement }
  check("engine: freeing a consumable slot does not unblock it", UseGate.usable(judgement) == false)
  G.jokers.config.card_limit = G.jokers.config.card_limit + 1
  check("engine: freeing a joker slot does", UseGate.usable(judgement) == true)
end

done()
