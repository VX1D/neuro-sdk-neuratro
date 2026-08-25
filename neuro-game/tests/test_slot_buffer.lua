_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local CU = require("facts.card_util")
local check, done = require("tests.helpers").harness("slot-buffer")

local function base()
  _G.G = {
    jokers = { cards = { {}, {} }, config = { card_limit = 5 } },
    consumeables = { cards = { {} }, config = { card_limit = 2 } },
    GAME = {},
  }
end

base()
local s = CU.joker_slot_status()
check("no buffer: joker count is #cards", s.count == 2 and not s.full, s.count)

G.GAME.joker_buffer = 1
local s2 = CU.joker_slot_status()
check("joker_buffer counts toward slots (incoming Judgement/spectral joker)", s2.count == 3, s2.count)

G.jokers.cards = { {}, {}, {}, {} }
local s3 = CU.joker_slot_status()
check("4 cards + buffer 1 = full (5/5)", s3.count == 5 and s3.full, s3.count)

base()
G.GAME.consumeable_buffer = 1
local c = CU.consumable_slot_status()
check("consumeable_buffer counts (Cartomancer tarot in flight)", c.count == 2 and c.full, c.count)

base()
G.GAME.joker_buffer = nil
check("nil buffer is safe (treated as 0)", CU.joker_slot_status().count == 2)

done()
