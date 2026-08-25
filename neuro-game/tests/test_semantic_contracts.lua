_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("semantic contracts")

_G.G = {
  NEURO = { run_generation = 1 },
  GAME = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
}

local Semantics = require("facts.card_semantics")
local Registry = require("core.semantic_registry")
local Scoring = require("util.scoring")

local walkie = {
  ability = { set = "Joker", name = "Walkie Talkie", extra = { chips = 10, mult = 4 } },
  config = { center = {
    key = "j_walkie_talkie", set = "Joker", name = "Walkie Talkie",
    loc_txt = { name = "Walkie Talkie", description = {
      "Played 10s and 4s give +10 Chips and +4 Mult when scored.",
    } },
  } },
}
local function card_with_description(text)
  return {
    ability = { set = "Joker", name = "Long Rule" },
    config = { center = { key = "j_long_rule", set = "Joker", name = "Long Rule",
      loc_txt = { name = "Long Rule", description = { text } } } },
  }
end

local projected = Semantics.project(walkie)
local conditional = {}
for _, effect in ipairs(projected.effects) do
  conditional[effect.kind] = (conditional[effect.kind] or 0) +
    (effect.certainty == "conditional" and effect.value or 0)
end
check("semantics: Walkie numeric fields remain conditional",
  conditional.mult == 4 and conditional.chips == 10)
G.jokers.cards = { walkie }
local aggregate = Scoring.joker_summary()
check("semantics: conditional Walkie bonus is excluded from guaranteed totals",
  aggregate and aggregate.mult == 0 and aggregate.chips == 0
    and #aggregate.conditional >= 2)
check("semantics: conditional XMult capability is not inferred from numeric storage",
  not Scoring.owned_has_xmult())

local plain = {
  ability = { set = "Joker", name = "Joker", mult = 4 },
  config = { center = {
    key = "j_joker", set = "Joker", name = "Joker",
    loc_txt = { name = "Joker", description = { "+4 Mult." } },
  } },
}
G.jokers.cards = { plain }
aggregate = Scoring.joker_summary()
check("semantics: unconditional plain Joker contributes guaranteed Mult",
  aggregate and aggregate.mult == 4 and #aggregate.conditional == 0)

local conditional_x = {
  ability = { set = "Joker", extra = { x_mult = 3 } },
  config = { center = {
    key = "j_cond_x", set = "Joker", name = "Conditional X",
    loc_txt = { description = { "X3 Mult if played hand contains a Pair." } },
  } },
}
G.jokers.cards = { conditional_x }
check("semantics: conditional XMult does not satisfy guaranteed capability",
  not Scoring.owned_has_xmult())
conditional_x.config.center.loc_txt.description = { "X3 Mult." }
check("semantics: unconditional XMult satisfies guaranteed capability",
  Scoring.owned_has_xmult())

local projections = {
  "card_effect_summary", "owned_joker_row", "shop_card_row",
  "pack_card_row", "consumable_row", "readable_joker",
}
local canonical = Registry.render(projections[1], walkie)
local consistent = true
for i = 2, #projections do
  if Registry.render(projections[i], walkie) ~= canonical then consistent = false end
end
check("semantics: every card projection shares the canonical rule renderer", consistent)
check("semantics: canonical renderer preserves trigger and target",
  canonical:find("10s and 4s", 1, true) ~= nil, canonical)

check("length: the truncating entry point is gone", Semantics.complete_text == nil)
local two_rules = "Gain +4 Mult when a Pair is played. Gain +20 Chips when a 10 is scored. "
  .. "Gain +2 Mult for every discard you have left at the end of the round. "
  .. "Destroy the Joker to the right when this blind is selected and add double its sell value here. "
  .. "Retrigger every played card whose rank is 2, 3, 4 or 5. "
  .. "This Joker is destroyed if you ever hold more than five consumables at once."
local multi = card_with_description(two_rules)
check("length: the fixture is past the removed 320-char cap", #two_rules > 320, #two_rules)
check("length: every rule of a multi-rule card reaches the projection",
  Registry.render("card_description_full", multi) == two_rules,
  Registry.render("card_description_full", multi))
local long_rule = "When the first played hand of the round contains exactly one card, permanently add +1 Mult to this Joker, and this repeats for every subsequent round in which the same thing happens again."
check("length: a rule far past every removed cap (320/140/80) is delivered whole",
  Registry.render("owned_joker_row", card_with_description(long_rule)) == long_rule,
  Registry.render("owned_joker_row", card_with_description(long_rule)))

local registry_ok, registry_errors = Registry.validate()
check("semantics: projection registry is exhaustive", registry_ok, table.concat(registry_errors or {}, "; "))

done()
