-- An accepted answer that names an action outside the standing offer ends the exchange: the offer is
-- withdrawn (API/README.md:23) and the decision is asked again, because SPECIFICATION.md:136-137
-- forbids a second force landing on top of a live one.
_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-window-outside-offer")

local STATES = { SELECTING_HAND = 4, SHOP = 5, BLIND_SELECT = 7, ROUND_EVAL = 8, MENU = 11 }

local CLOCK = 1000

local forces, registered, unregistered = {}, {}, {}
local results = {}

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

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Window = require("core.force_window")
local Helpers = require("tests.helpers")

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
      select_blind = function() end, exit_overlay_menu = function() G.OVERLAY_MENU = nil end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces, registered, unregistered, results = {}, {}, {}, {}
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = state_name,
    update = function() end,
    send_context = function() end,
    register_actions = function(_, defs)
      for _, d in ipairs(defs or {}) do registered[#registered + 1] = d.name or d end
    end,
    unregister_actions = function(_, names)
      for _, n in ipairs(names or {}) do unregistered[#unregistered + 1] = n end
    end,
  }
  function G.NEURO:force_actions(_ctx, _query, actions)
    forces[#forces + 1] = { t = G.TIMERS.REAL, state = G.NEURO.force_state,
      actions = table.concat(actions, ",") }
  end
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("outside-offer")
  require("core.tx_cache").reset()
end

local Orch = require("core.orchestrator")

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
  Dispatcher.handle_message({ command = "action", run_generation = 1,
    data = { id = "oo-" .. answer_n, name = name, data = payload } }, bridge)
  return results[#results]
end

-- The teardown does not strip the registry; it quarantines the offer's names, and the reconciler is
-- what keeps them off the wire until the settle gap passes (API/README.md:23).
local function quarantined(...)
  local now = G.TIMERS.REAL
  for _, name in ipairs({ ... }) do
    if FS.cancel_blocks(name, now) ~= true then return false, name end
  end
  return true
end

local function phase() return require("tests.helpers").force_phase(FS) end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("P: one force stands", #forces == 1 and phase() == Window.FORCED, phase())
  check("P: and exit_overlay_menu is not in it",
    forces[1] and forces[1].actions:find("exit_overlay_menu", 1, true) == nil,
    forces[1] and forces[1].actions)

  G.OVERLAY_MENU = { popup = true }
  local r = answer(b, "exit_overlay_menu", "{}")
  check("P: the out-of-offer answer is accepted", r and r.ok == true and r.code == nil,
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("P: the exchange is over -- nothing is left in flight",
    G.NEURO.force_inflight == false, tostring(G.NEURO.force_inflight))
  check("P: and the offer it did not answer is torn down",
    phase() == Window.ENDED, phase())
  check("P: the offer's names are withdrawn, which is what makes Neuro drop the force",
    quarantined("play_hand", "discard_hand"))
  check("P: the decision was not made, so its serial does not move",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))

  local before = #forces
  tick_for(20)
  check("P: and the game asks the same decision again instead of going quiet",
    #forces == before + 1, #forces)
  check("P: with the full offer, not one narrowed by the answer it got",
    forces[#forces].actions == forces[1].actions, forces[#forces].actions)
end

-- A refused answer is retried by Neuro against the same force (SPECIFICATION.md:184), so refusing one
-- must leave the offer exactly where it was -- being out of the offer changes nothing about that.
do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before, unregistered_before = #forces, #unregistered
  local r = answer(b, "exit_overlay_menu", "{}")
  check("R: with no popup open the out-of-offer answer is refused",
    r and r.ok == false, r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("R: the offer stays standing and in flight",
    phase() == Window.FORCED and G.NEURO.force_inflight == true, phase())
  check("R: and nothing of it is withdrawn", #unregistered == unregistered_before,
    table.concat(unregistered, ","))
  tick_for(30)
  check("R: so no second force is sent on top of the live one", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, 4 do answer(b, "play_hand", '{"indices":[1,2,99]}') end
  check("N: the fixture parked the offer in ACKNOWLEDGED", phase() == Window.ACKNOWLEDGED, phase())

  local before, serial_before = #forces, G.NEURO.decision_serial
  G.OVERLAY_MENU = { popup = true }
  local r = answer(b, "exit_overlay_menu", "{}")
  check("N: the out-of-offer answer is accepted", r and r.ok == true and r.code == nil,
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("N: and the parked offer is torn down too", phase() == Window.ENDED, phase())
  check("N: its names withdrawn", quarantined("play_hand", "discard_hand"))
  check("N: without spending the decision it never answered",
    G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  tick_for(20)
  check("N: and the decision is asked again", #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  G.jokers.cards = {
    { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
      config = { center = { key = "j_a", set = "Joker" } } },
    { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
      config = { center = { key = "j_b", set = "Joker" } } },
  }
  local b = bridge_stub()
  tick_for(10)
  check("M: set_joker_order is valid here",
    Actions.is_action_valid("set_joker_order") == true)
  check("M: set_joker_order is outside the offer",
    forces[1] and forces[1].actions:find("set_joker_order", 1, true) == nil,
    forces[1] and forces[1].actions)
  local before, unregistered_before = #forces, #unregistered
  local r = answer(b, "set_joker_order", '{"from_index":1,"to_index":2}')
  check("M: and it is accepted", r and r.ok == true and r.code == nil,
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("M: the offer is torn down", phase() == Window.ENDED, phase())
  check("M: and withdrawn from the client, not merely forgotten by the game",
    quarantined("play_hand", "discard_hand"))
  tick_for(20)
  check("M: the decision is asked again", #forces == before + 1, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local serial_before = G.NEURO.decision_serial
  local r = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("I: an in-offer answer is accepted", r and r.ok == true, r and tostring(r.ok))
  check("I: it ends the window", phase() == Window.ENDED, phase())
  check("I: and it spends the decision, unlike an answer from outside the offer",
    G.NEURO.decision_serial == serial_before + 1, tostring(G.NEURO.decision_serial))
end

done()
