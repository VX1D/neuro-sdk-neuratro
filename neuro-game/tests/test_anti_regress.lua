-- run: luajit test_anti_regress.lua (from neuro-game/); inert in-game, loaded by nothing
package.path = "./?.lua;;" .. package.path
_G.NEURO_TEST = true  -- set before any require: enables _test white-box hooks
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Utils = require("util.utils")
local ContextCompact = require("context.context_compact")
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

do
  local statics = {}
  for _, d in ipairs(A.get_static_actions()) do statics[d.name] = true end
  for _, r in ipairs({ "draw_from_deck", "highlight_card", "unhighlight_all" }) do
    check("removed/" .. r .. " not in static defs", not statics[r])
  end
end

-- card_click/end_consumeable were gated on a field nothing ever wrote
for _, st in ipairs({ "SELECTING_HAND", "SHOP", "TAROT_PACK" }) do
  check("card_click not in " .. st, not has(A.get_action_names_for_state(st), "card_click"))
  check("end_consumeable not in " .. st, not has(A.get_action_names_for_state(st), "end_consumeable"))
end

check("start_challenge_run in MENU", has(A.get_action_names_for_state("MENU"), "start_challenge_run"))
check("change_challenge_description in MENU", has(A.get_action_names_for_state("MENU"), "change_challenge_description"))
for _, st in ipairs({ "RUN_SETUP", "GAME_OVER" }) do
  check("start_challenge_run not in " .. st, not has(A.get_action_names_for_state(st), "start_challenge_run"))
  check("change_challenge_description not in " .. st, not has(A.get_action_names_for_state(st), "change_challenge_description"))
end

-- GAME_OVER must not hit the generic overlay intercept: it shadows the dedicated handler and soft-loops on exit_overlay_menu
do
  mock_state("With overlay present", "GAME_OVER")
  local f = D.get_force_for_state("GAME_OVER")
  check("GAME_OVER+overlay force omits the flaky exit_overlay_menu",
    f and not has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+overlay force offers setup_run (new-run path)",
    f and has(f.actions, "setup_run"))
end

do
  mock_state("With overlay present", "GAME_OVER")
  check("GAME_OVER offers setup_run immediately (no hold)",
    (D.get_force_for_state("GAME_OVER") or {}).actions ~= nil
      and has((D.get_force_for_state("GAME_OVER") or {}).actions, "setup_run"))
end

do
  mock_state("With unlock popup", "GAME_OVER")
  local f = D.get_force_for_state("GAME_OVER")
  check("GAME_OVER+unlock popup forces exit_overlay_menu",
    f and has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+unlock popup force is exit-only (not setup_run under the popup)",
    f and not has(f.actions, "setup_run"))
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local sh = A.get_action_names_for_state("SELECTING_HAND")
  check("commit action play_cards_from_highlighted de-registered", not has(sh, "play_cards_from_highlighted"))
  check("commit action discard_cards_from_highlighted de-registered", not has(sh, "discard_cards_from_highlighted"))
  check("legacy set_hand_highlight de-registered", not has(sh, "set_hand_highlight"))
  check("legacy clear_hand_highlight de-registered", not has(sh, "clear_hand_highlight"))
  check("play_hand offered in SELECTING_HAND", has(sh, "play_hand"))
  check("discard_hand offered in SELECTING_HAND", has(sh, "discard_hand"))
  check("play_hand valid with hand + hands_left>0", A.is_action_valid("play_hand"))
  check("discard_hand valid with hand + discards_left>0", A.is_action_valid("discard_hand"))
  G.GAME.current_round.hands_left = 0
  check("play_hand invalid with 0 hands left", not A.is_action_valid("play_hand"))
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 0
  check("discard_hand invalid with 0 discards left", not A.is_action_valid("discard_hand"))
  G.GAME.current_round.discards_left = 3
  G.hand = { cards = {}, highlighted = {} }
  check("play_hand invalid with empty hand", not A.is_action_valid("play_hand"))
  check("discard_hand invalid with empty hand", not A.is_action_valid("discard_hand"))
end

do
  mock_state("sell", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local avail = A.get_available_actions_for_state("SHOP")
  check("AVAIL excludes info (joker_info)", not has(avail, "joker_info"))
  check("AVAIL includes set_joker_order (2 jokers)", has(avail, "set_joker_order"))
  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"), {})
  check("context has AVAIL: line", blob:find("AVAIL:") ~= nil)
end

do
  mock_state("Normal", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = D.get_force_for_state("SHOP")
  check("SHOP force offers set_joker_order", f and has(f.actions, "set_joker_order"))
end

-- booster_kind reads the game-native center.kind (card_set collapses every pack to "Booster")
do
  local CU = require("facts.card_util")
  check("booster_kind: reads center.kind", CU.booster_kind({ config = { center = { kind = "Celestial" } } }) == "Celestial")
  check("booster_kind: empty for a non-pack", CU.booster_kind({ ability = { name = "Joker" }, config = { center = { key = "j_joker" } } }) == "")
end

do
  local function buffoon()
    return { cost = 4, ability = { set = "Booster", name = "Buffoon Pack" },
      config = { center = { kind = "Buffoon", set = "Booster", key = "p_buffoon_normal_1" } } }
  end
  local function arcana()
    return { cost = 4, ability = { set = "Booster", name = "Arcana Pack" },
      config = { center = { kind = "Arcana", set = "Booster", key = "p_arcana_normal_1" } } }
  end
  local function full_jokers()
    G.jokers = { cards = { { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } } },
      config = { card_limit = 1 } }
  end
  local WARN = "Buffoon pack"

  mock_state("Normal", "SHOP")
  full_jokers()
  G.shop_booster = { cards = { buffoon() } }
  local q_full = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force warns: Buffoon pack + joker slots full",
    q_full:find(WARN, 1, true) ~= nil and q_full:find("selling a joker", 1, true) ~= nil)

  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"), { no_cache = true })
  local row = blob:match("shop_booster[^\n]*")
  check("ctx: shop_booster type column = Buffoon (not generic Booster)",
    row ~= nil and row:find(",Buffoon,", 1, true) ~= nil, row)

  mock_state("Normal", "SHOP")
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_booster = { cards = { buffoon() } }
  local q_open = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning when joker slots open", q_open:find(WARN, 1, true) == nil)

  mock_state("Normal", "SHOP")
  full_jokers()
  G.shop_booster = { cards = { arcana() } }
  local q_arc = (D.get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning for a non-joker pack", q_arc:find(WARN, 1, true) == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("Close: near Flush (4 of a suit)", q:find("near Flush") ~= nil, q:match("Structure:[^\n]*"))
  -- engine reports Flush ready so near Flush must dedup
  G.FUNCS.get_poker_hand_info = function(_)
    local hc = G.hand.cards
    return "Flush", nil, { Flush = { hc[1], hc[2], hc[3], hc[4] }, ["High Card"] = { hc[1] } }, { hc[1], hc[2], hc[3], hc[4] }, nil
  end
  local q2 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("Ready: Flush shown", q2:find("Ready:[^\n]*Flush") ~= nil)
  check("near Flush deduped when ready", q2:find("near Flush") == nil)
  G.FUNCS.get_poker_hand_info = nil
  G.GAME.current_round.discards_left = 0
  local q3 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("no Close when discards=0", q3:find("Close:") == nil)
end

-- stone card must not count toward the suit total
do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("?", "?", true) }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("stone not counted (suit_max=4, near Flush)", q:find("suit_max:4") and q:find("near Flush"))
end

do
  local function dyna(arr) return { config = { string = arr } } end
  local r = {}; for i = 0, 23 do r[#r + 1] = tostring(i) end
  local mis = { ability = { name = "Misprint" }, config = { center = { key = "j_misprint" } },
    generate_UIBox_ability_table = function() return { main = {
      { config = { text = "  +" } }, { config = { object = dyna(r) } },
      { config = { object = dyna({ "Mult", "#@11D", "rand()" }) } } } } end }
  local desc = Utils.card_description(mis, 320) or ""
  check("Misprint desc has range 0 to 23", desc:find("0 to 23") ~= nil, desc)
  check("Misprint desc filters easter-egg", not desc:find("#@"), desc)
end

-- handlers return a closure on valid input, nil+error on invalid
do
  local function H(name) return D.get_action_handler(name) end
  check("play_hand handler accessor works", type(H("play_hand")) == "function")
  check("discard_hand handler accessor works", type(H("discard_hand")) == "function")

  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3

  local c1, e1 = H("play_hand")({})
  check("play_hand no indices -> error", c1 == nil and type(e1) == "string")
  local c_hl = H("play_hand")({ indices = { 1, 2 } })
  local ok_hl, r_hl = pcall(c_hl)
  check("atomic play -> closure runs to a string", type(c_hl) == "function" and ok_hl and type(r_hl) == "string", r_hl)

  G.GAME.blind = { debuff = { h_size_ge = 4 } }
  local c4, e4 = H("play_hand")({ indices = { 1 } })
  check("SH-2: boss min-cards rejects undersized play", c4 == nil and type(e4) == "string", e4)
  G.GAME.blind = nil

  local c_dis = H("discard_hand")({ indices = { 1 } })
  local ok_dis, r_dis = pcall(c_dis)
  check("atomic discard -> closure runs to a string", type(c_dis) == "function" and ok_dis and type(r_dis) == "string", r_dis)
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local c5, e5 = H("sell_card")({ area = "jokers", index = 1 })
  check("sell_card empty area -> error", c5 == nil and type(e5) == "string")

  local expensive = card("A", "Spades"); expensive.cost = 100
  G.shop_jokers = { cards = { expensive } }
  G.GAME.dollars = 4; G.NEURO.reserved_dollars = 0
  local c6, e6 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy_from_shop unaffordable -> error", c6 == nil and type(e6) == "string" and (e6:find("afford") ~= nil))

  local tarot = { ability = { consumeable = { max_highlighted = 1, min_highlighted = 1 } }, config = { center = { key = "c_tarot" } } }
  G.consumeables = { cards = { tarot } }
  G.hand = { cards = {} }
  local c7, e7 = H("use_card")({ area = "consumeables", index = 1 })
  check("use_card needs hand target but no hand -> error", c7 == nil and type(e7) == "string")
  local planet = { ability = { consumeable = {} }, config = { center = { key = "c_planet" } } }
  G.consumeables = { cards = { planet } }
  local c_uc = H("use_card")({ area = "consumeables", index = 1 })
  local ok_uc, r_uc = pcall(c_uc)
  check("use_card no-target -> closure runs to a string", type(c_uc) == "function" and ok_uc and type(r_uc) == "string", r_uc)
end

do
  local SV = require("util.schema_validate")
  local sch = { type = "object", required = { "index" }, properties = {
    index = { type = "integer", minimum = 1 },
    area = { type = "string", enum = { "jokers", "consumeables" } },
  } }
  local ok1 = SV.validate_value(sch, { index = 2, area = "jokers" }, "parameters")
  check("schema valid payload -> true", ok1 == true)
  local ok2, e2 = SV.validate_value(sch, { area = "jokers" }, "parameters")
  check("schema missing required -> error", ok2 == false and type(e2) == "string" and e2:find("index") ~= nil)
  local ok3 = SV.validate_value(sch, { index = 1.5 }, "parameters")
  check("schema non-integer -> false", ok3 == false)
  local ok4 = SV.validate_value(sch, { index = 1, area = "shop" }, "parameters")
  check("schema enum violation -> false", ok4 == false)
  local ok5 = SV.validate_value(sch, { index = 0 }, "parameters")
  check("schema minimum bound -> false", ok5 == false)
end

-- ctx_helpers short_* must resolve lookup tables without nil-global crash
do
  local CH = require("context.ctx_helpers")
  check("short_value resolves rank", CH.short_value("Ace") == "A")
  check("short_value passthrough unknown", CH.short_value("Foo") == "Foo")
  check("short_suit resolves suit", CH.short_suit("Hearts") == "H")
  check("short_enh resolves enhancement", CH.short_enh({ ability = { enhancement = "m_gold" } }):find("Gold") ~= nil)
  check("short_seal resolves seal", CH.short_seal({ seal = "Red" }):find("Red") ~= nil)
end

-- formatted-card context build is the hot path that hid the short_* crash
do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = {
    { base = { value = "Ace", suit = "Hearts" }, ability = { enhancement = "m_gold" }, seal = "Red", config = { center = { key = "c" } } },
    { base = { value = "King", suit = "Spades" }, config = { center = { key = "c" } } },
  }, highlighted = {}, config = { card_limit = 8 } }
  local ok_build, ctx = pcall(function() return ContextCompact.build("SELECTING_HAND") end)
  check("context build does not crash formatting cards", ok_build, ctx)
  if ok_build then
    local blob = type(ctx) == "table" and (ctx.query or ctx.text or table.concat(ctx, "\n")) or tostring(ctx)
    check("context emits compact card code (AH)", blob:find("AH") ~= nil)
  end
end

-- RUN_SETUP detected via the live overlay, not the dead in_run_setup flag
do
  local State = require("core.state")
  G.STATES = { MENU = 1 }
  G.STATE = 1
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  check("RUN_SETUP reachable via overlay detector", State.get_state_name() == "RUN_SETUP")
  check("change_viewed_back is a RUN_SETUP action", A.get_state_action_set("RUN_SETUP")["change_viewed_back"] == true)
  -- run-setup force must always offer start_setup_run, never trap in a change_selected_back loop
  local f = D.get_force_for_state("RUN_SETUP")
  check("run-setup force offers start_setup_run (no deck-pick trap)", has((f or {}).actions, "start_setup_run"))
  G.STATES = { MENU = 1, GAME_OVER = 4 }; G.STATE = 4
  check("GAME_OVER + open run-setup overlay resolves to RUN_SETUP", State.get_state_name() == "RUN_SETUP")
  check("GAME_OVER-hosted run-setup force offers start_setup_run",
    has((D.get_force_for_state(State.get_state_name()) or {}).actions, "start_setup_run"))
  -- regression: gate on the resolved state_name, not a live overlay probe, or the RUN_SETUP force serves forever in BLIND_SELECT (start_setup_run rejected every frame)
  G.STATES = { MENU = 1, BLIND_SELECT = 7 }; G.STATE = 7
  local ok_bs, fbs = pcall(D.get_force_for_state, "BLIND_SELECT")
  check("BLIND_SELECT with a lingering run-setup overlay does NOT serve the RUN_SETUP force",
    not (ok_bs and has((fbs or {}).actions, "start_setup_run")))
  G.STATES = { MENU = 1 }; G.STATE = 1
  G.OVERLAY_MENU = nil
  check("no overlay -> not RUN_SETUP", State.get_state_name() ~= "RUN_SETUP")
  G.STATES = nil; G.STATE = nil
end

-- pack picks gate consumable-slot capacity, not just joker slots
do
  local CU = require("facts.card_util")
  local tarot = { ability = { set = "Tarot" }, config = { center = { key = "c_tarot" } } }
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  check("Tarot not takeable when consumables full", CU.can_take_pack_card(tarot) == false)
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  check("Tarot takeable when consumable space", CU.can_take_pack_card(tarot) == true)

  local H = D.get_action_handler
  mock_state("Normal", "SELECTING_HAND")
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  G.pack_cards = { cards = { tarot } }
  G.booster_pack = G.pack_cards
  local c, e = H("use_card")({ area = "pack_cards", index = 1 })
  check("use_card rejects full-consumable pack pick with consumable message",
    c == nil and type(e) == "string" and e:find("consumable") ~= nil, e)
  G.pack_cards = nil; G.booster_pack = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local jA = { ability = { set = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } }, sell_cost = 3 }
  local jB = { ability = { set = "Joker" }, config = { center = { key = "j_blueprint", set = "Joker" } }, sell_cost = 3 }
  G.jokers = { cards = { jA, jB }, config = { card_limit = 5 } }
  local fp1 = ContextCompact.decision_fingerprint("SELECTING_HAND")
  G.jokers.cards = { jB, jA }
  local fp2 = ContextCompact.decision_fingerprint("SELECTING_HAND")
  check("set_joker_order changes decision fingerprint", fp1 ~= fp2)
