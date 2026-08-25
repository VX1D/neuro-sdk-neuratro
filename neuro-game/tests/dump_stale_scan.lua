
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Config = require("core.config")
local CardUtil = require("facts.card_util")
local StateKinds = require("core.state_kinds")

local TD = require("tests.test_deadlock")

local SEED  = tonumber(arg and arg[1]) or 20260722
local ITERS = tonumber(arg and arg[2]) or 4000
math.randomseed(SEED)
local function ri(a, b) return math.random(a, b) end
local function pick(t) return t[ri(1, #t)] end
local function chance(p) return math.random() < p end

local function targeted_consumable()   -- needs a live hand to use
  return { cost = ri(3, 6), sell_cost = ri(1, 3),
    ability = { name = "The Chariot", set = "Tarot", consumeable = { max_highlighted = ri(1, 2) } },
    config = { center = { key = "c_chariot", name = "The Chariot", set = "Tarot",
      loc_txt = { name = "The Chariot", description = "Enhances up to 2 selected cards to Steel" } } } }
end
local function plain_consumable()       -- usable without a hand (planet / space-only)
  return { cost = ri(3, 6), sell_cost = ri(1, 3),
    ability = { name = "Pluto", set = "Planet" },
    config = { center = { key = "c_pluto", name = "Pluto", set = "Planet",
      loc_txt = { name = "Pluto", description = "Levels up High Card" } } } }
end
local function shop_joker()
  return { cost = ri(2, 9), sell_cost = ri(1, 4), ability = { name = "Joker", set = "Joker", mult = 4 },
    config = { center = { key = "j_joker", name = "Joker", set = "Joker", loc_txt = { name = "Joker", description = "+4 Mult" } } } }
end

local WIPE = { "hand","jokers","consumeables","shop_jokers","shop_vouchers","shop_booster","shop","pack_cards","booster_pack","blind_select_opts","blind_select","OVERLAY_MENU" }
local function fresh_g()
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0, _reservation_epoch = 0, shop_reroll_count = 0,
  state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 5 }
end

local function mutate(state)
  if G.consumeables then
    local t = {}
    for i = 1, ri(0, 2) do t[i] = chance(0.6) and targeted_consumable() or plain_consumable() end
    G.consumeables.cards = t
    G.consumeables.config = G.consumeables.config or { card_limit = 2 }
  end
  if G.hand and chance(0.4) then G.hand.cards = {} end
  if state == "SHOP" and G.shop_jokers then
    local t = {}; for i = 1, ri(0, 3) do t[i] = shop_joker() end
    G.shop_jokers.cards = t
  end
  if G.GAME and chance(0.4) then G.GAME.dollars = ri(0, 3) end
end

local function preflight_ok(name, payload)
  local save = G.NEURO.reserved_dollars
  local ok, exec = pcall(D.preflight, name, payload)
  G.NEURO.reserved_dollars = save
  return ok and exec ~= nil and type(exec) ~= "string"
end

local function use_card_payload(card, i, area)
  local p = { area = area or "consumeables", index = i }
  local c = card.ability and card.ability.consumeable
  local m = (type(c) == "table") and tonumber(c.max_highlighted) or nil
  if m and m > 0 then
    local hi = {}
    local n = (G.hand and G.hand.cards) and #G.hand.cards or 0
    for k = 1, math.min(m, n) do hi[k] = k end
    p.hand_indices = hi
  end
  return p
end
local function has(v) for _, x in ipairs(v or {}) do if x == true then return true end end return false end

local phantom, parity, crashes = {}, {}, {}
local ran = 0

local function run_iteration(it)
  fresh_g()
  local sc = pick(TD.SCENARIOS)
  local state = sc.state
  local built = pcall(function()
    TD.apply_mock(sc.mock())
    if G.NEURO.persona == nil then G.NEURO.persona = "neuro" end
    mutate(state)
  end)
  if not built then crashes[#crashes + 1] = { it = it, state = state, phase = "build" }; return end

  local okf, force = pcall(D.get_force_for_state, state)
  if not okf then crashes[#crashes + 1] = { it = it, state = state, phase = "force" }; return end
  ran = ran + 1
  local advertised = (type(force) == "table" and force.actions) or {}
  local use_advertised = false
  for _, name in ipairs(advertised) do if name == "use_card" then use_advertised = true break end end

  if use_advertised then
    local usable_flags = {}
    if G.consumeables and G.consumeables.cards then
      for i, card in ipairs(G.consumeables.cards) do
        local rendered = CardUtil.consumable_usable_now(card) and true or false
        local real = preflight_ok("use_card", use_card_payload(card, i, "consumeables"))
        usable_flags[#usable_flags + 1] = real
        if rendered ~= real then
          local rec = { it = it, state = state, index = i, rendered = rendered, preflight = real,
            name = card.ability and card.ability.name, dangerous = (rendered and not real) }
          parity[#parity + 1] = rec
        end
      end
    end
    if G.pack_cards and G.pack_cards.cards then
      for i, card in ipairs(G.pack_cards.cards) do
        usable_flags[#usable_flags + 1] = preflight_ok("use_card", use_card_payload(card, i, "booster_pack"))
      end
    end
    if not has(usable_flags) then
      phantom[#phantom + 1] = { it = it, state = state, action = "use_card",
        targets = (G.consumeables and #G.consumeables.cards or 0) + (G.pack_cards and #G.pack_cards.cards or 0) }
    end
  end
end
for it = 1, ITERS do run_iteration(it) end

local dangerous, safe = 0, nil
for _, p in ipairs(parity) do
  if p.dangerous then dangerous = dangerous + 1 elseif not safe then safe = p end
end
local safe_n = #parity - dangerous

local function banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end
banner(string.format("STALE-SCAN FUZZ  seed=%d iters=%d rendered=%d phantom=%d dangerous=%d safe=%d crashes=%d",
  SEED, ITERS, ran, #phantom, dangerous, safe_n, #crashes))
print("phantom   = use_card advertised but NOTHING it can target passes execution (model chases nothing)")
print("dangerous = shown 'usable now' but execution REJECTS  -- the PRD phantom bug (GATED)")
print("safe      = shown 'not usable' but execution ACCEPTS  -- model may needlessly skip it (reported)\n")

if #phantom > 0 then
  banner("PHANTOM ACTIONS (advertised, unexecutable in the unchanged state) -- GATED")
  local seen = {}
  for _, f in ipairs(phantom) do local k = f.state; seen[k] = (seen[k] or 0) + 1 end
  for k, n in pairs(seen) do print(string.format("  use_card @ %-20s x%d", k, n)) end
end
if dangerous > 0 then
  banner("DANGEROUS PARITY (shown usable, execution rejects -- phantom the model chases) -- GATED")
  for _, p in ipairs(parity) do if p.dangerous then
    print(string.format("  seed=%d iter=%d state=%s consumable[%d]=%s", SEED, p.it, p.state, p.index, tostring(p.name)))
    break
  end end
end
if safe_n > 0 and safe then
  banner("SAFE PARITY (shown not-usable but execution accepts -- lower severity, NOT gated)")
  print(string.format("  e.g. %s @ %s shown not-usable but usable (x%d total). Likely consumable_usable_now",
    tostring(safe.name), safe.state, safe_n))
  print("  using has_consumable_space() for a consumable that is CONSUMED on use (needs no free slot).")
end
if #crashes > 0 then
  banner("CRASHES"); for i = 1, math.min(#crashes, 10) do
    print(string.format("  iter %d state %s phase %s", crashes[i].it, crashes[i].state, crashes[i].phase)) end
end

print()
print(string.format("==== stale-scan: %d phantom, %d DANGEROUS (gated), %d safe (reported), %d crash(es), %d states ====",
  #phantom, dangerous, safe_n, #crashes, ran))
if #crashes > 0 then os.exit(1) end
if (#phantom > 0 or dangerous > 0) and os.getenv("FAIL_ON_FINDINGS") == "1" then os.exit(1) end
