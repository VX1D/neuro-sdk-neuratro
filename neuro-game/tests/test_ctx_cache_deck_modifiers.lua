_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
require("tests.raster_capture")

local check, done = require("tests.helpers").harness("ctx-cache-deck-modifiers")
local ContextCompact = require("context.context_compact")

local function card()
  return { base = { value = "10", suit = "Hearts" }, ability = { name = "x", set = "Default" },
    config = { center = { key = "c_base" } } }
end

local deck
local function board()
  deck = {}
  for i = 1, 8 do deck[i] = card() end
  _G.G = {
    NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 1 },
    FUNCS = {},
    GAME = { hands = { ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 0 } },
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5, free_rerolls = 0 },
      dollars = 12, round = 1, used_vouchers = {}, modifiers = {}, interest_cap = 25,
      interest_amount = 1, starting_params = {}, round_resets = { ante = 1, blind_choices = {} },
      blind = { name = "Small Blind", chips = 300 } },
    hand = { cards = {}, config = {}, highlighted = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = deck }, playing_cards = deck,
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
  ContextCompact.invalidate_cache()
end

local OPTS = { split = "state", force_phase = true }
local ACTS = { "play_hand", "discard_hand" }
local function build() return ContextCompact.build("SELECTING_HAND", ACTS, OPTS) end

local MUTATIONS = {
  { "enhancement", function(c) c.ability.enhancement = "m_steel"; c.config.center.key = "m_steel" end },
  { "seal",        function(c) c.seal = "Gold" end },
  { "edition",     function(c) c.edition = { key = "e_foil", foil = true } end },
  { "rank",        function(c) c.base.value = "Ace" end },
  { "suit",        function(c) c.base.suit = "Spades" end },
}

for _, m in ipairs(MUTATIONS) do
  board()
  local before = build()
  m[2](deck[1])
  local after = build()
  local fresh = ContextCompact.build("SELECTING_HAND", ACTS,
    { split = "state", force_phase = true, no_cache = true })
  check("a " .. m[1] .. " change outside the hand moves the cached context",
    before ~= after, "cached text survived the " .. m[1] .. " change")
  check("and the cached text after it equals the uncached truth",
    after == fresh, after)
end

do
  local Metrics = require("util.metrics")
  board()
  build()
  local before = Metrics._counters.ctx_cache_hit or 0
  local a = build()
  local b = build()
  local hits = (Metrics._counters.ctx_cache_hit or 0) - before
  check("an unchanged board still hits the cache", hits == 2 and a == b, tostring(hits))
end

done()
