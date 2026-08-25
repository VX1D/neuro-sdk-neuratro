local check, done = require("tests.helpers").harness("agnostic-observation-boundary")
local strip = require("tests.helpers").strip_lua_comments
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local shop, pack, hand, roster = strip(read("force/force_shop.lua")), strip(read("force/force_pack.lua")),
  strip(read("force/force_selecting_hand.lua")), strip(read("context/ctx_jokers.lua"))
local output_sources = shop .. pack .. hand
check("the force builders are readable", #output_sources > 0)
local CEILING = "more from jokers gated on something other than the hand type"
check("the ceiling clause is reachable only with a hand in play",
  roster:find("if led and not roster_only", 1, true) ~= nil)
check("the ceiling clause is withheld when its held-card count is a hidden card",
  roster:find("not held_count_unreadable(led)", 1, true) ~= nil)
check("the roster prescribes no move", not roster:find("you should", 1, true)
  and not roster:find("consider ", 1, true) and not roster:find("better to ", 1, true))
check("the ceiling clause has exactly one author", select(2, roster:gsub(CEILING, "")) == 1)
check("roster consumes positive engine observations", roster:find("JokerObservations.roster_line", 1, true) ~= nil)
check("the roster reads observations through one call, not per row",
  select(2, roster:gsub("JokerObservations%.", "")) == 1)
done()
