_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")

local check, done = require("tests.helpers").harness("hand-facts")

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local COLOR = { Hearts = "red", Diamonds = "red", Spades = "black", Clubs = "black" }
local SMEAR = false  -- toggled by the Smeared Joker test below; affects all card() calls while true
local function card(v, suit, debuff)
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit },
    debuff = debuff or nil,
    config = { center = { key = "c_base", set = "Default" } },
    get_id = function() return id end,
    is_suit = function(_, s, _ignore_debuff, flush_calc)
      if s == suit then return true end
      if flush_calc and SMEAR and COLOR[s] == COLOR[suit] then return true end
      return false
    end,
  }
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

local function junk() -- must not accidentally form a pair/run/flush with the K-K front cards used below
  return { card("3","Spades"), card("7","Clubs"), card("9","Hearts"), card("2","Diamonds"), card("5","Spades"), card("8","Clubs") }
end
local function with_front(a, b) local h = { a, b }; for _, c in ipairs(junk()) do h[#h+1] = c end; return h end

do
  local kh, kd = card("K","Hearts"), card("K","Diamonds")
  setup(with_front(kh, kd), {
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 } },
    phi = function() return nil, nil, { Pair = { { kh, kd } } } end,
  })
  local s = HF.summary()
  check("size-floor: Ready Pair present", s:find("Pair%[1,2%]") ~= nil, s)
  check("size-floor: Ready Pair flagged play 5+", s:find("Pair%[1,2%]%(play 5%+ cards%)") ~= nil, s)
end

do
  local Metrics = require("util.metrics")
  local kh, kd = card("K","Hearts"), card("K","Diamonds")

  local function ready_line(debuff_hand)
    setup(with_front(kh, kd), {
      blind = { name = "The Psychic", debuff = { h_size_ge = 5 }, debuff_hand = debuff_hand },
      phi = function() return "Pair", nil, { Pair = { { kh, kd } } } end,
    })
    return HF.summary()
  end

  local working = ready_line(function() return true end)
  check("boss probe: a working debuff_hand marks the Ready entry as zeroed",
    working:find("Pair%[1,2%][^\n]* %-%- zeroed by The Psychic") ~= nil, working:match("Ready[^\n]*"))

  Metrics._counters["boss_debuff_probe_failed"] = nil
  local thrown = ready_line(function() error("engine exploded") end)
  check("boss probe: a THROWN debuff_hand never presents the hand as clean",
    thrown:find("Pair%[1,2%][^\n]* %-%- ") ~= nil, thrown:match("Ready[^\n]*"))
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
  local s = HF.summary()
  check("size-floor: near Three of a Kind flagged play 5+",
    s:find("Three of a Kind keep%[1,2%]/other%[[%d,]+%]%(discard at most %d+%)%(play 5%+ cards%)") ~= nil, s)
end

do
  local kh, kd = card("K","Hearts", true), card("K","Diamonds")
  setup(with_front(kh, kd), { blind = {} })
  local s = HF.summary()
  check("near-rank partial debuff annotated",
    s:find("Three of a Kind keep%[1,2%]/other%[[%d,]+%]%(discard at most %d+%)%(1 debuffed~0%)") ~= nil, s)
end

do
  local kh, kd = card("K","Hearts", true), card("K","Diamonds", true)
  setup(with_front(kh, kd), { blind = {} })
  local s = HF.summary()
  check("near-rank all-debuffed suppressed", s:find("Three of a Kind") == nil, s)
end

