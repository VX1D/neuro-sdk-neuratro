_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("boss-mechanics")

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local function card(v, suit, sort_id, debuff)
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit },
    sort_id = sort_id,
    debuff = debuff or nil,
    config = { center = { key = "c_base", set = "Default" } },
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end
local function junk()
  return { card("3","Spades"), card("7","Clubs"), card("9","Hearts"), card("2","Diamonds"), card("5","Spades"), card("8","Clubs") }
end
local function with_front(a, b)
  local h = { a, b }
  for _, c in ipairs(junk()) do h[#h + 1] = c end
  return h
end
local function setup(cards, opts)
  opts = opts or {}
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = {
    current_round = { discards_left = opts.discards or 3, hands_left = opts.hands or 4,
      most_played_poker_hand = opts.most_played },
    hands = opts.levels or {},
    blind = opts.blind or {},
  }
  G.FUNCS = { get_poker_hand_info = opts.phi }
end

_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {}, NEURO = {} }

local CtxHand = require("context.ctx_hand")
local DebuffFacts = require("facts.debuff_facts")
local HF = require("facts.hand_facts")
local BossModel = require("facts.boss.model")
local BossRender = require("facts.boss.render")
local CardUtil = require("facts.card_util")
local PlanGate = require("core.plan_gate")
local Scoring = require("util.scoring")
local CtxHelpers = require("context.ctx_helpers")
local BoardHandlers = require("handlers.board_handlers")

do
  local small_big_play = card("K", "Hearts", 101)
  small_big_play.debuff = true
  small_big_play.ability = { played_this_ante = true }
  local never_played = card("Q", "Spades", 102)
  local pillar_round_play = card("K", "Diamonds", 103)
  pillar_round_play.ability = { played_this_ante = true }
  G.GAME = { current_round = {},
    blind = { name = "The Pillar", debuff = {}, config = { blind = { key = "bl_pillar" } } } }

  local hand = { small_big_play, never_played, pillar_round_play }
  local marks = {}
  for i, c in ipairs(hand) do
    marks[i] = CtxHand.card_token(c, true, false):find("+USED", 1, true) ~= nil
  end
  local engine = {}
  for i, c in ipairs(hand) do engine[i] = not not c.debuff end
  check("+USED marks set-equal the engine's card.debuff set under The Pillar",
    marks[1] == engine[1] and marks[2] == engine[2] and marks[3] == engine[3],
    table.concat({ tostring(marks[1]), tostring(marks[2]), tostring(marks[3]) }, "/"))
  check("a card played during the Pillar round itself (not debuffed by the engine) carries no +USED",
    marks[3] == false, CtxHand.card_token(pillar_round_play, true, false))
  check("+USED suppressed when include_debuff is false",
    CtxHand.card_token(small_big_play, false, false) == "KH",
    CtxHand.card_token(small_big_play, false, false))

  local idx, n = DebuffFacts.pillar_used_indices(hand)
  check("pillar_used_indices flags exactly the engine-debuffed played_this_ante card",
    idx[1] == true and idx[2] == nil and idx[3] == nil,
    tostring(idx[1]) .. "/" .. tostring(idx[2]) .. "/" .. tostring(idx[3]))
  check("pillar_used_count counts exactly one", n == 1, n)

  G.GAME.blind = { name = "The Flint", debuff = {}, config = { blind = { key = "bl_flint" } } }
  check("pillar_used_count is 0 outside The Pillar even for played_this_ante+debuff cards",
    DebuffFacts._test.pillar_used_count(hand) == 0)
  check("+USED is not emitted outside The Pillar (the +DB mark still is)",
    CtxHand.card_token(small_big_play, true, false) == "KH+DB",
    CtxHand.card_token(small_big_play, true, false))

  check("no module writes a boss shadow set: G.NEURO.pillar_ante_ids is never populated",
    (G.NEURO or {}).pillar_ante_ids == nil, tostring((G.NEURO or {}).pillar_ante_ids))
end