end

do
  local Enforce = require("core.enforce")
  G.STATES = { SHOP = 5 }; G.STATE = 5
  G.GAME = G.GAME or {}
  G.GAME.dollars = 6
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.reroll_cost = 3
  G.NEURO.force_inflight = true
  G.NEURO.force_state = "SHOP"
  G.NEURO.force_action_set = { reroll_shop = true, buy_from_shop = true }
  local reroll_blocked = false
  for _ = 1, 8 do
    if not Enforce.pre_action(nil, "reroll_shop") then reroll_blocked = true break end
  end
  check("forced reroll_shop spam is repeat-capped", reroll_blocked)
  local buy_blocked = false
  for _ = 1, 5 do
    if not Enforce.pre_action(nil, "buy_from_shop") then buy_blocked = true break end
  end
  check("forced buy_from_shop not throttled at 5 (generous cap)", not buy_blocked)
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_action_set = nil
  G.STATES = nil; G.STATE = nil
end

-- all-debuffed hands are dropped entirely (score 0), not just flagged as duds
do
  mock_state("Normal", "SELECTING_HAND")
  local dh1 = card("5", "Hearts"); dh1.debuff = true
  local dh2 = card("5", "Spades"); dh2.debuff = true
  G.hand = { cards = { dh1, dh2, card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, dh2 }, ["High Card"] = { dh1 } }, { dh1, dh2 }, nil
  end
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("all-debuffed Ready hand dropped (scores 0)", q:find("Ready:[^\n]*Pair") == nil, q:match("Ready:[^\n]*") or "(no Ready line)")
  check("debuffed-card count surfaced", q:find("DEBUFFED") ~= nil)

  local pd = card("5", "Diamonds")
  G.hand = { cards = { dh1, pd, card("9", "Clubs") }, highlighted = {} }
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, pd }, ["High Card"] = { dh1 } }, { dh1, pd }, nil
  end
  local qp = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("partial-debuff Ready hand kept + annotated", qp:find("Pair%[[%d,]+%][^,]*%(1 debuffed") ~= nil, qp:match("Ready:[^\n]*"))
  G.FUNCS.get_poker_hand_info = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local cl = {}
  for _, r in ipairs({ "2", "5", "7", "9" }) do local c = card(r, "Clubs"); c.debuff = true; cl[#cl + 1] = c end
  G.hand = { cards = { cl[1], cl[2], cl[3], cl[4], card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = nil
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("debuffed-suit near-Flush not advertised in Close", q:find("near Flush") == nil, q:match("Close:[^\n]*") or "(no Close line)")
end

-- Ready/Close must respect The Mouth/Eye/Psychic boss rules (previously lured by hands the boss forbids)
do
  mock_state("Normal", "SELECTING_HAND")
  local c5a, c5b = card("5", "Hearts"), card("5", "Spades")
  local c9a, c9b = card("9", "Clubs"), card("9", "Diamonds")
  local ck = card("K", "Hearts")
  G.hand = { cards = { c5a, c5b, c9a, c9b, ck }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 },
                   ["Two Pair"] = { visible = true, level = 1, chips = 20, mult = 2, played = 0 } }
  G.FUNCS.get_poker_hand_info = function(cards)
    local by, order = {}, {}
    for _, c in ipairs(cards) do
      local r = c.base.value
      if not by[r] then by[r] = {}; order[#order + 1] = r end
      table.insert(by[r], c)
    end
    table.sort(order)
    local cores = {}
    for _, r in ipairs(order) do if #by[r] >= 2 then cores[#cores + 1] = { by[r][1], by[r][2] } end end
    local ph = {}
    for _, k in ipairs({ "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush",
      "Full House", "Four of a Kind", "Straight Flush", "Five of a Kind", "Flush House", "Flush Five" }) do ph[k] = {} end
    ph["High Card"] = { cards[1] }
    local text = "High Card"
    if #cores >= 2 then
      text = "Two Pair"; local tp = {}
      for _, pc in ipairs(cores) do for _, c in ipairs(pc) do tp[#tp + 1] = c end end
      ph["Two Pair"] = { tp }; ph["Pair"] = { cores[1] }
    elseif #cores == 1 then text = "Pair"; ph["Pair"] = { cores[1] } end
    return text, nil, ph, cards, nil
  end
  -- check_only=true must be side-effect-free (mirrors the game's own check-then-commit split)
  local function boss(name, debuff, hands, only_hand)
    return { name = name, disabled = false, debuff = debuff or {}, hands = hands, only_hand = only_hand,
      debuff_hand = function(self, cards, hand, handname, check_only)
        if self.disabled then return end
        if self.debuff then
          if self.debuff.h_size_ge and #cards < self.debuff.h_size_ge then return true end
          if self.debuff.h_size_le and #cards > self.debuff.h_size_le then return true end
          if self.name == "The Eye" then
            if self.hands[handname] then return true end
            if not check_only then self.hands[handname] = true end
          elseif self.name == "The Mouth" then
            if self.only_hand and self.only_hand ~= handname then return true end
            if not check_only then self.only_hand = handname end
          end
        end
      end }
  end
  local HF = require("facts.hand_facts")

  G.GAME.blind = boss("The Mouth", {}, nil, "Pair")
  local m = HF.summary()
  check("Mouth locked: off-type Two Pair dropped from Ready", m:find("Two Pair%[") == nil, m:match("Ready:[^\n]*"))
  check("Mouth locked: on-type Pair kept in Ready", m:find("Pair%[1,2%]") ~= nil, m:match("Ready:[^\n]*"))
  check("Mouth locked: Close (off-type) suppressed", m:find("Close:") == nil, m)
  check("Mouth locked: restriction note present", m:find("only Pair scores") ~= nil, m)

  G.GAME.blind = boss("The Mouth", {}, nil, false)
  local mu = HF.summary()
  check("Mouth unlocked: nothing dropped yet (both Ready)", mu:find("Two Pair%[") ~= nil and mu:find("Pair%[1,2%]") ~= nil)
  check("Mouth unlocked: teaching note present", mu:find("first hand type you play locks") ~= nil, mu)

  G.GAME.blind = boss("The Eye", {}, { ["Two Pair"] = true }, nil)
  local e = HF.summary()
  check("Eye: already-used Two Pair dropped from Ready", e:find("Two Pair%[") == nil, e:match("Ready:[^\n]*"))
  check("Eye: unused Pair kept in Ready", e:find("Pair%[1,2%]") ~= nil)
  check("Eye: used-types listed in note", e:find("Already used") ~= nil and e:find("Two Pair") ~= nil, e)

  G.GAME.blind = boss("The Psychic", { h_size_ge = 5 })
  local p = HF.summary()
  check("Psychic: size rule does NOT drop a paddable Pair", p:find("Pair%[1,2%]") ~= nil, p:match("Ready:[^\n]*"))
  check("Psychic: size rule keeps Two Pair too", p:find("Two Pair%[") ~= nil, p:match("Ready:[^\n]*"))
  check("Psychic: size-rule note present", p:find("at least 5 cards") ~= nil, p)

  G.GAME.blind = nil
  G.FUNCS.get_poker_hand_info = nil
end

do
  local DF = require("facts.debuff_facts")
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3

  G.GAME.blind = { name = "The Serpent", disabled = false, debuff = {} }
  check("Serpent play-note surfaced", (HF.summary() or ""):find("The Serpent") ~= nil)
  G.GAME.blind = { name = "The Arm", disabled = false, debuff = {} }
  check("Arm play-note surfaced", (HF.summary() or ""):find("lowers that hand type's level") ~= nil)
  G.GAME.blind = { name = "Verdant Leaf", disabled = false, debuff = {} }
  check("Verdant Leaf sell-a-joker note surfaced", (HF.summary() or ""):find("SELL a joker") ~= nil)

  G.hand.cards[2].ability = { forced_selection = true }
  G.GAME.blind = { name = "Cerulean Bell", disabled = false, debuff = {} }
  check("forced_selection_index finds locked card", DF.forced_selection_index() == 2)
  check("Cerulean note names the locked index", (HF.summary() or ""):find("card 2 is force%-selected") ~= nil)

  local CtxHand = require("context.ctx_hand")
  check("LOCK token on the forced card", CtxHand.card_token(G.hand.cards[2], true):find("LOCK") ~= nil)
  check("no LOCK token on a free card", CtxHand.card_token(G.hand.cards[1], true):find("LOCK") == nil)

  local H = D.get_action_handler
  local c_omit, e_omit = H("play_hand")({ indices = { 1, 3 } })
  check("play omitting locked card rejected", c_omit == nil and type(e_omit) == "string" and e_omit:find("force%-selected") ~= nil, e_omit)
  local c_ok = H("play_hand")({ indices = { 1, 2, 3 } })
  check("play including locked card accepted", type(c_ok) == "function")
  local c_disc, e_disc = H("discard_hand")({ indices = { 1 } })
  check("discard omitting locked card rejected", c_disc == nil and type(e_disc) == "string", e_disc)

  G.hand.cards[2].ability = nil
  G.GAME.blind = nil
end

-- affordability floor is G.GAME.bankrupt_at (Credit Card -$20); reservations are synchronous
do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  local function shop_item(c) local it = card("A", "Spades"); it.cost = c; return it end

  G.jokers = { cards = {} }; G.GAME.dollars = 0; G.GAME.bankrupt_at = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  local b0, e0 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy with $0 rejected (floor $0)", b0 == nil and type(e0) == "string")

  G.GAME.dollars = 5; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5), shop_item(5) } }
  local b1 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("first buy passes and reserves $5", type(b1) == "function" and (tonumber(G.NEURO.reserved_dollars) or 0) == 5)
  local b2, e2 = H("buy_from_shop")({ area = "shop_jokers", index = 2 })
  check("second rapid buy rejected (reserved-aware)", b2 == nil and type(e2) == "string")

  G.GAME.bankrupt_at = -20
  G.GAME.dollars = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  check("Credit Card allows buying into debt (floor -$20)", type(H("buy_from_shop")({ area = "shop_jokers", index = 1 })) == "function")
  G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(25) } }
  local b3, e3 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("Credit Card caps debt at -$20 ($25 rejected)", b3 == nil and type(e3) == "string")

  G.jokers = { cards = {} }; G.NEURO.reserved_dollars = 0
end

do
  local DF = require("facts.debuff_facts")
  local d1 = card("5", "Hearts"); d1.debuff = true
  local d2 = card("5", "Spades"); d2.debuff = true
  local ok3 = card("9", "Clubs")
  check("debuff_facts.count", DF.count({ d1, d2, ok3 }) == 2)
  check("debuff_facts.all_debuffed true", DF.all_debuffed({ d1, d2 }) == true)
  check("debuff_facts.all_debuffed false (mixed)", DF.all_debuffed({ d1, ok3 }) == false)
end

-- get_round_history handles integer hands_played; card_modifiers reads per-card not G.GAME.edition
do
  local Ctx = require("context.context")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_played = 3        -- integer counter, not a list
  G.GAME.current_round.discards_used = 0
  G.GAME.round = 1
  local ok_rh, rh = pcall(Ctx.get_round_history)
  check("get_round_history no crash on integer hands_played", ok_rh, rh)
  if ok_rh then check("round_history shows hands-played count", table.concat(rh, "\n"):find("Hands played this round: 3") ~= nil) end

  local ed = card("A", "Spades"); ed.edition = { name = "Foil" }
  G.GAME.edition = nil  -- prove we don't read this
  G.hand = { cards = { ed, card("2", "Hearts") } }
  G.deck = { cards = {} }
  local cm = Ctx.get_card_modifiers()
  check("card_modifiers reports per-card edition", table.concat(cm, "\n"):find("Foil") ~= nil, table.concat(cm, "\n"))

  -- old code scanned only hand+draw, undercounting modifiers on cards in the play/discard piles
  local ed2 = card("K", "Diamonds"); ed2.edition = { name = "Polychrome" }
  G.playing_cards = { ed2, card("3", "Clubs") }
  G.hand = { cards = { card("2", "Hearts") } }   -- ed2 is NOT in hand
  G.deck = { cards = {} }
  local cm2 = Ctx.get_card_modifiers()
  check("card_modifiers scans full deck (playing_cards), not just hand+draw",
    table.concat(cm2, "\n"):find("Polychrome") ~= nil, table.concat(cm2, "\n"))
  G.playing_cards = nil
end

-- deck-name localization: describe_deck resolves DECK_INFO by the stable engine key, so a localized display name still gets the detailed description
do
  local DeckFacts = require("facts.deck_facts")
  G.P_CENTERS = { b_red = { key = "b_red", loc_txt = { name = "Czerwona Talia" } } }
  local desc = DeckFacts.describe_deck({ key = "b_red" })
  check("deck info resolves by key under a non-English display name",
    desc ~= nil and desc:find("discard", 1, true) ~= nil, tostring(desc))
  G.P_CENTERS = nil
end

do
  local FH = require("force.force_helpers")
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
  check("warning empty with no failure", FH.failed_action_warning() == "")
  G.NEURO.last_failed_action = "use_card"
  G.NEURO.last_failed_reason = "the consumable could not be used"
  local w = FH.failed_action_warning()
  check("warning names the action", w:find("use_card") ~= nil, w)
  check("F9: warning carries last_failed_reason", w:find("the consumable could not be used") ~= nil, w)

  mock_state("Small blind selectable", "BLIND_SELECT")
  local okb, rb = pcall(require("force.force_blind_select").build, "")
  check("F8: BLIND_SELECT force prepends failure warning",
    okb and type(rb) == "table" and tostring(rb.query):find("use_card") ~= nil, okb and rb and rb.query)

  local okp, rp = pcall(require("force.force_pack").build, "", "TAROT_PACK")
  check("F8: PACK force prepends failure warning",
    okp and type(rp) == "table" and tostring(rp.query):find("Previous action rejected") ~= nil, okp and rp and rp.query)
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
end