do
  local hand = {
    card("2","Hearts"), card("5","Hearts", true), card("8","Hearts"), card("K","Hearts"),
    card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("near-flush partial debuff annotated",
    s:find("Flush: 4 Hearts keep%[1,2,3,4%]/other%[[%d,]+%]%(1 debuffed~0%)") ~= nil, s)
end

do
  local hand = {
    card("5","Hearts"), card("6","Diamonds"), card("7","Spades"), card("8","Clubs"),
    card("J","Hearts"), card("Q","Diamonds"), card("K","Spades"), card("2","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("open straight labeled", s:find("Straight keep%[.-%(open draw%)") ~= nil, s)
  check("open straight not called inside", s:find("inside draw") == nil, s)
end

do
  local hand = {
    card("5","Hearts"), card("6","Diamonds"), card("8","Spades"), card("9","Clubs"),
    card("Q","Hearts"), card("K","Diamonds"), card("2","Spades"), card("3","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("inside straight labeled", s:find("Straight keep%[.-%(inside draw%)") ~= nil, s)
end

do
  local hand = {
    card("A","Hearts"), card("2","Diamonds"), card("3","Spades"), card("4","Clubs"),
    card("6","Hearts"), card("8","Spades"), card("10","Clubs"), card("Q","Diamonds"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("A-2-3-4 is an inside draw", s:find("Straight keep%[.-%(inside draw%)") ~= nil and s:find("open draw") == nil, s)
end
do
  local hand = {
    card("J","Hearts"), card("Q","Diamonds"), card("K","Spades"), card("A","Clubs"),
    card("3","Hearts"), card("5","Spades"), card("7","Clubs"), card("9","Diamonds"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("J-Q-K-A is an inside draw", s:find("Straight keep%[.-%(inside draw%)") ~= nil and s:find("open draw") == nil, s)
end

do
  _G.SMODS = { four_fingers = function(kind) return 4 end }
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Diamonds"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("Four Fingers: 3-of-a-suit is a near-flush", s:find("Flush: 3 Hearts") ~= nil, s)
  _G.SMODS = nil
end

do
  local stone = card("2","Hearts"); stone.config.center.key = "m_stone"
  local hand = {
    stone, card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("Stone excluded from suit count", s:find("suit_max:3") ~= nil and s:find("near Flush") == nil, s)
end

do
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
    card("4","Spades"), card("4","Diamonds"), card("6","Clubs"), card("7","Clubs"),
  }
  setup(hand, { blind = {} })
  local s = HF.summary()
  check("full straight not mislabeled near", s:find("near Straight") == nil, s)
end

do
  SMEAR = true
  local hand = {
    card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Diamonds"),
    card("3","Spades"), card("6","Spades"), card("9","Clubs"), card("Q","Clubs"),
  }
  setup(hand, { blind = {} })
  G.jokers = { cards = { { config = { center = { key = "j_smeared" } } } } }
  local s = HF.summary()
  check("Smeared near-flush labeled by color", s:find("Flush: 4 red keep%[1,2,3,4%]") ~= nil, s)
  check("Smeared near-flush not labeled by suit", s:find("Flush: 4 Hearts") == nil, s)
  G.jokers = nil
  SMEAR = false
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
  pcall(HH.play_confirm_reject, cards)
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
  local s = HF.summary()
  check("open-ended straight counts BOTH ends as outs",
    s:find("near Straight keep%[1,2,3,4%].-%(draw 4/8=") ~= nil, s:match("Close:[^%.]*") or s)
  check("open-ended straight still labelled open", s:find("(open draw)", 1, true) ~= nil, s)
end

do
  local h = { card("2","Hearts"), card("3","Clubs"), card("4","Spades"), card("5","Diamonds"),
              card("9","Hearts"), card("J","Clubs"), card("Q","Spades"), card("K","Hearts") }
  setup(h, { discards = 2 })
  G.deck = { cards = { card("A","Hearts"), card("8","Clubs") } }
  local s = HF.summary()
  check("a drawn Ace counts as an out for 2-3-4-5",
    s:find("near Straight keep%[1,2,3,4%].-%(draw 1/2=") ~= nil, s:match("Close:[^%.]*") or s)
end

do
  local h = { card("5","Hearts"), card("6","Diamonds"), card("8","Spades"), card("9","Clubs"),
              card("Q","Hearts"), card("K","Diamonds"), card("2","Spades"), card("3","Clubs") }
  setup(h, { discards = 2 })
  G.deck = { cards = { card("7","Hearts"), card("7","Clubs"), card("4","Clubs") } }
  local s = HF.summary()
  check("double gutshot is labelled inside, not open", s:find("(inside draw)", 1, true) ~= nil,
    s:match("Close:[^%.]*") or s)
  check("double gutshot chooses the window with more live outs and counts only its gap",
    s:find("keep%[1,2,3,4%].-%(draw 2/3=") ~= nil, s:match("Close:[^%.]*") or s)
  G.deck = nil
end

do
  local h = { card("K","Hearts"), card("K","Spades"), card("2","Clubs"), card("7","Diamonds"),
              card("9","Hearts"), card("3","Spades"), card("4","Clubs"), card("5","Diamonds") }
  setup(h, { discards = 2, deck = { cards = { card("K","Clubs"), card("8","Hearts") } } })
  local s = HF.summary()
  local six = s:match("other%[([%d,]+)%]%(discard at most (%d+)%)")
  check("oversized other list carries the discard cap", six ~= nil, s:match("Close:[^%.]*") or s)
  local h2 = { card("K","Hearts"), card("K","Spades"), card("2","Clubs"), card("7","Diamonds") }
  setup(h2, { discards = 2, deck = { cards = { card("K","Clubs"), card("8","Hearts") } } })
  local s2 = HF.summary()
  check("short other list has no cap note", s2:find("discard at most", 1, true) == nil,
    s2:match("Close:[^%.]*") or s2)
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
  local bad, n = {}, 0
  for key, deb in pairs(CFG) do
    n = n + 1
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
  check("all 28 bosses were exercised (guards against a vacuous loop)", n == 28, tostring(n))
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
  check("the BOSS_NAMES name fallback still works", DF.blind_is(name_only, "bl_flint") == true)

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
  local s = HF.summary()
  check("accumulator Supernova: Ready Two Pair adds exact-type mult only (+17)", s:find("+17m", 1, true) ~= nil,
    s:match("Two Pair%[[%d,]*%]%b()%b()") or s)
  check("accumulator Supernova: NOT double-counted via contained Pair (no +20)", s:find("+20m", 1, true) == nil, s)
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
    { config = { center = { key = "j_jolly", set = "Joker", name = "Jolly",
      loc_txt = { name = "Jolly", description = { "+8 Mult if hand contains Pair" } } } },
      ability = { name = "Jolly", set = "Joker", type = "Pair", t_mult = 8 } },
  } }
  local s = HF.summary()
  local fh = s:match("Full House%[[%d,]*%]%b()")
  check("contains-joker kept on Full House (+8, Supernova Pair share excluded)", fh and fh:find("+8m", 1, true) ~= nil, fh or s)
  local pr = s:match("Pair%[4,5%]%b()%b()")
  check("exact Pair gets contains-joker + Supernova share (+10)", pr and pr:find("+10m", 1, true) ~= nil, pr or s)
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
  local s = HF.summary()
  check("guaranteed joker note appears on every Ready row",
    s:find("Pair%[1,2%]%(lv1 10c x2%)%(jokers%-always: %+5m%)", 1) ~= nil
    and s:find("Two Pair%[1,2,3,4%]%(lv1 20c x2%)%(jokers%-always: %+5m%)", 1) ~= nil, s)

  G.jokers = nil
  local s2 = HF.summary()
  check("no guaranteed joker -> no (jokers-always: ...) note",
    s2:find("Pair%[1,2%]%(lv1 10c x2%)", 1) ~= nil and s2:find("jokers%-always", 1) == nil, s2)
end

do
  local src = io.open("facts/hand_facts.lua"):read("*a")
  check("hand_facts has no private per-hand-type accumulation loop of its own",
    src:find("for _, effect in ipairs(jsum.conditional) do", 1, true) == nil,
    "found a local re-accumulation over jsum.conditional")
  check("hand_facts sources its per-hand-type view from jsum.ledger.by_type",
    src:find("jsum.ledger.by_type", 1, true) ~= nil, "no jsum.ledger.by_type reference found")
end

done()
