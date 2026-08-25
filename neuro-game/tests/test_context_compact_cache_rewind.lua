_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local STATES = { SHOP = 5 }
local function world(real)
  _G.G = {
    STATE = STATES.SHOP, STATES = STATES,
    GAME = { dollars = 20, chips = 0, bankrupt_at = 0, used_vouchers = {}, modifiers = {},
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 1 }, probabilities = { normal = 1 } },
    NEURO = { run_generation = 1 },
    TIMERS = { REAL = real, TOTAL = real }, SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
  }
end
world(500)
_G.SMODS = { Mods = {} }

local check, done = require("tests.helpers").harness("context-compact-cache-rewind")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)
local Metrics = require("util.metrics")
local ContextCompact = require("context.context_compact")

ContextCompact.build("SHOP", nil, {})
check("the first build is a cache miss (nothing cached yet)",
  (Metrics._counters.ctx_cache_miss or 0) == 1, Metrics._counters.ctx_cache_miss)

world(12)
ContextCompact.build("SHOP", nil, {})
check("a cache filled before a clock rewind is not served as a hit across it",
  (Metrics._counters.ctx_cache_hit or 0) == 0, Metrics._counters.ctx_cache_hit)
check("the post-rewind build is counted as a fresh miss instead",
  (Metrics._counters.ctx_cache_miss or 0) == 2, Metrics._counters.ctx_cache_miss)

ContextCompact.build("SHOP", nil, {})
check("a genuinely fresh cache (same key, small forward dt) is still served as a hit",
  (Metrics._counters.ctx_cache_hit or 0) == 1, Metrics._counters.ctx_cache_hit)

done()
