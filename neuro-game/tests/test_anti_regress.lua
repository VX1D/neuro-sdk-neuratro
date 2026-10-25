require("tests.stubs").setup({ love = "lazy", G = "board" })
local ES = require("tests.engine_cards").states()

local A = require("core.actions")
local D = require("core.dispatcher")
local ActionResult = require("core.action_result")
local Config = require("core.config")
local json = require("util.neuro_json")

local function action_error(value)
  return ActionResult.is_error(value) and ActionResult.normalize(value).message or tostring(value or "")
end
local ContextCompact = require("context.context_compact")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")

local check, done = require("tests.helpers").harness("anti-regress")
local has = require("tests.helpers").has
local card = require("tests.fake_cards").bare
local EngineCards = require("tests.engine_cards")

local function in_state(state)
  G.STATES = EngineCards.states()
  G.STATE = G.STATES[state]
  G.CONTROLLER = G.CONTROLLER or { locked = false }
end

local function mock_state(desc_match, state) return require("tests.helpers").mock_state(desc_match, state, true) end
local ActionReceipt = require("core.action_result")
local function is_execution_result(r) return ActionReceipt.is_receipt(r) or ActionReceipt.is_outcome(r) end
local function engine_commits()
  local function commit(counter)
    return function()
      local hand = G.hand
      for _, c in ipairs(hand.highlighted) do
        for i = #hand.cards, 1, -1 do if hand.cards[i] == c then table.remove(hand.cards, i) end end
      end
      hand.highlighted = {}
      G.GAME.current_round[counter] = G.GAME.current_round[counter] - 1
    end
  end
  G.FUNCS.play_cards_from_highlighted = commit("hands_left")
  G.FUNCS.discard_cards_from_highlighted = commit("discards_left")
end
local function run_commit(c)
  local ok, r = pcall(c)
  if ok and ActionReceipt.is_receipt(r) then ActionReceipt.settle(r, ActionReceipt.now(), G.NEURO.run_generation) end
  return ok
end
local function execution_text(r)
  if type(r) ~= "table" then return tostring(r) end
  return tostring(r.status or r.name) .. ": " .. tostring(r.message or r.applied_message)
end

do
  mock_state("With overlay present", "GAME_OVER")
  local f = require("force.force_router").get_force_for_state("GAME_OVER")
  check("GAME_OVER+overlay force omits the flaky exit_overlay_menu",
    f and not has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+overlay force offers open_run_setup (new-run path)",
    f and has(f.actions, "open_run_setup"))
end

do
  mock_state("With unlock popup", "GAME_OVER")
  local f = require("force.force_router").get_force_for_state("GAME_OVER")
  check("GAME_OVER+unlock popup forces exit_overlay_menu",
    f and has(f.actions, "exit_overlay_menu"), f and table.concat(f.actions or {}, ","))
  check("GAME_OVER+unlock popup force is exit-only (not open_run_setup under the popup)",
    f and not has(f.actions, "open_run_setup"))
end

