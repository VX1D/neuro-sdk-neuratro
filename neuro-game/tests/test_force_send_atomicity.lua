require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("force-send-atomicity")

local STATES = require("tests.engine_cards").states()

local joker = H.flat_mult_joker

H.orch_board({ kind = "club", state = "BLIND_SELECT", states = STATES, edit = function(g)
  g.jokers.cards = { joker("j_joker", "Joker") }
end })

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Tuning = require("core.config")
local json = require("util.neuro_json")

local forces, events = {}, {}
local canonical_catalogue = {}
local withdrawals = {}
local doubles, last_window = 0, nil

G.NEURO = H.orch_neuro({ dispatcher = Dispatcher, actions = Actions, send_context = "written",
  send_action_result = "noop" })
function G.NEURO:register_actions(defs)
  local names = {}
  for _, d in ipairs(defs or {}) do
    names[#names + 1] = d.name
    canonical_catalogue[d.name] = true
  end
  events[#events + 1] = { kind = "reg", names = names }
  return true
end
function G.NEURO:withdraw_actions(names)
  local copy = {}
  for i, v in ipairs(names or {}) do copy[i] = v end
  withdrawals[#withdrawals + 1] = copy
  return true
end
function G.NEURO:force_actions(ctx, query, actions)
  local window = G.NEURO.force_window
  if last_window and last_window ~= window and last_window.phase ~= "ended" then
    doubles = doubles + 1
  end
  last_window = window
  forces[#forces + 1] = { t = G.TIMERS.REAL, context = tostring(ctx), query = tostring(query),
    state = G.NEURO.state, actions = table.concat(actions, ",") }
  return true
end

require("core.validate").reset_run_state()
local Orch = require("core.orchestrator")
local Window = require("core.window")
local HudState = require("hud.state")
local function in_flight() return Window.current() ~= nil end

local function frame()
  G.TIMERS.REAL = G.TIMERS.REAL + 0.1
  local ok, err = pcall(Orch.update, 0.1)
  if not ok then print("ORCH ERR: " .. tostring(err)) end
end

local arm_frame, wire_frame, gap_frames = nil, nil, 0
for i = 1, 300 do
  frame()
  if in_flight() then
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
  G.NEURO.force_window.phase == "forced" and G.NEURO.force_window.sent_at ~= nil)

Window.reset()
Orch.reset_run_state()
HudState.state_changed_at = G.TIMERS.REAL - 100
local before_a2 = #forces
Window._test.arm("BLIND_SELECT")
check("the arming step ships its own force, no follow-up step required",
  #forces == before_a2 + 1, #forces - before_a2)
check("arming leaves no window waiting for a sender",
  in_flight() and G.NEURO.force_window.phase == "forced")

Window.reset()
Orch.reset_run_state()
local healthy_force_actions = G.NEURO.force_actions
G.NEURO.force_actions = function() error("injected force transport throw") end
local ok_throw = pcall(Window._test.arm, "BLIND_SELECT")
check("a thrown force transport callback is contained", ok_throw == true)
check("a force that never left the process is not left in flight", not in_flight())
G.NEURO.force_actions = healthy_force_actions

Window.reset()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
G.NEURO.llm_paused = true
local before_c = #forces
for _ = 1, 600 do frame() end
check("nothing is sent while the operator holds the pause", #forces == before_c, #forces - before_c)
check("the pause does not freeze a window in flight", not in_flight())
G.NEURO.llm_paused = false
for _ = 1, 300 do
  frame()
  if #forces > before_c then break end
end
check("the model is asked again once the pause lifts", #forces > before_c, #forces - before_c)

Window.reset()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
frame()
local open_names = { "select_blind", "sell_card", "record_plan" }
local stale_window = require("tests.helpers").open_force("BLIND_SELECT", open_names)
local withdraw_mark = #withdrawals
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
local last_reg = #events > mark and #events or nil
local withdrawn = withdrawals[withdraw_mark + 1]
local function contains_all(list)
  if type(list) ~= "table" or #list ~= #open_names then return false end
  local seen = {}
  for _, name in ipairs(list) do seen[name] = true end
  for _, name in ipairs(open_names) do
    if not seen[name] then return false end
  end
  return true
end
local catalogue_keeps_old_offer = true
for _, name in ipairs(open_names) do
  catalogue_keeps_old_offer = catalogue_keeps_old_offer and canonical_catalogue[name] == true
end
local catalogue_has_shop_actions = true
for _, name in ipairs(shop_valid) do
  catalogue_has_shop_actions = catalogue_has_shop_actions and canonical_catalogue[name] == true
end
check("the new screen does want names the dead offer held", next(stripped) ~= nil)
check("a sent stale force is withdrawn by unregistering its whole offer, tools included (README.md:27)",
  contains_all(withdrawn) and stale_window.phase == "ended",
  tostring(stale_window.phase) .. "/" .. table.concat(withdrawn or {}, ","))
check("the old force window is closed before the next offer", not in_flight())
check("the canonical action catalogue is additive across the state move",
  catalogue_keeps_old_offer and catalogue_has_shop_actions,
  string.format("old=%s shop=%s", tostring(catalogue_keeps_old_offer),
    tostring(catalogue_has_shop_actions)))
check("the stable catalogue is not re-registered for a state-only move",
  last_reg == nil and catalogue_has_shop_actions, tostring(last_reg))
check("the refresh does not wait out the entry cooldown",
  (G.TIMERS.REAL - moved_at) < Tuning.get("NEURO_ENTRY_CD_SHOP"),
  string.format("%.1f", G.TIMERS.REAL - moved_at))
Window.reset()

local Receipt = require("core.action_result")
local Execute = require("core.execute")
Window.reset()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
frame()
Execute.admit({ id = "atomicity-1", name = "select_blind", data = {}, bridge = G.NEURO,
  exec = function()
    return Receipt.create({ id = "atomicity-1", name = "select_blind", probe = function() return "pending" end,
      run_generation = 1, started_at = G.TIMERS.REAL, deadline = G.TIMERS.REAL + 1000 })
  end }, false)
G.STATE = STATES.SHOP
local mark_d3 = #events
frame()
check("the action is still being verified across the move", Execute.busy() == "verifying")
local shop_only = false
for i = mark_d3 + 1, #events do
  if events[i].kind == "reg" then
    for _, n in ipairs(events[i].names) do
      if n == "reroll_shop" then shop_only = true end
    end
  end
end
check("a pending action result does not postpone the stable action catalogue",
  not shop_only and canonical_catalogue.reroll_shop == true,
  tostring(shop_only) .. "/" .. tostring(canonical_catalogue.reroll_shop))
Execute.abort("test")

local bridge = H.stub_bridge({ results = {},
  send_action_result = H.result_log("results", { "id", "ok", "msg", "reason" }),
  send_context = H.written_context, is_transition_cooldown = "false", register_actions = "noop" })

Window.reset()
G.STATE = STATES.BLIND_SELECT
G.NEURO.state = "BLIND_SELECT"
local plan_n = 0
local answers = 0
local before_e = #forces
for _ = 1, 1200 do
  frame()
  if in_flight() then
    plan_n = plan_n + 1
    answers = answers + 1
    require("tests.helpers").stage_registered(nil, { "record_plan" })
    Dispatcher.handle_message({ command = "action",
      data = { id = "plan-" .. plan_n, name = "record_plan",
        data = json.encode({ hand_plan = "p" .. plan_n, build_plan = "p", money_plan = "p" }) } }, bridge)
  end
end
check("the run produced forces to measure", #forces > before_e, #forces - before_e)
check("no force ships while an earlier window is still open", doubles == 0, doubles)
check("forces never outrun answers", (#forces - before_e) <= answers + 1,
  string.format("%d forces / %d answers", #forces - before_e, answers))

done()
