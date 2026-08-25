_G.NEURO_TEST = true
_G.G = {}

local Scoring = require("util.scoring")
local CardUtil = require("facts.card_util")
local CardSemantics = require("facts.card_semantics")
local DebuffFacts = require("facts.debuff_facts")
local Utils = require("util.utils")

local check, done = require("tests.helpers").harness("ability-fields")

local function jokers(list) G.jokers = { cards = list } end

-- Greedy/Lusty/Wrathful/Gluttonous store their mult under config.extra.s_mult (game.lua:386-389); ability.s_mult is always nil.
local function suit_joker(key, suit)
  return { ability = { extra = { s_mult = 3, suit = suit }, type = "" },
           config = { center = { key = key, set = "Joker" } } }
end

local greedy = suit_joker("j_greedy_joker", "Diamonds")
local projected
for _, e in ipairs(CardSemantics.project(greedy).effects) do
  if e.source == "s_mult" then projected = e end
end
check("extra.s_mult is projected", projected ~= nil and projected.value == 3, projected and projected.value)
check("s_mult is conditional, never guaranteed", projected and projected.certainty == "conditional",
  projected and projected.certainty)
check("empty ability.type normalizes to nil hand_type", projected and projected.hand_type == nil,
  projected and ("[" .. tostring(projected.hand_type) .. "]"))

-- The game applies s_mult per matching scoring card (card.lua:3597-3601), so it must land in the per-card total, not the per-hand total.
jokers({ greedy })
local s = Scoring.joker_summary()
check("a suit joker reaches the summary as a PER-CARD rate", s and s.cond_mult_per_card == 3,
  s and s.cond_mult_per_card)
check("a suit joker is NOT summed into the per-hand conditional total", s and s.cond_mult == 0,
  s and s.cond_mult)

jokers({ suit_joker("j_greedy_joker", "Diamonds"), suit_joker("j_lusty_joker", "Hearts"),
         suit_joker("j_wrathful_joker", "Spades"), suit_joker("j_gluttenous_joker", "Clubs") })
s = Scoring.joker_summary()
check("all four suit jokers total +12 per scoring card", s and s.cond_mult_per_card == 12,
  s and s.cond_mult_per_card)
check("four suit jokers still contribute 0 to the per-hand total", s and s.cond_mult == 0,
  s and s.cond_mult)
check("suit jokers stay out of the guaranteed flat Mult", s and s.mult == 0, s and s.mult)

jokers({ { ability = { h_chips = 25 } } })
s = Scoring.joker_summary()
local held_chips
for _, e in ipairs(s and s.conditional or {}) do
  if e.source == "h_chips" then held_chips = e end
end
check("h_chips is read as a per-held-card chips RATE, not a per-hand total",
  held_chips ~= nil and held_chips.scope == "held_card" and held_chips.rate == 25 and s.cond_chips == 0,
  held_chips and (held_chips.scope .. "/" .. tostring(held_chips.rate) .. "/" .. tostring(s.cond_chips)))

jokers({ { ability = { extra = { h_size = 5, h_mod = 1 } },
           config = { center = { key = "j_turtle_bean", set = "Joker" } } } })
s = Scoring.joker_summary()
check("Turtle Bean's extra.h_mod is not reported as chips",
  s == nil or (s.chips == 0 and s.cond_chips == 0),
  s and (tostring(s.chips) .. "/" .. tostring(s.cond_chips)))

jokers({ { ability = { c_mult = 5, d_mult = 5, p_mult = 5, chips = 5, h_mod = 5 } } })
s = Scoring.joker_summary()
check("fields absent from the game contribute nothing", s == nil, s and "summary returned")

jokers({ { ability = { extra = { Xmult = 2 } } }, { ability = { h_mult = 4 } } })
s = Scoring.joker_summary()
check("untyped conditional xMult is kept", s and s.cond_xmult == 2, s and s.cond_xmult)
local held_mult
for _, e in ipairs(s and s.conditional or {}) do
  if e.source == "h_mult" then held_mult = e end
