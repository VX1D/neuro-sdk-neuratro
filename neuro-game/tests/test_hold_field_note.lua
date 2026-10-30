require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("hold-field-note")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local TxCache = require("core.bridge").tx

local n = 0
local function send(name, data)
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message, code)
    results[#results + 1] = { ok = ok, message = message, code = code }
    return true
  end
  G.NEURO.withdraw_actions = function() return true end
  n = n + 1
  local id = "hold-note-" .. n
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), G.NEURO)
  return results[1] or {}
end

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.jokers.cards = {}
  FP.build("SHOP")
  G.NEURO.gates = nil
  G.NEURO.shop_entry_dollars, G.GAME.dollars = 14, 3
  local r = send("leave_shop", { hand_plan = "Play pairs from non-Club cards", plan = { fallback = "Pair" } })
  check("leave_shop: the first send is held, executing nothing",
    r.ok == true and r.code == "CONFIRMATION_REQUIRED", tostring(r.code) .. " " .. tostring(r.message))
  check("leave_shop: the hold names the misplaced top-level field",
    has(r.message, "Not saved: hand_plan belongs under plan; send it as plan.hand_plan."), tostring(r.message))
  check("leave_shop: the hold names the plan field it does not take",
    has(r.message, "Not saved: plan.fallback is not a plan field of this move"), tostring(r.message))
  local review = (G.NEURO.gates and G.NEURO.gates.interest_engine_off or {}).review
  check("leave_shop: the note rides the result only, not the review the next decision repeats",
    review ~= nil and not has(review, "Not saved"), tostring(review))
end

do
  require("core.config").set("NEURO_CONFIRM_HAND", "on")
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  FP.build("SELECTING_HAND")
  G.NEURO.gates = nil
  local r = send("play_hand", { indices = { 1 }, boss_plan = "Lead with the pair", plan = { hand_plan = "x" } })
  check("play_hand: the first send is held for its review",
    r.ok == true and r.code == "CONFIRMATION_REQUIRED", tostring(r.code) .. " " .. tostring(r.message))
  check("play_hand: the hold names the misplaced top-level field",
    has(r.message, "Not saved: boss_plan belongs under plan; send it as plan.boss_plan."), tostring(r.message))
  check("play_hand: the hold names the plan field it does not take",
    has(r.message, "Not saved: plan.hand_plan is not a plan field of this move"), tostring(r.message))
end

done()
