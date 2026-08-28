_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("boss-records")

local Model = require("facts.boss.model")
local Render = require("facts.boss.render")
local View = require("facts.boss.view")
local Legality = require("facts.boss.legality")

local CLASSES = {
  C1_STATIC_CARD_DEBUFF = true, C2_HISTORY_CARD_DEBUFF = true, C3_HAND_TYPE_GATE = true,
  C4_SELECTION_CONSTRAINT = true, C5_RESOURCE_TAX = true, C6_STAT_CHECK = true,
  C7_INFO_DENIAL = true, C8_JOKER_INTERFERENCE = true,
}

local CFG = {
  bl_club = { suit = "Clubs" }, bl_goad = { suit = "Spades" }, bl_head = { suit = "Hearts" },
  bl_window = { suit = "Diamonds" }, bl_plant = { is_face = "face" }, bl_psychic = { h_size_ge = 5 },
}

local function pin(key)
  local rec = Model.RECORDS[key]
  local blind = { key = key, name = rec and rec.name, debuff = CFG[key] or {}, hands = {}, only_hand = false }
  _G.G = {
    GAME = { blind = blind, probabilities = { normal = 1 },
      current_round = { most_played_poker_hand = "High Card" }, hands = {} },
    hand = { cards = {} }, playing_cards = {}, deck = { cards = {} }, jokers = { cards = {} },
  }
  return blind
end