end
check("untyped conditional flat Mult is kept as a per-held-card rate",
  held_mult ~= nil and held_mult.scope == "held_card" and held_mult.rate == 4 and s.cond_mult == 0,
  held_mult and (held_mult.scope .. "/" .. tostring(held_mult.rate) .. "/" .. tostring(s.cond_mult)))

-- The game gates a targeted consumable on #highlighted >= min_highlighted (card.lua:1887); Death is the one base card with min_highlighted = 2 (game.lua:563).
local death = { ability = { consumeable = { max_highlighted = 2, min_highlighted = 2 } },
                config = { center = { key = "c_death", set = "Tarot" } } }
local chariot = { ability = { consumeable = { max_highlighted = 1, min_highlighted = 1 } },
                  config = { center = { key = "c_chariot", set = "Tarot" } } }
G.hand = { cards = {} }
check("Death unusable with an empty hand", CardUtil.consumable_usable_now(death) == false)
G.hand = { cards = { {} } }
check("Death unusable with 1 card (needs 2)", CardUtil.consumable_usable_now(death) == false)
check("a min_highlighted=1 consumable is still usable with 1 card",
  CardUtil.consumable_usable_now(chariot) == true)
G.hand = { cards = { {}, {} } }
check("Death usable once the hand holds 2", CardUtil.consumable_usable_now(death) == true)

local BOSS_NAME = {
  bl_house = "The House", bl_fish = "The Fish", bl_wheel = "The Wheel", bl_mark = "The Mark",
  bl_final_vessel = "Violet Vessel", bl_final_acorn = "Amber Acorn",
}
local function set_blind(key, round)
  G.GAME = { blind = { config = { blind = { key = key } }, name = BOSS_NAME[key], debuff = {} },
             current_round = round or { hands_played = 0, discards_used = 0, hands_left = 4 } }
end
set_blind("bl_wheel")
check("blind_is resolves by name (the only live path -- real blinds carry no .key)",
  DebuffFacts.blind_is(G.GAME.blind, "bl_wheel") == true)
check("blind_is does not match a different boss by name",
  DebuffFacts.blind_is(G.GAME.blind, "bl_fish") == false)

check("The Wheel flips on any draw", DebuffFacts.boss_draws_facedown() == true)
set_blind("bl_mark")
check("The Mark flips on any draw", DebuffFacts.boss_draws_facedown() == true)
set_blind("bl_fish", { hands_played = 0, discards_used = 0, hands_left = 4 })
check("The Fish warns before the first play (prepped is already cleared by then)",
  DebuffFacts.boss_draws_facedown() == true)
set_blind("bl_fish", { hands_played = 2, discards_used = 0, hands_left = 1 })
check("The Fish still warns mid-blind", DebuffFacts.boss_draws_facedown() == true)
set_blind("bl_fish", { hands_played = 3, discards_used = 0, hands_left = 0 })
check("The Fish stops warning with no hands left to redraw into",
  DebuffFacts.boss_draws_facedown() == false)
set_blind("bl_house", { hands_played = 0, discards_used = 0, hands_left = 4 })
check("The House does not warn about future draws", DebuffFacts.boss_draws_facedown() == false)

-- Violet Vessel is mult=6 vs a normal boss's 2 (game.lua:293); Amber Acorn shuffles joker order (blind.lua:218-232).
set_blind("bl_final_vessel")
local BossRender = require("facts.boss.render")
local vessel = BossRender.boss_line("select", "bl_final_vessel", G.GAME.blind) or ""
check("Violet Vessel rule names the boss", vessel:find("Violet Vessel", 1, true) ~= nil, vessel)
check("Violet Vessel rule states the 3x target", vessel:find("3x", 1, true) ~= nil, vessel)
set_blind("bl_final_acorn")
local acorn = BossRender.boss_line("select", "bl_final_acorn", G.GAME.blind) or ""
check("Amber Acorn rule names the boss", acorn:find("Amber Acorn", 1, true) ~= nil, acorn)
check("Amber Acorn rule states the joker ORDER fact, the part that affects scoring",
  acorn:lower():find("order", 1, true) ~= nil, acorn)