do
  mock_state("Overlay blocks during hand selection", "SELECTING_HAND")
  local valid = A.get_valid_actions_for_state("SELECTING_HAND")
  check("blocking overlay publishes only exit_overlay_menu",
    #valid == 1 and valid[1] == "exit_overlay_menu", table.concat(valid, ","))
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
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
  local avail = A.get_valid_actions_for_state("SHOP")
  check("available actions include set_joker_order (2 jokers)", has(avail, "set_joker_order"))
end

do
  mock_state("Normal", "SHOP")
  require("core.gate").reset()
  G.NEURO.force_window = nil
  G.NEURO.force_window = nil
  G.jokers = { cards = {
    { ability = { name = "Joker" }, sell_cost = 3, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, sell_cost = 3, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = require("force.force_router").get_force_for_state("SHOP")
  check("SHOP force offers set_joker_order among its tools",
    f and has(f.actions, "set_joker_order") and has(f.tools, "set_joker_order"))
  check("SHOP force offers record_plan among its tools whenever planning is on",
    f and has(f.actions, "record_plan") and has(f.tools, "record_plan"))
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.jokers = { cards = {
    { ability = { name = "Joker" }, config = { center = { key = "j_joker" } } },
    { ability = { name = "Blueprint" }, config = { center = { key = "j_blueprint" } } },
  }, config = { card_limit = 5 } }
  local f = require("force.force_blind_select").build()
  check("TW-01: blind force offers set_joker_order when advice can recommend it",
    f and has(f.actions, "set_joker_order"))
  check("TW-01: blind force offers record_plan whenever planning is on",
    f and has(f.actions, "record_plan"))
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
  local s_full = require("tests.helpers").force_frame("SHOP")
  local constraints = s_full:match("\n## Constraints\n(.-)\n## ") or ""
  check("shop frame's state warns: Buffoon pack + joker slots full",
    constraints:find(WARN, 1, true) ~= nil, s_full)

  local blob = ContextCompact.build("SHOP", A.get_valid_actions_for_state("SHOP"))
  local row = blob:match('## Shop boosters %(area "shop_booster"%)\n([^\n]*)')
  check("ctx: shop_booster type column = Buffoon (not generic Booster)",
    row ~= nil and row:find("(Buffoon)", 1, true) ~= nil, row)

  mock_state("Normal", "SHOP")
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_booster = { cards = { buffoon() } }
  local q_open = (require("force.force_router").get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning when joker slots open", q_open:find(WARN, 1, true) == nil)

  mock_state("Normal", "SHOP")
  full_jokers()
  G.shop_booster = { cards = { arcana() } }
  local q_arc = (require("force.force_router").get_force_for_state("SHOP") or {}).query or ""
  check("shop force: no Buffoon warning for a non-joker pack", q_arc:find(WARN, 1, true) == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = require("tests.helpers").force_payload("SELECTING_HAND")
  check("Close: near Flush (4 of a suit)", q:find("One card away: Flush") ~= nil, q:match("Shape:[^\n]*"))
  require("tests.engine_cards").install_smods({ four_fingers = function(t) return (t == "flush" or t == "straight") and 4 or 5 end })
  G.FUNCS.get_poker_hand_info = function(_)
    local hc = G.hand.cards
    return "Flush", nil, { Flush = { hc[1], hc[2], hc[3], hc[4] }, ["High Card"] = { hc[1] } }, { hc[1], hc[2], hc[3], hc[4] }, nil
  end
  local q2 = require("tests.helpers").force_payload("SELECTING_HAND")
  check("Ready: Flush shown", q2:find("Ready to play now:[^\n]*Flush") ~= nil)
  check("near Flush deduped when ready", q2:find("One card away") == nil)
  require("tests.engine_cards").install_smods()
  G.FUNCS.get_poker_hand_info = nil
  G.GAME.current_round.discards_left = 0
  local q3 = require("tests.helpers").force_payload("SELECTING_HAND")
  check("no Close when discards=0", q3:find("Close:") == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"), card("9", "Hearts"), card("?", "?", true) }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  local q = require("tests.helpers").force_payload("SELECTING_HAND")
  check("stone not counted (suit_max=4, near Flush)", q:find("most cards of one suit 4") and q:find("One card away: Flush"))
end

do
  local function H(name) return D.get_action_handler(name) end
  mock_state("Normal", "SELECTING_HAND")
  G.hand = require("tests.helpers").card_area({ cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") },
    highlighted = {} })
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").stub("Pair")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  local _, first_play_err = H("play_hand")({ indices = { 1, 2 } })
  check("atomic play first requests review", ActionResult.is_error(first_play_err))
  require("core.gate").delivered(first_play_err)

  local c1, e1 = H("play_hand")({})
  check("play_hand no indices -> error", c1 == nil and ActionResult.is_error(e1))
  local c_hl, e_hl = H("play_hand")({ indices = { 1, 2 } })
  check("repeating the reviewed play does not produce an execution closure",
    c_hl == nil and ActionResult.is_error(e_hl), e_hl)
  Config.set("NEURO_CONFIRM_HAND", "off")
  require("core.gate").reset()
  c_hl = H("play_hand")({ indices = { 1, 2 }, _action_id = "ar-play" })
  local ok_hl, r_hl = pcall(c_hl)
  check("confirmation toggle off restores immediate play execution",
    type(c_hl) == "function" and ok_hl and is_execution_result(r_hl), execution_text(r_hl))
  Config.set("NEURO_CONFIRM_HAND", "on")

  G.GAME.blind = { debuff = { h_size_ge = 3 } }
  local c4, e4 = H("play_hand")({ indices = { 1 } })
  check("SH-2: boss min-cards rejects undersized play", c4 == nil and ActionResult.is_error(e4), e4)
  G.GAME.blind = nil

  local c_dis = H("discard_hand")({ indices = { 1 }, _action_id = "ar-discard" })
  local ok_dis, r_dis = pcall(c_dis)
  check("atomic discard -> closure runs to a verifiable result", type(c_dis) == "function" and ok_dis
    and is_execution_result(r_dis), execution_text(r_dis))
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local c5, e5 = H("sell_card")({ area = "jokers", index = 1 })
  check("sell_card empty area -> error", c5 == nil and ActionResult.is_error(e5))

  local expensive = card("A", "Spades"); expensive.cost = 100
  G.shop_jokers = { cards = { expensive } }
  G.GAME.dollars = 4; G.NEURO.reserved_dollars = 0
  local c6, e6 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy_from_shop unaffordable -> error", c6 == nil and ActionResult.is_error(e6))

  in_state("SELECTING_HAND")
  G.consumeables = { cards = { EngineCards.consumable("c_lovers") } }
  G.hand = { cards = {}, highlighted = {} }
  local c7, e7 = H("use_consumable")({ area = "consumeables", index = 1 })
  check("use_consumable needs hand target but no hand -> error", c7 == nil and ActionResult.is_error(e7))
  local planet = EngineCards.consumable("c_pluto")
  G.consumeables = { cards = { planet } }
  local c_uc = H("use_consumable")({ area = "consumeables", index = 1, _action_id = "ar-use" })
  local ok_uc, r_uc = pcall(c_uc)
  check("use_consumable no-target -> closure runs to a verifiable result", type(c_uc) == "function" and ok_uc
    and is_execution_result(r_uc), execution_text(r_uc))

end

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
    check("context names the card (Ace of Hearts)", blob:find("Ace of Hearts", 1, true) ~= nil)
  end
end

do
  local State = require("core.state")
  require("tests.helpers").in_engine_state("MENU")
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  check("RUN_SETUP reachable via overlay detector", State.get_state_name() == "RUN_SETUP")
  local f = require("force.force_router").get_force_for_state("RUN_SETUP")
  check("run-setup force offers start_run (no deck-pick trap)", has((f or {}).actions, "start_run"))
  require("tests.helpers").in_engine_state("GAME_OVER")
  check("GAME_OVER + open run-setup overlay resolves to RUN_SETUP", State.get_state_name() == "RUN_SETUP")
  check("GAME_OVER-hosted run-setup force offers start_run",
    has((require("force.force_router").get_force_for_state(State.get_state_name()) or {}).actions, "start_run"))
  require("tests.helpers").in_engine_state("BLIND_SELECT")
  local ok_bs, fbs = pcall(require("force.force_router").get_force_for_state, "BLIND_SELECT")
  check("BLIND_SELECT with a lingering run-setup overlay does NOT serve the RUN_SETUP force",
    not (ok_bs and has((fbs or {}).actions, "start_run")))
  require("tests.helpers").in_engine_state("MENU")
  G.OVERLAY_MENU = nil
  check("no overlay -> not RUN_SETUP", State.get_state_name() ~= "RUN_SETUP")
  G.STATES = nil; G.STATE = nil
end

do
  local tarot = EngineCards.consumable("c_emperor")
  local H = D.get_action_handler
  mock_state("Normal", "SELECTING_HAND")
  in_state("SMODS_BOOSTER_OPENED")
  G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
  G.pack_cards = { cards = { tarot } }
  G.booster_pack = G.pack_cards
  local c, e = H("choose_pack_card")({ area = "pack_cards", index = 1 })
  check("choose_pack_card rejects full-consumable pack pick with consumable message",
    c == nil and ActionResult.is_error(e), e)
  G.pack_cards = nil; G.booster_pack = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local jA = { ability = { set = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } }, sell_cost = 3 }
  local jB = { ability = { set = "Joker" }, config = { center = { key = "j_blueprint", set = "Joker" } }, sell_cost = 3 }
  G.jokers = { cards = { jA, jB }, config = { card_limit = 5 } }
  local ctx1 = ContextCompact.build("SELECTING_HAND", nil)
  G.jokers.cards = { jB, jA }
  local ctx2 = ContextCompact.build("SELECTING_HAND", nil)
  check("set_joker_order changes the context the model sees", ctx1 ~= ctx2)
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
  require("tests.helpers").in_engine_state("SHOP")
  G.GAME = G.GAME or {}
  G.GAME.dollars = 6
  G.GAME.current_round = G.GAME.current_round or {}
  G.GAME.current_round.reroll_cost = 3
  G.NEURO.force_window = nil
  G.jokers = G.jokers or { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { { sort_id = 4401, cost = 4, sell_cost = 2, ability = { name = "Jolly Joker", set = "Joker" },
    config = { center = { key = "j_jolly", set = "Joker" } } } } }
  require("tests.helpers").open_force("SHOP", { "reroll_shop", "buy_from_shop" })
  G.NEURO.econ_plan_ok = true
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
  G.NEURO.force_window = nil
  G.NEURO.econ_plan_ok = nil
  G.STATES = nil; G.STATE = nil
end

do
  mock_state("Buffoon pack with a joker", "SMODS_BOOSTER_OPENED")
  local normal_force = require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED")
  G.NEURO.pack_exit_pending = true
  check("terminal pack pick suppresses stale follow-up force",
    normal_force ~= nil and require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED") == nil)
  G.NEURO.pack_exit_pending = nil
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
    require("tests.helpers").in_engine_state("SMODS_BOOSTER_OPENED")
  G.GAME = G.GAME or {}; G.GAME.STOP_USE = nil
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SMODS_BOOSTER_OPENED", { "choose_pack_card" })
  G.NEURO.state_enter_serial = 45
  G.NEURO.gates = nil
  G.NEURO.is_transition_cooldown = function() return true end
  local ok, msg, terminal, code = Enforce.pre_action(nil, "choose_pack_card")
  check("TW-07: transition cooldown still blocks execution before the decision window",
    ok == false, msg)
  check("TW-07: a forced action's transition block is terminal, so the force is not retried into it",
    code == "TRANSITION_PENDING" and terminal == true, tostring(code))
  G.NEURO.is_transition_cooldown = nil
  G.GAME.STOP_USE = 1
  local ok_su, _, terminal_su = Enforce.pre_action(nil, "choose_pack_card")
  check("TW-07: the engine-busy guard is terminal for a forced action too",
    ok_su == false and terminal_su == true, tostring(terminal_su))
  G.GAME.STOP_USE = nil
  G.NEURO.force_window = nil
  G.NEURO.is_transition_cooldown = function() return true end
  local ok2, msg2, terminal2, code2 = Enforce.pre_action(nil, "choose_pack_card")
  G.NEURO.is_transition_cooldown = nil
  check("TW-07: outside a force the same block stays a plain failure",
    ok2 == false and terminal2 == false and code2 == "TRANSITION_PENDING", tostring(code2) .. " / " .. tostring(msg2))
  G.NEURO.state_enter_serial = nil; G.STATES = nil; G.STATE = nil
end

do
  local HandHandlers = require("handlers.hand_handlers")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs") }, highlighted = {} }
  G.play = { cards = { card("K", "Spades") } }
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local exec, err = HandHandlers.handle_play_hand({ indices = { 1 } })
  check("TW-08: a hand still resolving does not execute play_hand",
    exec == nil and ActionResult.is_error(err), tostring(err))
  check("TW-08: the forced play_hand is refused terminally instead of retrying the force into the same wall",
    err and err.reason_code == "TRANSITION_PENDING" and ActionResult.terminal(err.reason_code, true) == true,
    err and tostring(err.reason_code))
  G.NEURO.force_window = nil
  local _, err_free = HandHandlers.handle_play_hand({ indices = { 1 } })
  check("TW-08: outside a force the same block stays a plain failure",
    err_free and err_free.reason_code == "TRANSITION_PENDING"
      and ActionResult.terminal(err_free.reason_code, false) == false,
    err_free and tostring(err_free.reason_code))
  G.play = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local dh1 = card("5", "Hearts"); dh1.debuff = true
  local dh2 = card("5", "Spades"); dh2.debuff = true
  G.hand = { cards = { dh1, dh2, card("9", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, dh2 }, ["High Card"] = { dh1 } }, { dh1, dh2 }, nil
  end
  local q = require("tests.helpers").force_payload("SELECTING_HAND")
  check("all-debuffed Ready hand dropped (scores 0)", q:find("Ready:[^\n]*Pair") == nil, q:match("Ready:[^\n]*") or "(no Ready line)")
  check("debuffed-card count surfaced", q:find("DEBUFFED") ~= nil)

  local pd = card("5", "Diamonds")
  G.hand = { cards = { dh1, pd, card("9", "Clubs") }, highlighted = {} }
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, { Pair = { dh1, pd }, ["High Card"] = { dh1 } }, { dh1, pd }, nil
  end
  local qp = require("tests.helpers").force_payload("SELECTING_HAND")
  G.FUNCS.get_poker_hand_info = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local cl = {}
  for _, r in ipairs({ "2", "5", "7", "9" }) do local c = card(r, "Clubs"); c.debuff = true; cl[#cl + 1] = c end
  G.hand = { cards = { cl[1], cl[2], cl[3], cl[4], card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.FUNCS.get_poker_hand_info = nil
  local q = require("tests.helpers").force_payload("SELECTING_HAND")
  check("debuffed-suit near-Flush not advertised in Close", q:find("near Flush") == nil, q:match("Close:[^\n]*") or "(no Close line)")
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("9", "Clubs"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3

  G.hand.cards[2].ability = { forced_selection = true }
  G.GAME.blind = { name = "Cerulean Bell", disabled = false, debuff = {} }
  local H = D.get_action_handler
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  local c_omit, e_omit = H("play_hand")({ indices = { 1, 3 } })
  check("play omitting locked card rejected", c_omit == nil and ActionResult.is_error(e_omit), e_omit)
  Config.set("NEURO_CONFIRM_HAND", "off")
  local c_ok = H("play_hand")({ indices = { 1, 2, 3 } })
  Config.set("NEURO_CONFIRM_HAND", "on")
  check("play including locked card accepted", type(c_ok) == "function")

  local c_disc, e_disc = H("discard_hand")({ indices = { 1 } })
  check("discard omitting locked card rejected", c_disc == nil and ActionResult.is_error(e_disc), e_disc)

  G.hand.cards[2].ability = nil
  G.GAME.blind = nil
end

do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  local function shop_item(c) local it = card("A", "Spades"); it.cost = c; return it end

  G.jokers = { cards = {} }; G.GAME.dollars = 0; G.GAME.bankrupt_at = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  local b0, e0 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("buy with $0 rejected (floor $0)", b0 == nil and ActionResult.is_error(e0))

  G.GAME.dollars = 5; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5), shop_item(5) } }
  local saved_manager, saved_Event = G.E_MANAGER, rawget(_G, "Event")
  local queued = {}
  G.E_MANAGER = { add_event = function(_, event) queued[#queued + 1] = event end }
  _G.Event = function(event) return event end
  local b1 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  if type(b1) == "function" then b1() end
  check("first buy execution reserves $5", type(b1) == "function" and (tonumber(G.NEURO.reserved_dollars) or 0) == 5)
  local b2, e2 = H("buy_from_shop")({ area = "shop_jokers", index = 2 })
  check("second rapid buy rejected (reserved-aware)", b2 == nil and ActionResult.is_error(e2))
  G.NEURO._reservation_epoch = (tonumber(G.NEURO._reservation_epoch) or 0) + 1
  G.NEURO.reserved_dollars = 5
  if queued[2] and queued[2].func then queued[2].func() end
  check("stale purchase event does not release a new shop reservation", G.NEURO.reserved_dollars == 5)
  G.E_MANAGER, _G.Event = saved_manager, saved_Event

  G.GAME.bankrupt_at = -20
  G.GAME.dollars = 0; G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(5) } }
  check("Credit Card allows buying into debt (floor -$20)", type(H("buy_from_shop")({ area = "shop_jokers", index = 1 })) == "function")
  G.NEURO.reserved_dollars = 0
  G.shop_jokers = { cards = { shop_item(25) } }
  local b3, e3 = H("buy_from_shop")({ area = "shop_jokers", index = 1 })
  check("Credit Card caps debt at -$20 ($25 rejected)", b3 == nil and ActionResult.is_error(e3))

  G.jokers = { cards = {} }; G.NEURO.reserved_dollars = 0
end

do
  G.NEURO.last_failed_action = "choose_pack_card"
  G.NEURO.last_failed_reason = "the consumable could not be used"
  local function clean(query)
    return type(query) == "string" and query:find("rejected", 1, true) == nil
      and query:find("the consumable could not be used", 1, true) == nil
  end

  mock_state("Small blind selectable", "BLIND_SELECT")
  local okb, rb = pcall(require("force.force_router").get_force_for_state, "BLIND_SELECT")
  check("BLIND_SELECT force carries no rejection prose after a failure",
    okb and type(rb) == "table" and clean(rb.query),
    okb and rb and rb.query)

  G.GAME.pack_choices = 1
  G.pack_cards = { cards = { card("2", "Hearts") } }
  G.STATES = G.STATES or {}
  G.STATES.SMODS_BOOSTER_OPENED = G.STATES.SMODS_BOOSTER_OPENED or 777
  G.STATE = G.STATES.SMODS_BOOSTER_OPENED
  local okp, rp = pcall(require("force.force_router").get_force_for_state, "SMODS_BOOSTER_OPENED")
  check("PACK force carries no rejection prose after a failure",
    okp and type(rp) == "table" and clean(rp.query), okp and rp and rp.query)
  G.GAME.pack_choices = nil; G.pack_cards = nil
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.validate")
  mock_state("Buffoon pack with a joker", "SMODS_BOOSTER_OPENED")
  G.jokers = { cards = {} }
  TG.reset_run_state(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 0
  local f0 = require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED")
  check("pack offers choose_pack_card once settled (STOP_USE=0)", f0 and has(f0.actions or {}, "choose_pack_card"),
    f0 and table.concat(f0.actions or {}, ","))

  TG.reset_run_state(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 4
  local f1 = require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED")
  local skip_only = f1 and f1.actions and #f1.actions == 1 and f1.actions[1] == "skip_pack"
  check("pack NEVER ships skip-only while choose_pack_card settles (defers instead)", not skip_only,
    f1 and table.concat(f1.actions or {}, ",") or "nil (deferred)")
  G.GAME.STOP_USE = 0; TG.reset_run_state(); Router._guard_defer_at = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.validate")
  local jk = function(k) return { ability = { set = "Joker", name = k }, config = { center = { key = k, set = "Joker" } }, sell_cost = 3 } end
  mock_state("Buffoon pack with a joker", "SMODS_BOOSTER_OPENED")
  G.jokers = { cards = { jk("j_a"), jk("j_b"), jk("j_c"), jk("j_d"), jk("j_e") }, config = { card_limit = 5 } }
  TG.reset_run_state(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 0
  local f0 = require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED")
  check("settled full-slot pack offers sell_card as a tool",
    f0 and has(f0.tools or {}, "sell_card"),
    f0 and table.concat(f0.actions or {}, ",") or "nil")
  TG.reset_run_state(); Router._guard_defer_at = nil
  G.GAME.STOP_USE = 4
  local f1 = require("force.force_router").get_force_for_state("SMODS_BOOSTER_OPENED")
  local sell_only = f1 and f1.actions and #f1.actions == 1 and f1.actions[1] == "sell_card"
  check("pack NEVER ships sell-only while choose_pack_card settles (defers)", not sell_only,
    f1 and table.concat(f1.actions or {}, ",") or "nil (deferred)")
  G.GAME.STOP_USE = 0; TG.reset_run_state(); Router._guard_defer_at = nil
end

do
  local Router = require("force.force_router")
  local TG = require("core.validate")
  local function move_tokens(q, actions)
    local names = {}
    for _, name in ipairs(actions or {}) do
      if q:find("Use the " .. name .. " action", 1, true) then names[#names + 1] = name end
    end
    return names
  end
  mock_state("Normal", "SHOP")
  G.GAME.STOP_USE = 0
  TG.reset_run_state(); Router._guard_defer_at = nil
  G.CONTROLLER = { locks = { leave_shop = true } }
  local f_lock = require("force.force_router").get_force_for_state("SHOP")
  local adv_lock = move_tokens((f_lock or {}).query or "", (f_lock or {}).actions)
  check("guard-locked leave_shop not advertised", not has(adv_lock, "leave_shop"),
    table.concat(adv_lock, ","))
  check("guard-locked leave_shop not in accepted set", not has((f_lock or {}).actions or {}, "leave_shop"),
    table.concat((f_lock or {}).actions or {}, ","))
  G.CONTROLLER = nil; TG.reset_run_state(); Router._guard_defer_at = nil
end

do
  local HH = require("handlers.hand_handlers")
  mock_state("Normal", "SELECTING_HAND")
  local cc = { card("2", "Hearts"), card("3", "Hearts"), card("4", "Hearts"), card("5", "Hearts") }
  G.hand = { cards = cc, highlighted = { cc[1], cc[2], cc[3], cc[4] } }
  G.GAME.current_round.hands_left = 3
  G.GAME.blind = { debuff = { h_size_le = 3 } }
  G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0
  local fn_over, err_over = HH.handle_play_hand({ indices = { 1, 2, 3, 4 } })
  check("h_size_le rejects oversized play", fn_over == nil and ActionResult.is_error(err_over) and action_error(err_over):find("at most 3") ~= nil, err_over)
  Config.set("NEURO_CONFIRM_HAND", "off")
  check("h_size_le allows a play within the limit", type(HH.handle_play_hand({ indices = { 1, 2, 3 } })) == "function")
  Config.set("NEURO_CONFIRM_HAND", "on")

  G.GAME.blind = nil
end

do
  local H = D.get_action_handler
  mock_state("Normal", "SHOP")
  G.GAME.dollars = 20; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  local called, captured_id, use_called
  G.FUNCS.buy_from_shop = function(e) called = true; captured_id = e.config.id end
  G.FUNCS.use_card = function(e) use_called = true end
  local events = require("tests.helpers").event_manager()

  local voucher = require("tests.engine_cards").card({ cost = 5, ability = { set = "Voucher" }, config = { center = { key = "v_overstock" } } })
  G.shop_vouchers = { cards = { voucher } }
  local _, first_err = H("buy_from_shop")({ area = "shop_vouchers", index = 1 })
  local first = first_err
  check("voucher buy asks for confirmation first", type(first) ~= "function", type(first))
  require("core.gate").delivered(first_err)
  local cv = H("buy_from_shop")({ area = "shop_vouchers", index = 1, _action_id = "ar-voucher" })
  check("voucher buy -> exec closure", type(cv) == "function")
  if cv then pcall(cv); events:run() end
  check("voucher routed via use_consumable, not buy_from_shop", use_called == true and called == nil)

  use_called = nil
  G.NEURO.reserved_dollars = 0
  local pack = require("tests.engine_cards").card({ cost = 4, ability = { set = "Booster" }, config = { center = { key = "p_arcana" } } })
  G.shop_booster = { cards = { pack } }
  local cb = H("buy_from_shop")({ area = "shop_booster", index = 1, _action_id = "ar-booster" })
  if cb then pcall(cb); events:run() end
  check("booster routed via use_consumable, not buy_from_shop", use_called == true and called == nil)

  called, captured_id = nil, nil
  G.NEURO.reserved_dollars = 0
  local plain = card("A", "Spades"); plain.cost = 5
  G.shop_jokers = { cards = { plain } }
  local cj = H("buy_from_shop")({ area = "shop_jokers", index = 1, _action_id = "ar-plain" })
  if cj then pcall(cj); events:run() end
  check("plain buy carries no buy_and_use id", called == true and captured_id == nil)

  G.NEURO.reserved_dollars = 0
  in_state("SHOP")
  local tarot = EngineCards.consumable("c_lovers", { cost = 5 })
  G.shop_jokers = { cards = { tarot } }
  local ct, et = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true })
  check("hand-targeting consumable use=true rejected", ct == nil and ActionResult.is_error(et), et)

  called, captured_id = nil, nil
  local planet = EngineCards.consumable("c_pluto", { cost = 5 })
  G.shop_jokers = { cards = { planet } }
  local cp = H("buy_from_shop")({ area = "shop_jokers", index = 1, use = true, _action_id = "ar-planet" })
  check("Planet use=true accepted", type(cp) == "function")
  if cp then pcall(cp); events:run() end
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
  check("select_blind resolves blind_choices override", type(c1) == "function" and ok1 and captured == G.P_BLINDS.bl_custom_small, tostring(r1))
  check("select_blind finishes without receipt text", ok1 and ActionReceipt.is_done(r1) and r1.message == nil, tostring(r1))
  captured = nil
  G.GAME.round_resets.blind_choices = nil
  local c2 = H("select_blind")({ blind = "small" })
  if c2 then pcall(c2) end
  check("select_blind falls back to bl_small", captured == G.P_BLINDS.bl_small)
  G.FUNCS.select_blind = nil
  G.P_BLINDS = nil
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  require("tests.helpers").in_engine_state("BLIND_SELECT")
  local saved_ante = G.GAME.round_resets.ante
  G.P_BLINDS = { bl_ox = { name = "The Ox" } }
  G.GAME.round_resets.blind_choices = { Boss = "bl_ox" }
  G.GAME.round_resets.blind_states = { Boss = "Select" }
  G.GAME.round_resets.ante = 3
  G.GAME.blind_on_deck = "Boss"
  G.NEURO.blind_plan_ok = false
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("BLIND_SELECT", { "select_blind" })
  G.NEURO.gates = nil
  local ok1, e1 = Enforce.pre_action(nil, "select_blind")
  local captured
  G.FUNCS.select_blind = function(e) captured = e.config.ref_table end
  local exec = ok1 and H("select_blind")({ blind = "boss" })
  if type(exec) == "function" then pcall(exec) end
  check("inline blind plan removes separate boss-review bounce",
    ok1 == true and e1 == nil and type(exec) == "function" and captured == G.P_BLINDS.bl_ox, e1)
  G.FUNCS.select_blind = nil; G.P_BLINDS = nil
  G.GAME.round_resets.blind_choices = nil; G.GAME.round_resets.blind_states = nil
  G.GAME.round_resets.ante = saved_ante
  G.GAME.blind_on_deck = nil; G.NEURO.blind_plan_ok = nil
  G.NEURO.force_window = nil
  G.NEURO.gates = nil
end

do
  local H = D.get_action_handler
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.GAME.round_resets.blind_states = { Small = "Select" }
  G.GAME.round_resets.blind_tags = { Small = "tag_handy", Big = "tag_handy" }
  G.GAME.blind_on_deck = "Small"
  G.blind_select_opts = { small = { get_UIE_by_ID = function() return { config = { ref_table = {} } } end } }
  local skipped = false
  G.FUNCS.skip_blind = function() skipped = true end
  local c1 = H("skip_blind")({})
  if type(c1) == "function" then pcall(c1) end
  check("skip executes immediately (no think gate)", type(c1) == "function" and skipped == true)
  G.FUNCS.skip_blind = nil; G.blind_select_opts = nil
  G.GAME.round_resets.blind_states = nil; G.GAME.blind_on_deck = nil
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
  require("tests.helpers").in_engine_state("SHOP")
  G.GAME = G.GAME or {}
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SHOP", { "leave_shop" })
  G.NEURO.gates = nil
  local function roster(specs)
    local cards = {}
    for _, s in ipairs(specs) do
      cards[#cards + 1] = { config = { center = { key = s[1] } }, ability = s[2] }
    end
    return { cards = cards, config = { card_limit = 5 } }
  end
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_greedy_joker", { mult = 3 } } })
  check("joker-order think stays silent on an all-additive roster (order is a no-op)",
    Enforce.pre_action(nil, "leave_shop") == true)
  G.NEURO.gates = nil
  G.jokers = roster({ { "j_scary_face", { set = "Joker", bonus = 50 } }, { "j_cavendish", { x_mult = 3 } } })
  check("joker-order think stays silent on chips+xMult (chips position is irrelevant)",
    Enforce.pre_action(nil, "leave_shop") == true)
  G.NEURO.gates = nil
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_cavendish", { x_mult = 3 } } })
  local ok1, msg1 = Enforce.pre_action(nil, "leave_shop")
  check("joker-order think fires when an xMult sits with additive jokers",
    ok1 == false and type(msg1) == "string", msg1)
  G.jokers = roster({ { "j_cavendish", { x_mult = 3 } }, { "j_joker", { mult = 4 } } })
  check("joker-order think silent on reorder-only (composition unchanged, repeat commits)",
    Enforce.pre_action(nil, "leave_shop") == true)
  G.jokers = roster({ { "j_joker", { mult = 4 } }, { "j_blueprint", {} } })
  check("joker-order think re-fires when the joker set changes",
    Enforce.pre_action(nil, "leave_shop") == false)
  G.jokers = nil
  G.NEURO.force_window = nil
  G.NEURO.gates = nil
  G.STATES = nil; G.STATE = nil
end

do
  mock_state("Normal", "SHOP")
  require("tests.helpers").in_engine_state("SHOP")
  G.shop = G.shop or {}
  G.jokers = { cards = {
    { ability = { name = "Joker" }, config = { center = { key = "j_joker" } }, states = {} },
    { ability = { name = "Blueprint" }, config = { center = { key = "j_blueprint" } }, states = {} },
  }, config = { card_limit = 5 } }
  G.NEURO.gates = nil
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = true
  local results = {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "_", "ok", "msg", "reason" }, "written"),
  }
  local function dispatch(id, name, data)
    G.NEURO.force_window = nil
    require("tests.helpers").open_force("SHOP", { "record_plan", "set_joker_order", "leave_shop" })
    D.handle_message({
      command = "action", run_generation = G.NEURO.run_generation,
      data = { id = id, name = name,
        data = next(data or {}) and json.encode(data) or "{}" },
    }, bridge)
  end
  local toggled = false
  G.FUNCS.toggle_shop = function()
    toggled = true
    G.shop = nil
    G.STATE = G.STATES.BLIND_SELECT
  end
  require("tests.helpers").stage_registered(nil, { "leave_shop", "record_plan", "set_joker_order" })
  dispatch("shop-revision-leave-early", "leave_shop")
  local toggled_early = toggled
  dispatch("shop-revision-partial", "record_plan", { money_plan = "hold enough for interest" })
  dispatch("shop-revision-full", "record_plan", {
    hand_plan = "play the upgraded hand",
    build_plan = "two jokers now, seek xMult",
    money_plan = "hold enough for interest",
  })
  dispatch("tw05-order", "set_joker_order", { from_index = 1, to_index = 2 })
  dispatch("tw05-leave", "leave_shop")
  check("shop exit requires a complete post-shop plan revision",
    #results == 5 and results[1].ok == true and results[1].reason == "CONFIRMATION_REQUIRED"
      and toggled_early == false and results[2].ok == false
      and results[3].ok == true and results[4].ok == true
      and results[5].ok == true and toggled == true,
    results[1] and (tostring(results[1].reason) .. " / " .. tostring(results[1].msg)))
  G.FUNCS.toggle_shop = nil; G.shop = nil; G.jokers = nil
  G.NEURO.force_window = nil
  G.NEURO.econ_plan_ok = nil; G.NEURO.shop_plan_revision_required = nil
  G.STATES = nil; G.STATE = nil
  G.NEURO.gates = nil
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
  Enforce.reset_run_state()
  mock_state("Normal", "SHOP")
  require("tests.helpers").in_engine_state("SHOP")
  G.shop = G.shop or {}
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.NEURO.shop_plan_revision_required = nil
  G.NEURO.plan = nil
  local results = {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "_", "ok", "msg", "reason" }),
  }
  require("tests.helpers").stage_registered(nil, { "record_plan" })
  for i = 1, 10 do
    G.NEURO.force_window = nil
    require("tests.helpers").open_force("SHOP", { "record_plan" })
    D.handle_message({
      command = "action", run_generation = G.NEURO.run_generation,
      data = { id = "n3f7-" .. i, name = "record_plan", data = "{}" },
    }, bridge)
  end
  check("ten record_plan|{} rejections are recorded",
    #results == 10, tostring(#results))
  check("the first three record_plan|{} rejections carry PRECONDITION_FAILED and success=false",
    results[1].ok == false and results[1].reason == "PRECONDITION_FAILED"
      and results[2].ok == false and results[2].reason == "PRECONDITION_FAILED"
      and results[3].ok == false and results[3].reason == "PRECONDITION_FAILED",
    string.format("%s/%s %s/%s %s/%s",
      tostring(results[1].ok), tostring(results[1].reason),
      tostring(results[2].ok), tostring(results[2].reason),
      tostring(results[3].ok), tostring(results[3].reason)))
  local all_refused = true
  for i = 4, 10 do
    all_refused = all_refused and results[i].ok == false and results[i].reason == "PRECONDITION_FAILED"
  end
  check("there is no retry budget: the tenth identical rejection is still success=false", all_refused,
    tostring(results[4].ok) .. "/" .. tostring(results[10].ok))

  G.shop = nil; G.jokers = nil
  G.NEURO.force_window = nil
  G.NEURO.shop_plan_revision_required = nil
  G.STATES = nil; G.STATE = nil
  Enforce.reset_run_state()
end

do
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks }
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
  G.NEURO.force_window = nil
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.jokers = { cards = {
    { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
      config = { center = { key = "j_a", set = "Joker" } } },
    { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
      config = { center = { key = "j_b", set = "Joker" } } },
  }, config = { card_limit = 5 } }
  G.TIMERS = { REAL = 1000 }
  local ok1 = Enforce.pre_action(nil, "set_joker_order")
  check("first spaced attempt passes", ok1 == true)
  G.TIMERS.REAL = 1100
  local ok2 = Enforce.pre_action(nil, "set_joker_order")
  G.TIMERS.REAL = 1200
  local ok3 = Enforce.pre_action(nil, "set_joker_order")
  check("repeats below the cap pass", ok2 == true and ok3 == true)
  G.TIMERS.REAL = 1300
  local ok4, e4 = Enforce.pre_action(nil, "set_joker_order")
  check("4th committed repeat hits the cap", ok4 == false and type(e4) == "string", e4)
  G.TIMERS.REAL = 1400
  local ok5 = Enforce.pre_action(nil, "set_joker_order")
  check("the streak stays capped until something breaks it", ok5 == false)
  G.TIMERS.REAL = 1500
  check("a different action passes (streak resets on name change)",
    Enforce.pre_action(nil, "discard_hand") == true)
  G.TIMERS.REAL = 1600
  check("original action passes again after the streak-breaker",
    Enforce.pre_action(nil, "set_joker_order") == true)
  G.jokers = nil
  G.TIMERS = nil; G.STATES = nil; G.STATE = nil
end

do
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
  local q = require("tests.helpers").force_payload("SELECTING_HAND")
  check("force query carries ready indices", q:find("Full House (cards 1, 2, 3, 6, 7)", 1, true) ~= nil)

  G.FUNCS.get_poker_hand_info = nil
end

local function lp_setup(rank, suit, flag, jokers)
  Config.set("NEURO_CONFIRM_HAND", "off")
  mock_state("Normal", "SELECTING_HAND")
  G.NEURO.last_play = nil
  G.hand = require("tests.helpers").card_area({ cards = { card("King", "Hearts"), card("King", "Spades"), card(rank, suit, flag),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} })
  if jokers then G.jokers = { cards = jokers } end
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 0
  G.GAME.chips = 100
  G.GAME.blind = { chips = 600 }
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").stub("Pair", function(cards) return { cards[1], cards[2] } end)
  engine_commits()
end

do
  local function H(name) return D.get_action_handler(name) end
  lp_setup("9", "Clubs")
  H("play_hand")({ indices = { 1, 2, 3 } })
  local c = H("play_hand")({ indices = { 1, 2, 3 }, _action_id = "lp-play" })
  local ok_play = type(c) == "function" and run_commit(c)
  local lp = G.NEURO.last_play
  check("LP stash on play commit", ok_play and type(lp) == "table" and lp.hand_type == "Pair"
    and lp.played == 3 and lp.scored == 2 and lp.pre_chips == 100 and lp.hands_left_after == 2)

  local blob = ContextCompact.build("SELECTING_HAND", nil)

  G.GAME.chips = 420
  blob = ContextCompact.build("SELECTING_HAND", nil)
  check("LP delta + score/target once chips land", blob:find("Last hand: Pair, played 3 cards, 2 scored, +320 chips, now 420/600, 180 short.", 1, true) ~= nil, blob:match("Last hand:[^\n]*"))

  G.GAME.current_round.discards_left = 3
  local cd = H("discard_hand")({ indices = { 1, 2 }, _action_id = "lp-discard" })
  run_commit(cd)
  check("LP discard stash", type(G.NEURO.last_play) == "table" and G.NEURO.last_play.kind == "discard"
    and G.NEURO.last_play.played == 2 and G.NEURO.last_play.discards_left_after == 2)
  blob = ContextCompact.build("SELECTING_HAND", nil)
  check("LP discard reports replacement result and remaining resource",
    blob:find("Last discard: replaced 2 cards, 2 discards remain.", 1, true) ~= nil,
    blob:match("Last discard:[^\n]*"))

  require("context.ctx_hand").clear_last_play()
  check("LP cleared on round-reset path", G.NEURO.last_play == nil)
  blob = ContextCompact.build("SELECTING_HAND", nil)
  check("no LP line after clear", blob:find("Last hand:", 1, true) == nil and blob:find("Last discard:", 1, true) == nil)

  G.GAME.chips = nil; G.GAME.blind = nil; G.FUNCS.get_poker_hand_info = nil
  G.FUNCS.play_cards_from_highlighted, G.FUNCS.discard_cards_from_highlighted = nil, nil
  Config.set("NEURO_CONFIRM_HAND", "on")
end

do
  local function H(name) return D.get_action_handler(name) end
  local function scored_with(jokers)
    lp_setup("Ace", "Clubs", true, jokers)
    H("play_hand")({ indices = { 1, 2, 3, 4 } })
    local c = H("play_hand")({ indices = { 1, 2, 3, 4 }, _action_id = "lp-scored" })
    if type(c) == "function" then run_commit(c) end
    local lp = G.NEURO.last_play
    G.GAME.chips = nil; G.GAME.blind = nil; G.FUNCS.get_poker_hand_info = nil; G.jokers = nil
    G.FUNCS.play_cards_from_highlighted, G.FUNCS.discard_cards_from_highlighted = nil, nil
    require("context.ctx_hand").clear_last_play()
    Config.set("NEURO_CONFIRM_HAND", "on")
    return lp and lp.scored
  end
  check("LP counts a played Stone Card as scored", scored_with({}) == 3)
  check("LP counts every played card under Splash",
    scored_with({ { config = { center = { key = "j_splash" } }, ability = { name = "Splash" } } }) == 4)
  check("LP ignores a debuffed Splash",
    scored_with({ { config = { center = { key = "j_splash" } }, ability = { name = "Splash" }, debuff = true } }) == 3)
end

do
  local function H(name) return D.get_action_handler(name) end
  mock_state("Normal", "SELECTING_HAND")
  require("core.gate").reset()
  G.hand = { cards = { card("King", "Hearts"), card("Queen", "Spades"), card("9", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.chips = 0
  G.GAME.blind = { chips = 1e20 }
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").stub("Flush")
  local _, err = H("play_hand")({ indices = { 1, 2, 3, 4, 5 } })
  local msg = require("tests.helpers").review_text(err)
  check("review names a huge remaining target without integer overflow",
    msg:find("1e+20 to clear", 1, true) ~= nil, msg)
  G.GAME.chips = nil; G.GAME.blind = nil; G.FUNCS.get_poker_hand_info = nil
  require("core.gate").reset()
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {} }
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.TIMERS = { REAL = 90000 }
  G.NEURO.state = "SELECTING_HAND"
  local results, ctxs = {}, {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "msg", "reason" }),
    send_context = function(self, msg, silent) ctxs[#ctxs + 1] = tostring(msg) end,
  }
  local Staging = require("core.staging")
  Staging.reset_run_state()
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
  G.NEURO.llm_paused = true
  require("tests.helpers").stage_registered(nil, { "exit_overlay_menu" })
  local msg = { command = "action", data = { id = "tp_pause1", name = "exit_overlay_menu" } }
  D.route_message(msg, bridge)
  check("pause: paused reply is success=true with operator message",
    #results == 1 and results[1].ok == true,
    results[1] and results[1].msg)
  check("pause: handler not dispatched", Staging.is_busy() == false, tostring(Staging.is_busy()))
  D.route_message(msg, bridge)
  check("pause: same-session redelivery is suppressed after the settled reply",
    #results == 1)
  G.NEURO.llm_paused = nil
  D.route_message(msg, bridge)
  check("pause: same-session replay after resume stays suppressed",
    #results == 1,
    results[2] and results[2].msg)
  check("pause: replay did not dispatch the handler", Staging.is_busy() == false, tostring(Staging.is_busy()))
  local msg2 = { command = "action", data = { id = "tp_pause2", name = "exit_overlay_menu" } }
  D.route_message(msg2, bridge)
  check("pause: fresh id queues after resume",
    #results == 2 and Staging.is_busy() == true
      and results[2].reason == "ACTION_ACCEPTED",
    results[2] and results[2].reason)
  Staging.update()
  check("pause: fresh id executes normally after resume",
    #results == 2 and results[2].ok == true
      and G.OVERLAY_MENU == nil,
    results[2] and tostring(results[2].msg))
  Staging.reset_run_state()
end

do
  mock_state("Normal", "SELECTING_HAND")
  require("tests.helpers").in_engine_state("MENU")
  G.GAME = { current_round = {} }
  G.OVERLAY_MENU = nil
  SMODS.RunSelect.Setup.choices = { seed = "" }

  local f = require("force.force_router").get_force_for_state("MENU")
  check("seed chain: MENU force offers open_run_setup", f and has(f.actions, "open_run_setup"))
  check("seed chain: MENU force omits toggle_seeded_run (fails without overlay)",
    not has((f or {}).actions, "toggle_seeded_run"))
  check("seed chain: MENU force omits paste_seed (wiped by overlay rebuild)",
    not has((f or {}).actions, "paste_seed"))
  check("seed chain: MENU force omits start_run (dispatcher rejects it)",
    not has((f or {}).actions, "start_run"))
  check("seed chain: toggle_seeded_run invalid without overlay", not A.is_action_valid("toggle_seeded_run"))
  check("seed chain: start_run invalid without overlay", not A.is_action_valid("start_run"))

  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  local rs = require("force.force_router").get_force_for_state("RUN_SETUP")
  check("seed chain: run-setup force offers toggle_seeded_run as a tool",
    rs and has(rs.tools, "toggle_seeded_run") and has(rs.actions, "toggle_seeded_run"))
  check("seed chain: run-setup force offers paste_seed as a tool",
    rs and has(rs.tools, "paste_seed") and has(rs.actions, "paste_seed"))
  check("seed chain: run-setup force offers start_run", rs and has(rs.actions, "start_run"))
  local rstate = require("tests.helpers").force_frame("RUN_SETUP", rs)
  check("seed chain: run-setup frame's state shows seeded mode fact", rstate:find(", not seeded.", 1, true) ~= nil, rstate)

  local toggle = D.get_action_handler("toggle_seeded_run")
  local run = toggle({})
  check("seed chain: toggle_seeded_run executes on overlay", type(run) == "function" and ActionReceipt.is_done(run()))
  check("seed chain: toggle flips engine flag", SMODS.RunSelect.Setup.choices.enable_seed == true)

  local paste = D.get_action_handler("paste_seed")
  local bad_prun, bad_err = paste({ seed = "ab-cd!" })
  check("seed chain: paste_seed rejects invalid characters", bad_prun == nil and bad_err ~= nil)

  local dash_prun, dash_err = paste({ seed = "abc-123xy" })
  check("seed chain: paste_seed rejects a dash instead of stripping it silently",
    dash_prun == nil and dash_err ~= nil, dash_err)

  local prun = paste({ seed = "abc123xy" })
  check("seed chain: paste_seed executes", type(prun) == "function" and ActionReceipt.is_done(prun()))
  check("seed chain: paste_seed arms engine seed", SMODS.RunSelect.Setup.choices.seed == "ABC123XY"
    and SMODS.RunSelect.Setup.choices.enable_seed == true)

  local rs2 = require("force.force_router").get_force_for_state("RUN_SETUP")
  local rstate2 = require("tests.helpers").force_frame("RUN_SETUP", rs2)
  check("seed chain: frame's state reflects seeded ON + pasted seed",
    rstate2:find(", seeded (seed ABC123XY).", 1, true) ~= nil, rstate2)
  check("seed chain: start_run valid with overlay open", A.is_action_valid("start_run"))

  G.OVERLAY_MENU = nil
  SMODS.RunSelect.Setup.choices = { seed = "" }
  G.STATES = nil; G.STATE = nil
end

do
  local red = { key = "b_red", name = "Red Deck" }
  local blue = { key = "b_blue", name = "Blue Deck" }
  local function back(center)
    return {
      effect = { center = center },
      change_to = function(self, next_center) self.effect.center = next_center end,
    }
  end
  G.P_CENTER_POOLS = G.P_CENTER_POOLS or {}
  local old_backs = G.P_CENTER_POOLS.Back
  G.P_CENTER_POOLS.Back = { red, blue }
  G.GAME = { viewed_back = back(red), selected_back = back(red) }
  G.SETTINGS = { profile = 1 }
  G.PROFILES = { [1] = { MEMORY = {} } }
  G.TIMERS = { REAL = 10 }
  require("core.validate").reset_run_state()
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end }
  local choose = D.get_action_handler("select_deck")({ back = "b_blue" })
  choose()
  G.GAME.viewed_back:change_to(red)
  G.GAME.selected_back:change_to(red)
  local started_with
  local old_start_run = G.FUNCS.start_run
  local injected_start_run = function(_, args)
    started_with = args and args.deck_choice and args.deck_choice.key
    G.NEURO.run_generation = (tonumber(G.NEURO.run_generation) or 0) + 1
  end
  G.FUNCS.start_run = injected_start_run
  G.FUNCS.start_setup_run = function(e)
    G.FUNCS.start_run(e, { stake = 1 })
  end
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("RUN_SETUP", { "start_run" })
  require("tests.helpers").stage_registered(nil, { "start_run" })
  D.handle_message({ command = "action", run_generation = G.NEURO.run_generation, data = {
    id = "deck-start-persistence", name = "start_run", data = "{}",
  } }, { send_action_result = function() return true, { status = "written" } end })
  check("selected deck is injected into start_run despite stale menu state", started_with == "b_blue", started_with)
  check("start_run hook is restored after run start", G.FUNCS.start_run == injected_start_run, tostring(G.FUNCS.start_run))
  G.FUNCS.start_setup_run = nil
  G.FUNCS.start_run = old_start_run
  G.P_CENTER_POOLS.Back = old_backs
  G.OVERLAY_MENU = nil
  G.NEURO.selected_back_key = nil
  G.STATES = nil; G.STATE = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  local CtxHand = require("context.ctx_hand")
  local d = { card("Ace", "Spades"), card("King", "Hearts"), card("5", "Hearts") }
  G.deck = { cards = { d[1], d[2], d[3] } }
  local dc1 = CtxHand.deck_cards_section()
  check("DC is size only", dc1 == "3 cards left in the draw pile.", dc1)
  check("DC exposes no suit/rank breakdown", not dc1:find("|") and not dc1:find("Hearts") and not dc1:find("Spades"), dc1)
  G.deck = { cards = { d[3], d[1], d[2] } }
  check("DC identical under reordering (no draw-order leak)", CtxHand.deck_cards_section() == dc1)
  G.deck = nil
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  local CtxBlind = require("context.ctx_blind")
  G.GAME.bosses_used = { boss = { bl_ox = 0, bl_wall = 1 }, small = { bl_small = 3 }, big = {} }
  local s = CtxBlind.blind_select_section() or ""
  check("bosses_used drives no roster line", s:lower():find("beaten", 1, true) == nil, s)
  G.GAME.bosses_used = { bl_ox = 0, bl_wall = 1 }
  s = CtxBlind.blind_select_section() or ""
  check("a flat bosses_used mock names no boss either",
    s:find("The Wall", 1, true) == nil, s)


  local saved_choices = G.GAME.round_resets and G.GAME.round_resets.blind_choices
  G.GAME.round_resets = G.GAME.round_resets or {}
  G.GAME.round_resets.blind_choices = { Boss = "bl_wall" }
  G.GAME.bosses_used = { boss = { bl_wall = 1, bl_ox = 1 } }
  s = CtxBlind.blind_select_section() or ""
  check("no boss roster is reconstructed from draw counts",
    s:lower():find("beaten", 1, true) == nil and s:find("The Ox", 1, true) == nil, s)
  G.GAME.round_resets.blind_choices = saved_choices
  G.GAME.bosses_used = nil
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.dollars = 0
  G.GAME.modifiers = {}
  G.GAME.current_round.hands_left = 1; G.GAME.current_round.discards_left = 0
  G.GAME.blind = { in_blind = true, dollars = 3, chips = 300 }
  G.hand = { cards = { card("5", "Hearts") }, highlighted = {}, config = { card_limit = 8 } }
  G.GAME.current_round.hands_left = 1
  local blob = ContextCompact.build("SELECTING_HAND", nil)
  check("last-hand B line projects H0", blob:find("blind $3 + hands $0 +", 1, true) ~= nil, blob:match("Cash%-out[^\n]*"))
  G.GAME.blind = nil
end

do
  mock_state("Small blind selectable", "BLIND_SELECT")
  G.GAME.blind_on_deck = nil
  local f = require("force.force_router").get_force_for_state("BLIND_SELECT")
  check("force still built from states fallback",
    f ~= nil)
  check("force carries the blind it was built for", f and f.blind == "small")
  G.GAME.blind_on_deck = nil
  G.GAME.round_resets.blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
  check("unresolved on-deck AND states -> no force (delay, never OD:?)",
    require("force.force_blind_select").build("") == nil)
end

do
  mock_state("Normal", "SELECTING_HAND")
  in_state("SELECTING_HAND")
  local hidden = EngineCards.consumable("c_ankh", { center = { loc_txt = { name = "Ankh" }, discovered = false },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end })
  G.jokers = { cards = { EngineCards.card({ ability = { set = "Joker", name = "Joker" }, sell_cost = 1,
    config = { center = { key = "j_joker", set = "Joker", name = "Joker" } } }) }, config = { card_limit = 5 } }
  G.consumeables = { cards = { hidden }, config = { card_limit = 2 } }
  G.FUNCS.use_card = function() end
  local c = D.get_action_handler("use_consumable")({ area = "consumeables", index = 1, _action_id = "ar-ankh" })
  local ok_u, r_u = pcall(c)
  check("a use not yet observed carries no effect text", ok_u and ActionReceipt.is_receipt(r_u) and r_u.applied_message == nil,
    execution_text(r_u))
  G.FUNCS.use_card = nil

  mock_state("Normal", "SHOP")
  local shop_hidden = require("tests.engine_cards").card({
    cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_x", loc_txt = { name = "Mystery Joker" }, set = "Joker" } },
    generate_UIBox_ability_table = function() return { name = "Not Discovered", main = {} } end,
  })
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_hidden } }
  G.FUNCS.buy_from_shop = function() end
  local events = require("tests.helpers").event_manager()
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, _action_id = "ar-mystery" })
  local ok_b, r_b = pcall(cb)
  check("a plain buy carries no receipt text", ok_b and ActionReceipt.is_receipt(r_b)
    and r_b.applied_message == nil, execution_text(r_b))
  events:run()
  G.FUNCS.buy_from_shop = nil; G.NEURO.reserved_dollars = 0
end

do
  mock_state("Normal", "SHOP")
  local function jk(nm)
    return { ability = { set = "Joker", name = nm }, sell_cost = 2,
      config = { center = { key = "j_" .. nm:lower():gsub(" ", "_"), set = "Joker", loc_txt = { name = nm } } } }
  end
  G.jokers = { cards = { jk("Green Joker"), jk("Abstract Joker"), jk("Ice Cream") },
    config = { card_limit = 5 } }
  G.FUNCS.sell_card = function() end
  G.NEURO._candidate_probe = true
  local shifted = { area = "jokers", index = 2, name = "Green Joker" }
  local c, err = D.get_action_handler("sell_card")(shifted)
  G.NEURO._candidate_probe = nil
  check("SELL: a unique exact name safely relocates a shifted index",
    type(c) == "function" and shifted.index == 1, tostring(err))
  local c2, err2 = D.get_action_handler("sell_card")({ area = "jokers", index = 2, name = "Abstract Joker" })
  check("SELL: matching name reaches the sell review, not a refusal", c2 == nil and type(err2) == "table"
    and err2.reason_code == "CONFIRMATION_REQUIRED" and tostring(err2.message):find("Selling Abstract Joker", 1, true) ~= nil,
    tostring(err2 and err2.message or err2))
  require("core.gate").delivered(err2)
  local c3, err3 = D.get_action_handler("sell_card")({ area = "jokers", index = 2, name = "Abstract Joker" })
  check("SELL: matching name passes validation", c3 ~= nil, tostring(err3))
  G.FUNCS.sell_card = nil
  G.jokers = nil
end

do
  mock_state("Normal", "SHOP")
  local item = { cost = 3, ability = { set = "Joker" }, sell_cost = 1,
    config = { center = { key = "j_gros_michel", set = "Joker", loc_txt = { name = "Gros Michel" } } } }
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { item } }
  local c, err = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, name = "Wee Joker" })
  check("BUY: name mismatch rejected", c == nil and action_error(err):find("'Gros Michel', not 'Wee Joker'", 1, true) ~= nil, tostring(err))
  local c2 = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, name = "gros michel" })
  check("BUY: case-insensitive name match passes", c2 ~= nil)

  mock_state("Normal", "SELECTING_HAND")
  in_state("SELECTING_HAND")
  G.consumeables = { cards = { EngineCards.consumable("c_fool") }, config = { card_limit = 2 } }
  local c3, err3 = D.get_action_handler("use_consumable")({ area = "consumeables", index = 1, name = "The Hermit" })
  check("USE: name mismatch rejected", c3 == nil and action_error(err3):find("'The Fool', not 'The Hermit'", 1, true) ~= nil, tostring(err3))
  G.consumeables = nil; G.shop_jokers = nil; G.jokers = nil
