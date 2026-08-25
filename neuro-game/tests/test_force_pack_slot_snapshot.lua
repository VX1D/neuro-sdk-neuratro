_G.NEURO_TEST = true
love = { timer = { getTime = function() return 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {} }

local TD = require("tests.test_deadlock")
local check, done = require("tests.helpers").harness("force-pack-slot-snapshot")
local CardUtil = require("facts.card_util")

local scenario
for _, candidate in ipairs(TD.SCENARIOS) do
  if candidate.state == "BUFFOON_PACK"
      and candidate.desc == "BUFFOON_PACK variant with pack cards" then
    scenario = candidate
  end
end
assert(scenario, "BUFFOON_PACK fixture scenario not found in test_deadlock")

local calls = 0
local original_status = CardUtil.joker_slot_status
CardUtil.joker_slot_status = function(...)
  calls = calls + 1
  return original_status(...)
end

local mock = scenario.mock()
mock.jokers = { cards = { { ability = {} } }, config = { card_limit = 5 } }
TD.apply_mock(mock)
local ok, force = pcall(require("force.force_pack").build, "BUFFOON_PACK")
CardUtil.joker_slot_status = original_status

check("force_pack builds with a sellable joker and a Buffoon Pack present",
  ok and type(force) == "table" and type(force.query) == "string", tostring(force))
check("force_pack reuses one joker-slot snapshot instead of recomputing it",
  calls == 1, "calls=" .. calls)

done()