do
  local State = require("core.state")
  local HH = require("handlers.hand_handlers")
  local CA = require("facts.card_area_util")

  -- under Four Fingers a 4-suit is a Flush not Near Flush, matching the engine
  _G.SMODS = { four_fingers = function(t) return (t == "flush" or t == "straight") and 4 or 5 end }
  mock_state("Normal", "SELECTING_HAND")
  local hh = { card("2", "Hearts"), card("5", "Hearts"), card("9", "Hearts"), card("K", "Hearts"), card("3", "Clubs") }
  G.hand = { cards = hh, highlighted = {}, config = { card_limit = 8 } }
  local st = State.build()
  local ph = (st and st.hand_analysis and st.hand_analysis.potential_hands) or {}
  check("F18: Four Fingers makes a 4-suit a Flush (not Near)", has(ph, "Flush") and not has(ph, "Near Flush"), table.concat(ph, ","))
  _G.SMODS = nil
  local st2 = State.build()
  local ph2 = (st2 and st2.hand_analysis and st2.hand_analysis.potential_hands) or {}
  check("F18: default (no four_fingers) 4-suit stays Near Flush", has(ph2, "Near Flush") and not has(ph2, "Flush"), table.concat(ph2, ","))

  -- h_size_le (max played cards) enforced at commit, mirroring h_size_ge
  mock_state("Normal", "SELECTING_HAND")
  local cc = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Hearts"), card("5", "Hearts") }
  G.hand = { cards = cc, highlighted = { cc[1], cc[2], cc[3], cc[4] } }
  G.GAME.current_round.hands_left = 3
  G.GAME.blind = { debuff = { h_size_le = 3 } }
  local fn_over, err_over = HH.handle_play_hand({ indices = { 1, 2, 3, 4 } })
  check("F11: h_size_le rejects oversized play", fn_over == nil and type(err_over) == "string" and err_over:find("at most 3") ~= nil, err_over)
  check("F11: h_size_le allows a play within the limit", type(HH.handle_play_hand({ indices = { 1, 2, 3 } })) == "function")
  G.GAME.blind = nil

  -- normalize_indices honors G.hand.config.highlighted_limit, not a hardcoded 5
  G.hand = { cards = {}, config = { highlighted_limit = 8 } }
  for i = 1, 9 do G.hand.cards[i] = card("2", "Hearts") end
  check("F14: highlighted_limit>5 honored", #CA.normalize_indices({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, 9) == 8)
  G.hand = nil
  check("F14: default cap 5 with no hand config", #CA.normalize_indices({ 1, 2, 3, 4, 5, 6, 7 }, 7) == 5)

  check("F15: blind_select_signature removed", require("force.force_helpers").blind_select_signature == nil)

  -- _enforce_budget no longer drops sections or emits DROPPED markers, despite the name
  local big = string.rep("x", 1900)
  local out16 = ContextCompact._enforce_budget("SELECTING_HAND",
    { "CTX:x", "STATE:SELECTING_HAND", "L:" .. big, "J:" .. big }, "volatile")
  local blob16 = table.concat(out16, "\n")
  check("F16: no lossy dropping (L + J both survive)",
    blob16:find("\nL:xx", 1, true) ~= nil and blob16:find("\nJ:xx", 1, true) ~= nil)
  check("F16: no DROPPED marker emitted", blob16:find("DROPPED:", 1, true) == nil, blob16:sub(1, 80))

  local pad = string.rep("x", 1600)
  local out_shop = ContextCompact._enforce_budget("SHOP",
    { "STATE:SHOP", "SH:x", "I:x", "LA:x", "J:" .. pad, "C:" .. pad, "L:" .. pad }, "volatile")
  local blob_shop = table.concat(out_shop, "\n")
  check("SHOP: full context kept -- J, C, L all survive, no DROPPED",
    blob_shop:find("\nJ:xx", 1, true) and blob_shop:find("\nC:xx", 1, true)
      and blob_shop:find("\nL:xx", 1, true) and blob_shop:find("DROPPED:", 1, true) == nil,
    blob_shop:sub(1, 60))

  local LD = require("util.level_delta")
  local msg0, snap0 = LD.compute({ Pair = { level = 1 }, Flush = { level = 1 } }, nil)
  check("F3: first snapshot emits nothing", msg0 == nil and snap0.Pair == 1)
  local msg1, snap1 = LD.compute({ Pair = { level = 3 }, Flush = { level = 1 } }, snap0)
  check("F3: level raise reported once", msg1 ~= nil and msg1:find("Pair L1%->L3") ~= nil, msg1)
  local msg2 = LD.compute({ Pair = { level = 3 }, Flush = { level = 1 } }, snap1)
  check("F3: unchanged levels stay silent", msg2 == nil)
end

do
  local CardUtil = require("facts.card_util")
  local CtxEconomy = require("context.ctx_economy")
  local HandFacts = require("facts.hand_facts")
  local DebuffFacts = require("facts.debuff_facts")

  -- editions read flag-first; vanilla editions have no .name
  check("edition_name Foil (flag)", CardUtil.edition_name({ foil = true }) == "Foil")
  check("edition_name Negative (flag)", CardUtil.edition_name({ negative = true }) == "Negative")
  check("edition_name Polychrome (flag)", CardUtil.edition_name({ polychrome = true }) == "Polychrome")
  check("edition_name nil when none", CardUtil.edition_name({}) == nil)
  check("enhancement_name m_bonus", CardUtil.enhancement_name("m_bonus") == "Bonus")
  check("enhancement_short m_bonus", CardUtil.enhancement_short("m_bonus") == "Bonus(+30c)")
  check("seal_name Red", CardUtil.seal_name("Red") == "Red")

  -- state.lua safe_card must expose a flagged edition, not nil
  mock_state("Normal", "SELECTING_HAND")
  local State = require("core.state")
  G.STATES = { SELECTING_HAND = 1 }; G.STATE = 1
  local jk = { ability = { set = "Joker" }, config = { center = { key = "j_x" } }, edition = { negative = true } }
  G.jokers = { cards = { jk }, config = { card_limit = 5 } }
  local st = State.build()
  local jdet = st and st.jokers and st.jokers[1]
  check("H1: structured joker edition not blind to Negative", jdet and jdet.edition == "Negative", jdet and tostring(jdet.edition))
  G.jokers = nil

  mock_state("Normal", "SHOP")
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 3; G.GAME.bankrupt_at = 0
  check("spend_floor $0 no credit", CtxEconomy.spend_floor() == 0)
  check("spendable = dollars-reserved-floor", CtxEconomy.spendable() == 7)
  G.GAME.bankrupt_at = -20
  check("spend_floor -20 with Credit Card", CtxEconomy.spend_floor() == -20)
  check("spendable extends by credit", CtxEconomy.spendable() == 27)
  G.GAME.bankrupt_at = 0
  G.jokers = { cards = { { config = { center = { key = "j_credit_card" } }, ability = { name = "Credit Card" } } } }
  check("spend_floor detects live spawned Credit Card", CtxEconomy.spend_floor() == -20)
  G.jokers = nil
  G.GAME.dollars = -8; G.GAME.interest_amount = 1; G.GAME.interest_cap = 25
  check("L1: interest never negative under debt", CtxEconomy.calc_interest(G.GAME.dollars) == 0)
  G.GAME.dollars = 10

  local five_h = { card("2","Hearts"), card("5","Hearts"), card("9","Hearts"), card("K","Hearts"), card("3","Hearts") }
  local sh5 = HandFacts.shape(five_h)
  check("H2: 5-suit is flush_ready (default thr 5)", sh5.flush_ready and not sh5.near_flush)
  local four_h = { card("2","Hearts"), card("5","Hearts"), card("9","Hearts"), card("K","Hearts"), card("3","Clubs") }
  local sh4 = HandFacts.shape(four_h)
  check("H2: 4-suit is near_flush (default thr 5)", sh4.near_flush and not sh4.flush_ready)

  -- Shortcut joker: max_run bridges single-rank gaps (step of 2), so a gap-2 spread is a made straight.
  local gap = { card("2","Hearts"), card("4","Clubs"), card("6","Spades"), card("8","Diamonds"), card("10","Hearts") }
  _G.SMODS = { shortcut = function() return true end }
  local sh_sc = HandFacts.shape(gap)
  check("H2b: Shortcut makes 2-4-6-8-10 straight_ready", sh_sc.straight_ready, "max_run=" .. tostring(sh_sc.max_run))
  _G.SMODS = nil
  local sh_no = HandFacts.shape(gap)
  check("H2b: without Shortcut, 2-4-6-8-10 is neither straight nor near", not sh_no.straight_ready and not sh_no.near_straight, "max_run=" .. tostring(sh_no.max_run))

  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = {
    ["Flush"]    = { visible = true, level = 3, chips = 35, mult = 7 },
    ["Pair"]     = { visible = true, level = 1, chips = 10, mult = 2 },
    ["Straight"] = { visible = false, level = 1, chips = 30, mult = 4 },
  }
  local rows = HandFacts.levels()
  check("levels() drops non-visible", #rows == 2)
  check("levels() sorted play-order (Pair before Flush)", rows[1].name == "Pair" and rows[2].name == "Flush")

  check("boss_debuff_text via engine method",
    DebuffFacts.boss_debuff_text({ get_loc_debuff_text = function() return "No face cards" end }) == "No face cards")
  check("boss_debuff_text via loc_txt fallback",
    DebuffFacts.boss_debuff_text({ loc_txt = { text = { "a", "b" } } }) == "a b")
  check("boss_debuff_text empty when nothing", DebuffFacts.boss_debuff_text({}) == "")
end

do
  local CardUtil = require("facts.card_util")
  local CtxEconomy = require("context.ctx_economy")
  local FH = require("force.force_helpers")

  G.TIMERS = { REAL = 42 }
  check("R1: Utils.now prefers G.TIMERS.REAL", Utils.now() == 42)
  G.TIMERS = nil

  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
  FH.record_failure("buy_from_shop", "the purchase could not be completed")
  check("R4: record_failure sets action", G.NEURO.last_failed_action == "buy_from_shop")
  check("R4: record_failure sets reason (was dropped)", G.NEURO.last_failed_reason == "the purchase could not be completed")
  check("R4: record_failure sets at", type(G.NEURO.last_failed_at) == "number")
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil

  mock_state("Normal", "SHOP")
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 8; G.jokers = { cards = {}, config = { card_limit = 5 } }
  local cheap = { cost = 3, config = { center = { set = "Joker" } } }
  check("R5: reserved dollars block a nominally-cheap buy", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == false)
  G.NEURO.reserved_dollars = 0
  check("R5: affordable + space => ok", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == true)
  G.jokers = { cards = { {}, {}, {}, {}, {} }, config = { card_limit = 5 } }
  check("R5: no joker slot => not ok even if affordable", CtxEconomy.item_afford_status(cheap, "shop_jokers").ok == false)
  G.jokers = nil

  -- edition_tag is flag-aware and must not drop Negative
  check("R6: edition_tag Foil", CardUtil.edition_tag({ foil = true }) == "Foil(+50c)")
  check("R6: edition_tag Negative (was dropped)", CardUtil.edition_tag({ negative = true }) == "Negative(free_slot)")
  check("R6: edition_tag empty when none", CardUtil.edition_tag({}) == "")

  check("R7: hand_visible true", require("facts.hand_facts").hand_visible({ visible = true }) == true)
  check("R7: hand_visible nil => false", require("facts.hand_facts").hand_visible({}) == false)

  local CtxHelpers = require("context.ctx_helpers")
  local ep = CtxHelpers.effect_parts({ x_mult = 2, h_mult = 4, t_mult = 3 })
  check("R2: effect_parts formats x_mult", ep[1] == "x2 Mult")
  check("R2: effect_parts t_mult => hand-type conditional, not per-trigger", table.concat(ep, "|"):find("+3 Mult%(conditional%)") ~= nil and table.concat(ep, "|"):find("/trigger") == nil)
  check("R2: effect_parts skips identity x_mult=1", #CtxHelpers.effect_parts({ x_mult = 1 }) == 0)

  G.NEURO.force_inflight = true; G.NEURO.force_state = "X"; G.NEURO.force_action_names = {}
  G.NEURO.force_action_set = {}; G.NEURO.force_sent_at = 1
  FH.clear_force_state()
  check("R8: clear_force_state clears inflight", G.NEURO.force_inflight == false and G.NEURO.force_state == nil
    and G.NEURO.force_action_names == nil and G.NEURO.force_action_set == nil and G.NEURO.force_sent_at == nil)

  local mn, mx = CardUtil.consumable_target_range({ ability = { consumeable = { max_highlighted = 2 } } })
  check("R9: target range min defaults to 1", mn == 1 and mx == 2)
  check("R9: no consumeable => nil range", select("#", CardUtil.consumable_target_range({})) >= 1 and (CardUtil.consumable_target_range({})) == nil)

  G.jokers = { cards = { {}, {} }, config = { card_limit = 5 } }
  local jss = CardUtil.joker_slot_status()
  check("R10: joker_slot_status", jss.count == 2 and jss.limit == 5 and jss.full == false)
  G.jokers = nil

  check("R26: NON_PROGRESS includes an info action", require("core.action_policy").NON_PROGRESS.scoring_explanation == true)
  check("R26: NON_PROGRESS includes a non-advancing action", require("core.action_policy").NON_PROGRESS.set_joker_order == true)

  G.NEURO.once_serials = nil
  check("R19: once_until first true", FH.once_until("t", 1) == true)
  check("R19: once_until same epoch false", FH.once_until("t", 1) == false)
  check("R19: once_until new epoch true", FH.once_until("t", 2) == true)

  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5","Hearts"), card("5","Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local list16, set16 = FH.collect_actions({ "joker_info", "help" })
  check("R16: collect_actions excludes invalid (no jokers)", set16.joker_info ~= true)
  check("R16: collect_actions returns exactly {help}", #list16 == 1 and list16[1] == "help" and set16.help == true,
    table.concat(list16, ","))
  G.jokers = nil

  local DeckFacts = require("facts.deck_facts")
  check("R13: DECK_INFO has curated Plasma formula", (DeckFacts.DECK_INFO["Plasma Deck"] or ""):find("chips%+mult") ~= nil)
  check("R13: short_desc from config flags", (DeckFacts.short_desc({ config = { discards = 1 } }) or ""):find("discard") ~= nil)
end

do
  local Info = require("handlers.info_handlers")
  mock_state("Normal", "SELECTING_HAND")
  local h = { card("5","Hearts"), card("5","Spades"), card("9","Clubs") }
  G.hand = { cards = h, highlighted = {} }
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2 } }
  G.FUNCS.get_poker_hand_info = function(sel) return "Pair", nil, { Pair = sel }, { sel[1], sel[2] }, nil end
  local c = Info.handle_simulate_hand({ indices = { 1, 2 } })
  local ok_s, r_s = pcall(c)
  check("simulate_hand(indices) works with nothing highlighted", type(c) == "function" and ok_s and r_s:find("Pair") ~= nil, r_s)
  local c0, e0 = Info.handle_simulate_hand({ indices = {} })
  check("simulate_hand no indices + no highlight -> error", c0 == nil and type(e0) == "string")
  G.FUNCS.get_poker_hand_info = nil
end

-- all_debuffed accepts the engine's nested card-group shape, not just a flat list
do
  local DF = require("facts.debuff_facts")
  local d1 = card("5", "Hearts"); d1.debuff = true
  local d2 = card("5", "Spades"); d2.debuff = true
  local ok3 = card("9", "Clubs")
  check("all_debuffed nested: all-debuffed group detected", DF.all_debuffed({ { d1, d2 } }) == true)
  check("all_debuffed nested: mixed group not flagged", DF.all_debuffed({ { d1, ok3 } }) == false)
  check("all_debuffed nested: multiple groups all debuffed", DF.all_debuffed({ { d1 }, { d2 } }) == true)
end

-- vouchers/boosters route via use_card: buy_from_shop double-charges in Card:open/redeem
do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local called, captured_id, use_called
  G.FUNCS.buy_from_shop = function(e) called = true; captured_id = e.config.id end
  G.FUNCS.use_card = function(e) use_called = true end

  local voucher = { cost = 5, ability = { set = "Voucher" }, config = { center = { key = "v_overstock" } } }
  G.shop_vouchers = { cards = { voucher } }
  local cv = H("buy_from_shop")({ area = "shop_vouchers", index = 1 })
  check("voucher buy -> exec closure", type(cv) == "function")
  if cv then pcall(cv) end
  check("voucher routed via use_card, not buy_from_shop", use_called == true and called == nil)

  use_called = nil
  G.NEURO.reserved_dollars = 0
  local pack = { cost = 4, ability = { set = "Booster" }, config = { center = { key = "p_arcana" } } }
  G.shop_booster = { cards = { pack } }
  local cb = H("buy_from_shop")({ area = "shop_booster", index = 1 })
  if cb then pcall(cb) end
  check("booster routed via use_card, not buy_from_shop", use_called == true and called == nil)

  called, captured_id = nil, nil
  G.NEURO.reserved_dollars = 0
  local plain = card("A", "Spades"); plain.cost = 5
  G.shop_jokers = { cards = { plain } }
  local cj = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  if cj then pcall(cj) end
  check("plain buy carries no buy_and_use id", called == true and captured_id == nil)

  G.NEURO.reserved_dollars = 0
  local tarot = { cost = 5, ability = { set = "Tarot", consumeable = { max_highlighted = 1 } }, config = { center = { key = "c_tarot" } } }
  G.shop_jokers = { cards = { tarot } }
  local ct, et = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true })
  check("X6: hand-targeting consumable use=true rejected", ct == nil and type(et) == "string" and et:find("targets hand") ~= nil, et)

  called, captured_id = nil, nil
  local planet = { cost = 5, ability = { set = "Planet", consumeable = {} }, config = { center = { key = "c_pluto" } } }
  G.shop_jokers = { cards = { planet } }
  local cp = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true })
  check("Planet use=true accepted", type(cp) == "function")
  if cp then pcall(cp) end
  check("Planet use=true routed with id=buy_and_use", called == true and captured_id == "buy_and_use")
  G.FUNCS.buy_from_shop = nil
  G.FUNCS.use_card = nil
  G.NEURO.reserved_dollars = 0
end