end

do
  mock_state("Normal", "SHOP")
  local shop_j = require("tests.engine_cards").card({ cost = 4, ability = { set = "Joker" },
    config = { center = { key = "j_y", loc_txt = { name = "Test Joker" }, set = "Joker" } } })
  G.GAME.dollars = 10; G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.shop_jokers = { cards = { shop_j } }
  G.FUNCS.buy_from_shop = nil
  local events = require("tests.helpers").event_manager()
  local cb = D.get_action_handler("buy_from_shop")({ area = "shop_jokers", index = 1, _action_id = "ar-f005" })
  local ok_b, r_b = pcall(cb)
  events:run()
  local settled = ok_b and ActionReceipt.is_receipt(r_b) and ActionReceipt.settle(r_b, ActionReceipt.now(), r_b.run_generation)
  check("F-005: missing buy callback settles failed with a correction, not optimistic",
    settled and r_b.phase == "failed",
    execution_text(r_b) .. " phase=" .. tostring(r_b and r_b.phase))
  check("F-005: missing buy callback names the refused callback",
    type(r_b) == "table" and r_b.details and r_b.details.cause == "purchase callback refused the prepared target")
  G.NEURO.reserved_dollars = 0
  G.NEURO.last_failed_action = nil; G.NEURO.last_failed_reason = nil
