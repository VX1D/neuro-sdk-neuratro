_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("dynamic-mult")

local Scoring = require("util.scoring")
local Semantics = require("facts.card_semantics")
local DynamicJokers = require("facts.dynamic_jokers")

local function joker(key, name, ability, desc)
  ability = ability or {}
  ability.name = name
  ability.set = "Joker"
  return { config = { center = { key = key, set = "Joker", name = name,
    loc_txt = { name = name, description = { desc or "" } } } }, ability = ability }
end

local function guaranteed_of(card, kind)
  for _, e in ipairs(Semantics.project(card).effects) do
    if e.kind == kind and e.certainty == "guaranteed" and e.source ~= "edition" then return e.value end
  end
  return nil
end

local ridebus = joker("j_ride_the_bus", "Ride the Bus", { mult = 5 }, "gains +1 Mult per consecutive hand with no face card")
check("Ride the Bus flat mult forced guaranteed", guaranteed_of(ridebus, "mult") == 5)

local hologram = joker("j_hologram", "Hologram", { x_mult = 2.5 }, "gains X0.25 Mult per card added to deck")
check("Hologram flat xMult forced guaranteed", guaranteed_of(hologram, "xmult") == 2.5)

check("Popcorn flat mult counted", guaranteed_of(joker("j_popcorn", "Popcorn", { mult = 12 }, "loses 4 mult per round"), "mult") == 12)
check("Spare Trousers flat mult counted", guaranteed_of(joker("j_trousers", "Spare Trousers", { mult = 8 }, "gains +2 Mult if played hand contains Two Pair"), "mult") == 8)

_G.G = { GAME = { consumeable_usage_total = { tarot = 3 } } }
check("Fortune Teller injected from tarot usage", guaranteed_of(joker("j_fortune_teller", "Fortune Teller", { extra = 1 }, "gains +1 Mult per Tarot used"), "mult") == 3)

_G.G = { jokers = { cards = {} } }
local abstract = joker("j_abstract", "Abstract Joker", { extra = 3 }, "+3 Mult for each Joker card")
G.jokers.cards = { abstract, joker("j_joker", "Joker", { mult = 4 }) }
check("Abstract injected = extra * joker count", guaranteed_of(abstract, "mult") == 6, guaranteed_of(abstract, "mult"))

check("Steel Joker injected xMult = 1 + extra*tally",
  guaranteed_of(joker("j_steel_joker", "Steel Joker", { extra = 0.2, steel_tally = 3 }), "xmult") == 1.6,
  guaranteed_of(joker("j_steel_joker", "Steel Joker", { extra = 0.2, steel_tally = 3 }), "xmult"))

_G.G = { jokers = { cards = {
  joker("j_supernova", "Supernova", { extra = 1 }, "adds times played to Mult"),
  joker("j_joker", "Joker", { mult = 4 }),
} }, GAME = { hands = { ["Two Pair"] = { played = 6 }, ["Pair"] = { played = 2 } } } }
local agg = Scoring.joker_summary()
check("Supernova does NOT inflate the flat mult (stays the +4 joker only)", agg and agg.mult == 4, agg and agg.mult)
check("Supernova Two Pair per-type +7 (played 6 + 1)", agg and agg.cond_by_type["Two Pair"] and agg.cond_by_type["Two Pair"].mult == 7,
  agg and agg.cond_by_type["Two Pair"] and agg.cond_by_type["Two Pair"].mult)
check("Supernova Pair per-type +3 (played 2 + 1)", agg and agg.cond_by_type["Pair"] and agg.cond_by_type["Pair"].mult == 3)
check("Supernova per-type bucket flagged accumulator (render gate lifted even solo)",
  agg and agg.cond_by_type["Two Pair"] and agg.cond_by_type["Two Pair"].accumulator == true)

local greedy = joker("j_greedy_joker", "Greedy Joker", { t_mult = 3 }, "Diamond cards give +3 Mult when scored")
check("Greedy (real conditional) is NOT forced guaranteed", guaranteed_of(greedy, "mult") == nil)

local caino_rate = function(c) return DynamicJokers.read_from(c, DynamicJokers.ROWS.j_caino[1].from) end
check("the j_caino row's rate defaults to 1 (X1) when caino_xmult is unset",
  caino_rate({ ability = {} }) == 1, caino_rate({ ability = {} }))
check("the j_caino row's rate passes through the real value once set",
  caino_rate({ ability = { caino_xmult = 1.5 } }) == 1.5)
check("the j_caino row declares its scope and its dump branch",
  DynamicJokers.ROWS.j_caino[1].scope == "hand" and DynamicJokers.ROWS.j_caino[1].ref == 4400)

local fresh_caino = joker("j_caino", "Caino", { extra = 1 }, "This Joker gains X0.5 Mult when a face card is destroyed")
check("Fresh Caino has no guaranteed xMult effect (X1, not X0)", guaranteed_of(fresh_caino, "xmult") == nil)

