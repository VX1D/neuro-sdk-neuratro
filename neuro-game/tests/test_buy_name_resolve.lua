_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("buy-name-resolve")

local function card(name) return { ability = { name = name } } end
local function area(...) return { cards = { ... } } end

local CardArea = require("facts.card_area_util")
local find = CardArea.find_card_by_name

do
  local a = area(card("Ice Cream"), card("Wily Joker"), card("Blueprint"))
  local c, i = find(a, "Wily Joker")
  check("unique match returns card+index", c == a.cards[2] and i == 2, tostring(i))
end

do
  local a = area(card("Ice Cream"), card("Wily Joker"))
  local c1, i1 = find(a, "Wily")
  check("substring (want in have) matches", c1 == a.cards[2] and i1 == 2, tostring(i1))
  local a2 = area(card("Joker"))
  local c2, i2 = find(a2, "Joker (Common)")
  check("substring (have in want) matches", c2 == a2.cards[1] and i2 == 1, tostring(i2))
end

do
  local a = area(card("Pareidolia"), card("Blueprint"), card("Pareidolia"))
  local c = find(a, "Pareidolia")
  check("ambiguous match returns nil (no guess)", c == nil)
end

do
  local a = area(card("Ice Cream"), card("Blueprint"))
  check("absent name returns nil", find(a, "Wily Joker") == nil)
end

do
  check("nil name -> nil", find(area(card("X")), nil) == nil)
  check("empty name -> nil", find(area(card("X")), "") == nil)
  check("nil area -> nil", find(nil, "X") == nil)
  check("empty area -> nil", find(area(), "X") == nil)
end

done()
