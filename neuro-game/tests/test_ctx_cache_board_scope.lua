_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("ctx-cache-board-scope")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local ContextCompact = require("context.context_compact")
local Metrics = require("util.metrics")

local MODDED = "MYMOD_PACK"

LB.load("TAROT_PACK", "Has pack cards")
check("the fallback branch under test is the cached one",
  require("context.context_readable").SUPPORTED[MODDED] == nil
    and require("core.dispatcher").get_force_for_state(MODDED) ~= nil,
  "MYMOD_PACK is not routed to the uncached ContextReadable path")

local function truth()
  ContextCompact.invalidate_cache()
  local t = FP.build(MODDED)
  ContextCompact.invalidate_cache()
  return t and t.state
end

local function drives(label, mutate, gone)
  LB.load("TAROT_PACK", "Has pack cards")
  ContextCompact.invalidate_cache()
  local before = FP.build(MODDED)
  check(label .. ": the first payload states the fact",
    before and before.state:find(gone, 1, true) ~= nil, gone .. " was never in the payload")
  local hits = Metrics._counters.ctx_cache_hit or 0
  mutate()
  local after = FP.build(MODDED)
  check(label .. ": the second payload is not the first one served again",
    after and before and after.state ~= before.state, "byte-identical payload across the change")
  check(label .. ": and it no longer states the retired fact",
    after and after.state:find(gone, 1, true) == nil, "still states " .. gone)
  local held = FP.build(MODDED)
  check(label .. ": an untouched board is still served from the cache",
    (Metrics._counters.ctx_cache_hit or 0) > hits and held and held.state == after.state,
    "no cache hit on the unchanged board -- the key is nondeterministic, not scoped")
  check(label .. ": and the served text equals the uncached truth",
    after and after.state == truth(), "cached text differs from an uncached build of the same board")
end

drives("a pack card taken", function()
  local pa = G.pack_cards or G.booster_pack
  table.remove(pa.cards, 1)
end, "3. 10 of Hearts")

drives("a voucher list change", function()
  G.GAME.used_vouchers = { grabber = true }
end, "overstock_norm")

done()
