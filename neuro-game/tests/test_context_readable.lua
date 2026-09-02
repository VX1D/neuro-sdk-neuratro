_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Config = require("core.config")
local ContextReadable = require("context.context_readable")
local ContextCompact = require("context.context_compact")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local check, done = require("tests.helpers").harness("context-readable")

local SUPPORTED = ContextReadable.SUPPORTED

local JARGON = {
  "xM=", "+M=", "+C=", "jh=", "$/r=", " · ", "·", "_per_round", "_EOround", "_held_",
  "per_copy", "min_cards", "max_cards", "most_played=", "rounds_left=", "DEBUFFED_",
  "no_suit_no_rank", "counts_as", "unsellable", "Bonus(", "Steel(", "Glass(", "Stone(",
  "Poly(", "Holo(", "Foil(", "song=",
}
local function jargon_hit(s)
  for _, j in ipairs(JARGON) do if s:find(j, 1, true) then return j end end
  return nil
end

local FORBIDDEN = {
  "B|", "BD|", "H:", "HL|", "DK|", "DC:", "PLAY|", "LP|", "J:", "JORD:", "JK_ALL:",
  "JD:", "L:", "SH|", "I:", "LA|", "C[", "V|", "TAGS|", "BS|", "BU|", "BP|", "BA|",
  "BO:", "RE|", "PK:", "PC:", "ACTS|", "STATE:", "AVAIL:",
}
local function token_line(blob)
  for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
    for _, p in ipairs(FORBIDDEN) do
      if line:sub(1, #p) == p then return line:sub(1, 48) end
    end
  end
  return nil
end

local function missing_number(cmp, prose)
  for line in (cmp .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" and not line:find("^STATE:") and not line:find("^AVAIL:") and not line:find("^ACTS|") then
      for n in line:gmatch("%d+") do
        if not prose:find(n, 1, true) then return n .. " (from: " .. line:sub(1, 40) .. ")" end
      end
    end
  end
  return nil
end

local MOCK_RESET = {
  "hand", "jokers", "consumeables", "deck",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack", "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS",
}
local function reset_g()
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
end

local seen, covered = {}, {}
for _, sc in ipairs(TD.SCENARIOS) do
  local key = sc.state .. "|" .. sc.desc
  if not seen[key] then
    seen[key] = true
    reset_g()
    local ok = pcall(function()
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro";
    end)
    if ok then
      local acts = A.get_valid_actions_for_state(sc.state)
      local tag = sc.state .. "/" .. sc.desc:sub(1, 20)

      local ok_build, prose = pcall(ContextReadable.build, sc.state, acts)
      check(tag .. ": build never throws", ok_build, prose)

      if SUPPORTED[sc.state] then
        if type(G.GAME) == "table" then
          check(tag .. ": supported state rendered prose to scan",
            type(prose) == "string" and prose ~= "", type(prose) .. "/" .. tostring(prose))
        end
        if type(prose) == "string" and prose ~= "" then
          local leak = token_line(prose)
          local cmp_present = ContextCompact.build(sc.state, acts, { split = "volatile", no_cache = true }) or ""
          check(tag .. ": compact side rendered text to compare against", cmp_present ~= "", cmp_present)
          check(tag .. ": no compact token line", leak == nil, leak)
          local jarg = jargon_hit(prose)
          check(tag .. ": no jargon leak", jarg == nil, jarg)
          local cmp = ContextCompact.build(sc.state, acts, { split = "volatile", no_cache = true }) or ""
          local miss = missing_number(cmp, prose)
          check(tag .. ": every compact number present in prose", miss == nil, miss)
          if cmp:find("+DB", 1, true) then
            check(tag .. ": debuffed card marked", prose:lower():find("debuff", 1, true) ~= nil)
          end
          if cmp:find("+LOCK", 1, true) then
            check(tag .. ": locked card marked", (prose:lower():find("forced", 1, true) or prose:lower():find("lock", 1, true)) ~= nil)
          end
          if sc.state == "SELECTING_HAND" then
            check(tag .. ": Structure not duplicated in board",
              not prose:find("Structure:", 1, true) and not prose:find("Ready:", 1, true) and not prose:find("Close:", 1, true))
          end
          if leak == nil and miss == nil then covered[sc.state] = true end
        end
      else
        check(tag .. ": unsupported state falls back (nil)", prose == nil, type(prose))
      end
    end
  end
end

do
  local base
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SELECTING_HAND" and not sc.xfail then base = sc break end
  end
  check("a SELECTING_HAND scenario exists to stage marks on", base ~= nil)
  if base then
    reset_g()
    TD.apply_mock(base.mock())
    G.NEURO.persona = "neuro"
    local cards = (G.hand or {}).cards or {}
    check("MARK1 the staged hand has cards to mark", #cards >= 2, tostring(#cards))
    if #cards >= 2 then
      cards[1].debuff = true
      cards[2].ability = cards[2].ability or {}
      cards[2].ability.forced_selection = true

      local acts = A.get_valid_actions_for_state("SELECTING_HAND")
      local CtxHand = require("context.ctx_hand")
      local db_tok = CtxHand.card_token(cards[1], true, false)
      local lock_tok = CtxHand.card_token(cards[2], true, false)
      local prose = ContextReadable.build("SELECTING_HAND", acts) or ""
      check("MARK2 the compact side marks the debuffed card +DB",
        db_tok:find("+DB", 1, true) ~= nil, db_tok)
      check("MARK3 the compact side marks the forced card +LOCK",
        lock_tok:find("+LOCK", 1, true) ~= nil, lock_tok)
      check("MARK4 the prose says the card is debuffed",
        prose:lower():find("debuff", 1, true) ~= nil, prose)
      check("MARK5 the prose says the card is locked or forced",
        (prose:lower():find("forced", 1, true) or prose:lower():find("lock", 1, true)) ~= nil, prose)
    end
  end
end

local V = ContextReadable._verbalize

do
  local CtxShop = require("context.ctx_shop")
  local function jk(key, name, mult, rarity, cost, edition)
    return { ability = { name = name, set = "Joker", mult = mult },
      config = { center = { key = key, set = "Joker", rarity = rarity } }, cost = cost, edition = edition }
  end
  local function tarot(key, name, cost)
    return { ability = { name = name, set = "Tarot" }, config = { center = { key = key, set = "Tarot" } }, cost = cost }
  end
  local function planet(key, name, cost)
    return { ability = { name = name, set = "Planet" },
      config = { center = { key = key, set = "Planet", config = {} } }, cost = cost }
  end
  local function booster(kind, name, cost)
    return { ability = { set = "Booster", name = name }, cost = cost,
      config = { center = { kind = kind, set = "Booster", key = "p_x" } } }
  end

  _G.G = {
    NEURO = { reserved_dollars = 0 }, FUNCS = {},
    GAME = { current_round = { reroll_cost = 5, free_rerolls = 0 }, dollars = 10, round_resets = { ante = 2 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {
      jk("j_mime", "Mime", 2, 2, 5, { polychrome = true }),
      jk("j_fib", "Fib", 3, 3, 8),
      tarot("c_justice", "Justice", 3),
      planet("c_pluto", "Pluto", 3),
    } },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {
      booster("Arcana", "Jumbo Arcana Pack", 6), booster("Buffoon", "Buffoon Pack", 4),
      booster("Celestial", "Jumbo Celestial Pack", 6), booster("Spectral", "Spectral Pack", 4),
      booster("Standard", "Standard Pack", 4),
    } },
  }
  local prose = CtxShop.shop_section() or ""
  local jarg = jargon_hit(prose)
  check("shop items: no jargon leak", jarg == nil, (jarg or "-") .. " | " .. prose)
  local WANT = {
    "Mime", "Uncommon", "1.5 Mult", "Fib", "Rare", "a consumable, not a Joker",
    "pack of Tarot consumables", "pack of Jokers", "pack of Planet consumables",
    "pack of Spectral consumables", "pack of playing cards",
  }
  for _, want in ipairs(WANT) do
    check("shop items: has '" .. want .. "'", prose:find(want, 1, true) ~= nil, prose)
  end

  G.GAME.dollars = 1
  G.shop_jokers = { cards = { jk("j_joker", "Joker", 4, 1, 2) } }
  G.shop_booster = { cards = {} }
  local unaffordable = CtxShop.shop_section() or ""
  check("shop items: has 'affordable now: no'", unaffordable:find("affordable now: no", 1, true) ~= nil, unaffordable)
end

do
  local CtxHelpers = require("context.ctx_helpers")
  local eff = CtxHelpers.humanize_effect("+4 Mult · x2 Mult(only if hand has Flush) · +30 Chips · Poly(x1.5m)", true)
  check("edition token dropped from the effect column when flags carry it",
    eff == "+4 Mult, x2 Mult(only if hand has Flush), +30 Chips", eff)
  local dots = CtxHelpers.humanize_effect("+4 Mult · and so on...", true)
  check("a real trailing clause is no longer mistaken for a cut edition token",
    dots == "+4 Mult, and so on...", dots)
  local flg = CtxHelpers.humanize_flags("Poly(x1.5m)")
  check("the edition is still shown via flags", flg:find("X1.5 Mult", 1, true) ~= nil, flg)

  local ante = CtxHelpers.humanize_effect("-1 Ante, -1 hand each round")
  check("a leading minus survives (Hieroglyph reads -1 Ante, not 1 Ante)",
    ante == "-1 Ante, -1 hand each round", ante)
  local semi = CtxHelpers.humanize_effect("-1 Ante; -1 hand each round")
  check("the same holds when the separator is a semicolon",
    semi == "-1 Ante, -1 hand each round", semi)
  local trailing = CtxHelpers.humanize_effect(", +4 Mult,")
  check("separators at either edge are still stripped", trailing == "+4 Mult", trailing)
end

do
  local CtxShop = require("context.ctx_shop")
  local menu = CtxShop.legality_section("MENU", { start_run = true }) or ""
  check("legality_section menu shows run-start/deck-switch, not shop legality",
    menu:find("can start run: yes", 1, true) ~= nil
    and menu:find("can switch deck: no", 1, true) ~= nil
    and menu:find("can buy", 1, true) == nil, menu)
end

do
  local raw = "Structure: pairs>=2:1 trips>=3:0 quads>=4:0 top:J suit_max:3 run_max:2. Ready: Pair[3,4](lv1 10c x2). Close: near Three of a Kind[3,4]; near Two Pair[3,4]. "
  local p = ContextReadable.structure_prose(raw)
  check("structure_prose: no 'pairs>=2' token", p:find("pairs>=2", 1, true) == nil, p)
  check("structure_prose: no [N,N] positions", p:find("%[%d") == nil, p)
  check("structure_prose: no (lvN Nc xN)", p:find("lv%d") == nil, p)
  check("structure_prose: no 'Close:'/'near'", p:find("Close:", 1, true) == nil and p:find("near ", 1, true) == nil, p)
  check("structure_prose: prose present",
    p:find("Ready to play now: Pair", 1, true) and p:find("cards 3, 4", 1, true)
    and p:find("One card away:", 1, true) and p:find("Jack", 1, true), p)

  local raw2 = "Structure: pairs>=2:1 trips>=3:0 quads>=4:0 top:K suit_max:2 run_max:1. Ready: Pair[1,2](lv1 10c x2)(1 debuffed~0)(play 5+ cards). Close: near Flush: 4 red[1,2,3,4](1 debuffed~0). "
  local p2 = ContextReadable.structure_prose(raw2)
  check("structure_prose: debuff/floor/color verbalized cleanly",
    p2:find("1 debuffed, score 0", 1, true) and p2:find("needs 5+ cards played", 1, true)
    and p2:find("4 red", 1, true) and p2:find("%[%d") == nil and p2:find("lv%d") == nil, p2)
end
do
  local TokenLegends = require("facts.token_legends")
  local function token_prefixed(s)
    for line in ((s or "") .. "\n"):gmatch("([^\n]*)\n") do
      if line:match("^[A-Z][A-Z_0-9]*[|:]") then return line:sub(1, 40) end
    end
    return nil
  end
  check("READABLE_COMMON is prose (no token prefix)",
    token_prefixed(TokenLegends.READABLE_COMMON) == nil, token_prefixed(TokenLegends.READABLE_COMMON))
  local stable = ContextReadable.verbalize_stable(
    "FRAME|Rules here.\nRUN|Deck here.\nVouchers you own: Telescope (effect).\nJoker details:\n1. Egg — desc.")
  check("verbalize_stable strips FRAME|/RUN| prefixes and passes already-prose sections through",
    token_prefixed(stable) == nil, stable)
end

do
  local LevelDelta = require("util.level_delta")
  local hands, snap = { Flush = { level = 2, visible = true } }, { Flush = 1 }
  local rmsg = LevelDelta.brief(hands, snap) .. "."
  check("level-up readable: prose form, carrying no L-> token",
    rmsg == "Flush leveled up from 1 to 2.", rmsg)
end

do
  local FactHints = require("facts.fact_hints")
  local function joker(key, name) return { config = { center = { key = key } }, ability = { name = name } } end
  G.jokers = { cards = { joker("j_blueprint", "Blueprint"), joker("j_cavendish", "Cavendish") } }
  G.NEURO.state_enter_serial = 999001
  local bp = FactHints.blueprint_chain_hint()
  check("bp_chain readable: no JOKER CHAIN header", bp:find("JOKER CHAIN", 1, true) == nil, bp)
  check("bp_chain readable: no ->copies / [i] token", bp:find("->copies", 1, true) == nil and bp:find("%[%d%]") == nil, bp)
  check("bp_chain readable: names the copy + target", bp:find("Blueprint", 1, true) ~= nil and bp:find("Cavendish", 1, true) ~= nil, bp)
  G.jokers = nil

  G.shop_jokers = { cards = {
    { ability = { name = "Baron", set = "Joker" }, config = { center = { set = "Joker" } }, edition = { polychrome = true } },
    { ability = { name = "Mime", set = "Joker" }, config = { center = { set = "Joker" } }, edition = { filtered = true } },
  } }
  G.NEURO.state_enter_serial = 999003
  local se = FactHints.shop_edition_hint()
  check("shop_edition readable: no compact tag leak", se:find("Poly(", 1, true) == nil and se:find("(x1.5m", 1, true) == nil, se)
  check("shop_edition readable: edition name shown", se:find("Baron (Polychrome)", 1, true) ~= nil, se)
  check("shop_edition readable: effect not restated (lives in the shop row)", se:find("X1.5 Mult", 1, true) == nil, se)
  check("shop_edition describes the edition as an attached parallel effect",
    se:find("applies alongside the card text and occupies no separate Joker slot", 1, true) ~= nil
      and se:find("modifies that Joker's base effect", 1, true) == nil, se)
  G.shop_jokers = nil
end

do
  local CtxHand = require("context.ctx_hand")
  local function pc(perma, extra_enh)
    return { base = { value = "Queen", suit = "Spades" },
      ability = { perma_bonus = perma, extra_enhancement = extra_enh } }
  end
  G.hand = { cards = { pc(8) }, config = {} }
  local sec = CtxHand.hand_section and CtxHand.hand_section() or ""
  check("perma_bonus shows on the card token", sec:find("permanently +8 chips", 1, true) ~= nil, sec)
  check("perma_bonus leaves no compact token in readable mode",
    sec:find("perma8c", 1, true) == nil, sec)

  G.hand = { cards = { pc(0) }, config = {} }
  local zero = CtxHand.hand_section and CtxHand.hand_section() or ""
  check("the zero-bonus card row really rendered",
    zero:find("1) Queen of Spades", 1, true) ~= nil, zero)
  check("no perma tag when the card has no permanent bonus", zero:find("perma", 1, true) == nil, zero)

  G.hand = { cards = { pc(8, true) }, config = {} }
  local ee = CtxHand.hand_section and CtxHand.hand_section() or ""
  check("the extra_enhancement card row really rendered",
    ee:find("1) Queen of Spades", 1, true) ~= nil, ee)
  check("no perma tag when extra_enhancement suppresses it in-game",
    ee:find("perma", 1, true) == nil, ee)
  G.hand = nil
end

do
  local CS = require("facts.card_semantics")
  local function tarot(desc)
    return { ability = { set = "Tarot" }, config = { center = { key = "c_t", set = "Tarot",
      loc_txt = { description = { desc } } } } }
  end
  local d = CS.full_description(tarot("Convert the left card into the right (Drag to rearrange)"), 200)
  check("UI-only hint stripped from description", d:find("Drag", 1, true) == nil, d)
  check("stripping the hint leaves no trailing space", d:sub(-1) ~= " " and d:find("  ") == nil, "[" .. d .. "]")
  check("the real text survives", d:find("Convert the left card into the right", 1, true) ~= nil, d)
  local keep = CS.full_description(tarot("x2 Mult (1 in 4 to break)"), 200)
  check("informative parentheses are kept", keep:find("(1 in 4 to break)", 1, true) ~= nil, keep)
  check("kept parentheses keep their leading space", keep:find("Mult (1 in", 1, true) ~= nil, keep)
end

do
  local CtxMisc = require("context.ctx_misc")
  local card = { ability = { name = "Death", set = "Tarot" }, sell_cost = 1,
    config = { center = { key = "c_death", set = "Tarot",
      loc_txt = { description = { "Select 2 cards, convert the left card" } } } } }
  _G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} },
    consumeables = { cards = { card }, config = { card_limit = 2 } } }
  local row = CtxMisc.consumables_section() or ""
  check("comma in consumable description does not double the space", row:find("  ") == nil, "[" .. row .. "]")
  check("comma in consumable description survives intact", row:find("cards, convert", 1, true) ~= nil, row)
