_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("reask-parity")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local Once = require("util.once")
local real_once_until = Once.once_until
local gate_opens = {}
Once.once_until = function(key, epoch)
  local ok = real_once_until(key, epoch)
  if ok then gate_opens[#gate_opens + 1] = tostring(key) end
  return ok
end

local function opens_naming(tag)
  local n = 0
  for _, key in ipairs(gate_opens) do if key:find(tag, 1, true) then n = n + 1 end end
  return n
end

local function rules_segment(query)
  local i = query:find("Rules: 1)", 1, true)
  if not i then return nil end
  local j = query:find("Hand card indices:", i, true)
  return query:sub(i, (j or (#query + 1)) - 1)
end

local function boss_floor()
  local bl = G.GAME and G.GAME.blind
  local d = bl and not bl.disabled and bl.debuff
  return (type(d) == "table" and tonumber(d.h_size_ge)) or nil
end

local function chips_owed()
  local tgt = tonumber(G.GAME and G.GAME.blind and G.GAME.blind.chips) or 0
  return math.max(0, tgt - (tonumber(G.GAME.chips) or 0))
end

local function load_bearing()
  local want = {}
  local floor = boss_floor()
  if floor then want[#want + 1] = { "the boss legality floor", "at least " .. floor .. " cards" } end
  want[#want + 1] = { "the chips still owed", string.format("%.0f", chips_owed()) }
  want[#want + 1] = { "the hand indices", "1-" .. tostring(#G.hand.cards) }
  return want
end

local forces, missing, blind_leak = {}, {}, {}

local function force(label)
  local payload = FP.build("SELECTING_HAND")
  if not payload then
    missing[#missing + 1] = label .. ": no force at all"
    return nil
  end
  local rec = { label = label, round = G.GAME.round, query = payload.query,
    message = payload.message, seg = rules_segment(payload.query),
    actions = payload.actions }
  if not rec.seg then missing[#missing + 1] = label .. ": no numbered rules list" end
  for _, want in ipairs(load_bearing()) do
    if not payload.message:find(want[2], 1, true) then
      missing[#missing + 1] = string.format("%s: %s (%q) is absent", label, want[1], want[2])
    end
  end
  for _, name in ipairs(rec.actions) do
    if not payload.query:find(name, 1, true) then
      missing[#missing + 1] = label .. ": offers " .. name .. " without naming it in the query"
    end
  end
  forces[#forces + 1] = rec
  return rec
end

local BOSS = { name = "The Psychic", key = "bl_psychic", boss = true, in_blind = true,
  disabled = false, chips = 1200, mult = 2, debuff = { h_size_ge = 5 }, hands = {} }

local function set_blind(floor, chips)
  local b = {}
  for k, v in pairs(BOSS) do b[k] = v end
  b.debuff = { h_size_ge = floor }
  b.chips = chips
  G.GAME.blind = b
end

LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
G.GAME.round = 7
set_blind(5, 1200)
local sold_name = G.jokers.cards[1].ability.name

force("r7 first offer")
force("r7 re-ask, nothing spent")
G.GAME.current_round.hands_left = 3
G.GAME.chips = 260
force("r7 after one hand")
table.remove(G.jokers.cards, 1)
G.NEURO.jokers_sold_run = 1
force("r7 after selling a joker")
G.GAME.current_round.discards_left = 2
force("r7 after one discard")
G.GAME.current_round.hands_left = 2
G.GAME.chips = 520
force("r7 after two hands")
G.GAME.current_round.hands_left = 1
G.GAME.chips = 900
force("r7 on the last hand")

local r7 = {}
for _, f in ipairs(forces) do if f.round == 7 then r7[#r7 + 1] = f end end

check("the round was actually played out across many forces",
  #r7 >= 7, "forces in round 7: " .. #r7)
check("every force of the round carries the facts a move cannot be chosen without",
  #missing == 0, table.concat(missing, " | "))

do
  local longest, count = 0, 0
  for _, f in ipairs(r7) do if f.seg and #f.seg > longest then longest = #f.seg end end
  local shortest = math.huge
  for _, f in ipairs(r7) do if f.seg and #f.seg < shortest then shortest = #f.seg end end
  local at_max = {}
  for _, f in ipairs(r7) do
    if f.seg and #f.seg == longest then count = count + 1; at_max[#at_max + 1] = f.label end
  end
  check("the long form of the rules is stated exactly once in the round, however many hands are spent",
    count == 1, string.format("%d forces carry the longest rules block (%d chars): %s",
      count, longest, table.concat(at_max, ", ")))
  check("P3a and the short form really is a different, shorter block",
    shortest < longest * 0.9, string.format("longest=%d shortest=%d", longest, shortest))
  check("P3b the round-cadence gate opened exactly once for the whole round",
    opens_naming("sh_rules_core") == 1, "openings: " .. opens_naming("sh_rules_core"))
end

do
  local restated = {}
  for i = 2, #r7 do
    if r7[i].message:find(sold_name, 1, true) and i >= 4 then
      restated[#restated + 1] = r7[i].label
    end
  end
  check("a joker sold mid-round is gone from every later force of that round",
    #restated == 0, table.concat(restated, ", "))
end

G.GAME.round = 8
G.GAME.current_round.hands_left = 4
G.GAME.current_round.discards_left = 3
G.GAME.chips = 0
set_blind(4, 1800)
force("r8 first offer")
force("r8 re-ask")
G.GAME.current_round.hands_left = 3
G.GAME.chips = 400
force("r8 after one hand")

local r8 = {}
for _, f in ipairs(forces) do if f.round == 8 then r8[#r8 + 1] = f end end
check("the next round states the long form again",
  #r8 >= 3, "forces in round 8: " .. #r8)
do
  local longest, count = 0, 0
  for _, f in ipairs(r8) do if f.seg and #f.seg > longest then longest = #f.seg end end
  for _, f in ipairs(r8) do if f.seg and #f.seg == longest then count = count + 1 end end
  check("P5a exactly once, in the new round too", count == 1,
    string.format("%d of %d forces carry the longest block", count, #r8))
  check("P5b and the round gate opened a second time, once",
    opens_naming("sh_rules_core") == 2, "openings: " .. opens_naming("sh_rules_core"))
end
for _, f in ipairs(r8) do
  if f.query:find("at least 5 cards", 1, true) then
    blind_leak[#blind_leak + 1] = f.label
  end
end
check("the previous blind's legality floor does not survive into the new round",
  #blind_leak == 0, table.concat(blind_leak, ", "))
check("every force in the run carried the load-bearing facts",
  #missing == 0, table.concat(missing, " | "))

check("every force in the round was taken off G.NEURO.force_actions",
  FP.captures() >= #forces, "payloads captured: " .. FP.captures() .. ", forces: " .. #forces)

Once.once_until = real_once_until
done()
