_G.NEURO_TEST = true
_G.G = {}

local NumericEffects = require("facts.numeric_effects")
local CardUtil = require("facts.card_util")
local CtxHelpers = require("context.ctx_helpers")
local Vanilla = require("tests.fixtures.vanilla_jokers")

local check, done = require("tests.helpers").harness("conditional-effect-labels")

local SPEC = {}
for _, s in ipairs(NumericEffects) do SPEC[s.field] = s end

local GATED = {
  { "j_jolly",  "t_mult",  "Pair" },            { "j_zany",   "t_mult",  "Three of a Kind" },
  { "j_mad",    "t_mult",  "Two Pair" },        { "j_crazy",  "t_mult",  "Straight" },
  { "j_droll",  "t_mult",  "Flush" },
  { "j_sly",    "t_chips", "Pair" },            { "j_wily",   "t_chips", "Three of a Kind" },
  { "j_clever", "t_chips", "Two Pair" },        { "j_devious","t_chips", "Straight" },
  { "j_crafty", "t_chips", "Flush" },
  { "j_duo",    "x_mult",  "Pair" },            { "j_trio",   "x_mult",  "Three of a Kind" },
  { "j_family", "x_mult",  "Four of a Kind" },  { "j_order",  "x_mult",  "Straight" },
  { "j_tribe",  "x_mult",  "Flush" },
}

local function with_centers(cards, fn)
  local prev = _G.G
  local centers = {}
  for _, c in ipairs(cards) do centers[c.config.center.key] = c.config.center end
  _G.G = { P_CENTERS = centers }
  local ok, err = pcall(fn)
  _G.G = prev
  if not ok then error(err) end
end

local function bare(field, value)
  local s = SPEC[field]
  return s.op .. tostring(value) .. s.unit
end

for _, row in ipairs(GATED) do
  local key, field, hand = row[1], row[2], row[3]
  local card = Vanilla.card(key)
  local label = NumericEffects.label(card.ability, SPEC[field])
  local value = card.ability[field]
  check(key .. ": label names the hand type it is gated on",
    type(label) == "string" and label:find(hand, 1, true) ~= nil, tostring(label))
  check(key .. ": label is not the bare unconditional number",
    label ~= bare(field, value), tostring(label))

  with_centers({ card }, function()
    local fx = CardUtil.joker_fx(card)
    check(key .. ": joker_fx stamp carries the gate",
      fx ~= "" and fx:find(hand, 1, true) ~= nil, "[" .. tostring(fx) .. "]")
    check(key .. ": joker_fx stamp is not the bare unconditional number",
      fx ~= bare(field, value), "[" .. tostring(fx) .. "]")
  end)

  local joined = table.concat(CtxHelpers.effect_parts(card.ability), "|")
  check(key .. ": context effect_parts carries the gate",
    joined:find(hand, 1, true) ~= nil, joined)
end

-- Negative control: card.lua:4328 pays j_joker's flat mult with no gate at all, so its line must stay bare.
local plain = Vanilla.card("j_joker")
check("j_joker: label is exactly the bare number",
  NumericEffects.label(plain.ability, SPEC["mult"]) == "+4 Mult",
  tostring(NumericEffects.label(plain.ability, SPEC["mult"])))
check("j_joker: context effect_parts states +4 Mult unqualified",
  table.concat(CtxHelpers.effect_parts(plain.ability), "|") == "+4 Mult",
  table.concat(CtxHelpers.effect_parts(plain.ability), "|"))

check("x_mult with no hand type stays ungated",
  NumericEffects.label({ x_mult = 2, type = "" }, SPEC["x_mult"]) == "x2 Mult",
  tostring(NumericEffects.label({ x_mult = 2, type = "" }, SPEC["x_mult"])))
check("t_mult with no hand type is still marked conditional",
  (NumericEffects.label({ t_mult = 3, type = "" }, SPEC["t_mult"]) or ""):find("conditional", 1, true) ~= nil,
  tostring(NumericEffects.label({ t_mult = 3, type = "" }, SPEC["t_mult"])))

local greedy = Vanilla.card("j_greedy_joker")
local s_label = NumericEffects.label(greedy.ability, SPEC["s_mult"])
check("j_greedy_joker: s_mult label names the suit it is gated on",
  type(s_label) == "string" and s_label:find("Diamonds", 1, true) ~= nil, tostring(s_label))
