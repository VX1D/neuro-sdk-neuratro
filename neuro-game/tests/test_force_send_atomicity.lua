_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-send-atomicity")

local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7, MENU = 11 }

local joker = require("tests.helpers").flat_mult_joker

_G.G = {
  STATE = STATES.BLIND_SELECT, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
  GAME = { dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 4,
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
      blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
    blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
    hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
  P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
    bl_big = { key = "bl_big", name = "Big Blind" },
    bl_club = { key = "bl_club", name = "The Club" } },
  jokers = { cards = { joker("j_joker", "Joker") }, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  deck = { cards = {} },
  shop_jokers = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {}, config = { card_limit = 1 } },
  shop_booster = { cards = {}, config = { card_limit = 2 } },
  FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
    select_blind = function() end },
  CONTROLLER = { locks = {} },
  blind_select = {},
  E_MANAGER = { queues = {} },
}

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Tuning = require("core.config")

local forces, events = {}, {}
local doubles, last_window = 0, nil

G.NEURO = {
  enabled = true, persona = "neuro", run_generation = 1,
  dispatcher = Dispatcher, actions = Actions,
  _decision_windows = {}, once_serials = {}, decision_serial = 1,
  state_enter_serial = 1, reserved_dollars = 0,
  update = function() end,
  send_context = function() end,
  send_action_result = function() end,
}
function G.NEURO:register_actions(defs)
  local names = {}
  for _, d in ipairs(defs or {}) do names[#names + 1] = d.name end
  events[#events + 1] = { kind = "reg", names = names }
end
function G.NEURO:unregister_actions(names)
  local copy = {}
  for i, v in ipairs(names or {}) do copy[i] = v end
  events[#events + 1] = { kind = "unreg", names = copy }
end
function G.NEURO:force_actions(ctx, query, actions)
  local window = require("core.force_state").window()
  if last_window and last_window ~= window and last_window.phase ~= "ended" then
    doubles = doubles + 1
  end
  last_window = window
  forces[#forces + 1] = { t = G.TIMERS.REAL, context = tostring(ctx), query = tostring(query),
    state = G.NEURO.state, actions = table.concat(actions, ",") }
end

require("core.transition_guard").reset()
local Orch = require("core.orchestrator")
local FS = require("core.force_state")
local HudState = require("hud.state")

local function frame()
  G.TIMERS.REAL = G.TIMERS.REAL + 0.1
  local ok, err = pcall(Orch.update, 0.1)
  if not ok then print("ORCH ERR: " .. tostring(err)) end
end

local arm_frame, wire_frame, gap_frames = nil, nil, 0
for i = 1, 300 do
  frame()
  if G.NEURO.force_inflight then
    arm_frame = arm_frame or i
    if #forces == 0 then gap_frames = gap_frames + 1 end
  end
  if #forces > 0 then wire_frame = wire_frame or i break end
end
check("the first decision reaches the wire", #forces == 1, #forces)
check("the window opens in the frame its force ships", arm_frame ~= nil and arm_frame == wire_frame,
  tostring(arm_frame) .. "/" .. tostring(wire_frame))
check("no frame holds an in-flight window over an empty wire", gap_frames == 0, gap_frames)
check("the in-flight window is stamped as sent",
  FS.window().phase == "forced" and G.NEURO.force_sent_at ~= nil)

FS.clear_force_state()
Orch.reset_run_state()
G.NEURO.force_dirty = true
G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
HudState.state_changed_at = G.TIMERS.REAL - 100
local before_a2 = #forces
Orch._step_force_arming("BLIND_SELECT", G.TIMERS.REAL)
check("the arming step ships its own force, no follow-up step required",
  #forces == before_a2 + 1, #forces - before_a2)
check("arming leaves no window waiting for a sender",
  G.NEURO.force_inflight == true and FS.window().phase == "forced")

FS.clear_force_state()
Orch.reset_run_state()
G.NEURO.force_dirty = true
G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
HudState.state_changed_at = G.TIMERS.REAL - 100
local healthy_force_actions = G.NEURO.force_actions
G.NEURO.force_actions = function() error("injected force transport throw") end
local ok_throw = pcall(Orch._step_force_arming, "BLIND_SELECT", G.TIMERS.REAL)
check("a thrown force transport callback is contained", ok_throw == true)
check("a force that never left the process is not left in flight",
  G.NEURO.force_inflight == false and not require("core.force_window").is_open(FS.window()))
G.NEURO.force_actions = healthy_force_actions
G.TIMERS.REAL = G.TIMERS.REAL + FS.CANCEL_SETTLE
FS.cancel_pending(G.TIMERS.REAL)

local STALE_Q = "STALE-QUERY-MARKER"
local function stale_payload(query)
  return { context = "STALE-CONTEXT", query = query, actions = { "select_blind" }, priority = "low" }
end

FS.clear_force_state()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
check("a window can hold a payload that has not been sent",
  FS.arm("BLIND_SELECT", { "select_blind" }, { select_blind = true }, G.TIMERS.REAL,
    stale_payload(STALE_Q)) == true)
G.STATE = STATES.SHOP
local before_b = #forces
frame()
local leaked = false
for i = before_b + 1, #forces do
  if forces[i].query == STALE_Q then leaked = true end
end
check("a payload built for the previous screen never reaches the wire", leaked == false)
local w_after = FS.window()
check("the undelivered window does not stay in flight",
  G.NEURO.force_inflight == false
    or (type(w_after) == "table" and w_after.state == "SHOP"),
  tostring(G.NEURO.force_inflight) .. "/" .. tostring(type(w_after) == "table" and w_after.state))

FS.clear_force_state()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
G.NEURO.llm_paused = true
local PAUSED_Q = "PAUSED-QUERY-MARKER"
FS.arm("BLIND_SELECT", { "select_blind" }, { select_blind = true }, G.TIMERS.REAL,
  stale_payload(PAUSED_Q))
local before_c = #forces
for _ = 1, 600 do frame() end
G.GAME.dollars = 999
check("nothing is sent while the operator holds the pause", #forces == before_c, #forces - before_c)
check("the pause does not freeze a window in flight", G.NEURO.force_inflight == false)
G.NEURO.llm_paused = false
G.NEURO.force_dirty = true
G.NEURO.force_dirty_at = G.TIMERS.REAL - 100
for _ = 1, 300 do
  frame()
  if #forces > before_c then break end
end
check("the model is asked again once the pause lifts", #forces > before_c, #forces - before_c)
local after_pause = forces[#forces]
check("what ships is built after the pause, not the payload parked before it",
  after_pause ~= nil and after_pause.query ~= PAUSED_Q, after_pause and after_pause.query)

FS.clear_force_state()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
frame()
local open_names = { "select_blind", "sell_card", "set_plan" }
FS.arm("BLIND_SELECT", open_names,
  { select_blind = true, sell_card = true, set_plan = true }, G.TIMERS.REAL,
  stale_payload("OPEN-QUERY"))
FS.mark_sent(G.TIMERS.REAL)
G.STATE = STATES.SHOP
local shop_valid = Actions.get_valid_actions_for_state("SHOP")
local shop_set = {}
for _, n in ipairs(shop_valid) do shop_set[n] = true end
local mark = #events
local moved_at = G.TIMERS.REAL
frame()
local stripped = {}
for _, n in ipairs(open_names) do
  if shop_set[n] then stripped[n] = true end
end
local last_reg, unregs = nil, 0
for i = mark + 1, #events do
  if events[i].kind == "unreg" then unregs = unregs + 1 else last_reg = i end
end
check("the new screen does want names the dead offer held", next(stripped) ~= nil)
check("closing the stale force explicitly withdraws its exact names before replacement",
  unregs >= 1, unregs)
check("the same frame registers the new screen's set", last_reg ~= nil, tostring(last_reg))
local unreg_before_reg = false
if last_reg then
  for i = mark + 1, last_reg - 1 do
    if events[i].kind == "unreg" then
      local covers = false
      for _, n in ipairs(events[i].names) do
        if stripped[n] then covers = true end
      end
      if covers then unreg_before_reg = true break end
    end
  end
end
check("the withdrawal precedes the shared names' return to the register", unreg_before_reg,
  tostring(unreg_before_reg))

local settle_mark = #events
local deadline = G.TIMERS.REAL + FS.CANCEL_SETTLE + 1
local restored = {}
while G.TIMERS.REAL < deadline do
  frame()
  for i = settle_mark + 1, #events do
    if events[i].kind ~= "unreg" then
      for _, n in ipairs(events[i].names) do
        if stripped[n] then restored[n] = true end
      end
    end
  end
  settle_mark = #events
end
local covered = true
for n in pairs(stripped) do
  if not restored[n] then covered = false end
end
check("and every one of them is back once it has settled", covered)
check("the refresh does not wait out the entry cooldown",
  (G.TIMERS.REAL - moved_at) < Tuning.get("NEURO_ENTRY_CD_SHOP"),
  string.format("%.1f", G.TIMERS.REAL - moved_at))

local Receipt = require("core.action_receipt")
Receipt.reset("atomicity_setup")
FS.clear_force_state()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
frame()
FS.arm("BLIND_SELECT", open_names,
  { select_blind = true, sell_card = true, set_plan = true }, G.TIMERS.REAL,
  stale_payload("HELD-QUERY"))
FS.mark_sent(G.TIMERS.REAL)
Receipt.create({ id = "atomicity-1", name = "select_blind", probe = function() return "pending" end,
  run_generation = 1, started_at = G.TIMERS.REAL, deadline = G.TIMERS.REAL + 1000 })
G.STATE = STATES.SHOP
local mark_d3 = #events
frame()
check("the receipt is still open across the move", Receipt.has_active() == true)
local shop_only = false
for i = mark_d3 + 1, #events do
  if events[i].kind == "reg" then
    for _, n in ipairs(events[i].names) do
      if n == "reroll_shop" then shop_only = true end
    end
  end
end
check("a pending action result does not postpone the new screen's action set", shop_only)
Receipt.reset("atomicity_done")

--  SPECIFICATION.md:131-137 -- one unanswered force at a time, whatever the send path does
local bridge = { results = {} }
function bridge:send_action_result(id, ok, msg, reason)
  self.results[#self.results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
end
function bridge:send_context() end
function bridge:is_transition_cooldown() return false end
function bridge:register_actions() end

FS.clear_force_state()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
local plan_n = 0
local answers = 0
local before_e = #forces
for _ = 1, 1200 do
  frame()
  if G.NEURO.force_inflight then
    plan_n = plan_n + 1
    answers = answers + 1
    require("tests.helpers").stage_registered(nil, { "set_plan" })
    Dispatcher.handle_message({ command = "action", run_generation = 1,
      data = { id = "plan-" .. plan_n, name = "set_plan",
        data = { hand_plan = "p" .. plan_n, build_plan = "p", money_plan = "p" } } }, bridge)
  end
end
check("the run produced forces to measure", #forces > before_e, #forces - before_e)
check("no force ships while an earlier window is still open", doubles == 0, doubles)
check("forces never outrun answers", (#forces - before_e) <= answers + 1,
  string.format("%d forces / %d answers", #forces - before_e, answers))

done()
