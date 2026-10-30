require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("copy-target-and-noop-records")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local TxCache = require("core.bridge").tx
local CtxJokers = require("context.ctx_jokers")
local Budget = require("core.decision_budget")

local SHOP = "Normal: affordable joker, affordable booster, $10"

local sid = 900
local function jk(key, opts)
  sid = sid + 1
  local c = LB.joker(key, sid)
  for k, v in pairs(opts or {}) do c[k] = v end
  return c
end

local function section(cards)
  LB.load("SHOP", SHOP)
  G.jokers.cards = cards
  for _, c in ipairs(cards) do c.area = G.jokers end
  return tostring(CtxJokers.jokers_section("SHOP"))
end

local function row(text, n)
  for line in text:gmatch("[^\n]+") do
    if line:sub(1, #tostring(n) + 2) == n .. ". " then return line end
  end
  return ""
end

local function has(s, needle) return s:find(needle, 1, true) ~= nil end

do
  local text = section({ jk("j_blueprint"), jk("j_half") })
  check("header: positions run left to right and jokers trigger in that order",
    has(text, "1 = leftmost, they trigger left to right)"), text)
  check("Blueprint left of a compatible joker copies it",
    has(row(text, 1), "copying now: Half Joker"), row(text, 1))
  check("only Blueprint and Brainstorm carry a copy line", not has(row(text, 2), "copying now"), row(text, 2))

  text = section({ jk("j_half"), jk("j_blueprint") })
  check("rightmost Blueprint copies nothing",
    has(row(text, 2), "copying now: nothing (no joker to its right)"), row(text, 2))

  text = section({ jk("j_blueprint"), jk("j_rocket") })
  check("an incompatible neighbour is named as uncopyable (blueprint_compat = false)",
    has(row(text, 1), "copying now: nothing (Rocket can't be copied)"), row(text, 1))

  text = section({ jk("j_blueprint"), jk("j_half", { debuff = true }) })
  check("a debuffed neighbour is copied for nothing (SMODS.blueprint_effect)",
    has(row(text, 1), "copying now: nothing (Half Joker is debuffed)"), row(text, 1))

  text = section({ jk("j_half"), jk("j_brainstorm") })
  check("Brainstorm copies the leftmost joker", has(row(text, 2), "copying now: Half Joker"), row(text, 2))
  text = section({ jk("j_brainstorm"), jk("j_half") })
  check("leftmost Brainstorm copies nothing",
    has(row(text, 1), "copying now: nothing (it is your leftmost joker)"), row(text, 1))
end

do
  local half = section({ jk("j_blueprint"), jk("j_half", { facing = "back" }) })
  local joker = section({ jk("j_blueprint"), jk("j_joker", { facing = "back" }) })
  check("a compatible face-down neighbour is reported as the game labels it, unnamed",
    has(row(half, 1), "copying now: a face-down joker") and not has(half, "Half Joker"), half)
  check("which compatible face-down joker it is cannot be told apart", half == joker, half .. "\n--\n" .. joker)
  local rocket = section({ jk("j_blueprint"), jk("j_rocket", { facing = "back" }) })
  check("an incompatible face-down neighbour mirrors the game's 'incompatible' label, unnamed",
    has(row(rocket, 1), "copying now: nothing (the face-down joker to its right can't be copied)")
      and not has(rocket, "Rocket"), rocket)
  local hidden_bp = section({ jk("j_blueprint", { facing = "back" }), jk("j_half") })
  check("a face-down Blueprint states no copy target", not has(hidden_bp, "copying now"), hidden_bp)
end

local sends = 0
local function send(name, data)
  sends = sends + 1
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  local results = {}
  local bridge = G.NEURO
  bridge.send_action_result = Helpers.result_log(results, { "id", "ok", "message", "code" }, true)
  bridge.withdraw_actions = Helpers.yes
  local id = "rec-" .. sends
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), bridge)
  require("core.execute").step(G.TIMERS.REAL)
  return results[1] or {}
end

