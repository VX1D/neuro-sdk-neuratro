package.path = "./?.lua;;" .. package.path
love = { timer = { getTime = function() return _CLOCK or 0 end }, event = { quit = function() end } }
_CLOCK = 1000

local STATES = { SELECTING_HAND = 1, GAME_OVER = 4, MENU = 11, SHOP = 5, BLIND_SELECT = 7 }

local function fresh_G(prev_state, sent_ago)
  local captured = { force_sent = false, force_actions = nil }
  local NEURO = {
    enabled = true, persona = "evil",
    force_inflight = true, force_state = "SELECTING_HAND",
    force_sent_at = _CLOCK - (sent_ago or 0),
    force_dirty = false, last_force_fingerprint = "OLD",
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
local function check(label, cond) if not cond then fails = fails + 1; print("  FAIL " .. label) end end
local iA = run("SELECTING_HAND", 0, "A: transition observed (state_changed)")
check("A: stale inflight cleared", iA == false)
local iB, dB = run("MENU", 0, "B: state already MENU, fresh (THE HANG)")
check("B: stale inflight cleared at MENU without waiting for stall", iB == false)
check("B: re-forced (dirty)", dB == true)
local iC = run("MENU", 999, "C: past stall timeout")
check("C: stale inflight cleared", iC == false)
do
  local Enforce = require("core.enforce")
  local saved = Enforce.pre_action
  Enforce.pre_action = function() return false, "not_in_state name=play_hand state=MENU", false end
  local N = { force_inflight = true, force_state = "MENU",
    force_action_set = { setup_run = true }, force_action_names = { "setup_run" },
    persona = "evil", enabled = true, dispatcher = Dispatcher, actions = Actions }
  _G.G = { STATE = STATES.MENU, STATES = STATES, GAME = {}, NEURO = N }
  Dispatcher.handle_message({ command = "action", data = { id = "t1", name = "play_hand", data = {} } },
    { send_action_result = function() end, register_actions = function() end })
  Enforce.pre_action = saved
  print("[REJECT] out-of-set play_hand rejected at MENU -> inflight_after=" .. tostring(N.force_inflight))
  check("reject-reforce: guard-rejected out-of-set answer clears force_inflight", N.force_inflight == false)
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

print(string.format("GAMEOVER_SYNTH_FAILS=%d (0 = clean)", fails))
os.exit(fails == 0 and 0 or 1)
