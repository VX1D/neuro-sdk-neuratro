rawset(_G, "NEURO_TEST", true)
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local check, done = H.harness("privacy regressions")
local CtxJokers = require("context.ctx_jokers")
local Scoring = require("util.scoring")
local HandFacts = require("facts.hand_facts")
local Legality = require("facts.boss.legality")
local BossView = require("facts.boss.view")
local Compact = require("context.context_compact")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)
local next_sort_id = 0
local function card(value, suit, hidden, wheel)
  next_sort_id = next_sort_id + 1
  local c = require("tests.engine_cards").playing(H.VALN[value] or value, suit,
    { sort_id = next_sort_id, facing = hidden and "back" or "front" })
  c.ability.wheel_flipped = wheel or nil
  return c
end

local function base_world()
  local states = require("tests.engine_cards").states()
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = states.SELECTING_HAND, STATES = states,
    NEURO = { run_generation = 1, render_dirty_epoch = 0, state_enter_serial = 1, decision_serial = 1 },
    GAME = { dollars = 20, chips = 0, probabilities = { normal = 1 }, hands = {},
      current_round = { hands_left = 4, discards_left = 3 }, blind = {} },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, playing_cards = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
    pack_cards = { cards = {} }, booster_pack = { cards = {} },
    FUNCS = {},
  }
  return G
end

local function hidden_deck_summary(value, wheel)
  local g = base_world()
  local hidden = card(value, "Clubs", not wheel, wheel)
  local visible = card("K", "Spades")
  g.playing_cards = { visible, hidden }
  g.deck.cards = g.playing_cards
  g.hand.cards = { hidden }
  local joker = {
    sort_id = 1, sell_cost = 2, ability = { set = "Joker", name = "Baron", extra = 1.5 },
    config = { center = { key = "j_baron", set = "Joker", name = "Baron", rarity = 1,
      loc_txt = { name = "Baron", description = { "Each King held in hand gives X1.5 Mult" } } } },
    is_rarity = function(_, rarity) return rarity == "Common" end,
  }
  g.jokers.cards = { joker }
  return CtxJokers.jokers_section("SELECTING_HAND")
end

local hidden_k = hidden_deck_summary("K")
local hidden_two = hidden_deck_summary("2")
check("face-down deck identity does not change complete joker context", hidden_k == hidden_two,
  tostring(hidden_k) .. "\n---\n" .. tostring(hidden_two))
local wheel_k = hidden_deck_summary("K", true)
local wheel_two = hidden_deck_summary("2", true)
check("wheel-hidden deck identity does not change complete joker context", wheel_k == wheel_two,
  tostring(wheel_k) .. "\n---\n" .. tostring(wheel_two))

local function ready_summary(hidden_effect, wheel)
  local g = base_world()
  local k1, k2 = card("K", "Hearts"), card("K", "Spades")
  local junk = { card("3", "Clubs"), card("7", "Diamonds"), card("9", "Hearts") }
  g.hand.cards = { k1, k2, junk[1], junk[2], junk[3] }
  g.GAME.hands = { ["Pair"] = { level = 1, chips = 10, mult = 2, visible = true } }
  g.FUNCS.get_poker_hand_info = function() return "Pair", {}, { Pair = { k1, k2 } }, { k1, k2 } end
  local concealed = {
    sort_id = 4, facing = wheel and "front" or "back",
    ability = { set = "Joker", name = "Hidden Joker", type = "Pair", t_mult = hidden_effect,
      wheel_flipped = wheel or nil },
    config = { center = { key = "j_hidden", set = "Joker", name = "Hidden Joker", rarity = 1,
      loc_txt = { name = "Hidden Joker", description = { "+mult if Pair" } } } },
    is_rarity = function(_, rarity) return rarity == "Common" end,
  }
  g.jokers.cards = { concealed }
  return require("context.context_readable").structure_prose(HandFacts.structure())
end

check("concealed joker effects do not change Ready output", ready_summary(4) == ready_summary(99),
  tostring(ready_summary(4)) .. "\n---\n" .. tostring(ready_summary(99)))
