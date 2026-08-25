_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = {}

local check, done = require("tests.helpers").harness("placeholder-guess-order")
local Utils = require("util.utils")

do
  local card = {
    ability = { x_mult = 2, extra = 5 },
    config = { center = { key = "j_test_holo_shape", set = "Joker",
      loc_txt = { description = { "Text #1# then #2#." } } } },
  }
  local desc = Utils.safe_description(card.config.center.loc_txt, card)
  check("the guesser never emits the fixed-list order it cannot verify",
    desc ~= "Text 2 then 5.", desc)
  check("nor does it emit the loc_vars order by luck",
    desc ~= "Text 5 then 2.", desc)
end

do
  local card = {
    ability = { x_mult = 2, extra = 5 },
    config = { center = { key = "j_test_holo_shape2", set = "Joker",
      loc_txt = { description = { "Text #1# then #2#." } } } },
  }
  local desc = Utils.safe_description(card.config.center.loc_txt, card)
  check("FIX CONTRACT: an ambiguous (2+ value) placeholder guess refuses instead of asserting an order",
    desc == "Text ? then ?.", desc)
end

do
  local card = {
    ability = { mult = 7 },
    config = { center = { key = "j_test_single_value", set = "Joker",
      loc_txt = { description = { "Text #1#." } } } },
  }
  local desc = Utils.safe_description(card.config.center.loc_txt, card)
  check("a single-value guess still renders (no ordering ambiguity, unaffected by the fix)",
    desc == "Text 7.", desc)
end

done()