check("s_mult unit carries no baked qualifier",
  SPEC["s_mult"].unit:find("conditional", 1, true) == nil, SPEC["s_mult"].unit)

for _, s in ipairs(NumericEffects) do
  check("spec " .. s.field .. " has no legacy conditional flag",
    s.cond == nil and s.type_cond == nil, s.field)
  check("spec " .. s.field .. " states its unit without a qualifier",
    s.unit:find("conditional", 1, true) == nil and s.unit:find("only ", 1, true) == nil, s.unit)
end

do
  local card = Vanilla.card("j_jolly")
  with_centers({ card }, function()
    check("joker_fx_line yields nothing when the description already states the effect",
      CardUtil.joker_fx_line(card, "+8 Mult if played hand contains a Pair") == "")
    check("joker_fx_line still stamps a card with no description",
      CardUtil.joker_fx_line(card, "") ~= "")
    check("joker_fx_line treats a nil description as absent",
      CardUtil.joker_fx_line(card, nil) ~= "")
  end)
end

check("a hand-type gate is spaced off the number",
  NumericEffects.label({ t_mult = 8, type = "Pair" }, SPEC["t_mult"]) == "+8 Mult (only if hand has Pair)",
  tostring(NumericEffects.label({ t_mult = 8, type = "Pair" }, SPEC["t_mult"])))
check("an unnameable gate is spaced off the number too",
  NumericEffects.label({ t_mult = 3, type = "" }, SPEC["t_mult"]) == "+3 Mult (conditional)",
  tostring(NumericEffects.label({ t_mult = 3, type = "" }, SPEC["t_mult"])))
check("an unnameable gate reaches the wire already spaced",
  CtxHelpers.humanize_effect(table.concat(CtxHelpers.effect_parts({ t_mult = 3, type = "" }), " · "))
    == "+3 Mult (conditional)",
  CtxHelpers.humanize_effect(table.concat(CtxHelpers.effect_parts({ t_mult = 3, type = "" }), " · ")))
check("a named gate reaches the wire already spaced",
  CtxHelpers.humanize_effect(table.concat(CtxHelpers.effect_parts({ t_chips = 50, type = "Pair" }), " · "))
    == "+50 Chips (only if hand has Pair)",
  CtxHelpers.humanize_effect(table.concat(CtxHelpers.effect_parts({ t_chips = 50, type = "Pair" }), " · ")))

do
  local CardSemantics = require("facts.card_semantics")
  local typed = { ability = { mult = 5, type = "Pair", set = "Joker" },
                  config = { center = { key = "j_mod_typed_mult", set = "Joker" } } }
  local row
  for _, e in ipairs(CardSemantics.project(typed).effects) do
    if e.source == "mult" then row = e end
  end
  check("a plain mult on a typed joker is not gated on the hand type",
    row ~= nil and row.hand_type == nil and row.certainty == "guaranteed",
    row and (tostring(row.hand_type) .. "/" .. tostring(row.certainty)))

  local held = { ability = { h_chips = 20, type = "Flush", set = "Joker" },
                 config = { center = { key = "j_mod_typed_held", set = "Joker" } } }
  row = nil
  for _, e in ipairs(CardSemantics.project(held).effects) do
    if e.source == "h_chips" then row = e end
  end
  check("a held-in-hand field on a typed joker keeps its held gate, not the hand type",
    row ~= nil and row.hand_type == nil and row.gate and row.gate.id == "held_card",
    row and (tostring(row.hand_type) .. "/" .. tostring(row.gate and row.gate.id)))

  local function gate_of(ability, source)
    for _, e in ipairs(CardSemantics.project({ ability = ability,
        config = { center = { key = "j_mod_asym", set = "Joker" } } }).effects) do
      if e.source == source then return e end
    end
  end
  local x = gate_of({ x_mult = 2, type = "", set = "Joker" }, "x_mult")
  check("x_mult with an empty type projects ungated (card.lua:4027)",
    x ~= nil and x.certainty == "guaranteed", x and x.certainty)
  local t = gate_of({ t_mult = 3, type = "", set = "Joker" }, "t_mult")
  check("t_mult with an empty type still projects conditional (card.lua:4034)",
    t ~= nil and t.certainty == "conditional", t and t.certainty)
  local xt = gate_of({ x_mult = 2, type = "Flush", set = "Joker" }, "x_mult")
  check("x_mult with a named type keeps its hand-type gate",
    xt ~= nil and xt.hand_type == "Flush", xt and tostring(xt.hand_type))
end

done()
