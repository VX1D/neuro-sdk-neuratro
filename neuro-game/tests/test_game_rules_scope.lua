_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {}, modifiers = {}, dollars = 0 } }

local check, done = require("tests.helpers").harness("game-rules-scope")

local function fresh_game_rules()
  package.loaded["context.game_rules"] = nil
  return require("context.game_rules")
end

do
  local GameRules = fresh_game_rules()
  G.playing_cards = { { ability = { enhancement = "m_stone" } } }
  G.GAME.blind = nil
  local no_boss = GameRules.invariant_frame()
  check("FRAME: live Stone ownership is absent from immutable rules",
    no_boss:find("Stone always scores", 1, true) == nil)
  check("RUN: current Stone exception is present in ephemeral state",
    GameRules.run_frame_text():find("Stone", 1, true) ~= nil)

  G.GAME.blind = { key = "bl_final_leaf", in_blind = true, disabled = false }
  local verdant = GameRules.invariant_frame()
  check("FRAME: no present-tense exception ('right now') on the permanent rules block",
    verdant:find("right now", 1, true) == nil, verdant)
  check("FRAME: Verdant Leaf active does not change the timeless FRAME text",
    verdant == no_boss, "no_boss=" .. no_boss .. "\nverdant=" .. verdant)

  G.playing_cards = nil
  G.GAME.blind = nil
end

do
  local GameRules = fresh_game_rules()
  G.GAME.interest_cap = 50
  G.jokers = { cards = {
    { config = { center = { key = "j_splash" } }, ability = { name = "Splash" } },
  } }
  check("RUN_SETUP: dead-run economy and joker exceptions are withheld",
    GameRules.run_frame_text("RUN_SETUP") == nil,
    tostring(GameRules.run_frame_text("RUN_SETUP")))
  check("RUN: the same live values remain available inside the run",
    (GameRules.run_frame_text("SELECTING_HAND") or ""):find("max %+%$10/round") ~= nil)
  G.jokers = nil
  G.GAME.interest_cap = nil
end

do
  local GameRules = fresh_game_rules()
  G.GAME.round_resets = { ante = 1 }
  G.GAME.round = 1
  G.GAME.interest_amount = 1
  G.GAME.interest_cap = 25
  local base = GameRules.run_frame_text()
  check("RUN: base interest rule present",
    base:find("max %+%$5/round", 1, false) ~= nil, base)
  check("RUN: no scope stamp on the economy clause",
    base:find("[ante", 1, true) == nil, base)

  G.GAME.round_resets.ante = 3
  G.GAME.round = 9
  G.GAME.interest_cap = 50 -- Seed Money (game.lua:619, config.extra = 50)
  local seed_money = GameRules.run_frame_text()
  check("RUN: Seed Money cap reflected",
    seed_money:find("max %+%$10/round", 1, false) ~= nil, seed_money)
  check("RUN: no scope stamp on the Seed Money clause either",
    seed_money:find("[ante", 1, true) == nil, seed_money)

  check("RUN: base and Seed Money statements differ (the cap value itself, not a scope tag)",
    base ~= seed_money)

  G.GAME.round_resets = nil
  G.GAME.round = nil
  G.GAME.interest_amount = nil
  G.GAME.interest_cap = nil
end