end

local function hearts_setup()
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("2", "Hearts"), card("5", "Hearts"), card("7", "Hearts"),
    card("9", "Hearts"), card("King", "Spades") }, highlighted = {} }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.GAME.blind = { chips = 700 }
  G.GAME.chips = 100
end

do
  hearts_setup()
  G.deck = { cards = { card("6", "Hearts"), card("Jack", "Hearts"), card("3", "Spades"),
    card("3", "Clubs"), card("Ace", "Diamonds") } }
  require("tests.engine_cards").enhance(G.deck.cards[1], "m_glass")
  G.deck.cards[3].seal = "Red"
  local blob = ContextCompact.build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"))
  check("DD: draw-pile composition line present",
    blob:find("Unplayed pool by suit: 2 Hearts, 1 Spades, 1 Diamonds, 1 Clubs. Ranks in that pool: A x1, J x1, 6 x1, 3 x2.", 1, true) ~= nil,
    blob:match("Draw pile[^\n]*") or blob)
  check("DD: draw-pile modifier inventory is scoped to what is still unseen",
    blob:find("Modifiers in that pool: seals Red x1; enhancements Glass x1.", 1, true) ~= nil,
    blob:match("Modifiers in that pool[^\n]*") or blob)
  G.deck = nil
  G.GAME.blind = nil
