require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("reask-parity")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

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

local function board_text(s) return (tostring(s or ""):gsub("Since your last decision:[^\n]*", "")) end

local forces, missing, blind_leak = {}, {}, {}

local function force(label)
  local payload = FP.build("SELECTING_HAND")
  if not payload then
    missing[#missing + 1] = label .. ": no force at all"
    return nil
  end
  local rec = { label = label, round = G.GAME.round, query = payload.query,
    message = payload.message, actions = payload.actions }
  for _, want in ipairs(load_bearing()) do
    if not payload.message:find(want[2], 1, true) then
      missing[#missing + 1] = string.format("%s: %s (%q) is absent", label, want[1], want[2])
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

do
  local restated = {}
  for i = 2, #r7 do
    if board_text(r7[i].message):find(sold_name, 1, true) and i >= 4 then
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
for _, f in ipairs(r8) do
  if f.query:find("at least 5 cards", 1, true) then
    blind_leak[#blind_leak + 1] = f.label
  end
end
check("the previous blind's legality floor does not survive into the new round",
  #blind_leak == 0, table.concat(blind_leak, ", "))
check("every force in the run carried the load-bearing facts",
  #missing == 0, table.concat(missing, " | "))

done()
