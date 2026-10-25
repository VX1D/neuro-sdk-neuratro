require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("review-state-markers")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Gate = require("core.gate")
local ForceHelpers = require("force.force_helpers")
local TxCache = require("core.bridge").tx

local function has(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

local sends = 0
local function send(name, data)
  sends = sends + 1
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message) results[#results + 1] = { ok = ok, message = message } return true end
  G.NEURO.withdraw_actions = function() return true end
  local id = "review-marker-" .. sends
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), G.NEURO)
  pcall(require("core.execute").step, G.TIMERS.REAL)
  return results[1] or {}
end

local function tags()
  local out = {}
  for i = 1, #((G.jokers and G.jokers.cards) or {}) do out[i] = { index = i, tag = "HOLD" } end
  return out
end

local function pin(label, frame)
  check(label .. ": a force follows the review", frame ~= nil)
end

local function fresh(state_name, desc)
  LB.load(state_name, desc)
  G.NEURO.gates = nil
  local first = FP.build(state_name)
  check(state_name .. "/" .. desc .. ": no Review section before any review", first and not has(first.state, "## Review"),
    first and first.state)
  return first
end

do
  fresh("SHOP", "Normal: affordable joker, affordable booster, $10")
  send("sell_card", { area = "jokers", index = 1, plan = { build_plan = "x", money_plan = "y" } })
  pin("sell", FP.next())
end

do
  fresh("SHOP", "Only vouchers affordable (no jokers/boosters)")
  G.GAME.dollars = 20
  local name = require("util.utils").real_name_or(G.shop_vouchers.cards[1])
  send("buy_from_shop", { area = "shop_vouchers", index = 1, name = name,
    plan = { money_plan = "Buy the voucher now." } })
  pin("voucher", FP.next())
end

do
  fresh("SMODS_BOOSTER_OPENED", "Has pack cards")
  send("choose_pack_card", { area = "booster_pack", index = 1 })
  pin("pack", FP.next())
end

do
  fresh("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.NEURO.shop_entry_dollars, G.GAME.dollars = 14, 3
  send("leave_shop", { joker_order_confirmed = true, intents = tags(),
    plan = { hand_plan = "x", build_plan = "x", money_plan = "y" } })
  local frame = FP.next()
  pin("leave", frame)
  check("leave: state carries both banks the review weighs (C6-4)",
    frame and has(frame.state, "$3 in bank") and has(frame.state, "You entered this shop with $14."), frame and frame.state)
  check("leave: query states neither bank (C6-4)",
    frame and not has(frame.query, "$3") and not has(frame.query, "$14"), frame and frame.query)
end

do
  fresh("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  send("play_hand", { indices = { 1, 2 } })
  local proposal = FP.next()
  check("declined play: the proposal frame has no Review section (its state is the Proposed play)",
    proposal and has(proposal.state, "## Proposed play") and not has(proposal.state, "## Review"), proposal and proposal.state)
  send("resolve_play", { answer = "no" })
  pin("declined play", FP.next())
end

do
  local missing = {}
  for _, def in ipairs(Gate.DEFINITIONS) do
    if def.stage ~= "plan" and not ForceHelpers.REVIEW_MARKERS[def.id] then missing[#missing + 1] = def.id end
  end
  check("every non-plan gate has a Review marker", #missing == 0, table.concat(missing, ", "))
end

done()