do
  local GameRules = fresh_game_rules()
  G.GAME.interest_amount = 1
  G.GAME.interest_cap = 25
  local frame = GameRules.invariant_frame()
  check("FRAME: the moved sell and joker-landing rules are on the permanent channel",
    frame:find("Selling returns only the sell value shown", 1, true) ~= nil
      and frame:find("rightmost joker slot, with no joker to its right", 1, true) ~= nil, frame)
  check("FRAME: the hand-history caveat is stated once here, not per rendered history line",
    frame:find("may differ next time with other cards, Jokers, boss rules", 1, true) ~= nil, frame)
  check("FRAME: interest advice crosses as a condition, never as a claim that interest exists",
    frame:find("While interest is enabled", 1, true) ~= nil
      and frame:find("Held cash keeps earning that interest", 1, true) == nil, frame)
  check("FRAME: no money figure of any kind on the channel that cannot be retracted",
    frame:find("$", 1, true) == nil, frame)
  check("FRAME: the deck being played is never named on the permanent channel",
    frame:find("Your deck", 1, true) == nil, frame)
  check("FRAME: draw and hand-level rules leave room for explicit boss effects",
    frame:find("draw back up to hand size", 1, true) == nil
      and frame:find("never its level", 1, true) == nil
      and frame:find("explicit card, boss, or other effect", 1, true) ~= nil, frame)
  check("FRAME: Planet wording does not overload 'base' beside level-1 starting values",
    frame:find("base chips", 1, true) == nil and frame:find("starting chips", 1, true) ~= nil,
    frame)

  local run = GameRules.run_frame_text()
  check("RUN: the mutable interest figures stay on the ephemeral channel",
    run:find("max %+%$5/round") ~= nil, run)
  check("RUN: and it does not repeat what the frame already holds forever",
    run:find("Selling returns", 1, true) == nil
      and run:find("rightmost joker slot", 1, true) == nil
      and run:find("keeps earning", 1, true) == nil, run)

  G.STAGES = { MAIN_MENU = 1, RUN = 2 }
  G.STAGE = G.STAGES.RUN
  check("DECK: no reference is offered while no deck centre is resolvable",
    GameRules.deck_reference() == nil)
  G.P_CENTERS = { b_red = { key = "b_red", loc_txt = { name = "Red Deck" } } }
  G.GAME.selected_back = { key = "b_red" }
  G.STAGE = G.STAGES.MAIN_MENU
  check("DECK: a deck merely selected outside a run offers no retained reference",
    GameRules.deck_reference() == nil)
  G.STAGE = G.STAGES.RUN
  local sig, text = GameRules.deck_reference()
  check("DECK: the reference states the deck's rules, and its name keys on the deck",
    type(sig) == "string" and sig:find("b_red", 1, true) ~= nil
      and type(text) == "string" and text:find("Deck rules -- Red Deck", 1, true) ~= nil,
    tostring(sig) .. " | " .. tostring(text))
  check("DECK: the reference is a rule about that deck, not a claim about the current run",
    text:find("Your deck", 1, true) == nil and text:find("you are playing", 1, true) == nil, text)
  check("RUN: the ephemeral half still names the deck in play",
    GameRules.run_frame_text():find("Your deck: Red Deck.", 1, true) ~= nil,
    GameRules.run_frame_text())

  G.P_CENTERS = nil
  G.GAME.selected_back = nil
  G.GAME.interest_amount = nil
  G.GAME.interest_cap = nil
end