do
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = { bl_small = { name = "Small Blind" }, bl_custom_small = { name = "Custom Small" } }
  G.GAME.round_resets.blind_choices = { Small = "bl_custom_small" }
  local captured
  G.FUNCS.select_blind = function(e) captured = e.config.ref_table end
  local c1 = H("select_blind")({ blind = "small" })
  local ok1, r1 = pcall(c1)
  check("select_blind resolves blind_choices override", type(c1) == "function" and ok1 and captured == G.P_BLINDS.bl_custom_small, r1)
  check("select_blind names the custom blind", ok1 and type(r1) == "string" and r1:find("Custom Small") ~= nil, r1)
  captured = nil
  G.GAME.round_resets.blind_choices = nil
  local c2 = H("select_blind")({ blind = "small" })
  if c2 then pcall(c2) end
  check("select_blind falls back to bl_small", captured == G.P_BLINDS.bl_small)
  G.FUNCS.select_blind = nil
  G.P_BLINDS = nil
end

do
  local J = require("util.neuro_json")
  local ok_arr = pcall(J.decode, '[1,null,3]')
  check("M35: null in array errors", ok_arr == false)
  local ok_obj, obj = pcall(J.decode, '{"a":null}')
  check("M35: null object value drops the key", ok_obj and type(obj) == "table" and obj.a == nil and next(obj) == nil)
  check("M35: dense array encodes as array", J.encode({ 1, 2, 3 }) == "[1,2,3]")
  local rt = J.decode(J.encode({ 10, 20, 30 }))
  check("M35: dense array round-trips as array", type(rt) == "table" and #rt == 3 and rt[1] == 10 and rt[3] == 30)
  local sp = J.encode({ [1] = "a", [3] = "c" })
  check("M35: sparse integer table encodes as object", sp:sub(1, 1) == "{" and sp:find('"3":"c"', 1, true) ~= nil, sp)
end

-- F-001: cooldown denials don't advance the streak; success doesn't reset it (only a state/action-name change does)
do
  local Enforce = require("core.enforce")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.NEURO.force_inflight = nil; G.NEURO.force_state = nil; G.NEURO.force_action_set = nil
  G.STATES = { SELECTING_HAND = 7 }; G.STATE = 7
  Enforce.post_action(nil, false)  -- neutral warm-up; does not touch the streak
  G.TIMERS = { REAL = 1000 }
  local ok1 = Enforce.pre_action(nil, "help")
  check("H18: first spaced attempt passes", ok1 == true)
  local cooldown_denied = 0
  for i = 1, 6 do
    G.TIMERS.REAL = 1000 + i * 0.01
    local ok, err = Enforce.pre_action(nil, "help")
    if ok == false and type(err) == "string" and err:find("wait") then cooldown_denied = cooldown_denied + 1 end
  end
  check("H18: rapid retries all cooldown-denied (never repeat-capped)", cooldown_denied == 6)
  G.TIMERS.REAL = 1100
  local ok2 = Enforce.pre_action(nil, "help")
  G.TIMERS.REAL = 1200
  local ok3 = Enforce.pre_action(nil, "help")
  check("H18: spaced attempts still pass (streak untouched by denials)", ok2 == true and ok3 == true)
  G.TIMERS.REAL = 1300
  local ok4, e4 = Enforce.pre_action(nil, "help")
  check("H18: 4th committed repeat hits the cap", ok4 == false and type(e4) == "string" and e4:find("repeated") ~= nil, e4)
  Enforce.post_action(nil, true)
  G.TIMERS.REAL = 1400
  local ok5 = Enforce.pre_action(nil, "help")
  check("H18: post_action(true) does NOT reset the streak (still capped)", ok5 == false)
  G.TIMERS.REAL = 1500
  check("H18: a different action passes (streak resets on name change)",
    Enforce.pre_action(nil, "quick_status") == true)
  G.TIMERS.REAL = 1600
  check("H18: original action passes again after the streak-breaker",
    Enforce.pre_action(nil, "help") == true)
  G.TIMERS = nil; G.STATES = nil; G.STATE = nil
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs"), card("Queen", "Hearts"), card("Queen", "Diamonds") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[1], hc[2], hc[3], hc[6], hc[7] } },
      ["Pair"] = { { hc[6], hc[7] } },
    }, { hc[1], hc[2], hc[3], hc[6], hc[7] }, nil
  end
  local s = HF.summary()
  check("ready indices: Full House[1,2,3,6,7]", s:find("Full House[1,2,3,6,7]", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("ready indices: Pair[6,7]", s:find("Pair[6,7]", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("force query carries ready indices", q:find("Full House[1,2,3,6,7]", 1, true) ~= nil)

  local foreign = card("2", "Spades")
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { ["Pair"] = { { hc[6], foreign, hc[7] } } }, { hc[6], hc[7] }, nil
  end
  local ok_f, s2 = pcall(HF.summary)
  check("nested-shape: foreign ref skipped, no crash", ok_f and s2:find("Pair[6,7]", 1, true) ~= nil, tostring(s2))

  G.FUNCS.get_poker_hand_info = nil
  G.hand = { cards = { card("2", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  local s3 = HF.summary()
  check("no ready hands -> no Ready line, no brackets", s3:find("Ready:") == nil and s3:find("%[") == nil, s3)

  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  local s4 = HF.summary()
  check("near Flush carries suit + indices", s4:find("near Flush: 4 Hearts[1,2,3,4]", 1, true) ~= nil, s4:match("Close:[^%.]*"))

  G.hand = { cards = { card("2", "Hearts"), card("3", "Spades"), card("4", "Clubs"), card("5", "Diamonds"), card("King", "Spades") }, highlighted = {} }
  local s5 = HF.summary()
  check("near Straight carries run indices", s5:find("near Straight[1,2,3,4]", 1, true) ~= nil, s5:match("Close:[^%.]*"))
end

-- LP| stashes last play at commit, withholds chips until the async score lands, cleared on round reset
do
  local function H(name) return D.get_action_handler(name) end
  mock_state("Normal", "SELECTING_HAND")
  G.NEURO.last_play = nil
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("9", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.GAME.chips = 100
  G.GAME.blind = { chips = 600 }
  G.FUNCS.get_poker_hand_info = function(cards)
    return "Pair", nil, { Pair = { { cards[1], cards[2] } } }, { cards[1], cards[2] }, nil
  end
  local c = H("play_hand")({ indices = { 1, 2, 3 } })
  local ok_play = pcall(c)
  local lp = G.NEURO.last_play
  check("LP stash on play commit", ok_play and type(lp) == "table" and lp.hand_type == "Pair"
    and lp.played == 3 and lp.scored == 2 and lp.pre_chips == 100 and lp.hands_left_after == 2)

  local blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP renders without chips part pre-score", blob:find("LP|Pair|played 3 cards, 2 scored", 1, true) ~= nil
    and blob:find("LP|Pair|played 3 cards, 2 scored|+", 1, true) == nil, blob:match("LP[^\n]*"))

  G.GAME.chips = 420
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP delta + score/target once chips land", blob:find("LP|Pair|played 3 cards, 2 scored|+320c|420/600", 1, true) ~= nil, blob:match("LP[^\n]*"))
  local fp = ContextCompact.decision_fingerprint("SELECTING_HAND", blob)
  check("LP participates in decision fingerprint", fp:find("LP|Pair", 1, true) ~= nil)

  local cd = H("discard_hand")({ indices = { 4, 5 } })
  pcall(cd)
  check("LP discard stash", type(G.NEURO.last_play) == "table" and G.NEURO.last_play.kind == "discard" and G.NEURO.last_play.played == 2)
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("LP discard line", blob:find("LP|discard|2 cards", 1, true) ~= nil, blob:match("LP[^\n]*"))

  require("context.ctx_hand").clear_last_play()
  check("LP cleared on round-reset path", G.NEURO.last_play == nil)
  blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("no LP line after clear", blob:find("LP|", 1, true) == nil)
  G.GAME.chips = nil; G.GAME.blind = nil; G.FUNCS.get_poker_hand_info = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.round_resets = { ante = 1 }
  G.NEURO.once_serials = {}
  local frame = require("context.game_rules").invariant_frame()
  check("rules: extra-played-cards sentence",
    frame:find("Only the cards forming the played hand score; extra played cards add nothing but leave your hand like a discard", 1, true) ~= nil)
  check("rules: joker-synergy plan sentence",
    frame:find("hunting for jokers that build on the ones you already own is one of the most important plans of a run", 1, true) ~= nil)

  local _, hand_legend = require("facts.token_legends").for_state("SELECTING_HAND")
  hand_legend = hand_legend or ""
  check("legend: [..] indices refer to H: positions",
    hand_legend:find("Numbers in [..] after a Ready/Close hand are those cards' positions in H:", 1, true) ~= nil)

  check("rules: FRAME win clause is generic (no hardcoded Ante-8)",
    frame:find("Ante-8", 1, true) == nil and frame:find("final ante's Boss wins", 1, true) ~= nil)
  local COMMON = require("facts.token_legends").COMMON or ""
  check("legend: joker [..] gloss covers per-suit + song scaling codes",
    COMMON:find("+NM/<suit>-card", 1, true) ~= nil and COMMON:find("song=", 1, true) ~= nil)
  check("legend: joker t-flags gloss covers DEBUFFED", COMMON:find("DEBUFFED", 1, true) ~= nil)
  check("legend: index base stated once (1-based)", COMMON:find("1-based", 1, true) ~= nil)
end

do
  mock_state("Normal", "SHOP")
  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"), { no_cache = true })
  local i_state, i_avail, i_la = blob:find("STATE:", 1, true), blob:find("AVAIL:", 1, true), blob:find("LA|", 1, true)
  check("assembly: AVAIL sits directly under STATE (before legality)",
    i_state and i_avail and i_la and i_state < i_avail and i_avail < i_la, blob:sub(1, 90))
end

do
  local base    = "STATE:SHOP\nAVAIL:buy_from_shop,toggle_shop\nLA|CB:Y|CR:N\nACTS|last:play_hand"
  local changed = "STATE:SHOP\nAVAIL:buy_from_shop,toggle_shop\nLA|CB:Y|CR:N\nACTS|last:sell_card"
  check("fingerprint: ACTS churn does not move the SHOP fingerprint",
    ContextCompact.decision_fingerprint("SHOP", base) == ContextCompact.decision_fingerprint("SHOP", changed))
end

local Tuning = require("core.tuning")
local dotenv = require("util.dotenv")
do
  local defs = Tuning.entries()
  check("tuning: entries ordered, SPEED_MULT first", defs[1] and defs[1].key == "NEURO_SPEED_MULT")
  local have_conf = false
  for _, name in ipairs({ "neuro.conf", "neuro_tuning.env", ".env" }) do
    local f = io.open(dotenv.dir() .. "/" .. name, "r")
    if f then f:close(); have_conf = true end
  end
  if have_conf then
    check("tuning: default check skipped (override file present)", true)
    check("tuning: default check skipped (override file present) 2", true)
  else
    check("tuning: get returns dotenv-seeded default (action cooldown)",
      Tuning.get("NEURO_ACTION_COOLDOWN") == dotenv.num("NEURO_ACTION_COOLDOWN", 0.08))
    check("tuning: get returns dotenv-seeded default (global shop gap)",
      Tuning.get("NEURO_GLOBAL_THROTTLE_SHOP") == dotenv.num("NEURO_GLOBAL_THROTTLE_SHOP", 6.0))
  end
  check("tuning: set clamps to max", Tuning.set("NEURO_SPEED_MULT", 99) == 2.0)
  check("tuning: set clamps to min", Tuning.set("NEURO_SPEED_MULT", -5) == 0.1)
  check("tuning: set rejects unknown key", Tuning.set("NEURO_NOT_A_KNOB", 1) == nil)

  Tuning.set("NEURO_SPEED_MULT", 2.0)
  Tuning.set("NEURO_FORCE_STALL_SECONDS", 12)
  check("tuning: stall watchdog scales with speed mult > 1", Tuning.force_stall_seconds() == 24)
  Tuning.set("NEURO_SPEED_MULT", 0.5)
  check("tuning: stall watchdog unscaled at speed mult <= 1", Tuning.force_stall_seconds() == 12)
  Tuning.reset("NEURO_SPEED_MULT")

  local tmp = os.tmpname()
  Tuning.set("NEURO_POST_PLAY", 2.3)
  Tuning.set("NEURO_GLOBAL_COOLDOWN", 4.2)
  check("tuning: save writes override file", Tuning.save(tmp) == true)
  Tuning.reset("NEURO_POST_PLAY")
  Tuning.reset("NEURO_GLOBAL_COOLDOWN")
  local applied = Tuning.load_overrides(tmp)
  -- serialize writes timing DEFS + non-readonly runtime rows; load re-applies all of them
  local expected = #defs
  for _, d in ipairs(Tuning.runtime_entries()) do if not d.readonly then expected = expected + 1 end end
  check("tuning: load applies every saved entry", applied == expected, applied)
  check("tuning: round-trip POST_PLAY", math.abs(Tuning.get("NEURO_POST_PLAY") - 2.3) < 1e-9)
  check("tuning: round-trip GLOBAL_COOLDOWN", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - 4.2) < 1e-9)
  os.remove(tmp)
  Tuning.reset("NEURO_POST_PLAY")
  Tuning.reset("NEURO_GLOBAL_COOLDOWN")
  check("tuning: missing override file is silent", Tuning.load_overrides("/nonexistent/neuro_tuning.env") == 0)
end

do
  local rt = Tuning.runtime_entries()
  check("config: runtime entries present", #rt > 0)
  check("config: persona is first runtime row", rt[1] and rt[1].key == "NEURO_PERSONA")
  check("config: readonly key rejects set", Tuning.set("NEURO_ENABLE", "on") == nil)
  check("config: readonly key not serialized", not Tuning.serialize():find("NEURO_ENABLE=", 1, true))
  local tmp = os.tmpname()
  Tuning.set("NEURO_AI_CARD_GLOW", "off")
  check("config: runtime enum set", Tuning.get_raw("NEURO_AI_CARD_GLOW") == "off")
  Tuning.save(tmp)
  Tuning.set("NEURO_AI_CARD_GLOW", "on")
  Tuning.load_overrides(tmp)
  check("config: runtime enum round-trips through the file", Tuning.get_raw("NEURO_AI_CARD_GLOW") == "off")
  Tuning.set("NEURO_SELFTEST_FILTER", "abc")
  check("config: string key set", Tuning.get("NEURO_SELFTEST_FILTER") == "abc")
  check("config: string key serialized", Tuning.serialize():find("NEURO_SELFTEST_FILTER=abc", 1, true) ~= nil)
  os.remove(tmp)
  Tuning.reset("NEURO_AI_CARD_GLOW")
  Tuning.reset("NEURO_SELFTEST_FILTER")
end

do
  local prev_settings = G.SETTINGS
  G.SETTINGS = { GAMESPEED = 1 }
  Tuning.reset("NEURO_AUTO_TUNE")
  Tuning.reset("NEURO_CD_PRESET")
  Tuning.reset("NEURO_COOLDOWN_SCALE")
  local base = Tuning.get_raw("NEURO_GLOBAL_COOLDOWN")
  check("cdpreset: no-op at GAMESPEED 1 (auto)", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base) < 1e-9)

  G.SETTINGS.GAMESPEED = 4
  check("cdpreset: auto applies 4x stream factor 0.5", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.5) < 1e-9)
  check("cdpreset: event delay never scaled",
    math.abs(Tuning.get("NEURO_SHOP_BUY_DELAY") - Tuning.get_raw("NEURO_SHOP_BUY_DELAY")) < 1e-9)

  Tuning.set("NEURO_AUTO_TUNE", "off")
  check("cdpreset: auto-tune off = our values (no scaling) at GAMESPEED 4", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base) < 1e-9)
  Tuning.set("NEURO_AUTO_TUNE", "on")

  G.SETTINGS.GAMESPEED = 1
  Tuning.set("NEURO_CD_PRESET", "4x")
  check("cdpreset: pinned 4x applies stream factor regardless of native speed", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.5) < 1e-9)
  Tuning.set("NEURO_CD_PRESET", "2x")
  check("cdpreset: pinned 2x applies 2x stream factor 0.7", math.abs(Tuning.get("NEURO_GLOBAL_COOLDOWN") - base * 0.7) < 1e-9)
  Tuning.set("NEURO_CD_PRESET", "auto")

  G.SETTINGS.GAMESPEED = 0.5
  Tuning.set("NEURO_FORCE_STALL_SECONDS", 12)
  check("cdpreset: watchdog stretches with 0.5x gates (12 * 1.5)", math.abs(Tuning.force_stall_seconds() - 18) < 1e-9)

  G.SETTINGS.GAMESPEED = 99
  check("cdpreset: GAMESPEED clamps to 4", Tuning.game_speed() == 4)
  Tuning.reset("NEURO_AUTO_TUNE")
  Tuning.reset("NEURO_CD_PRESET")
  Tuning.reset("NEURO_FORCE_STALL_SECONDS")
  G.SETTINGS = prev_settings
end

do
  mock_state("Normal", "SHOP")
  local E = require("core.enforce")
  G.STATES = { SHOP = 5 }
  G.STATE = 5
  G.TIMERS = { REAL = 50000 }
  Tuning.set("NEURO_GLOBAL_THROTTLE_SHOP", 6.0)
  Tuning.set("NEURO_THROTTLE_SHOP", 1.2)
  check("enforce: first action passes cooldowns", E.pre_action(nil, "quick_status") == true)
  G.TIMERS.REAL = 50003
  local ok2, err2 = E.pre_action(nil, "quick_status")
  check("enforce: throttled inside global shop gap", ok2 == false and tostring(err2):find("wait") ~= nil, err2)
  Tuning.set("NEURO_GLOBAL_THROTTLE_SHOP", 2.0)
  check("enforce: Tuning.set lowers gap live, same call now passes", E.pre_action(nil, "quick_status") == true)
  Tuning.reset("NEURO_GLOBAL_THROTTLE_SHOP")
  Tuning.reset("NEURO_THROTTLE_SHOP")
end

do
  mock_state("Normal", "SELECTING_HAND")
  local Staging = require("core.staging")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs") }, highlighted = {} }
  G.TIMERS = { REAL = 0 }
  G.NEURO.state = "SELECTING_HAND"
  local results = {}
  local bridge = { send_action_result = function(self, id, ok, msg) results[#results + 1] = { ok = ok, msg = msg } end }
  Tuning.set("NEURO_STAGING_FAILSAFE", 60)
  check("staging: queue accepted", Staging.queue({ command = "action", data = { id = "tp_stage1", name = "play_hand", data = '{"indices":[1]}' } }, bridge) == true)
  G.TIMERS.REAL = 30
  Staging.update()
  check("staging: within raised failsafe, still staged", Staging.is_busy() and #results == 0)
  Tuning.set("NEURO_STAGING_FAILSAFE", 10)
  Staging.update()
  check("staging: lowered failsafe cancels live", not Staging.is_busy() and #results == 1 and results[1].ok == false,
    results[1] and results[1].msg)
  Tuning.reset("NEURO_STAGING_FAILSAFE")
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {} }
  G.STATES = { SELECTING_HAND = 1 }
  G.STATE = 1
  G.TIMERS = { REAL = 90000 }
  G.NEURO.state = "SELECTING_HAND"
  local results, ctxs = {}, {}
  local bridge = {
    send_action_result = function(self, id, ok, msg) results[#results + 1] = { id = id, ok = ok, msg = msg } end,
    send_context = function(self, msg, silent) ctxs[#ctxs + 1] = tostring(msg) end,
  }
  G.NEURO.llm_paused = true
  local msg = { command = "action", data = { id = "tp_pause1", name = "help" } }
  D.route_message(msg, bridge)
  check("pause: action rejected with operator message",
    #results == 1 and results[1].ok == false and results[1].msg:find("Paused by operator") ~= nil,
    results[1] and results[1].msg)
  check("pause: handler not executed (no context sent)", #ctxs == 0)
  D.route_message(msg, bridge)
  check("pause: retry while paused rejects again (id not settled)", #results == 2 and results[2].ok == false)
  G.NEURO.llm_paused = nil
  D.route_message(msg, bridge)
  check("pause: same id executes normally after resume", #results == 3 and results[3].ok == true, results[3] and results[3].msg)
  check("pause: post-resume execution ran the handler", #ctxs >= 1 and ctxs[#ctxs]:find("AVAILABLE COMMANDS") ~= nil, ctxs[#ctxs])
end

do
  local P = require("hud.tuning_panel")
  local defs = Tuning.entries()
  G.NEURO.force_dirty = false
  G.NEURO.last_force_fingerprint = "stale_fp"
  local override_path = dotenv.dir() .. "/neuro_tuning.env"
  local prior = io.open(override_path, "r")
  local prior_content = prior and prior:read("*a") or nil
  if prior then prior:close() end

  check("panel: open pauses LLM", P.toggle() == true and G.NEURO.llm_paused == true)
  check("panel: swallows own keys while open", P.keypressed("down") == true)
  check("panel: leaves other keys alone", P.keypressed("f9") == false)
  local d2 = defs[2]
  P.reveal(d2.key)
  local before = Tuning.get(d2.key)
  P.keypressed("right")
  check("panel: right adjusts selected by step", math.abs(Tuning.get(d2.key) - math.min(d2.max, before + d2.step)) < 1e-9)
  P.keypressed("r")
  check("panel: R resets selected to default", Tuning.get(d2.key) == d2.default)
  check("panel: close resumes LLM", P.toggle() == false and G.NEURO.llm_paused == nil)
  check("panel: resume marks force dirty + clears fingerprint",
    G.NEURO.force_dirty == true and G.NEURO.last_force_fingerprint == nil)
  local saved = io.open(override_path, "r")
  check("panel: close auto-saves overrides", saved ~= nil)
  if saved then saved:close() end

  if prior_content then
    local f = io.open(override_path, "w")
    f:write(prior_content)
    f:close()
  else
    os.remove(override_path)
  end
  check("panel: closed panel ignores keys", P.keypressed("down") == false)
end

do
  for _, k in ipairs({ "NEURO_OVERLAY_SCALE_RIGHT", "NEURO_OVERLAY_SCALE_LEFT" }) do
    local d
    for _, e in ipairs(Tuning.entries()) do if e.key == k then d = e end end
    check("scale: " .. k .. " registered 0.5-1.5 step 0.05 default 1",
      d and d.min == 0.5 and d.max == 1.5 and d.step == 0.05 and d.default == 1.0)
    check("scale: " .. k .. " clamps high", Tuning.set(k, 9) == 1.5)
    check("scale: " .. k .. " clamps low", Tuning.set(k, 0) == 0.5)
    Tuning.reset(k)
    check("scale: " .. k .. " reset to 1.0", Tuning.get(k) == 1.0)
  end
end

do
  local P = require("hud.tuning_panel")
  local DS = require("render.debug_stats")
  local d
  local defs = Tuning.entries()
  local sel_idx
  for i, e in ipairs(defs) do if e.key == "NEURO_DEBUG_OVERLAY" then d = e sel_idx = i end end
  check("enum: NEURO_DEBUG_OVERLAY entry has mode list off/compact/expanded",
    d and d.values and d.values[1] == "off" and d.values[2] == "compact" and d.values[3] == "expanded")
  check("enum: set accepts listed value", Tuning.set("NEURO_DEBUG_OVERLAY", "expanded") == "expanded")
  check("enum: set rejects unlisted value", Tuning.set("NEURO_DEBUG_OVERLAY", "loud") == nil)
  Tuning.set("NEURO_DEBUG_OVERLAY", "off")

  local applied = {}
  local orig_smn = DS.set_mode_name
  DS.set_mode_name = function(name) applied[#applied + 1] = name end
  P.toggle()
  P.reveal("NEURO_DEBUG_OVERLAY")
  P.keypressed("right")
  P.keypressed("right")
  P.keypressed("right")
  DS.set_mode_name = orig_smn
  P.toggle()
  check("enum: panel right cycles through full mode list and wraps",
    #applied == 3 and applied[1] == "compact" and applied[2] == "expanded" and applied[3] == "off")
  check("enum: panel applies the tuned value to DebugStats", applied[#applied] == Tuning.get("NEURO_DEBUG_OVERLAY"))
  check("enum: set_mode_name drives visible mode", (function()
    DS.set_mode_name("compact")
    local vis = DS.visible()
    DS.set_mode_name("off")
    return vis and not DS.visible()
  end)())
  Tuning.set("NEURO_DEBUG_OVERLAY", "off")
end

-- resume must clear a force stuck inflight or watchdog-less states like MENU never re-force
do
  local override_path = dotenv.dir() .. "/neuro_tuning.env"
  local prior = io.open(override_path, "r")
  local prior_content = prior and prior:read("*a") or nil
  if prior then prior:close() end

  local ok_ng, ng_err = pcall(require, "neuro-game")
  check("f8: neuro-game loads offline", ok_ng, ng_err)
  check("f8: love.keypressed hook installed", type(love.keypressed) == "function")
  local P = require("hud.tuning_panel")
  if P.is_open() then P.toggle() end
  G.NEURO.login_anim = nil
  G.NEURO.llm_paused = nil
  G.NEURO.force_inflight = true
  G.NEURO.force_state = "MENU"
  G.NEURO.force_sent_at = 1
  G.NEURO.force_dirty = false
  G.NEURO.last_force_fingerprint = "stale_fp"
  love.keypressed("f8")
  check("f8: first press pauses LLM + opens panel", G.NEURO.llm_paused == true and P.is_open())
  love.keypressed("f8")
  check("f8: second press resumes (llm_paused cleared)", not G.NEURO.llm_paused and not P.is_open())
  check("f8: resume re-arms force (dirty + fingerprint cleared)",
    G.NEURO.force_dirty == true and G.NEURO.last_force_fingerprint == nil)
  check("f8: resume clears stale inflight force so re-force can send",
    G.NEURO.force_inflight == false and G.NEURO.force_sent_at == nil)

  if prior_content then
    local f = io.open(override_path, "w")
    f:write(prior_content)
    f:close()
  else
    os.remove(override_path)
  end
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.STATES = { MENU = 1 }
  G.STATE = 1
  G.GAME = { current_round = {} }
  G.OVERLAY_MENU = nil
  G.run_setup_seed = nil
  G.setup_seed = nil

  local f = D.get_force_for_state("MENU")
  check("seed chain: MENU force offers setup_run", f and has(f.actions, "setup_run"))
  check("seed chain: MENU force omits toggle_seeded_run (fails without overlay)",
    not has((f or {}).actions, "toggle_seeded_run"))
  check("seed chain: MENU force omits paste_seed (wiped by overlay rebuild)",
    not has((f or {}).actions, "paste_seed"))
  check("seed chain: MENU force omits start_setup_run (dispatcher rejects it)",
    not has((f or {}).actions, "start_setup_run"))
  check("seed chain: toggle_seeded_run invalid without overlay", not A.is_action_valid("toggle_seeded_run"))
  check("seed chain: start_setup_run invalid without overlay", not A.is_action_valid("start_setup_run"))

  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  local rs = D.get_force_for_state("RUN_SETUP")
  check("seed chain: run-setup force offers toggle_seeded_run", rs and has(rs.actions, "toggle_seeded_run"))
  check("seed chain: run-setup force offers paste_seed", rs and has(rs.actions, "paste_seed"))
  check("seed chain: run-setup force offers start_setup_run", rs and has(rs.actions, "start_setup_run"))
  local rq = (rs or {}).query or ""
  check("seed chain: run-setup force shows seeded mode fact", rq:find("Seeded mode: OFF", 1, true) ~= nil, rq)
  check("seed chain: run-setup force gives paste_seed payload example",
    rq:find('paste_seed|{"seed":"ABC123XY"}', 1, true) ~= nil, rq)

  local toggle = D.get_action_handler("toggle_seeded_run")
  local run = toggle({})
  check("seed chain: toggle_seeded_run executes on overlay", type(run) == "function" and run():find("ON") ~= nil)
  check("seed chain: toggle flips engine flag", G.run_setup_seed == true)

  local paste = D.get_action_handler("paste_seed")
  local prun = paste({ seed = "abc-123xy" })
  check("seed chain: paste_seed normalizes + reports seed",
    type(prun) == "function" and prun() == "Seed set to: ABC123XY")
  check("seed chain: paste_seed arms engine seed", G.setup_seed == "ABC123XY" and G.run_setup_seed == true)

  local rs2 = D.get_force_for_state("RUN_SETUP")
  local rq2 = (rs2 or {}).query or ""
  check("seed chain: force reflects seeded ON + pasted seed",
    rq2:find("Seeded mode: ON", 1, true) ~= nil and rq2:find("Pasted seed: ABC123XY", 1, true) ~= nil, rq2)
  check("seed chain: start_setup_run valid with overlay open", A.is_action_valid("start_setup_run"))

  G.OVERLAY_MENU = nil
  G.run_setup_seed = nil
  G.setup_seed = nil
  G.STATES = nil; G.STATE = nil
end

-- DC is deck size only: per-suit/per-rank breakdown would be deck counting (out of bounds)
do
  mock_state("Normal", "SELECTING_HAND")
  local CtxHand = require("context.ctx_hand")
  local d = { card("Ace", "Spades"), card("King", "Hearts"), card("5", "Hearts") }
  G.deck = { cards = { d[1], d[2], d[3] } }
  local dc1 = CtxHand.deck_cards_section()
  check("W1: DC is size only", dc1 == "DC:3", dc1)
  check("W1: DC exposes no suit/rank breakdown", not dc1:find("|") and not dc1:find(":%d.*%a"), dc1)
  G.deck = { cards = { d[3], d[1], d[2] } }
  check("W1: DC identical under reordering (no draw-order leak)", CtxHand.deck_cards_section() == dc1)
  G.deck = nil
end

-- BU| reads the vanilla bosses_used shape (0 = unused); the old if-v-then emitted subtable keys too
do
  mock_state("Small blind selectable", "BLIND_SELECT")
  local CtxBlind = require("context.ctx_blind")
  G.GAME.bosses_used = { boss = { bl_ox = 0, bl_wall = 1 }, small = { bl_small = 3 }, big = {} }
  local s = CtxBlind.blind_select_section() or ""
  check("W2: BU lists only used bosses from the boss subtable", (s:match("BU|[^\n]*") or "") == "BU|wall", s:match("BU|[^\n]*"))
  G.GAME.bosses_used = { bl_ox = 0, bl_wall = 1 }
  s = CtxBlind.blind_select_section() or ""
  check("W2: flat bosses_used mock {bl_ox=0,bl_wall=1} -> only wall", (s:match("BU|[^\n]*") or "") == "BU|wall", s:match("BU|[^\n]*"))
  G.GAME.bosses_used = { boss = { bl_ox = 0 }, small = {}, big = {} }
  s = CtxBlind.blind_select_section() or ""
  check("W2: no BU line when no boss used yet", s:find("BU|") == nil)
  G.GAME.bosses_used = nil
end

do
  mock_state("Normal", "SHOP")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = D.get_force_for_state("SHOP")
  local ctx = ContextCompact.build("SHOP", f.actions, { force_phase = true, no_cache = true })
  check("W3: force-phase context has no AVAIL line", ctx:find("AVAIL:") == nil, ctx:sub(1, 200))
  local ctx2 = ContextCompact.build("SHOP", f.actions, { no_cache = true })
  local avail = ctx2:match("AVAIL:([^\n]*)") or ""
  local expected = {}
  for _, n in ipairs(f.actions) do
    if not A.INFO_ACTIONS[n] then expected[#expected + 1] = n end
  end
  check("W3: non-force AVAIL == shipped action list (minus info)", avail == table.concat(expected, ","),
    avail .. " vs " .. table.concat(expected, ","))
end

do
  local FH = require("force.force_helpers")
  mock_state("Normal", "SELECTING_HAND")
  G.STATES = { SELECTING_HAND = 1, SHOP = 5 }
  G.STATE = 1
  check("W4: force for the current state is not stale", FH.force_is_stale("SELECTING_HAND", {}) == false)
  check("W4: force built for a superseded state is stale", FH.force_is_stale("SHOP", {}) == true)
  G.STATES = nil; G.STATE = nil

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.STATES = { BLIND_SELECT = 3 }; G.STATE = 3
  check("W4: blind force matching the selectable blind is not stale",
    FH.force_is_stale("BLIND_SELECT", { blind = "small" }) == false)
  G.GAME.blind_on_deck = "Big"
  G.GAME.round_resets.blind_states = { Small = "Defeated", Big = "Select", Boss = "Upcoming" }
  check("W4: blind force naming a superseded selectable is stale",
    FH.force_is_stale("BLIND_SELECT", { blind = "small" }) == true)
  G.STATES = nil; G.STATE = nil
end

-- Ready index lists are one best instance (best first), never the union, never over 5
do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("7", "Clubs"),
    card("7", "Diamonds"), card("7", "Hearts"), card("4", "Clubs"), card("4", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[3], hc[4], hc[5], hc[1], hc[2] }, { hc[3], hc[4], hc[5], hc[6], hc[7] } },
      ["Three of a Kind"] = { { hc[3], hc[4], hc[5] } },
      ["Two Pair"] = { { hc[1], hc[2], hc[6], hc[7] } },
      ["Pair"] = { { hc[1], hc[2] }, { hc[6], hc[7] } },
    }, { hc[3], hc[4], hc[5], hc[1], hc[2] }, nil
  end
  local s = HF.summary()
  local ready_ix = {}
  for name, ix in (s:match("Ready:[^%.]*") or ""):gmatch("([%a ]+)%[([%d,]+)%]") do
    ready_ix[name:gsub("^[%s,]+", "")] = ix
  end
  check("B2: Full House = exactly the KK+777 positions [1,2,3,4,5]",
    ready_ix["Full House"] == "1,2,3,4,5", s:match("Ready:[^%.]*"))
  check("B2: Pair = highest pair only [1,2] (not the union of all pairs)",
    ready_ix["Pair"] == "1,2", s:match("Ready:[^%.]*"))
  for name, ix in pairs(ready_ix) do
    local n = 0
    for _ in ix:gmatch("%d+") do n = n + 1 end
    check("B2: ready list for " .. name .. " never exceeds 5", n <= 5, ix)
  end

  G.hand = { cards = { card("2", "Hearts"), card("King", "Hearts"), card("5", "Hearts"),
    card("9", "Hearts"), card("Ace", "Hearts"), card("Jack", "Hearts"), card("3", "Clubs") }, highlighted = {} }
  local fc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Flush", nil, { ["Flush"] = { { fc[1], fc[2], fc[3], fc[4], fc[5], fc[6] } } },
      { fc[2], fc[4], fc[5], fc[6], fc[3] }, nil
  end
  local s2 = HF.summary()
  check("B2: 6-card Flush trimmed to the 5 highest of the suit [2,3,4,5,6]",
    s2:find("Flush[2,3,4,5,6]", 1, true) ~= nil, s2:match("Ready:[^%.]*"))
  G.FUNCS.get_poker_hand_info = nil
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("4", "Diamonds"),
    card("9", "Clubs"), card("Queen", "Hearts") }, highlighted = {} }
  local s = HF.summary()
  check("B3: near Three of a Kind carries the pair's positions",
    s:find("near Three of a Kind[1,2]", 1, true) ~= nil, s:match("Close:[^%.]*"))
  check("B3: near Two Pair carries the pair's positions",
    s:find("near Two Pair[1,2]", 1, true) ~= nil, s:match("Close:[^%.]*"))

  G.hand = { cards = { card("7", "Clubs"), card("7", "Diamonds"), card("7", "Hearts"),
    card("King", "Spades"), card("2", "Clubs") }, highlighted = {} }
  local s2 = HF.summary()
  check("B3: near Four of a Kind carries the trips' positions",
    s2:find("near Four of a Kind[1,2,3]", 1, true) ~= nil, s2:match("Close:[^%.]*"))
  check("B3: near Full House carries the trips' positions",
    s2:find("near Full House[1,2,3]", 1, true) ~= nil, s2:match("Close:[^%.]*"))
end

-- SELECTING_HAND payout projection drops the deciding hand; other states keep hands_left
do
  local CtxEconomy = require("context.ctx_economy")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.dollars = 0
  G.GAME.modifiers = {}
  G.GAME.current_round.hands_left = 1; G.GAME.current_round.discards_left = 0
  check("B4: default projection counts all hands (H1)", CtxEconomy.economy_projection().hands_bonus == 1)
  check("B4: selecting-hand projection excludes the deciding hand (H0)",
    CtxEconomy.economy_projection({ selecting_hand = true }).hands_bonus == 0)
  G.GAME.current_round.hands_left = 3
  check("B4: selecting-hand projection = hands_left-1",
    CtxEconomy.economy_projection({ selecting_hand = true }).hands_bonus == 2)
  G.GAME.blind = { in_blind = true, dollars = 3, chips = 300 }
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {}, config = { card_limit = 8 } }
  G.GAME.current_round.hands_left = 1
  local blob = ContextCompact.build("SELECTING_HAND", nil, { no_cache = true })
  check("B4: last-hand B line projects H0", blob:find("PY:B3+hr0+", 1, true) ~= nil, blob:match("PY:[^|\n]*"))
  G.GAME.blind = nil
end

-- selectable blind falls back to blind_states when blind_on_deck unset; fully unresolved builds no force
do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.GAME.blind_on_deck = nil
  check("M1: get_selectable_blind_key falls back to blind_states Select",
    A.get_selectable_blind_key() == "Small")
  local f = D.get_force_for_state("BLIND_SELECT")
  check("M1: force still built from states fallback (names small)",
    f ~= nil and tostring(f.query):find("Currently selectable: small", 1, true) ~= nil, f and f.query)
  check("M1: force carries the blind it was built for", f and f.blind == "small")
  G.GAME.blind_on_deck = nil
  G.GAME.round_resets.blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
  check("M1: unresolved on-deck AND states -> no force (delay, never OD:?)",
    require("force.force_blind_select").build("") == nil)
end

-- feedback names the real card even when the UI shows Not Discovered
do
  mock_state("Normal", "SELECTING_HAND")
  local hidden = {
    ability = { consumeable = {}, set = "Spectral", name = "c_ankh" },
    config = { center = { key = "c_ankh", loc_txt = { name = "Ankh" }, discovered = false } },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end,
  }
  check("M2: safe_name is discovery-gated (UI path)", Utils.safe_name(hidden) == "Not Discovered")
  check("M2: real_name reveals the owned card's center name", Utils.real_name(hidden) == "Ankh")
  G.consumeables = { cards = { hidden }, config = { card_limit = 2 } }
  G.FUNCS.use_card = function() end
  local c = D.get_action_handler("use_card")({ area = "consumeables", index = 1 })
  local ok_u, r_u = pcall(c)
  check("M2: use feedback names the card", ok_u and r_u == "Used: Ankh", tostring(r_u))
  G.FUNCS.use_card = nil

  mock_state("Normal", "SHOP")
  local shop_hidden = {
    cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_x", loc_txt = { name = "Mystery Joker" }, set = "Joker" } },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end,
  }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_hidden } }
  G.FUNCS.buy_from_shop = function() end
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1 })
  local ok_b, r_b = pcall(cb)
  check("M2: buy feedback names the card", ok_b and r_b == "Buying: Mystery Joker for $4", tostring(r_b))
  G.FUNCS.buy_from_shop = nil; G.NEURO.reserved_dollars = 0
end

-- F-005: a missing engine callback must correct the optimistic ok, not report an optimistic "Buying:"
do
  mock_state("Normal", "SHOP")
  local shop_j = { cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_y", loc_txt = { name = "Test Joker" }, set = "Joker" } } }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_j } }
  G.FUNCS.buy_from_shop = nil  -- engine callback unavailable
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1 })
  local ok_b, r_b = pcall(cb)
  check("F-005: missing buy callback returns corrective, not optimistic",
    ok_b and type(r_b) == "string" and r_b:find("Could not buy", 1, true) ~= nil, tostring(r_b))
  check("F-005: missing buy callback records a failure", G.NEURO.last_failed_action == "buy_from_shop")
  G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil; G.NEURO.last_failed_at = nil
end

-- F-007: affordability + reroll reuse item_afford_status (full slot => not buyable even if cash-affordable), so context/HUD never disagree with the validator
do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local shop_j = { cost = 3, ability = { set = "Joker" },
    config = { center = { key = "j_z", loc_txt = { name = "Slot Joker" }, set = "Joker" } } }
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = { {}, {}, {}, {}, {} }, config = { card_limit = 5 } }  -- joker slots FULL
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { shop_j } }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  G.GAME.current_round.reroll_cost = 5
  local la = CtxShop.legality_section("SHOP") or ""
  check("F-007: cash-affordable but full-slot joker is not buyable (CB:N)", la:find("CB:N", 1, true) ~= nil, la)
  check("F-007: CRS is '-' when nothing is buyable to protect", la:find("CRS:-", 1, true) ~= nil, la)
  local sec = CtxShop.shop_section() or ""
  check("F-007: shop row marks full-slot joker ok=N",
    sec:find("Slot Joker", 1, true) ~= nil and sec:find(",N,", 1, true) ~= nil, sec)
end

do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local rare_joker = { cost = 6, ability = { set = "Joker" },
    config = { center = { key = "j_rare", set = "Joker", rarity = 3, loc_txt = { name = "Rare J" } } } }
  G.GAME.dollars = 12; G.NEURO.reserved_dollars = 0
  G.GAME.current_round.reroll_cost = 5; G.GAME.current_round.free_rerolls = 0
  G.GAME.modifiers = {}; G.GAME.bankrupt_at = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = { rare_joker } }
  G.shop_vouchers = { cards = {} }; G.shop_booster = { cards = {} }
  local sec = CtxShop.shop_section() or ""
  check("A1: I header carries rar column", sec:find("I:a,i,n,t,rar,$,ok,f,d", 1, true) ~= nil, sec)
  check("A1: rare joker row shows rarity R", sec:find(",Joker,R,$6,", 1, true) ~= nil, sec)
  check("A2: SH line carries SP spendable=12", sec:find("|SP:12|", 1, true) ~= nil, sec)
  check("A4: SH line carries RRN next-reroll=6", sec:find("|RRN:6|", 1, true) ~= nil, sec)
  check("A3: SH line carries NXT to next interest step=3", sec:find("|NXT:3", 1, true) ~= nil, sec)
  G.jokers = { cards = { { config = { center = { key = "j_credit_card", set = "Joker" } },
    ability = { set = "Joker", name = "Credit Card" } } }, config = { card_limit = 5 } }
  local sec2 = CtxShop.shop_section() or ""
  check("A2: Credit Card surfaces FLOOR:-20", sec2:find("|FLOOR:-20", 1, true) ~= nil, sec2)
end

do
  mock_state("Normal", "SHOP")
  local CtxShop = require("context.ctx_shop")
  local Ctx = require("context.context")
  local Eco = require("context.ctx_economy")
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.GAME.current_round.reroll_cost = 7; G.GAME.current_round.free_rerolls = 0
  G.GAME.modifiers = {}; G.GAME.interest_cap = 25; G.GAME.interest_amount = 1
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = { cards = {} }; G.shop_vouchers = { cards = {} }; G.shop_booster = { cards = {} }

  check("U1: ctx_economy reroll_cost reads live value", Eco.reroll_cost() == 7)
  check("U1: reroll_facts effective == cost when no free reroll", Eco.reroll_facts().effective == 7)
  check("U1: compact SH RR uses helper (RR:7)", (CtxShop.shop_section() or ""):find("|RR:7|", 1, true) ~= nil)
  local verbose = table.concat(Ctx.get_shop_context() or {}, "\n")
  check("U1: verbose context reroll == helper ($7)", verbose:find("Reroll Cost: $7", 1, true) ~= nil, verbose)

  -- unknown reroll must surface as ?, never a fake 5
  G.GAME.current_round.reroll_cost = nil
  local sh2 = CtxShop.shop_section() or ""
  check("U2: unknown reroll shows RR:? (no fake 5)", sh2:find("|RR:?|", 1, true) ~= nil and sh2:find("|RR:5|", 1, true) == nil, sh2)
  check("U2: verbose reroll shows $? when unknown",
    table.concat(Ctx.get_shop_context() or {}, "\n"):find("Reroll Cost: $?", 1, true) ~= nil)
  G.GAME.current_round.reroll_cost = 5

  -- U3: engine reports reroll_cost=0 during a free reroll; the last free reroll uses skip_increment, so the first paid reroll is base+increase (increase does NOT advance on the free->paid transition)
  G.GAME.current_round.reroll_cost = 0; G.GAME.current_round.free_rerolls = 1
  G.GAME.current_round.reroll_cost_increase = 0; G.GAME.round_resets = { reroll_cost = 5 }
  local rf = Eco.reroll_facts()
  check("U3: free reroll shown as $0 effective", rf.effective == 0)
  check("U3: first paid reroll after a free one is base+increase (paid=5, next=5)", rf.paid == 5 and rf.next == 5)
  G.GAME.current_round.free_rerolls = 0; G.GAME.current_round.reroll_cost = 5
end

do
  local TL = require("facts.token_legends")
  local _, legend = TL.for_state("SELECTING_HAND")
  -- shared tokens (DC/L/C/...) ride the once-per-ante COMMON gloss; state legends carry only unique tokens
  legend = (legend or "") .. " " .. (TL.COMMON or "")
  for _, tok in ipairs({ "LP=", "DC=", "DK=", "HL=", "ERN=" }) do
    check("B1: legend defines " .. tok:sub(1, -2), legend:find(tok, 1, true) ~= nil)
  end
  check("B1: DC legend is size-only (no per-suit/rank counting)",
    legend:find("DC=number of cards left in the draw pile", 1, true) ~= nil
    and legend:find("per suit", 1, true) == nil)
  check("B1: glossary carries the shape-only caveat", legend:find("shape only", 1, true) ~= nil)
  local by_name = {}
  for _, def in ipairs(require("core.actions").get_static_actions()) do by_name[def.name] = def end
  check("B1: evaluate_play is no longer registered", by_name.evaluate_play == nil)
  check("B1: simulate_hand action description carries usage",
    ((by_name.simulate_hand or {}).description or ""):find("indices", 1, true) ~= nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.NEURO.once_serials = {}
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("B-C1: query omits the shape-only caveat", q:find("shape only", 1, true) == nil, q)
  check("B-C4: query omits evaluate_play prose", q:find("evaluate_play|", 1, true) == nil)
  check("B-C2: query omits the duplicated Active debuff line", q:find("Active debuff:", 1, true) == nil)
  check("B5: query omits the once-per-entry deck strategy hint", q:find("Deck: ", 1, true) == nil, q)
  check("B-O1: commit ask is the query tail", q:find("Your move: ", 1, true) ~= nil
    and q:gsub("%s+$", ""):find("uses a %w+%)%.$") ~= nil, q)
  check("C10: economy rules gone from the query", q:find("At round end each unused hand", 1, true) == nil)
  local stable = ContextCompact.build("SELECTING_HAND", nil, { split = "stable", no_cache = true })
  check("C10: economy rules on the stable RUN| line", stable:find("RUN|", 1, true) ~= nil
    and stable:find("At round end each unused hand", 1, true) ~= nil)
end

do
  mock_state("Normal", "SHOP")
  local blob = ContextCompact.build("SHOP", nil, { no_cache = true })
  local sh = blob:match("SH|[^\n]*")
  check("B1: SH economy line dropped the duplicated J:/C: slot pair",
    not (sh and sh:find("|J:%d+/%d+|C:%d+/%d+")), sh)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  local q = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("FRAME: principle line present", q:find("the exact cards that form it", 1, true) ~= nil, q)
  check("FRAME: does not prescribe a hand type (High Card/Pair builds stay valid)",
    q:find("any type counts", 1, true) ~= nil and q:find("Prefer a Ready hand", 1, true) == nil, q)
  check("FRAME: no computed Pace line", q:find("Pace:", 1, true) == nil, q)
  check("FRAME: Close-keep reminder present when Close exists", q:find("lists cards to KEEP", 1, true) ~= nil, q)
  check("FRAME: no DB/LOCK line without a debuffed/forced card", q:find("DB cards score 0", 1, true) == nil, q)

  G.GAME.current_round.discards_left = 0
  local q2 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("FRAME: Close-keep suppressed when no Close", q2:find("lists cards to KEEP", 1, true) == nil, q2)
  check("FRAME: principle line still present without Close", q2:find("the exact cards that form it", 1, true) ~= nil, q2)

  G.GAME.current_round.discards_left = 2
  local dc = card("5", "Clubs"); dc.debuff = true
  G.hand = { cards = { dc, card("9", "Diamonds"), card("King", "Spades") }, highlighted = {} }
  local q3 = (D.get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("FRAME: DB/LOCK reminder present with a debuffed card", q3:find("DB cards score 0", 1, true) ~= nil, q3)

  local _, legend = require("facts.token_legends").for_state("SELECTING_HAND")
  check("FRAME: SELECTING_HAND legend no longer mentions Pace", legend:find("Pace", 1, true) == nil, legend)
end

-- DynaText config.string can be a raw number (e.g. Green Joker "Currently +0 Mult"); coerce it, don't drop it
do
  local U = require("util.utils")
  local function mk(valnode)
    return { generate_UIBox_ability_table = function()
      return { main = {
        { config = { text = "(Currently " } },
        { config = { object = { config = { string = { valnode } } } } },
        { config = { text = " Mult)" } },
      } }
    end }
  end
  check("JOKER0: numeric DynaText value 0 is kept (not dropped)",
    (U.card_description(mk({ string = 0 })) or ""):find("Currently 0 Mult", 1, true) ~= nil,
    U.card_description(mk({ string = 0 })))
  check("JOKER0: numeric DynaText value 5 is kept",
    (U.card_description(mk({ string = 5 })) or ""):find("Currently 5 Mult", 1, true) ~= nil,
    U.card_description(mk({ string = 5 })))
  check("JOKER0: two numeric values still collapse to a range",
    (U.card_description({ generate_UIBox_ability_table = function()
      return { main = { { config = { object = { config = { string = { { string = 1 }, { string = 6 } } } } } } } }
    end }) or ""):find("1 to 6", 1, true) ~= nil, "range")
end

-- a boss size-rule violation must skip staging so the rejection is instant, not delayed by hover animation
do
  local Staging = require("core.staging")
  local CardArea = require("facts.card_area_util")
  check("SIZE: min-cards violation flagged", CardArea.blind_size_rule_error({ h_size_ge = 5 }, 2) ~= nil)
  check("SIZE: legal count passes", CardArea.blind_size_rule_error({ h_size_ge = 5 }, 5) == nil)
  check("SIZE: max-cards violation flagged", CardArea.blind_size_rule_error({ h_size_le = 3 }, 4) ~= nil)
  check("SIZE: no debuff passes", CardArea.blind_size_rule_error(nil, 2) == nil)
  local saved = G.GAME and G.GAME.blind
  G.GAME = G.GAME or {}
  G.GAME.blind = { disabled = false, debuff = { h_size_ge = 5 } }
  check("SIZE: should_stage=false for 2 cards vs must-play-5 (instant reject)",
    Staging.should_stage({ command = "action", data = { name = "play_hand", indices = { 1, 2 }, id = "sz1" } }) == false)
  check("SIZE: should_stage=true for a legal 5-card play",
    Staging.should_stage({ command = "action", data = { name = "play_hand", indices = { 1, 2, 3, 4, 5 }, id = "sz2" } }) == true)
  G.GAME.blind = saved
end

do
  local DF = require("facts.debuff_facts")
  local CtxBlind = require("context.ctx_blind")
  local CtxMisc = require("context.ctx_misc")
  _G.localize = function(args)
    if type(args) == "table" and args.type == "raw_descriptions" then
      if args.set == "Blind" and args.key == "bl_pillar" then
        return { "Cards played previously this ante are debuffed" }
      end
      if args.set == "Tag" and args.key == "tag_charm" then
        return { "Gives a free Mega Arcana Pack" }
      end
      if args.set == "Voucher" and args.key == "v_grabber" then
        return { "Permanently gain +" .. tostring(args.vars and args.vars[1] or "?") .. " hand per round" }
      end
    end
    return nil
  end

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = {
    bl_small = { name = "Small Blind", dollars = 3, debuff = {} },
    bl_big = { name = "Big Blind", dollars = 4, debuff = {} },
    bl_pillar = { name = "The Pillar", dollars = 5, debuff = {}, boss = { min = 1 } },
  }
  G.P_TAGS = { tag_charm = { name = "Charm Tag", config = {} } }
  G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_pillar" }
  G.GAME.round_resets.blind_tags = { Small = "tag_charm" }
  local s = CtxBlind.blind_select_section() or ""
  check("CW1: BO boss row carries localized effect text",
    s:find("Cards played previously this ante are debuffed", 1, true) ~= nil, s:match("Boss[^\n]*"))
  check("CW2: BO tag_effect carries localized tag text",
    s:find("Gives a free Mega Arcana Pack", 1, true) ~= nil, s:match("Small[^\n]*"))

  local f = require("force.force_blind_select").build("")
  local q = (f or {}).query or ""
  check("CW1: force offers select_blind and does not duplicate the boss desc",
    has((f or {}).actions, "select_blind") and q:find("Cards played previously this ante", 1, true) == nil, q)
  check("CW2: force query does not duplicate the tag reward text",
    q:find("Skip reward:", 1, true) == nil and q:find("Gives a free Mega Arcana Pack", 1, true) == nil, q)

  G.GAME.tags = { { key = "tag_charm", config = {} } }
  local ts = CtxMisc.tags_section() or ""
  check("CW2: owned TAGS carries localized effect", ts:find("Gives a free Mega Arcana Pack", 1, true) ~= nil, ts)
  G.GAME.tags = nil
  G.P_CENTERS = { v_grabber = { name = "Grabber", key = "v_grabber", set = "Voucher", config = { extra = 1 } } }
  G.GAME.used_vouchers = { v_grabber = true }
  local vs = CtxMisc.vouchers_section() or ""
  check("CW8: V| carries localized voucher effect with engine vars",
    vs:find("Permanently gain +1 hand per round", 1, true) ~= nil, vs)
  G.GAME.used_vouchers = nil; G.P_CENTERS = nil

  _G.localize = nil
  check("CW1: P_BLINDS loc_txt fallback still works",
    DF.blind_effect_text("bl_mod", { name = "Mod Blind", loc_txt = { text = { "Modded effect" } } }) == "Modded effect")
  G.P_BLINDS = nil; G.P_TAGS = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 4 } }
  G.GAME.pack_choices = 1
  local planet = { ability = { set = "Planet", name = "Pluto" }, config = { center = { key = "c_pluto" } } }
  G.pack_cards = { cards = { planet } }
  local blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { no_cache = true, split = "volatile" })
  check("CW3: planet card visible -> L: attached", blob:find("L:n,lv,c,m,p", 1, true) ~= nil, blob)

  local playing = card("9", "Hearts")
  G.pack_cards = { cards = { playing } }
  G.deck = { cards = { card("Ace", "Spades"), card("King", "Hearts") } }
  blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { no_cache = true, split = "volatile" })
  check("CW3: playing card visible -> DC aggregate attached", blob:find("DC:2", 1, true) ~= nil, blob)
  check("CW3: playing card visible -> no L:", blob:find("L:n,lv", 1, true) == nil)
  G.pack_cards = nil; G.deck = nil
end

do
  mock_state("Normal", "SHOP")
  G.GAME.hands = {
    Pair = { visible = true, level = 2, chips = 20, mult = 3, played = 6 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
  }
  G.shop_jokers = { cards = {}, config = { card_limit = 2 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local blob_none = ContextCompact.build("SHOP", nil, { no_cache = true, split = "volatile" })
  check("CW4: SHOP without Planet/conditional-joker omits L: table", blob_none:find("L:n,lv,c,m,p", 1, true) == nil, blob_none)
  G.shop_jokers = { cards = { { ability = { set = "Planet", name = "Pluto" }, config = { center = { key = "c_pluto" } } } }, config = { card_limit = 2 } }
  local blob = ContextCompact.build("SHOP", nil, { no_cache = true, split = "volatile" })
  check("CW4: SHOP with a buyable Planet has L: table", blob:find("L:n,lv,c,m,p", 1, true) ~= nil, blob)
  check("CW4: SHOP L: rows carry all hand types", blob:find("Pair,2,20,3,6", 1, true) ~= nil
    and blob:find("Flush,1,35,4,0", 1, true) ~= nil, blob:match("L:n[^\n]*\n[^\n]*\n[^\n]*"))
  G.shop_jokers = nil; G.jokers = nil
end

do
  local CtxHand = require("context.ctx_hand")
  local CtxBlind = require("context.ctx_blind")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 7, played_this_round = 1 } }
  local ls = CtxHand.levels_section() or ""
  check("CW5: L row has p column (times played this run)", ls:find("Pair,1,10,2,7", 1, true) ~= nil, ls)

  G.GAME.blind = { name = "The Ox", debuff = {} }
  G.GAME.current_round.most_played_poker_hand = "Flush"
  local bd = CtxBlind.blind_debuff_line() or ""
  check("CW5: Ox BD line names most_played", bd:find("most_played=Flush", 1, true) ~= nil, bd)
  G.GAME.current_round.most_played_poker_hand = nil
  local bd2 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Ox most_played derived from max played when engine field unset",
    bd2:find("most_played=Pair", 1, true) ~= nil, bd2)

  G.GAME.blind = { name = "The Eye", debuff = {} }
  local bd3 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Eye BD line lists hands played this round",
    bd3:find("played_this_round=Pair", 1, true) ~= nil, bd3)
  G.GAME.hands.Pair.played_this_round = 0
  local bd4 = CtxBlind.blind_debuff_line() or ""
  check("CW5: Eye BD line says none before first play",
    bd4:find("played_this_round=none", 1, true) ~= nil, bd4)
  G.GAME.blind = nil

  mock_state("Small blind selectable", "BLIND_SELECT")
  G.P_BLINDS = { bl_ox = { name = "The Ox", dollars = 5, debuff = {}, boss = { min = 6 } } }
  G.GAME.round_resets.blind_choices = { Boss = "bl_ox" }
  G.GAME.current_round.most_played_poker_hand = "Two Pair"
  local q = (require("force.force_blind_select").build("") or {}).query or ""
  check("CW5: known Ox boss names most_played in the force",
    q:find("most-played hand (Two Pair)", 1, true) ~= nil, q)
  G.P_BLINDS = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local f = D.get_force_for_state("SELECTING_HAND")
  check("CW6: force does NOT offer simulate_hand (progress-only force set)", f and not has(f.actions, "simulate_hand"))
  check("CW6: simulate_hand still registered for SELECTING_HAND",
    has(A.get_valid_actions_for_state("SELECTING_HAND"), "simulate_hand"))
  check("CW6: simulate_hand is NON_PROGRESS", require("core.action_policy").NON_PROGRESS.simulate_hand == true)
  check("CW6: simulate_hand excluded from AVAIL (info action)", A.INFO_ACTIONS.simulate_hand == true)
