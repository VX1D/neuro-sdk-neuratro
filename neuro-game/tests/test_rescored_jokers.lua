require("tests.stubs").setup({ love = "lazy", G = "board" })

local H = require("tests.helpers")
local check, done = H.harness("rescored jokers")

local DUMP_DIR = os.getenv("BALATRO_DUMP")
local function read_lines(name) return require("tests.helpers").read_lines(DUMP_DIR, name) end
local card_lua, game_lua = read_lines("card.lua"), read_lines("game.lua")
if #card_lua == 0 or #game_lua == 0 then
  require("tests.skip_ledger").bail("rescored jokers", 9, "game dump not found; set BALATRO_DUMP to run")
end

local KEY_BY_NAME = {}
for _, l in ipairs(game_lua) do
  local key = l:match("^%s*(j_[%w_]+)%s*=%s*{")
  local name = l:match("name%s*=%s*'([^']+)'") or l:match('name%s*=%s*"([^"]+)"')
  if key and name then KEY_BY_NAME[name] = key end
end
local function region(from, to)
  local lo, hi
  for i, l in ipairs(card_lua) do
    if not lo and l:find(from, 1, true) then lo = i
    elseif lo and not hi and l:find(to, 1, true) then hi = i end
  end
  return lo, hi
end
local engine = {}
for _, r in ipairs({
  { "if context.before then", "elseif context.after then" },
  { "elseif context.individual then", "if context.cardarea == G.hand then" },
  { "elseif context.playing_card_added", "elseif context.first_hand_drawn" },
  { "elseif context.discard then", "elseif context.end_of_round then" },
}) do
  local lo, hi = region(r[1], r[2])
  check("engine region found: " .. r[1], lo and hi, tostring(lo) .. ".." .. tostring(hi))
  local name
  for i = lo or 1, (hi or 0) - 1 do
    local l = card_lua[i]
    name = l:match("self%.ability%.name%s*==%s*'([^']+)'") or name
    if name and (l:find("SMODS.scale_card(self", 1, true) or l:find("SMODS.reset_card(self", 1, true)) then
      engine[KEY_BY_NAME[name] or name] = true
    end
  end
end