end

do
  local function snap(v, depth, visited, out)
    if depth > 4 then return end
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then out[#out + 1] = tostring(v); return end
    if t ~= "table" then out[#out + 1] = t; return end
    if visited[v] then out[#out + 1] = "<cyc>"; return end
    visited[v] = true
    local keys = {}
    for k in pairs(v) do
      if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local val = v[k]
      if type(val) ~= "function" and k ~= "children" and k ~= "UIBox" and k ~= "parent" and k ~= "T" then
        out[#out + 1] = tostring(k) .. "="
        snap(val, depth + 1, visited, out)
      end
    end
    visited[v] = nil
  end
  local function state_sig()
    local out = {}
    snap({ GAME = G.GAME, hand = G.hand, jokers = G.jokers, deck = G.deck,
           consumeables = G.consumeables, shop_jokers = G.shop_jokers }, 0, {}, out)
    return table.concat(out, "|")
  end
  local mutated, seen3 = {}, {}
  for _, sc in ipairs(TD.SCENARIOS) do
    local key = sc.state .. "|" .. sc.desc
    if not seen3[key] then
      seen3[key] = true
      reset_g()
      local ok = pcall(function()
        TD.apply_mock(sc.mock())
        G.NEURO.persona = "neuro";
      end)
      if ok then
        local acts = A.get_valid_actions_for_state(sc.state)
        local before = state_sig()
        pcall(ContextCompact.build, sc.state, acts, { no_cache = true })
        if state_sig() ~= before then mutated[#mutated + 1] = key end
      end
    end
  end
  check("building context never mutates game state", #mutated == 0, table.concat(mutated, "; "))
end

do
  local unstable = {}
  local seen2 = {}
  for _, sc in ipairs(TD.SCENARIOS) do
    local key = sc.state .. "|" .. sc.desc
    if not seen2[key] then
      seen2[key] = true
      reset_g()
      local ok = pcall(function()
        TD.apply_mock(sc.mock())
        G.NEURO.persona = "neuro";
      end)
      if ok then
        local acts = A.get_valid_actions_for_state(sc.state)
        local a = ContextCompact.build(sc.state, acts, { no_cache = true })
        local b = ContextCompact.build(sc.state, acts, { no_cache = true })
        local c = ContextCompact.build(sc.state, acts, { no_cache = true })
        if not (a == b and b == c) then unstable[#unstable + 1] = key end
      end
    end
  end
  check("context build is deterministic across rebuilds",
    #unstable == 0, table.concat(unstable, "; "))
end

for st in pairs(SUPPORTED) do
  check("covered supported state: " .. st, covered[st], "no mock scenario hit it")
end

done()
