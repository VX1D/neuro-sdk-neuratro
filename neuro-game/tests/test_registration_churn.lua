local H = require("tests.hand_pipeline_harness")
local LB = require("tests.fixtures.live_board")
local Window = require("core.window")
local check, done = require("tests.helpers").harness("registration-churn")

local has = require("tests.helpers").has

local function exchange(name, payload)
  local mark = #H.frames()
  local id = H.send(name, payload)
  H.tick(0.3)
  H.wait_force()
  local gone, back, result, force, registered = {}, {}, nil, nil, {}
  local all = H.frames()
  for i = 1, #all do
    local f = all[i]
    if f.command == "actions/register" then
      for _, n in ipairs(H.names_of(f)) do registered[n] = true end
      if i > mark and result then for _, n in ipairs(H.names_of(f)) do back[#back + 1] = n end end
    elseif f.command == "actions/unregister" then
      for _, n in ipairs(H.names_of(f)) do
        registered[n] = nil
        if i > mark and not result then gone[#gone + 1] = n end
      end
    elseif i > mark and f.command == "action/result" and f.data.id == id then
      result = f.data
    elseif i > mark and result and f.command == "actions/force" and not force then
      force = {}
      for _, n in ipairs(H.names_of(f)) do if not registered[n] then force[#force + 1] = n end end
    end
  end
  return { result = result, gone = gone, back = back, stray = force }
end

local function shop_board()
  H.board({ confirm_hand = false })
  G.STATE = H.STATES.SHOP; G.NEURO.state = "SHOP"; G.shop = {}
  G.GAME.dollars = 30; G.NEURO.shop_visit_epoch = 1
  local a, b = LB.joker("j_joker", 701), LB.joker("j_mime", 702)
  a.cost, b.cost = 2, 3
  G.shop_jokers.cards = { a, b }
end

local PLAN = { build_plan = "Mult build", money_plan = "Spend now" }

local function crossing(label, name, payload)
  local f = Window.current()
  local x = exchange(name, payload)
  check(label .. ": accepted", x.result and x.result.success == true, x.result and tostring(x.result.message))
  check(label .. ": F's leave_shop is unregistered before the result (README.md:27)", has(x.gone, "leave_shop"),
    table.concat(x.gone, ","))
  check(label .. ": F ended as answered", f.phase == "ended" and f.ended_by == "answered",
    tostring(f.phase) .. "/" .. tostring(f.ended_by))
  check(label .. ": the next force goes out only after leave_shop is registered again",
    x.stray ~= nil and #x.stray == 0 and has(x.back, "leave_shop"),
    tostring(x.stray and table.concat(x.stray, ",")) .. " / " .. table.concat(x.back, ","))
end

do
  shop_board()
  check("shop: fixture forced with leave_shop", H.wait_force() and Window.current().set.leave_shop == true, H.phase())
  crossing("buy", "buy_from_shop", { area = "shop_jokers", index = 1, plan = PLAN })
  crossing("tool", "reroll_shop", { plan = PLAN })
end

do
  local FP = require("tests.force_payload")
  local Helpers = require("tests.helpers")
  local TxCache = require("core.bridge").tx
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  FP.build("SMODS_BOOSTER_OPENED")
  G.NEURO.gates = nil
  local withdrawn, order = {}, {}
  G.NEURO.send_action_result = function(_, _, ok, message)
    order[#order + 1] = { kind = "result", ok = ok, message = message }
    return true
  end
  G.NEURO.withdraw_actions = function(_, names)
    for _, n in ipairs(names) do withdrawn[#withdrawn + 1] = n end
    order[#order + 1] = { kind = "unregister" }
    return true
  end
  Window.reset()
  local w = Helpers.open_force("SMODS_BOOSTER_OPENED", { "choose_pack_card", "skip_pack", "sell_card" })
  Helpers.stage_registered(nil, { "choose_pack_card" })
  TxCache.open("churn-pack-1", "choose_pack_card", G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action("choose_pack_card", "churn-pack-1",
    { area = "booster_pack", index = 1 }), G.NEURO)
  local r = order[#order] or {}
  check("pack pick: accepted on the first send", r.kind == "result" and r.ok == true, tostring(r.message))
  check("pack pick: F's pack decisions are unregistered before the result",
    order[1] and order[1].kind == "unregister" and has(withdrawn, "choose_pack_card") and has(withdrawn, "skip_pack"),
    table.concat(withdrawn, ","))
  check("pack pick: the answer resolves F", w.phase == "ended" and w.ended_by == "answered",
    tostring(w.phase) .. "/" .. tostring(w.ended_by))
end

do
  local function outside(label, board, name, payload, expected)
    board()
    H.wait_force()
    Window.reset()
    check(label .. ": no force is open", Window.current() == nil, H.phase())
    local mark = #H.frames()
    local id = H.send(name, payload)
    H.tick(0.05)
    local gone, result = {}, nil
    local all = H.frames()
    for i = mark + 1, #all do
      local f = all[i]
      if f.command == "action/result" and f.data.id == id then result = f.data end
      if f.command == "actions/unregister" and not result then
        for _, n in ipairs(H.names_of(f)) do gone[#gone + 1] = n end
      end
    end
    table.sort(gone)
    check(label .. ": accepted", result and result.success == true, result and tostring(result.message))
    check(label .. ": unregisters only " .. (expected == "" and "nothing" or expected),
      table.concat(gone, ",") == expected, table.concat(gone, ","))
  end
  outside("no force, discard", function() H.board({ confirm_hand = false }) end,
    "discard_hand", { indices = { 1, 2 } }, "discard_hand")
  outside("no force, buy", shop_board, "buy_from_shop", { area = "shop_jokers", index = 1, plan = PLAN }, "")
  outside("no force, tool", shop_board, "reroll_shop", { plan = PLAN }, "")
end

H.finish(check, done)
