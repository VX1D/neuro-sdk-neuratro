_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local Tuning = require("core.config")

local FactHints = require("facts.fact_hints")
local PlanGate = require("core.plan_gate")

local check, done = require("tests.helpers").harness("plan-continuity")

local function jk(key) return { config = { center = { key = key } }, ability = { set = "Joker" } } end
local function base(jokers)
  _G.G = {
    STATE = 2, STATES = { SHOP = 2 },
    GAME = { round_resets = { ante = 2 } },
    NEURO = {},
    jokers = { cards = jokers },
  }
end

base({ jk("j_a"), jk("j_b") })
G.NEURO.plan = { build = "buy an xMult joker", build_scope = PlanGate.current_build_scope(), ante = 2 }
local note = FactHints.plan_note("shop")
check("current build shows 'Build focus'", note:find("Build focus: buy an xMult joker", 1, true) ~= nil, note)
check("current build not shown as stale", note:find("build last shop", 1, true) == nil, note)

G.jokers.cards = { jk("j_a"), jk("j_c") }
local note2 = FactHints.plan_note("shop")
check("stale build surfaced as 'build last shop'",
  note2:find("Your build last shop: 'buy an xMult joker'", 1, true) ~= nil, note2)
check("continuity prompt offers continue/iterate/change",
  note2:find("continue this direction", 1, true) ~= nil, note2)

G.NEURO.plan = { hand = "play the two pair line", hand_scope = "OLD_BLIND", ante = 2 }
local nh = FactHints.plan_note("shop")
check("stale hand plan surfaced as prior context",
  nh:find("Your hand plan last blind: 'play the two pair line'", 1, true) ~= nil, nh)

G.NEURO.plan = { money = "bank to $25", money_scope = "OLD_ECON", ante = 2 }
local nm = FactHints.plan_note("shop")
check("stale money plan surfaced as prior context",
  nm:find("Your last economy call: 'bank to $25'", 1, true) ~= nil, nm)

do
  base({ jk("j_a") })
  G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" }
  G.GAME.blind_on_deck = "Small"
  local permanent = require("handlers.plan_handlers")
    .prepare_plan({ hand_plan = "play the two pair line" })()
  check("the plan write puts nothing on the permanent channel", permanent == nil, tostring(permanent))
  check("but the plan and its scope are recorded",
    G.NEURO.plan.hand == "play the two pair line"
      and G.NEURO.plan.hand_scope == PlanGate.current_blind_scope())

  G.GAME.blind_on_deck = "Big"
  G.GAME.round_resets.ante = 3
  local ephemeral = FactHints.plan_note("blind")
  check("the same plan, once stale, is labelled on the channel that forgets",
    ephemeral:find("Your hand plan last blind (written by you, Ante 2, decision 0) [set 1 ante ago", 1, true) ~= nil
      and ephemeral:find(": 'play the two pair line'", 1, true) ~= nil, ephemeral)
  check("and it is dated",
    ephemeral:find("[set 1 ante ago", 1, true) ~= nil, ephemeral)
  check("so no unlabelled copy of that sentence can outlive it",
    tostring(permanent):find("play the two pair line", 1, true) == nil, tostring(permanent))
end

done()
