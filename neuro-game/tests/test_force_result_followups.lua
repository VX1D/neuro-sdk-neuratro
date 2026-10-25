local H = require("tests.hand_pipeline_harness")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Window = require("core.window")
local check, done = require("tests.helpers").harness("force-result-followups")

local function frames_from(i)
  local out, all = {}, H.frames()
  for k = i + 1, #all do out[#out + 1] = all[k] end
  return out
end

local has = require("tests.helpers").has

local function shop_board()
  H.board({ confirm_hand = false })
  G.STATE = H.STATES.SHOP; G.NEURO.state = "SHOP"; G.shop = {}
  G.GAME.dollars = 30; G.NEURO.shop_visit_epoch = 1
end

do
  H.board({ confirm_hand = false })
  check("F5: fixture forced", H.wait_force(), H.phase())
  local w = Window.current()
  check("F5: fixture liveness is the long bound", Window.liveness_timeout(w) > 2 * Window.REFUSED_LIVENESS,
    tostring(Window.liveness_timeout(w)))
  local id = H.send("play_hand", { indices = { 1, 99 } })
  H.tick(0.3)
  check("F5: the bad answer is refused with success=false", H.result_for(id) and H.result_for(id).success == false)
  H.tick(Window.REFUSED_LIVENESS - 5)
  local again = H.send("play_hand", { indices = { 1, 98 } })
  H.tick(Window.REFUSED_LIVENESS - 5)
  check("F5: a further answer restarts the bound", Window.current() == w and w.phase == "forced"
    and H.result_for(again) and H.result_for(again).success == false, tostring(w.phase) .. "/" .. tostring(w.ended_by))
  local forces = H.count("actions/force")
  H.tick(10)
  check("F5: with no answer after the refusal the force is withdrawn", w.phase == "ended"
    and w.ended_by == "liveness_timeout", tostring(w.phase) .. "/" .. tostring(w.ended_by))
  check("F5: and asked again", H.wait_force() and H.count("actions/force") == forces + 1,
    forces .. "->" .. H.count("actions/force"))
end

