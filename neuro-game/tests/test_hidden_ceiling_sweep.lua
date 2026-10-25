require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local EC = require("tests.engine_cards")
local V = require("tests.fixtures.vanilla_jokers")
local HandInfo = require("tests.engine_hand_info")
local CardSemantics = require("facts.card_semantics")
local check, done = H.harness("hidden ceiling sweep")

local DECK = {
  { "Ace", "Spades" }, { "2", "Hearts" }, { "3", "Clubs" }, { "4", "Diamonds" }, { "5", "Spades", "m_gold" },
  { "6", "Hearts" }, { "7", "Clubs" }, { "10", "Diamonds" }, { "Jack", "Spades" }, { "Queen", "Hearts" },
  { "King", "Clubs" },
}
local VISIBLE = { QueenHearts = true, ["4Diamonds"] = true, ["7Clubs"] = true, JackSpades = true }
local UNSEEN = {}
for _, d in ipairs(DECK) do
  if not VISIBLE[d[1] .. d[2]] then UNSEEN[#UNSEEN + 1] = d[1] .. d[2] end
end

local function board(jkeys, hidden_key, where)
  local g = H.base_G()
  local by, sid = {}, 0
  local deck = {}
  g.deck = { cards = deck, config = { card_limit = #DECK } }
  g.discard = { cards = {} }
  g.play = { cards = {} }
  for _, d in ipairs(DECK) do
    sid = sid + 1
    local c = EC.playing(d[1], d[2], { sort_id = sid, enhancement = d[3] })
    c.cost, c.sell_cost = 1, 1
    by[d[1] .. d[2]] = c
    g.playing_cards[#g.playing_cards + 1] = c
  end
  local hand = {}
  for _, d in ipairs(DECK) do
    local c = by[d[1] .. d[2]]
    if VISIBLE[d[1] .. d[2]] then hand[#hand + 1] = c; c.area = g.hand end
  end
  local hc = by[hidden_key]
  hc.facing = "back"
  hc.ability.wheel_flipped = true
  if where == "hand" then
    table.insert(hand, 3, hc); hc.area = g.hand
  else
    g.discard.cards[1] = hc; hc.area = g.discard
  end
  g.hand.cards = hand
  for _, d in ipairs(DECK) do
    local c = by[d[1] .. d[2]]
    if not c.area then deck[#deck + 1] = c; c.area = g.deck; c.facing = "back" end
  end
  g.GAME.current_round.idol_card = { id = 14, suit = "Spades", rank = "Ace" }
  g.GAME.current_round.ancient_card = { suit = "Hearts" }
  local js = {}
  for i, k in ipairs(jkeys) do
    local j = V.card_played(k, 900 + i)
    j.area, j.facing = g.jokers, "front"
    js[i] = j
  end
  g.jokers.cards = js
  g.FUNCS.get_poker_hand_info = HandInfo.engine()
  for _, n in ipairs(HandInfo.HANDLIST) do
    g.GAME.hands[n] = { level = 1, chips = 10, mult = 2, played = 0, played_this_round = 0, visible = true, order = 1 }
  end
  H.in_engine_state("SELECTING_HAND")
  require("core.validate").reset_run_state()
  return g
end

local function emitted(jkeys, hidden_key, where)
  board(jkeys, hidden_key, where)
  local section = require("context.ctx_jokers").jokers_section("SELECTING_HAND") or ""
  local st, q = H.force_frame("SELECTING_HAND")
  return section .. "\n" .. st .. "\n" .. q
end

local function first_diff(a, b)
  local la, lb = {}, {}
  for l in a:gmatch("[^\n]+") do la[#la + 1] = l end
  for l in b:gmatch("[^\n]+") do lb[#lb + 1] = l end
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then return tostring(la[i]) .. "  <>  " .. tostring(lb[i]) end
  end
  return ""
end

local per_card = {}
for _, key in ipairs(V.keys()) do
  local g = board({ key }, UNSEEN[1], "hand")
  local ok, proj = pcall(CardSemantics.project, g.jokers.cards[1])
  if ok and type(proj) == "table" then
    for _, e in ipairs(proj.effects or {}) do
      if e.scope == "scoring_card" then per_card[#per_card + 1] = key; break end
    end
  end
end

local listed = {}
for _, k in ipairs(per_card) do listed[k] = true end
check("the registry yields the per-scoring-card jokers",
  #per_card >= 10 and listed.j_scholar and listed.j_greedy_joker and listed.j_arrowhead,
  table.concat(per_card, ","))

for _, where in ipairs({ "hand", "discard" }) do
  for _, key in ipairs(per_card) do
    local base = emitted({ key }, UNSEEN[1], where)
    local bad
    for i = 2, #UNSEEN do
      local other = emitted({ key }, UNSEEN[i], where)
      if other ~= base then bad = UNSEEN[1] .. " vs " .. UNSEEN[i] .. ": " .. first_diff(base, other); break end
    end
    check(key .. ": text is the same whichever unseen card is face-down in the " .. where, not bad, bad)
  end
end

do
  local text = emitted({ "j_scholar" }, "2Hearts", "hand")
  check("Scholar's ceiling counts the one Ace in the pool, not the face-down card",
    text:find("+4 Mult -- 1 such card", 1, true) ~= nil, text:match("[^\n]*Scholar[^\n]*"))
end

done()
