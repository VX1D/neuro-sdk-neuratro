rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }

local H = require("tests.helpers")
local EngineCards = require("tests.engine_cards")
local check, done = H.harness("hidden fact derivability")

local sid = 0
local function card(v, suit, face_down)
  sid = sid + 1
  local c = EngineCards.playing(H.VALN[v] or v, suit, { sort_id = sid, facing = face_down and "back" or "front" })
  c.cost, c.sell_cost = 1, 1
  return c
end

local function joker(key, name, ability, desc, face_down)
  sid = sid + 1
  ability = ability or {}
  ability.name = name
  ability.set = "Joker"
  return { sort_id = sid, cost = 5, sell_cost = 2, ability = ability,
    facing = face_down and "back" or "front",
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name, description = { desc or "" } } } },
    is_rarity = function(_, r) return r == "Common" end }
end

local base_G = H.base_G

local FactHints = require("facts.fact_hints")

local function acorn_chain(order)
  local g = base_G()
  g.jokers.cards = order
  for _, j in ipairs(order) do j.area = g.jokers; j.facing = "back" end
  return (FactHints.copy_chain() or "")
end

local bp_a  = joker("j_blueprint", "Blueprint", {}, "Copies ability of Joker to the right")
local bar_a = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
local chain_bp_first = acorn_chain({ bp_a, bar_a })

local bp_b  = joker("j_blueprint", "Blueprint", {}, "Copies ability of Joker to the right")
local bar_b = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
local chain_bar_first = acorn_chain({ bar_b, bp_b })

check("Amber Acorn: shuffled face-down order is not derivable from the copy-chain hint",
  chain_bp_first == chain_bar_first, "[" .. chain_bp_first .. "] vs [" .. chain_bar_first .. "]")
check("Amber Acorn: the copy-chain hint says nothing at all while the roster is hidden",
  chain_bp_first == "", "[" .. chain_bp_first .. "]")

do
  local g = base_G()
  local bp  = joker("j_blueprint", "Blueprint", {}, "Copies ability of Joker to the right")
  local bar = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  g.jokers.cards = { bp, bar }
  for _, j in ipairs(g.jokers.cards) do j.area = g.jokers end
  local text = (FactHints.copy_chain() or "")
  check("face-up roster: the copy-chain hint still names Blueprint's target",
    text:find("Blueprint (slot 1) copies the joker to its right (Baron)", 1, true) ~= nil, text)
end

local CtxJokers = require("context.ctx_jokers")
local Scoring = require("util.scoring")

local function quantity_sig(q)
  if not q then return "nil" end
  return tostring(q.k) .. "/" .. tostring(q.n) .. "/" .. tostring(q.why and q.why[1])
end