end

do
  local J = require("util.neuro_json")
  local Execute = require("core.execute")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("9", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs") }, highlighted = {} }
  G.GAME.current_round.discards_left = 3; G.GAME.current_round.hands_left = 4
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").stub("Pair", {})
  G.NEURO.play_confirm = nil
  G.NEURO.weak_fired_serial = nil
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  local n = 0
  local function route_play(indices)
    n = n + 1
    G.TIMERS = { REAL = 1000 * n, TOTAL = 1000 * n }
    local results = {}
    local bridge = { send_context = function() return true end }
    function bridge:send_action_result(_, ok, message) results[#results + 1] = { ok = ok, msg = message } end
    D.route_message({ command = "action", data = { name = "play_hand", id = "stage-" .. n,
      data = J.encode({ indices = indices }) } }, bridge)
    local staged = Execute.busy() == "staged"
    D.reset_run_state()
    return staged, results[1]
  end
  G.GAME.blind = { disabled = false, debuff = { h_size_ge = 5 } }
  local staged, result = route_play({ 1, 2 })
  check("SIZE: a play the boss size rule refuses is answered and never staged",
    not staged and result and result.ok == false and tostring(result.msg):find("5", 1, true) ~= nil,
    result and result.msg)
  G.GAME.blind = {}
  staged, result = route_play({ 1, 2 })
  check("CONFIRM: a first play that needs review is answered and never staged (no card-lift on the pause)",
    not staged and result and result.msg == require("handlers.hand_handlers").PLAY_REVIEW_BRIEF, result and result.msg)
  require("core.gate").invalidate()
  G.STATES = nil; G.STATE = nil
end


do
  mock_state("Normal", "SELECTING_HAND")
  require("tests.helpers").in_engine_state("SHOP")
  G.shop_jokers = { cards = { { ability = { name = "Mad Joker", set = "Joker" },
    config = { center = { key = "j_mad" } }, cost = 4 } } }
  G.NEURO.econ_plan_ok = true
  local handler = D.get_action_handler("buy_from_shop")
  check("SHOP-JANK: a buy whose name matches the card validates",
    type(handler({ area = "shop_jokers", index = 1, name = "Mad Joker" })) == "function")
  check("SHOP-JANK: a buy with a mismatched name is refused before any hover",
    handler({ area = "shop_jokers", index = 1, name = "Luchador" }) == nil)
  local saved_plan = G.NEURO.plan
  G.NEURO.econ_plan_ok = nil
  G.NEURO.plan = nil
  local _, tx_err = require("core.plan_transaction").prepare("buy_from_shop",
    { area = "shop_jokers", index = 1, name = "Mad Joker" })
  local tx_code = require("core.action_result").normalize(tx_err).reason_code
  check("SHOP-JANK: a buy with no money plan is refused by the plan gate",
    tx_code == "PRECONDITION_FAILED", tostring(tx_code))
  G.shop_jokers = nil; G.STATES = nil; G.STATE = nil; G.NEURO.econ_plan_ok = nil; G.NEURO.plan = saved_plan
end

do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 4 } }
  G.GAME.pack_choices = 1
  in_state("SMODS_BOOSTER_OPENED")
  local planet = EngineCards.consumable("c_pluto")
  G.pack_cards = { cards = { planet } }
  local blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { split = "volatile" })
  local _, levels_count = blob:gsub("Hand levels", "Hand levels")
  check("CW3: planet card visible -> L: attached exactly once", levels_count == 1, blob)

  local playing = card("9", "Hearts")
  G.pack_cards = { cards = { playing } }
  G.deck = { cards = { card("Ace", "Spades"), card("King", "Hearts") } }
  blob = ContextCompact.build("SMODS_BOOSTER_OPENED", nil, { split = "volatile" })
  check("CW3: playing card visible -> DC aggregate attached", blob:find("2 cards left in the draw pile", 1, true) ~= nil, blob)
  local _, n0 = blob:gsub("Hand levels", "Hand levels")
  check("CW3: booster context always attaches L: exactly once", n0 == 1, blob)
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
  local blob_plan = ContextCompact.build("SHOP", nil, { split = "volatile" })
  local _, np = blob_plan:gsub("Hand levels", "Hand levels")
  check("CW4: SHOP always shows the L: table exactly once", np == 1, blob_plan)
  G.shop_jokers = { cards = { EngineCards.consumable("c_pluto") }, config = { card_limit = 2 } }
  local blob = ContextCompact.build("SHOP", nil, { split = "volatile" })
  local _, nb = blob:gsub("Hand levels", "Hand levels")
  check("CW4: SHOP with a buyable Planet has L: table exactly once", nb == 1, blob)
  check("CW4: SHOP L: upgraded hands listed and base summarized", blob:find("Pair: level 2, 20 chips x 3 mult = 60 before any card or joker, played 6.", 1, true) ~= nil
    and blob:find("all other hands: level 1", 1, true) ~= nil, blob:match("Hand levels[^\n]*\n[^\n]*\n[^\n]*"))
  G.shop_jokers = nil; G.jokers = nil
