_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("force-cadence")

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
  FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
    select_blind = function() end },
  CONTROLLER = { locks = {} },
  blind_select = {},
  E_MANAGER = { queues = {} },
}

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Router = require("force.force_router")
local Tuning = require("core.config")

local forces = {}
G.NEURO = {
  enabled = true, persona = "neuro", run_generation = 1,
  dispatcher = Dispatcher, actions = Actions,
  _decision_windows = {}, once_serials = {}, decision_serial = 1,
  state_enter_serial = 1, reserved_dollars = 0,
  update = function() end,
  register_actions = function() end,
  unregister_actions = function() end,
  send_context = function() end,
  send_action_result = function() end,
}
function G.NEURO:force_actions(_ctx, _query, actions)
  forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
end

require("core.transition_guard").reset()
local Orch = require("core.orchestrator")

local bridge = { results = {} }
function bridge:send_action_result(id, ok, msg, reason)
  self.results[#self.results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
end
function bridge:send_context() end
function bridge:is_transition_cooldown() return false end
function bridge:register_actions() end

local function tick_for(seconds)
  for _ = 1, math.floor(seconds / 0.1) do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.1
    local ok, err = pcall(Orch.update, 0.1)
    if not ok then print("ORCH ERR: " .. tostring(err)) break end
  end
end

local plan_n = 0
local function answer_set_plan(text)
  plan_n = plan_n + 1
  require("tests.helpers").stage_registered(nil, { "record_plan" })
  Dispatcher.handle_message({ command = "action", run_generation = 1,
    data = { id = "plan-" .. plan_n, name = "record_plan",
      data = { hand_plan = text, build_plan = text, money_plan = text } } }, bridge)
  return bridge.results[#bridge.results]
end

--  SPECIFICATION.md:131-137 -- one force at a time; a window opens only when none is in flight
tick_for(10)
check("the first decision opens one window", #forces == 1)
check("the window is in flight", G.NEURO.force_inflight == true)

local before = #forces
tick_for(30)
check("no second window opens while one is in flight (SPEC:135-137)", #forces == before)

--  SPECIFICATION.md:184,188 -- an in-force action that changes nothing still answers success=true
local r1 = answer_set_plan("plan one")
check("a NON_PROGRESS answer inside a force reports success=true (SPEC:188)", r1.ok == true)
check("answering ends the window", G.NEURO.force_inflight == false)

before = #forces
tick_for(30)
check("an ended window is followed by a new one (Unity/USAGE.md:149)", #forces == before + 1)

local r2 = answer_set_plan("plan one")
check("the repeated answer also reports success=true", r2.ok == true)
before = #forces
tick_for(60)
check("a repeated decision still gets a force -- no starvation", #forces > before)

for i = 1, 5 do
  answer_set_plan("repeated plan " .. i)
  tick_for(30)
end
local last = forces[#forces]
check("repeated windows don't lose the non-progress action",
  last and last.actions:find("record_plan") ~= nil, last and last.actions)
check("repeated windows still carry the progress action",
  last and last.actions:find("select_blind") ~= nil, last and last.actions)

before = #forces
local answers = 0
for _ = 1, 2000 do
  G.TIMERS.REAL = G.TIMERS.REAL + 0.1
  pcall(Orch.update, 0.1)
  if G.NEURO.force_inflight then
    answers = answers + 1
    answer_set_plan("plan one")
  end
end
check("a repeating no-op answer cannot flood forces", (#forces - before) <= answers,
  string.format("%d forces / %d answers", #forces - before, answers))

done()
