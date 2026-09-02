_G.NEURO_TEST = true
_G.G = {}
local CardUtil = require("facts.card_util")

local check, done = require("tests.helpers").harness("pack-area")

G.pack_cards = { cards = {} }
check("live pack_cards returned", CardUtil.pack_area() == G.pack_cards)

G.pack_cards = { cards = nil }
G.booster_pack = { cards = {} }
check("removed pack_cards skipped, falls through to booster_pack", CardUtil.pack_area() == G.booster_pack)

G.pack_cards = { cards = {}, REMOVED = true }
G.booster_pack = nil
check("REMOVED-flagged pack_cards -> nil", CardUtil.pack_area() == nil)

G.pack_cards = { cards = nil }
G.booster_pack = { cards = nil }
check("both dead -> nil", CardUtil.pack_area() == nil)

G.pack_cards = nil
G.booster_pack = { cards = {} }
check("booster_pack live when no pack_cards", CardUtil.pack_area() == G.booster_pack)

G.pack_cards = nil
G.booster_pack = nil
check("no areas -> nil", CardUtil.pack_area() == nil)

local Dispatcher = require("core.dispatcher")

G.pack_cards, G.booster_pack, G.GAME = nil, nil, nil
check("skip rejected when no pack is open", Dispatcher.skip_pack_reject_reason() ~= nil)

G.pack_cards, G.booster_pack = { cards = { {} } }, nil
G.GAME = { STOP_USE = 0 }
check("skip allowed on a live pack when STOP_USE=0", Dispatcher.skip_pack_reject_reason() == nil)

G.GAME.STOP_USE = 3
local r = Dispatcher.skip_pack_reject_reason()
check("skip rejected while STOP_USE>0 (double-close guard)", r ~= nil and tostring(r):find("resolving") ~= nil, r)

G.GAME.STOP_USE = nil
check("skip allowed again once STOP_USE clears (nil)", Dispatcher.skip_pack_reject_reason() == nil)

done()