end

do
  G.NEURO.persona = "neuro"
  check("choose_persona invalid once persona locked", A.is_action_valid("choose_persona") == false)
  G.NEURO.persona = "hiyori"
  check("choose_persona valid at the identity gate", A.is_action_valid("choose_persona") == true)
  G.NEURO.persona = nil
end

do
  local FSH = require("force.force_selecting_hand")
  local VALN = require("tests.helpers").VALN
  local saved_G = _G.G
  local function leaf_card(v, suit) return require("tests.engine_cards").playing(VALN[v] or v, suit) end
  local function round_with_boss(key, name)
    _G.G = {
      P_CENTERS = require("tests.engine_centers").centers(),
      STATES = ES, STATE = ES.SELECTING_HAND,
      hand = { cards = { leaf_card("3", "Spades"), leaf_card("7", "Clubs"), leaf_card("9", "Hearts") },
        config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} },
      GAME = { chips = 0, round_resets = { ante = 1 },
        current_round = { hands_left = 4, discards_left = 3 },
        blind = { chips = 1000, boss = true, name = name, debuff = {},
          config = { blind = { key = key } } },
        hands = {} },
      FUNCS = { get_poker_hand_info = function() return nil, nil, {} end },
      NEURO = { once_serials = {}, state_enter_serial = 1 },
      jokers = { cards = { { ability = { set = "Joker", name = "Joker" }, sell_cost = 2,
        config = { center = { key = "j_joker", set = "Joker" } } } }, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
    }
  end
  local function offers_sell()
    local f = FSH.build()
    for _, a in ipairs((f or {}).actions or {}) do if a == "sell_card" then return true end end
    return false
  end
  round_with_boss("bl_pillar", "The Pillar")
  check("mid-round sell of a joker whose sale does nothing this round stays unoffered under a boss that is not Verdant Leaf",
    not A.is_action_valid("sell_card") and not offers_sell())
  table.insert(_G.G.jokers.cards, { ability = { set = "Joker", name = "Luchador" }, sell_cost = 2,
    config = { center = { key = "j_luchador", set = "Joker" } } })
  _G.G.GAME.blind.get_type = function() return "Boss" end
  local luchador_only = true
  for _, p in ipairs(require("core.action_registry").candidates("sell_card")) do
    if p.name ~= "Luchador" then luchador_only = false end
  end
  check("SELECTING_HAND force offers selling Luchador mid-boss, and only Luchador (its sale disables the boss now)",
    A.is_action_valid("sell_card") and offers_sell() and luchador_only)
  round_with_boss("bl_pillar", "The Pillar")
  round_with_boss("bl_final_leaf", "Verdant Leaf")
  check("SELECTING_HAND force offers sell_card under Verdant Leaf (the only way to lift its all-debuff)",
    A.is_action_valid("sell_card") and offers_sell())