local function shop_with_jokers()
  LB.load("SHOP", SHOP)
  G.jokers.cards = { jk("j_joker"), jk("j_greedy_joker") }
  for _, c in ipairs(G.jokers.cards) do c.area = G.jokers end
  FP.build("SHOP")
  Budget.reset()
end

do
  shop_with_jokers()
  local roles = { intents = { { index = 1, tag = "CORE", note = "base mult" }, { index = 2, tag = "HOLD" } } }
  local first = send("record_joker_roles", roles)
  check("first record saves", first.ok == true and first.code == "ACTION_ACCEPTED",
    tostring(first.code) .. " " .. tostring(first.message))
  local again = send("record_joker_roles", roles)
  check("identical roles answer success with a true, short message",
    again.ok == true and again.code == "UNCHANGED"
      and again.message == "Those joker roles are already recorded; nothing changed.",
    tostring(again.code) .. " " .. tostring(again.message))
  local no_note = send("record_joker_roles", { intents = { { index = 1, tag = "CORE" } } })
  check("omitting a stored note keeps it, so that is unchanged too", no_note.code == "UNCHANGED",
    tostring(no_note.code))
  check("identical re-records count toward the decision budget",
    Budget.spent("record_joker_roles", "SHOP"))

  Budget.reset()
  local partial = send("record_joker_roles", { intents = { { index = 1, tag = "CORE" }, { index = 2, tag = "CHANGE" } } })
  local stored = G.NEURO.joker_intents[G.jokers.cards[2].sort_id]
  check("a partial change saves normally", partial.code == "ACTION_ACCEPTED" and stored.tag == "CHANGE",
    tostring(partial.code) .. " " .. tostring(stored and stored.tag))
  check("and keeps the unchanged joker's note",
    G.NEURO.joker_intents[G.jokers.cards[1].sort_id].note == "base mult")
  local cleared = send("record_joker_roles", { intents = { { index = 1, tag = "CORE", note = "" } } })
  check("clearing a note is a change", cleared.code == "ACTION_ACCEPTED"
    and G.NEURO.joker_intents[G.jokers.cards[1].sort_id].note == nil, tostring(cleared.code))
end

do
  shop_with_jokers()
  local plan = { hand_plan = "Play pairs", build_plan = "Find xMult", money_plan = "Hold $25 for interest" }
  local first = send("record_plan", plan)
  check("first plan saves", first.ok == true and first.code == "ACTION_ACCEPTED",
    tostring(first.code) .. " " .. tostring(first.message))
  local revision = G.NEURO.plan_revision
  local again = send("record_plan", { hand_plan = "  Play   pairs ", build_plan = "Find xMult" })
  check("an identical plan (after whitespace normalisation) answers success with a true, short message",
    again.ok == true and again.code == "UNCHANGED" and again.message == "Your plan already says that; nothing changed.",
    tostring(again.code) .. " " .. tostring(again.message))
  check("and writes no new plan revision", G.NEURO.plan_revision == revision)
  send("record_plan", { plan = { money_plan = "Hold $25 for interest" } })
  check("identical plan re-records count toward the decision budget", Budget.spent("record_plan", "SHOP"))

  Budget.reset()
  local case = send("record_plan", { hand_plan = "play pairs" })
  check("a case change is a change", case.code == "ACTION_ACCEPTED" and G.NEURO.plan.hand == "play pairs",
    tostring(case.code))
  local partial = send("record_plan", { hand_plan = "play pairs", build_plan = "Find a Blueprint" })
  check("a partial change saves normally",
    partial.code == "ACTION_ACCEPTED" and G.NEURO.plan.build == "Find a Blueprint" and G.NEURO.plan.hand == "play pairs",
    tostring(partial.code) .. " " .. tostring(G.NEURO.plan.build))

  local rerolled = 0
  G.FUNCS.reroll_shop = function() rerolled = rerolled + 1 end
  local inline = send("reroll_shop", { plan = { hand_plan = "play pairs" } })
  check("an unchanged inline plan never turns the main move into a no-op",
    inline.ok == true and inline.code == "ACTION_ACCEPTED" and rerolled == 1,
    tostring(inline.code) .. " " .. tostring(inline.message) .. " rerolled=" .. rerolled)
end

done()
