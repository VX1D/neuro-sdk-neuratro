rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local H = require("tests.helpers")
local check, done = H.harness("force-query-visibility")

local LB = require("tests.fixtures.live_board")
local FactHints = require("facts.fact_hints")
local CardUtil = require("facts.card_util")

local function sentinel(key, name, sort_id, facing)
  local card = LB.consumable(key, sort_id)
  card.ability.name = name
  card.config.center.name = name
  card.config.center.loc_txt.name = name
  card.facing = facing
  return card
end

local function shop_query(key, name, facing)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local card = sentinel(key, name, 9001, facing)
  card.area = G.shop_jokers
  G.shop_jokers.cards = { card }
  FactHints.reset_pending()
  local built = require("force.force_shop").build()
  return (type(built) == "table" and built.query) or ""
end

do
  local up = shop_query("c_hanged_man", "Sentinel Targeter", "front")
  check("a face-up targeting consumable is still named in the shop query",
    up:find("Sentinel Targeter", 1, true) ~= nil, up:sub(1, 400))

  local hidden = shop_query("c_hanged_man", "Sentinel Targeter", "back")
  check("a face-down shop card is not named in the shop query",
    hidden:find("Sentinel Targeter", 1, true) == nil,
    hidden:match("[^.]*Sentinel[^.]*") or hidden:sub(1, 400))
  check("and its targeting contract is not stated either",
    hidden:find("Targeting consumables here", 1, true) == nil,
    hidden:match("[^.]*Targeting[^.]*") or "")

  local other = shop_query("c_pluto", "Sentinel Leveller", "back")
  check("the shop query is byte-identical for two different face-down shop cards",
    hidden == other, "[" .. hidden:sub(1, 400) .. "] vs [" .. other:sub(1, 400) .. "]")
end

local function pack_query(key, name, facing)
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  local area = CardUtil.pack_area()
  local card = sentinel(key, name, 9002, facing)
  card.area = area
  area.cards = { card }
  FactHints.reset_pending()
  local built = require("force.force_pack").build()
  return (type(built) == "table" and built.query) or ""
end

do
  local up = pack_query("c_hanged_man", "Sentinel Targeter", "front")
  check("a face-up pack card is still named in the pack query",
    up:find("Sentinel Targeter", 1, true) ~= nil, up:sub(1, 400))

  local hidden = pack_query("c_hanged_man", "Sentinel Targeter", "back")
  check("a face-down pack card is not named in the pack query",
    hidden:find("Sentinel Targeter", 1, true) == nil,
    hidden:match("[^.]*Sentinel[^.]*") or hidden:sub(1, 400))

  local other = pack_query("c_pluto", "Sentinel Leveller", "back")
  check("the pack query is byte-identical for two different face-down pack cards",
    hidden == other, "[" .. hidden:sub(1, 400) .. "] vs [" .. other:sub(1, 400) .. "]")
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local negative = LB.joker("j_blueprint", 9003)
  negative.edition = { negative = true, key = "e_negative" }
  negative.facing = "front"
  G.shop_jokers.cards = { negative }
  check("a face-up Negative joker still answers area_has_negative_joker",
    CardUtil.area_has_negative_joker(G.shop_jokers) == true)

  negative.facing = "back"
  check("a face-down Negative joker does not",
    CardUtil.area_has_negative_joker(G.shop_jokers) == false)
  check("nor does it answer the area-wide edition probe",
    CardUtil.area_has_negative(G.shop_jokers) == false)
end

done()
