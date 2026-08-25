_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("plan-provenance")
local Plans = require("handlers.plan_handlers")
local FactHints = require("facts.fact_hints")

local function joker(key, sid)
  return { sort_id = sid, config = { center = { key = key } }, ability = { set = "Joker", name = key } }
end

_G.G = {
  STATE = 1,
  STATES = { SHOP = 1 },
  GAME = {
    dollars = 12,
    blind_on_deck = "Small",
    round_resets = { ante = 2,
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" } },
    current_round = { reroll_cost = 5 },
    used_vouchers = {},
  },
  NEURO = { decision_serial = 41, plan_revision = 0, joker_intent_revision = 0 },
  jokers = { cards = { joker("Alpha", 101), joker("Beta", 102) }, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
}

local first, first_err = Plans.prepare_plan({ hand_plan = "play pairs", build_plan = "keep Alpha",
  money_plan = "keep a reserve" })
check("multi-field plan prepares", type(first) == "function", first_err)
first()
local hand_p = G.NEURO.plan.provenance.hand
local build_p = G.NEURO.plan.provenance.build
check("explicit fields receive source provenance",
  hand_p.ante == 2 and hand_p.decision_serial == 41 and hand_p.revision == 1
    and type(hand_p.scope) == "string"
    and build_p.ante == 2 and build_p.decision_serial == 41 and build_p.revision == 1)

G.NEURO.decision_serial = 42
local second = Plans.prepare_plan({ hand_plan = "play flushes" })
second()
check("partial plan preserves omitted value", G.NEURO.plan.build == "keep Alpha")
check("partial plan preserves omitted provenance by identity",
  G.NEURO.plan.provenance.build == build_p)
check("partial plan stamps only the explicitly rewritten field",
  G.NEURO.plan.provenance.hand ~= hand_p
    and G.NEURO.plan.provenance.hand.decision_serial == 42
    and G.NEURO.plan.provenance.hand.revision == 2)

G.NEURO.decision_serial = 43
G.GAME.round_resets.ante = 2
local delayed = assert(Plans.prepare_plan({ build_plan = "keep the scaling Joker" }))
G.NEURO.decision_serial = 99
G.GAME.round_resets.ante = 4
delayed()
check("delayed commit retains prepare-time authorship",
  G.NEURO.plan.provenance.build.ante == 2
    and G.NEURO.plan.provenance.build.decision_serial == 43)

local aged_note = FactHints.plan_note("shop")
check("age is derived per field from its own provenance",
  aged_note:find("Build focus (written by you, Ante 2, decision 43) [set 2 antes ago", 1, true) ~= nil,
  aged_note)
check("plan renderer owns terminal punctuation exactly once",
  aged_note:find("..", 1, true) == nil, aged_note)

G.GAME.round_resets.ante = 2
G.NEURO.decision_serial = 42

do
  local prior_money = G.NEURO.plan.provenance.money
  local tx, tx_err = require("core.plan_transaction").prepare("buy_from_shop", {})
  check("transaction can inherit the current required money plan", type(tx) == "table", tx_err)
  local wrapped = require("core.plan_transaction").wrap("buy_from_shop", {}, function()
    return require("core.action_receipt").outcome("applied")
  end, tx)
  wrapped()
  check("transaction-carried plan retains original provenance",
    G.NEURO.plan.money == "keep a reserve" and G.NEURO.plan.provenance.money == prior_money)
end

local note = FactHints.plan_note("shop")
check("render labels the model as author",
  note:find("written by you, Ante 2, decision 42", 1, true) ~= nil, note)

G.NEURO.decision_serial = 50
local intents = Plans.prepare_joker_intents({ intents = {
  { index = 1, tag = "CORE", note = "anchor" },
  { index = 2, tag = "HOLD" },
} })
intents()
local alpha_p = G.NEURO.joker_intents[101].provenance
local beta_p = G.NEURO.joker_intents[102].provenance
check("intent write stamps both selected cards",
  alpha_p.ante == 2 and alpha_p.decision_serial == 50 and alpha_p.revision == 1
    and beta_p.revision == 1)

G.NEURO.decision_serial = 51
Plans.prepare_joker_intents({ intents = { { index = 1, tag = "SCALING" } } })()
check("retag stamps only the selected Joker",
  G.NEURO.joker_intents[101].provenance.decision_serial == 51
    and G.NEURO.joker_intents[101].provenance.revision == 2
    and G.NEURO.joker_intents[102].provenance == beta_p)
check("retag still preserves an omitted note",
  G.NEURO.joker_intents[101].note == "anchor")

do
  local function marks(txt)
    local n = 0
    for _ in txt:gmatch("%(written by you") do n = n + 1 end
    return n
  end

  G.GAME.round_resets.ante = 2
  G.NEURO.decision_serial = 60
  Plans.prepare_plan({ hand_plan = "play pairs", build_plan = "keep Alpha",
    money_plan = "keep a reserve" })()
  local shared = FactHints.plan_note("shop")
  check("three fields from one decision carry no inline authorship mark",
    marks(shared) == 0, shared)
  check("their shared authorship is stated once, and named as covering all of them",
    select(2, shared:gsub("All written by you, Ante 2, decision 60%.", "")) == 1, shared)
  check("no placeholder survives the substitution",
    shared:find("[\1\2]") == nil, shared)
  for _, field in ipairs({ "play pairs", "keep Alpha", "keep a reserve" }) do
    check("the hoist loses no plan text: " .. field, shared:find(field, 1, true) ~= nil, shared)
  end

  G.NEURO.decision_serial = 61
  Plans.prepare_plan({ money_plan = "spend down to $10" })()
  local mixed = FactHints.plan_note("shop")
  check("a field written at another decision keeps its own mark",
    mixed:find("(written by you, Ante 2, decision 61)", 1, true) ~= nil, mixed)
  check("and the clause then covers only the remainder",
    select(2, mixed:gsub("The rest written by you, Ante 2, decision 60%.", "")) == 1, mixed)
  check("exactly one field pays for an inline mark", marks(mixed) == 1, mixed)

  G.NEURO.plan = { ante = 2, build = "keep Alpha",
    build_scope = require("core.plan_gate").current_build_scope(),
    provenance = { build = { ante = 2, decision_serial = 60 } } }
  local lone = FactHints.plan_note("shop")
  check("a lone field keeps its inline mark", marks(lone) == 1, lone)
  check("and states no trailing clause",
    lone:find("written by you, Ante 2, decision 60.", 1, true) == nil, lone)

  G.NEURO.plan = { ante = 2, build = "keep Alpha", hand = "play pairs",
    build_scope = require("core.plan_gate").current_build_scope(),
    hand_scope = require("core.plan_gate").current_blind_scope(),
    provenance = { build = { ante = 2, decision_serial = 60 } } }
  local partial = FactHints.plan_note("shop")
  check("an unattributed field blocks the hoist rather than being credited",
    partial:find("All written by you", 1, true) == nil
      and partial:find("The rest written by you", 1, true) == nil, partial)
end

do
  local CtxJokers = require("context.ctx_jokers")
  local function roster_joker(name, sid, facing)
    return { sort_id = sid, facing = facing, sell_cost = 2, cost = 4, debuff = false,
      config = { center = { key = name } }, ability = { set = "Joker", name = name, extra = {} } }
  end
  local function board(cards, joker_intents)
    G.jokers = { cards = cards, config = { card_limit = 5 } }
    G.NEURO.joker_intents = joker_intents
    return CtxJokers.jokers_section("SHOP")
  end
  local function marks(text)
    local n = 0
    for _ in text:gmatch("%(written by you") do n = n + 1 end
    return n
  end
  local function rec(ante, serial) return { ante = ante, decision_serial = serial } end
  local A, B, C = roster_joker("Alpha", 101), roster_joker("Beta", 102), roster_joker("Gamma", 103)

  local shared = board({ A, B, C }, {
    [101] = { tag = "CORE", note = "anchor", provenance = rec(2, 41) },
    [102] = { tag = "HOLD", provenance = rec(2, 41) },
    [103] = { tag = "SCALING", provenance = rec(2, 41) },
  })
  check("three roster tags from one decision carry no inline mark", marks(shared) == 0, shared)
  check("their shared authorship is stated once, and named as covering all of them",
    select(2, shared:gsub("All plan tags above written by you, Ante 2, decision 41%.", "")) == 1,
    shared)
  check("no roster placeholder survives the substitution",
    shared:find("[\1\2]") == nil, shared)
  for _, kept in ipairs({ "1. Alpha", "2. Beta", "3. Gamma", "your plan: CORE", "your plan: HOLD",
      "your plan: SCALING", 'your note: "anchor"' }) do
    check("the roster hoist loses no row text: " .. kept, shared:find(kept, 1, true) ~= nil, shared)
  end

  local mixed = board({ A, B, C }, {
    [101] = { tag = "CORE", provenance = rec(2, 41) },
    [102] = { tag = "HOLD", provenance = rec(2, 41) },
    [103] = { tag = "SCALING", provenance = rec(3, 77) },
  })
  check("a row written at another decision keeps its own mark",
    mixed:find("your plan: SCALING (written by you, Ante 3, decision 77)", 1, true) ~= nil, mixed)
  check("and the roster clause then covers only the remainder",
    select(2, mixed:gsub("The rest of the plan tags above written by you, Ante 2, decision 41%.",
      "")) == 1, mixed)
  check("exactly one roster row pays for an inline mark", marks(mixed) == 1, mixed)
  do
    local prev, placed = nil, false
    for line in (mixed .. "\n"):gmatch("([^\n]*)\n") do
      if line:find("plan tags above written by you", 1, true) then
        placed = prev ~= nil and prev:find("^3%. Gamma") ~= nil
      end
      prev = line
    end
    check("the shared clause sits directly under the last roster row", placed, mixed)
  end

  local lone = board({ A }, { [101] = { tag = "CORE", provenance = rec(2, 41) } })
  check("a lone tagged joker keeps its inline mark", marks(lone) == 1, lone)
  check("and states no roster clause",
    lone:find("plan tags above written by you", 1, true) == nil, lone)

  local partial = board({ A, B, C }, {
    [101] = { tag = "CORE", provenance = rec(2, 41) },
    [102] = { tag = "HOLD", provenance = rec(2, 41) },
    [103] = { tag = "SCALING" },
  })
  check("an unattributed roster tag blocks the hoist rather than being credited",
    partial:find("plan tags above written by you", 1, true) == nil and marks(partial) == 2, partial)
  check("and the unattributed row is credited to nobody",
    partial:find("your plan: SCALING\n") ~= nil or partial:find("your plan: SCALING$") ~= nil,
    partial)

  local hidden = board({ A, B, roster_joker("Gamma", 103, "back") }, {
    [101] = { tag = "CORE", provenance = rec(2, 41) },
    [102] = { tag = "HOLD", provenance = rec(2, 41) },
    [103] = { tag = "SCALING", provenance = rec(3, 77) },
  })
  check("a face-down joker's row still says only that it is hidden",
    hidden:find("3. face-down (hidden)", 1, true) ~= nil
      and hidden:find("SCALING", 1, true) == nil, hidden)
  check("and the hoist covers exactly the rows that were rendered",
    select(2, hidden:gsub("All plan tags above written by you, Ante 2, decision 41%.", "")) == 1
      and marks(hidden) == 0, hidden)
end

done()