local RANKS = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
local SUITS = { "Spades","Hearts","Clubs","Diamonds" }
local function standard_deck()
  local deck, by = {}, {}
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = card(v, s)
      deck[#deck + 1] = c
      by[v .. s] = c
    end
  end
  return deck, by
end

local function baron_board(hidden_value, pos)
  local g = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  local deck, by = standard_deck()
  g.deck = { cards = deck }
  g.playing_cards = deck
  local hidden = by[hidden_value .. "Clubs"]
  hidden.facing = "back"
  local hand = { by["KSpades"], by["KHearts"], by["4Diamonds"], by["7Hearts"] }
  table.insert(hand, pos or 3, hidden)
  g.hand.cards = hand
  local section = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
  local ledger = Scoring.joker_summary().ledger
  return section, quantity_sig(ledger and ledger.gated and ledger.gated.xmult)
end

local each_position = require("tests.helpers").each_position

local hidden_king = baron_board("K")
local hidden_two  = baron_board("2")
check("hidden hand card: the ledger never names the concealed card", each_position(5,
  function(pos)
    local sk, qk = baron_board("K", pos)
    local st = baron_board("2", pos)
    local named = sk:find("King of Clubs", 1, true) or st:find("2 of Clubs", 1, true)
      or qk:find("of Clubs", 1, true)
    return named == nil, "[" .. sk .. " | " .. qk .. "] vs [" .. st .. "]"
  end))
check("hidden hand card: the ledger itself carries no held-card count", each_position(5,
  function(pos)
    local _, qk = baron_board("K", pos)
    return qk:find("in hand", 1, true) == nil, qk
  end))
check("hidden hand card: no held-card ceiling figure is printed at all",
  not tostring(hidden_king):find("Mult more from jokers", 1, true), hidden_king)
check("hidden hand card: the roster row itself survives (ownership is not the hidden fact)",
  tostring(hidden_king):find("1. Baron", 1, true) ~= nil, hidden_king)

do
  local g = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  g.hand.cards = { card("K", "Spades"), card("K", "Hearts"), card("2", "Clubs"),
                   card("4", "Diamonds"), card("7", "Hearts") }
  g.playing_cards = g.hand.cards
  local visible = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
  check("all-visible hand: the held-card ceiling is still stated",
    visible:find("Mult more from jokers", 1, true) ~= nil, visible)
  local q = Scoring.joker_summary().ledger.gated.xmult
  check("all-visible hand: the ledger counts the two visible Kings off the hand",
    quantity_sig(q):find("2 such cards in hand", 1, true) ~= nil, quantity_sig(q))
end

do
  local g = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = g.jokers
  g.jokers.cards = { baron }
  local deck = {}
  for _, s in ipairs({ "Spades", "Hearts", "Clubs", "Diamonds" }) do
    for _, v in ipairs({ "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }) do
      deck[#deck + 1] = card(v, s)
    end
  end
  g.playing_cards = deck
  g.deck = { cards = deck }

  g.hand.cards = {}
  local empty = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
  check("empty hand is not what this guard reacts to (no face-down card, ceiling still stated)",
    empty:find("you hold at most", 1, true) ~= nil, empty)

  g.hand.cards = { card("K", "Spades"), card("9", "Hearts") }
  local held = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
  check("a real hand keeps the ceiling",
    held:find("Mult more from jokers", 1, true) ~= nil, held)
end

local LB = require("tests.fixtures.live_board")
local HF = require("facts.hand_facts")
local CR = require("context.context_readable")

_G.localize = _G.localize or function() return "" end

local EXTRA_TEXT = { j_jolly = "+8 Mult if played hand contains a Pair" }

local function acorn_board(keys, visible)
  LB.load("SELECTING_HAND", "Amber Acorn: the boss that names reordering")
  local roster = {}
  for i, key in ipairs(keys) do
    roster[i] = LB.joker(key, 800 + i)
    if not LB.TEXT[key] then
      roster[i].config.center.loc_txt =
        { name = roster[i].config.center.name, description = { EXTRA_TEXT[key] } }
    end
    roster[i].area = G.jokers
    if not visible then roster[i].facing = "back" end
  end
  G.jokers = { cards = roster, config = { card_limit = 5 } }
  return CR.structure_prose(HF.structure())
end

local function sweep(keys, render)
  local forms, order, out = {}, {}, keys
  local function permute(k)
    if k > #out then
      local text = render(acorn_board(out))
      if not forms[text] then forms[text] = true; order[#order + 1] = text end
      return
    end
    for i = k, #out do
      out[k], out[i] = out[i], out[k]
      permute(k + 1)
      out[k], out[i] = out[i], out[k]
    end
  end
  permute(1)
  return order
end

local ACORN_MULTISET = { "j_hologram", "j_cavendish", "j_jolly", "j_baron", "j_scary_face" }

local prose_forms = sweep(ACORN_MULTISET, function(s) return s end)
check("Amber Acorn: 120 hidden orders of one multiset render one prose payload",
  #prose_forms == 1, #prose_forms .. " distinct forms, e.g. [" ..
    prose_forms[1] .. "] vs [" .. prose_forms[math.min(2, #prose_forms)] .. "]")

check("Amber Acorn: hidden joker contributions are rendered in no chain at all",
  prose_forms[1]:find("jokers left to right", 1, true) == nil
    and prose_forms[1]:find("as the cards score", 1, true) == nil, prose_forms[1])

do
  local visible = acorn_board(ACORN_MULTISET, true)
  check("face-up roster: the ready-hand note still names the paying slot",
    visible:find("then jokers left to right: joker 1 ", 1, true) ~= nil, visible)
end

do
  local SPLASH_SET = { "j_splash", "j_cavendish", "j_rocket", "j_baron", "j_hologram" }
  for _, visible in ipairs({ true, false }) do
    local summary = acorn_board(SPLASH_SET, visible)
    local roster = tostring(CtxJokers.jokers_section("SELECTING_HAND"))
    local in_roster = roster:find("Splash", 1, true) ~= nil
    local in_forecast = summary:find("(Splash)", 1, true) ~= nil
    check("Splash cue agrees with the roster it is printed beside (" ..
      (visible and "face-up" or "face-down") .. ")",
      in_roster == in_forecast and in_roster == visible,
      "roster=" .. tostring(in_roster) .. " forecast=" .. tostring(in_forecast))
  end
end

do
  local HF2 = require("facts.hand_facts")
  -- Smeared is derived from the live joker even when it is face down.
  local function suit_card(v, suit) return EngineCards.playing(H.VALN[v] or v, suit) end

  local HAND = { { "K", "Hearts" }, { "9", "Hearts" }, { "Q", "Diamonds" }, { "J", "Diamonds" },
                 { "7", "Clubs" }, { "5", "Spades" }, { "3", "Spades" } }
  local RANKS2 = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
  local SUITS2 = { "Hearts","Spades","Diamonds","Clubs" }

  local function smeared_board(joker_key, visible)
    local g = base_G()
    local j = joker(joker_key, joker_key == "j_smeared" and "Smeared Joker" or "Joker", {}, "")
    j.facing = visible and "front" or "back"
    j.area = g.jokers
    g.jokers.cards = { j }
    local used, hand = {}, {}
    for _, hc in ipairs(HAND) do
      hand[#hand + 1] = suit_card(hc[1], hc[2])
      used[hc[1] .. hc[2]] = true
    end
    local pile = {}
    for _, su in ipairs(SUITS2) do
      for _, v in ipairs(RANKS2) do
        if not used[v .. su] then pile[#pile + 1] = suit_card(v, su) end
      end
    end
    g.hand = { cards = hand, highlighted = {},
      config = { card_limit = 8, highlighted_limit = 5 } }
    g.deck = { cards = pile }
    g.GAME.hands = {}
    g.FUNCS = {}
    return CR.structure_prose(HF2.structure())
  end

  local hidden_smeared = smeared_board("j_smeared", false)
  local hidden_plain   = smeared_board("j_joker", false)
  check("a face-down Smeared Joker's effect is reported truthfully in the suit tally",
    hidden_smeared ~= hidden_plain,
    "[" .. hidden_smeared .. "]\nvs\n[" .. hidden_plain .. "]")
  check("and the concealed board states the true shape, from the engine's own answer",
    hidden_smeared:find("most cards of one suit 4;", 1, true) ~= nil,
    hidden_smeared)

  local shown = smeared_board("j_smeared", true)
  check("face-up Smeared Joker: the count and the label are both smeared",
    shown:find("Flush: 4 red", 1, true) ~= nil, shown)
  check("face-up Smeared Joker: no base-suit label is printed beside a smeared count",
    shown:find("4 Hearts", 1, true) == nil and shown:find("4 Diamonds", 1, true) == nil, shown)
end

do
  local Scoring2 = require("util.scoring")

  local function roster_board(hidden_key, hidden_name, hidden_ability)
    local g = base_G()
    local banner = joker("j_banner", "Banner", { extra = 30 }, "+30 Chips for each remaining discard")
    local scary = joker("j_scary_face", "Scary Face", { extra = 30 }, "Played face cards give +30 Chips when scored")
    local secret = joker(hidden_key, hidden_name, hidden_ability, "", true)
    g.jokers.cards = { banner, scary, secret }
    for _, j in ipairs(g.jokers.cards) do j.area = g.jokers end
    g.GAME.current_round.discards_left = 3
    local sm = Scoring2.joker_summary()
    local flat = string.format("%s/%s/%s/%s", tostring(sm and sm.chips), tostring(sm and sm.mult),
      tostring(sm and sm.xmult), tostring(sm and sm.xchips))
    return flat, Scoring2.owned_xmult_state()
  end

  local xa, sa = roster_board("j_cavendish", "Cavendish", { extra = { Xmult = 3 }, x_mult = 1 })
  local xb, sb = roster_board("j_joker", "Joker", { mult = 4 })
  check("hidden joker: its numbers are not derivable from the always-on aggregate",
    xa == xb, "[" .. xa .. "] vs [" .. xb .. "]")
  check("hidden joker: the face-up jokers' own numbers survive the filter",
    xa:find("^90/") ~= nil, xa)
  check("hidden joker: owned_xmult_state does not answer 'does it have xMult'",
    sa == sb, sa .. " vs " .. sb)
  check("hidden joker: and it is not the answer that prints the roster-wide claim",
    sa ~= "none", sa)

  do
    local g = base_G()
    local jkr = joker("j_joker", "Joker", { mult = 4 }, "+4 Mult")
    jkr.area = g.jokers
    g.jokers.cards = { jkr }
    local sm = Scoring2.joker_summary()
    check("all-visible roster: the always-on total is still published",
      sm and sm.mult == 4, sm and tostring(sm.mult))
    check("all-visible roster: 'no xMult' is still answerable",
      Scoring2.owned_xmult_state() == "none", Scoring2.owned_xmult_state())
  end

  do
    local function baseball(hidden_rarity)
      local g = base_G()
      local bb = joker("j_baseball", "Baseball Card", { extra = 1.5 }, "")
      bb.is_rarity = function(_, r) return r == "Rare" end
      local secret = joker("j_joker", "Joker", { mult = 4 }, "", true)
      secret.is_rarity = function(_, r) return r == hidden_rarity end
      g.jokers.cards = { bb, secret }
      for _, j in ipairs(g.jokers.cards) do j.area = g.jokers end
      local q = Scoring2.joker_summary().ledger.gated.xmult
      return tostring(q.k) .. "/" .. tostring(q.n) .. "/" .. tostring(q.why[1])
    end
    check("hidden joker: its rarity is not derivable from a per-other-joker ceiling",
      baseball("Uncommon") == baseball("Common"),
      baseball("Uncommon") .. " vs " .. baseball("Common"))
  end
end

done()