end

do
  local HF = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.hands = {
    ["Full House"] = { visible = true, level = 1, chips = 40, mult = 4, played = 2 },
    ["Pair"] = { visible = true, level = 1, chips = 10, mult = 2, played = 5 },
  }
  G.jokers = { cards = {
    { ability = { name = "Joker", mult = 4 }, config = { center = { key = "j_joker" } } },
    { ability = { name = "Supernova", type = "Full House", t_mult = 3 }, config = { center = { key = "j_x" } } },
  }, config = { card_limit = 5 } }
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("7", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs"), card("Queen", "Hearts"), card("Queen", "Diamonds") }, highlighted = {} }
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[1], hc[2], hc[3], hc[6], hc[7] } },
      ["Pair"] = { { hc[6], hc[7] } },
    }, { hc[1], hc[2], hc[3], hc[6], hc[7] }, nil
  end
  local s = HF.summary()
  check("D1+D2: Ready row = base score + matching joker",
    s:find("Full House[1,2,3,6,7](lv1 40c x4)(J2 applies)", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("D1: non-conditional hand gets score only, no joker note",
    s:find("Pair[6,7](lv1 10c x2)", 1, true) ~= nil and s:find("Pair%[6,7%]%(lv1 10c x2%)%(J", 1) == nil,
    s:match("Ready:[^%.]*"))

  G.jokers.cards[2].ability = { name = "Joker2", mult = 2 }
  local s0 = HF.summary()
  check("D2: no conditional joker -> no applies note", s0:find("applies", 1, true) == nil, s0:match("Ready:[^%.]*"))
  G.jokers.cards[2].ability = { name = "Supernova", type = "Full House", t_mult = 3 }

  hc[1].debuff = true; hc[2].debuff = true
  local s2 = HF.summary()
  check("D4: partial debuff count on Ready row",
    s2:find("Full House[1,2,3,6,7](lv1 40c x4)(J2 applies)(2 debuffed~0)", 1, true) ~= nil, s2:match("Ready:[^%.]*"))
  hc[1].debuff = nil; hc[2].debuff = nil

  G.jokers.cards[1].config.center.key = "j_splash"
  local s3 = HF.summary()
  check("D6: Splash fact appended", s3:find("All played cards score (Splash).", 1, true) ~= nil, s3)
  G.FUNCS.get_poker_hand_info = nil
  G.jokers = nil
end

do
  local big = string.rep("x", 1900)
  local out = ContextCompact._enforce_budget("SELECTING_HAND",
    { "CTX:x", "STATE:SELECTING_HAND", "LP|Pair|played 3 cards", "L:small_levels", "J:" .. big }, "volatile")
  local blob = table.concat(out, "\n")
  check("D7: J and L both kept (no lossy drop)", blob:find("L:small_levels", 1, true) ~= nil and blob:find("\nJ:xx", 1, true) ~= nil, blob:sub(1, 120))
  check("D7: LP kept", blob:find("LP|Pair", 1, true) ~= nil)
end

-- shop I-row descriptions render >56-char text whole, no mid-sentence cut
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
  check("trunc: >56-char shop description renders whole", s:find(long_desc, 1, true) ~= nil, s:match("shop_jokers[^\n]*"))
  G.shop_jokers = nil; G.jokers = nil
end

do
  local P = require("render.palette")
  local Tn = require("core.tuning")
  P.reset_all_colors("neuro"); P.reset_all_colors("evil"); P.reset_all_colors("hiyori")
  local live = P.get_color("neuro", "ACCENT")
  local dft = P.default_color("neuro", "ACCENT")
  check("colour: defaults snapshotted", dft ~= nil and type(dft[1]) == "number")
  local function near(a, b) return math.abs(a - b) < 1e-9 end
  P.set_override("neuro", "ACCENT", 10 / 255, 20 / 255, 30 / 255)
  check("colour: override mutates live table in place",
    near(live[1], 10 / 255) and near(live[2], 20 / 255) and near(live[3], 30 / 255))
  local ser = Tn.serialize()
  check("colour: serialize emits NEURO_COLOR_NEURO_ACCENT=0A141E",
    ser:find("NEURO_COLOR_NEURO_ACCENT=0A141E", 1, true) ~= nil)
  local tmp = "test_color_roundtrip.env.tmp"
  local f = assert(io.open(tmp, "w")); f:write(ser); f:close()
  P.reset_all_colors("neuro")
  check("colour: reset-all restores snapshot values",
    near(live[1], dft[1]) and near(live[2], dft[2]) and near(live[3], dft[3]))
  check("colour: reset-all removes overrides from serialization",
    Tn.serialize():find("NEURO_COLOR_", 1, true) == nil)
  local applied = P.apply_overrides(dotenv.parse_file(tmp))
  os.remove(tmp)
  check("colour: round-trip load reapplies override",
    applied == 1 and near(live[1], 10 / 255) and near(live[3], 30 / 255))
  local evil = P.get_color("evil", "ACCENT")
  local evil_d = P.default_color("evil", "ACCENT")
  check("colour: neuro override does not leak into evil",
    near(evil[1], evil_d[1]) and near(evil[2], evil_d[2]) and near(evil[3], evil_d[3]))
  check("colour: color_keys skips non-colour entries (NAME/MOTION)", (function()
    for _, k in ipairs(P.color_keys("neuro")) do
      if k == "NAME" or k == "MOTION" then return false end
    end
    return #P.color_keys("neuro") > 0
  end)())
  P.reset_all_colors("neuro")
end

-- selftest row: Enter must not call SelfTest.start() when unavailable
do
  local real_selftest = require("core.selftest")
  local real_panel = package.loaded["hud.tuning_panel"]
  package.loaded["hud.tuning_panel"] = nil
  local st_started = 0
  package.loaded["core.selftest"] = {
    available = function() return false end,
    start = function() st_started = st_started + 1 return true end,
    running = function() return false end,
    status = function() return "selftest: idle" end,
    abort = function() end,
    results = function() return {} end,
    report_path = function() return nil end,
  }
  local Panel = require("hud.tuning_panel")
  check("selftest row: panel opens", Panel.toggle() == true)
  Panel.keypressed("up")
  Panel.keypressed("return")
  check("selftest row: start NOT called while unavailable", st_started == 0)
  package.loaded["core.selftest"].available = function() return true end
  Panel.keypressed("return")
  check("selftest row: start called once available", st_started == 1)
  check("selftest row: 'a' not swallowed when idle", Panel.keypressed("a") == false)
  package.loaded["core.selftest"].running = function() return true end
  check("selftest row: 'a' swallowed while running", Panel.keypressed("a") == true)
  G.NEURO.llm_paused = nil
  package.loaded["core.selftest"] = real_selftest
  package.loaded["hud.tuning_panel"] = real_panel
end

do
  local made = 0
  local prev_graphics = love.graphics
  love.graphics = { newFont = function(path, px) made = made + 1 return { path = path, px = px } end }
  local U2 = require("util.utils")
  local s1, b1 = U2.load_font_pair("f.ttf", 12, 14, 1.15)
  local s2, b2 = U2.load_font_pair("f.ttf", 12, 14, 1.15)
  check("font cache: same scaled request returns same objects", s1 == s2 and b1 == b2)
  check("font cache: px rounds to integer (14 x 1.15 -> 16)", b1.px == 16)
  local made_before = made
  U2.load_font_pair("f.ttf", 12, 14, 1.15)
  check("font cache: cached request allocates no new font", made == made_before)
  local s3, b3 = U2.load_font_pair("f.ttf", 12, 14, 0.5)
  check("font cache: different scale is a different size", s3 ~= s1 and s3.px == 6 and b3.px == 7)
  check("font cache: unscaled equals scale 1.0", select(2, U2.load_font_pair("f.ttf", 12, 14))
    == select(2, U2.load_font_pair("f.ttf", 12, 14, 1.0)))
  love.graphics = prev_graphics
end

do
  local real_panel = package.loaded["hud.tuning_panel"]
  package.loaded["hud.tuning_panel"] = nil
  local prev_graphics = love.graphics
  local prev_mouse = love.mouse
  local rect_calls = {}
  local stub_font = {
    getHeight = function() return 14 end,
    getWidth = function(_, s) return 7 * #tostring(s) end,
  }
  love.graphics = {
    getFont = function() return stub_font end,
    setFont = function() end,
    getWidth = function() return 1280 end,
    getHeight = function() return 720 end,
    setColor = function() end,
    setLineWidth = function() end,
    print = function() end,
    rectangle = function(mode) rect_calls[#rect_calls + 1] = mode end,
    line = function() end,
  }
  love.mouse = { getPosition = function() return -1, -1 end }
  local Shud = require("hud.state")
  local pf, pfs = Shud.panel_font, Shud.panel_font_small
  Shud.panel_font, Shud.panel_font_small = stub_font, stub_font
  local Tn = require("core.tuning")
  local real_save = Tn.save
  Tn.save = function() return true end
  local Panel = require("hud.tuning_panel")

  check("mouse: closed panel ignores clicks", Panel.mousepressed(640, 360, 1) == false)
  Panel.toggle()
  Panel.draw()
  local H = Panel._test.hit
  local defs = Tn.entries()
  check("mouse: layout valid after draw", H.valid == true and H.pw == 520)
  check("mouse: hitbox rows == visible items", H.n == #Panel._test.rows())
  check("mouse: row 3 resolves at its own y", Panel._test.row_at(H.px + 10, H.rows[3] + 2) == 3)
  check("mouse: title area resolves no row", Panel._test.row_at(H.px + 10, H.py + 1) == nil)
  check("mouse: outside panel x resolves nil", Panel._test.row_at(H.px - 5, H.rows[3] + 2) == nil)
  Panel.mousepressed(H.px + 10, H.rows[3] + 2, 1)
  local _, sel_now = Panel._test.state()
  check("mouse: click selects row 3", sel_now == 3)

  local orig_speed = Tn.get("NEURO_SPEED_MULT")
  Tn.set("NEURO_SPEED_MULT", 2.0)
  love.mouse.getPosition = function() return H.px + 10, H.rows[2] + 2 end
  check("wheel: consumed over panel", Panel.wheelmoved(0, 1) == true)
  check("wheel: adjust clamps at max", Tn.get("NEURO_SPEED_MULT") == 2.0)
  Panel.wheelmoved(0, -1)
  check("wheel: steps down from max", math.abs(Tn.get("NEURO_SPEED_MULT") - 1.95) < 1e-9)
  love.mouse.getPosition = function() return 0, 0 end
  check("wheel: not consumed outside panel", Panel.wheelmoved(0, 1) == false)
  Tn.set("NEURO_SPEED_MULT", orig_speed)

  Panel.mousepressed(H.t2_x + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to COLOURS", (Panel._test.state()) == 2)
  Panel.draw()
  local ckeys = require("render.palette").color_keys(require("render.palette").persona())
  check("mouse: page2 hitboxes rebuilt", H.n == #ckeys + 1 and H.hex_x > H.val_x)
  Panel.mousepressed(H.hex_x + H.hexw + H.hgap + 1, H.rows[1] + 2, 1)
  local _, _, em, ec = Panel._test.state()
  check("mouse: hex segment click enters edit on channel 2", em == true and ec == 2)
  Panel.mousepressed(H.px + 10, H.rows[1] + 2, 2)
  local _, _, em2 = Panel._test.state()
  check("mouse: right-click exits colour edit", em2 == false)

  local Pal = require("render.palette")
  Panel.keypressed("return")
  local _, sel_c = Panel._test.state()
  local swallowed = Panel.keypressed("0")
  Panel.keypressed("a"); Panel.keypressed("1"); Panel.keypressed("4"); Panel.keypressed("1"); Panel.keypressed("e")
  check("hex: typing is swallowed during colour edit", swallowed == true)
  check("hex: buffer holds the typed code", Panel._test.edit_hex() == "0a141e")
  local ckA = Pal.color_keys(Pal.persona())[sel_c]
  local colA = Pal.get_color(Pal.persona(), ckA)
  check("hex: typed code applies live to the row",
    math.abs(colA[1] - 0x0a / 255) < 1e-6 and math.abs(colA[2] - 0x14 / 255) < 1e-6
    and math.abs(colA[3] - 0x1e / 255) < 1e-6)
  Panel.keypressed("return")
  local _, _, emH = Panel._test.state()
  check("hex: enter exits edit and clears buffer", emH == false and Panel._test.edit_hex() == "")

  local sw = Panel._test.swatches
  local sx6 = H.sw_x + 5 * (H.sw + H.sw_gap) + 1
  check("swatch: 6th chip resolves at its x", Panel._test.swatch_at(sx6, H.sw_y + 1) == 6)
  Panel.mousepressed(sx6, H.sw_y + 1, 1)
  local _, sel_s = Panel._test.state()
  local ckB = Pal.color_keys(Pal.persona())[sel_s]
  local colB = Pal.get_color(Pal.persona(), ckB)
  local hx6 = sw[6]
  check("swatch: click applies preset hex to selected row",
    math.abs(colB[1] - tonumber(hx6:sub(1, 2), 16) / 255) < 1e-6
    and math.abs(colB[2] - tonumber(hx6:sub(3, 4), 16) / 255) < 1e-6
    and math.abs(colB[3] - tonumber(hx6:sub(5, 6), 16) / 255) < 1e-6)

  local bd = Panel._test.bool_def
  check("checkbox: on/off enum detected", bd({ values = { "off", "on" } }) and bd({ values = { "on", "off" } }))
  check("checkbox: 3-state enum is a cycle chip, not a checkbox",
    not bd({ values = { "off", "compact", "expanded" } }))
  check("checkbox: numeric def is not a checkbox", not bd({ step = 1, min = 0, max = 1 }))
  check("checkbox: state helper", Panel._test.checkbox_on("on") and not Panel._test.checkbox_on("off"))
  local n0 = #rect_calls
  Panel._test.draw_checkbox(0, 0, 12, true, 1, { 1, 0, 0 })
  local drew_on = #rect_calls - n0
  n0 = #rect_calls
  Panel._test.draw_checkbox(0, 0, 12, false, 1, { 1, 0, 0 })
  local drew_off = #rect_calls - n0
  check("checkbox: on = fill + border, off = border only", drew_on == 2 and drew_off == 1)

  Panel.mousepressed(H.t3_x + 2, H.tab_y + 2, 1)
  check("mouse: header tab switches to RUNTIME", (Panel._test.state()) == 3)
  Panel.draw()
  local rdefs = Tn.runtime_entries()
  check("runtime: hitbox rows == visible items", H.n == #Panel._test.rows())
  local glow_i
  for i, d in ipairs(rdefs) do if d.key == "NEURO_AI_CARD_GLOW" then glow_i = i end end
  local glow_before = Tn.get_raw("NEURO_AI_CARD_GLOW")
  love.mouse.getPosition = function() return H.px + 10, H.rows[glow_i + 1] + 2 end
  Panel.wheelmoved(0, 1)
  check("runtime: editable enum row toggles via wheel", Tn.get_raw("NEURO_AI_CARD_GLOW") ~= glow_before)
  Tn.set("NEURO_AI_CARD_GLOW", glow_before)
  love.mouse.getPosition = function() return -1, -1 end

  check("mouse: [X] closes panel", (function()
    Panel.mousepressed(H.cl_x + 2, H.cl_y + 2, 1)
    return Panel.is_open() == false and H.valid == false
  end)())
  check("mouse: clicks pass through after close", Panel.mousepressed(H.px + 10, H.py + 10, 1) == false)

  Tn.save = real_save
  Shud.panel_font, Shud.panel_font_small = pf, pfs
  love.graphics = prev_graphics
  love.mouse = prev_mouse
  G.NEURO.llm_paused = nil
  package.loaded["hud.tuning_panel"] = real_panel
end

-- fmt_num: %d wraps doubles >2^63 to INT64_MIN; must survive Balatro's endless scores without a wrong sign
do
  local U = require("util.utils")
  check("fmt_num: exact integer below 1e15", U.fmt_num(123456789) == "123456789")
  check("fmt_num: no scientific just under 1e15", U.fmt_num(999999999999999) == "999999999999999")
  check("fmt_num: 1e19 does not wrap to a negative INT64", U.fmt_num(1e19):sub(1, 1) ~= "-")
  check("fmt_num: 1e19 is compact scientific", U.fmt_num(1.23456e19) == "1.235e+19")
  check("fmt_num: huge negative keeps its sign", U.fmt_num(-9.9e20):sub(1, 1) == "-")
  check("fmt_num: zero and negative-zero both '0'", U.fmt_num(0) == "0" and U.fmt_num(-0.0) == "0")
  check("fmt_num: nil/nan coerce to '0'", U.fmt_num(nil) == "0" and U.fmt_num(0 / 0) == "0")
  local ok, res = pcall(string.format, "%d", 1e19)
  check("fmt_num: raw %d WOULD wrap or error (proves the bug exists)", not ok or res:sub(1, 1) == "-")
end

-- R4: the SDK doesn't actually enforce uniqueItems; validate it ourselves
do
  local SV = require("util.schema_validate")
  local arr = { type = "array", items = { type = "integer", minimum = 1 }, minItems = 1, maxItems = 5, uniqueItems = true }
  check("R4: valid indices pass", SV.validate_value(arr, { 1, 2, 3 }, "indices") == true)
  check("R4: minItems rejects empty", SV.validate_value(arr, {}, "indices") == false)
  check("R4: maxItems rejects >5", SV.validate_value(arr, { 1, 2, 3, 4, 5, 6 }, "indices") == false)
  check("R4: uniqueItems rejects dupes", SV.validate_value(arr, { 1, 1, 2 }, "indices") == false)
end

do
  local V = require("facts.card_area_util").validate_hand_indices
  local a = V({ 1, 2, 3 }, 8, 5); check("R5: clean indices accepted", type(a) == "table" and #a == 3)
  check("R5: out-of-range rejected (no silent drop of 99)", (V({ 1, 99 }, 8, 5)) == nil)
  check("R5: duplicate rejected", (V({ 1, 1 }, 8, 5)) == nil)
  check("R5: over-cap rejected", (V({ 1, 2, 3, 4, 5, 6 }, 8, 5)) == nil)
  check("R5: empty rejected", (V({}, 8, 5)) == nil)
end

do
  local by = {}; for _, dd in ipairs(A.get_static_actions()) do by[dd.name] = dd end
  local ph = by.play_hand and by.play_hand.schema and by.play_hand.schema.properties
    and by.play_hand.schema.properties.indices
  check("R4b: play_hand schema has minItems/maxItems/uniqueItems",
    ph and ph.minItems == 1 and ph.maxItems == 5 and ph.uniqueItems == true)
end

do
  G.NEURO.persona = "neuro"
  check("R2: choose_persona invalid once persona locked", A.is_action_valid("choose_persona") == false)
  G.NEURO.persona = "hiyori"
  check("R2: choose_persona valid at the identity gate", A.is_action_valid("choose_persona") == true)
  G.NEURO.persona = nil
end

-- R7: the server ignores a re-register of an already-registered name, so a changed action must unregister first
do
  local Bridge = require("core.bridge")
  local sent = {}
  local fake = setmetatable({ send = function(_, msg) sent[#sent + 1] = msg.command end }, { __index = Bridge })
  fake:register_actions({ { name = "foo", description = "first", schema = { type = "object" } } })
  check("R7: first register sends actions/register", has(sent, "actions/register"))
  sent = {}; fake:register_actions({ { name = "foo", description = "first", schema = { type = "object" } } })
  check("R7: identical contract does not resend", #sent == 0)
  sent = {}; fake:register_actions({ { name = "foo", description = "SECOND", schema = { type = "object" } } })
  check("R7: changed description unregisters the stale action", has(sent, "actions/unregister"))
  check("R7: changed description re-registers", has(sent, "actions/register"))
end

-- G1: regression for the 07-02 underplay bug where get_poker_hand_info returned an over-inclusive group (7 cards for Full House)
do
  local HandFacts = require("facts.hand_facts")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = {
    card("King", "Hearts"), card("King", "Spades"),
    card("4", "Clubs"), card("4", "Diamonds"), card("4", "Hearts"),
    card("9", "Spades"), card("2", "Clubs"),
  }, highlighted = {} }
  G.GAME.current_round.hands_left = 4; G.GAME.current_round.discards_left = 4
  local all = G.hand.cards
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.get_poker_hand_info = function(_) return "Full House", nil, { ["Full House"] = { all } } end
  local s = HandFacts.summary()
  G.FUNCS.get_poker_hand_info = nil
  local function count_idx(label)
    local m = s:match(label .. "%[([%d,]+)%]")
    if not m then return nil end
    local n = 1; for _ in m:gmatch(",") do n = n + 1 end; return n
  end
  check("G1: Full House index is exactly 5 (not the over-inclusive engine group)", count_idx("Full House") == 5, s)
  check("G1: Two Pair index (if listed) is exactly 4", count_idx("Two Pair") == nil or count_idx("Two Pair") == 4, s)
end

print(string.format("\n==== anti-regress: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
