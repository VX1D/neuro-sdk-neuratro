require("tests.stubs").setup({ love = "lazy", G = "hand" })

local HF = require("facts.hand_facts")
local CR = require("context.context_readable")
local function prose() return require("tests.helpers").index_only(CR.structure_prose(HF.structure())) end

local check, done = require("tests.helpers").harness("hand-facts")

local VALN = require("tests.helpers").VALN
local function card(v, suit, debuff)
  return require("tests.engine_cards").playing(VALN[v] or v, suit, { debuff = debuff or nil })
end

local function setup(cards, opts)
  opts = opts or {}
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = {
    current_round = { discards_left = opts.discards or 3, hands_left = opts.hands or 4 },
    hands = opts.levels or {},
    blind = opts.blind or {},
  }
  G.FUNCS = { get_poker_hand_info = opts.phi }
end

local function junk()
  return { card("3","Spades"), card("7","Clubs"), card("9","Hearts"), card("2","Diamonds"), card("5","Spades"), card("8","Clubs") }
end
local function with_front(a, b) local h = { a, b }; for _, c in ipairs(junk()) do h[#h+1] = c end; return h end

do
  local kh, kd = card("K","Hearts"), card("K","Diamonds")
  setup(with_front(kh, kd), {
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  local s = prose()
  check("size-floor: Ready Pair flagged play 5+",
    s:find("Pair (cards 1, 2) (this boss needs 5+ cards played - add spare cards)", 1, true) ~= nil, s)
end

do
  local Metrics = require("util.metrics")
  local kh, kd = card("K","Hearts"), card("K","Diamonds")

  local function ready_line(debuff_hand)
    setup(with_front(kh, kd), {
      blind = { name = "The Psychic", debuff = { h_size_ge = 5 }, debuff_hand = debuff_hand },
      phi = function() return "Pair", nil, { Pair = { { kh, kd } } } end,
    })
    return prose()
  end

  local working = ready_line(function() return true end)
  check("boss probe: a working debuff_hand marks the Ready entry as zeroed",
    working:find("Pair %(cards 1, 2%)[^\n]* %-%- zeroed by The Psychic") ~= nil, working:match("Ready[^\n]*"))

  Metrics._counters["boss_debuff_probe_failed"] = nil
  local thrown = ready_line(function() error("engine exploded") end)
  check("boss probe: a THROWN debuff_hand never presents the hand as clean",
    thrown:find("Pair %(cards 1, 2%)[^\n]* %-%- ") ~= nil, thrown:match("Ready[^\n]*"))
  check("boss probe: the swallowed failure is named in the metrics",
    (Metrics._counters["boss_debuff_probe_failed"] or 0) > 0,
    tostring(Metrics._counters["boss_debuff_probe_failed"]))

  local DF = require("facts.debuff_facts")
  setup(with_front(kh, kd), {
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 }, debuff_hand = function() error("boom") end },
    phi = function() return "Pair", nil, { Pair = { { kh, kd } } } end,
  })
  local blocked, certain = DF.boss_would_debuff({ kh, kd }, "Pair")
  check("boss probe: a thrown probe answers 'not certain', not a confident false",
    blocked == false and certain == false, tostring(blocked) .. "/" .. tostring(certain))

  setup(with_front(kh, kd), {
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 }, debuff_hand = function() return false end },
    phi = function() return "Pair", nil, { Pair = { { kh, kd } } } end,
  })
  local ok_blocked, ok_certain = DF.boss_would_debuff({ kh, kd }, "Pair")
  check("boss probe: a working probe still answers with certainty",
    ok_blocked == false and ok_certain == true, tostring(ok_blocked) .. "/" .. tostring(ok_certain))
end

do
  local kh, kd = card("K","Hearts"), card("K","Diamonds")
  setup(with_front(kh, kd), { blind = { name = "The Psychic", debuff = { h_size_ge = 5 } } })
  local s = prose()
  check("size-floor: near Three of a Kind flagged play 5+",
    s:find("Three of a Kind keep cards 1, 2, the others are [%d, ]+ %(you may discard at most %d+ of them%) "
      .. "%(this boss needs 5%+ cards played %- add spare cards%)") ~= nil, s)
end