do
  local kh, kd = card("K", "Hearts"), card("K", "Diamonds")
  setup(with_front(kh, kd), {
    blind = { name = "The Tooth", debuff = {}, in_blind = true, config = { blind = { key = "bl_tooth" } } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  check("tooth_active reads the live boss blind", DebuffFacts.tooth_active() == true)
  local s = HF.summary()
  check("Tooth: Ready Pair carries a -$2 cost matching the 2 cards it plays",
    s:find("Pair%[1,2%][^;%.]*%(%-%$2%)") ~= nil, s)
end

do
  local kh, kd = card("K", "Hearts"), card("K", "Diamonds")
  setup(with_front(kh, kd), {
    blind = { name = "The Ox", debuff = {}, in_blind = true, config = { blind = { key = "bl_ox" } } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  check("tooth_active is false outside The Tooth", DebuffFacts.tooth_active() == false)
  local s = HF.summary()
  check("the Ready Pair row a Tooth cost would ride on is present",
    s:find("Ready: Pair[1,2]", 1, true) ~= nil, s)
  check("Ready Pair carries no -$ cost outside The Tooth", s:find("%(%-%$", 1) == nil, s)
end

do
  local kh, kd, ks = card("K", "Hearts"), card("K", "Diamonds"), card("K", "Spades")
  local hand = { kh, kd, ks }
  for _, c in ipairs(junk()) do hand[#hand + 1] = c end
  setup(hand, {
    blind = { name = "The Ox", debuff = {}, in_blind = true, config = { blind = { key = "bl_ox" } } },
    most_played = "Pair",
    phi = function()
      return nil, nil, { Pair = { { kh, kd } }, ["Three of a Kind"] = { { kh, kd, ks } } }
    end,
  })
  check("ox_active reads the live boss blind", DebuffFacts.ox_active() == true)
  check("most_played_hand reads current_round.most_played_poker_hand", DebuffFacts.most_played_hand() == "Pair")
  local s = HF.summary()
  local pair_entry = s:match("Pair%[1,2%][^;%.]*")
  local trips_entry = s:match("Three of a Kind%[[%d,]+%][^;%.]*")
  check("Ox: the most-played Pair entry carries the zeroes-$ warning",
    pair_entry ~= nil and pair_entry:find("OX: zeroes $ if played", 1, true) ~= nil, pair_entry)
  check("Ox: the non-most-played Three of a Kind entry carries no warning",
    trips_entry ~= nil and trips_entry:find("OX", 1, true) == nil, trips_entry)
end

do
  local GENERIC = {
    { key = "bl_club", name = "The Club", debuff = { suit = "Clubs" } },
    { key = "bl_head", name = "The Head", debuff = { suit = "Hearts" } },
    { key = "bl_goad", name = "The Goad", debuff = { suit = "Spades" } },
    { key = "bl_window", name = "The Window", debuff = { suit = "Diamonds" } },
    { key = "bl_plant", name = "The Plant", debuff = { is_face = "face" } },
  }
  for _, g in ipairs(GENERIC) do
    local blind = { name = g.name, debuff = g.debuff, config = { blind = { key = g.key } } }
    local line = BossRender.boss_line("status", g.key, blind)
    check("status renderer names " .. g.name, line ~= nil and line:find(g.name, 1, true) ~= nil, line)
    check("status renderer states the +DB mark for " .. g.name,
      line ~= nil and line:find("+DB", 1, true) ~= nil, line)
  end
end

do
  local kh, kd = card("K", "Hearts", nil, true), card("K", "Diamonds")
  setup(with_front(kh, kd), {
    blind = { name = "The Club", debuff = { suit = "Clubs" } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  local s = HF.summary()
  check("partially debuffed Ready Pair shows (1 debuffed~0)",
    s:find("Pair%[1,2%][^;%.]*%(1 debuffed~0%)") ~= nil, s)
end

do
  local kh, kd = card("K", "Hearts", nil, true), card("K", "Diamonds", nil, true)
  setup(with_front(kh, kd), {
    blind = { name = "The Club", debuff = { suit = "Clubs" } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  local s = HF.summary()
  check("a Pair made entirely of debuffed cards stays in Ready, annotated (all debuffed~0)",
    s:find("Pair%[1,2%][^;%.]*%(all debuffed~0%)") ~= nil, s)
  check("the debuffed-card count still surfaces at the Structure level",
    s:find("2 card%(s%) DEBUFFED", 1) ~= nil, s)
end

do
  setup(junk(), { discards = 0, blind = { name = "The Water", debuff = {} } })
  local hl = CtxHand.hand_limits_section()
  check("Water: 0 discards left reports Can discard: no", hl ~= nil and hl:find("Can discard: no", 1, true) ~= nil, hl)
  setup(junk(), { discards = 2, blind = { name = "The Water", debuff = {} } })
  local hl2 = CtxHand.hand_limits_section()
  check("a boss with discards left reports Can discard: yes", hl2 ~= nil and hl2:find("Can discard: yes", 1, true) ~= nil, hl2)
end

do
  G.jokers = { cards = {
    { ability = { set = "Joker", mult = 10 },
      config = { center = { key = "j_a", set = "Joker" } }, debuff = true },
    { ability = { set = "Joker", mult = 4 },
      config = { center = { key = "j_b", set = "Joker" } } },
  } }
  local s = Scoring.joker_summary()
  check("Crimson Heart: the hand's randomly-disabled joker is excluded from the guaranteed total",
    s ~= nil and s.mult == 4, s and tostring(s.mult))
  check("Crimson Heart: a disabled joker is tagged DEBUFFED(inactive) in its own row",
    CtxHelpers.joker_tags({ debuff = true }) == "DEBUFFED(inactive)", CtxHelpers.joker_tags({ debuff = true }))
  check("an active joker carries the empty-flag marker, not a DEBUFFED tag",
    CtxHelpers.joker_tags({}) == "-", CtxHelpers.joker_tags({}))
end

do
  G.jokers = { cards = {
    { facing = "back", config = { center = { key = "j_a", set = "Joker" } } },
    { facing = "back", config = { center = { key = "j_b", set = "Joker" } } },
    { facing = "back", config = { center = { key = "j_c", set = "Joker" } } },
  } }
  local exec, err = BoardHandlers.handle_set_joker_order({ from_index = 1, to_index = 3 })
  check("Amber Acorn: set_joker_order accepts face-down jokers", type(exec) == "function", err)
  if type(exec) == "function" then
    exec()
    check("Amber Acorn: reordering a face-down joker actually moves it",
      G.jokers.cards[3].config.center.key == "j_a", G.jokers.cards[3].config.center.key)
  end
end

do
  local function serpent_status()
    return BossRender.render("status", "bl_serpent") or ""
  end
  G.deck = { cards = {} }
  for i = 1, 5 do G.deck.cards[i] = {} end
  check("Serpent status draws min(deck,3) with a 5-card deck: draws 3",
    serpent_status():find("the next such draw is 3 card(s)", 1, true) ~= nil, serpent_status())
  check("Serpent status reports the true deck size (5) even though only 3 are drawn",
    serpent_status():find("The deck has 5 card(s) left", 1, true) ~= nil, serpent_status())
  check("Serpent prose says the three-card draw bypasses the hand-size cap",
    serpent_status():find("ignoring your hand-size cap", 1, true) ~= nil, serpent_status())
  check("Serpent prose keeps the opening draw normal",
    serpent_status():find("opening draw of the round is a normal full draw", 1, true) ~= nil,
    serpent_status())

  G.deck.cards = { {} }
  check("Serpent status draws min(deck,3) with a 1-card deck: draws 1",
    serpent_status():find("the next such draw is 1 card(s)", 1, true) ~= nil, serpent_status())

  G.deck.cards = {}
  check("Serpent status draws 0 with an empty deck",
    serpent_status():find("the next such draw is 0 card(s)", 1, true) ~= nil, serpent_status())
end

do
  G.deck = { cards = { {}, {}, {}, {}, {} } }
  G.GAME = { blind = { name = "The Serpent", debuff = {}, config = { blind = { key = "bl_serpent" } } } }
  local note = require("context.ctx_blind").blind_debuff_line()
  check("the live FACT line dispatches to Serpent's status renderer",
    note ~= nil and note:find("the next such draw is 3 card(s)", 1, true) ~= nil, note)
end

do
  G.hand = { config = { card_limit = 7 } }
  check("hand_limit passes through a Manacle-reduced card_limit", CardUtil.hand_limit() == 7)
  G.hand = { config = { card_limit = 8 } }
  check("hand_limit reads a normal 8-card limit", CardUtil.hand_limit() == 8)
  G.hand = { config = {} }
  check("hand_limit defaults to 8 when card_limit is unset", CardUtil.hand_limit() == 8)
end

do
  local c1, m1 = DebuffFacts.flint_halve(100, 10)
  check("flint_halve halves 100 chips to 50", c1 == 50, c1)
  check("flint_halve halves 10 mult to 5", m1 == 5, m1)

  local c2, m2 = DebuffFacts.flint_halve(5, 0)
  check("flint_halve halves 5 chips to 3 (floor(2.5+0.5))", c2 == 3, c2)
  check("flint_halve floors a halved-to-0 mult up to 1, never 0", m2 == 1, m2)

  local c3, m3 = DebuffFacts.flint_halve(0, 0)
  check("flint_halve floors chips at 0", c3 == 0, c3)
  check("flint_halve floors mult at 1 even from a zero base", m3 == 1, m3)
end

do
  local CtxEconomy = require("facts.economy_facts")
  _G.get_blind_amount = function() return 1000 end
  _G.G = {
    P_BLINDS = { bl_wall = { mult = 4 }, bl_hook = { mult = 2 } },
    GAME = { round_resets = { ante = 1 }, starting_params = { ante_scaling = 1 } },
  }
  local tw = CtxEconomy.calc_blind_target("bl_wall")
  local th = CtxEconomy.calc_blind_target("bl_hook")
  check("calc_blind_target computed a Hook target", th == 2000, th)
  check("calc_blind_target computed a Wall target double a mult-2 boss", tw == 4000, tw)
  check("Wall's target really is hook_target * (wall_mult/hook_mult)",
    tw == th * (4 / 2), tostring(tw) .. " vs " .. tostring(th * (4 / 2)))
  _G.get_blind_amount = nil
end

do
  local CtxEconomy = require("facts.economy_facts")
  _G.get_blind_amount = function() return 1000 end
  _G.G = {
    P_BLINDS = { bl_hook = { mult = 2 }, bl_needle = { mult = 1 } },
    GAME = { round_resets = { ante = 1 }, starting_params = { ante_scaling = 1 } },
  }
  local th = CtxEconomy.calc_blind_target("bl_hook")
  local tn = CtxEconomy.calc_blind_target("bl_needle")
  check("Needle's target is half a normal (mult-2) boss",
    tn == th / 2, tostring(tn) .. " vs " .. tostring(th / 2))
  _G.get_blind_amount = nil
end

do
  local CtxEconomy = require("facts.economy_facts")
  _G.get_blind_amount = function() return 1000 end
  _G.G = {
    P_BLINDS = { bl_hook = { mult = 2 }, bl_final_vessel = { mult = 6 } },
    GAME = { round_resets = { ante = 1 }, starting_params = { ante_scaling = 1 } },
  }
  local th = CtxEconomy.calc_blind_target("bl_hook")
  local tv = CtxEconomy.calc_blind_target("bl_final_vessel")
  check("Violet Vessel's target is 3x a normal (mult-2) boss",
    tv == th * 3, tostring(tv) .. " vs " .. tostring(th * 3))
  _G.get_blind_amount = nil
end

do
  local ForceSelectingHand = require("force.force_selecting_hand")
  local ASK_TEXT = "You did not set a boss plan when you chose this blind. State the rule this boss imposes on you in plan.boss_plan with your next play_hand or discard_hand. "

  local function note(blind_boss, key, name, plan)
    _G.G = {
      GAME = { blind = { boss = blind_boss, name = name, config = { blind = { key = key } } } },
      NEURO = { plan = plan },
    }
    return ForceSelectingHand.boss_state_note()
  end

  check("boss round without a current boss_plan is exactly the request sentence, nothing else",
    note(true, "bl_flint", "The Flint") == ASK_TEXT, note(true, "bl_flint", "The Flint"))

  check("non-boss blind is exactly empty",
    note(false, "bl_small", "Small Blind") == "", note(false, "bl_small", "Small Blind"))

  local current_plan = { boss = "Grind pairs.", boss_scope = "0|bl_flint" }
  check("boss round with a current boss_plan is exactly empty (no re-ask, no other text)",
    note(true, "bl_flint", "The Flint", current_plan) == "", note(true, "bl_flint", "The Flint", current_plan))
end

do
  local ForceSelectingHand = require("force.force_selecting_hand")
  local function boss_state(key, name)
    setup(junk(), {
      discards = 3, hands = 4,
      blind = { chips = 1000, boss = true, name = name, debuff = {}, config = { blind = { key = key } } },
      phi = function() return nil, nil, {} end,
    })
    G.GAME.chips = 0
    G.STATES = { BLIND_SELECT = 1, SELECTING_HAND = 2 }
    G.STATE = G.STATES.SELECTING_HAND
    G.NEURO = { once_serials = {}, state_enter_serial = 1 }
  end

  boss_state("bl_flint", "The Flint")
  G.NEURO.plan = { boss = "Grind Pairs, hold discards for the back half.", boss_scope = PlanGate.current_boss_scope() }
  local f1 = ForceSelectingHand.build()
  check("a current boss plan satisfies the gate and is echoed back",
    f1 and f1.query and f1.query:find("Your boss-round plan:", 1, true) ~= nil,
    f1 and f1.query)

  boss_state("bl_flint", "The Flint")
  local f2 = ForceSelectingHand.build()
  check("no-plan boss force really was built",
    f2 and f2.query and f2.query:find("State: SELECTING_HAND.", 1, true) ~= nil, f2 and f2.query)
  check("boss plan echo is absent with no plan set",
    f2 and f2.query and f2.query:find("Your boss-round plan:", 1, true) == nil, f2 and f2.query)

  boss_state("bl_manacle", "The Manacle")
  G.NEURO.plan = { boss = "Grind Pairs against The Flint.", boss_scope = "0|bl_flint" }
  local f3 = ForceSelectingHand.build()
  check("changed-boss force really was built",
    f3 and f3.query and f3.query:find("State: SELECTING_HAND.", 1, true) ~= nil, f3 and f3.query)
  check("boss plan echo stays absent once the boss round changes",
    f3 and f3.query and f3.query:find("Your boss-round plan:", 1, true) == nil, f3 and f3.query)

  local function decision_query(cards, phi)
    setup(cards, {
      discards = 3, hands = 4,
      blind = { chips = 1000, boss = false, name = "Small Blind", debuff = {} },
      phi = phi,
    })
    G.GAME.chips = 0
    G.STATES = { BLIND_SELECT = 1, SELECTING_HAND = 2 }
    G.STATE = G.STATES.SELECTING_HAND
    G.NEURO = { once_serials = {}, state_enter_serial = 1 }
    return ForceSelectingHand.build()
  end

  local fh = { card("K", "Hearts"), card("K", "Spades"), card("K", "Clubs"),
    card("Q", "Hearts"), card("Q", "Diamonds"), card("4", "Clubs") }
  local ready_force = decision_query(fh, function()
    return nil, nil, {
      ["Full House"] = { { fh[1], fh[2], fh[3], fh[4], fh[5] } },
      ["Three of a Kind"] = { { fh[1], fh[2], fh[3] } },
      Pair = { { fh[4], fh[5] } },
    }
  end)
  local rq = ready_force and ready_force.query or ""
  local ready_at, cue_at = rq:find("Ready to play now:", 1, true), rq:find("You still need", 1, true)
  check("multi-Ready query is built (disclaimer test is meaningful)", ready_at ~= nil, rq)
  check("multi-Ready query does not add a ranking disclaimer",
    rq:find("Two or more hands are Ready", 1, true) == nil, rq)
  check("decision pressure precedes the multi-Ready candidate list",
    cue_at ~= nil and ready_at ~= nil and cue_at < ready_at, rq)

  local near = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Hearts"),
    card("5", "Hearts"), card("9", "Clubs") }
  local close_force = decision_query(near, function() return nil, nil, {} end)
  local cq = close_force and close_force.query or ""
  local close = cq:match("One card away: (.-)%. ") or cq:match("One card away: (.-)%.") or ""
  check("multi-Close query is built (disclaimer test is meaningful)", close:find("; ", 1, true) ~= nil, cq)
  check("multi-Close query does not add a ranking disclaimer",
    cq:find("Two or more hands are listed as Close", 1, true) == nil, cq)
end

done()