do
  local GameRules = fresh_game_rules()
  G.jokers = { cards = {} }
  local frame = GameRules.invariant_frame()

  check("FRAME: no 'sum all +Mult then apply every XMult' formula",
    frame:find("XMult sources in play order", 1, true) == nil
      and frame:find(") x (Base Mult", 1, true) == nil, frame)
  check("FRAME: per-scoring-card xMult is stated to apply BEFORE joker flat +Mult",
    frame:find("before any joker's flat +Mult", 1, true) ~= nil, frame)
  check("FRAME: an xMult is described as multiplying what has accumulated so far, not the total",
    frame:find("accumulated up to the moment it fires", 1, true) ~= nil
      and frame:find("not a separate stage applied to the finished total", 1, true) ~= nil, frame)
  check("FRAME: the played-card pass is stated to run before the held-card pass and the jokers",
    (function()
      local play = frame:find("scores your played cards first", 1, true)
      local held = frame:find("then the cards you still hold", 1, true)
      local jok = frame:find("only after all of that your jokers", 1, true)
      return play and held and jok and play < held and held < jok
    end)(), frame)

  local n = 0
  for _ in frame:gmatch("Score = ") do n = n + 1 end
  check("FRAME: the score relation is written exactly once", n == 1, tostring(n))

  local Vanilla = require("tests.fixtures.vanilla_jokers")
  G.jokers = { cards = { Vanilla.card("j_photograph", 1), Vanilla.card("j_joker", 2) },
    config = { card_limit = 5 } }
  local ordered = fresh_game_rules().invariant_frame()
  check("FRAME: the order reference fires for a Photograph + Joker board",
    ordered:find("your jokers fire left to right", 1, true) ~= nil, ordered)
  check("FRAME: and it excludes the per-scoring-card joker from the slot claim",
    ordered:find("has already fired by then and its slot does not", 1, true) ~= nil, ordered)
  G.jokers = { cards = {} }

  local NEEDLE = "your jokers fire left to right"
  local function frame_for(cards)
    G.jokers = { cards = cards, config = { card_limit = 5 } }
    local text = fresh_game_rules().invariant_frame()
    G.jokers = { cards = {} }
    return text
  end
  local ROSTERS = {
    ["no jokers at all"] = {},
    ["an xMult joker beside a hand-type-gated +Mult joker"] =
      { Vanilla.card("j_photograph", 1), Vanilla.card("j_jolly", 2) },
    ["a single joker that pays neither Mult nor xMult"] = { Vanilla.card("j_scary_face", 1) },
    ["two flat +Mult jokers and no multiplier"] =
      { Vanilla.card("j_jolly", 1), Vanilla.card("j_joker", 2) },
    ["a per-scoring-card +Mult joker on its own"] = { Vanilla.card("j_fibonacci", 1) },
  }
  local names = {}
  for name in pairs(ROSTERS) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local text = frame_for(ROSTERS[name])
    check("ORDER: the frame is built at all with " .. name,
      text:find("Order of operations:", 1, true) ~= nil, text)
    check("ORDER: the left-to-right rule ships with " .. name,
      text:find(NEEDLE, 1, true) ~= nil, text)
    local hits = 0
    for _ in text:gmatch(NEEDLE) do hits = hits + 1 end
    check("ORDER: and exactly once with " .. name, hits == 1, tostring(hits))
  end

  do
    local pipe = assert(io.popen("grep -rl '" .. NEEDLE .. "' context core facts force handlers hud render util 2>/dev/null | sort", "r"))
    local authors = {}
    for path in pipe:lines() do authors[#authors + 1] = path end
    pipe:close()
    check("ORDER: exactly one module authors the rule", #authors == 1, table.concat(authors, ", "))
    check("ORDER: and it is context/game_rules.lua", authors[1] == "context/game_rules.lua",
      tostring(authors[1]))
  end

  check("FRAME: vanilla multipliers rendered from config", frame:find("Glass x2 Mult", 1, true) ~= nil
    and frame:find("Polychrome x1.5 Mult", 1, true) ~= nil
    and frame:find("Steel x1.5 Mult", 1, true) ~= nil, frame)

  package.loaded["facts.card_util"] = nil
  G.P_CENTERS = {
    m_glass = { config = { Xmult = 7 } },
    e_polychrome = { config = { extra = 9 } },
    m_steel = { config = { h_x_mult = 11 } },
  }
  local modded = fresh_game_rules().invariant_frame()
  check("FRAME: a modded Glass/Polychrome/Steel multiplier moves the prose with it",
    modded:find("Glass x7 Mult", 1, true) ~= nil
      and modded:find("Polychrome x9 Mult", 1, true) ~= nil
      and modded:find("Steel x11 Mult", 1, true) ~= nil, modded)
  G.P_CENTERS = nil
  package.loaded["facts.card_util"] = nil
end

do
  local GameRules = fresh_game_rules()
  G.jokers = { cards = {} }
  local NEEDLE = "pays once per card that scores"
  local frame = GameRules.invariant_frame()
  check("CAP: the per-scoring-card ceiling rule is on the permanent frame",
    frame:find(NEEDLE, 1, true) ~= nil, frame)
  local n = 0
  for _ in frame:gmatch(NEEDLE) do n = n + 1 end
  check("CAP: and it is written exactly once", n == 1, tostring(n))
  local sentence = frame:match("A joker paying per scoring card[^.]*%.")
  check("CAP: the rule carries no cap size, which change_play_limit can move mid-run",
    sentence ~= nil and sentence:find("%d") == nil, tostring(sentence))
  local pipe = assert(io.popen(
    "grep -rl 'scoring hand holds at most' context core facts force handlers hud render util 2>/dev/null | sort", "r"))
  local authors = {}
  for path in pipe:lines() do authors[#authors + 1] = path end
  pipe:close()
  check("CAP: and no module restates it on a per-force slot", #authors == 0, table.concat(authors, ", "))
  G.jokers = nil
end

done()
