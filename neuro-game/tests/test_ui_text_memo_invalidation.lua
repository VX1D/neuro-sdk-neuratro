rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }

local check, done = require("tests.helpers").harness("ui text memo invalidation")

local function joker(key, name, ability)
  ability.name = name
  ability.set = "Joker"
  return { sort_id = key, cost = 5, sell_cost = 2, ability = ability,
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name, description = { "" } } } } }
end

_G.G = {
  TIMERS = { REAL = 100.0, TOTAL = 100.0 },
  SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
  GAME = {}, P_CENTERS = {}, localization = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  hand = { cards = {}, config = { card_limit = 8 } },
}

local Utils = require("util.utils")

local swash = joker("j_swashbuckler", "Swashbuckler", { mult = 0 })
local other = joker("j_joker", "Joker", { mult = 4 })
other.sell_cost = 3
local builds = 0
swash.generate_UIBox_ability_table = function(self)
  builds = builds + 1
  return { name = "Swashbuckler",
    main = { { config = { text = "Adds the sell value of all your other owned Jokers to Mult (currently +"
      .. tostring(self.ability.mult) .. " Mult)" } } } }
end
G.jokers.cards = { swash, other }
swash.area = G.jokers
other.area = G.jokers

local before = tostring(Utils.card_description_with_fallback(swash))
check("Swashbuckler renders the live sell total before the sale",
  before:find("+3 Mult", 1, true) ~= nil, before)

local builds_before = builds
local repeated = tostring(Utils.card_description_with_fallback(swash))
check("an unchanged board inside the TTL is still a memo hit (no rebuild)",
  builds == builds_before and repeated == before, builds .. " builds")

table.remove(G.jokers.cards, 2)
other.area = nil
G.TIMERS.REAL = 100.0 + 0.72
G.TIMERS.TOTAL = 100.0 + 0.72

local after = tostring(Utils.card_description_with_fallback(swash))
check("live ability.mult was recomputed to 0 by the refresh", swash.ability.mult == 0, swash.ability.mult)
check("the memo does not serve the pre-sale figure inside the TTL",
  after:find("+3 Mult", 1, true) == nil, after)
check("the memo serves the post-sale figure inside the TTL",
  after:find("+0 Mult", 1, true) ~= nil, after)

done()
