require("tests.stubs").setup({ love = "lazy" })

local check, done = require("tests.helpers").harness("buy-name-resolve")

local function card(name) return { ability = { name = name } } end
local function area(...) return { cards = { ... } } end

local CardArea = require("facts.card_area_util")
local function find(a, name, index)
  G = { jokers = a }
  local _, c, i = CardArea.resolve_target({ area = "jokers", index = index or 1, name = name },
    CardArea.TARGET_RULES.buy_from_shop)
  if c and c.ability.name ~= name then return nil end
  return c, i
end

do
  local a = area(card("Ice Cream"), card("Wily Joker"), card("Blueprint"))
  local c, i = find(a, "Wily Joker")
  check("unique match returns card+index", c == a.cards[2] and i == 2, tostring(i))
  local c2, i2 = find(a, "Wily Joker", 9)
  check("an index past the row still relocates by name", c2 == a.cards[2] and i2 == 2, tostring(i2))
end

do
  local a = area(card("Ice Cream"), card("Wily Joker"))
  local c1, i1 = find(a, "Wily")
  check("truncated target does not relocate", c1 == nil and i1 == nil, tostring(i1))
  local a2 = area(card("Joker"))
  local c2, i2 = find(a2, "Joker (Common)")
  check("decorated target does not relocate", c2 == nil and i2 == nil, tostring(i2))
end

do
  local a = area(card("Pareidolia"), card("Blueprint"), card("Pareidolia"))
  local c = find(a, "Pareidolia", 2)
  check("ambiguous match returns nil (no guess)", c == nil)
end

do
  local a = area(card("Ice Cream"), card("Blueprint"))
  check("absent name returns nil", find(a, "Wily Joker") == nil)
end

do
  local a = area(card("Ice Cream"), { ability = { name = "Wily Joker", wheel_flipped = true } })
  check("a face-down card is never found by name", find(a, "Wily Joker") == nil)
  check("empty area -> nil", find(area(), "X") == nil)
end

done()
