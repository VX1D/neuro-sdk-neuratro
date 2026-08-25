
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Config = require("core.config")
local ContextCompact = require("context.context_compact")
local Orchestrator = require("core.orchestrator") -- exposes _maybe_emit_stable_context under NEURO_TEST
local Bridge = require("core.bridge")

if type(Orchestrator._maybe_emit_stable_context) ~= "function" then
  print("FATAL: Orchestrator._maybe_emit_stable_context test seam missing (NEURO_TEST hooks)")
  os.exit(2)
end

local SEED  = tonumber(arg and arg[1]) or 20260722
local ITERS = tonumber(arg and arg[2]) or 4000
math.randomseed(SEED)
local function ri(a, b) return math.random(a, b) end
local function pick(t) return t[ri(1, #t)] end
local function chance(p) return math.random() < p end

local SUITS = { "Hearts", "Clubs", "Diamonds", "Spades" }
local RANKS = { "2","3","4","5","6","7","8","9","10","Jack","Queen","King","Ace" }
local JOKER_POOL = {
  { key="j_joker", name="Joker", ab={ mult=4 }, desc="+4 Mult" },
  { key="j_crazy", name="Crazy Joker", ab={ mult=12, type="Straight" }, desc="+12 Mult if played hand contains a Straight" },
  { key="j_baron", name="Baron", ab={ extra={ Xmult=1.5 } }, desc="Each King held in hand gives X1.5 Mult" },
  { key="j_bull", name="Bull", ab={ chips=0 }, desc="+2 Chips for each dollar you have" },
  { key="j_loyalty_card", name="Loyalty Card", ab={ extra={ Xmult=4 } }, desc="X4 Mult every 6 hands played" },
  { key="j_greedy_joker", name="Greedy Joker", ab={ mult=3, type="Diamonds" }, desc="Played Diamond cards give +3 Mult when scored" },
}
local EDITIONS = { false, false, { foil=true }, { holo=true }, { polychrome=true }, { negative=true } }
local BOSSES = { false, { suit="Clubs", name="The Club" }, { is_face="face", name="The Plant" }, { h_size_ge=5, name="The Psychic" } }

local function make_joker(def, ed)
  local ab = {}; for k,v in pairs(def.ab) do ab[k]=v end; ab.name, ab.set = def.name, "Joker"
  return { cost=4, sell_cost=ri(1,4), ability=ab, edition=ed or nil, debuff=false,
    config={ center={ key=def.key, name=def.name, set="Joker", loc_txt={ name=def.name, description=def.desc } } } }
end

local function build_stable_state()
  local state = pick({ "SELECTING_HAND", "SHOP" })
  local boss = pick(BOSSES)
  G.GAME = {
    dollars = ri(0, 30), bankrupt_at = 0,
    current_round = { hands_left = ri(0, 4), discards_left = ri(0, 4), reroll_cost = 5 },
    round_resets = { ante = ri(1, 8), blind_choices = { Small="bl_small", Big="bl_big", Boss="bl_boss" },
      blind_states = { Small="Defeated", Big="Defeated", Boss="Select" }, boss_rerolled = false },
    blind = { chips = ri(100, 4000), mult = 2, name = boss and boss.name or "Big Blind",
      debuff = boss and { suit=boss.suit, is_face=boss.is_face, h_size_ge=boss.h_size_ge } or nil, disabled = false },
    blind_on_deck = boss and "Boss" or "Big", chips = 0, used_vouchers = {}, stake = 1, pack_choices = 1,
  }
  local jc = {}; for i = 1, ri(1, 5) do jc[i] = make_joker(pick(JOKER_POOL), pick(EDITIONS) or nil) end
  G.jokers = { cards = jc, config = { card_limit = 5 } }
  G.hand = { cards = {}, highlighted = {} }
  for i = 1, 6 do G.hand.cards[i] = { base = { value = pick(RANKS), suit = pick(SUITS) }, ability = { set = "Default" }, config = { center = { key = "c_base" } }, debuff = false } end
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  if state == "SHOP" then
    G.shop_jokers = { cards = { make_joker(pick(JOKER_POOL)) } }
    G.shop_vouchers = { cards = {} }; G.shop_booster = { cards = {} }; G.shop = { reroll_cost = 5 }
  end
  return state
end

local function make_bridge()
  local b = { emitted = {}, llm_paused = false,
    dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0,
  shop_reroll_count = 0, state_enter_serial = 1 }
  function b:send_context(message, _, receipt)
    if self.llm_paused then if receipt then receipt.status = "rejected" end return false end
    self.emitted[#self.emitted + 1] = message or ""
    if receipt then receipt.status = "written" end
    return true
  end
  b.register_actions = function() end
  b.send = function() end
  return b
end

local ALT_POOL = { "STABLE-A " .. string.rep("x", 60), "STABLE-B " .. string.rep("y", 60),
  "How to decide " .. string.rep("z", 40) }

local double_sends, mutable_leaks, alt_dropped, dead_channels = {}, {}, {}, {}
local ran = 0

local function live_mutation(it)
  local gm = G.GAME
  gm.dollars = 40000 + it
  gm.chips = 900000 + it
  gm.current_round.hands_left = (gm.current_round.hands_left + 2) % 5
  gm.current_round.discards_left = (gm.current_round.discards_left + 3) % 5
  gm.blind.chips = gm.blind.chips + 777
  gm.used_vouchers = { v_hone = true, v_glow_up = true }
  gm.modifiers = { no_interest = true }
  G.jokers.cards[#G.jokers.cards + 1] = make_joker(pick(JOKER_POOL), { polychrome = true })
  G.consumeables.cards[#G.consumeables.cards + 1] =
    { ability = { set = "Tarot", name = "The Fool" }, config = { center = { key = "c_fool", set = "Tarot" } } }
  G.hand.cards[#G.hand.cards + 1] = { base = { value = "Ace", suit = "Spades" },
    ability = { set = "Default" }, config = { center = { key = "c_base" } }, debuff = false }
end

local function emit_retained(state)
  local b = make_bridge(); G.NEURO = b
  require("core.context_delivery").reset_transport()
  ContextCompact.invalidate_cache()
  b.stable_refresh_due = true
  Orchestrator._maybe_emit_stable_context(state)
  return b, table.concat(b.emitted, "\n")
end

local function first_difference(a, b)
  for i = 1, math.min(#a, #b) do
    if a:sub(i, i) ~= b:sub(i, i) then return i end
  end
  return math.min(#a, #b) + 1
end

for it = 1, ITERS do
  local state = build_stable_state()
  local cash_sentinel = tostring(30000 + it)
  G.GAME.dollars = tonumber(cash_sentinel)
  local b, before_text = emit_retained(state)
  ran = ran + 1
  local base = #b.emitted

  if base == 0 or #before_text < 40 then
    dead_channels[#dead_channels + 1] = { it = it, state = state, frames = base,
      bytes = #before_text }
  end
  if before_text:find(cash_sentinel, 1, true) then
    mutable_leaks[#mutable_leaks + 1] = { it = it, state = state,
      why = "live cash " .. cash_sentinel .. " inside a retained frame" }
  end

  local resent, rounds = 0, ri(2, 6)
  for r = 1, rounds do
    b:send_context("~volatile interleave marker " .. it .. "-" .. r, true)
    b.stable_refresh_due = true
    local before = #b.emitted
    Orchestrator._maybe_emit_stable_context(state)
    if #b.emitted > before then resent = resent + 1 end
  end
  if resent > 0 then
    double_sends[#double_sends + 1] = { it = it, state = state, resent = resent, rounds = rounds,
      sample = b.emitted[base > 0 and base or 1] }
  end

  live_mutation(it)
  ContextCompact.invalidate_cache()
  b.stable_refresh_due = true
  local before = #b.emitted
  local ok_emit, emit_err = pcall(Orchestrator._maybe_emit_stable_context, state)
  if not ok_emit then
    mutable_leaks[#mutable_leaks + 1] = { it = it, state = state,
      why = "retained key rewritten: " .. tostring(emit_err) }
  elseif #b.emitted > before then
    mutable_leaks[#mutable_leaks + 1] = { it = it, state = state,
      why = "run mutation produced a new retained frame" }
  end

  local _, after_text = emit_retained(state)
  if after_text ~= before_text then
    local at = first_difference(before_text, after_text)
    mutable_leaks[#mutable_leaks + 1] = { it = it, state = state,
      why = "retained bytes follow the run at offset " .. at,
      sample = "was: " .. before_text:sub(at - 40 < 1 and 1 or at - 40, at + 60)
        .. "  now: " .. after_text:sub(at - 40 < 1 and 1 or at - 40, at + 60) }
  end
  G.NEURO = b

  local rb = Bridge:new({ game = "Balatro", enabled = true })
  rb.frames = {}
  rb.send = function(self, message) self.frames[#self.frames + 1] = message return true end
  local seq = {}
  for i = 1, ri(4, 10) do seq[i] = pick(ALT_POOL) end
  for _, m in ipairs(seq) do rb:send_context(m, true) end
  if #rb.frames ~= #seq then
    alt_dropped[#alt_dropped + 1] = { it = it, sent = #seq, framed = #rb.frames }
  else
    for i = 1, #seq do
      local f = rb.frames[i]
      if not (type(f) == "table" and f.command == "context" and type(f.data) == "table"
              and f.data.message == seq[i] and f.data.silent == true) then
        alt_dropped[#alt_dropped + 1] = { it = it, sent = #seq, framed = #rb.frames, at = i,
          got = type(f) == "table" and tostring(f.command) or type(f) }
        break
      end
    end
  end
end

local function banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end
banner(string.format("EMIT-SCAN FUZZ  seed=%d iters=%d rendered=%d double_sends=%d alternation_drops=%d mutable_leaks=%d dead_channels=%d",
  SEED, ITERS, ran, #double_sends, #alt_dropped, #mutable_leaks, #dead_channels))
print("double_send     = the same UNCHANGED stable context re-emitted across a re-entry (bug)")
print("alternation_drop = a send_context call that produced no matching context frame on the wire")
print("mutable_leak    = retained SDK context whose bytes follow the live run (lifetime bug)")
print("dead_channel    = the retained channel produced nothing at all (silently stopped speaking)\n")

if #dead_channels > 0 then
  banner("DEAD CHANNEL (retained context stopped being produced)")
  local d = dead_channels[1]
  print(string.format("  first at seed=%d iter=%d state=%s frames=%d bytes=%d booked=%s (+%d total)",
    SEED, d.it, d.state, d.frames, d.bytes, tostring(d.booked), #dead_channels - 1))
end

if #alt_dropped > 0 then
  banner("ALTERNATION DROP (send_context call without its own context frame)")
  local a = alt_dropped[1]
  print(string.format("  first at iter %d: %d call(s) -> %d frame(s), first mismatch at %s (%s) (+%d total)",
    a.it, a.sent, a.framed, tostring(a.at or "count"), tostring(a.got or "-"), #alt_dropped - 1))
end

if #double_sends > 0 then
  banner("DOUBLE-SEND (stable context re-emitted unchanged)")
  local d = double_sends[1]
  print(string.format("  seed=%d iter=%d state=%s re-emitted %d/%d re-entries", SEED, d.it, d.state, d.resent, d.rounds))
  print("  offending stable content (first 300 chars):")
  print("  " .. tostring(d.sample):sub(1, 300))
  print(string.format("  ...and %d more double-send iteration(s)", #double_sends - 1))
end
if #mutable_leaks > 0 then
  banner("MUTABLE LEAK (run-state change reached retained context)")
  local m = mutable_leaks[1]
  print(string.format("  first at seed=%d iter=%d state=%s: %s (+%d total)",
    SEED, m.it, m.state, tostring(m.why), #mutable_leaks - 1))
  if m.sample then print("  " .. tostring(m.sample):gsub("%s+", " ")) end
end

print()
print(string.format("==== emit-scan: %d double-send(s), %d alternation-drop(s), %d mutable-leak(s), %d dead-channel(s) over %d sequences ====",
  #double_sends, #alt_dropped, #mutable_leaks, #dead_channels, ran))
if (#double_sends > 0 or #alt_dropped > 0 or #mutable_leaks > 0 or #dead_channels > 0)
    and os.getenv("FAIL_ON_FINDINGS") == "1" then os.exit(1) end