check("wheel-hidden joker effects do not change Ready output",
  ready_summary(4, true) == ready_summary(99, true),
  tostring(ready_summary(4, true)) .. "\n---\n" .. tostring(ready_summary(99, true)))

local function hidden_boss_verdict(value, wheel)
  local g = base_world()
  local hidden = card(value, "Clubs", not wheel, wheel)
  local shown = card("K", "Spades")
  g.hand.cards = { shown, hidden }
  g.GAME.blind = { key = "bl_eye", name = "The Eye", hands = { Pair = true }, debuff = {}, disabled = false,
    debuff_hand = function(self, _, _, handname) return self.hands[handname] == true end }
  g.GAME.hands = { Pair = { level = 2, chips = 10, mult = 2, visible = true } }
  g.FUNCS.get_poker_hand_info = function() error("hidden hand classification must not be probed") end
  return Legality.play_verdict({ shown, hidden }, { 1, 2 })
end

check("hidden boss legality is independent of concealed identity",
  hidden_boss_verdict("K") == hidden_boss_verdict("2"),
  tostring(hidden_boss_verdict("K")) .. " / " .. tostring(hidden_boss_verdict("2")))
check("wheel-hidden boss legality is independent of concealed identity",
  hidden_boss_verdict("K", true) == hidden_boss_verdict("2", true),
  tostring(hidden_boss_verdict("K", true)) .. " / " .. tostring(hidden_boss_verdict("2", true)))

local function club_verdict(value, hidden_flag)
  local g = base_world()
  local first = card(value, "Spades", hidden_flag)
  local king = card("K", "Clubs")
  king.debuff = true
  g.hand.cards = { first, king }
  g.GAME.blind = { key = "bl_club", name = "The Club", config = { blind = { key = "bl_club" } },
    debuff = { suit = "Clubs" }, disabled = false }
  g.GAME.hands = { Pair = { level = 1 }, ["High Card"] = { level = 1 } }
  g.FUNCS.get_poker_hand_info = function(sel)
    if sel[1].base.value == sel[2].base.value then return "Pair", "Pair", { Pair = { sel } }, sel end
    return "High Card", "High Card", { ["High Card"] = { { king } } }, { king }
  end
  return Legality.play_verdict({ first, king }, { 1, 2 })
end

check("the all-debuffed verdict is independent of a face-down card's rank",
  club_verdict("5", true) == club_verdict("K", true),
  tostring(club_verdict("5", true)) .. " / " .. tostring(club_verdict("K", true)))
check("a visible selection still gets the all-debuffed verdict",
  tostring(club_verdict("5", false)):find("every scoring card in this selection is +DB", 1, true) ~= nil,
  tostring(club_verdict("5", false)))

local g = base_world()
local wheel_hand = card("K", "Hearts")
wheel_hand.ability.wheel_flipped = true
local wheel_joker = { facing = "front", ability = { wheel_flipped = true } }
g.hand.cards = { wheel_hand }
g.jokers.cards = { wheel_joker }
local view = BossView.build({ key = "bl_eye", debuff = {}, disabled = false })
check("boss view counts wheel-hidden hand and joker cards", view.facedown_in_hand == 1 and view.facedown_jokers == 1,
  tostring(view.facedown_in_hand) .. "/" .. tostring(view.facedown_jokers))

do
  local function note_for(values)
    local sel = {}
    for i, v in ipairs(values) do sel[i] = card(v[1], v[2], v[3]) end
    return Legality.mask_note(sel)
  end
  local one = note_for({ { "K", "Spades", true }, { "5", "Hearts" } })
  check("one face-down card: the note says one", one:find("One selected card is face down", 1, true) == 1, one)
  local five = note_for({ { "K", "Spades", true }, { "5", "Hearts", true }, { "2", "Clubs", true },
    { "9", "Diamonds", true }, { "A", "Spades", true } })
  check("five face-down cards: the note says five", five:find("5 selected cards are face down", 1, true) == 1, five)
  local other = note_for({ { "3", "Hearts", true }, { "7", "Clubs", true }, { "4", "Diamonds", true },
    { "Q", "Hearts", true }, { "8", "Clubs", true } })
  check("the note does not depend on the face-down cards' identities", five == other, five .. " / " .. other)
  local mixed = note_for({ { "K", "Spades", true }, { "5", "Hearts" }, { "2", "Clubs", true } })
  check("face-up cards are not counted", mixed:find("2 selected cards are face down", 1, true) == 1, mixed)
  check("no face-down card: no note", note_for({ { "K", "Spades" } }) == nil)
