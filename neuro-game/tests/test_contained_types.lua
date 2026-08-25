_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local HandFacts = require("facts.hand_facts")
local check, done = require("tests.helpers").harness("contained-types")

local function card(suit, value) return { base = { suit = suit, value = value } } end
local RED = { Hearts = true, Diamonds = true }
local function red_card(base_suit, value)
  return { base = { suit = base_suit, value = value },
           is_suit = function(_, suit) return RED[suit] == true end }
end
local function contains(cards) return HandFacts.contained_types(cards) end

do
  local hand = {
    card("Hearts", "King"), card("Hearts", "King"), card("Hearts", "King"),
    card("Hearts", "2"), card("Hearts", "3"),
    card("Spades", "Queen"), card("Spades", "Queen"),
  }
  local t = contains(hand)
  check("flush present (5 hearts)", t["Flush"] == true)
  check("full house present (KKK + QQ across suits)", t["Full House"] == true)
  check("NO flush house: the pair (QQ) is not in the flush suit", t["Flush House"] ~= true, "false-positive")
end

do
  local hand = {
    card("Hearts", "King"), card("Hearts", "King"), card("Hearts", "King"),
    card("Hearts", "2"), card("Hearts", "2"),
  }
  local t = contains(hand)
  check("real flush house: full house entirely within hearts", t["Flush House"] == true)
end

do
  local hand = {
    card("Hearts", "King"), card("Hearts", "King"), card("Hearts", "King"),
    card("Hearts", "King"), card("Hearts", "King"),
  }
  local t = contains(hand)
  check("flush five: five kings all hearts", t["Flush Five"] == true)
  check("five of a kind present", t["Five of a Kind"] == true)
end

do
  local hand = {
    card("Hearts", "King"), card("Spades", "King"), card("Clubs", "King"),
    card("Hearts", "2"), card("Spades", "2"),
  }
  local t = contains(hand)
  check("mixed full house is Full House", t["Full House"] == true)
  check("mixed full house is NOT a flush", t["Flush"] ~= true)
  check("mixed full house is NOT a flush house", t["Flush House"] ~= true)
end

do
  local hand = {
    red_card("Hearts", "King"), red_card("Hearts", "King"), red_card("Diamonds", "King"),
    red_card("Hearts", "Queen"), red_card("Hearts", "Queen"), red_card("Hearts", "2"),
  }
  local t = contains(hand)
  check("smeared cross-suit flush house detected (in_suit spans red, base suits differ)", t["Flush House"] == true, "modifier false-negative")
end

do
  local hand = {
    card("Hearts", "King"), card("Hearts", "King"), card("Hearts", "King"),
    card("Hearts", "2"), card("Hearts", "3"),
    card("Diamonds", "Queen"), card("Diamonds", "Queen"),
  }
  local t = contains(hand)
  check("no-smear: hearts flush + off-suit pair is NOT a flush house", t["Flush House"] ~= true, "false-positive")
end

done()
