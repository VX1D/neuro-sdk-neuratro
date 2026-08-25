_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local Helpers = require("tests.helpers")
local check, done = Helpers.harness("unmodelled-state-guard")

local Actions = require("core.actions")
local Enforce = require("core.enforce")
local State = require("core.state")
local Dispatcher = require("core.dispatcher")
local Router = require("force.force_router")
local TxCache = require("core.tx_cache")
local ForceState = require("core.force_state")
local ActionReceipt = require("core.action_receipt")

-- G.STATES verbatim from the running build: game-dump/globals.lua:295-317, including the two
-- Steamodded values injected by smods/lovely/booster.toml:102.
local ENGINE_STATES = {
  SMODS_BOOSTER_OPENED = 999, SMODS_REDEEM_VOUCHER = 998,
  SELECTING_HAND = 1, HAND_PLAYED = 2, DRAW_TO_HAND = 3, GAME_OVER = 4, SHOP = 5,
  PLAY_TAROT = 6, BLIND_SELECT = 7, ROUND_EVAL = 8, TAROT_PACK = 9, PLANET_PACK = 10,
  MENU = 11, TUTORIAL = 12, SPLASH = 13, SANDBOX = 14, SPECTRAL_PACK = 15,
  DEMO_CTA = 16, STANDARD_PACK = 17, BUFFOON_PACK = 18, NEW_ROUND = 19,
}

-- Two more names core/state.lua can return that the engine enum does not carry: RUN_SETUP is the
-- overlay reading (state.lua:25-27), UNKNOWN is the miss (state.lua:8,24) -- which is what
-- G.STATE = -1 from Game:delete_run (game-dump/game.lua:1224) reads back as.
local MOD_ONLY_STATES = { "RUN_SETUP", "UNKNOWN" }

local EXPECTED_UNMODELLED = {
  "DEMO_CTA", "DRAW_TO_HAND", "HAND_PLAYED", "NEW_ROUND", "PLAY_TAROT",
  "SANDBOX", "SMODS_REDEEM_VOUCHER", "TUTORIAL", "UNKNOWN",
}

local function all_state_names()
  local names = {}
  for name in pairs(ENGINE_STATES) do names[#names + 1] = name end
  for _, name in ipairs(MOD_ONLY_STATES) do names[#names + 1] = name end
  table.sort(names)
  return names
end

do
  local unmodelled = {}
  for _, name in ipairs(all_state_names()) do
    if not Actions.state_is_modelled(name) then unmodelled[#unmodelled + 1] = name end
  end
  check("every state the mod can name is either modelled or one of the nine",
    table.concat(unmodelled, ",") == table.concat(EXPECTED_UNMODELLED, ","),
    table.concat(unmodelled, ","))
end

do
  G.OVERLAY_MENU = nil
  G.STATES = ENGINE_STATES
  for _, name in ipairs(EXPECTED_UNMODELLED) do
    local ok, force = pcall(Router.get_force_for_state, name)
    check("no force is offered on " .. name, ok and force == nil, tostring(ok and force))
  end
end

local play_card = require("tests.helpers").play_card

local played = 0

-- A live SELECTING_HAND run whose registry is then carried, unchanged, onto an unmodelled screen --
-- exactly what core/orchestrator.lua:225-227 leaves behind.
local function parked_at(state_name)
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.STATES = ENGINE_STATES
  G.STATE = ENGINE_STATES[state_name] or -1
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small", blind_choices = {} },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
    play_cards_from_highlighted = function() played = played + 1 end,
    discard_cards_from_highlighted = function() played = played + 1 end,
  }
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = state_name, state_enter_serial = 1 }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  ForceState.clear_force_state()
  ActionReceipt.reset("unmodelled")
  TxCache.reset()
  Helpers.stage_registered("SELECTING_HAND")
  check("the parked screen reads back as " .. state_name, State.get_state_name() == state_name,
    State.get_state_name())
end

local STALE_NAMES = Actions.get_action_names_for_state("SELECTING_HAND")

do
  check("SELECTING_HAND really leaves names behind to be refused", #STALE_NAMES > 1, #STALE_NAMES)
  for _, state_name in ipairs(EXPECTED_UNMODELLED) do
    parked_at(state_name)
    local leaked = {}
    for _, name in ipairs(STALE_NAMES) do
      if name ~= "exit_overlay_menu" then
        local allowed, _, _, code = Enforce.pre_action(nil, name, {})
        if allowed ~= false or code ~= "ACTION_UNAVAILABLE" then
          leaked[#leaked + 1] = name .. "/" .. tostring(code)
        end
      end
    end
    check("every stale action is refused as unavailable on " .. state_name,
      #leaked == 0, table.concat(leaked, ","))
  end
end

do
  for _, state_name in ipairs(EXPECTED_UNMODELLED) do
    parked_at(state_name)
    local before = played
    local log = {}
    local bridge = {
      send_action_result = function(_, id, ok, message, code)
        log[#log + 1] = { id = id, ok = ok, message = message, code = code }
      end,
      send_context = function() end,
      register_actions = function() end,
      unregister_actions = function() end,
      is_transition_cooldown = function() return false end,
    }
    local id = state_name .. "-stale-1"
    Dispatcher.handle_message({ command = "action",
      data = { id = id, name = "play_hand", data = { card_indices = { 1, 2 } } } }, bridge)
    check("a stale action delivered on " .. state_name .. " is answered exactly once",
      #log == 1 and log[1].id == id, #log .. " result(s)")
    check("and it did not reach the engine on " .. state_name, played == before, played - before)
    check("and no result is left owed on " .. state_name, #TxCache.outstanding(0) == 0,
      #TxCache.outstanding(0))
  end
end

done()
