
_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("shop-entry-snapshot")

local Orchestrator = require("core.orchestrator")
local DW = require("core.decision_window")

local STATE_ID = {
  SELECTING_HAND = 1, ROUND_EVAL = 2, SHOP = 3, ARCANA_PACK = 4,
  BLIND_SELECT = 5, PLAY_TAROT = 6,
}

local BUSY_EVENT = { blocking = true, blockable = true }

local function env(dollars)
  _G.G = {
    STATE = STATE_ID.ROUND_EVAL,
    STATES = STATE_ID,
    STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 },
    TIMERS = { REAL = 100 },
    FUNCS = {},
    E_MANAGER = { queues = { base = {} } },
    GAME = {
      dollars = dollars,
      blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5, dollars = 0 },
      round_resets = {
        ante = 2,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
      modifiers = {},
    },
    NEURO = {
      enabled = false, run_generation = 1, decision_serial = 1, state_enter_serial = 1,
      economy_epoch = 0, shop_visit_epoch = 0, reserved_dollars = 0,
      _reservation_epoch = 0, _prev_ante = 2, _decision_windows = {}, once_serials = {},
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop = {}, shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    P_BLINDS = {
      bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_boss = { key = "bl_boss", name = "Boss Blind" },
    },
  }
end

local function go(from, to)
  G.STATE = STATE_ID[to]
  G.NEURO.state = from
  local ok, err = pcall(Orchestrator._step_state_transition, to, true, from)
  check("transition " .. from .. " -> " .. to .. " completes without error", ok, err)
  G.NEURO.state = to
  Orchestrator._step_shop_entry_settle(to)
end

local function frame()
  Orchestrator._step_shop_entry_settle(require("core.state").get_state_name())
end

local function busy(is_busy)
  G.E_MANAGER.queues.base = is_busy and { BUSY_EVENT } or {}
end

env(4)
busy(true)
G.GAME.current_round.dollars = 9
go("ROUND_EVAL", "SHOP")
check("transition frame with a busy queue does not close the snapshot",
  G.NEURO.shop_entry_pending == true, tostring(G.NEURO.shop_entry_pending))
frame()
check("snapshot does not freeze on the pre-payout bank",
  G.NEURO.shop_entry_dollars == 4, G.NEURO.shop_entry_dollars)
G.GAME.dollars = 13
frame()
check("booking the payout in an open window updates the snapshot",
  G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)
busy(false)
frame()
check("draining the queue closes the snapshot", G.NEURO.shop_entry_pending == nil,
  tostring(G.NEURO.shop_entry_pending))
check("closed snapshot is the bank after payout", G.NEURO.shop_entry_dollars == 13,
  G.NEURO.shop_entry_dollars)
G.GAME.dollars = 2
frame()
check("a purchase after closing does not move the snapshot", G.NEURO.shop_entry_dollars == 13,
  G.NEURO.shop_entry_dollars)

env(13)
busy(false)
G.GAME.current_round.dollars = 9
go("ROUND_EVAL", "SHOP")
check("an already-booked payout closes the snapshot immediately", G.NEURO.shop_entry_pending == nil,
  tostring(G.NEURO.shop_entry_pending))
check("an already-booked payout is not added twice",
  G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)
G.GAME.dollars = 3
frame(); frame()
check("subsequent frames do not re-snapshot", G.NEURO.shop_entry_dollars == 13,
  G.NEURO.shop_entry_dollars)

env(5)
busy(true)
G.GAME.current_round.dollars = 8
go("ROUND_EVAL", "SHOP")
G.GAME.dollars = 13
busy(false)
frame()
G.GAME.dollars = 1
DW.reset_field("interest_engine_off")
local lvl, msg = DW.evaluate("toggle_shop")
check("entering with $13 and leaving with $1 fires the gate", lvl == "soft_reject", tostring(lvl))
check("prose quotes the bank after payout", msg and msg:find("entered it with $13", 1, true) ~= nil, msg)
check("prose does not quote the pre-payout bank",
  msg and msg:find("entered it with $5", 1, true) == nil, msg)

