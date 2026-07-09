-- run: luajit test_readiness.lua from neuro-game/; inert in-game (loaded by nothing)
package.path = "./?.lua;;" .. package.path
_G.NEURO_TEST = true  -- set before any require: enables _enforce_budget test hook
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Utils = require("util.utils")
local ContextCompact = require("context.context_compact")
local CardUtil = require("facts.card_util")
local CtxMisc = require("context.ctx_misc")
local CtxHand = require("context.ctx_hand")
local CtxBlind = require("context.ctx_blind")
local CtxHelpers = require("context.ctx_helpers")
local DF = require("facts.debuff_facts")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local fails, total = 0, 0
local function check(name, cond, detail)
  total = total + 1
  if cond then
    print("PASS  " .. name)
  else
    fails = fails + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end
local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end
local function card(v, s, stone)
  return { base = { value = v, suit = s }, config = { center = { key = stone and "m_stone" or "c" } } }
end
local MOCK_RESET = {
  "hand", "jokers", "consumeables", "deck",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack",
  "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "TIMERS", "P_CENTER_POOLS",
}
local function mock_state(desc_match, state)
  for _, k in ipairs(MOCK_RESET) do G[k] = nil end
  G.GAME = { current_round = {} }
  G.FUNCS.get_poker_hand_info = nil
  G.NEURO.reserved_dollars = 0
  G.NEURO.shop_reroll_count = 0
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc:find(desc_match, 1, true) then
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro"; G.NEURO.rules_sent = true; G.NEURO.state_entry_hints = nil
      return
    end
  end
  error(string.format("mock_state: no scenario matching %q in state %s", desc_match, state))
end

local function joker(name, key, extra)
  local j = { ability = { name = name, set = "Joker" }, sell_cost = 3,
    config = { center = { key = key, set = "Joker" } } }
  for k, v in pairs(extra or {}) do j.ability[k] = v end
  return j
