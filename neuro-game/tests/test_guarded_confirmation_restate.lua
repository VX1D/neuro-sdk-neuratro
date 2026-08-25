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
local StateKinds = require("core.state_kinds")
local Helpers = require("tests.helpers")
local check, done = Helpers.harness("guarded-confirmation-restate")

local SELL_LINE = "sell_card confirmation is open for"
local VOUCHER_LINE = "buy_from_shop confirmation is open for the voucher"

local STATE_IDS = { SELECTING_HAND = 1, SHOP = 5, BLIND_SELECT = 7, BUFFOON_PACK = 8 }

local function scenario(state, desc)
  for _, s in ipairs(TD.SCENARIOS) do
    if s.state == state and s.desc == desc then return s end
  end
  error("test_guarded_confirmation_restate: fixture not found -- " .. state .. " / " .. desc)
end

local ROSTER = {
  { key = "j_jolly",  name = "Jolly Joker" },
  { key = "j_greedy", name = "Greedy Joker" },
  { key = "j_zany",   name = "Zany Joker" },
}

local function roster_joker(i)
  local e = ROSTER[i]
  return { ability = { set = "Joker", name = e.name },
    config = { center = { key = e.key, set = "Joker", loc_txt = { name = e.name } } },
    sell_cost = 3, cost = 4, sort_id = 9000 + i }
end

local function roster()
  local cards = {}
  for i = 1, #ROSTER do cards[i] = roster_joker(i) end
  return cards
end

local function stand(state, desc, tweak)
  local mock = scenario(state, desc).mock()
  mock.jokers = { cards = roster(), config = { card_limit = 5 } }
  if tweak then tweak(mock) end
  TD.apply_mock(mock)
  G.STATES = G.STATES or {}
  for name, id in pairs(STATE_IDS) do G.STATES[name] = id end
  G.STATE = STATE_IDS[state]
  G.NEURO.state = state
  G.NEURO.state_enter_serial = 1
  G.NEURO.decision_serial = 0
  G.NEURO.last_sell_reject = nil
  G.NEURO.last_sell_review_serial = nil
  G.NEURO.last_voucher_reject = nil
  G.NEURO.last_voucher_review_serial = nil
  G.NEURO.state_entry_hints = nil
  G.FUNCS.sell_card = function() end
  G.FUNCS.use_card = function() end
  G.FUNCS.buy_from_shop = function() end
end

local function query(state)
  local ok, force = pcall(Dispatcher.get_force_for_state, state)
  if not ok then return "FORCE ERROR: " .. tostring(force) end
  return (type(force) == "table" and type(force.query) == "string") and force.query or ""
end

local function offers(state, action)
  local ok, force = pcall(Dispatcher.get_force_for_state, state)
  if not ok or type(force) ~= "table" then return false end
  for _, name in ipairs(force.actions or {}) do
    if name == action then return true end
  end
  return false
end

local SELL_FIXTURES = {
  SHOP = function() stand("SHOP", "$0 nothing affordable, has jokers to sell") end,
  BLIND_SELECT = function() stand("BLIND_SELECT", "Small blind selectable") end,
  SELECTING_HAND = function()
    stand("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards", function(mock)
      mock.GAME.blind = { name = "Verdant Leaf", chips = 800, mult = 2, boss = true, debuff = {},
        in_blind = true, key = "bl_final_leaf" }
    end)
    G.P_BLINDS = G.P_BLINDS or {}
    G.P_BLINDS.bl_final_leaf = { name = "Verdant Leaf" }
  end,
  BUFFOON_PACK = function()
    stand("BUFFOON_PACK", "BUFFOON_PACK variant with pack cards", function(mock)
      mock.jokers.config.card_limit = #ROSTER
    end)
  end,
}

