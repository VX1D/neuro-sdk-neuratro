rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }
_G.localize = function() return "" end

local H = require("tests.helpers")
local check, done = H.harness("possession-visibility")

local sid = 0
local function joker(key, name, desc)
  sid = sid + 1
  return { sort_id = sid, cost = 5, sell_cost = 2, facing = "front", debuff = false,
    ability = { name = name, set = "Joker" },
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name, description = { desc or "" } } } },
    is_rarity = function(_, r) return r == "Common" end }
end

local function base_G()
  _G.G = {
    NEURO = { run_generation = 1 }, STATE = 1,
    STATES = { SELECTING_HAND = 1, SHOP = 2, BLIND_SELECT = 3, ROUND_EVAL = 7, MENU = 20 },
    P_BLINDS = {}, P_TAGS = {}, TIMERS = { REAL = 100, TOTAL = 100 },
    SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, playing_cards = {}, FUNCS = {},
    GAME = { dollars = 20, chips = 0, round = 4, skips = 0, win_ante = 8, used_vouchers = {},
      modifiers = {}, tags = {}, interest_amount = 1, interest_cap = 25,
      probabilities = { normal = 1 }, starting_params = {}, hands = {},
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5, free_rerolls = 0 },
      round_resets = { ante = 3, hands = 4, discards = 3 },
      round_bonus = { discards = 0, next_hands = 0 } },
  }
  return _G.G
end

local function fresh_game_rules()
  package.loaded["context.game_rules"] = nil
  return require("context.game_rules")
end

do
  local g = base_G()
  g.jokers.cards = { joker("j_splash", "Splash", "Every played card counts in scoring") }
  local face_up = fresh_game_rules().run_frame_text()
  check("face-up Splash is stated as a scoring exception",
    face_up:find("Splash scores every played card", 1, true) ~= nil, face_up)

  g.jokers.cards[1].facing = "back"
  local flipped = fresh_game_rules().run_frame_text()
  check("a face-down joker's identity is not read off config.center.key",
    flipped:find("Splash", 1, true) == nil, flipped)
  check("and the rest of the run frame is unchanged by the flip",
    flipped == (face_up:gsub("Current scoring exceptions: Splash scores every played card%. ", "")),
    "[" .. flipped .. "] vs [" .. face_up .. "]")
end

do
  local g = base_G()
  g.jokers.cards = { joker("j_splash", "Splash", "Every played card counts in scoring") }
  g.jokers.cards[1].facing = "back"
  local as_splash = fresh_game_rules().run_frame_text()

  g = base_G()
  g.jokers.cards = { joker("j_joker", "Joker", "+4 Mult") }
  g.jokers.cards[1].facing = "back"
  local as_joker = fresh_game_rules().run_frame_text()

  check("the run frame is byte-identical for two different face-down jokers",
    as_splash == as_joker, "[" .. as_splash .. "] vs [" .. as_joker .. "]")
end

do
  local LB = require("tests.fixtures.live_board")
  local FactHints = require("facts.fact_hints")

  local function force_query(key, name, desc, facing)
    LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
    local j = joker(key, name, desc)
    j.facing = facing
    j.area = G.jokers
    G.jokers.cards = { j }
    FactHints.reset_pending()
    require("context.context_compact").invalidate_cache()
    local built = require("force.force_selecting_hand").build()
    return (type(built) == "table" and built.query) or ""
  end

  local SPLASH_CUE = "Exception (Splash)"
  local up = force_query("j_splash", "Splash", "Every played card counts in scoring", "front")
  check("face-up Splash still earns its scoring cue in the force query",
    up:find(SPLASH_CUE, 1, true) ~= nil, up)

  local hidden_splash = force_query("j_splash", "Splash", "Every played card counts in scoring", "back")
  check("a face-down Splash is not named in the force query",
    hidden_splash:find("Splash", 1, true) == nil,
    hidden_splash:match("[^.]*Splash[^.]*") or hidden_splash)

  local hidden_other = force_query("j_joker", "Joker", "+4 Mult", "back")
  check("the force query is byte-identical for two different face-down jokers",
    hidden_splash == hidden_other,
    "[" .. hidden_splash:sub(1, 400) .. "] vs [" .. hidden_other:sub(1, 400) .. "]")
end

do
  local DD = require("facts.decision_delta")

  local function gained_line(key, name)
    _G.G = { GAME = { dollars = 10, used_vouchers = {}, hands = {} }, playing_cards = {},
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      NEURO = { run_generation = 1, decision_serial = 1 } }
    local before = DD.capture()
    local j = joker(key, name, "")
    j.facing = "back"
    G.jokers.cards = { j }
    local after = DD.capture()
    return DD.render(before, after) or "", after
  end

  local smeared, smeared_board = gained_line("j_smeared", "Smeared Joker")
  local blueprint = gained_line("j_blueprint", "Blueprint")
  check("a face-down joker gained is reported without naming it",
    smeared:find("Smeared", 1, true) == nil and smeared:find("jokers gained", 1, true) ~= nil,
    smeared)
  check("the delta line is byte-identical for two different face-down jokers",
    smeared == blueprint, "[" .. smeared .. "] vs [" .. blueprint .. "]")
  check("and the name map itself carries no identity beside the anonymised key",
    tostring(smeared_board.names["hidden:jokers:1"]):find("Smeared", 1, true) == nil,
    tostring(smeared_board.names["hidden:jokers:1"]))

  do
    _G.G = { GAME = { dollars = 10, used_vouchers = {}, hands = {} }, playing_cards = {},
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      NEURO = { run_generation = 1, decision_serial = 1 } }
    local before = DD.capture()
    G.jokers.cards = { joker("j_smeared", "Smeared Joker", "") }
    local text = DD.render(before, DD.capture()) or ""
    check("a face-up joker gained is still named in the delta",
      text:find("jokers gained Smeared Joker", 1, true) ~= nil, text)
  end
end

done()
