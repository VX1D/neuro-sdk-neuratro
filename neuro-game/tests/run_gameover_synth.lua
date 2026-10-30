love = { timer = { getTime = function() return _CLOCK or 0 end }, event = { quit = function() end } }
_CLOCK = 1000

local STATES = require("tests.engine_cards").states()

local function fresh_G(prev_state, sent_ago)
  local captured = { force_sent = false, force_actions = nil }
  local NEURO = require("tests.helpers").started_bridge({
    enabled = true, persona = "evil",
    force_window = { id = 1, state = "SELECTING_HAND", phase = "forced", names = { "play_hand" },
      set = { play_hand = true }, legal = { play_hand = true }, sent_at = _CLOCK - (sent_ago or 0) },
    state = prev_state,
    llm_paused = nil,
    last_action_at = 0,
    update = function() end,
    send_context = function() end,
    register_actions = function() return true end,
    send_startup = nil,
  })
  function NEURO:force_actions(ctx, query, actions) captured.force_sent = true; captured.force_actions = actions end
  local G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = STATES.MENU, STATES = STATES, STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 },
    GAME = { current_round = {}, dollars = 4, round_resets = { ante = 1 } },
    FUNCS = {}, OVERLAY_MENU = nil, screenwipe = nil,
    NEURO = NEURO, hand = { cards = {} }, jokers = { cards = {} }, consumeables = { cards = {} },
    TIMERS = { REAL = _CLOCK, TOTAL = _CLOCK },
  }
  return G, captured, NEURO
end

_G.G = select(1, fresh_G("SELECTING_HAND"))
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions
local Orch = require("core.orchestrator")

local Window = require("core.window")

local function run(prev_state, sent_ago, label)
  local G2, cap, N = fresh_G(prev_state, sent_ago)
  G2.NEURO.dispatcher = Dispatcher
  G2.NEURO.actions = Actions
  _G.G = G2
  pcall(Orch.update, 0.1)
  local open = Window.current() ~= nil
  for _ = 1, 40 do
    _CLOCK = _CLOCK + 0.1
    G2.TIMERS.REAL, G2.TIMERS.TOTAL = _CLOCK, _CLOCK
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("update error: " .. tostring(err)) end
  end
  print(string.format("[%s] prev_state=%s sent_ago=%ss -> open_after=%s reforced=%s",
    label, tostring(prev_state), tostring(sent_ago), tostring(open), tostring(cap.force_sent)))
  return open, cap.force_sent
end

print("=== game-over -> MENU synth (force_inflight=SELECTING_HAND, state now MENU) ===")
local fails = 0
local checks = 0
local function check(label, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print("  FAIL " .. label) end
end
local iA = run("SELECTING_HAND", 0, "A: transition observed (state_changed)")
check("A: stale inflight cleared", iA == false)
local iB, dB = run("MENU", 0, "B: state already MENU, fresh (THE HANG)")
check("B: stale inflight cleared at MENU without waiting for stall", iB == false)
check("B: re-forced", dB == true)
local iC = run("MENU", 999, "C: force_sent_at far in the past (age alone is not a trigger)")
check("C: stale inflight cleared by the state change, not by force age", iC == false)
do
  local N = { persona = "evil", enabled = true, dispatcher = Dispatcher, actions = Actions }
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), STATE = STATES.MENU, STATES = STATES, GAME = {}, NEURO = N }
  require("tests.helpers").open_force("MENU", { "open_run_setup" })
  Dispatcher.handle_message({ command = "action", data = { id = "t1", name = "play_hand", data = {} } },
    { send_action_result = function() end, register_actions = function() end })
  print("[REJECT] out-of-set play_hand rejected at MENU -> open_after=" .. tostring(Window.current() ~= nil))
  check("reject-keepforce: a refused out-of-set answer leaves the force open", Window.current() ~= nil)
end

do
  local N = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), STATE = STATES.GAME_OVER, STATES = STATES, GAME = { round_resets = { ante = 3 } },
    OVERLAY_MENU = require("tests.helpers").unlock_overlay(1), NEURO = N, FUNCS = {} }
  local f = require("force.force_router").get_force_for_state("GAME_OVER")
  local has_exit = false
  for _, a in ipairs((f or {}).actions or {}) do if a == "exit_overlay_menu" then has_exit = true end end
  print("[UNLOCK] gameover unlock popup (hold+recovery) -> forces exit_overlay_menu=" .. tostring(has_exit))
  check("unlock popup at GAME_OVER is forced dismissable through hold/recovery", has_exit)