end

do
  local PlanHandlers = require("handlers.plan_handlers")
  local res, res_err = PlanHandlers.prepare_plan({}, false)
  local msg = ActionResult.is_error(res_err) and ActionResult.normalize(res_err).message or tostring(res_err)
  check("a plan call without fields is rejected", res == nil and ActionResult.is_error(res_err))
  check("the missing-plan-fields error names only fields record_plan takes, never boss_plan",
    msg:find("hand_plan", 1, true) ~= nil and msg:find("boss_plan", 1, true) == nil, msg)
end

do
  local SeedHandlers = require("handlers.seed_run_handlers")

  local exec_ok, err_ok = SeedHandlers.handle_paste_seed({ seed = "ABC123XY" })
  check("a valid eight-character seed is accepted",
    type(exec_ok) == "function", tostring(err_ok))

  local seed_pasted_before = G.NEURO and G.NEURO.seed_pasted
  local exec_long, err_long = SeedHandlers.handle_paste_seed({ seed = "ABCDEFGHIJKL" })
  check("a seed longer than eight characters is rejected rather than truncated",
    exec_long == nil and type(err_long) == "string",
    tostring(exec_long) .. " / " .. tostring(err_long))
  check("a rejected long seed does not silently change G.NEURO.seed_pasted",
    G.NEURO.seed_pasted == seed_pasted_before, tostring(G.NEURO.seed_pasted))