end
local function tarot(name, sell)
  return { ability = { name = name, set = "Tarot" }, sell_cost = sell,
    config = { center = { key = "c_" .. tostring(name):lower():gsub("%W", "") } } }
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.consumeables = { cards = { tarot("The Hermit", 3) }, config = { card_limit = 2 } }
  local blob = ContextCompact.build("BLIND_SELECT", { "use_card", "select_blind" }, { no_cache = true, split = "volatile" })
  check("1: BLIND_SELECT + use_card renders C section", blob:find("C[slots 1/2]:i,n,t,$,sel,ok,d", 1, true) ~= nil, blob)
  check("1: C row carries sell $", blob:find(",$3,", 1, true) ~= nil, blob:match("C%[[^\n]*\n[^\n]*"))
  local no_use = ContextCompact.build("BLIND_SELECT", { "select_blind" }, { no_cache = true, split = "volatile" })
  check("1: no use/sell in set -> no C section", no_use:find("C[slots", 1, true) == nil)
  check("1: consumables_info registered for BLIND_SELECT",
    has(A.get_action_names_for_state("BLIND_SELECT"), "consumables_info"))

  local fp1 = ContextCompact.decision_fingerprint("BLIND_SELECT", blob)
  G.consumeables.cards[#G.consumeables.cards + 1] = tarot("The Emperor", 4)
  local blob2 = ContextCompact.build("BLIND_SELECT", { "use_card", "select_blind" }, { no_cache = true, split = "volatile" })
  local fp2 = ContextCompact.decision_fingerprint("BLIND_SELECT", blob2)
  check("1: consumable change moves BLIND_SELECT fingerprint", fp1 ~= fp2)
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.jokers = { cards = { joker("Gros Michel", "j_gros_michel", { eternal = true }) }, config = { card_limit = 5 } }
  local blob = ContextCompact.build("BLIND_SELECT", { "sell_card", "select_blind" }, { no_cache = true, split = "volatile" })
  check("2: sell_card-only set renders J section", blob:find("J:i,n,f,flg,$", 1, true) ~= nil, blob)
  check("2: J row carries eternal flag", blob:find("eternal(unsellable)", 1, true) ~= nil, blob:match("J:[^\n]*\n[^\n]*"))
  check("2: J row carries sell $", blob:find(",$3", 1, true) ~= nil)
  local no_sell = ContextCompact.build("BLIND_SELECT", { "select_blind" }, { no_cache = true, split = "volatile" })
  check("2: no joker action in set -> no J section", no_sell:find("J:i,n,f,flg,$", 1, true) == nil)
end

-- live odds: G.GAME.probabilities.normal is the numerator everywhere odds render
do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.probabilities = { normal = 1 }
  check("3: Lucky short baseline frozen at 1x",
    CardUtil.enhancement_short("m_lucky") == "Lucky(1/5:+20m_or_1/15:+20$)", CardUtil.enhancement_short("m_lucky"))
  G.GAME.probabilities = { normal = 2 }
  check("3: Lucky short doubles under Oops",
    CardUtil.enhancement_short("m_lucky") == "Lucky(2/5:+20m_or_2/15:+20$)", CardUtil.enhancement_short("m_lucky"))
  local rec = CardUtil.enhancement_record("m_lucky")
  check("3: Lucky desc live", rec.desc == "2 in 5 for +20 Mult, 2 in 15 for $20", rec.desc)
  check("3: Glass short live", CardUtil.enhancement_short("m_glass") == "Glass(x2m_always_then_2/4_destroyed)",
    CardUtil.enhancement_short("m_glass"))
  check("3: Glass desc live", CardUtil.enhancement_record("m_glass").desc == "x2 Mult, 2 in 4 chance to break")
  check("3: live_odds helper", CardUtil.live_odds(4) == "2 in 4")

  -- non-targeting consumables emit no force hint; effect+odds live in C:'s d= column
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.consumeables = { cards = { tarot("The Wheel of Fortune", 2) }, config = { card_limit = 2 } }
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("3: non-targeting consumable omits effect prose from force query",
    q:find("chance to add foil", 1, true) == nil, q)
  G.GAME.probabilities = nil
end

do
  mock_state("Normal", "SHOP")
  G.consumeables = { cards = { tarot("The Hermit", 3) }, config = { card_limit = 2 } }
  local s = CtxMisc.consumables_section() or ""
  check("4: C header has $ column", s:find("C[slots 1/2]:i,n,t,$,sel,ok,d", 1, true) ~= nil, s)
  check("4: C row has $3", s:find(",$3,", 1, true) ~= nil, s)
end

do
  mock_state("Has pack cards", "TAROT_PACK")
  G.GAME.pack_choices = 1
  G.pack_cards = { cards = { tarot("The Fool") } }
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  local s = CtxMisc.pack_section("TAROT_PACK") or ""
  check("5: PC header has ok column", s:find("PC:i,n,t,f,ok", 1, true) ~= nil, s)
  check("5: blocked pick renders ok=N", s:find(",N$") ~= nil or s:find(",N\n") ~= nil, s)
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  local s2 = CtxMisc.pack_section("TAROT_PACK") or ""
  check("5: takeable pick renders ok=Y", s2:find(",Y$") ~= nil or s2:find(",Y\n") ~= nil, s2)

  mock_state("Full joker slots during buffoon pack", "BUFFOON_PACK")
  G.NEURO.once_serials = {}
  local f = require("force.force_pack").build("BUFFOON_PACK")
  local q = (f or {}).query or ""
  check("5: buffoon pack warns on full joker slots", q:find("Joker slots FULL", 1, true) ~= nil, q)
  local _, pack_legend = require("facts.token_legends").for_state("BUFFOON_PACK")
  check("5: pack legend defines PC columns incl ok", (pack_legend or ""):find("i,n,t,f,ok", 1, true) ~= nil, pack_legend)
end

-- legends ride the retained glossary channel (facts.token_legends), not the ephemeral force query
do
  local TL = require("facts.token_legends")
  local common = TL.COMMON or ""
  local _, q = TL.for_state("SHOP")
  -- shared tokens (L/AVAIL/JORD/...) ride the once-per-ante COMMON gloss
  q = (q or "") .. " " .. common
  for _, tok in ipairs({ "CB=can-buy", "CR=can-afford-reroll", "CRS=reroll-still-leaves", "CS=can-sell",
      "CU=can-use-consumable", "L:=per-hand-type", "AVAIL=actions", "SR=rerolls this shop visit", "JORD=" }) do
    check("6: SHOP legend defines " .. tok, q:find(tok, 1, true) ~= nil)
  end

  local _, rq = TL.for_state("ROUND_EVAL")
  rq = rq or ""
  check("6: ROUND_EVAL legend defines RE tokens", rq:find("ERN=end-of-round earnings", 1, true) ~= nil
    and rq:find("IN=interest", 1, true) ~= nil, rq)

  local _, sq = TL.for_state("SELECTING_HAND")
  sq = sq or ""
  check("6: SH legend defines (Jn applies)", sq:find("(Jn applies)=", 1, true) ~= nil, sq)
  check("6: COMMON legend defines AVAIL", common:find("AVAIL=actions", 1, true) ~= nil)
  check("6: SH legend uses SEL (HG overload removed)", sq:find("SEL=selected now", 1, true) ~= nil)
  check("6: COMMON legend defines C sel column", common:find("sel=hand cards", 1, true) ~= nil)
end

-- _enforce_budget no longer drops sections or emits DROPPED markers, despite the name
do
  local big = string.rep("x", 1900)
  local out = ContextCompact._enforce_budget("BLIND_SELECT",
    { "CTX:x", "STATE:BLIND_SELECT", "BO:type,key", "C[slots 2/2]:i,n,t,$,d\n" .. big }, "volatile")
  local blob = table.concat(out, "\n")
  check("7: C section kept (no lossy drop)", blob:find("C[slots 2/2]", 1, true) ~= nil, blob:sub(1, 120))
  check("7: BO survives", blob:find("BO:type,key", 1, true) ~= nil)
  check("7: no DROPPED marker emitted", blob:find("DROPPED:", 1, true) == nil)

  local out2 = ContextCompact._enforce_budget("PLANET_PACK",
    { "CTX:x", "STATE:PLANET_PACK", "PK:PLANET|PICKS:1", "L:n,lv,c,m,p\nPair,1,10,2,0", "J:" .. big }, "volatile")
  local blob2 = table.concat(out2, "\n")
  check("7: PLANET_PACK keeps L", blob2:find("L:n,lv", 1, true) ~= nil, blob2:sub(1, 120))
  check("7: PLANET_PACK keeps J too (no drop)", blob2:find("J:", 1, true) ~= nil and blob2:find("DROPPED:", 1, true) == nil)
end

do
  mock_state("Normal: has G.GAME", "MENU")
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  G.P_CENTER_POOLS = { Stake = { { name = "White Stake", key = "stake_white" }, { name = "Red Stake", key = "stake_red" } } }
  local sk = CtxMisc.stake_list_line() or ""
  check("8: stake list line", sk == "STK[change_stake to_key]:1=White Stake,2=Red Stake", sk)
  local blob = ContextCompact.build("RUN_SETUP", nil, { no_cache = true, split = "volatile" })
  check("8: RUN_SETUP context carries STK line", blob:find("STK[change_stake", 1, true) ~= nil, blob)
  G.OVERLAY_MENU = nil
  check("8: stake line no longer gated by overlay", CtxMisc.stake_list_line() ~= nil)
  G.P_CENTER_POOLS = nil
  check("8: no stake pool -> no stake line", CtxMisc.stake_list_line() == nil)

  mock_state("No overlay", "GAME_OVER")
  G.GAME = { current_round = {}, won = false, round = 7, round_resets = { ante = 3 } }
  local go = ContextCompact.build("GAME_OVER", nil, { no_cache = true })
  check("8: GAME_OVER context has GO outcome line", go:find("GO|lost|A:3|R:7", 1, true) ~= nil, go)
  local f = D.get_force_for_state("GAME_OVER")
  local q = (f or {}).query or ""
  check("8: GAME_OVER force names the outcome", q:find("Run lost at Ante 3, round 7", 1, true) ~= nil, q)
  G.GAME.won = true
  local go2 = ContextCompact.build("GAME_OVER", nil, { no_cache = true })
  check("8: won run renders WON", go2:find("GO|WON", 1, true) ~= nil, go2)
end

-- challenge select/start wired into MENU: change_challenge_description sets G.challenge_tab, start_challenge_run consumes it
do
  check("9: change_challenge_description in MENU", has(A.get_action_names_for_state("MENU"), "change_challenge_description"))
  check("9: change_challenge_description not in RUN_SETUP", not has(A.get_action_names_for_state("RUN_SETUP"), "change_challenge_description"))
  mock_state("Normal: has G.GAME", "MENU")
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  local rs = D.get_force_for_state("RUN_SETUP")
  check("9: run-setup force omits challenge-select action",
    not has((rs or {}).actions, "change_challenge_description"))
  check("9: run-setup force still offers start_setup_run", has((rs or {}).actions, "start_setup_run"))
  G.OVERLAY_MENU = nil
  G.CHALLENGES = { { id = "c_omelette", name = "The Omelette" }, { id = "c_city", name = "The City" } }
  G.challenge_tab = nil
  local mf = D.get_force_for_state("MENU")
  check("9: MENU force lists challenge names in query", ((mf or {}).query or ""):find("The Omelette", 1, true) ~= nil, (mf or {}).query)
  check("9: MENU force offers change_challenge_description", has((mf or {}).actions, "change_challenge_description"))
  check("9: start_challenge_run NOT offered before a selection", not has((mf or {}).actions, "start_challenge_run"))
  G.challenge_tab = G.CHALLENGES[1]
  local mf2 = D.get_force_for_state("MENU")
  check("9: start_challenge_run offered after selecting a challenge", has((mf2 or {}).actions, "start_challenge_run"))
  G.challenge_tab = nil; G.CHALLENGES = nil
end

-- non-targeting planets emit no force hint; the level-up effect lives in C:'s d= column
do
  mock_state("Normal: 5 cards", "SELECTING_HAND")
  G.consumeables = { cards = { { ability = { set = "Planet", name = "Mercury" },
    config = { center = { key = "c_mercury", set = "Planet" } } } }, config = { card_limit = 2 } }
  G.NEURO.state_entry_hints = nil
  local f = D.get_force_for_state("SELECTING_HAND")
  check("10: planet consumable omits effect prose from force query",
    ((f or {}).query or ""):find("levels up a hand type", 1, true) == nil, (f or {}).query)
  G.consumeables = nil
end

-- token overload renames: HL inner HG -> SEL, BP inner BO -> BOSS
do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  local hl = CtxHand.hand_limits_section() or ""
  check("B: HL line uses SEL", hl:find("|SEL:", 1, true) ~= nil and hl:find("|HG:", 1, true) == nil, hl)

  mock_state("Small blind selectable", "BLIND_SELECT")
  local bs = CtxBlind.blind_select_section() or ""
  local bp = bs:match("BP|[^\n]*") or ""
  check("B: BP line uses BOSS", bp:find("|BOSS:", 1, true) ~= nil and bp:find("|BO:", 1, true) == nil, bp)
end

do
  local txt = DF.boss_debuff_text({ loc_txt = { text = { "Playing a #1# sets money to $0" } }, vars = { "Pair" } })
  check("P1: loc_txt fallback substitutes #1#", txt == "Playing a Pair sets money to $0", txt)
  local txt2 = DF.boss_debuff_text({ loc_txt = { text = { "#2# something" } } })
  check("P1: unknown var strips to ?", txt2 == "? something", txt2)

  _G.localize = nil
  G.P_TAGS = { tag_handy = { name = "Handy Tag", loc_txt = { text = { "Gives $#1# per hand played" } },
    config = { dollars_per_hand = 1 } } }
  local tt = DF.tag_effect_text("tag_handy")
  check("P1: tag fallback resolves loc_txt with vars", tt == "Gives $1 per hand played", tt)
  G.P_TAGS = nil

  _G.localize = function(a, b)
    if b == "poker_hands" and a == "Pair" then return "Paire" end
    return nil
  end
  G.GAME = G.GAME or {}; G.GAME.current_round = { most_played_poker_hand = "Pair" }
  local bt = DF.blind_effect_text("bl_ox", { name = "The Ox", loc_txt = { text = { "Playing a #1# sets money to $0" } } })
  check("C: Ox var goes through localize(key,'poker_hands')", bt == "Playing a Paire sets money to $0", bt)
  _G.localize = nil
end

-- pack rows carry enhancement/seal/edition; edition alone never suppresses description
do
  mock_state("Has pack cards", "TAROT_PACK")
  G.GAME.pack_choices = 1
  local pc = { base = { value = "10", suit = "Diamonds" }, edition = { foil = true },
    seal = "Gold", config = { center = { key = "m_bonus" } } }
  G.pack_cards = { cards = { pc } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  local s = CtxMisc.pack_section("STANDARD_PACK") or ""
  check("P2: pack playing-card row carries enhancement tag", s:find("Bonus(+30c)", 1, true) ~= nil, s)
  check("P2: pack playing-card row carries edition tag", s:find("Foil(+50c)", 1, true) ~= nil, s)
  check("P2: pack playing-card row carries seal tag", s:find("Gold(+$3_when_scored)", 1, true) ~= nil, s)

  local ed_only = { edition = { foil = true }, ability = {},
    generate_UIBox_ability_table = function() return { name = "X", main = { { config = { text = "Creates a random Joker" } } } } end }
  local eff = CtxHelpers.card_effect_summary(ed_only)
  check("P2: edition-only summary keeps description", eff:find("Foil(+50c)", 1, true) ~= nil
    and eff:find("Creates a random Joker", 1, true) ~= nil, eff)
end

-- joker tags render full modifier stack (edition no longer cut at 40 chars)
do
  mock_state("Normal", "SELECTING_HAND")
  local j = joker("Stacked", "j_stacked", { eternal = true, perishable = true, perish_tally = 3, rental = true })
  j.edition = { foil = true }
  local t = CtxHelpers.joker_tags(j)
  check("P5: full tag stack incl edition", t:find("eternal(unsellable)", 1, true) ~= nil
    and t:find("perishable(rounds_left=3)", 1, true) ~= nil
    and t:find("rental($3_per_round)", 1, true) ~= nil
    and t:find("Foil(+50c)", 1, true) ~= nil, t)
end

do
  mock_state("Normal", "SELECTING_HAND")
  local enh = card("5", "Hearts"); enh.config.center.key = "m_bonus"
  G.hand = { cards = { enh, card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("P6a: 'Enhanced cards in hand' line dropped", q:find("Enhanced cards in hand", 1, true) == nil, q)
  local gl = card("5", "Hearts"); gl.config.center.key = "m_glorp"
  G.hand = { cards = { gl, card("9", "Clubs") }, highlighted = {} }
  local q2 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("P6a: Glorpy gotcha still surfaces", q2:find("Glorpy cards give 10x chips", 1, true) ~= nil, q2)
end

do
  mock_state("Normal", "SHOP")
  local long_desc = "Adds the number of times poker hand has been played this run to Mult when scoring"
  local jk = {
    cost = 5, ability = { set = "Joker", name = "LongDesc" },
    config = { center = { key = "j_long", set = "Joker" } },
    generate_UIBox_ability_table = function()
      return { name = "LongDesc", main = { { config = { text = long_desc } } } }
    end,
  }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { jk } }
  local s = require("context.ctx_shop").shop_section() or ""
  local row = s:match("shop_jokers[^\n]*") or ""
  local first, second = row:find(long_desc, 1, true)
  local again = second and row:find(long_desc, second + 1, true)
  check("P6b: identical desc collapsed to '-'", first ~= nil and again == nil and row:find(",%-") ~= nil, row)

  G.NEURO.once_serials = {}
  local q = (D.get_force_for_state("SHOP") or {}).query or ""
  check("P3: no fused '}.Buyable' sentence", q:find("}.Buyable", 1, true) == nil, q:match("index[^B]*Buyable?"))
end

print(string.format("\n==== readiness: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