env(0)
busy(true)
G.GAME.current_round.dollars = 4
go("ROUND_EVAL", "SHOP")
G.GAME.dollars = 4
busy(false)
frame()
DW.reset_field("interest_engine_off")
check("entering with $4 does not fire the gate", DW.evaluate("toggle_shop") == false)

env(4)
busy(true)
G.GAME.current_round.dollars = 9
go("ROUND_EVAL", "SHOP")
G.GAME.dollars = 13
busy(false)
frame()
local visit = G.NEURO.shop_visit_epoch
local economy = G.NEURO.economy_epoch
G.NEURO.econ_plan_ok = true
G.NEURO.last_sell_reject = "sell:1:j_a"
G.NEURO.shop_reroll_count = 2
G.GAME.dollars = 9
go("SHOP", "PLAY_TAROT")
check("using a consumable does not bump the visit epoch", G.NEURO.shop_visit_epoch == visit,
  G.NEURO.shop_visit_epoch)
check("using a consumable does not clear the reroll counter", G.NEURO.shop_reroll_count == 2,
  tostring(G.NEURO.shop_reroll_count))
G.GAME.dollars = 1
go("PLAY_TAROT", "SHOP")
check("returning from a consumable does not bump the visit epoch", G.NEURO.shop_visit_epoch == visit,
  G.NEURO.shop_visit_epoch)
check("returning from a consumable does not bump the economy epoch", G.NEURO.economy_epoch == economy,
  G.NEURO.economy_epoch)
check("returning from a consumable does not re-snapshot the account",
  G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)
check("returning from a consumable does not reopen the snapshot",
  G.NEURO.shop_entry_pending == nil, tostring(G.NEURO.shop_entry_pending))
check("returning from a consumable does not clear the economy plan", G.NEURO.econ_plan_ok == true)
check("returning from a consumable does not disarm the sell confirmation",
  G.NEURO.last_sell_reject == "sell:1:j_a", tostring(G.NEURO.last_sell_reject))
check("returning from a consumable does not zero the reroll counter", G.NEURO.shop_reroll_count == 2,
  tostring(G.NEURO.shop_reroll_count))
DW.reset_field("interest_engine_off")
local lvl2, msg2 = DW.evaluate("toggle_shop")
check("the gate after a round trip quotes the bank from shop entry",
  lvl2 == "soft_reject" and msg2:find("entered it with $13", 1, true) ~= nil, msg2)

env(9)
busy(false)
go("SELECTING_HAND", "PLAY_TAROT")
go("PLAY_TAROT", "SHOP")
check("a consumable reached from outside the shop does not fake an ongoing visit", G.NEURO.shop_visit_epoch == 1,
  G.NEURO.shop_visit_epoch)
check("a consumable reached from outside the shop does not block the snapshot", G.NEURO.shop_entry_dollars == 9,
  G.NEURO.shop_entry_dollars)

env(4)
busy(true)
G.GAME.current_round.dollars = 9
go("ROUND_EVAL", "SHOP")
G.GAME.dollars = 13
busy(false)
frame()
go("SHOP", "ARCANA_PACK")
G.GAME.dollars = 5
go("ARCANA_PACK", "SHOP")
check("returning from a pack does not re-snapshot the account", G.NEURO.shop_entry_dollars == 13,
  G.NEURO.shop_entry_dollars)
frame()
check("a frame after returning from a pack also does not re-snapshot",
  G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)

do
  local fh = io.open("core/orchestrator.lua", "r")
  local src = fh:read("a")
  fh:close()
  local body = src:match("local function _step_neuro_frame%(.-\nend\n")
  check("the snapshot-closing step is wired into the frame, not the transition",
    body ~= nil
      and body:find('_neuro_guarded(errors, "shop settle", _step_shop_entry_settle', 1, true) ~= nil)
end

done()