do
  H.board({ confirm_hand = false })
  check("F9: fixture forced", H.wait_force(), H.phase())
  local churn, spent = {}, 0
  for i = 1, 8 do
    if not H.wait_force() then break end
    local mark = #H.frames()
    local id = H.send("play_hand", { indices = { 1, 90 + i } })
    H.tick(0.3)
    local r = H.result_for(id)
    if r and r.success == true then
      spent = spent + 1
      H.wait_force()
      for _, f in ipairs(frames_from(mark)) do
        if f.command == "actions/unregister" or f.command == "actions/register" then
          churn[#churn + 1] = i .. ":" .. f.command .. " " .. table.concat(H.names_of(f), ",")
        end
      end
    end
  end
  check("F9: the budget is spent within the sends", spent >= 3, tostring(spent))
  check("F9: a spent answer neither unregisters nor re-registers the offer", #churn == 0, table.concat(churn, "; "))
  check("F9: each spent answer is still asked again (BEST_PRACTICES.md:35)", H.phase() == "forced", H.phase())
end

do
  H.board({ confirm_hand = false })
  check("F10: fixture forced", H.wait_force(), H.phase())
  local Dispatcher = require("core.dispatcher")
  local real_preflight = Dispatcher.preflight
  Dispatcher.preflight = function() error("boom", 0) end
  local pre = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.2)
  Dispatcher.preflight = real_preflight
  local State = require("core.state")
  local real_state = State.get_state_name
  State.get_state_name = function() error("state read failed", 0) end
  Dispatcher.handle_message({ command = "action", data = { id = "crash-1", name = "play_hand", data = '{"indices":[1,2]}' } },
    G.NEURO)
  State.get_state_name = real_state
  local crash, preflight = H.result_for("crash-1"), H.result_for(pre)
  check("F10: the double fault is answered at once, unsuccessfully", crash ~= nil and crash.success == false,
    tostring(crash and crash.success))
  check("F12: the crash text is the preflight-fault text", crash ~= nil and preflight ~= nil
    and crash.message == preflight.message, tostring(crash and crash.message) .. " || " .. tostring(preflight and preflight.message))
end

do
  shop_board()
  G.consumeables.cards = { LB.consumable("c_mercury", 801) }
  check("F11: fixture forced the shop", H.wait_force(), H.phase())
  local id = H.send("sell_card", { area = "jokers", index = 3 })
  H.tick(0.3)
end

do
  H.board({ confirm_hand = false })
  check("F13: fixture forced the hand", H.wait_force(), H.phase())
  Window.withdraw("test")
  G.STATE = H.STATES.ROUND_EVAL
  G.round_eval = {}
  G.GAME.current_round.dollars = 0
  G.FUNCS.cash_out = function() end
  H.tick(0.2)
  local entered = H.CLOCK
  Helpers.cash_out_ready(G, 7)
  local asked
  for _ = 1, 100 do
    H.tick(0.1)
    if H.phase() == "forced" and has(Window.current().names, "cash_out") then asked = H.CLOCK - entered break end
  end
  local entry = require("util.utils").gate_seconds("state_entry_cooldown", "NEURO_ENTRY_CD_ROUND_EVAL")
  check("F13: cash_out is forced well inside the timed entry cooldown", asked ~= nil and asked < entry - 1,
    tostring(asked) .. " vs " .. tostring(entry))
end

do
  shop_board()
  local joker = LB.joker("j_joker", 701)
  joker.cost = 2
  G.shop_jokers.cards = { joker }
  check("F14: fixture forced the shop", H.wait_force(), H.phase())
  check("F14: the offer carries both", has(Window.current().names, "buy_from_shop")
    and has(Window.current().names, "leave_shop"), table.concat(Window.current().names, ","))
  local mark = #H.frames()
  local id = H.send("buy_from_shop", { area = "shop_jokers", index = 1, plan = { build_plan = "Mult build", money_plan = "Spend now" } })
  H.tick(0.3)
  local unreg = {}
  for _, f in ipairs(frames_from(mark)) do
    if f.command == "actions/unregister" then for _, n in ipairs(H.names_of(f)) do unreg[#unreg + 1] = n end end
  end
  local r = H.result_for(id)
  check("F14: the purchase is accepted", r and r.success == true, tostring(r and r.message))
  check("F14: its answer takes leave_shop off, so the force is cancelled (README.md:27)", has(unreg, "leave_shop"),
    table.concat(unreg, ","))
  check("F14: and leaves buy_from_shop registered", not has(unreg, "buy_from_shop"), table.concat(unreg, ","))
  local ActionPolicy = require("core.action_policy")
  check("F14: leaving the shop takes buy_from_shop off with it",
    has(ActionPolicy.disposable_group("leave_shop"), "buy_from_shop"))
end

do
  H.board({ confirm_hand = false })
  check("F15: fixture forced", H.wait_force(), H.phase())
  local id = H.send("play_hand", { indices = { 1, 2 }, foo = 1, bar = "x" })
  H.tick(0.3)
  local r = H.result_for(id)
  check("F15: the action still succeeds", r and r.success == true, tostring(r and r.success))
  H.board({ confirm_hand = false })
  H.wait_force()
  local clean = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.3)
  local c = H.result_for(clean)
  check("F15: a clean payload gets no note", c ~= nil and c.success == true and c.message == nil,
    tostring(c and c.message))
end

do
  H.board({ confirm_hand = false })
  check("F16: fixture forced", H.wait_force(), H.phase())
  local id = H.send("play_hand", { indices = { 1, 2 }, boss_plan = "x", foo = 1 })
  H.tick(0.3)
  local r = H.result_for(id)
  check("F16: the action still succeeds", r and r.success == true, tostring(r and r.success))
  check("F16: and the note is true: nothing was saved as the boss plan",
    not (G.NEURO.plan and G.NEURO.plan.boss == "x"), tostring(G.NEURO.plan and G.NEURO.plan.boss))
end

H.finish(check, done)
