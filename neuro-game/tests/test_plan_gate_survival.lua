_G.NEURO_TEST = true
local clock = 1000
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("plan-gate-survival")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local PlanGate = require("core.plan_gate")
local PlanTransaction = require("core.plan_transaction")
local PlanHandlers = require("handlers.plan_handlers")

local function card(sort_id)
  return {
    base = { value = 5, suit = "Spades" }, sort_id = sort_id,
    config = { center = { key = "c_base", set = "Default" } },
  }
end

local function bridge()
  return {
    results = {}, contexts = {},
    send_action_result = function(self, id, ok, message, reason_code)
      self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
    end,
    send_context = function(self, message) self.contexts[#self.contexts + 1] = message end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
end

local function base(opts)
  opts = opts or {}
  clock = clock + 10
  _G.G = {
    STATE = 1,
    STATES = { SELECTING_HAND = 1 },
    hand = { cards = { card(1), card(2), card(3), card(4) }, highlighted = {} },
    GAME = {
      chips = 0,
      round_resets = { ante = opts.ante or 1 },
      current_round = { hands_left = 4, discards_left = 3 },
      blind = opts.blind or { key = "bl_flint", name = "The Flint", boss = true },
      hands = { Pair = { level = 1, chips = 10, mult = 2 } },
    },
    NEURO = {
      run_generation = 7, state_enter_serial = 11, once_serials = {},
    },
    FUNCS = {
      discard_cards_from_highlighted = function()
        local selected = {}
        for _, item in ipairs(G.hand.highlighted) do selected[item] = true end
        local kept = {}
        for _, item in ipairs(G.hand.cards) do if not selected[item] then kept[#kept + 1] = item end end
        G.hand.cards, G.hand.highlighted = kept, {}
        G.GAME.current_round.discards_left = G.GAME.current_round.discards_left - 1
      end,
      play_cards_from_highlighted = function()
        local selected = {}
        for _, item in ipairs(G.hand.highlighted) do selected[item] = true end
        local kept = {}
        for _, item in ipairs(G.hand.cards) do if not selected[item] then kept[#kept + 1] = item end end
        G.hand.cards, G.hand.highlighted = kept, {}
        G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
      end,
      get_poker_hand_info = function() return "Pair" end,
    },
  }
  Dispatcher.reset_tx()
  Enforce.reset_run_state()
  require("core.force_state").arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, 1)
  require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand" })
end

local function rearm()
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SELECTING_HAND", { "play_hand", "discard_hand" },
    { play_hand = true, discard_hand = true }, 1)
  require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand" })
end

local function send(name, id, data, b)
  Dispatcher.handle_message({
    command = "action", run_generation = G.NEURO.run_generation,
    data = { id = id, name = name, data = data },
  }, b)
end

local function joined_contexts(b)
  return table.concat(b.contexts, "\n")
end

local BOSS = "Chip with pairs, keep one discard for the last hand."

do
  base()
  local b = bridge()
  send("play_hand", "p1", { indices = { 1, 2 }, plan = { boss_plan = BOSS } }, b)
  check("first play is held at the confirmation gate",
    b.results[1] and b.results[1].reason_code == "CONFIRMATION_REQUIRED",
    b.results[1] and b.results[1].reason_code)
  check("the gated attempt commits no plan yet", G.NEURO.plan == nil)
  check("the gated attempt holds its plan write",
    G.NEURO.held_plan_write ~= nil and G.NEURO.held_plan_write.values.boss_plan == BOSS,
    G.NEURO.held_plan_write and tostring(G.NEURO.held_plan_write.values.boss_plan))

  rearm()
  send("play_hand", "p2", { indices = { 1, 2 } }, b)
  check("the bare resend is not refused for a missing plan field",
    b.results[2] and b.results[2].reason_code ~= "PRECONDITION_FAILED",
    b.results[2] and tostring(b.results[2].reason_code) .. "/" .. tostring(b.results[2].message))
  check("the bare resend plays", b.results[2] and b.results[2].ok == true
    and G.GAME.current_round.hands_left == 3, G.GAME.current_round.hands_left)
  check("the plan written at the gate reaches the register", G.NEURO.plan and G.NEURO.plan.boss == BOSS,
    G.NEURO.plan and tostring(G.NEURO.plan.boss))
  check("the boss scope committed with it is current", PlanGate.boss_plan_is_current(G.NEURO.plan))
  check("committing releases the hold", G.NEURO.held_plan_write == nil)
  check("no copy of the plan text reaches the permanent channel",
    joined_contexts(b):find(BOSS, 1, true) == nil, joined_contexts(b))
  check("and the write is still acknowledged, by the action result alone",
    b.results[2] and b.results[2].ok == true, b.results[2] and tostring(b.results[2].ok))
end

do
  base()
  local b = bridge()
  send("play_hand", "p1", { indices = { 1, 2 }, plan = { boss_plan = BOSS } }, b)
  check("play is gated before a discard is tried", b.results[1]
    and b.results[1].reason_code == "CONFIRMATION_REQUIRED")
  rearm()
  send("discard_hand", "d1", { indices = { 3 } }, b)
  check("a different action in the same round is not refused for the missing field",
    b.results[2] and b.results[2].ok == true, b.results[2] and tostring(b.results[2].reason_code))
  check("the held plan commits with it", G.NEURO.plan and G.NEURO.plan.boss == BOSS,
    G.NEURO.plan and tostring(G.NEURO.plan.boss))
end

do
  base()
  local b = bridge()
  send("play_hand", "p1", { indices = { 1, 2 }, plan = { boss_plan = BOSS } }, b)
  check("play is gated before the blind changes", b.results[1]
    and b.results[1].reason_code == "CONFIRMATION_REQUIRED")
  G.GAME.blind = { key = "bl_window", name = "The Window", boss = true }
  rearm()
  send("play_hand", "p2", { indices = { 1, 2 } }, b)
  check("a held plan from the previous boss does not satisfy the new one",
    b.results[2] and b.results[2].ok == false and b.results[2].reason_code == "PRECONDITION_FAILED",
    b.results[2] and tostring(b.results[2].reason_code))
  check("no foreign plan reached the register", G.NEURO.plan == nil)
end

do
  base()
  local b = bridge()
  send("play_hand", "p1", { indices = { 1, 2 }, plan = { boss_plan = BOSS } }, b)
  check("play is gated before the run generation moves", b.results[1]
    and b.results[1].reason_code == "CONFIRMATION_REQUIRED")
  G.NEURO.run_generation = 8
  check("a hold from an older run generation is dropped", PlanTransaction.prepare("play_hand",
    { indices = { 1, 2 } }) == nil and G.NEURO.held_plan_write == nil)
end

do
  base()
  G.NEURO.plan = nil
  local first = PlanHandlers.prepare_plan({ boss_plan = "Grind chips with pairs." })
  check("a first write emits nothing for the permanent channel", first() == nil, tostring(first()))
  check("but it did commit", G.NEURO.plan and G.NEURO.plan.boss == "Grind chips with pairs.",
    G.NEURO.plan and tostring(G.NEURO.plan.boss))
  local same = PlanHandlers.prepare_plan({ boss_plan = "Grind chips with pairs." })
  check("a rewrite emits nothing either", same() == nil)
end

do
  base()
  G.NEURO.plan = nil
  local out = PlanHandlers.prepare_plan({
    hand_plan = "dump off-suit singles to dig for pairs.",
    build_plan = "take any strong economy joker",
  })()
  check("a multi-field write emits nothing for the permanent channel", out == nil, tostring(out))
  check("every field it named still committed",
    G.NEURO.plan.hand == "dump off-suit singles to dig for pairs."
      and G.NEURO.plan.build == "take any strong economy joker",
    tostring(G.NEURO.plan.hand) .. " / " .. tostring(G.NEURO.plan.build))
  check("and each carries the scope its truth is bound to",
    G.NEURO.plan.hand_scope == PlanGate.current_blind_scope()
      and G.NEURO.plan.build_scope == PlanGate.current_build_scope())
end

done()