-- Bootstraps' calculate is gated on floor(dollars/extra.dollars) >= 1 (card.lua:4394); in debt it contributes nothing, and the negative figure shown there is display-only (card.lua:1118).
local DynamicJokers = require("facts.dynamic_jokers")
local boot = { ability = { extra = { mult = 2, dollars = 5 } } }
local boot_mult = function(c) return DynamicJokers.read_from(c, DynamicJokers.ROWS.j_bootstraps[1].from) end
G.GAME = { dollars = -10, dollar_buffer = 0 }
check("Bootstraps contributes 0 in debt, never negative Mult", boot_mult(boot) == 0, boot_mult(boot))
G.GAME = { dollars = 4, dollar_buffer = 0 }
check("Bootstraps contributes 0 below one full step", boot_mult(boot) == 0, boot_mult(boot))
G.GAME = { dollars = 23, dollar_buffer = 0 }
check("Bootstraps scales with whole steps ($23 -> +8)", boot_mult(boot) == 8, boot_mult(boot))
G.GAME = { dollars = -10, dollar_buffer = 15 }
check("Bootstraps counts dollar_buffer like the game", boot_mult(boot) == 2, boot_mult(boot))

G.GAME = { hands = { Pair = { played = 0, visible = true },
                     ["Two Pair"] = { played = 6, visible = true },
                     ["Flush Five"] = { played = 0, visible = false } } }
local nova = DynamicJokers.per_hand_type("j_supernova").per_type
check("Supernova credits a never-played type (+1)", nova.Pair == 1, nova.Pair)
check("Supernova credits played+1 on a played type", nova["Two Pair"] == 7, nova["Two Pair"])
check("Supernova omits undiscovered secret hands", nova["Flush Five"] == nil, nova["Flush Five"])

local EconomyFacts = require("facts.economy_facts")
G.NEURO = { reserved_dollars = 0 }
G.GAME = { dollars = -10, bankrupt_at = -20, interest_cap = 25 }
check("safe-spend at a negative balance is the whole overdraft",
  EconomyFacts.safe_spend_keep_interest() == 10, EconomyFacts.safe_spend_keep_interest())
G.GAME = { dollars = 12, bankrupt_at = 0, interest_cap = 25 }
check("safe-spend keeps whole interest steps ($12 -> $2)",
  EconomyFacts.safe_spend_keep_interest() == 2, EconomyFacts.safe_spend_keep_interest())
G.GAME = { dollars = 12, bankrupt_at = 0, interest_cap = 25, modifiers = { no_interest = true } }
G.NEURO = { reserved_dollars = 5 }
check("safe-spend never exceeds spendable (reserved dollars honored)",
  EconomyFacts.safe_spend_keep_interest() == 7, EconomyFacts.safe_spend_keep_interest())

local GameFacts = require("facts.game_facts")

G.P_CENTERS = { j_card_sharp = { config = { extra = { Xmult = 3 } } } }
local sharp_fx = CardUtil.joker_fx({ ability = { extra = { Xmult = 3 } },
                                     config = { center = { key = "j_card_sharp" } } }) or ""
check("extra.Xmult produces a joker_fx string", sharp_fx ~= "", "[" .. sharp_fx .. "]")
check("extra.Xmult stamp carries the registry gate, never a bare number",
  sharp_fx == "x3 Mult (replaying a hand type you already played this round)", "[" .. sharp_fx .. "]")
G.P_CENTERS = nil

jokers({ { ability = { x_chips = 2 }, config = { center = { key = "j_x", set = "Joker" } } } })
s = Scoring.joker_summary()
check("guaranteed xchips reaches the summary", s and s.xchips == 2, s and s.xchips)

