_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("shop-visit-continuity")

local Orchestrator = require("core.orchestrator")

local STATE_ID = {
  SELECTING_HAND = 1, ROUND_EVAL = 2, SHOP = 3, ARCANA_PACK = 4,
  BLIND_SELECT = 5, BUFFOON_PACK = 6,
}

local function env(dollars)
  _G.G = {
    STATE = STATE_ID.ROUND_EVAL,
    STATES = STATE_ID,
    STATE_COMPLETE = true,
    SETTINGS = { GAMESPEED = 1 },
    TIMERS = { REAL = 100 },
    FUNCS = {},
    GAME = {
      dollars = dollars,
      blind_on_deck = "Small",
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
end

local function snap()
  return {
    visit = G.NEURO.shop_visit_epoch, economy = G.NEURO.economy_epoch,
    entry = G.NEURO.shop_entry_dollars,
  }
end

env(9)
go("ROUND_EVAL", "SHOP")
local first = snap()
check("entry from ROUND_EVAL advances the visit epoch", first.visit == 1, first.visit)
check("entry from ROUND_EVAL advances the economy epoch", first.economy == 1, first.economy)
check("shop entry snapshots the current balance", first.entry == 9, first.entry)

G.NEURO.econ_plan_ok = true
G.NEURO.last_sell_reject = "sell:1:j_a"
G.NEURO.reserved_dollars = 4
G.GAME.dollars = 5
go("SHOP", "ARCANA_PACK")
local in_pack = snap()
check("opening a pack does not advance the visit epoch", in_pack.visit == first.visit, in_pack.visit)
check("opening a pack does not advance the economy epoch", in_pack.economy == first.economy, in_pack.economy)
check("opening a pack preserves the entry balance snapshot", in_pack.entry == 9, in_pack.entry)
check("opening a pack marks the shop visit as resumable",
  G.NEURO.shop_pack_interrupt == true, tostring(G.NEURO.shop_pack_interrupt))
check("leaving the shop releases the dollar reservation",
  G.NEURO.reserved_dollars == 0, tostring(G.NEURO.reserved_dollars))

G.GAME.dollars = 1
go("ARCANA_PACK", "SHOP")
local back = snap()
check("returning from a pack does not advance the visit epoch", back.visit == first.visit, back.visit)
check("returning from a pack does not advance the economy epoch", back.economy == first.economy, back.economy)
check("returning from a pack preserves the entry balance snapshot", back.entry == 9, back.entry)
check("returning from a pack preserves the economy plan", G.NEURO.econ_plan_ok == true)
check("returning from a pack preserves sell confirmation",
  G.NEURO.last_sell_reject == "sell:1:j_a", tostring(G.NEURO.last_sell_reject))
check("returning from a pack consumes the resume marker",
  G.NEURO.shop_pack_interrupt == nil, tostring(G.NEURO.shop_pack_interrupt))

go("SHOP", "BLIND_SELECT")
check("leaving the shop for the blind is not resumable",
  G.NEURO.shop_pack_interrupt == nil, tostring(G.NEURO.shop_pack_interrupt))
G.GAME.dollars = 14
go("BLIND_SELECT", "SELECTING_HAND")
go("SELECTING_HAND", "ROUND_EVAL")
go("ROUND_EVAL", "SHOP")
local second = snap()
check("the next real shop visit advances the visit epoch", second.visit == first.visit + 1, second.visit)
check("the next real shop visit advances the economy epoch", second.economy > first.economy, second.economy)
check("the next real shop visit snapshots the balance again", second.entry == 14, second.entry)

env(9)
go("SELECTING_HAND", "BLIND_SELECT")
go("BLIND_SELECT", "BUFFOON_PACK")
G.GAME.dollars = 9
go("BUFFOON_PACK", "SHOP")
local tagged = snap()
check("a pack opened outside the shop does not impersonate an active visit", tagged.visit == 1, tagged.visit)
check("a pack opened outside the shop does not block the balance snapshot", tagged.entry == 9, tagged.entry)

env(7)
G.NEURO.shop_pack_interrupt = true
go("ROUND_EVAL", "SHOP")
local stale = snap()
check("a stale pack marker does not suppress ROUND_EVAL entry", stale.visit == 1, stale.visit)
check("a stale pack marker does not block the balance snapshot", stale.entry == 7, stale.entry)

done()
