_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("silence-paths")

local Router = require("force.force_router")
local Guard = require("core.transition_guard")
local Tuning = require("core.config")
local FAILSAFE = Tuning.get("NEURO_ROUTER_DEFER_FAILSAFE")

local PACK_STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7 }

local function tarot()
  return { ability = { set = "Tarot", consumeable = {} },
    config = { center = { key = "c_fool", set = "Tarot", name = "The Fool" } } }
end

local function pack_board()
  _G.G = {
    STATE = PACK_STATES.TAROT_PACK, STATES = PACK_STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
    GAME = { dollars = 20, round = 11, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4, blind_choices = {}, blind_states = {} },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
      hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
    P_BLINDS = {},
    NEURO = { run_generation = 1, _decision_windows = {}, once_serials = {}, decision_serial = 1,
      state_enter_serial = 1, plan = {}, reserved_dollars = 0 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    pack_cards = { cards = { tarot() }, config = {} },
    booster_pack = {},
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      skip_booster = function() end, use_card = function() end },
    CONTROLLER = { locks = {} },
  }
  Guard.reset()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  Router._guard_defer_generation = nil
  Router._pack_exit_at = nil
  Router._pack_exit_generation = nil
end

local function shape(state)
  local force = Router.get_force_for_state(state)
  if not force then return nil end
  return table.concat(force.actions, ",")
end

do
  pack_board()
  local full = shape("TAROT_PACK")
  check("fixture: an unblocked pack offers the two actions that leave it",
    full == "choose_pack_card,skip_pack", tostring(full))

  G.GAME.STOP_USE = 1
  check("the settling pack defers first", shape("TAROT_PACK") == nil)
  G.TIMERS.REAL = 1000 + FAILSAFE - 0.5
  check("and holds the defer until the failsafe elapses", shape("TAROT_PACK") == nil)

  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  local released = shape("TAROT_PACK")
  check("past the failsafe the force carries a real way out of the pack",
    released ~= nil and released:find("choose_pack_card", 1, true) ~= nil
      and released:find("skip_pack", 1, true) ~= nil, tostring(released))

  local shapes, order = {}, {}
  local silent = 0
  for step = 0, 600 do
    G.TIMERS.REAL = 1000 + FAILSAFE + 0.5 + step
    local sig = shape("TAROT_PACK")
    if sig then shapes[sig] = true; order[#order + 1] = sig else silent = silent + 1 end
  end
  local distinct = 0
  for _ in pairs(shapes) do distinct = distinct + 1 end
  check("ten more minutes with the flag stuck never go silent again", silent == 0, silent)
  check("and never alternate -- one force shape, so the arming loop has nothing to churn",
    distinct == 1 and order[1] == released, distinct .. " shapes")
end

do
  pack_board()
  G.NEURO.pack_exit_pending = true
  check("the optimistic pack exit suppresses the follow-up force",
    shape("TAROT_PACK") == nil)
  G.TIMERS.REAL = 1000 + FAILSAFE - 0.5
  check("the suppression holds while the exit is plausible", shape("TAROT_PACK") == nil)

  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  local back = shape("TAROT_PACK")
  check("an engine that never left the pack gets asked again",
    back == "choose_pack_card,skip_pack", tostring(back))
  check("and the stale flag is dropped, so the next pack starts clean",
    G.NEURO.pack_exit_pending == nil, tostring(G.NEURO.pack_exit_pending))

  local silent = 0
  for step = 1, 120 do
    G.TIMERS.REAL = 1000 + FAILSAFE + 0.5 + step
    if not shape("TAROT_PACK") then silent = silent + 1 end
  end
  check("no relapse into silence", silent == 0, silent)
end

do
  pack_board()
  G.NEURO.pack_exit_pending = true
  G.booster_pack = nil
  check("a destroyed pack object suppresses the follow-up force", shape("TAROT_PACK") == nil)
  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  check("it still does not advertise impossible pack actions past the deadline",
    shape("TAROT_PACK") == nil, tostring(shape("TAROT_PACK")))
  check("the overdue transition is diagnosed and its stale optimistic gate is released",
    G.NEURO.pack_exit_pending == nil and G.NEURO.pack_transition_stalled ~= nil,
    tostring(G.NEURO.pack_exit_pending))

  G.STATE = PACK_STATES.SHOP
  check("the state handing back releases the suppression",
    Router.get_force_for_state("SHOP") ~= nil)
end

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7 }
local CLOCK = 5000
local forces, results = {}, {}

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Helpers = require("tests.helpers")
local Orch = require("core.orchestrator")

