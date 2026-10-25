require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("decision delta hidden corpus")

local DD = require("facts.decision_delta")
local DestructionLog = require("core.destruction_log")

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local function card(v, suit, sort_id)
  return require("tests.engine_cards").playing(H.VALN[v] or v, suit, { sort_id = sort_id, facing = "back" })
end

local function permute(list, seed)
  local out, x = {}, seed
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    x = (x * 1103515245 + 12345) % 2147483648
    local j = (x % i) + 1
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function remove(list, c)
  for i, v in ipairs(list) do if v == c then table.remove(list, i); return end end
end

local function move(c, area, face_up)
  remove(G.hand.cards, c); remove(G.deck.cards, c); remove(G.discard.cards, c); remove(G.play.cards, c)
  c.area = area
  c.facing = face_up and "front" or "back"
  if face_up then c.ability.wheel_flipped = nil end
  area.cards[#area.cards + 1] = c
end

local function draw(face_up)
  local c = G.deck.cards[#G.deck.cards]
  move(c, G.hand, face_up)
  if not face_up then c.ability.wheel_flipped = true end
  return c
end

local serial = 0
local function decide(state)
  serial = serial + 1
  G.NEURO.decision_serial = serial
  local text, cand = DD.for_force(state)
  DD.commit(cand)
  return text or ""
end

local HAND0 = { "8Clubs", "7Hearts", "6Clubs", "5Hearts", "4Clubs", "QHearts", "3Diamonds" }
local DRAW1 = { "KSpades", "9Diamonds" }
local DRAW2 = { "2Spades", "JHearts", "10Clubs", "4Spades", "AHearts", "7Spades" }

local function play_world(seed, hidden)
  local by, all = {}, {}
  for s_i, s in ipairs(SUITS) do
    for v_i, v in ipairs(RANKS) do
      local c = card(v, s, (s_i - 1) * 13 + v_i)
      by[v .. s] = c
      all[#all + 1] = c
    end
  end
  _G.G = {
    GAME = { dollars = 10, used_vouchers = {}, hands = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {} }, deck = { cards = {} }, discard = { cards = {} }, play = { cards = {} },
    playing_cards = all,
    NEURO = { run_generation = 1, shop_visit_epoch = 1, decision_serial = 0 },
  }
  local fixed = {}
  for _, k in ipairs(HAND0) do fixed[by[k]] = true end
  for _, k in ipairs(DRAW1) do fixed[by[k]] = true end
  for _, k in ipairs(DRAW2) do fixed[by[k]] = true end
  for _, k in ipairs(hidden) do fixed[by[k]] = true end
  local rest = {}
  for _, c in ipairs(all) do if not fixed[c] then rest[#rest + 1] = c end end
  rest = permute(rest, seed)
  local function stack(keys)
    for i = #keys, 1, -1 do rest[#rest + 1] = by[keys[i]] end
  end
  stack({ DRAW2[1], DRAW2[2], hidden[2], DRAW2[3], DRAW2[4], DRAW2[5], DRAW2[6] })
  stack(DRAW1)
  for _, c in ipairs(rest) do move(c, G.deck, false) end
  for _, k in ipairs(HAND0) do move(by[k], G.hand, true) end
  move(by[hidden[1]], G.hand, false)
  by[hidden[1]].ability.wheel_flipped = true

  local texts = {}
  texts[#texts + 1] = decide("SELECTING_HAND")
  move(by["8Clubs"], G.discard, false)
  move(by["7Hearts"], G.discard, false)
  local secret = by[hidden[1]]
  secret.config.center = { key = "m_gold", set = "Enhanced" }
  secret.ability.set = "Enhanced"
  draw(true); draw(true)
  texts[#texts + 1] = decide("SELECTING_HAND")
  local top = {}
  for i = 1, 7 do top[i] = table.remove(G.deck.cards) end
  G.deck.cards = permute(G.deck.cards, seed + 7)
  for i = 7, 1, -1 do G.deck.cards[#G.deck.cards + 1] = top[i] end
  texts[#texts + 1] = decide("SELECTING_HAND")
  local seen = by["5Hearts"]
  seen.config.center = { key = "m_mult", set = "Enhanced" }
  seen.ability.set = "Enhanced"
  texts[#texts + 1] = decide("SELECTING_HAND")
  local keep = {}
  for i = 1, 7 do keep[i] = table.remove(G.deck.cards) end
  for _, area in ipairs({ G.hand, G.discard }) do
    while #area.cards > 0 do move(area.cards[#area.cards], G.deck, false) end
  end
  G.deck.cards = permute(G.deck.cards, seed + 13)
  for i = 7, 1, -1 do G.deck.cards[#G.deck.cards + 1] = keep[i] end
  for _, c in ipairs(G.deck.cards) do c.ability.wheel_flipped = nil end
  texts[#texts + 1] = decide("SHOP")
  draw(true); draw(true); draw(false); draw(true); draw(true); draw(true); draw(true)
  texts[#texts + 1] = decide("SELECTING_HAND")
  return texts
end

local WORLDS = {
  { seed = 1, hidden = { "9Hearts", "KClubs" } },
  { seed = 977, hidden = { "ASpades", "3Clubs" } },
  { seed = 31337, hidden = { "2Diamonds", "QSpades" } },
}

local base = play_world(WORLDS[1].seed, WORLDS[1].hidden)
for w = 2, #WORLDS do
  local other = play_world(WORLDS[w].seed, WORLDS[w].hidden)
  for i = 1, #base do
    check(string.format("world %d decision %d: delta identical to world 1", w, i), base[i] == other[i],
      "[" .. base[i] .. "]\nvs\n[" .. other[i] .. "]")
  end
end

local all = table.concat(base, "\n")
check("no pile slot is ever named", all:find("item #", 1, true) == nil, all)
check("the unseen enhancement of a face-down card is not reported", all:find("Gold", 1, true) == nil, all)
check("control: a visible card's change is still reported",
  all:find("5 of Hearts to 5 of Hearts (Mult", 1, true) ~= nil, all)

do
  local c = card("6", "Clubs", 99)
  _G.G = { deck = { cards = { card("2", "Hearts", 1), c, card("3", "Hearts", 2) } }, discard = { cards = {} } }
  c.area = G.deck
  local label = DestructionLog.card_label(c)
  check("a pile card's label names neither its slot nor its identity",
    label:find("#", 1, true) == nil and label:find("Clubs", 1, true) == nil, label)
  G.deck.cards = { c }
  local alone = DestructionLog.card_label(c)
  check("a pile card's label does not depend on where it sits", label == alone, label .. " vs " .. alone)
end

done()
