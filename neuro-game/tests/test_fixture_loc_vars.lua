_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, TIMERS = { REAL = 100 },
  GAME = { current_round = {}, dollars = 12, starting_deck_size = 52,
    consumeable_usage = {}, consumeable_usage_total = { tarot = 3 } },
  jokers = { cards = {}, config = { card_limit = 5 } },
  deck = { cards = {} }, playing_cards = {} }

local check, done = require("tests.helpers").harness("fixture-loc-vars")

local Vanilla = require("tests.fixtures.vanilla_jokers")
local SemanticRegistry = require("core.semantic_registry")

local keys = Vanilla.keys()
check("the sweep has a roster to scan", #keys >= 140, tostring(#keys))

local unresolved = {}
for _, key in ipairs(keys) do
  local desc = SemanticRegistry.render("card_description_full", Vanilla.card_played(key, 900))
  if desc:find("?", 1, true) then unresolved[#unresolved + 1] = key .. " => " .. desc end
end
check("no vanilla joker description renders with an unresolved placeholder",
  #unresolved == 0, table.concat(unresolved, " | "):sub(1, 400))

local function desc(key) return SemanticRegistry.render("card_description_full", Vanilla.card_played(key, 900)) end

check("a two-placeholder hand-type joker binds count then hand name",
  desc("j_sly"):find("+50 Chips", 1, true) ~= nil and desc("j_sly"):find("a Pair", 1, true) ~= nil,
  desc("j_sly"))
check("a suit joker binds mult then suit",
  desc("j_greedy_joker"):find("+3 Mult", 1, true) ~= nil
  and desc("j_greedy_joker"):find("Diamond suit", 1, true) ~= nil, desc("j_greedy_joker"))
check("an accumulator joker shows both its rate and its current value",
  desc("j_hologram"):find("X0.25", 1, true) ~= nil
  and desc("j_hologram"):find("X1.5", 1, true) ~= nil, desc("j_hologram"))
check("a probability joker fills both sides of the odds",
  desc("j_cavendish"):find("1 in 1000", 1, true) ~= nil, desc("j_cavendish"))
check("a three-placeholder joker keeps all three",
  desc("j_green_joker"):find("+1 Mult", 1, true) ~= nil
  and desc("j_green_joker"):find("-1 Mult", 1, true) ~= nil, desc("j_green_joker"))

local fresh = SemanticRegistry.render("card_description_full", Vanilla.card("j_ceremonial", 900))
local played = desc("j_ceremonial")
check("a fresh accumulator reads 0 and a played one reads its progress",
  fresh:find("+0 Mult", 1, true) ~= nil and played:find("+6 Mult", 1, true) ~= nil,
  fresh .. " || " .. played)

done()
