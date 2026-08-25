_G.NEURO_TEST = true

local wall = 0
love = { timer = { getTime = function() return wall end } }

local STATES = { BLIND_SELECT = 1, SELECTING_HAND = 3, SHOP = 5, MENU = 11, SPLASH = 12 }
_G.G = {
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
_G.SMODS = { Mods = {} }

local check, done = require("tests.helpers").harness("clock-stalls")
local Utils = require("util.utils")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local Orch = require("core.orchestrator")
local Lifecycle = require("core.neuro_lifecycle")
local ForceState = require("core.force_state")
local Receipt = require("core.action_receipt")
local Staging = require("core.staging")
local S = require("hud.state")

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
  G.NEURO = {
    enabled = true, persona = "neuro", llm_paused = false, run_generation = 1,
    state = "SHOP", reserved_dollars = 0, decision_serial = 1, state_enter_serial = 1,
    _decision_windows = {}, once_serials = {},
    update = function() end, send_context = function() end,
    send_action_result = function() end,
    register_actions = function() end, unregister_actions = function() end,
    force_actions = function() end,
  }
  S.state_changed_at = G.TIMERS.REAL
  S.state_changed_at_game = 0
  Receipt.reset("test")
  Staging.reset_run_state()
  ForceState.clear_force_state()
  ForceState.clear_cancel_pending()
  Orch.reset_run_state()
  return G.NEURO
end

-- G.FUNCS.go_to_menu queues Game:main_menu, which sets both timers to 12 (dump game.lua:1556-1558)
-- before prep_stage changes G.STATE; the mod's run reset hangs on G.FUNCS.start_run, which is the
-- last thing to happen on the way back into a run and is never reached on the Esc-menu route at all.
local REWIND_TO = 12

do
  fresh_neuro()
  advance(2400)
  Lifecycle.mark_action_at()
  local epoch_before = Utils.clock_epoch()

  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  check("every stamp taken during the run is now in the future",
    (G.NEURO.last_action_at or 0) > Utils.gate_now("action_cooldown"),
    tostring(G.NEURO.last_action_at) .. " vs " .. Utils.gate_now("action_cooldown"))
  check("and the action gate is shut with nothing that can open it",
    Orch._neuro_can_act() == false)

  Orch._step_clock_rewind()
  check("the rewind is observed exactly once", Utils.clock_epoch() == epoch_before + 1,
    Utils.clock_epoch() .. " vs " .. epoch_before)
  check("and it runs the run reset the engine never announces",
    G.NEURO.last_action_at == nil, tostring(G.NEURO.last_action_at))
  check("so the action gate is open again on the menu", Orch._neuro_can_act() == true)

  Orch._step_clock_rewind()
  check("a second frame at the same clock does not reset again",
    Utils.clock_epoch() == epoch_before + 1)
end

do
  fresh_neuro()
  advance(2400)
  Lifecycle.mark_action_at()
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  advance(600)
  check("ten minutes on the menu do not clear it by themselves",
    Orch._neuro_can_act() == false)
  Orch._step_clock_rewind()
  check("the rewind step does", Orch._neuro_can_act() == true)
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
  Lifecycle.mark_action_at()
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

local function stall_window()
  return Utils.gate_seconds("force_stall", "NEURO_FORCE_STALL")
end

do
  fresh_neuro()
  G.NEURO.reserved_dollars = 7
  Orch._step_force_stall()
  advance(stall_window() + 1)
  check("the stall watchdog releases an ownerless dollar reservation",
    Orch._step_force_stall() == true and G.NEURO.reserved_dollars == 0)
end

do
  fresh_neuro()
  advance(5)
  check("a quiet frame does not fire on its own", Orch._step_force_stall() == false)
  advance(stall_window() - 0.5)
  check("nor just before the window is up", Orch._step_force_stall() == false)
  advance(1)
  local fired = Orch._step_force_stall()
  check("with no window, no force and nothing staged the stall watchdog fires", fired == true)
  check("and it marks the force dirty so arming tries again",
    G.NEURO.force_dirty == true and G.NEURO.force_dirty_at ~= nil)
end

do
  fresh_neuro()
  advance(2)
  Orch._step_force_stall()
  advance(stall_window() - 1)
  S.state_changed_at = G.TIMERS.REAL
  Orch._step_force_stall()
  advance(2)
  check("activity restarts the window rather than being counted as silence",
    Orch._step_force_stall() == false)
end

do
  fresh_neuro()
  advance(2)
  Orch._step_force_stall()
  ForceState.arm("SHOP", { "reroll_shop" }, { reroll_shop = true }, nil, { context = "c" })
  advance(stall_window() + 2)
  check("an open window is the liveness watchdog's business, not this one",
    Orch._step_force_stall() == false)
  ForceState.clear_force_state()
end

do
  fresh_neuro()
  advance(2)
  Orch._step_force_stall()
  local r = Receipt.create({ id = "stall-1", name = "buy_from_shop",
    deadline = Receipt.now() + 600, timeout_outcome = "failed",
    probe = function() return "pending" end })
  advance(stall_window() + 2)
  check("an action still being verified is not silence either",
    Orch._step_force_stall() == false, r.phase)
  Receipt.reset("test")
end

do
  fresh_neuro()
  advance(2)
  Orch._step_force_stall()
  G.SETTINGS.paused = true
  local frozen = G.TIMERS.TOTAL
  local target = G.TIMERS.REAL + stall_window() + 1
  while G.TIMERS.REAL < target do
    G.TIMERS.REAL = G.TIMERS.REAL + 1 / 60
    wall = wall + 1 / 60
  end
  check("the game clock really is frozen for that whole stretch",
    G.TIMERS.TOTAL == frozen)
  check("the stall watchdog still fires while the game is paused",
    Orch._step_force_stall() == true)
  G.SETTINGS.paused = false
end

do
  fresh_neuro()
  advance(2)
  Orch._step_force_stall()
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  check("the frame the clock jumps backwards is not treated as a stall",
    Orch._step_force_stall() == false)
  advance(stall_window() + 1)
  check("and the bound still expires afterwards rather than never",
    Orch._step_force_stall() == true)
end

local function open_receipt(id)
  return Receipt.create({ id = id, name = "buy_from_shop",
    deadline = Receipt.now() + 3600, timeout_outcome = "failed",
    probe = function() return "pending" end })
end

do
  fresh_neuro()
  advance(2)
  ForceState.arm("SHOP", { "reroll_shop" }, { reroll_shop = true }, nil, { context = "c" })
  ForceState.mark_sent()
  open_receipt("hoist-1")
  G.NEURO.state = "BLIND_SELECT"
  G.STATE = STATES.BLIND_SELECT
  Orch._step_force_arming("BLIND_SELECT", Utils.now())
  check("a state move still supersedes the offer while a receipt is active",
    ForceState.window_is_open() == false, tostring(G.NEURO.force_last_result))
  Receipt.reset("test")
end

do
  fresh_neuro()
  advance(2)
  ForceState.arm("SHOP", { "reroll_shop" }, { reroll_shop = true }, nil, { context = "c" })
  ForceState.mark_sent()
  ForceState.acknowledge_offer()
  check("the offer is acknowledged and waiting", ForceState.reask_due() == false)
  open_receipt("hoist-2")
  advance(Utils.gate_seconds("ack_idle_reask", "NEURO_ACK_IDLE_REASK") + 1)
  check("the ack-idle re-ask is due", ForceState.reask_due() == true)
  Orch._step_force_arming("SHOP", Utils.now())
  check("and it fires while a receipt is active", ForceState.reask_due() == false)
  Receipt.reset("test")
end

do
  fresh_neuro()
  advance(2)
  ForceState.arm("SHOP", { "reroll_shop" }, { reroll_shop = true }, nil, { context = "c" })
  ForceState.mark_sent()
  ForceState.invalidate("test")
  check("the withdrawn offer is quarantined", ForceState.cancel_pending() ~= nil)
  open_receipt("hoist-3")
  advance(Utils.gate_seconds("cancel_settle", "NEURO_FORCE_CANCEL_IDLE") + 0.5)
  Orch._step_force_arming("SHOP", Utils.now())
  check("the quarantine still settles itself while a receipt is active",
    G.NEURO.force_cancel_pending == nil)
  Receipt.reset("test")
end

for _, phase in ipairs({ "prepared", "acknowledged", "executing" }) do
  fresh_neuro()
  advance(2)
  local r = Receipt.create({ id = "deadline-" .. phase, name = "buy_from_shop",
    deadline = Receipt.now() + 4, timeout_outcome = "failed",
    probe = function() return "pending" end })
  if phase ~= "prepared" then Receipt.transition(r, "acknowledged") end
  if phase == "executing" then Receipt.transition(r, "executing") end
  advance(6)
  local completed = Receipt.update(Receipt.now(), nil)
  check("a receipt stranded in " .. phase .. " past its deadline is still bounded",
    #completed == 1 and Receipt.has_active() == false, r.phase)
end

do
  fresh_neuro()
  advance(2400)
  local r = Receipt.create({ id = "rewind-receipt", name = "buy_from_shop",
    deadline = Receipt.now() + 4, timeout_outcome = "failed",
    probe = function() return "pending" end })
  Receipt.transition(r, "acknowledged")
  G.TIMERS.REAL, G.TIMERS.TOTAL = REWIND_TO, REWIND_TO
  Receipt.update(Receipt.now(), nil)
  check("a rewind re-bases the deadline instead of pushing it out of reach",
    r.deadline <= Receipt.now() + 4 and Receipt.has_active() == true, r.deadline)
  advance(6)
  Receipt.update(Receipt.now(), nil)
  check("so it still times out after its own length", Receipt.has_active() == false)
end

-- The boss banner sets blind.block_play for the length of its animation (dump blind.lua:248), so
-- play_hand is illegal while the offer is built and legal again a few seconds later.
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

  ForceState.arm("SELECTING_HAND", { "discard_hand" }, { discard_hand = true }, nil, { context = "c" })
  ForceState.mark_sent()
  check("the offer named discard_hand alone", ForceState.window_is_open() == true)

  advance(0.5)
  check("an unchanged board does not re-arm", Orch._step_force_widened("SELECTING_HAND") == nil)

  G.GAME.blind.block_play = nil
  advance(0.5)
  local widened = Orch._step_force_widened("SELECTING_HAND")
  check("the banner clearing is noticed as the offer widening", widened == "play_hand", tostring(widened))
  check("and the stale offer is withdrawn rather than left standing",
    ForceState.window_is_open() == false, tostring(G.NEURO.force_last_result))
  check("so arming rebuilds it", G.NEURO.force_dirty == true)
end

do
  selecting_hand_world()
  G.GAME.blind.block_play = nil
  ForceState.arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, nil, { context = "c" })
  ForceState.mark_sent()
  advance(0.5)
  Orch._step_force_widened("SELECTING_HAND")
  G.GAME.current_round.discards_left = 0
  advance(0.5)
  check("an offer that narrowed is not torn down",
    Orch._step_force_widened("SELECTING_HAND") == nil and ForceState.window_is_open() == true)
end

do
  selecting_hand_world()
  ForceState.arm("SELECTING_HAND", { "discard_hand" }, { discard_hand = true }, nil, { context = "c" })
  ForceState.mark_sent()
  advance(0.5)
  Orch._step_force_widened("SELECTING_HAND")
  G.GAME.blind.block_play = nil
  advance(0.5)
  Orch._step_force_widened("SELECTING_HAND")
  ForceState.clear_cancel_pending()
  ForceState.arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, nil, { context = "c" })
  ForceState.mark_sent()
  advance(0.5)
  Orch._step_force_widened("SELECTING_HAND")
  advance(0.5)
  check("the re-armed offer is not torn down again by the same widening",
    Orch._step_force_widened("SELECTING_HAND") == nil and ForceState.window_is_open() == true)
end

done()