do
  local bad, n = {}, 0
  _G.G = {}
  local sample_view = View.build()
  for key in pairs(Model.BOSS_NAMES) do
    n = n + 1
    local rec = Model.RECORDS[key]
    if not rec then
      bad[#bad + 1] = key .. ": NO RECORD"
    else
      if type(rec.rule) ~= "string" or rec.rule == "" then bad[#bad + 1] = key .. ": empty rule" end
      if not CLASSES[rec.class] then bad[#bad + 1] = key .. ": bad class " .. tostring(rec.class) end
      if type(rec.horizon) ~= "table" or next(rec.horizon) == nil then bad[#bad + 1] = key .. ": no horizon" end
      if type(rec.since) ~= "number" then bad[#bad + 1] = key .. ": no since" end
      if rec.name ~= Model.BOSS_NAMES[key] then bad[#bad + 1] = key .. ": name mismatch" end
      for _, e in ipairs(Model._test.closure_errors(rec, sample_view)) do bad[#bad + 1] = e end
    end
  end
  for key in pairs(Model.RECORDS) do
    if not Model.BOSS_NAMES[key] then bad[#bad + 1] = key .. ": record without a BOSS_NAMES key" end
  end
  table.sort(bad)
  check("completeness: all 28 keys carry a record with rule, class, horizon, since and template closure",
    n == 28 and #bad == 0, tostring(n) .. " keys; " .. table.concat(bad, "; "))
end

local SURFACES = { "select", "status", "hand", "ante" }

local function each_rendered(fn)
  for key in pairs(Model.RECORDS) do
    local blind = pin(key)
    for _, surface in ipairs(SURFACES) do
      local got = Render.render(surface, key, { blind = blind })
      if type(got) == "string" and got ~= "" then fn(key, surface, got) end
    end
  end
end

do
  local bad, seen = {}, 0
  each_rendered(function(key, surface, got)
    seen = seen + 1
    if not got:find(Model.RECORDS[key].name, 1, true) and surface ~= "ante" then
      bad[#bad + 1] = key .. "/" .. surface .. ": does not name its own boss"
    end
  end)
  table.sort(bad)
  check("every boss renders on the surfaces it declares and names itself", #bad == 0 and seen >= 28,
    table.concat(bad, "; ") .. " seen=" .. tostring(seen))
end

do
  local bad = {}
  each_rendered(function(key, surface, got)
    local hole = got:match("%b{}")
    if hole then bad[#bad + 1] = key .. "/" .. surface .. ": unsubstituted " .. hole end
  end)
  table.sort(bad)
  check("no template variable ever reaches the model unsubstituted", #bad == 0, table.concat(bad, "; "))
end

do
  local MALFORMED = {
    { "  ", "double space" }, { " .", "space before period" }, { " ,", "space before comma" },
    { "()", "empty parentheses" }, { "( )", "blank parentheses" }, { " ;", "space before semicolon" },
  }
  local bad = {}
  each_rendered(function(key, surface, got)
    for _, m in ipairs(MALFORMED) do
      if got:find(m[1], 1, true) then bad[#bad + 1] = key .. "/" .. surface .. ": " .. m[2] end
    end
    if got:find("%s$") or got:find("^%s") then
      bad[#bad + 1] = key .. "/" .. surface .. ": leading or trailing whitespace"
    end
  end)
  table.sort(bad)
  check("rendered boss text is well formed -- no seams from a missing fact", #bad == 0,
    table.concat(bad, "; "))
end

do
  local BANNED = { "you should", "keep them out", "lean on", "plan around", "plan to", "build so",
    "prefer ", "avoid ", "usually ", "worth ", "best ", "strongest" }
  local bad = {}
  each_rendered(function(key, surface, got)
    local lower = got:lower()
    for _, phrase in ipairs(BANNED) do
      if lower:find(phrase, 1, true) then bad[#bad + 1] = key .. "/" .. surface .. ": " .. phrase end
    end
  end)
  table.sort(bad)
  check("no-steering: a boss states its rule and the board, it never tells the model what to do",
    #bad == 0, table.concat(bad, "; "))
end

do
  local LEAKS = { "reason_code", "SCHEMA_INVALID", "POLICY_", "TODO", "FIXME", "nil", "userdata",
    "function:", "table:", "2026-", "%d+%.lua" }
  local bad = {}
  each_rendered(function(key, surface, got)
    for _, pat in ipairs(LEAKS) do
      if got:find(pat) then bad[#bad + 1] = key .. "/" .. surface .. ": " .. pat end
    end
  end)
  table.sort(bad)
  check("no internal token or Lua artefact reaches the model", #bad == 0, table.concat(bad, "; "))
end

do
  local bad = {}
  for key, rec in pairs(Model.RECORDS) do
    if rec.marks then
      local blind = pin(key)
      local status = Render.render("status", key, { blind = blind }) or ""
      for _, token in ipairs(rec.marks) do
        if not status:find(token, 1, true) then
          bad[#bad + 1] = key .. ": status text lacks its own mark token " .. token
        end
      end
    end
  end
  table.sort(bad)
  check("vocabulary alignment: every card-mark token appears literally in that boss's status text",
    #bad == 0, table.concat(bad, "; "))
end

do
  pin("bl_eye")
  G.GAME.blind = { key = "bl_modded_boss", name = "The Modded", debuff = {}, boss = { min = 1, max = 10 },
    loc_txt = { text = { "Modded boss effect text" } } }
  local line = Render.boss_line("status", nil, G.GAME.blind)
  check("unknown boss key falls back to raw engine text instead of dropping silently",
    line ~= nil and line:find("Modded boss effect text", 1, true) ~= nil
      and line:find("The Modded", 1, true) ~= nil, line)
  local CtxBlind = require("context.ctx_blind")
  local ok_bd, bd = pcall(CtxBlind.blind_debuff_line)
  check("the FACT line carries the modded boss's own effect text, matching what the prose channel renders",
    ok_bd and type(bd) == "string" and bd:find("Modded boss effect text", 1, true) ~= nil
      and bd:find("The Modded", 1, true) ~= nil, tostring(ok_bd) .. " / " .. tostring(bd))
end

do
  pin("bl_pillar")
  G.playing_cards = {
    { ability = { played_this_ante = true }, debuff = true },
    { ability = { played_this_ante = true }, debuff = true },
    { ability = { played_this_ante = true } },
    { ability = {} },
  }
  local ante_line = Render.render("ante", "bl_pillar")
  check("the Pillar ante-horizon line is the bare engine count plus the boss identity",
    ante_line == "3 card(s) in your deck are flagged as played this ante. This ante's Boss is"
      .. " The Pillar, which debuffs exactly those cards.", ante_line)
  G.GAME.blind = { name = "Small Blind", debuff = {} }
  G.GAME.round_resets = { blind_choices = { Boss = "bl_pillar" } }
  local CtxBlind = require("context.ctx_blind")
  check("the ante line renders during Small/Big of a Pillar-boss ante",
    CtxBlind.blind_debuff_line() == ante_line, CtxBlind.blind_debuff_line())
  G.GAME.round_resets = { blind_choices = { Boss = "bl_wall" } }
  check("no ante line when the ante's boss is not The Pillar",
    CtxBlind.blind_debuff_line() == nil, CtxBlind.blind_debuff_line())
end

do
  pin("bl_psychic")
  G.hand = { config = { highlighted_limit = 5 } }
  require("core.actions") -- registers the play_hand contract this block reads back
  local Registry = require("core.action_registry")
  local function advertised(name)
    local out = {}
    for _, def in ipairs(Registry.definitions()) do out[def.name] = def end
    return out[name]
  end
  local play = advertised("play_hand")
  check("affordance: play_hand indices narrowed to exactly 5 under an h_size_ge=5 boss",
    play.schema.properties.indices.minItems == 5 and play.schema.properties.indices.maxItems == 5,
    tostring(play.schema.properties.indices.minItems))
  check("affordance: the prose the model reads is narrowed with it",
    play.description:find("Play exactly 5 hand cards", 1, true) ~= nil
      and Registry.prompt("play_hand"):find("pick exactly 5 different hand positions", 1, true) ~= nil,
    play.description:sub(1, 40))
  check("affordance: discard_hand is not narrowed",
    advertised("discard_hand").schema.properties.indices.minItems == 1)
  check("affordance: the registered contract itself is never mutated",
    Registry.definitions() and (function()
      pin("bl_eye")
      return advertised("play_hand").schema.properties.indices.minItems == 1
    end)())
  check("affordance: C3 hand-type legality is not expressible and narrows nothing",
    advertised("play_hand").schema.properties.indices.minItems == 1
      and advertised("play_hand").description:find("Play 1-5 hand cards", 1, true) ~= nil)
end

do
  local Metrics = require("util.metrics")
  local blind = pin("bl_eye")
  blind.hands = {}
  blind.debuff_hand = function() error("engine exploded") end
  local a = { sort_id = 31, base = { value = "King", suit = "Hearts" } }
  local b = { sort_id = 32, base = { value = "King", suit = "Spades" } }
  G.hand = { cards = { a, b }, highlighted = {}, config = { highlighted_limit = 5 } }
  G.GAME.hands = { Pair = { level = 1, visible = true } }
  G.GAME.current_round.hands_left = 2
  G.GAME.current_round.discards_left = 1
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }

  Metrics._counters["boss_debuff_probe_failed"] = nil
  local verdict = Legality.play_verdict({ a, b }, { 1, 2 })
  check("verdict: a thrown boss probe states the uncertainty instead of staying silent",
    type(verdict) == "string" and verdict:find("could not be checked", 1, true) ~= nil,
    tostring(verdict))
  check("verdict: the thrown probe is named in the metrics",
    (Metrics._counters["boss_debuff_probe_failed"] or 0) > 0,
    tostring(Metrics._counters["boss_debuff_probe_failed"]))
end

do
  local blind = pin("bl_eye")
  blind.hands = { Pair = true }
  blind.debuff_hand = function(self, _cards, _ph, handname, _check)
    return self.hands[handname] == true
  end
  local a = { sort_id = 1, base = { value = "King", suit = "Hearts" } }
  local b = { sort_id = 2, base = { value = "King", suit = "Spades" } }
  G.hand = { cards = { a, b }, highlighted = {}, config = { highlighted_limit = 5 } }
  G.GAME.hands = { Pair = { level = 2, visible = true } }
  G.GAME.current_round.hands_left = 2
  G.GAME.current_round.discards_left = 1
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }
  local verdict = Legality.play_verdict({ a, b }, { 1, 2 })
  check("verdict: fixed frame -- engine classification, boss-attributed fact, resources, commit protocol",
    verdict ~= nil
      and verdict:find("Selection [1,2] = Pair (lvl 2).", 1, true) ~= nil
      and verdict:find("BOSS (The Eye): Pair was already played this round -- under this boss it scores 0."
        .. " Hand types already played this round: Pair.", 1, true) ~= nil
      and verdict:find("2 hand(s), 1 discard(s) left.", 1, true) ~= nil,
    verdict)
  check("verdict: no alternative is ever named -- the frame is exactly its three parts, nothing appended",
    verdict == "Selection [1,2] = Pair (lvl 2).\n"
      .. "BOSS (The Eye): Pair was already played this round -- under this boss it scores 0."
      .. " Hand types already played this round: Pair.\n"
      .. "2 hand(s), 1 discard(s) left.",
    verdict)
  blind.hands = {}
  check("verdict: silent on a legal play -- never speak on a legal action",
    Legality.play_verdict({ a, b }, { 1, 2 }) == nil)
end

do
  local blind = pin("bl_eye")
  blind.hands = { Pair = true }
  blind.debuff_hand = function(self, _cards, _ph, handname, _check)
    return self.hands[handname] == true
  end
  local a = { sort_id = 11, base = { value = "King", suit = "Hearts" } }
  local b = { sort_id = 12, base = { value = "King", suit = "Spades" } }
  G.hand = { cards = { a, b }, highlighted = {}, config = { highlighted_limit = 5 } }
  G.GAME.hands = { Pair = { level = 1, visible = true } }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.NEURO = { decision_serial = 7 }
  require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }
  require("core.transition_guard").reset()
  G.TIMERS = { REAL = 100 }
  local results = {}
  local bridge = {
    send_action_result = function(_, id, ok, message, reason_code)
      results[#results + 1] = { id = id, ok = ok, message = message, reason_code = reason_code }
    end,
    send_context = function() end,
  }
  local Dispatcher = require("core.dispatcher")
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "verdict-1", name = "play_hand", data = { indices = { 1, 2 } } } }, bridge)
  local r1 = results[#results]
  check("a boss-rule verdict acknowledges with success=true so the force is not retried",
    r1 ~= nil and r1.ok == true and r1.reason_code == "CONFIRMATION_REQUIRED"
      and tostring(r1.message):find("Selection [1,2]", 1, true) ~= nil, r1 and tostring(r1.message))
  check("the verdict releases the force and re-arms the next one",
    G.NEURO.force_inflight == false and G.NEURO.force_dirty == true,
    tostring(G.NEURO.force_inflight) .. "/" .. tostring(G.NEURO.force_dirty))
  check("the verdict does not advance the decision serial, so the resend latch stays valid",
    G.NEURO.decision_serial == 7, tostring(G.NEURO.decision_serial))
  check("the legality latch is armed for the same selection",
    G.NEURO.play_confirm and G.NEURO.play_confirm.signature == "11,12",
    tostring(G.NEURO.play_confirm and G.NEURO.play_confirm.signature))

  G.NEURO.force_inflight = true
  G.TIMERS.REAL = 200
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "verdict-2", name = "play_hand", data = { indices = { 1, 2 } } } }, bridge)
  local r2 = results[#results]
  check("a deliberate resend of the same indices commits (success=true, executor ran)",
    r2 ~= nil and r2.ok == true and tostring(r2.message):find("Selection [1,2]", 1, true) == nil, r2 and tostring(r2.message))

  G.NEURO.force_inflight = true
  G.TIMERS.REAL = 300
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  Dispatcher.handle_message({ command = "action",
    data = { id = "verdict-3", name = "play_hand", data = { indices = { 1, 99 } } } }, bridge)
  local r3 = results[#results]
  check("a schema/engine-invalid submission keeps success=false",
    r3 ~= nil and r3.ok == false, r3 and tostring(r3.message))

end

do
  local blind = pin("bl_pillar")
  blind.debuff_hand = function() return false end
  local db = { sort_id = 21, debuff = true, ability = { played_this_ante = true },
    base = { value = "10", suit = "Spades" }, get_id = function() return 10 end }
  local clean = { sort_id = 22, ability = {},
    base = { value = "10", suit = "Hearts" }, get_id = function() return 10 end }
  G.hand = { cards = { db, clean }, highlighted = {}, config = { highlighted_limit = 5 } }
  G.GAME.hands = { ["High Card"] = { level = 1, visible = true } }
  G.GAME.current_round.hands_left = 4
  G.GAME.current_round.discards_left = 3
  G.FUNCS = { get_poker_hand_info = function(cards) return "High Card", {}, { top = {} }, cards, { db } end }
  local verdict = Legality.play_verdict({ db }, { 1 })
  check("Pillar verdict: all-debuffed selection carries the rank-vs-card contrast",
    verdict ~= nil
      and verdict:find("every scoring card in this selection is +DB", 1, true) ~= nil
      and verdict:find("Card 1 (10 of Spades) is +DB; card 2 (10 of Hearts) is the same rank and is not +DB.", 1, true) ~= nil,
    verdict)
end

do
  local p = io.popen("grep -rl 'pillar_ante_ids' --include='*.lua'"
    .. " --exclude-dir='.local-backups' --exclude-dir='pre-revert-*' . 2>/dev/null")
  local hits = {}
  if p then
    for line in p:lines() do
      if not line:find("tests/", 1, true) and not line:find("dev/", 1, true) then hits[#hits + 1] = line end
    end
    p:close()
  end
  check("principle A: no source module keeps a Pillar shadow set -- boss card facts are engine reads only",
    #hits == 0, table.concat(hits, ", "))
end

local function board(key, opts)
  opts = opts or {}
  local rec = Model.RECORDS[key]
  _G.get_blind_amount = function(ante) return ({ 300, 800, 2000, 5000 })[ante] or 300 end
  local blind = { key = key, name = rec and rec.name, debuff = CFG[key] or {}, hands = {}, only_hand = false }
  _G.G = {
    GAME = { blind = blind, probabilities = { normal = 1 }, round_resets = { ante = 4 },
      current_round = { most_played_poker_hand = opts.most_played or "Flush",
        hands_left = opts.hands_left, discards_left = opts.discards_left }, hands = {} },
    P_BLINDS = { [key] = { name = rec and rec.name, mult = opts.mult or 2 } },
    hand = { cards = opts.hand or {}, config = { card_limit = opts.hand_size } },
    playing_cards = {}, deck = { cards = opts.deck or {} }, jokers = { cards = opts.jokers or {} },
  }
  G.GAME.dollars = opts.dollars
  local HF = require("facts.hand_facts")
  local rows = opts.levels or { { name = "Flush", level = 2, chips = 35, mult = 7 } }
  HF.levels = function() return rows end
  return Render.render(opts.surface or "status", key, { blind = blind }) or ""
end

do
  local bad = {}
  for _, key in ipairs({ "bl_flint", "bl_wall", "bl_final_vessel" }) do
    local out = board(key, { mult = key == "bl_wall" and 4 or (key == "bl_final_vessel" and 6 or 2) })
    if out:find("It needs", 1, true) then bad[#bad + 1] = key .. ": reach line returned" end
    if out:find("comes to about", 1, true) then bad[#bad + 1] = key .. ": per-hand figure returned" end
    if out == "" then bad[#bad + 1] = key .. ": rule text lost with it" end
  end
  check("a stat-check boss states its rule without projecting a per-hand figure",
    #bad == 0, table.concat(bad, "; "))

  local plain = board("bl_flint")
  local halved = board("bl_flint", { levels = { { name = "Flush", level = 2, chips = 18, mult = 4 } } })
  check("the boss line no longer varies with the hand rows it is handed",
    plain == halved and plain ~= "", plain .. " || " .. halved)
end

local function cards(n)
  local t = {}
  for i = 1, n or 0 do t[i] = { base = { value = "King" } } end
  return t
end

do
  local CASES = {
    { "bl_needle", { hands_left = 1 }, "1 hand this round" },
    { "bl_water", { discards_left = 2 }, "2 discards this round" },
    { "bl_manacle", { hand_size = 7 }, "holds 7 cards this round" },
    { "bl_hook", { hand = cards(8), deck = cards(31) }, "holding 8 cards" },
    { "bl_tooth", { dollars = 4 }, "You hold $4" },
  }
  local bad = {}
  for _, c in ipairs(CASES) do
    local out = board(c[1], c[2])
    if not out:find(c[3], 1, true) then
      bad[#bad + 1] = c[1] .. ": lacks '" .. c[3] .. "'"
    end
  end
  check("a resource-tax boss reports how much of that resource is left, not just the rule",
    #bad == 0, table.concat(bad, "; "))

  check("the resource it does not tax stays out of its line",
    not board("bl_needle", { hands_left = 1, discards_left = 3 }):find("discard", 1, true),
    board("bl_needle", { hands_left = 1, discards_left = 3 }))
end

do
  local psychic = board("bl_psychic", { hand = cards(4) })
  check("singles: The Psychic states how many cards are in hand against its five-card floor",
    psychic:find("holding 4 cards", 1, true) ~= nil, psychic)

  -- Amber Acorn turns the whole row over (game-dump blind.lua:218-227), so the board has to as well:
  -- the sentence counts the jokers actually hidden, not the roster size, and a board that names the
  -- boss without flipping would have the payload call visible jokers hidden.
  local flipped = cards(3)
  for _, c in ipairs(flipped) do c.facing = "back" end
  local acorn = board("bl_final_acorn", { jokers = flipped })
  check("singles: Amber Acorn counts the jokers it hid",
    acorn:find("3 jokers are face down", 1, true) ~= nil, acorn)

  local heart = board("bl_final_heart", { jokers = cards(4) })
  check("singles: Crimson Heart names the pool the pick is drawn from",
    heart:find("from your 4 jokers", 1, true) ~= nil, heart)

  local lone = board("bl_final_heart", { jokers = cards(1) })
  check("singles: with one joker Crimson Heart says the pick is not a lottery",
    lone:find("it is the one picked", 1, true) ~= nil, lone)

  check("singles: a boss with nothing to count stays silent rather than printing a zero",
    not board("bl_final_acorn", { jokers = {} }):find("face down in a shuffled", 1, true),
    board("bl_final_acorn", { jokers = {} }))
end

done()