do
  local kh, kd = card("K","Hearts", true), card("K","Diamonds")
  setup(with_front(kh, kd), { blind = {} })
  local s = prose()
  check("near-rank partial debuff annotated",
    s:find("Three of a Kind keep cards 1, 2, the others are [%d, ]+ %(you may discard at most %d+ of them%) "
      .. "%(1 card debuffed, adding nothing%)") ~= nil, s)
end

do
  local kh, kd = card("K","Hearts", true), card("K","Diamonds", true)
  setup(with_front(kh, kd), { blind = {} })
  local s = prose()
  check("near-rank all-debuffed suppressed", s:find("Three of a Kind") == nil, s)
end

do
  local hand = {
    card("2","Hearts"), card("5","Hearts", true), card("8","Hearts"), card("K","Hearts"),
    card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("near-flush partial debuff annotated",
    s:find("Flush: 4 Hearts keep cards 1, 2, 3, 4, the others are [%d, ]+ %(1 card debuffed, adding nothing%)") ~= nil, s)
end

do
  local hand = {
    card("5","Hearts"), card("6","Diamonds"), card("7","Spades"), card("8","Clubs"),
    card("J","Hearts"), card("Q","Diamonds"), card("K","Spades"), card("2","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("open straight labeled", s:find("Straight keep cards .-%(completes on either end%)") ~= nil, s)
  check("open straight not called inside", s:find("needs one exact rank", 1, true) == nil, s)
end

do
  local hand = {
    card("5","Hearts"), card("6","Diamonds"), card("8","Spades"), card("9","Clubs"),
    card("Q","Hearts"), card("K","Diamonds"), card("2","Spades"), card("3","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("inside straight labeled", s:find("Straight keep cards .-%(needs one exact rank%)") ~= nil, s)
end

do
  local hand = {
    card("A","Hearts"), card("2","Diamonds"), card("3","Spades"), card("4","Clubs"),
    card("6","Hearts"), card("8","Spades"), card("10","Clubs"), card("Q","Diamonds"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("A-2-3-4 is an inside draw", s:find("Straight keep cards .-%(needs one exact rank%)") ~= nil
    and s:find("completes on either end", 1, true) == nil, s)
end
do
  local hand = {
    card("J","Hearts"), card("Q","Diamonds"), card("K","Spades"), card("A","Clubs"),
    card("3","Hearts"), card("5","Spades"), card("7","Clubs"), card("9","Diamonds"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("J-Q-K-A is an inside draw", s:find("Straight keep cards .-%(needs one exact rank%)") ~= nil
    and s:find("completes on either end", 1, true) == nil, s)
end

do
  require("tests.engine_cards").install_smods({ four_fingers = function(kind) return 4 end })
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Diamonds"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("Four Fingers: 3-of-a-suit is a near-flush", s:find("Flush: 3 Hearts") ~= nil, s)
  require("tests.engine_cards").install_smods()
end

do
  local stone = require("tests.engine_cards").enhance(card("2","Hearts"), "m_stone")
  local hand = {
    stone, card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("Stone excluded from suit count", s:find("most cards of one suit 3;", 1, true) ~= nil
    and s:find("Flush: %d") == nil, s)
end

do
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
    card("4","Spades"), card("4","Diamonds"), card("6","Clubs"), card("7","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = prose()
  check("full straight not mislabeled near", (s:match("One card away: [^\n]*") or ""):find("Straight", 1, true) == nil, s)
end

do
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Diamonds"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  G.jokers = { cards = { { config = { center = { key = "j_smeared" } } } } }
  local s = prose()
  check("Smeared near-flush labeled by color", s:find("Flush: 4 red keep cards 1, 2, 3, 4", 1, true) ~= nil, s)
  check("Smeared near-flush not labeled by suit", s:find("Flush: 4 Hearts") == nil, s)
  G.jokers = nil
end

do
  G.hand = { cards = {}, config = {} }
  G.GAME = { selected_back = { key = "b_plasma", effect = { center = { key = "b_plasma" } } },
    current_round = {}, hands = {}, blind = {} }
  local n = table.concat(HF.level_notes(), "; ")
  check("Plasma level note present", n:find("Plasma") ~= nil and n:find("balances") ~= nil, n)
  G.GAME.selected_back = { key = "b_red", effect = { center = { key = "b_red" } } }
  check("non-Plasma deck: no plasma note", table.concat(HF.level_notes(), "; "):find("Plasma") == nil, "")
end

do
  local CtxBlind = require("context.ctx_blind")
  local function line(blind) G.GAME = { current_round = {}, hands = {}, blind = blind }; return CtxBlind.blind_debuff_line() end
  check("FACT line: suit boss names the suit (dynamic)",
    (line({ name = "The Head", debuff = { suit = "Hearts" } }) or ""):find("Hearts", 1, true) ~= nil)
  check("FACT line: face boss mentions face cards",
    (line({ name = "The Plant", debuff = { is_face = "face" } }) or ""):find("face cards", 1, true) ~= nil)
  check("FACT line: Hook states the 2-random-cards fact",
    (line({ key = "bl_hook", debuff = {} }) or ""):find("2 random", 1, true) ~= nil)
  check("FACT line: Water by name fallback",
    (line({ name = "The Water", debuff = {} }) or ""):find("discards to 0", 1, true) ~= nil)
  check("FACT line: Needle single hand",
    (line({ key = "bl_needle", debuff = {} }) or ""):find("hands for the round to 1", 1, true) ~= nil)
  check("FACT line: Needle states its smaller target",
    (line({ key = "bl_needle", debuff = {} }) or ""):find("half a normal boss", 1, true) ~= nil,
    line({ key = "bl_needle", debuff = {} }))
  check("FACT line: Wall states its larger target",
    (line({ key = "bl_wall", debuff = {} }) or ""):find("double", 1, true) ~= nil)
  check("FACT line: Violet Vessel states its larger target",
    (line({ key = "bl_final_vessel", debuff = {} }) or ""):find("3x", 1, true) ~= nil)
  for _, k in ipairs({ "bl_hook", "bl_ox", "bl_mouth" }) do
    local a = line({ key = k, debuff = {}, hands = {} }) or ""
    check("FACT line: " .. k .. " makes no target-size claim",
      not a:find("half a normal boss", 1, true) and not a:find("3x a normal boss", 1, true)
        and not a:find("roughly double", 1, true), a)
  end
  check("FACT line: nil for a plain blind", line({ name = "Small Blind", debuff = {} }) == nil)
  check("FACT line: nil when blind disabled", line({ key = "bl_hook", debuff = {}, disabled = true }) == nil)
end

do
  local HH = require("handlers.hand_handlers")
  local saved_hand, saved_funcs, saved_game = G.hand, G.FUNCS, G.GAME
  local cards = { card("K", "Hearts"), card("K", "Spades") }
  local blind = { key = "bl_mouth", name = "The Mouth", debuff = {}, only_hand = "Flush",
    triggered = false,
    debuff_hand = function(self) self.triggered = true; return true end }
  G.GAME = { current_round = { hands_left = 3, discards_left = 2 }, hands = {}, blind = blind }
  G.hand = { cards = cards, config = { highlighted_limit = 5 }, highlighted = {} }
  G.FUNCS = { get_poker_hand_info = function() return "Pair", nil, { Pair = { cards } } end }
  pcall(HH.play_review_reason, cards)
  check("play preflight leaves blind.triggered untouched", blind.triggered == false,
    tostring(blind.triggered))
  G.hand, G.FUNCS, G.GAME = saved_hand, saved_funcs, saved_game
end

do
  local h = { card("2","Hearts"), card("3","Clubs"), card("4","Spades"), card("5","Diamonds"),
              card("9","Hearts"), card("J","Clubs"), card("Q","Spades"), card("K","Hearts") }
  setup(h, { discards = 2 })
  G.deck = { cards = {
    card("A","Hearts"), card("A","Spades"), card("6","Clubs"), card("6","Diamonds"),
    card("8","Hearts"), card("8","Clubs"), card("8","Spades"), card("8","Diamonds") } }
  local s = prose()
  check("open-ended straight counts BOTH ends as outs",
    s:find("Straight keep cards 1, 2, 3, 4.-%(4 of the 8 draw%-pile cards complete it;") ~= nil,
    s:match("One card away:[^\n]*") or s)
  check("open-ended straight still labelled open", s:find("(completes on either end)", 1, true) ~= nil, s)
end

do
  local h = { card("2","Hearts"), card("3","Clubs"), card("4","Spades"), card("5","Diamonds"),
              card("9","Hearts"), card("J","Clubs"), card("Q","Spades"), card("K","Hearts") }
  setup(h, { discards = 2 })
  G.deck = { cards = { card("A","Hearts"), card("8","Clubs") } }
  local s = prose()
  check("a drawn Ace counts as an out for 2-3-4-5",
    s:find("Straight keep cards 1, 2, 3, 4.-%(1 of the 2 draw%-pile cards complete it;") ~= nil,
    s:match("One card away:[^\n]*") or s)
end

do
  local h = { card("5","Hearts"), card("6","Diamonds"), card("8","Spades"), card("9","Clubs"),
              card("Q","Hearts"), card("K","Diamonds"), card("2","Spades"), card("3","Clubs") }
  setup(h, { discards = 2 })
  G.deck = { cards = { card("7","Hearts"), card("7","Clubs"), card("4","Clubs") } }
  local s = prose()
  check("double gutshot is labelled inside, not open", s:find("(needs one exact rank)", 1, true) ~= nil,
    s:match("One card away:[^\n]*") or s)
  check("double gutshot chooses the window with more live outs and counts only its gap",
    s:find("keep cards 1, 2, 3, 4.-%(2 of the 3 draw%-pile cards complete it;") ~= nil,
    s:match("One card away:[^\n]*") or s)
  G.deck = nil
end

do
  local h = { card("K","Hearts"), card("K","Spades"), card("2","Clubs"), card("7","Diamonds"),
              card("9","Hearts"), card("3","Spades"), card("4","Clubs"), card("5","Diamonds") }
  setup(h, { discards = 2, deck = { cards = { card("K","Clubs"), card("8","Hearts") } } })
  local s = prose()
  local six = s:match("the others are ([%d, ]+) %(you may discard at most (%d+) of them%)")
  check("oversized other list carries the discard cap", six ~= nil, s:match("One card away:[^\n]*") or s)
  local h2 = { card("K","Hearts"), card("K","Spades"), card("2","Clubs"), card("7","Diamonds") }
  setup(h2, { discards = 2, deck = { cards = { card("K","Clubs"), card("8","Hearts") } } })
  local s2 = prose()
  check("short other list has no cap note", s2:find("discard at most", 1, true) == nil,
    s2:match("One card away:[^\n]*") or s2)
end

do
  local Model = require("facts.boss.model")
  local Render = require("facts.boss.render")
  local saved = G.GAME
  local CFG = {
    bl_ox = {}, bl_eye = {}, bl_mouth = {}, bl_pillar = {}, bl_flint = {}, bl_serpent = {},
    bl_arm = {}, bl_final_leaf = {}, bl_final_bell = {}, bl_house = {}, bl_wheel = {}, bl_fish = {},
    bl_mark = {}, bl_hook = {}, bl_water = {}, bl_needle = {}, bl_tooth = {}, bl_wall = {},
    bl_manacle = {}, bl_final_heart = {}, bl_final_vessel = {}, bl_final_acorn = {},
    bl_club = { suit = "Clubs" }, bl_goad = { suit = "Spades" }, bl_head = { suit = "Hearts" },
    bl_window = { suit = "Diamonds" }, bl_plant = { is_face = "face" }, bl_psychic = { h_size_ge = 5 },
  }
  local bad = {}
  for key, deb in pairs(CFG) do
    local b = { key = key, debuff = deb, config = { blind = { key = key } } }
    G.GAME = { current_round = {}, hands = { Pair = { played = 3, visible = true } }, blind = b }
    local rec = Model.RECORDS[key]
    if not rec then bad[#bad + 1] = key .. ": no record" end
    for _, surface in ipairs({ "select", "status", "hand" }) do
      local ok, txt = pcall(Render.render, surface, key, { blind = b })
      if not ok then bad[#bad + 1] = key .. "/" .. surface .. ": error"
      elseif type(txt) ~= "string" or txt == "" then bad[#bad + 1] = key .. "/" .. surface .. ": empty"
      elseif txt:find(" nil", 1, true) or txt:find("#%d") or txt:find("{%w+}") then
        bad[#bad + 1] = key .. "/" .. surface .. ": malformed: " .. txt
      end
    end
  end
  table.sort(bad)
  check("every boss renders a well-formed rule on every prose surface -- no whitelist, no exceptions",
    #bad == 0, table.concat(bad, ", "))
  G.GAME = saved
end

do
  local DF = require("facts.debuff_facts")
  local saved = G.GAME
  local center_only = { name = "Le Silex", debuff = {}, in_blind = true,
    config = { blind = { key = "bl_flint" } } }
  G.GAME = { current_round = {}, hands = {}, blind = center_only }
  check("blind_is matches on the center key when the name is unrecognised",
    DF.blind_is(center_only, "bl_flint") == true)
  check("a boss behaviour keyed off it still fires", DF.flint_active() == true)

  local name_only = { name = "The Flint", debuff = {}, in_blind = true }
  check("the record-name fallback still works", DF.blind_is(name_only, "bl_flint") == true)

  local other = { name = "The Hook", debuff = {}, config = { blind = { key = "bl_hook" } } }
  check("a different blind does not match", DF.blind_is(other, "bl_flint") == false)
  G.GAME = saved
end

do
  local DF = require("facts.debuff_facts")
  local cards = { { base = { value = "King", suit = "Hearts" } }, { base = { value = "King", suit = "Spades" } } }
  local function probe(initial, debuff_hand)
    local blind = { debuff = { hand = "Pair" }, triggered = initial, debuff_hand = debuff_hand }
    G.GAME = { current_round = {}, hands = {}, blind = blind }
    G.FUNCS = { get_poker_hand_info = function() return "Pair", nil, { Pair = { cards } } end }
    DF.boss_would_debuff(cards, "Pair")
    return blind.triggered
  end
  local function sets_true(self) self.triggered = true; return true end
  local function sets_false(self) self.triggered = false; return false end
  check("probe restores triggered=false after the game sets it true", probe(false, sets_true) == false)
  check("probe restores triggered=true after the game sets it false", probe(true, sets_false) == true)
  check("probe leaves an unset triggered unset", probe(nil, sets_true) == nil)
  check("probe still reports the block", (function()
    local blind = { debuff = { hand = "Pair" }, debuff_hand = sets_true }
    G.GAME = { current_round = {}, hands = {}, blind = blind }
    G.FUNCS = { get_poker_hand_info = function() return "Pair", nil, { Pair = { cards } } end }
    return DF.boss_would_debuff(cards, "Pair")
  end)() == true)
end

do
  local kh, kd = card("K", "Hearts"), card("K", "Diamonds")
  local nc, nd = card("9", "Clubs"), card("9", "Spades")
  local h = { kh, kd, nc, nd, card("3", "Spades"), card("7", "Clubs"), card("2", "Diamonds"), card("5", "Hearts") }
  setup(h, {
    levels = { ["Two Pair"] = { played = 6 }, ["Pair"] = { played = 2 } },
    phi = function() return nil, nil, { ["Two Pair"] = { { kh, kd, nc, nd } }, Pair = { { kh, kd } } } end,
  })
  G.jokers = { cards = {
    { config = { center = { key = "j_supernova", set = "Joker", name = "Supernova",
      loc_txt = { name = "Supernova", description = { "adds times played" } } } },
      ability = { name = "Supernova", set = "Joker", extra = 1 } },
    { config = { center = { key = "j_madlike", set = "Joker", name = "MadLike",
      loc_txt = { name = "MadLike", description = { "+10 Mult if hand contains Two Pair" } } } },
      ability = { name = "MadLike", set = "Joker", type = "Two Pair", t_mult = 10 } },
  } }
  local s = prose()
  local tp = s:match("Two Pair %(cards [^;]*") or s
  check("accumulator Supernova: Ready Two Pair adds its exact-type +7 and MadLike's +10, in slot order",
    tp:find("(then jokers left to right: joker 1 +7 mult, joker 2 +10 mult)", 1, true) ~= nil, tp)
  check("accumulator Supernova: NOT double-counted via contained Pair (no +3 Pair share)",
    tp:find("+3 mult", 1, true) == nil, tp)
end

do
  local ks, kh, kd = card("K", "Spades"), card("K", "Hearts"), card("K", "Diamonds")
  local nc, nd = card("9", "Clubs"), card("9", "Spades")
  local h = { ks, kh, kd, nc, nd, card("3", "Hearts"), card("7", "Clubs"), card("2", "Diamonds") }
  setup(h, {
    levels = { ["Pair"] = { played = 1 } },
    phi = function() return nil, nil,
      { ["Full House"] = { { ks, kh, kd, nc, nd } }, ["Three of a Kind"] = { { ks, kh, kd } }, Pair = { { nc, nd } } } end,
  })
  G.jokers = { cards = {
    { config = { center = { key = "j_supernova", set = "Joker", name = "Supernova",
      loc_txt = { name = "Supernova", description = { "adds times played" } } } },
      ability = { name = "Supernova", set = "Joker", extra = 1 } },
    { config = { center = { key = "j_jolly", set = "Joker", name = "Jolly Joker",
      loc_txt = { name = "Jolly Joker", description = { "+8 Mult if hand contains Pair" } } } },
      ability = { name = "Jolly Joker", set = "Joker", type = "Pair", t_mult = 8 } },
  } }
  local s = prose()
  check("contains-joker kept on Full House (+8, Supernova Pair share excluded)",
    s:find("Full House (cards 1, 2, 3, 4, 5);", 1, true) ~= nil
      and s:find("Full House, Three of a Kind and Two Pair: then jokers left to right: joker 2 +8 mult.", 1, true) ~= nil, s)
  local pr = s:match("; Pair %(cards 1, 2%)[^;]*")
  check("exact Pair gets Supernova's share and the contains-joker, in slot order",
    pr and pr:find("(then jokers left to right: joker 1 +2 mult, joker 2 +8 mult)", 1, true) ~= nil, pr or s)
end

do
  local saved = G.GAME
  G.GAME = { current_round = {}, hands = {
    ["Two Pair"]   = { visible = true, level = 3, chips = 60, mult = 6, played = 6 },
    ["Flush"]      = { visible = true, level = 2, chips = 50, mult = 6, played = 3 },
    ["Straight"]   = { visible = true, level = 1, chips = 30, mult = 4, played = 1 },
    ["Full House"] = { visible = false, level = 2, chips = 60, mult = 6, played = 2 },
  } }
  local section = require("context.ctx_hand").levels_section() or ""
  check("levels_section still reports every leveled type with its play count",
    section:find("Two Pair: level 3", 1, true) and section:find("played 6.", 1, true)
      and section:find("Flush: level 2", 1, true) and section:find("played 3.", 1, true), section)
  check("levels_section leaves an unleveled visible type out of the leveled rows",
    not section:find("Straight: level 1", 1, true), section)
  check("levels_section never leaks a hidden hand type",
    not section:find("Full House", 1, true), section)
  G.GAME = saved
end

do
  local h = { card("King","Hearts"), card("King","Spades"), card("Queen","Hearts"), card("Queen","Diamonds") }
  setup(h, { levels = { Pair = { level = 1, chips = 10, mult = 2 }, ["Two Pair"] = { level = 1, chips = 20, mult = 2 } },
    phi = function() return nil, nil, { Pair = { { h[1], h[2] } }, ["Two Pair"] = { { h[1], h[2], h[3], h[4] } } } end })
  G.jokers = { cards = { { ability = { name = "Joker", mult = 5 }, config = { center = { key = "j_joker" } } } } }
  local s = prose()
  check("an always-on joker appears in every Ready row's chain",
    s:find("Pair (cards 1, 2) (level 1, 10 chips x2 mult); Two Pair (cards 1, 2, 3, 4) (level 1, 20 chips x2 mult)."
      .. " Each of these: then jokers left to right: joker 1 +5 mult.", 1, true) ~= nil, s)

  G.jokers = nil
  local s2 = prose()
  check("no joker -> no chain",
    s2:find("Pair (cards 1, 2) (level 1, 10 chips x2 mult)", 1, true) ~= nil and s2:find("jokers left to right", 1, true) == nil, s2)
end

done()