end

do
  local SeedHandlers = require("handlers.seed_run_handlers")
  local saved_clipboard, saved_overlay = G.CLIPBOARD, G.OVERLAY_MENU
  G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return (id == "run_setup_seed") and {} or nil end }
  local choices = SMODS.RunSelect.Setup.choices

  G.CLIPBOARD = "Seed: ABC12345 have fun"
  local run1, err1 = SeedHandlers.handle_paste_seed({})
  check("clipboard prose around a seed is rejected rather than normalized",
    run1 == nil and type(err1) == "string", tostring(run1) .. " / " .. tostring(err1))

  G.CLIPBOARD = "my seed is 8LB3RD9X"
  local run2, err2 = SeedHandlers.handle_paste_seed({})
  check("'my seed is X' clipboard prose is rejected rather than normalized to MYSEEDIS",
    run2 == nil and type(err2) == "string", tostring(run2) .. " / " .. tostring(err2))

  choices.seed = ""
  G.CLIPBOARD = "ABC12345"
  local run3 = SeedHandlers.handle_paste_seed({})
  check("a bare clipboard seed remains valid", type(run3) == "function")
  if type(run3) == "function" then run3() end
  check("a bare clipboard seed is preserved exactly", choices.seed == "ABC12345",
    tostring(choices.seed))

  choices.seed = ""
  G.CLIPBOARD = "  ABC12345\n"
  local run4 = SeedHandlers.handle_paste_seed({})
  check("a bare clipboard seed with surrounding whitespace remains valid", type(run4) == "function")
  if type(run4) == "function" then run4() end
  check("surrounding whitespace does not change a bare clipboard seed", choices.seed == "ABC12345",
    tostring(choices.seed))

  G.CLIPBOARD, G.OVERLAY_MENU = saved_clipboard, saved_overlay
end

do
  local FactHints = require("facts.fact_hints")
  local Delivery = require("core.context_delivery")
  local saved_neuro = G.NEURO
  G.NEURO = { session_once_serials = {}, once_serials = {}, state_enter_serial = 1,
    decision_serial = 1, run_generation = 1 }
  Delivery.reset_transport()
  FactHints.reset_pending()

  local TAG = "n3f6_hint"
  G.NEURO.send_context = function(_self, _msg, _silent, receipt)
    if receipt then receipt.status = "rejected" end
    return false
  end
  local queued_text = FactHints.once_per_run_hint(TAG, "HINT TEXT")
  check("the first call queues a hint", queued_text == "")
  check("the hint is pending in the queue", FactHints.pending_count() == 1,
    tostring(FactHints.pending_count()))

  check("an undelivered flush reports no delivered frame", FactHints.flush_pending() == 0)
  check("the hint is offered again after an undelivered flush",
    FactHints.once_per_run_hint(TAG, "HINT TEXT") == "" and FactHints.pending_count() == 1,
    tostring(FactHints.pending_count()))

  G.NEURO.send_context = function(_self, _msg, _silent, receipt)
    if receipt then receipt.status = "written" end
    return true
  end
  local sent = FactHints.flush_pending()
  check("a delivered flush reports one sent frame", sent == 1, tostring(sent))
  check("the gate is recorded only after actual delivery, so the offer is not queued again",
    FactHints.once_per_run_hint(TAG, "HINT TEXT") == "" and FactHints.pending_count() == 0,
    tostring(FactHints.pending_count()))

  G.NEURO = saved_neuro
  FactHints.reset_pending()
end

done()