local steel_fx
for _, e in ipairs(CardSemantics.project(
      { ability = { h_x_mult = 1.5 }, config = { center = { key = "m_steel", set = "Enhanced" } } }).effects) do
  if e.source == "h_x_mult" then steel_fx = e end
end
check("h_x_mult projects as a conditional xMult",
  steel_fx and steel_fx.kind == "xmult" and steel_fx.value == 1.5 and steel_fx.certainty == "conditional",
  steel_fx and (steel_fx.kind .. "/" .. tostring(steel_fx.value)))
local zero_fx
for _, e in ipairs(CardSemantics.project(
      { ability = { h_x_mult = 0 }, config = { center = { key = "j_z", set = "Joker" } } }).effects) do
  if e.source == "h_x_mult" then zero_fx = e end
end
check("the h_x_mult default of 0 never becomes an x0 multiplier", zero_fx == nil)

--  Aura's gate also requires the target to be editionless (card.lua:1866)
local aura = { ability = { consumeable = {} }, config = { center = { key = "c_aura", set = "Spectral" } } }
G.hand = { cards = { { edition = { foil = true } } } }
check("Aura unusable when every hand card already has an edition",
  CardUtil.consumable_usable_now(aura) == false)
G.hand = { cards = { { edition = { foil = true } }, {} } }
check("Aura usable once an editionless card is in hand", CardUtil.consumable_usable_now(aura) == true)

G.NEURO = { blind_reward_cache = 5, blind_reward_round = 3 }
G.GAME = { round = 3 }
check("blind reward is honored inside its own round", GameFacts.blind_reward() == 5, GameFacts.blind_reward())
G.GAME = { round = 4 }
check("a blind reward stamped in an earlier round reads 0", GameFacts.blind_reward() == 0,
  GameFacts.blind_reward())

do
  local F = Utils.ABILITY_NUMERIC_FIELDS
  local expect = { "x_mult", "h_mult", "h_mod", "t_mult", "s_mult", "x_chips", "mult", "chips" }
  local same = #F == #expect
  if same then for i = 1, #expect do if F[i] ~= expect[i] then same = false end end end
  check("placeholder field order is exactly the known-real sequence", same, table.concat(F, ","))
  for _, ghost in ipairs({ "c_mult", "d_mult", "p_mult" }) do
    local found = false
    for _, f in ipairs(F) do if f == ghost then found = true end end
    check("ghost field '" .. ghost .. "' is not in the placeholder list", not found)
  end
  check("mult and chips stay last", F[#F - 1] == "mult" and F[#F] == "chips",
    tostring(F[#F - 1]) .. "," .. tostring(F[#F]))
end

do
  local function jk(key, name, sell)
    return { config = { center = { key = key } },
      ability = { name = name, set = "Joker", mult = 0 }, sell_cost = sell }
  end
  local prev = _G.G
  local sb, a, b = jk("j_swashbuckler", "Flibustier", 0), jk("j_a", "A", 3), jk("j_b", "B", 4)
  _G.G = { jokers = { cards = { sb, a, b } }, STAGE = 1 }
  sb.area, a.area, b.area = G.jokers, G.jokers, G.jokers
  Utils.refresh_dynamic_joker(sb)
  check("Swashbuckler refresh keys off the center key, not the English name",
    sb.ability.mult == 7, tostring(sb.ability.mult))

  local named_only = { config = { center = {} },
    ability = { name = "Swashbuckler", set = "Joker", mult = 0 } }
  _G.G = { jokers = { cards = { named_only, a, b } }, STAGE = 1 }
  named_only.area, a.area, b.area = G.jokers, G.jokers, G.jokers
  Utils.refresh_dynamic_joker(named_only)
  check("name fallback still works when no center key is present",
    named_only.ability.mult == 7, tostring(named_only.ability.mult))
  _G.G = prev
end

done()
