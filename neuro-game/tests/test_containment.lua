if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Utils = require("util.utils")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local check, done = require("tests.helpers").harness("containment")
local card = require("tests.fake_cards").bare
local mock_state = require("tests.helpers").mock_state

do
  local Helpers = require("tests.helpers")
  local function bridge_mock()
    return Helpers.stub_bridge({
      send_action_result = function(self, id, ok, msg, code)
        self.last = { id = id, ok = ok, msg = msg, code = code }
        return true, { status = "written" }
      end,
      send_context = "noop", register_actions = "noop", is_transition_cooldown = "false",
    })
  end
  local function preview_msg(id)
    return Helpers.inbound_action("set_joker_order", id,
      '{"from_index":1,"to_index":2}')
  end
  local function setup()
    mock_state("Normal", "SELECTING_HAND")
    G.TIMERS = { REAL = 5000 }
    G.NEURO.run_generation = 1
    G.NEURO.transport_session = 1
    G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
    G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
    G.GAME.hands = { Flush = { visible = true, level = 1, chips = 10, mult = 2 } }
    G.FUNCS.get_poker_hand_info = function(sel) return "Flush", nil, { Flush = { { sel[1], sel[2] } } }, { sel[1], sel[2] }, nil end
    G.jokers = { cards = {
      { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
        config = { center = { key = "j_a", set = "Joker" } } },
      { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
        config = { center = { key = "j_b", set = "Joker" } } },
    }, config = { card_limit = 5 } }
    require("core.staging").reset_run_state()
    require("core.gate").forget("handler")
    require("core.bridge").tx.reset()
    D.reset_tx()
  end

  local Window = require("core.window")
  local withdrawn
  G.NEURO.withdraw_actions = function(_, names) withdrawn = names return true end

  setup()
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  require("tests.helpers").stage_registered(nil, { "set_joker_order" })
  local b1 = bridge_mock()
  D.handle_message(preview_msg("pv-1"), b1)
  check("ride-along preview succeeded", b1.last and b1.last.ok == true, b1.last and b1.last.msg)
  check("a success beside the listed set still ends the window (ActionWindowResponse.cs:20)",
    Window.current() == nil)

  setup()
  withdrawn = nil
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "set_joker_order" })
  require("tests.helpers").stage_registered(nil, { "set_joker_order" })
  local b2 = bridge_mock()
  D.handle_message(preview_msg("pv-2"), b2)
  check("in-set preview settles the answered force", Window.current() == nil)
  check("in-set preview withdraws nothing", withdrawn == nil)

  setup()
  G.NEURO.force_window = nil
  local b0 = bridge_mock()
  D.handle_message(preview_msg("pv-2b"), b0)
  G.NEURO.last_quality_reject = "?,?"
  G.NEURO.last_quality_review_serial = tonumber(G.NEURO.decision_serial) or 0
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  local b3 = bridge_mock()
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  D.handle_message(Helpers.inbound_action("play_hand", "pv-3", '{"indices":[1,2]}'), b3)
  check("the next unforced answer reaches its review without a pacing wait",
    b3.last and b3.last.code == "CONFIRMATION_REQUIRED", b3.last and tostring(b3.last.code))
  check("the review answer opens no force by itself", Window.current() == nil)
  G.FUNCS.get_poker_hand_info = nil
  G.TIMERS = nil
end

done()