local function each_index(fn)
  local bad
  for idx = 1, #ROSTER do
    local ok, detail = fn(idx)
    if not ok and not bad then bad = "selling index " .. idx .. ": " .. tostring(detail) end
  end
  return bad == nil, bad or ("indices 1.." .. #ROSTER)
end

local function arm_sell(state, idx)
  SELL_FIXTURES[state]()
  local exec, err = ShopHandlers.handle_sell_card({ area = "jokers", index = idx })
  return exec, err, query(state)
end

for _, state in ipairs({ "SHOP", "BLIND_SELECT", "SELECTING_HAND", "BUFFOON_PACK" }) do
  SELL_FIXTURES[state]()
  check(state .. ": the force offers sell_card", offers(state, "sell_card"))
  check(state .. ": nothing is announced before an agreement exists",
    query(state):find(SELL_LINE, 1, true) == nil, query(state))

  check(state .. ": the sell is gated on the first send", each_index(function(idx)
    local exec, err = arm_sell(state, idx)
    return exec == nil and ActionResult.is_error(err) and err.reason_code == "CONFIRMATION_REQUIRED",
      tostring(err and err.reason_code)
  end))

  check(state .. ": the open sell agreement is restated in the rebuilt force state",
    each_index(function(idx)
      local _, _, armed = arm_sell(state, idx)
      return armed:find(SELL_LINE, 1, true) ~= nil, armed
    end))

  check(state .. ": the restated agreement names the joker the confirmation is armed for",
    each_index(function(idx)
      local _, _, armed = arm_sell(state, idx)
      local want = "sell_card confirmation is open for " .. ROSTER[idx].name
      return armed:find(want, 1, true) ~= nil, "want [" .. want .. "] in [" .. armed .. "]"
    end))

  check(state .. ": resending sell_card for the joker the restatement names completes the sale",
    each_index(function(idx)
      local _, _, armed = arm_sell(state, idx)
      local named = armed:match("sell_card confirmation is open for ([^:]+):")
      if not named then return false, "no joker named in [" .. armed .. "]" end
      local at
      for i, card in ipairs(G.jokers.cards) do
        if (card.ability and card.ability.name) == named then at = i break end
      end
      if not at then return false, "restatement names an unowned joker: " .. named end
      local exec2, err2 = ShopHandlers.handle_sell_card({ area = "jokers", index = at })
      return type(exec2) == "function",
        "resend for " .. named .. " (index " .. at .. ") gave " ..
          tostring(err2 and err2.reason_code or type(exec2))
    end))

  check(state .. ": the restated agreement says what a resend does", each_index(function(idx)
    local _, _, armed = arm_sell(state, idx)
    return armed:find("sending sell_card for that joker again completes the sale", 1, true) ~= nil, armed
  end))

  check(state .. ": an action resolved in between drops the line again", each_index(function(idx)
    arm_sell(state, idx)
    G.NEURO.decision_serial = (tonumber(G.NEURO.decision_serial) or 0) + 1
    return query(state):find(SELL_LINE, 1, true) == nil, query(state)
  end))
end

for state in pairs(ShopHandlers.GUARDED_SELL_STATES) do
  check("coverage: guarded sell state " .. state .. " has a fixture", SELL_FIXTURES[state] ~= nil)
end
check("coverage: a pack state is exercised too",
  StateKinds.is_pack_state("BUFFOON_PACK") and SELL_FIXTURES.BUFFOON_PACK ~= nil)

local function voucher_fixture()
  stand("SHOP", "Only vouchers affordable (no jokers/boosters)", function(mock)
    mock.shop_vouchers = { cards = { {
      cost = 8, sell_cost = 4, sort_id = 9101,
      ability = { set = "Voucher", name = "Clearance Sale" },
      config = { center = { key = "v_clearance_sale", set = "Voucher",
        loc_txt = { name = "Clearance Sale" } } },
    } } }
  end)
end

voucher_fixture()
check("SHOP voucher: the force offers buy_from_shop", offers("SHOP", "buy_from_shop"))
check("SHOP voucher: nothing is announced before an agreement exists",
  query("SHOP"):find(VOUCHER_LINE, 1, true) == nil, query("SHOP"))

local vexec, verr = ShopHandlers.handle_buy_from_shop({ area = "shop_vouchers", index = 1 })
check("SHOP voucher: the purchase is gated on the first send",
  vexec == nil and ActionResult.is_error(verr) and verr.reason_code == "CONFIRMATION_REQUIRED",
  verr and verr.reason_code)

local varmed = query("SHOP")
check("SHOP voucher: the open purchase agreement is restated in the rebuilt force state",
  varmed:find(VOUCHER_LINE, 1, true) ~= nil, varmed)
check("SHOP voucher: the restated agreement names the voucher",
  varmed:find("the voucher Clearance Sale", 1, true) ~= nil, varmed)
check("SHOP voucher: the restated agreement says what a resend does",
  varmed:find("sending buy_from_shop for that voucher again completes the purchase", 1, true) ~= nil,
  varmed)

G.NEURO.decision_serial = (tonumber(G.NEURO.decision_serial) or 0) + 1
check("SHOP voucher: an action resolved in between drops the line again",
  query("SHOP"):find(VOUCHER_LINE, 1, true) == nil, query("SHOP"))

voucher_fixture()
ShopHandlers.handle_buy_from_shop({ area = "shop_vouchers", index = 1 })
local vexec2 = ShopHandlers.handle_buy_from_shop({ area = "shop_vouchers", index = 1 })
check("SHOP voucher: the identical resend the restatement describes commits",
  type(vexec2) == "function", type(vexec2))

local GUARDED_ACTIONS = { "sell_card", "buy_from_shop" }
local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return Helpers.strip_lua_comments(body)
end
for _, file in ipairs({ "force_shop.lua", "force_blind_select.lua", "force_selecting_hand.lua",
    "force_pack.lua" }) do
  local src = read("force/" .. file)
  local guards = false
  for _, action in ipairs(GUARDED_ACTIONS) do
    if src:find('"' .. action .. '"', 1, true) then guards = true end
  end
  if guards then
    check("class: " .. file .. " restates open confirmations for the guarded actions it offers",
      src:find("pending_confirmation_note", 1, true) ~= nil
        or src:find("pending_sell_card_name", 1, true) ~= nil, file)
  end
end

done()
