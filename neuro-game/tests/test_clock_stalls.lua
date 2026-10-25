_G.NEURO_TEST = true

local wall = 0
love = { timer = { getTime = function() return wall end } }

local STATES = require("tests.engine_cards").states()
_G.G = {
  P_CENTERS = require("tests.engine_centers").centers(),
  STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
  GAME = { dollars = 20, round = 1, chips = 0, STOP_USE = 0,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 1, blind_choices = {}, blind_states = {} },
    used_vouchers = {}, modifiers = {}, hands = {} },
  FUNCS = {}, CONTROLLER = { locks = {} }, E_MANAGER = { queues = {} },
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  deck = { cards = {} },
  shop_jokers = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {}, config = { card_limit = 1 } },
  shop_booster = { cards = {}, config = { card_limit = 2 } },
}
require("tests.engine_cards").install_smods({ Mods = {} })

local check, done = require("tests.helpers").harness("clock-stalls")
local Utils = require("util.utils")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local Orch = require("core.orchestrator")
local Window = require("core.window")
local Execute = require("core.execute")
local Receipt = require("core.action_result")
local Staging = require("core.staging")
local S = require("hud.state")
local H = require("tests.helpers")

local withdrawn, forces = {}, 0

local function advance(seconds, dt)
  dt = dt or 1 / 60
  local target = G.TIMERS.REAL + seconds
  while G.TIMERS.REAL < target - 1e-12 do
    local step = math.min(dt, target - G.TIMERS.REAL)
    G.TIMERS.REAL = G.TIMERS.REAL + step
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + step * G.SPEEDFACTOR
    wall = wall + step
    Utils.observe_clock()
  end
end

