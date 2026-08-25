_G.NEURO_TEST = true
_G.G = { GAME = { hands = {
  Pair = { visible = true },
  Flush = { visible = true },
  Secret = { visible = false },
} } }

local check, done = require("tests.helpers").harness("visible-hand-names")
local names = require("facts.game_facts").visible_hand_names()

check("visible hand names are strict and sorted",
  type(names) == "table" and table.concat(names, ",") == "Flush,Pair",
  names and table.concat(names, ","))

done()
