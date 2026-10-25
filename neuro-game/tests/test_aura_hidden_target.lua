require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local check, done = H.harness("aura hidden target")
local EC = require("tests.engine_cards")
local V = require("tests.fixtures.vanilla_jokers")
local HandInfo = require("tests.engine_hand_info")

local RANKS = { "2","3","4","5","6","7","8","9","10","Jack","Queen","King","Ace" }
local SUITS = { "Spades","Hearts","Clubs","Diamonds" }
local FACE = { Jack = true, Queen = true, King = true }

local MODS = {
  ["3Hearts"] = { enhancement = "m_steel" }, ["9Spades"] = { enhancement = "m_gold" },
  ["KingClubs"] = { enhancement = "m_glass" }, ["5Diamonds"] = { enhancement = "m_lucky" },
  ["7Spades"] = { enhancement = "m_stone" }, ["QueenHearts"] = { seal = "Red" },
  ["10Clubs"] = { edition = { foil = true, key = "e_foil" } }, ["2Diamonds"] = { enhancement = "m_wild" },
  ["AceHearts"] = { edition = { polychrome = true, key = "e_polychrome" } },
  ["8Clubs"] = { enhancement = "m_bonus" }, ["4Spades"] = { enhancement = "m_mult" },
}

local function all_keys()
  local ks = {}
  for _, s in ipairs(SUITS) do for _, r in ipairs(RANKS) do ks[#ks + 1] = r .. s end end
  return ks
end

local function lcg(seed) local x = seed return function(n) x = (x * 1103515245 + 12345) % 2147483648 return (x % n) + 1 end end
local function make_board(world, opts)
  opts = opts or {}
  local g = H.base_G()
  g.discard = { cards = {} }
  g.play = { cards = {} }
  local deck = {}
  g.deck = { cards = deck, config = { card_limit = 52 } }
  local by, sid = {}, 0
  for _, s in ipairs(SUITS) do
    for _, r in ipairs(RANKS) do
      sid = sid + 1
      local k = r .. s
      local m = MODS[k] or {}
      local c = EC.playing(r, s, { sort_id = sid, enhancement = m.enhancement, seal = m.seal, edition = m.edition })
      c.cost, c.sell_cost = 1, 1
      by[k] = c
      g.playing_cards[#g.playing_cards + 1] = c
    end
  end
  local hand = {}
  for i, e in ipairs(world.hand) do
    local c = by[e.key]
    c.area = g.hand
    if e.hidden then c.facing = "back"; c.ability.wheel_flipped = true end
    hand[i] = c
  end
  g.hand.cards = hand
  for _, e in ipairs(world.disc) do
    local c = by[e.key]
    c.area = g.discard
    if e.hidden then c.facing = "back"; c.ability.wheel_flipped = true end
    g.discard.cards[#g.discard.cards + 1] = c
  end
  for _, k in ipairs(world.pile) do
    local c = by[k]
    c.area = g.deck; c.facing = "back"
    deck[#deck + 1] = c
  end
  local js = {}
  for i, k in ipairs(opts.jokers or {}) do
    local j = V.card_played(k, 900 + i)
    j.area, j.facing = g.jokers, "front"
    js[i] = j
  end
  g.jokers.cards = js
  g.GAME.current_round.idol_card = { id = 14, suit = "Spades", rank = "Ace" }
  g.GAME.current_round.ancient_card = { suit = "Hearts" }
  g.GAME.current_round.mail_card = { id = 5, rank = "5" }
  g.GAME.current_round.castle_card = { suit = "Clubs" }
  g.FUNCS.get_poker_hand_info = HandInfo.engine()
  for _, n in ipairs(HandInfo.HANDLIST) do
    g.GAME.hands[n] = { level = 1, chips = 10, mult = 2, played = 0, played_this_round = 0, visible = true, order = 1 }
  end
  if opts.blind then
    g.GAME.blind = { name = opts.blind.name, chips = 1600, dollars = 5, in_blind = true, boss = true,
      debuff = {}, disabled = false, config = { blind = { key = opts.blind.key } },
      get_type = function() return "Boss" end }
    g.GAME.round_resets.blind_choices.Boss = opts.blind.key
  end
  if opts.hl then
    g.hand.highlighted = {}
    for _, i in ipairs(opts.hl) do g.hand.highlighted[#g.hand.highlighted + 1] = hand[i] end
  end
  H.in_engine_state("SELECTING_HAND")
  require("core.validate").reset_run_state()
  require("facts.fact_hints").reset_pending()
  return g, by
end

local TEMPLATES = {
  { "AceHearts", "QueenHearts", "JackHearts", "9Hearts", "7Clubs", "5Diamonds", "3Spades", "KingSpades" },
  { "KingSpades", "KingHearts", "KingClubs", "9Hearts", "9Spades", "5Diamonds", "3Spades", "2Clubs" },
  { "5Hearts", "6Spades", "7Clubs", "8Diamonds", "10Hearts", "QueenHearts", "2Spades", "2Clubs" },
  { "2Hearts", "6Hearts", "9Hearts", "JackHearts", "KingHearts", "3Clubs", "8Spades", "4Diamonds" },
  { "7Spades", "7Hearts", "AceSpades", "AceClubs", "3Diamonds", "3Hearts", "KingDiamonds", "10Spades" },
  { "2Spades", "2Hearts", "2Clubs", "2Diamonds", "5Clubs", "5Spades", "6Hearts", "JackDiamonds" },
}
local function emit_aura(hidden_key, visible_have_edition)
  local world = { hand = {}, disc = {}, pile = {} }
  local vis = TEMPLATES[1]
  for i, k in ipairs(vis) do world.hand[i] = { key = k, hidden = false } end
  world.hand[#world.hand + 1] = { key = hidden_key, hidden = true }
  local used = {}
  for _, e in ipairs(world.hand) do used[e.key] = true end
  for _, k in ipairs(all_keys()) do if not used[k] then world.pile[#world.pile + 1] = k end end
  for _, e in ipairs(world.hand) do
    if not e.hidden and visible_have_edition then MODS[e.key] = MODS[e.key] or {}; MODS[e.key].edition = { foil = true, key = "e_foil" } end
    if not e.hidden and not visible_have_edition then if MODS[e.key] then MODS[e.key].edition = nil end end
  end
  MODS["4Hearts"] = { edition = { foil = true, key = "e_foil" } }
  local g = make_board(world, { blind = { key = "bl_house", name = "The House" } })
  local EC2 = require("tests.engine_cards")
  local aura = EC2.consumable("c_aura", { sort_id = 5001, sell_cost = 2, cost = 4 })
  aura.area = g.consumeables
  g.consumeables.cards = { aura }
  g.consumeables.config = { card_limit = 2 }
  local st, q = H.force_frame("SELECTING_HAND")
  return st .. "\n" .. q
end

local function offered(t) return t:find("Aura", 1, true) ~= nil end
local A = emit_aura("4Hearts", true)
local B = emit_aura("6Diamonds", true)
local C = emit_aura("6Diamonds", false)
check("hidden card's edition does not change the frame", A == B)
check("Aura is offered when a visible card can take it", offered(C))

local function probe(hidden_key)
  emit_aura(hidden_key, true)
  local ok, exec = pcall(require("core.dispatcher").preflight, "use_consumable",
    { name = "Aura", area = "consumables", index = 1, hand_indices = { 9 } })
  return ok and exec and "accepted" or "refused"
end
check("preflight on a face-down target is the same either way", probe("4Hearts") == probe("6Diamonds"))
done()
