require("tests.stubs").setup({ love = "timers", G = "timed" })

-- G.shop persists for a visit; only explicit toggle, hand-selection update, or run deletion removes it.
local check, done = require("tests.helpers").harness("shop-visit-identity")

local Orchestrator = require("core.orchestrator")

local function shop_env(states, dollars, edit)
  _G.G = {
    STATE = states.ROUND_EVAL, STATES = states, STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 }, TIMERS = { REAL = 100 }, FUNCS = {},
    GAME = {
      dollars = dollars, blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = {
        ante = 2,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
    },
    NEURO = {
      enabled = false, run_generation = 1, decision_serial = 1, state_enter_serial = 1,
      economy_epoch = 0, shop_visit_epoch = 0, reserved_dollars = 0,
      _reservation_epoch = 0, _prev_ante = 2, once_serials = {}, register_actions = function() end,
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
  edit(G)
end

do
  local STATE_ID = require("tests.engine_cards").states()
  STATE_ID.SOME_MOD_INTERLUDE = 777

  local function env(dollars) shop_env(STATE_ID, dollars, function(g) g.P_BLINDS = {} end) end

  local function open_shop_box() G.shop = { alignment = { offset = { y = -5.3 } } } end
  local function close_shop_box()
    G.shop.REMOVED = true
    G.shop = nil
  end

  local go = require("tests.helpers").shop_go(check, STATE_ID)

  local function frame(state) Orchestrator._step_shop_entry_settle(state) end

  local function snap()
    local n = G.NEURO
    return { visit = n.shop_visit_epoch, economy = n.economy_epoch, entry = n.shop_entry_dollars,
      plan = n.econ_plan_ok }
  end

  local function interlude(state, box_built_before_transition)
    env(12)
    if box_built_before_transition then open_shop_box() end
    go("ROUND_EVAL", "SHOP")
    if not box_built_before_transition then open_shop_box() end
    frame("SHOP")
    local first = snap()
    check(state .. ": entry opens visit 1", first.visit == 1, first.visit)
    G.NEURO.econ_plan_ok = true
    G.GAME.dollars = 2
    go("SHOP", state)
    check(state .. ": the visit is marked resumable while the shop box lives",
      G.NEURO.shop_pack_interrupt == true, tostring(G.NEURO.shop_pack_interrupt))
    go(state, "SHOP")
    local after = snap()
    check(state .. ": returning does not open a new visit", after.visit == 1, after.visit)
    check(state .. ": returning does not age the economy", after.economy == first.economy, after.economy)
    check(state .. ": returning keeps the entry balance", after.entry == 12, after.entry)
    check(state .. ": returning keeps the money plan", after.plan == true, tostring(after.plan))
  end

  for _, built_first in ipairs({ false, true }) do
    interlude("SMODS_REDEEM_VOUCHER", built_first)
    interlude("SOME_MOD_INTERLUDE", built_first)
    interlude("SMODS_BOOSTER_OPENED", built_first)
    interlude("PLAY_TAROT", built_first)
  end

  env(9)
  go("ROUND_EVAL", "SHOP")
  open_shop_box()
  frame("SHOP")
  close_shop_box()
  go("SHOP", "BLIND_SELECT")
  check("leaving through toggle_shop is not resumable", G.NEURO.shop_pack_interrupt == nil,
    tostring(G.NEURO.shop_pack_interrupt))
  go("BLIND_SELECT", "SELECTING_HAND")
  go("SELECTING_HAND", "ROUND_EVAL")
  G.GAME.dollars = 14
  open_shop_box()
  go("ROUND_EVAL", "SHOP")
  check("the next visit gets its own epoch even when its box exists at the transition",
    G.NEURO.shop_visit_epoch == 2, G.NEURO.shop_visit_epoch)
  check("the next visit snapshots its own entry balance", G.NEURO.shop_entry_dollars == 14,
    G.NEURO.shop_entry_dollars)

  env(5)
  open_shop_box()
  go("SELECTING_HAND", "SMODS_REDEEM_VOUCHER")
  go("SMODS_REDEEM_VOUCHER", "SHOP")
  check("a box this mod never saw during a visit is a new visit", G.NEURO.shop_visit_epoch == 1,
    G.NEURO.shop_visit_epoch)

  env(9)
  go("ROUND_EVAL", "SHOP")
  open_shop_box()
  frame("SHOP")
  G.NEURO.reserved_dollars = 4
  G.GAME.dollars = 5
  go("SHOP", "SMODS_BOOSTER_OPENED")
  check("leaving the shop releases the dollar reservation", G.NEURO.reserved_dollars == 0,
    tostring(G.NEURO.reserved_dollars))

  env(9)
  open_shop_box()
  go("SELECTING_HAND", "BLIND_SELECT")
  go("BLIND_SELECT", "SMODS_BOOSTER_OPENED")
  go("SMODS_BOOSTER_OPENED", "SHOP")
  check("a pack opened outside the shop does not impersonate an active visit",
    G.NEURO.shop_visit_epoch == 1, G.NEURO.shop_visit_epoch)
  check("a pack opened outside the shop does not block the balance snapshot",
    G.NEURO.shop_entry_dollars == 9, G.NEURO.shop_entry_dollars)

  env(7)
  G.NEURO.shop_pack_interrupt = true
  go("ROUND_EVAL", "SHOP")
  check("a stale resume marker does not suppress a real entry", G.NEURO.shop_visit_epoch == 1,
    G.NEURO.shop_visit_epoch)

  env(8)
  go("ROUND_EVAL", "SHOP")
  open_shop_box()
  frame("SHOP")
  local box = G.shop
  G.NEURO.run_generation = 2
  G.NEURO.shop_visit_epoch = 1
  go("SHOP", "SMODS_REDEEM_VOUCHER")
  go("SMODS_REDEEM_VOUCHER", "SHOP")
  check("a box bound in another run does not resume this run's visit",
    G.NEURO.shop_visit_epoch == 2 and G.shop == box, G.NEURO.shop_visit_epoch)
end

do
  require("tests.stubs").setup({ love = "timers", G = "timed" })
  local STATE_ID = require("tests.engine_cards").states()

  local BUSY_EVENT = { blocking = true, blockable = true }

  local function env(dollars)
    shop_env(STATE_ID, dollars, function(g)
      g.E_MANAGER = { queues = { base = {} } }
      g.GAME.current_round.dollars = 0
      g.GAME.modifiers = {}
      g.shop = {}
      g.P_BLINDS = {
        bl_small = { key = "bl_small", name = "Small Blind" },
        bl_big = { key = "bl_big", name = "Big Blind" },
        bl_boss = { key = "bl_boss", name = "Boss Blind" },
      }
    end)
  end

  local go = require("tests.helpers").shop_go(check, STATE_ID)

  local function frame()
    Orchestrator._step_shop_entry_settle(require("core.state").get_state_name())
  end

  local function busy(is_busy)
    G.E_MANAGER.queues.base = is_busy and { BUSY_EVENT } or {}
  end

  local function enter(dollars, is_busy, payout)
    env(dollars)
    busy(is_busy)
    G.GAME.current_round.dollars = payout
    go("ROUND_EVAL", "SHOP")
  end

  enter(4, true, 9)
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

  enter(13, false, 9)
  check("an already-booked payout closes the snapshot immediately", G.NEURO.shop_entry_pending == nil,
    tostring(G.NEURO.shop_entry_pending))
  check("an already-booked payout is not added twice",
    G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)
  G.GAME.dollars = 3
  frame(); frame()
  check("subsequent frames do not re-snapshot", G.NEURO.shop_entry_dollars == 13,
    G.NEURO.shop_entry_dollars)

  enter(5, true, 8)
  G.GAME.dollars = 13
  busy(false)
  frame()
  G.GAME.dollars = 1
  G.NEURO.gates = nil
  local first = require("tests.helpers").review("leave_shop")
  local msg = first and first.message
  local shop_text = require("context.ctx_shop").shop_section() or ""
  check("the review fires and the Shop section quotes the bank after payout",
    msg ~= nil and shop_text:find("You entered this shop with $13.", 1, true) ~= nil, shop_text)
  check("prose does not quote the pre-payout bank",
    msg and msg:find("entered it with $5", 1, true) == nil, msg)

  enter(0, true, 4)
  G.GAME.dollars = 4
  busy(false)
  frame()
  G.NEURO.gates = nil
  check("entering with $4 does not fire the gate", require("tests.helpers").review("leave_shop") == nil)

  enter(4, true, 9)
  G.GAME.dollars = 13
  busy(false)
  frame()
  local visit = G.NEURO.shop_visit_epoch
  local economy = G.NEURO.economy_epoch
  G.NEURO.econ_plan_ok = true
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
  check("returning from a consumable does not zero the reroll counter", G.NEURO.shop_reroll_count == 2,
    tostring(G.NEURO.shop_reroll_count))
  G.NEURO.gates = nil
  local msg2 = (require("tests.helpers").review("leave_shop") or {}).message
  local shop_text2 = require("context.ctx_shop").shop_section() or ""
  check("the gate after a round trip fires and the Shop section quotes the bank from shop entry",
    msg2 ~= nil and shop_text2:find("You entered this shop with $13.", 1, true) ~= nil, shop_text2)

  env(9)
  busy(false)
  go("SELECTING_HAND", "PLAY_TAROT")
  go("PLAY_TAROT", "SHOP")
  check("a consumable reached from outside the shop does not fake an ongoing visit", G.NEURO.shop_visit_epoch == 1,
    G.NEURO.shop_visit_epoch)
  check("a consumable reached from outside the shop does not block the snapshot", G.NEURO.shop_entry_dollars == 9,
    G.NEURO.shop_entry_dollars)

  enter(4, true, 9)
  G.GAME.dollars = 13
  busy(false)
  frame()
  go("SHOP", "SMODS_BOOSTER_OPENED")
  G.GAME.dollars = 5
  go("SMODS_BOOSTER_OPENED", "SHOP")
  check("returning from a pack does not re-snapshot the account", G.NEURO.shop_entry_dollars == 13,
    G.NEURO.shop_entry_dollars)
  frame()
  check("a frame after returning from a pack also does not re-snapshot",
    G.NEURO.shop_entry_dollars == 13, G.NEURO.shop_entry_dollars)
end

done()
