_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local CtxMisc = require("context.ctx_misc")
local check, done = require("tests.helpers").harness("pack-planet-facts")

local function planet(key, hand)
  return {
    ability = { name = (key:gsub("^c_", ""):gsub("_", " ")), set = "Planet",
      consumeable = { hand_type = hand } },
    config = { center = { key = key, set = "Planet", config = { hand_type = hand } } },
  }
end
local function tarot(key)
  return {
    ability = { name = (key:gsub("^c_", ""):gsub("_", " ")), set = "Tarot", consumeable = {} },
    config = { center = { key = key, set = "Tarot" } },
  }
end

_G.G = {
  NEURO = {}, FUNCS = {},
  GAME = {
    current_round = {}, pack_choices = 2,
    hands = {
      ["Two Pair"] = { played = 42, level = 1 },
      ["Three of a Kind"] = { played = 1, level = 2 },
    },
  },
  consumeables = { cards = {}, config = { card_limit = 2 } },
}

G.pack_cards = { cards = { planet("c_uranus", "Two Pair"), planet("c_venus", "Three of a Kind"), tarot("c_fool") } }

local s = CtxMisc.pack_section("PLANET_PACK") or ""

check("Uranus row shows Two Pair played 42x lvl 1",
  s:find("played Two Pair 42x this run (lvl 1)", 1, true) ~= nil, s)
check("Venus row shows Three of a Kind played 1x lvl 2",
  s:find("played Three of a Kind 1x this run (lvl 2)", 1, true) ~= nil, s)

check("no garbled '-,' before the played-count suffix (empty-effect sentinel leak)",
  s:find("-, played", 1, true) == nil and s:find("— , played", 1, true) == nil, s)
check("Uranus row transitions cleanly from the dash straight into 'played'",
  s:find("— played Two Pair", 1, true) ~= nil, s)

local n = 0
for _ in s:gmatch("this run") do n = n + 1 end
check("exactly 2 played-count suffixes (planets only, not the Tarot)", n == 2, s)

check("no 'prefer' / 'most' steering in the pack rows",
  s:find("prefer", 1, true) == nil and s:find("most", 1, true) == nil, s)

G.GAME.hands["Flush"] = nil
G.pack_cards = { cards = { planet("c_jupiter", "Flush") } }
local ok, s2 = pcall(function() return CtxMisc.pack_section("PLANET_PACK") or "" end)
check("missing hand row is nil-guarded (no crash, no suffix)",
  ok and s2:find("this run", 1, true) == nil, tostring(ok) .. " :: " .. tostring(s2))

done()
