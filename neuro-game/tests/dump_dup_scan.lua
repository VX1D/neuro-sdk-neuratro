
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Config = require("core.config")
local ContextReadable = require("context.context_readable")
local ContextCompact = require("context.context_compact")
local StateKinds = require("core.state_kinds")
G.NEURO.dispatcher = D
G.NEURO.actions = A

local TD = require("tests.test_deadlock")

local SEED  = tonumber(arg and arg[1]) or 20260722
local ITERS = tonumber(arg and arg[2]) or 6000
math.randomseed(SEED)
local function ri(a, b) return math.random(a, b) end
local function pick(t) return t[ri(1, #t)] end
local function chance(p) return math.random() < p end

local SUITS = { "Hearts", "Clubs", "Diamonds", "Spades" }
local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }
local NOMINAL = { ["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,["9"]=9,["10"]=10,
  Jack=10, Queen=10, King=10, Ace=11 }

local JOKER_POOL = {
  { key="j_joker",  name="Joker",         ab={ mult=4 },                       desc="+4 Mult" },
  { key="j_crazy",  name="Crazy Joker",   ab={ mult=12, type="Straight" },     desc="+12 Mult if played hand contains a Straight" },
  { key="j_bull",   name="Bull",          ab={ chips=0 },                      desc="+2 Chips for each dollar you have" },
  { key="j_loyalty_card", name="Loyalty Card", ab={ extra={ Xmult=4 } },       desc="X4 Mult every 6 hands played (this is a countdown, not a hand condition)" },
  { key="j_trading_card", name="Trading Card", ab={},                          desc="If your first discard of the round is a single card, destroy it and earn $3" },
  { key="j_walkie_talkie", name="Walkie Talkie", ab={ chips=10, mult=4 },      desc="Each played 10 or 4 gives +10 Chips and +4 Mult" },
  { key="j_banner", name="Banner",        ab={ chips=0 },                      desc="+30 Chips for each remaining discard" },
  { key="j_baron",  name="Baron",         ab={ extra={ Xmult=1.5 } },          desc="Each King held in hand gives X1.5 Mult" },
  { key="j_greedy_joker", name="Greedy Joker", ab={ mult=3, type="Diamonds" }, desc="Played cards with Diamond suit give +3 Mult when scored" },
  { key="j_even_steven", name="Even Steven", ab={ mult=4 },                    desc="Played cards with an even rank give +4 Mult when scored" },
  { key="j_blueprint", name="Blueprint",  ab={},                               desc="Copies the ability of the joker to its right" },
  { key="j_brainstorm", name="Brainstorm",ab={},                               desc="Copies the ability of the leftmost joker" },
  { key="j_hack",   name="Hack",          ab={},                               desc="Retrigger each played 2, 3, 4 or 5" },
  { key="j_dusk",   name="Dusk",          ab={},                               desc="Retrigger all played cards in the final hand of the round" },
  { key="j_ride_the_bus", name="Ride the Bus", ab={ mult=0 },                  desc="+1 Mult per consecutive hand played without a face card (resets if a face is scored)" },
  { key="j_business", name="Business Card", ab={},                             desc="Each played face card has a 1 in 2 chance to give $2" },
  { key="j_mime",   name="Mime",          ab={},                               desc="Retrigger all held-in-hand card abilities" },
  { key="j_cavendish", name="Cavendish",  ab={ extra={ Xmult=3 } },            desc="X3 Mult; 1 in 1000 chance this joker is destroyed at end of round" },
}

local EDITIONS = { false, false, false, false, { foil = true }, { holo = true }, { polychrome = true }, { negative = true } }

local BOSSES = {
  false, false, false,
  { key="bl_club",   name="The Club",   debuff = { suit = "Clubs" } },
  { key="bl_head",   name="The Head",   debuff = { suit = "Hearts" } },
  { key="bl_goad",   name="The Goad",   debuff = { suit = "Spades" } },
  { key="bl_window", name="The Window", debuff = { suit = "Diamonds" } },
  { key="bl_plant",  name="The Plant",  debuff = { is_face = "face" } },
  { key="bl_psychic",name="The Psychic",debuff = { h_size_ge = 5 } },
  { key="bl_eye",    name="The Eye",    debuff = { single_hand_type = true }, hands = {} },
  { key="bl_mouth",  name="The Mouth",  debuff = { hand = true } },
  { key="bl_needle", name="The Needle", debuff = { hand = true } },
  { key="bl_pillar", name="The Pillar", debuff = { } },
  { key="bl_flint",  name="The Flint",  debuff = { } },
  { key="bl_mark",   name="The Mark",   debuff = { } },
}

local ENHANCEMENTS = { false, false, false, "m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_gold", "m_stone", "m_lucky" }
local SEALS = { false, false, false, false, "Gold", "Red", "Blue", "Purple" }

local CONSUMABLES = {
  { key="c_fool",  name="The Fool",   set="Tarot",  desc="Creates the last Tarot or Planet card used this run (The Fool excluded)" },
  { key="c_magician", name="The Magician", set="Tarot", desc="Enhances up to 2 selected cards to Lucky cards" },
  { key="c_pluto", name="Pluto",      set="Planet", desc="Levels up High Card (+1 Mult, +10 Chips)" },
  { key="c_mercury", name="Mercury",  set="Planet", desc="Levels up Pair (+1 Mult, +15 Chips)" },
  { key="c_familiar", name="Familiar",set="Spectral", desc="Destroy 1 random card in hand, add 3 random Enhanced face cards" },
  { key="c_hex",   name="Hex",        set="Spectral", desc="Add Polychrome to a random joker, destroy the rest" },
}

local function make_joker(def, ed)
  local ab = {}; for k, v in pairs(def.ab) do ab[k] = v end
  ab.name, ab.set = def.name, "Joker"
  return { cost = ri(3, 8), sell_cost = ri(1, 4), ability = ab, edition = ed or nil, debuff = false,
    highlighted = false,
    config = { center = { key = def.key, name = def.name, set = "Joker", loc_txt = { name = def.name, description = def.desc } } } }
end

local function make_consumable(def)
  return { cost = ri(3, 6), sell_cost = ri(1, 3), ability = { name = def.name, set = def.set },
    config = { center = { key = def.key, name = def.name, set = def.set, loc_txt = { name = def.name, description = def.desc } } } }
end

local function rand_jokers(nmax)
  local n = ri(0, nmax or 5)
  local t = {}
  for i = 1, n do t[i] = make_joker(pick(JOKER_POOL), pick(EDITIONS) or nil) end
  return t
end

local function enrich_card(c)
  if type(c) ~= "table" then return end
  if not c.base then c.base = { value = pick(RANKS), suit = pick(SUITS) } end
  c.base.nominal = NOMINAL[c.base.value] or 10
  local enh = pick(ENHANCEMENTS)
  if enh then
    c.ability = c.ability or {}
    c.config = c.config or { center = {} }
    c.config.center = c.config.center or {}
    c.config.center.key = enh
    c.ability.set = "Enhanced"
  end
  local seal = pick(SEALS); if seal then c.seal = seal end
  local ed = pick(EDITIONS); if ed then c.edition = ed end
end

local function mutate(state)
  local boss = nil
  if G.GAME and G.GAME.blind and (state == "SELECTING_HAND" or state == "SHOP" or state == "ROUND_EVAL") then
    local b = pick(BOSSES)
    if b then
      boss = b.name
      G.GAME.blind.debuff = b.debuff
      G.GAME.blind.name = b.name
      G.GAME.blind.disabled = false
      if b.hands then G.GAME.blind.hands = b.hands end
    end
  end
  if G.jokers and chance(0.85) then
    G.jokers.cards = rand_jokers(5)
    G.jokers.config = G.jokers.config or { card_limit = 5 }
  end
  if G.hand and G.hand.cards then
    local dsuit = G.GAME and G.GAME.blind and G.GAME.blind.debuff and G.GAME.blind.debuff.suit
    for _, c in ipairs(G.hand.cards) do
      if chance(0.5) then enrich_card(c) end
      if dsuit and c.base and chance(0.4) then c.base.suit = dsuit; if chance(0.7) then c.debuff = true end end
    end
  end
  if G.consumeables and chance(0.5) then
    local t = {}; for i = 1, ri(0, 2) do t[i] = make_consumable(pick(CONSUMABLES)) end
    G.consumeables.cards = t
    G.consumeables.config = G.consumeables.config or { card_limit = 2 }
  end
  if state == "SHOP" then
    if G.shop_jokers then
      local t = {}; for i = 1, ri(1, 2) do t[i] = make_joker(pick(JOKER_POOL), pick(EDITIONS) or nil) end
      G.shop_jokers.cards = t
    end
    if G.shop_booster and chance(0.5) then
      G.shop_booster.cards = { { cost = ri(3, 6), ability = { set = "Booster", name = pick({ "Arcana Pack", "Celestial Pack", "Buffoon Pack", "Standard Pack" }) }, config = { center = {} } } }
    end
  end
  if StateKinds.is_pack_state(state) and G.pack_cards then
    local t = {}
    for i = 1, ri(2, 4) do
      if state == "BUFFOON_PACK" then t[i] = make_joker(pick(JOKER_POOL), pick(EDITIONS) or nil)
      elseif state == "STANDARD_PACK" then local c = { base = { value = pick(RANKS), suit = pick(SUITS) }, ability = {}, config = { center = {} } }; enrich_card(c); t[i] = c
      else t[i] = make_consumable(pick(CONSUMABLES)) end
    end
    G.pack_cards.cards = t
  end
  if chance(0.5) then
    local jn = (G.jokers and G.jokers.cards[1] and G.jokers.cards[1].config.center.name) or "the board"
    G.NEURO.plan = {
      hand = "Aim the strongest line and clear the blind",
      hand_scope = "ante" .. tostring((G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1) .. "|Boss|bl_boss",
      build = chance(0.5) and (jn .. " is the scaling piece") or "Need an xMult joker next",
      build_scope = "sig", money = "Hold cash for interest", money_scope = "e",
      ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1,
    }
  end
  return boss
end

local WIPE = {
  "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "shop",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU",
}
local function fresh_g()
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0, shop_reroll_count = 0,
  state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 7 }
  ContextCompact.invalidate_cache()
end

local STOP = {}
for _, w in ipairs({ "the","a","an","to","of","and","or","in","on","is","it","you","your","for",
  "with","that","this","are","be","if","as","at","by","not","no","its","has","have","can",
  "when","each","them","they","their","so","do","up","1","2","3","4","5","6","7","8" }) do STOP[w] = true end

local STRIPS = {
  { "\n%s*%d+%.[^\n]*", "\n", 1550 },
  { "Your hand:[^\n]*", " ", 1150 },
  { "One card away:.-%.%s", " ", 650 },
  { "Joker copy order:[^\n]*", " ", 880 },
  { "[^\n]*needs[^\n]-chips[^\n]-reward[^\n]*", " ", 470 },
  { "Shop items:[^\n]*", " ", 40 },
  { "shop %w+ slot %d+:[^\n]*", " ", 840 },
  { "Your move:.*$", " ", 1300 },
}

local STRIP_HITS, STRIP_WORST = {}, {}

local function strip_lists(msg)
  local s = "\n" .. msg .. "\n"
  for i, rule in ipairs(STRIPS) do
    local before = #s
    local out, n = s:gsub(rule[1], rule[2])
    STRIP_HITS[i] = (STRIP_HITS[i] or 0) + n
    local removed = before - #out
    if removed > (STRIP_WORST[i] or 0) then STRIP_WORST[i] = removed end
    s = out
  end
  return s
end

local function words_of(s)
  local w = {}
  for tok in tostring(s):gmatch("%S+") do
    local n = tok:lower():gsub("[^%w]", "")
    if n ~= "" then w[#w + 1] = n end
  end
  return w
end

local K = 5
local function repeated_shingles(words)
  local last, total = {}, {}
  for i = 1, #words - K + 1 do
    local content = 0
    for j = i, i + K - 1 do if not STOP[words[j]] then content = content + 1 end end
    if content >= 3 then
      local key = table.concat(words, " ", i, i + K - 1)
      if not last[key] then
        last[key], total[key] = i, 1
      elseif i >= last[key] + K then
        last[key], total[key] = i, total[key] + 1
      end
    end
  end
  local out = {}
  for key, c in pairs(total) do if c >= 2 then out[#out + 1] = { phrase = key, count = c } end end
  table.sort(out, function(x, y) return x.count > y.count end)
  return out
end

local function is_benign(key)
  if key:find("hands? and # discards?") or key:find("# hand.? and # discard") then return true end
  if key:find("you still need # chips") then return true end
  if key:find("if the hand contains") or key:find("hand contains a") then return true end
  return false
end

local crashes = {}
local SAMPLES, SAMPLE_STATES = {}, {}
local rendered = 0
local patterns = {} -- norm_phrase -> aggregate across all messages
local function norm(p) return (p:gsub("%d+", "#")) end
local TARGET = os.getenv("TARGET_PHRASE")

for it = 1, ITERS do
  fresh_g()
  local sc = pick(TD.SCENARIOS)
  local state = sc.state
  local built, boss = pcall(function()
    TD.apply_mock(sc.mock())
    if G.NEURO.persona == nil then G.NEURO.persona = "neuro" end

    return mutate(state)
  end)
  if not built then
    crashes[#crashes + 1] = { it = it, state = state, phase = "build", err = tostring(boss) }
  else
    local ok, msg = pcall(function()
      local acts = A.get_valid_actions_for_state(state)
      local board = ContextReadable.build(state, acts) or ""
      local force = D.get_force_for_state(state)
      local q = (type(force) == "table" and force.query) or ""
      return board .. "\n" .. q
    end)
    if not ok then
      crashes[#crashes + 1] = { it = it, state = state, phase = "render", err = tostring(msg) }
    else
      rendered = rendered + 1
      if not SAMPLES[state] then SAMPLES[state] = msg; SAMPLE_STATES[#SAMPLE_STATES + 1] = state end
      if TARGET then
        local stripped = strip_lists(msg)
        local n = 0; for _ in stripped:lower():gmatch(TARGET:lower():gsub("(%W)", "%%%1")) do n = n + 1 end
        if n >= 2 then
          print("=== STATE " .. state .. " iter " .. it .. " -- '" .. TARGET .. "' x" .. n .. " in stripped ===")
          print(stripped); os.exit(0)
        end
      end
      for _, e in ipairs(repeated_shingles(words_of(strip_lists(msg)))) do
        local key = norm(e.phrase)
        local rec = patterns[key]
        if not rec then rec = { key = key, msgs = 0, max = 0 }; patterns[key] = rec end
        rec.msgs = rec.msgs + 1
        if e.count > rec.max then
          rec.max, rec.phrase, rec.it, rec.msg = e.count, e.phrase, it, msg
          rec.boss, rec.state = boss, state
        end
      end
    end
  end
end

local function banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end
local ranked, gated = {}, 0
for _, rec in pairs(patterns) do
  ranked[#ranked + 1] = rec
  if not is_benign(rec.key) then gated = gated + 1 end
end
table.sort(ranked, function(a, b) return a.msgs > b.msgs end)

banner(string.format("DUP-SCAN FUZZ  seed=%d iters=%d rendered=%d crashes=%d", SEED, ITERS, rendered, #crashes))
print("Distinct cross-section duplication PATTERNS (same >=5-word prose phrase in >1 section of")
print("one message; per-card/per-hand lists stripped first). # = any number. [benign] = intentional.\n")
print(string.format("  %-6s %-7s  %s", "msgs", "worst", "pattern"))
for _, rec in ipairs(ranked) do
  print(string.format("  %-6d x%-6d %s%s", rec.msgs, rec.max, rec.phrase, is_benign(rec.key) and "   [benign]" or ""))
end

local sample
for _, rec in ipairs(ranked) do if not is_benign(rec.key) then sample = rec; break end end
if sample then
  print()
  banner(string.format("SAMPLE: \"%s\" x%d  [%s / boss=%s / seed=%d iter=%d]",
    sample.phrase, sample.max, sample.state, tostring(sample.boss), SEED, sample.it))
  print(sample.msg)
end

if #crashes > 0 then
  print()
  banner("CRASHES (renderer/build errored on a valid state -- always a hard failure)")
  for i = 1, math.min(#crashes, 15) do
    print(string.format("  seed=%d iter=%d state=%s phase=%s :: %s",
      SEED, crashes[i].it, crashes[i].state, crashes[i].phase, crashes[i].err))
  end
end

local dead = {}
for i, rule in ipairs(STRIPS) do
  if (STRIP_HITS[i] or 0) == 0 then dead[#dead + 1] = rule[1] end
end
if #dead > 0 then
  print()
  banner("DEAD STRIPS (no builder emits these, so they are permanent blind spots)")
  for _, pat in ipairs(dead) do print("  FAIL never matched in " .. rendered .. " messages: " .. pat) end
end

local fat = {}
for i, rule in ipairs(STRIPS) do
  local worst, cap = STRIP_WORST[i] or 0, tonumber(rule[3])
  if not cap then
    fat[#fat + 1] = rule[1] .. " declares no byte ceiling (worst " .. worst .. " in one message)"
  elseif worst > cap then
    fat[#fat + 1] = string.format("%s removed %d bytes from one message, ceiling %d",
      rule[1], worst, cap)
  end
end
if #fat > 0 then
  print()
  banner("OVER-BROAD STRIPS (removed more of one message than declared -- a blanked section)")
  for _, line in ipairs(fat) do print("  FAIL " .. line) end
end

local CONTROL_ANCHORS = {
  { id = "permanent rules preamble", pat = "^At round end each unused hand pays" },
  { id = "state and constraints line", pat = "^State: " },
  { id = "shop legality", pat = "^Legality: " },
  { id = "joker roster header", pat = "^Your jokers %(" },
  { id = "card modifiers", pat = "^Card modifiers" },
  { id = "bank figure", pat = "%$%-?%d+ in t?h?e? ?bank" },
}

local function lines_of(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end
local function phrase_set(text)
  local set = {}
  for _, e in ipairs(repeated_shingles(words_of(strip_lists(text)))) do set[e.phrase] = true end
  return set
end

local blind = {}
for _, anchor in ipairs(CONTROL_ANCHORS) do
  local found_line, found_state, probe
  for _, state in ipairs(SAMPLE_STATES) do
    local msg = SAMPLES[state]
    local ls = lines_of(msg)
    for i, line in ipairs(ls) do
      if line:find(anchor.pat) then
        local injectable = (line:gsub("%s*Your move:.*$", ""))
        if #words_of(injectable) >= 8 then
          local copy = { injectable }
          for j = 1, #ls do copy[#copy + 1] = ls[j] end
          found_line, found_state, probe = injectable, state, table.concat(copy, "\n")
          break
        end
      end
    end
    if probe then break end
  end
  if not probe then
    blind[#blind + 1] = anchor.id .. ": no rendered message carries this line at all"
  else
    local base, after = phrase_set(SAMPLES[found_state]), phrase_set(probe)
    local joined = table.concat(words_of(found_line), " ")
    local seen = false
    for phrase in pairs(after) do
      if not base[phrase] and joined:find(phrase, 1, true) then seen = true break end
    end
    if not seen then
      blind[#blind + 1] = string.format("%s (%s): a duplication of this line is invisible to the scan",
        anchor.id, found_state)
      if os.getenv("DUP_DEBUG") == "1" then
        local pre, joined_dbg = {}, table.concat(words_of(found_line), " ")
        for phrase in pairs(base) do
          if joined_dbg:find(phrase, 1, true) then pre[#pre + 1] = phrase end
        end
        print(string.format("DUP_DEBUG %s (%s): base_already_matching=%d line=%q",
          anchor.id, tostring(found_state), #pre, found_line))
        for _, p in ipairs(pre) do print("  base-has: " .. p) end
      end
    end
  end
end
if #blind > 0 then
  print()
  banner("BLIND SECTIONS (an injected duplication here was NOT reported -- a strip is eating it)")
  for _, line in ipairs(blind) do print("  FAIL " .. line) end
end

print()
print(string.format("==== dup-scan: %d distinct dup pattern(s) (%d gated, %d benign), %d crash(es), %d dead strip(s), %d over-broad strip(s), %d blind section(s), %d states ====",
  #ranked, gated, #ranked - gated, #crashes, #dead, #fat, #blind, rendered))
if #crashes > 0 then os.exit(1) end
if (gated > 0 or #dead > 0 or #fat > 0 or #blind > 0) and os.getenv("FAIL_ON_FINDINGS") == "1" then
  os.exit(1)
end
