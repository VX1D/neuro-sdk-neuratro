require("tests.stubs").setup({ love = "lazy" })
_G.G = require("tests.helpers").base_G()
local H = require("tests.helpers")
local check, done = H.harness("mid-round-sell-reason")
local V = require("tests.fixtures.vanilla_jokers")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx

H.selecting_hand_env({ reset_tx_cache = true, time = 100 })
G.NEURO = H.started_bridge({ state = "SELECTING_HAND", state_enter_serial = 1, decision_serial = 1, run_generation = 1,
  enabled = true, persona = "neuro", dispatcher = Dispatcher, actions = Actions,
  register_actions = H.noop, send_context = H.yes, is_transition_cooldown = H.no })
local joker = V.card_played("j_ice_cream", 801)
joker.sell_cost, joker.facing = 2, "front"
G.jokers = { cards = { joker }, config = { card_limit = 5 } }
joker.area = G.jokers
H.stage_registered("SELECTING_HAND", { "play_hand", "discard_hand", "sell_card" })

local b = H.fake_bridge({ reason = "reason_code" })
TxCache.open("sell-1", "sell_card", G.TIMERS.REAL)
Dispatcher.handle_message({ command = "action",
  data = { id = "sell-1", name = "sell_card", data = '{"area":"jokers","index":1,"name":"Ice Cream"}' } }, b)
local r = b.results[#b.results] or {}
check("a mid-round sale of a card she owns is refused with the mid-round rule, not as owning nothing",
  r.ok == false and tostring(r.message):find("Mid-round, a card can be sold only when its sale does something", 1, true) ~= nil
    and tostring(r.message):find("Nothing you own", 1, true) == nil, tostring(r.message))
joker.ability.eternal = true
TxCache.open("sell-2", "sell_card", G.TIMERS.REAL)
Dispatcher.handle_message({ command = "action",
  data = { id = "sell-2", name = "sell_card", data = '{"area":"jokers","index":1,"name":"Ice Cream"}' } }, b)
r = b.results[#b.results] or {}
check("an Eternal joker is not sent to the shop to be sold",
  r.ok == false and tostring(r.message):find("in the shop instead", 1, true) == nil, tostring(r.message))
done()