local play_card = require("tests.helpers").play_card

local function bridge_stub()
  return {
    send_action_result = function(_, id, ok, message, code)
      results[#results + 1] = { id = id, ok = ok, message = message, code = code }
    end,
    send_context = function() end,
    register_actions = function() end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

local function board(state_name)
  _G.G = {
    STATE = STATES[state_name], STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = CLOCK }, SETTINGS = { GAMESPEED = 1 },
    OVERLAY_MENU = nil, screenwipe = nil,
    GAME = {
      dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, STOP_USE = 0,
      blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Small Blind" },
      hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_hook = { key = "bl_hook", name = "The Hook" } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces, results = {}, {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = state_name,
    update = function() end,
    send_context = function() end,
    register_actions = function() end,
    unregister_actions = function() end,
  }
  function G.NEURO:force_actions(_ctx, _query, actions)
    forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
  end
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("silence-paths")
  require("core.tx_cache").reset()
  Dispatcher.reset_tx()
end

local function tick_for(seconds)
  for _ = 1, math.floor(seconds / 0.1) do
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) break end
  end
end

local answer_n = 0
local function answer(bridge, name, payload)
  answer_n = answer_n + 1
  Helpers.stage_registered(nil, { name })
  Dispatcher.handle_message({ command = "action", run_generation = G.NEURO.run_generation,
    data = { id = "sil-" .. answer_n, name = name, data = payload } }, bridge)
  return results[#results]
end

local function phase() return require("tests.helpers").force_phase(FS) end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 1 }, b)
  tick_for(10)
  check("fixture: the game asked its first question",
    #forces == 1 and G.NEURO.force_inflight == true, #forces .. "/" .. tostring(G.NEURO.force_inflight))
  check("fixture: and the mod remembered the transport stamp it has already seen",
    G.NEURO.transport_session == 1, tostring(G.NEURO.transport_session))
  local before = #forces

  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 1 }, b)
  check("a reconnect that repeats its stamp still ends the unanswerable offer",
    G.NEURO.force_inflight == false and phase() == Window.ENDED,
    tostring(G.NEURO.force_inflight) .. "/" .. phase())

  tick_for(120)
  check("so the fresh client is asked again instead of waiting on a window it never got",
    #forces == before + 1, #forces .. " forces after " .. before)

  local settled = #forces
  tick_for(FS.FORCE_LIVENESS_TIMEOUT - (G.TIMERS.REAL - G.NEURO.force_sent_at) - 5)
  check("and the replacement is asked exactly once -- no reconnect storm",
    #forces == settled, #forces .. " forces after " .. settled)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  Dispatcher.handle_message({ command = "actions/reregister_all", transport_session = 1 }, b)
  tick_for(10)
  local before = #forces
  for _ = 1, 5 do
    Dispatcher.handle_message({ command = "actions/reregister_all" }, b)
  end
  check("a stamp-less request from the server never touches a live offer",
    G.NEURO.force_inflight == true and phase() == Window.FORCED,
    tostring(G.NEURO.force_inflight) .. "/" .. phase())
  tick_for(30)
  check("and asks nothing new", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before = #forces
  b.is_transition_cooldown = function() return true end

  local acks = 0
  for _ = 1, 12 do
    local r = answer(b, "play_hand", '{"indices":[1,2]}')
    if r and r.ok == true and r.code == "TRANSITION_ACKNOWLEDGED" then acks = acks + 1 end
    tick_for(2)
  end
  check("every one of the twelve answers really hit the transition gate", acks == 12, acks)
  local asked = #forces - before
  check("twelve answers no longer buy twelve replacement forces", asked < 12, asked)
  check("the budget still lets the game come back, so this is not silence", asked >= 1, asked)

  b.is_transition_cooldown = function() return false end
  local parked = #forces
  tick_for(FS.ACK_IDLE_REASK + 20)
  check("a parked offer nobody answers again is re-asked, so this never becomes a dead end",
    #forces == parked + 1, #forces .. " forces after " .. parked)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  b.is_transition_cooldown = function() return true end
  local r = answer(b, "play_hand", '{"indices":[1,2]}')
  check("a single transition answer is a terminal acknowledgement, not a promised follow-up",
    r.ok == true and r.code == "TRANSITION_ACKNOWLEDGED", tostring(r.code))
  check("which parks the offer rather than re-asking one-for-one",
    phase() == Window.ACKNOWLEDGED, phase())
  check("the offer's actions stay registered, so she can retry when the screen settles",
    FS.is_forced_action("play_hand") == true)
end

done()