end

do
  local BossRender = require("facts.boss.render")
  local function pillar_world(hidden_played)
    local w = base_world()
    local used = card("K", "Hearts")
    used.debuff, used.ability.played_this_ante = true, true
    local fresh = card("5", "Spades")
    local fd = card("Q", "Clubs", true)
    fd.debuff, fd.ability.played_this_ante = hidden_played or nil, hidden_played or nil
    w.hand.cards = { used, fresh, fd }
    w.playing_cards = { used, fresh, fd }
    for _, c in ipairs(w.hand.cards) do c.area = w.hand end
    w.GAME.blind = { key = "bl_pillar", name = "The Pillar", config = { blind = { key = "bl_pillar" } },
      debuff = {}, hands = {}, disabled = false }
    return w
  end
  local function probe(hidden_played)
    local w = pillar_world(hidden_played)
    return BossView.build(w.GAME.blind).pillar_used_in_hand,
      BossRender.render("status", "bl_pillar", { blind = w.GAME.blind })
  end
  local fresh_view, fresh_line = probe(false)
  local used_view, used_line = probe(true)
  check("Pillar in-hand count ignores a face-down card's history", fresh_view == 1 and used_view == 1,
    tostring(fresh_view) .. "/" .. tostring(used_view))
  local function hand_clause(line) return tostring(line):match("; (%d+ of them are in your hand%.[^%.]*%.?)") end
  check("Pillar status line's in-hand clause is independent of a face-down card",
    hand_clause(fresh_line) ~= nil and hand_clause(fresh_line) == hand_clause(used_line),
    tostring(fresh_line) .. "\n---\n" .. tostring(used_line))
  check("Pillar status line says face-down cards are not counted",
    tostring(used_line):find("Face-down cards in your hand are not counted.", 1, true) ~= nil, tostring(used_line))

  local w = base_world()
  local up = { facing = "front", ability = { set = "Joker", eternal = true } }
  local down_eternal = { facing = "back", ability = { set = "Joker", eternal = true } }
  local down_free = { facing = "back", ability = { set = "Joker" } }
  w.jokers.cards = { up, down_eternal }
  local a = BossView.build({ key = "bl_final_leaf", debuff = {}, disabled = false }).sellable_jokers
  w.jokers.cards = { up, down_free }
  local b = BossView.build({ key = "bl_final_leaf", debuff = {}, disabled = false }).sellable_jokers
  check("sellable joker count does not read a face-down joker's stickers", a == b, tostring(a) .. "/" .. tostring(b))
end

local function shop_card(cost)
  return { cost = cost, sell_cost = 1, ability = { set = "Joker", name = "Shop Joker" },
    config = { center = { key = "j_joker", set = "Joker", name = "Joker", rarity = 1,
      loc_txt = { name = "Joker", description = { "Adds mult" } } } },
    is_rarity = function(_, rarity) return rarity == "Common" end }
end

local shop_world = base_world()
shop_world.STATE = shop_world.STATES.SHOP
shop_world.GAME.blind = {}
shop_world.shop_jokers.cards = { shop_card(3) }
local before = Compact.build("SHOP", nil, {})
shop_world.shop_jokers.cards[1].cost = 17
local after = Compact.build("SHOP", nil, {})
check("engine-only visible shop mutation reaches the next context build",
  before ~= after and before:find("$3", 1, true) ~= nil and after:find("$17", 1, true) ~= nil,
  tostring(before) .. "\n---\n" .. tostring(after))

done()
