love = { timer = { getTime = function() return _CLOCK or 0 end }, event = { quit = function() end } }
_CLOCK = 1000

local STATES = { SELECTING_HAND = 1, GAME_OVER = 4, MENU = 11, SHOP = 5, BLIND_SELECT = 7 }

local function fresh_G(prev_state, sent_ago)
  local captured = { force_sent = false, force_actions = nil }
  local NEURO = {
    enabled = true, persona = "evil",
    force_inflight = true, force_state = "SELECTING_HAND",
    force_sent_at = _CLOCK - (sent_ago or 0),
    force_dirty = false,
    state = prev_state,
    llm_paused = nil,
    last_action_at = 0,
    update = function() end,
    send_context = function() end,
    send_startup = nil,
  }
  function NEURO:force_actions(ctx, query, actions) captured.force_sent = true; captured.force_actions = actions end
  local G = {
    STATE = STATES.MENU, STATES = STATES, STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 },
    GAME = { current_round = {}, dollars = 4, round_resets = { ante = 1 } },
    FUNCS = {}, OVERLAY_MENU = nil, screenwipe = nil,
    NEURO = NEURO, hand = { cards = {} }, jokers = { cards = {} }, consumeables = { cards = {} },
    TIMERS = { REAL = _CLOCK },
  }
  return G, captured, NEURO
end

_G.G = select(1, fresh_G("SELECTING_HAND"))
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions
local Orch = require("core.orchestrator")

local function run(prev_state, sent_ago, label)
  local G2, cap, N = fresh_G(prev_state, sent_ago)
  G2.NEURO.dispatcher = Dispatcher
  G2.NEURO.actions = Actions
  _G.G = G2
  pcall(Orch.update, 0.1)
  print(string.format("[%s] prev_state=%s sent_ago=%ss -> inflight_after=%s dirty=%s",
    label, tostring(prev_state), tostring(sent_ago), tostring(N.force_inflight), tostring(N.force_dirty)))
  return N.force_inflight, N.force_dirty
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
check("B: re-forced (dirty)", dB == true)
local iC = run("MENU", 999, "C: force_sent_at far in the past (age alone is not a trigger)")
check("C: stale inflight cleared by the state change, not by force age", iC == false)
do
  local Enforce = require("core.enforce")
  local saved = Enforce.pre_action
  Enforce.pre_action = function() return false, "not_in_state name=play_hand state=MENU", false end
  local N = { persona = "evil", enabled = true, dispatcher = Dispatcher, actions = Actions }
  _G.G = { STATE = STATES.MENU, STATES = STATES, GAME = {}, NEURO = N }
  require("core.force_state").arm("MENU", { "open_run_setup" }, { open_run_setup = true }, 1)
  Dispatcher.handle_message({ command = "action", data = { id = "t1", name = "play_hand", data = {} } },
    { send_action_result = function() end, register_actions = function() end })
  Enforce.pre_action = saved
  print("[REJECT] out-of-set play_hand rejected at MENU -> inflight_after=" .. tostring(N.force_inflight))
  check("reject-keepforce: guard-rejected out-of-set answer leaves the force open", N.force_inflight == true)
  check("reject-keepforce: out-of-set rejection does not re-arm a second force", N.force_dirty ~= true)
end

do
  local N = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }
  _G.G = { STATE = STATES.GAME_OVER, STATES = STATES, GAME = { round_resets = { ante = 3 } },
    OVERLAY_MENU = { joker_unlock_table = "j_joker" }, NEURO = N, FUNCS = {} }
  local f = Dispatcher.get_force_for_state("GAME_OVER")
  local has_exit = false
  for _, a in ipairs((f or {}).actions or {}) do if a == "exit_overlay_menu" then has_exit = true end end
  print("[UNLOCK] gameover unlock popup (hold+recovery) -> forces exit_overlay_menu=" .. tostring(has_exit))
  check("unlock popup at GAME_OVER is forced dismissable through hold/recovery", has_exit)
end

local StateKinds = require("core.state_kinds")
local function overlay_with(ids)
  return { get_UIE_by_ID = function(_, id) return ids[id] and {} or nil end }
end

do
  _G.G = { STATE = STATES.GAME_OVER, STATES = STATES, GAME = { round_resets = { ante = 3 } },
    OVERLAY_MENU = overlay_with({}), NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {} }
  local f = Dispatcher.get_force_for_state("GAME_OVER")
  local has_exit = false
  for _, a in ipairs((f or {}).actions or {}) do if a == "exit_overlay_menu" then has_exit = true end end
  print("[STACK] non-unlock notification over GAME_OVER -> forces exit_overlay_menu=" .. tostring(has_exit))
  check("stacked non-unlock overlay at GAME_OVER is forced dismissable", has_exit)
end

do
  _G.G = { STATE = STATES.GAME_OVER, STATES = STATES, GAME = { won = false, round_resets = { ante = 3 } },
    OVERLAY_MENU = overlay_with({ from_game_over = true }), NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {} }
  local f = Dispatcher.get_force_for_state("GAME_OVER")
  local has_exit, has_setup = false, false
  for _, a in ipairs((f or {}).actions or {}) do
    if a == "exit_overlay_menu" then has_exit = true end
    if a == "open_run_setup" then has_setup = true end
  end
  print("[PROG] game-over progression screen -> NOT dismissed via exit_overlay_menu=" .. tostring(not has_exit))
  check("game-over progression screen is not force-dismissed (no soft-loop)", not has_exit)
  check("game-over progression screen offers open_run_setup (no soft-hang)", has_setup)
end

do
  _G.G = { STATE = STATES.SHOP, STATES = STATES, GAME = { won = true, round_resets = { ante = 8 } },
    OVERLAY_MENU = overlay_with({ from_game_won = true }), NEURO = { enabled = true, persona = "evil",
    dispatcher = Dispatcher, actions = Actions }, FUNCS = {} }
  local f = Dispatcher.get_force_for_state("SHOP")
  local has_exit = false
  for _, a in ipairs((f or {}).actions or {}) do if a == "exit_overlay_menu" then has_exit = true end end
  print("[WIN] win overlay at non-GAME_OVER state -> forces exit_overlay_menu=" .. tostring(has_exit))
  check("win screen forces exit_overlay_menu", has_exit)
end

check("is_progression_overlay: game-over screen", (function()
  _G.G = { OVERLAY_MENU = overlay_with({ from_game_over = true }) }; return StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: win screen NOT progression", (function()
  _G.G = { OVERLAY_MENU = overlay_with({ from_game_won = true }) }; return not StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: run-setup screen", (function()
  _G.G = { OVERLAY_MENU = overlay_with({ run_setup_seed = true }) }; return StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: plain notification is NOT progression", (function()
  _G.G = { OVERLAY_MENU = overlay_with({}) }; return not StateKinds.is_progression_overlay() end)())
check("is_progression_overlay: no overlay is NOT progression", (function()
  _G.G = { OVERLAY_MENU = nil }; return not StateKinds.is_progression_overlay() end)())

print(string.format("GAMEOVER_SYNTH_FAILS=%d (0 = clean) GAMEOVER_SYNTH_CHECKS=%d", fails, checks))
os.exit(fails == 0 and 0 or 1)