local DJ = require("facts.dynamic_jokers")
local missing, extra = {}, {}
for key in pairs(engine) do if not DJ.RESCORE[key] then missing[#missing + 1] = key end end
for key in pairs(DJ.RESCORE) do if not engine[key] then extra[#extra + 1] = key end end
table.sort(missing); table.sort(extra)
check("every self-rewriting joker in the engine is classified as rescored", #missing == 0,
  table.concat(missing, ", "))
check("nothing is classified as rescored that the engine does not rewrite", #extra == 0,
  table.concat(extra, ", "))

local A = require("core.actions")
local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")
local CR = require("context.context_readable")

local function joker(key, name, ability)
  ability.name, ability.set = name, "Joker"
  return { sort_id = math.random(1e6), cost = 6, sell_cost = 3, facing = "front", ability = ability,
    config = { center = { key = key, name = name, set = "Joker", rarity = 1, config = {}, blueprint_compat = true } } }
end

TD.apply_mock(TD.SCENARIOS[1].mock())
H.in_engine_state("SELECTING_HAND")
G.NEURO.persona = "neuro"
G.jokers.cards = {
  joker("j_ride_the_bus", "Ride the Bus", { mult = 5, extra = 1, x_mult = 1 }),
  joker("j_obelisk", "Obelisk", { mult = 0, extra = 0.2, x_mult = 1.8 }),
  joker("j_green_joker", "Green Joker", { mult = 3, x_mult = 1, extra = { hand_add = 1, discard_sub = 1 } }),
}
for _, c in ipairs(G.jokers.cards) do c.area = G.jokers end
local s = CR.build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"))

check("no rescored joker is summed as always on", s:find("always on", 1, true) == nil, s)
check("Ride the Bus is a ceiling that names its reset",
  s:find("a further at most x2 Mult and at most +6 Mult more", 1, true) ~= nil
    and s:find("Ride the Bus +6 Mult -- before it pays, it resets to 0 if a face card scores,"
    .. " otherwise it gains +1 Mult", 1, true) ~= nil, s)
check("Obelisk is a ceiling that names its reset",
  s:find("Obelisk x2 Mult -- before it pays, it resets to x1 Mult if this hand type has now been played"
    .. " more times than every other hand type (a tie keeps it growing), otherwise it gains x0.2 Mult",
    1, true) ~= nil, s)
check("Green Joker names the value it pays, one step above its current +3",
  s:find("Green Joker +4 Mult -- it gains +1 Mult before every hand pays", 1, true) ~= nil, s)
check("Green Joker is listed as paid on the next hand, outside the gated ceiling",
  s:find("also paid on the next hand you play, whatever it is: Green Joker +4 Mult", 1, true) ~= nil, s)

local Scoring = require("util.scoring")
local playing = require("tests.engine_cards").playing
local function card(value, suit)
  local c = playing(value, suit)
  c.area = G.hand
  return c
end
local kh, kd = card("King", "Hearts"), card("King", "Diamonds")
local th, td = card("10", "Hearts"), card("10", "Diamonds")
G.GAME.hands = { Pair = { played = 3, visible = true }, ["High Card"] = { played = 5, visible = true } }
G.FUNCS.get_poker_hand_info = function(sel)
  return "Pair", "Pair", { Pair = { sel }, ["Two Pair"] = {}, Straight = {}, ["Full House"] = {} }, sel
end
local function mult_for(sel)
  local js = Scoring.joker_summary(sel)
  local led = js and js.ledger
  if not led then return "<none>" end
  local q = led.gated.mult
  local n = q.n
  for _, m in ipairs(led.met) do if m.kind == "mult" then n = n + m.total.n end end
  return q.k .. " " .. tostring(n)
end
check("a scoring face card resets Ride the Bus: only Green Joker's +4 is left",
  mult_for({ kh, kd }) == "known 4", mult_for({ kh, kd }))
check("no scoring face card: Ride the Bus pays +6 on top of Green Joker's +4",
  mult_for({ th, td }) == "known 10", mult_for({ th, td }))

do
  local function held(value, suit, facing) return playing(value, suit, { facing = facing }) end
  local function render(jokers, hand)
    TD.apply_mock(TD.SCENARIOS[1].mock())
    H.in_engine_state("SELECTING_HAND")
    G.NEURO.persona = "neuro"
    G.GAME.current_round.hands_played = 0
    G.jokers.cards = jokers
    for _, c in ipairs(jokers) do c.area = G.jokers end
    if hand then
      G.hand.cards = hand
      for _, c in ipairs(hand) do c.area = G.hand end
    end
    return CR.build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"))
  end
  local function hologram() return joker("j_hologram", "Hologram", { x_mult = 1.5, extra = 0.25 }) end
  local function down(key, name)
    local j = joker(key, name, { extra = {} })
    j.facing = "back"
    return j
  end

  check("a visible DNA names its copy for Hologram",
    render({ hologram(), joker("j_dna", "DNA", { extra = {} }) }):find("DNA copies", 1, true) ~= nil)
  local dna = render({ hologram(), down("j_dna", "DNA") })
  local plain = render({ hologram(), down("j_joker", "Joker") })
  check("a face-down DNA is not named by Hologram's text", dna:find("DNA", 1, true) == nil, dna)
  check("Hologram's text is the same whichever joker is face down", dna == plain)

  local function vampire() return joker("j_vampire", "Vampire", { x_mult = 1.5, extra = 0.1 }) end
  check("Vampire's text is the same whether the face-down joker is Midas Mask or not",
    render({ vampire(), down("j_midas_mask", "Midas Mask") }) == render({ vampire(), down("j_joker", "Joker") }))

  local function fist(rank)
    return render({ joker("j_raised_fist", "Raised Fist", { extra = {} }) },
      { held("King", "Hearts", "front"), held("Queen", "Hearts", "front"), held(rank, "Clubs", "back") })
  end
  local low, high = fist("2"), fist("9")
  check("Raised Fist gives no value read from a face-down held card",
    low:find("+4 Mult", 1, true) == nil and high:find("+18 Mult", 1, true) == nil, high)
  check("Raised Fist's text is the same whichever card is face down", low == high)
  check("it says why it has no number",
    high:find("no number for Raised Fist -- it depends on the lowest-ranked card still in your hand", 1, true) ~= nil, high)
end

done()
