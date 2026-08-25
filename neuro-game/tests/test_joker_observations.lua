_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
local check, done = require("tests.helpers").harness("joker-observations")

local calls = 0
_G.Card = {
  calculate_joker = function(_self, context)
    calls = calls + 1
    if context.nil_trigger then return nil, true end
    return context.result, context.triggered
  end,
  calculate_dollar_bonus = function(self) calls = calls + 1; return self.payout end,
}
_G.G = { NEURO = {}, GAME = { round = 4 }, jokers = { cards = {} } }
local Recorder = require("core.joker_recorder")
local Render = require("facts.joker_observations")
local function joker(id, name)
  return setmetatable({ sort_id = id, payout = 4, ability = { set = "Joker", name = name },
    config = { center = { key = "j_" .. id, name = name } } }
    , { __index = Card })
end
local a, b = joker(1, "Alpha"), joker(2, "Beta")
G.jokers.cards = { a, b }

check("install wraps the live engine methods", Recorder.install() == true)
local result, triggered = a:calculate_joker({ result = { mult_mod = 7, dollars = 1, repetitions = 1 } })
check("calculate_joker is called exactly once", calls == 1)
check("both engine returns survive", result.mult_mod == 7 and triggered == nil)
local rec = G.NEURO.joker_observations[1]
check("known raw keys become positive mechanical channels", rec.score_mult and rec.dollars and rec.retrigger)
a:calculate_joker({ nil_trigger = true })
check("nil,true is retained only as an activation", rec.activated == true)
local before = calls
a:calculate_joker({ mod_probability = true, result = { Xmult = 3 } })
check("getter contexts still call the engine", calls == before + 1)
check("getter contexts do not manufacture an observation", rec.score_xmult == nil)
_G.SMODS = { Scoring_Parameter = { obj_table = {
  mult = { key = "mult", calculation_keys = { "modded_mult_key" } },
} } }
b:calculate_joker({ result = { modded_mult_key = 9 } })
check("runtime SMODS scoring keys extend the headless fallback vocabulary",
  G.NEURO.joker_observations[2].score_mult == true)
_G.SMODS = nil
check("round payout return is preserved", a:calculate_dollar_bonus() == 4)
check("round payout is source-attributed with its exact returned amount",
  rec.last_dollar_payout.amount == 4 and rec.last_dollar_payout.round == 4)
local row = Render.for_card(a) or ""
check("the per-joker observation reports its channels", row:find("Mult", 1, true) and row:find("last end-of-round payout $4", 1, true), row)
b:calculate_joker({ result = { Xmult = 2 } })
local line = Render.roster_line(G.jokers.cards) or ""
check("one line carries every observed joker, keyed by its roster number",
  line:find("1. Mult, dollars", 1, true) and line:find("2. Mult, xMult", 1, true), line)
check("and the wording it is made of is written once",
  select(2, line:gsub("Observed this run", "")) == 1, line)
b.ability.name, b.config.center.name = "Alpha", "Alpha"
line = Render.roster_line(G.jokers.cards) or ""
check("duplicate centers remain distinct instances", line:find("1. ", 1, true)
  and line:find("2. ", 1, true) and line:find("(#", 1, true) == nil, line)
do
  local CardUtil = require("facts.card_util")
  local was = CardUtil.is_face_down
  CardUtil.is_face_down = function(card) return card == b end
  local hidden = Render.roster_line(G.jokers.cards) or ""
  check("a face-down joker contributes no entry at all",
    hidden:find("1. ", 1, true) ~= nil and hidden:find("2. ", 1, true) == nil, hidden)
  CardUtil.is_face_down = was
end
G.jokers.cards = { b }
Recorder.prune_owned()
check("sold instances are pruned by stable sort_id", G.NEURO.joker_observations[1] == nil)
check("a second install is idempotent", Recorder.install() == false)
local Lifecycle = require("core.neuro_lifecycle")
G.NEURO.joker_observations = { [9] = { activated = true } }
Lifecycle.reset_run_state()
check("a run reset wipes the observation store through the lifecycle field list",
  G.NEURO.joker_observations == nil)
check("and the recorder offers no second reset to drift from it", Recorder.reset_run_state == nil)
done()