end

local StateKinds = require("core.state_kinds")
local overlay_with = require("tests.helpers").overlay_with

do
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), STATE = STATES.GAME_OVER, STATES = STATES, GAME = { round_resets = { ante = 3 } },
    OVERLAY_MENU = overlay_with({}), NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {} }
  local f = require("force.force_router").get_force_for_state("GAME_OVER")
  local has_exit = false
  for _, a in ipairs((f or {}).actions or {}) do if a == "exit_overlay_menu" then has_exit = true end end
  print("[STACK] non-unlock notification over GAME_OVER -> forces exit_overlay_menu=" .. tostring(has_exit))
  check("stacked non-unlock overlay at GAME_OVER is forced dismissable", has_exit)
end

do
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), STATE = STATES.GAME_OVER, STATES = STATES, GAME = { won = false, round_resets = { ante = 3 } },
    OVERLAY_MENU = overlay_with({ from_game_over = true }), NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {} }
  G.OVERLAY_MENU.config = { no_esc = true }
  local f = require("force.force_router").get_force_for_state("GAME_OVER")
  local has_exit, has_setup = false, false
  for _, a in ipairs((f or {}).actions or {}) do
    if a == "exit_overlay_menu" then has_exit = true end
    if a == "open_run_setup" then has_setup = true end
  end
  print("[PROG] game-over progression screen -> NOT dismissed via exit_overlay_menu=" .. tostring(not has_exit))
  check("game-over progression screen is not force-dismissed (no soft-loop)", not has_exit)
  check("game-over progression screen offers open_run_setup (no soft-hang)", has_setup)
end

-- The win screen is opened no_esc (state_events.lua:38) yet closes through its own Endless button (UI_definitions.lua:2987).
local function win_G(overlay)
  overlay.config = { no_esc = true }
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), STATE = STATES.ROUND_EVAL, STATES = STATES,
    GAME = { won = true, win_notified = true, win_ante = 8, round_resets = { ante = 8 } },
    OVERLAY_MENU = overlay, NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {}, round_eval = {} }
end

do
  win_G(overlay_with({ from_game_won = true, you_win_UI = true }))
  local f = require("force.force_router").get_force_for_state("ROUND_EVAL")
  local listed = table.concat((f or {}).actions or {}, ",")
  print("[WIN] win overlay over ROUND_EVAL -> force " .. listed)
  check("win screen forces exit_overlay_menu alone", listed == "exit_overlay_menu", listed)
  check("win screen: closing it is valid", Actions.is_action_valid("exit_overlay_menu"))
  check("win screen: cash_out under it is not", not Actions.is_action_valid("cash_out"))
end

do
  win_G(overlay_with({}))
  local f = require("force.force_router").get_force_for_state("ROUND_EVAL")
  check("a modal with no way to close it leaves no in-run move usable or forced",
    not Actions.is_action_valid("cash_out") and not Actions.is_action_valid("exit_overlay_menu") and f == nil,
    table.concat((f or {}).actions or {}, ","))
end

check("is_closable_overlay: the game-over screen is not closable", (function()
  _G.G = { OVERLAY_MENU = require("tests.helpers").game_over_overlay() }; return not StateKinds.is_closable_overlay() end)())
check("is_closable_overlay: an escape-closable options menu is", (function()
  _G.G = { OVERLAY_MENU = require("tests.helpers").options_overlay() }; return StateKinds.is_closable_overlay() end)())

check("is_progression_overlay: game-over screen", (function()
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), OVERLAY_MENU = overlay_with({ from_game_over = true }) }; return StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: win screen NOT progression", (function()
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), OVERLAY_MENU = overlay_with({ from_game_won = true }) }; return not StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: run-setup screen", (function()
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), OVERLAY_MENU = overlay_with({ run_setup_seed = true }) }; return StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: plain notification is NOT progression", (function()
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), OVERLAY_MENU = overlay_with({}) }; return not StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: no overlay is NOT progression", (function()
  _G.G = { P_CENTERS = require("tests.engine_centers").centers(), OVERLAY_MENU = nil }; return not StateKinds.is_progression_overlay() end)())

print(string.format("GAMEOVER_SYNTH_FAILS=%d (0 = clean) GAMEOVER_SYNTH_CHECKS=%d", fails, checks))
os.exit(fails == 0 and 0 or 1)