_G.G = { jokers = { cards = {
  joker("j_caino", "Caino", { extra = 1 }, "This Joker gains X0.5 Mult when a face card is destroyed"),
  joker("j_joker", "Joker", { mult = 4 }),
} } }
local caino_agg = Scoring.joker_summary()
check("Fresh Caino does not zero the roster's guaranteed xMult", caino_agg and caino_agg.xmult == 1, caino_agg and caino_agg.xmult)
check("Fresh Caino leaves the other joker's flat Mult intact", caino_agg and caino_agg.mult == 4, caino_agg and caino_agg.mult)

local active_caino = joker("j_caino", "Caino", { extra = 1, caino_xmult = 1.5 }, "This Joker gains X0.5 Mult when a face card is destroyed")
check("Active Caino injected xMult from ability.caino_xmult", guaranteed_of(active_caino, "xmult") == 1.5)

check("add_effect refuses a degenerate xmult regardless of source",
  #Semantics.project(joker("j_test_zero_xmult", "Test", { x_mult = 0 })).effects == 0)

_G.G = { jokers = { cards = { joker("j_baron", "Baron", { extra = 1.5 }, "each King held gives X1.5 Mult"),
  joker("j_joker", "Joker", { mult = 4 }) } }, GAME = {} }
local agg2 = Scoring.joker_summary()
check("Baron per-King xMult not counted in flat guaranteed xmult", agg2 and agg2.xmult == 1, agg2 and agg2.xmult)
check("Baron counts as an xMult producer for ordering",
  Semantics.produces_xmult(joker("j_baron", "Baron", { extra = 1.5 })) == true)

do
  local function pcard(id, nominal, enh, debuff)
    local c = { base = { id = id, nominal = nominal, suit = "Spades" }, ability = {}, debuff = debuff,
      config = { center = { key = enh } } }
    function c:get_id() return enh == "m_stone" and -12345 or id end
    return c
  end
  local fist = joker("j_raised_fist", "Raised Fist", {}, "Adds double the rank of the lowest card held in hand to Mult")
  local function rate(hand)
    _G.G = { GAME = {}, jokers = { cards = { fist } }, hand = { cards = hand, config = { card_limit = 8 } } }
    for _, e in ipairs(Semantics.project(fist).effects) do
      if e.kind == "mult" then return e.value end
    end
    return nil
  end

  check("Raised Fist pays 2x the lowest ranked card held",
    rate({ pcard(9, 9), pcard(5, 5), pcard(13, 10) }) == 10, tostring(rate({ pcard(9, 9), pcard(5, 5) })))
  check("a Stone Card is skipped, not elected as the lowest",
    rate({ pcard(9, 9), pcard(2, 2, "m_stone"), pcard(13, 10) }) == 18,
    tostring(rate({ pcard(9, 9), pcard(2, 2, "m_stone"), pcard(13, 10) })))
  check("a debuffed lowest card pays nothing at all",
    rate({ pcard(9, 9), pcard(5, 5, nil, true) }) == nil,
    tostring(rate({ pcard(9, 9), pcard(5, 5, nil, true) })))
  check("a hand of nothing but Stone Cards pays nothing",
    rate({ pcard(2, 2, "m_stone"), pcard(7, 7, "m_stone") }) == nil,
    tostring(rate({ pcard(2, 2, "m_stone"), pcard(7, 7, "m_stone") })))
  check("a debuffed card that is NOT the lowest does not suppress the payout",
    rate({ pcard(9, 9, nil, true), pcard(5, 5) }) == 10,
    tostring(rate({ pcard(9, 9, nil, true), pcard(5, 5) })))
end

do
  local pipe = assert(io.popen("find context core facts force handlers hud render util -name '*.lua' | sort", "r"))
  local owners = {}
  for path in pipe:lines() do
    local fh = io.open(path, "r")
    if fh then
      local src = fh:read("*a")
      fh:close()
      if src:find("function%s+[%w_%.:]*no_rank%s*%(") then owners[#owners + 1] = path end
    end
  end
  pipe:close()
  check("exactly one module defines a no-rank predicate", #owners == 1, table.concat(owners, ", "))
  check("and it is facts/card_util.lua", owners[1] == "facts/card_util.lua", tostring(owners[1]))
end

local CardUtil = require("facts.card_util")
do
  local stone = { config = { center = { key = "m_stone" } }, base = { id = 2, nominal = 2 } }
  local plain = { config = { center = {} }, base = { id = 5, nominal = 5 } }
  function plain:get_id() return 5 end
  local negative = { config = { center = {} }, base = { id = 2, nominal = 2 } }
  function negative:get_id() return -12345 end
  check("the canonical predicate answers for a Stone Card with no get_id at all",
    CardUtil.has_no_rank(stone) == true)
  check("the canonical predicate answers for a negative get_id (card.lua:1174-1179)",
    CardUtil.has_no_rank(negative) == true)
  check("and stays false for an ordinary ranked card", CardUtil.has_no_rank(plain) == false)
end

done()