local function fresh_neuro()
  withdrawn, forces = {}, 0
  G.NEURO = H.orch_neuro({
    llm_paused = false, state = "SHOP", send_context = "written", send_action_result = "noop",
    register_actions = "true",
    withdraw_actions = function(_, names) withdrawn[#withdrawn + 1] = names return true end,
    force_actions = function() forces = forces + 1 return true end,
  })
  S.state_changed_at = G.TIMERS.REAL
  S.state_changed_at_game = 0
  Staging.reset_run_state()
  Execute.abort("test")
  Window.reset()
  Orch.reset_run_state()
  return G.NEURO
end

local REWIND_TO = 12
local settled = function() return Window._test.settled("SHOP") end

do
  fresh_neuro()
  advance(2400)
  Window.hold_after_action()
  local epoch_before = Utils.clock_epoch()

  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  check("every stamp taken during the run is now in the future",
    (G.NEURO.last_action_at or 0) > Utils.gate_now("action_cooldown"),
    tostring(G.NEURO.last_action_at) .. " vs " .. Utils.gate_now("action_cooldown"))
  check("and the action gate is shut with nothing that can open it", settled() == false)

  Orch._step_clock_rewind()
  check("the rewind is observed exactly once", Utils.clock_epoch() == epoch_before + 1,
    Utils.clock_epoch() .. " vs " .. epoch_before)
  check("and it runs the run reset the engine never announces",
    G.NEURO.last_action_at == nil, tostring(G.NEURO.last_action_at))
  check("so the action gate is open again on the menu", settled() == true)

  Orch._step_clock_rewind()
  check("a second frame at the same clock does not reset again",
    Utils.clock_epoch() == epoch_before + 1)
end

do
  fresh_neuro()
  advance(2400)
  Window.hold_after_action()
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  advance(600)
  check("ten minutes on the menu do not clear it by themselves", settled() == false)
  Orch._step_clock_rewind()
  check("the rewind step does", settled() == true)
end

do
  fresh_neuro()
  local epoch = Utils.clock_epoch()
  advance(120)
  Orch._step_clock_rewind()
  check("ordinary play never looks like a rewind", Utils.clock_epoch() == epoch)
end

do
  fresh_neuro()
  advance(60)
  Window.hold_after_action()
  local stamp = G.NEURO.last_action_at
  G.NEURO.dev_preview_active = true
  G.TIMERS.REAL, G.TIMERS.TOTAL = 1, 1
  Orch._step_clock_rewind()
  check("a dev preview swapping the clock table does not reset the run",
    G.NEURO.last_action_at == stamp, tostring(G.NEURO.last_action_at))
  G.NEURO.dev_preview_active = nil
end

do
  fresh_neuro()
  advance(300)
  local lines = {}
  local real_print = print
  local function boom() error("boom") end
  _G.print = function(...) lines[#lines + 1] = tostring((...)) end
  pcall(Orch.update, 1 / 60, boom)
  local first = #lines
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  pcall(Orch.update, 1 / 60, boom)
  _G.print = real_print
  check("the mod printed its own error before the rewind", first > 0, first)
  check("and is not silenced about it across the rewind", #lines > first,
    first .. " -> " .. #lines)
end

do
  fresh_neuro()
  G.NEURO.reserved_dollars = 7
  advance(5)
  check("a leftover dollar reservation does not hold the next decision", settled() == true)
end

local function open_receipt(id)
  return Receipt.create({ id = id, name = "buy_from_shop", run_generation = 1,
    deadline = Receipt.now() + 3600, timeout_outcome = "failed",
    probe = function() return "pending" end })
end

do
  fresh_neuro()
  advance(2)
  H.open_force("SHOP", { "buy_from_shop" })
  G.NEURO.state = "BLIND_SELECT"
  G.STATE = STATES.BLIND_SELECT
  Window.step("BLIND_SELECT")
  check("a state move withdraws the sent offer by unregistering its actions",
    Window.current() == nil and #withdrawn == 1 and withdrawn[1][1] == "buy_from_shop",
    tostring(#withdrawn))
end

do
  fresh_neuro()
  advance(2)
  local w = H.open_force("SHOP", { "buy_from_shop" })
  Window.on_result("buy_from_shop", true)
  check("an answered offer ends without unregistering anything",
    w.phase == "ended" and #withdrawn == 0, w.phase)
  Execute.admit({ id = "hoist-2", name = "buy_from_shop", data = {}, bridge = G.NEURO,
    exec = function() return open_receipt("hoist-2") end }, false)
  advance(600)
  Window.step("SHOP")
  check("an action in flight holds the next decision however long it runs",
    Window.current() == nil and forces == 0 and Execute.busy() == "verifying", tostring(Execute.busy()))
  Execute.abort("test")
end

do
  fresh_neuro()
  advance(2)
  local w = H.open_force("SHOP", { "buy_from_shop" })
  Window.withdraw("test")
  check("a withdrawn offer ends and its actions are unregistered",
    w.phase == "ended" and #withdrawn == 1 and Window.current() == nil)
end

do
  fresh_neuro()
  advance(2)
  local r = Receipt.create({ id = "deadline", name = "buy_from_shop",
    deadline = Receipt.now() + 4, timeout_outcome = "failed",
    probe = function() return "pending" end })
  advance(6)
  check("a receipt past its deadline is bounded",
    Receipt.settle(r, Receipt.now(), nil) == true and r.phase == "failed", r.phase)
end

do
  fresh_neuro()
  advance(2400)
  local r = Receipt.create({ id = "rewind-receipt", name = "buy_from_shop",
    deadline = Receipt.now() + 4, timeout_outcome = "failed",
    probe = function() return "pending" end })
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  Receipt.settle(r, Receipt.now(), nil)
  check("a rewind re-bases the deadline instead of pushing it out of reach",
    r.deadline <= Receipt.now() + 4 and r.phase == nil, r.deadline)
  advance(6)
  Receipt.settle(r, Receipt.now(), nil)
  check("so it still times out after its own length", r.phase == "failed")
end

-- The boss banner temporarily sets blind.block_play, so play_hand becomes legal only after it ends.
local function card(rank, suit)
  return { base = { value = rank, suit = suit, nominal = 5, id = 5 }, ability = { effect = "base" },
    config = { center = { key = "c_base" } }, highlighted = false,
    facing = "front", debuff = false, area = G.hand }
end

local function selecting_hand_world()
  fresh_neuro()
  G.STATE = STATES.SELECTING_HAND
  G.NEURO.state = "SELECTING_HAND"
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 3
  G.hand.cards = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Hearts"),
    card("5", "Hearts"), card("6", "Hearts") }
  G.GAME.blind = { name = "The Hook", boss = true, block_play = true }
end

do
  local Actions = require("core.actions")
  selecting_hand_world()
  local blocked = Utils.list_to_set(Actions.get_valid_actions_for_state("SELECTING_HAND"))
  check("the banner really does make play_hand illegal while it plays",
    blocked.play_hand ~= true and blocked.discard_hand == true,
    tostring(blocked.play_hand) .. "/" .. tostring(blocked.discard_hand))

  local w = H.open_force("SELECTING_HAND", { "discard_hand" })
  advance(0.5)
  Window.step("SELECTING_HAND")
  check("an unchanged board does not re-arm", Window.current() == w)

  G.GAME.blind.block_play = nil
  advance(0.5)
  Window.step("SELECTING_HAND")
  check("the banner clearing withdraws the offer as widened",
    w.phase == "ended" and w.ended_by == "widened" and #withdrawn == 1, tostring(w.ended_by))
end

do
  selecting_hand_world()
  G.GAME.blind.block_play = nil
  local w = H.open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  advance(0.5)
  G.GAME.current_round.discards_left = 0
  advance(0.5)
  Window.step("SELECTING_HAND")
  check("an offer that narrowed is not torn down", Window.current() == w)
end

done()
