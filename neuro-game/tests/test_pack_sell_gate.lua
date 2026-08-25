_G.NEURO_TEST = true
love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {} }

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local TD = require("tests.test_deadlock")
local ShopHandlers = require("handlers.shop_handlers")
local ActionResult = require("core.action_result")
local check, done = require("tests.helpers").harness("pack-sell-gate")

local ANNOUNCE = "A sell_card confirmation is open for"

local scenario
for _, s in ipairs(TD.SCENARIOS) do
  if s.state == "BUFFOON_PACK" and s.desc == "BUFFOON_PACK variant with pack cards" then scenario = s end
end
assert(scenario, "test_pack_sell_gate: BUFFOON_PACK fixture scenario not found in test_deadlock")

local function pack_fixture()
  local mock = scenario.mock()
  local held = { ability = { set = "Joker", name = "Joker" },
    config = { center = { key = "j_joker", set = "Joker", loc_txt = { name = "Joker" } } },
    sell_cost = 3, sort_id = 4242 }
  mock.jokers = { cards = { held }, config = { card_limit = 1 } }
  TD.apply_mock(mock)
  G.STATES = G.STATES or {}
  G.STATES.BUFFOON_PACK = G.STATES.BUFFOON_PACK or 8
  G.STATE = G.STATES.BUFFOON_PACK
  G.NEURO.state = "BUFFOON_PACK"
  G.NEURO.state_enter_serial = 1
  G.NEURO.decision_serial = 0
  G.NEURO.last_sell_reject = nil
  G.NEURO.last_sell_review_serial = nil
  G.FUNCS.sell_card = function() end
  return held
end

local function query()
  local ok, force = pcall(require("force.force_pack").build, "BUFFOON_PACK")
  return ok and type(force) == "table" and force.query or nil
end

local held = pack_fixture()
local base_query = query()
check("the pack force offers sell_card with the joker slots full",
  type(base_query) == "string" and base_query:find("sell_card", 1, true) ~= nil, tostring(base_query))
check("nothing is announced before an agreement exists",
  base_query and base_query:find(ANNOUNCE, 1, true) == nil, tostring(base_query))

local exec, err = ShopHandlers.handle_sell_card({ area = "jokers", index = 1 })
check("the make-room sell is gated inside the pack",
  exec == nil and ActionResult.is_error(err) and err.reason_code == "CONFIRMATION_REQUIRED",
  err and err.reason_code)
check("the gate reuses the shop token and the recorded decision",
  G.NEURO.last_sell_reject == "sell:1:" .. tostring(held.sort_id)
    and G.NEURO.last_sell_review_serial == 0,
  tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))

local armed_query = query()
check("the open agreement reaches the pack force state",
  armed_query and armed_query:find(ANNOUNCE, 1, true) ~= nil, tostring(armed_query))

G.NEURO.decision_serial = 1
local lapsed_query = query()
check("an action resolved in between drops the line again",
  lapsed_query and lapsed_query:find(ANNOUNCE, 1, true) == nil, tostring(lapsed_query))
local _, err2 = ShopHandlers.handle_sell_card({ area = "jokers", index = 1 })
check("the lapsed agreement is re-gated, not committed",
  ActionResult.is_error(err2) and err2.reason_code == "CONFIRMATION_REQUIRED", err2 and err2.reason_code)

local exec2 = ShopHandlers.handle_sell_card({ area = "jokers", index = 1 })
check("the identical resend inside the pack commits", type(exec2) == "function", type(exec2))
check("confirming consumes both halves of the token",
  G.NEURO.last_sell_reject == nil and G.NEURO.last_sell_review_serial == nil,
  tostring(G.NEURO.last_sell_reject) .. "/" .. tostring(G.NEURO.last_sell_review_serial))

done()
