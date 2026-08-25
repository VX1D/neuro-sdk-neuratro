_G.G = {}
local CardArea = require("facts.card_area_util")
local check, done = require("tests.helpers").harness("target-name-guard")

local function card(n) return { ability = {}, config = { center = { name = n } } } end
local function guard(actual, provided)
  return CardArea.check_target_name(card(actual), provided, 1, "jokers")
end

check("an exact name passes", guard("Jolly Joker", "Jolly Joker") == nil)
check("a listing-truncated prefix passes", guard("Jolly Joker", "Jolly Jok") == nil)
check("case and whitespace differences are accepted", guard("Jolly  Joker", "jolly joker") == nil)
check("a substring that is not a prefix is rejected",
  guard("Jolly Joker", "Joker") ~= nil, tostring(guard("Jolly Joker", "Joker")))
check("a different card is rejected", guard("Steel Joker", "Blueprint") ~= nil)
check("an empty optional name is not checked", guard("Jolly Joker", "") == nil)

check("a leading 'The' on the board does not block a match",
  guard("The Hierophant", "Hierophant") == nil, tostring(guard("The Hierophant", "Hierophant")))
check("a leading 'The' from the model does not block a match",
  guard("Hierophant", "The Hierophant") == nil, tostring(guard("Hierophant", "The Hierophant")))
check("removing the article does not allow a non-prefix substring",
  guard("Jolly Joker", "Joker") ~= nil)
check("removing the article does not merge different card names",
  guard("The Duo", "Trio") ~= nil)
done()
