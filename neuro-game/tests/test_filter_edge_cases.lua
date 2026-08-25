_G.NEURO_TEST = true

local Filtered = require("core.filtered")
local check, done = require("tests.helpers").harness("filter-edge-cases")

local function masked(s, strict) return Filtered.sanitize(s, strict) == "***" end
local function clean(s, strict)
  local out = Filtered.sanitize(s, strict)
  return out == s
end

local CLEAN = {
  "cockpit", "cocktail", "peacock", "shuttlecock", "cockatoo", "cockney", "cockroach",
  "scunthorpe", "shiitake", "snigger", "sniggered", "dickens", "dickinson",
}
for _, w in ipairs(CLEAN) do
  check("strict: clean word not masked: " .. w, not masked(w, true), Filtered.sanitize(w, true))
  check("loose: clean word untouched: " .. w, clean(w, false), Filtered.sanitize(w, false))
end

local NONSLUR = { "suspicious", "raccoon", "cocoon", "tycoon", "spicy", "spice", "assassin", "class", "analysis", "trigger" }
for _, w in ipairs(NONSLUR) do
  check("loose: non-slur clean word untouched: " .. w, clean(w, false), Filtered.sanitize(w, false))
end

check("loose: glued slur caught (bignigger)", masked("bignigger", false), Filtered.sanitize("bignigger", false))
check("loose: glued slur caught (superfaggot)", masked("superfaggot", false), Filtered.sanitize("superfaggot", false))
check("loose: glued slur inside sentence masked",
  Filtered.sanitize("you bignigger loser", false):find("%*%*%*") ~= nil,
  Filtered.sanitize("you bignigger loser", false))

check("strict: obfuscated slur still caught (spaced cunt)", masked("s cunt horpe extra", true), Filtered.sanitize("s cunt horpe extra", true))
check("strict: obfuscated slur still caught (n i g g e r)", masked("n i g g e r", true), Filtered.sanitize("n i g g e r", true))
check("strict: plain slur still caught", masked("nigger", true))
check("strict: glued profanity still caught (fuckyou)", masked("fuckyou", true))

check("loose: plain slur still masked", Filtered.sanitize("nigger", false):find("%*%*%*") ~= nil, Filtered.sanitize("nigger", false))
check("loose: benign game text untouched",
  clean("Play a flush for big chips and mult", false), Filtered.sanitize("Play a flush for big chips and mult", false))

done()
