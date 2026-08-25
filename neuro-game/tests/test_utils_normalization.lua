_G.NEURO_TEST = true
_G.G = { GAME = {} }

local Utils = require("util.utils")
local check, done = require("tests.helpers").harness("utils-normalization")

check("normalize_ws collapses controls, whitespace, and edges",
  Utils.normalize_ws(" \talpha\n\rbeta  ") == "alpha beta")

done()
