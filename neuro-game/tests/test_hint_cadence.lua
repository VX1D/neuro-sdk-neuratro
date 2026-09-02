_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(a)
  if type(a) == "table" and a.type == "raw_descriptions" then return { "All Heart cards are debuffed" } end
  return ""
end

local check, done = require("tests.helpers").harness("hint-cadence")
local H = require("tests.helpers")
local function has(q, s) return type(q) == "string" and q:find(s, 1, true) ~= nil end

local FactHints = require("facts.fact_hints")
local shint = FactHints.once_per_state_entry_hint

local UNSTUBBED_IS_ACTION_VALID = require("core.actions").is_action_valid
local function stub_valid(fn)
  check("is_action_valid is unstubbed before this block replaces it",
    require("core.actions").is_action_valid == UNSTUBBED_IS_ACTION_VALID,
    "an earlier block left its stub installed")
  require("core.actions").is_action_valid = fn
end
local function unstub_valid()
  require("core.actions").is_action_valid = UNSTUBBED_IS_ACTION_VALID
end

local function dhint(tag, text)
  FactHints.once_per_decision_hint(tag, text)
  return H.drain_hints()
end
local function shint_out(tag, text)
  shint(tag, text)
  return H.drain_hints()
end

do
  _G.G = { NEURO = { once_serials = {}, decision_serial = 1, state_enter_serial = 1 } }
  check("the helper returns nothing to the caller (no hint text in the query)",
    FactHints.once_per_decision_hint("ret", "TXT") == "" and FactHints.pending_count() == 1)
  H.drain_hints()
  check("fires on first sight at a serial", dhint("t", "TXT") == "TXT")
  check("suppressed on repeat at the SAME serial", dhint("t", "TXT") == "")
  G.NEURO.decision_serial = 2
  check("re-fires when decision_serial advances", dhint("t", "TXT") == "TXT")
  check("suppressed again at the new serial", dhint("t", "TXT") == "")
  check("empty text -> empty (never emits blank hint)", dhint("t2", "") == "")
  check("distinct tags are independent", dhint("a", "A") == "A" and dhint("b", "B") == "B")
  G.NEURO.decision_serial = nil
  check("nil decision_serial treated as 0 (fires once)", dhint("nilser", "N") == "N")
  check("A7b still suppressed at nil(=0)", dhint("nilser", "N") == "")
  _G.G = nil
  check("no crash / empty when G is absent", dhint("t", "X") == "")
end

do
  _G.G = { NEURO = { once_serials = {}, decision_serial = 5, state_enter_serial = 5 } }
  check("state-entry hint fires on first sight", shint_out("v", "V") == "V")
  check("suppressed on repeat at same state_enter_serial", shint_out("v", "V") == "")
  G.NEURO.decision_serial = 99
  check("per-visit hint does NOT re-fire when only decision_serial advances", shint_out("v", "V") == "")
  G.NEURO.state_enter_serial = 6
  check("per-visit hint re-fires when state_enter_serial advances", shint_out("v", "V") == "V")
  _G.G = { NEURO = { once_serials = {}, decision_serial = 5, state_enter_serial = 5 } }
  check("per-decision hint fires first", dhint("d", "D") == "D")
  G.NEURO.state_enter_serial = 50
  check("per-decision hint does NOT re-fire when only state_enter_serial advances", dhint("d", "D") == "")
  _G.G = { NEURO = { once_serials = {}, decision_serial = 1, state_enter_serial = 1 } }
  check("same tag on both helpers does not collide (decision side fires)", dhint("same", "DD") == "DD")
  check("same tag on both helpers does not collide (entry side still fires)", shint_out("same", "SS") == "SS")
end

do
  local Lifecycle = require("core.neuro_lifecycle")
  local Utils = require("util.utils")
  _G.G = { NEURO = { decision_serial = 42, state_enter_serial = 42, once_serials = { x = 1 } } }
  local ok = pcall(function() return Utils.neuro_ready() end)
  if ok and Utils.neuro_ready() then
    Lifecycle.reset_run_state()
    check("reset zeroes decision_serial", G.NEURO.decision_serial == 0)
    check("reset zeroes state_enter_serial", G.NEURO.state_enter_serial == 0)
  else
    check("reset zeroes decision_serial", false, "live reset unavailable -- nothing was checked")
    check("reset zeroes state_enter_serial", false, "live reset unavailable -- nothing was checked")
  end
end

do
  local D = require("core.dispatcher")
  local Actions = require("core.actions")
  local Config = require("core.config")
  local function bridge() return { send_action_result = function(self, id, ok, m) self.last = { id = id, ok = ok, m = m } end, send_context = function() end, register_actions = function() end } end
  local function base_G()
    _G.G = {
      STATE = 7, STATES = { SELECTING_HAND = 7 }, TIMERS = { REAL = 1000 },
      GAME = { current_round = { hands_left = 3, discards_left = 3 }, hands = { Flush = { level = 1, chips = 10, mult = 2 } }, blind = {} },
      hand = { cards = { {base={value="9",suit="Hearts"},sort_id=1,is_suit=function() return true end},
                         {base={value="5",suit="Hearts"},sort_id=2,is_suit=function() return true end} }, highlighted = {}, config = { highlighted_limit = 5 } },
      FUNCS = { get_poker_hand_info = function(sel) return "Flush", nil, { Flush = sel }, { sel[1], sel[2] }, nil end,
                play_cards_from_highlighted = function() return true end },
      NEURO = { decision_serial = 10, state_enter_serial = 3, once_serials = {},
                weak_fired_serial = 10 },
      jokers = { cards = {
        { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
          config = { center = { key = "j_a", set = "Joker" } } },
        { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
          config = { center = { key = "j_b", set = "Joker" } } },
      }, config = { card_limit = 5 } },
      play = nil,
    }
    _G.G.NEURO.play_confirm = {
      signature = "1,2",
      content = require("handlers.hand_handlers").play_content({ G.hand.cards[1], G.hand.cards[2] }),
      indices = { 1, 2 }, decision_serial = 10, run_generation = 0,
    }
    require("core.transition_guard").reset()
    require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
  end

  Config.set("NEURO_CONFIRM_HAND", "off")
  base_G()
  local before = G.NEURO.decision_serial
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  D.handle_message({ command = "action", data = { id = "d1", name = "play_hand", data = '{"indices":[1,2]}' } }, bridge())
  check("successful forced progress action (play_hand) bumps decision_serial",
    (G.NEURO.decision_serial or 0) == before + 1, "before=" .. tostring(before) .. " after=" .. tostring(G.NEURO.decision_serial))
  Config.set("NEURO_CONFIRM_HAND", "on")

  base_G()
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  require("core.force_state").arm("SELECTING_HAND", { "play_hand", "set_joker_order" },
    { play_hand = true, set_joker_order = true }, 1)
  local before2 = G.NEURO.decision_serial
  require("tests.helpers").stage_registered(nil, { "set_joker_order" })
  D.handle_message({ command = "action",
    data = { id = "d2", name = "set_joker_order", data = '{"from_index":1,"to_index":2}' } }, bridge())
  check("non-progress answer does NOT bump decision_serial (decision still pending)",
    (G.NEURO.decision_serial or 0) == before2, "before=" .. tostring(before2) .. " after=" .. tostring(G.NEURO.decision_serial))

  base_G()
  local before3 = G.NEURO.decision_serial
  require("tests.helpers").stage_registered(nil, { "cash_out" })
  D.handle_message({ command = "action", data = { id = "d3", name = "cash_out", data = "{}" } }, bridge())
  check("rejected/out-of-set answer does NOT bump decision_serial",
    (G.NEURO.decision_serial or 0) == before3, "before=" .. tostring(before3) .. " after=" .. tostring(G.NEURO.decision_serial))
end

do
  local Actions = require("core.actions")
  stub_valid(function(n) return n == "leave_shop" or n == "buy_from_shop" end)
  local FS = require("force.force_shop")
  local function q() return ((FS.build() or {}).query or "") .. H.drain_hints() end
  local function shop(njokers, cash)
    local jc = {}
    for _ = 1, (njokers or 0) do jc[#jc + 1] = { ability = { name = "J", mult = 0 }, cost = 3, config = { center = { key = "j_x" } } } end
    _G.G = {
      STATE = 5, STATES = { SHOP = 5 },
      P_BLINDS = { bl_head = { name = "The Head", key = "bl_head", set = "Blind", debuff = {} } },
      GAME = { dollars = cash or 8, interest_cap = 25, interest_amount = 1, blind_on_deck = "Big",
        round = 4,
        round_resets = { ante = 2, blind_choices = { Big = "bl_big", Boss = "bl_head" } },
        current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 }, modifiers = {} },
      NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
      jokers = { cards = jc }, consumeables = { cards = {} },
      shop_jokers = { cards = { { ability = { name = "Some Joker", mult = 0 }, cost = 3, config = { center = { key = "j_x", set = "Joker" } } } } },
      shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    }
  end
  local function new_decision() G.NEURO.decision_serial = G.NEURO.decision_serial + 1 end
  local function new_visit() G.NEURO.state_enter_serial = G.NEURO.state_enter_serial + 1; new_decision() end

  local VERDICTS = {
    "You own NO jokers",
    "None of your jokers multiply",
    "empty joker slot",
    "reorder it with set_joker_order",
    "sell_card frees a slot",
    "weigh your joker build",
    "poker hands are all still at base level",
    "still keep that interest",
    "+$1 per $5 held",
    "compounds into far more",
  }
  local function marks_in(text)
    local found = {}
    for _, mark in ipairs(VERDICTS) do
      if has(text, mark) then found[#found + 1] = mark end
    end
    table.sort(found)
    return table.concat(found, " | ")
  end
  local function verdict_free(label)
    local first = marks_in(q())
    local serial = G.NEURO.decision_serial
    G.NEURO.decision_serial = serial + 1
    local second = marks_in(q())
    G.NEURO.decision_serial = serial
    check("E-verdicts " .. label .. ": every build verdict this board raises survives the re-ask",
      first == second, first .. " -> " .. second)
  end

  shop(0)
  verdict_free("no jokers owned")
  new_decision()
  verdict_free("no jokers owned, second decision")

  shop(1)
  G.NEURO.plan = {
    hand = "flush build",
    hand_scope = require("core.plan_gate").current_blind_scope(),
    build = "no xMult yet",
    build_scope = require("core.plan_gate").current_build_scope(),
    money = "bank until the upgrade appears",
    money_scope = require("core.plan_gate").current_economy_scope(),
    ante = 2,
  }
  local qp = q()
  check("E-plan injected in shop (build read)", has(qp, "Build focus: no xMult yet"))
  check("E-plan injected in shop (current-blind decision)", has(qp, "flush build"))
  check("E-plan injected in shop (economy decision)", has(qp, "Economy decision: bank until the upgrade appears"))
  check("E-plan framed as decision notes, not a snapshot", has(qp, "do not treat them as a snapshot"))

  shop(2)
  local narrow_valid = Actions.is_action_valid
  Actions.is_action_valid = function(n)
    return n == "leave_shop" or n == "buy_from_shop" or n == "sell_card" or n == "set_joker_order"
  end
  verdict_free("sell_card and set_joker_order both offered")
  local qb = q()
  check("E-offer the reorder and sell forms are still stated",
    has(qb, "set_joker_order") and has(qb, "sell_card"), qb)
  Actions.is_action_valid = narrow_valid

  shop(1)
  verdict_free("one flat joker and an open slot")
  new_decision()
  verdict_free("one flat joker and an open slot, second decision")

  shop(5, 20); G.jokers.config = { card_limit = 5 }
  G.jokers.cards[1].config.center.key = "j_hologram"; G.jokers.cards[1].ability.x_mult = 2
  verdict_free("bank $20, xMult build, interest >= 3")
  shop(5, 8); G.jokers.config = { card_limit = 5 }
  G.jokers.cards[1].config.center.key = "j_hologram"; G.jokers.cards[1].ability.x_mult = 2
  verdict_free("bank $8, xMult build, interest < 3")
  shop(1, 20); G.jokers.config = { card_limit = 5 }
  G.jokers.cards[1].config.center.key = "j_hologram"; G.jokers.cards[1].ability.x_mult = 2
  verdict_free("one flat joker, bank $20")

  shop(1)
  check("E-primer present on visit entry", has(q(), "Upcoming Boss (The Head)"))
  new_decision()
  check("E-primer restated on the next decision of the same visit",
    has(q(), "Upcoming Boss (The Head)"))
  new_visit()
  check("E-primer re-shows on a NEW shop visit", has(q(), "Upcoming Boss (The Head)"))

  require("core.context_delivery").reset_transport()
  shop(0)
  G.jokers.cards = {
    { config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint" } },
      ability = { name = "Blueprint", set = "Joker", mult = 0 } },
    { config = { center = { key = "j_joker", set = "Joker", name = "Joker" } },
      ability = { name = "Joker", set = "Joker", mult = 4 } },
  }
  G.shop_vouchers.cards = { { cost = 10, ability = { set = "Voucher", name = "Hone" },
    config = { center = { key = "v_hone", name = "Hone", set = "Voucher" } } } }
  local raw121 = (FS.build() or {}).query or ""
  local wire121 = H.drain_hints()
  check("E-121 the copy-order fact rides the shop query", has(raw121, "Joker copy order:"), raw121)
  check("E-121 and never the retained channel", not has(wire121, "Joker copy order:"), wire121)
  check("E-121 the voucher-chain rule rides the retained channel", has(wire121, "unlocks"), wire121)
  check("E-121 and never the query", not has(raw121, "unlocks"), raw121)

  new_decision()
  local raw121b = (FS.build() or {}).query or ""
  local wire121b = H.drain_hints()
  check("E-121 the next decision restates the copy order",
    has(raw121b, "Joker copy order:"), raw121b)
  check("E-121 and does not re-teach the voucher rule", not has(wire121b, "unlocks"), wire121b)
  unstub_valid()
end

do
  local Actions = require("core.actions")
  stub_valid(function(n) return n == "choose_pack_card" or n == "skip_pack" end)
  local FP = require("force.force_pack")
  local function q() return ((FP.build("BUFFOON_PACK") or {}).query or "") .. H.drain_hints() end
  local function pack()
    local joker = { ability = { name = "Wily", mult = 0 }, cost = 4, config = { center = { key = "j_x", set = "Joker" } } }
    _G.G = {
      STATE = 9, STATES = { BUFFOON_PACK = 9 },
      GAME = { pack_choices = 2, dollars = 4, modifiers = {}, current_round = {} },
      NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
      jokers = { cards = {} }, consumeables = { cards = {} },
      pack_cards = { cards = { joker } }, booster_pack = { cards = { joker } },
    }
  end
  local function new_decision() G.NEURO.decision_serial = G.NEURO.decision_serial + 1 end

  pack()
  check("F-pick facts present on pick 1",
    has(q(), "almost always better than skipping")
      and has(q(), "None of your jokers multiply"), q())
  new_decision()
  check("F-pick facts restated on the next pick",
    has(q(), "almost always better than skipping")
      and has(q(), "None of your jokers multiply"), q())

  Actions.is_action_valid = function(n) return n == "choose_pack_card" or n == "skip_pack" end
  local function stdpack()
    local pc = { base = { value = "9", suit = "Hearts" }, config = { center = { key = "c", set = "Default" } } }
    _G.G = {
      STATE = 9, STATES = { STANDARD_PACK = 9 },
      GAME = { pack_choices = 2, modifiers = {}, current_round = {} },
      NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
      jokers = { cards = {} }, consumeables = { cards = {} },
      pack_cards = { cards = { pc } }, booster_pack = { cards = { pc } },
    }
  end
  stdpack()
  local q2 = ((FP.build("STANDARD_PACK") or {}).query or "") .. H.drain_hints()
  check("F-pack_std teaching present on pick 1", has(q2, "straight to your deck"))
  new_decision()
  local q2b = ((FP.build("STANDARD_PACK") or {}).query or "") .. H.drain_hints()
  check("F-pack_std teaching restated on the next pick of the same pack",
    has(q2b, "straight to your deck"), q2b)
  unstub_valid()
end

do
  local Actions = require("core.actions")
  stub_valid(function(n) return n == "choose_pack_card" or n == "skip_pack" end)
  local FP = require("force.force_pack")
  local function q() return ((FP.build("PLANET_PACK") or {}).query or "") .. H.drain_hints() end
  local function planetpack(hands)
    local planet = { ability = { name = "Jupiter", set = "Planet" }, config = { center = { key = "c_jupiter", set = "Planet" } } }
    _G.G = {
      STATE = 9, STATES = { PLANET_PACK = 9 },
      GAME = { pack_choices = 1, modifiers = {}, current_round = {}, hands = hands or {} },
      NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
      jokers = { cards = {} }, consumeables = { cards = {} },
      pack_cards = { cards = { planet } }, booster_pack = { cards = { planet } },
    }
  end

  planetpack({
    ["Two Pair"] = { visible = true, level = 3, played = 6 },
    ["Flush"]    = { visible = true, level = 2, played = 3 },
  })
  local q1 = q()
  check("the pack force states what levelling a hand type does",
    has(q1, "level a type you actually play"), q1)
  check("the levels themselves still reach the model in a Planet pack",
    (function()
      local Compact = require("context.context_compact")
      Compact.invalidate_cache()
      local ctx = Compact.build("PLANET_PACK", { "choose_pack_card", "skip_pack" },
        { split = "state", no_cache = true }) or ""
      return ctx:find("Two Pair", 1, true) ~= nil and ctx:find("Flush", 1, true) ~= nil, ctx
    end)())
  unstub_valid()
end

do
  local Actions = require("core.actions")
  stub_valid(function(n) return n == "skip_pack" end)
  local FP = require("force.force_pack")
  local tarot = { ability = { name = "The Tower", set = "Tarot" }, config = { center = { key = "c_tower", set = "Tarot" } } }
  _G.G = {
    STATE = 9, STATES = { TAROT_PACK = 9 },
    GAME = { pack_choices = 1, modifiers = {}, current_round = {} },
    NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
    jokers = { cards = {} }, consumeables = { cards = {} },
    pack_cards = { cards = { tarot } }, booster_pack = { cards = { tarot } },
  }
  local q = ((FP.build("TAROT_PACK") or {}).query or "") .. H.drain_hints()
  check("blocked consumable pack has NO choose_pack_card in the move list", not has(q, 'choose_pack_card|'))
  check("blocked consumable pack explains WHY you can't take (not a bare skip-only)",
    has(q, "You can't take a card from this pack right now"), q)
  check("blocked pack still offers skip_pack", has(q, "skip_pack"))
  unstub_valid()
end

do
  _G.G = {
    NEURO = { session_once_serials = {}, once_serials = {}, state_enter_serial = 1, decision_serial = 1 }
  }
  local sess_hint = function(t, txt)
    FactHints.once_per_session_hint(t, txt)
    return H.drain_hints()
  end
  check("session hint fires on first sight", sess_hint("card_rank", "RANKS") == "RANKS")
  check("session hint suppressed on repeat", sess_hint("card_rank", "RANKS") == "")
  G.NEURO.decision_serial = 5
  G.NEURO.state_enter_serial = 10
  check("session hint stays suppressed across decision/state advances", sess_hint("card_rank", "RANKS") == "")
end

do
  local function round_hint(t, txt)
    FactHints.once_per_round_hint(t, txt)
    return H.drain_hints()
  end
  local function board(round)
    _G.G = { NEURO = { once_serials = {}, decision_serial = 1, state_enter_serial = 1 },
      GAME = { round = round, round_resets = { ante = 1 } } }
  end

  board(3)
  check("round hint fires on first sight in a round", round_hint("rules", "RULES") == "RULES")
  check("suppressed on repeat within the same round", round_hint("rules", "RULES") == "")
  G.NEURO.state_enter_serial = 7
  check("a new state entry in the same round does NOT re-fire it",
    round_hint("rules", "RULES") == "", "state_enter_serial advanced")
  G.NEURO.decision_serial = 9
  check("nor does a new decision", round_hint("rules", "RULES") == "")
  G.GAME.round_resets.ante = 2
  check("nor a new ante while the round number stands", round_hint("rules", "RULES") == "")
  G.GAME.round = 4
  check("the next round re-arms it", round_hint("rules", "RULES") == "RULES")
  check("and then suppresses it again", round_hint("rules", "RULES") == "")
  G.NEURO.once_serials = {}
  FactHints.once_per_round_hint("rules", "RULES")
  check("a run reset re-arms the gate", FactHints.pending_count() == 1,
    tostring(FactHints.pending_count()))
  check("P8b but the retained channel does not re-send a frame the model still holds",
    H.drain_hints() == "" and FactHints.pending_count() == 0)
  require("core.context_delivery").reset_transport()
  check("P8c a NEW transport view replays it -- it is the SDK's memory that was reset, not the gate",
    round_hint("rules", "RULES") == "RULES")

  board(5)
  G.GAME.round = nil
  check("no round number -> withheld, and nothing is parked under a :0 key",
    round_hint("norounds", "N") == "" and FactHints.pending_count() == 0)
  G.GAME.round = 5
  check("and it is still owed once the round number is back",
    round_hint("norounds", "N") == "N")

  board(2)
  check("distinct tags stay independent",
    round_hint("a", "A") == "A" and round_hint("b", "B") == "B")
  check("empty text never emits", round_hint("blank", "") == "")

  board(6)
  FactHints.once_per_round_hint("dropme", "D")
  check("hint_is_pending sees a queued round hint",
    FactHints.hint_is_pending("dropme") == true)
  FactHints.drop_hint("dropme")
  check("drop_hint removes it from that view",
    FactHints.hint_is_pending("dropme") == false)
  check("and empties it from the queue", FactHints.pending_count() == 0)
  check("a dropped round hint can be queued again", round_hint("dropme", "D") == "D")

  board(7)
  FactHints.once_per_decision_hint("both", "A")
  FactHints.once_per_round_hint("both", "R")
  check("a decision hint and a round hint on the same tag are two separate gates",
    FactHints.pending_count() == 2)
  check("hint_is_pending sees the pair", FactHints.hint_is_pending("both") == true)
  FactHints.drop_hint("both")
  check("drop_hint clears both suffixed prefixes",
    FactHints.pending_count() == 0 and FactHints.hint_is_pending("both") == false)
end

do
  local Actions = require("core.actions")
  local Delivery = require("core.context_delivery")
  local real_amount = _G.get_blind_amount
  _G.get_blind_amount = function(a) return 300 * a end
  local FSH = require("force.force_selecting_hand")
  local FS = require("force.force_shop")

  local STATE_MARK = {
    rules_any        = "Rules: 1)",
    consumable_slots = "To use a targeting consumable",
    bp_chain         = "Joker copy order:",
  }
  local RULE_MARK = {
    voucher_chain      = "unlocks",
    voucher_basics_run = "A voucher is a permanent",
  }
  local DELETED_MARK = {
    correction = "no discards are left this round",
  }

  local NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 0, decision_serial = 0 }
  Delivery.reset_transport()

  local hits, forces = {}, 0
  local function count(query, retained)
    forces = forces + 1
    for tag, mark in pairs(STATE_MARK) do
      if query:find(mark, 1, true) then
        hits[tag] = (hits[tag] or 0) + 1
      end
      if retained:find(mark, 1, true) then
        hits[tag .. "@retained"] = (hits[tag .. "@retained"] or 0) + 1
      end
    end
    for tag, mark in pairs(RULE_MARK) do
      if retained:find(mark, 1, true) then hits[tag] = (hits[tag] or 0) + 1 end
      if query:find(mark, 1, true) then
        hits[tag .. "@query"] = (hits[tag .. "@query"] or 0) + 1
      end
    end
    for tag, mark in pairs(DELETED_MARK) do
      if query:find(mark, 1, true) or retained:find(mark, 1, true) then
        hits[tag] = (hits[tag] or 0) + 1
      end
    end
  end
  local function reset_hits() hits, forces = {}, 0 end

  local VALN = { J = "Jack", Q = "Queen", K = "King", A = "Ace" }
  local RANKS = { "A", "K", "Q", "J", "9", "8", "7", "6" }
  local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
  local function hand_cards()
    local cards = {}
    for i = 1, 8 do
      local suit = SUITS[((i - 1) % 4) + 1]
      cards[i] = { base = { value = VALN[RANKS[i]] or RANKS[i], suit = suit }, sort_id = i,
        config = { center = { key = "c_base", set = "Default" } },
        is_suit = function(_, sx) return sx == suit end }
    end
    return cards
  end
  local jokers = {
    { config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint" } },
      ability = { name = "Blueprint", set = "Joker", mult = 0 }, sell_cost = 2 },
    { config = { center = { key = "j_joker", set = "Joker", name = "Joker" } },
      ability = { name = "Joker", set = "Joker", mult = 4 }, sell_cost = 2 },
  }
  local function board(round)
    _G.G = {
      P_BLINDS = {},
      GAME = {
        round = round, dollars = 8, interest_cap = 25, interest_amount = 1, win_ante = 8,
        used_vouchers = {}, modifiers = {}, probabilities = { normal = 1 }, starting_params = {},
        round_resets = { ante = 3, discards = 3, blind_choices = {} },
        current_round = { hands_left = 4, discards_left = 3, discards_used = 0,
          free_rerolls = 0, reroll_cost = 5, most_played_poker_hand = "High Card" },
        hands = { ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 3 } },
        blind = { name = "Small Blind", chips = 300 },
      },
      FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
      NEURO = NEURO,
      hand = { cards = hand_cards(), config = { highlighted_limit = 5 }, highlighted = {} },
      jokers = { cards = jokers, config = { card_limit = 5 } },
      consumeables = { cards = { { ability = { name = "The Lovers", set = "Tarot",
          consumeable = { max_highlighted = 1, min_highlighted = 1 } },
        config = { center = { key = "c_lovers", set = "Tarot", name = "The Lovers" } } } },
        config = { card_limit = 2 } },
      shop_jokers = { cards = {} },
      shop_vouchers = { cards = { { cost = 10, ability = { set = "Voucher", name = "Hone" },
        config = { center = { key = "v_hone", name = "Hone", set = "Voucher" } } } } },
      shop_booster = { cards = {} },
      playing_cards = {}, deck = { cards = {} }, play = nil,
    }
  end
  local function enter() NEURO.state_enter_serial = NEURO.state_enter_serial + 1
    NEURO.decision_serial = NEURO.decision_serial + 1 end
  local function emit(build)
    FactHints.reset_pending()
    local res = build()
    local query = ((res or {}).query or "")
    local retained = H.drain_hints()
    count(query, retained)
    return query, retained
  end
  stub_valid(function(n)
    if n == "play_hand" or n == "discard_hand" then return UNSTUBBED_IS_ACTION_VALID(n) end
    return n == "use_consumable" or n == "sell_card" or n == "set_joker_order"
      or n == "leave_shop" or n == "buy_from_shop"
  end)

  local hand_forces, shop_forces = 0, 0
  local function play_round(round)
    board(round); enter()
    local opening = emit(FSH.build)
    hand_forces = hand_forces + 1
    for d = 1, 3 do
      board(round)
      G.GAME.current_round.discards_left = 3 - d
      G.GAME.current_round.discards_used = d
      enter()
      emit(FSH.build)
      hand_forces = hand_forces + 1
    end
    for h = 1, 2 do
      board(round)
      G.GAME.current_round.hands_left = 4 - h
      G.GAME.current_round.discards_left = 0
      G.GAME.current_round.discards_used = 3
      enter()
      emit(FSH.build)
      hand_forces = hand_forces + 1
    end
    local function shop_board()
      board(round)
      G.GAME.current_round.hands_left = 0
      G.GAME.current_round.discards_left = 0
      G.GAME.current_round.discards_used = 3
    end
    shop_board(); enter()
    emit(FS.build); shop_forces = shop_forces + 1
    NEURO.decision_serial = NEURO.decision_serial + 1
    emit(FS.build); shop_forces = shop_forces + 1
    shop_board(); enter()
    local after_pack = emit(FS.build); shop_forces = shop_forces + 1
    NEURO.decision_serial = NEURO.decision_serial + 1
    emit(FS.build); shop_forces = shop_forces + 1
    return opening, after_pack
  end

  reset_hits()
  hand_forces, shop_forces = 0, 0
  local opening = play_round(7)
  local round7 = forces

  check("every state claim is on every force whose precondition holds -- none is taught once",
    (hits.rules_any or 0) == hand_forces
      and (hits.consumable_slots or 0) == hand_forces
      and (hits.bp_chain or 0) == (hand_forces + shop_forces),
    string.format("forces=%d hand=%d shop=%d rules=%s cons=%s bp=%s", round7, hand_forces,
      shop_forces, tostring(hits.rules_any), tostring(hits.consumable_slots),
      tostring(hits.bp_chain)))
  check("Q1b and none of them reached the retained channel, which cannot take them back",
    (hits["rules_any@retained"] or 0) == 0 and (hits["consumable_slots@retained"] or 0) == 0
      and (hits["bp_chain@retained"] or 0) == 0,
    string.format("rules=%s cons=%s bp=%s", tostring(hits["rules_any@retained"]),
      tostring(hits["consumable_slots@retained"]), tostring(hits["bp_chain@retained"])))
  check("Q1c every permanent mechanic is taught exactly once across the whole round",
    (hits.voucher_chain or 0) == 1 and (hits.voucher_basics_run or 0) == 1,
    string.format("chain=%s basics=%s", tostring(hits.voucher_chain),
      tostring(hits.voucher_basics_run)))
  check("Q1d and none of them rode an ephemeral force, which would teach and forget it",
    (hits["voucher_chain@query"] or 0) == 0 and (hits["voucher_basics_run@query"] or 0) == 0,
    string.format("chain=%s basics=%s", tostring(hits["voucher_chain@query"]),
      tostring(hits["voucher_basics_run@query"])))
  local revived = {}
  for tag in pairs(DELETED_MARK) do
    if (hits[tag] or 0) > 0 then revived[#revived + 1] = tag end
  end
  table.sort(revived)
  check("Q1e no deleted build verdict came back with the facts",
    #revived == 0, table.concat(revived, ","))
  check("the opening force of the round carries the full rules block",
    opening:find("Rules: 1)", 1, true) ~= nil, opening)

  reset_hits()
  local after_pack, after_pack_retained
  do
    board(7)
    G.GAME.current_round.hands_left = 0
    G.GAME.current_round.discards_left = 0
    G.GAME.current_round.discards_used = 3
    enter()
    after_pack, after_pack_retained = emit(FS.build)
  end
  check("coming back from a booster into the same shop restates the mutable facts",
    (hits.bp_chain or 0) == 1, tostring(hits.bp_chain) .. " || " .. after_pack)
  check("Q3b and teaches the retained channel nothing new",
    after_pack_retained == "", after_pack_retained)

  reset_hits()
  local reentry, reentry_retained
  do
    board(7)
    G.GAME.current_round.hands_left = 2
    G.GAME.current_round.discards_left = 0
    G.GAME.current_round.discards_used = 3
    enter()
    reentry, reentry_retained = emit(FSH.build)
  end
  check("re-entering SELECTING_HAND after a play carries the rules and the slot fact again",
    (hits.rules_any or 0) == 1 and (hits.consumable_slots or 0) == 1
      and (hits.bp_chain or 0) == 1,
    string.format("rules=%s cons=%s bp=%s", tostring(hits.rules_any),
      tostring(hits.consumable_slots), tostring(hits.bp_chain)))
  check("Q4b and adds nothing to the retained channel", reentry_retained == "", reentry_retained)

  check("Q4c the re-entry carries the reminder, not a second copy of the full block",
    #reentry < #opening and reentry:find("Rules: 1)", 1, true) ~= nil,
    #reentry .. " vs " .. #opening)

  reset_hits()
  do
    board(7)
    jokers = { jokers[2], jokers[1] }
    G.jokers.cards = jokers
    G.GAME.current_round.hands_left = 0
    G.GAME.current_round.discards_left = 0
    NEURO.decision_serial = NEURO.decision_serial + 1
    local q = emit(FS.build)
    check("reordering jokers inside the visit restates the copy order, following the roster",
      q:find("Blueprint (slot 2)", 1, true) ~= nil, q)
  end
  check("and re-teaches no permanent mechanic",
    (hits.voucher_chain or 0) == 0 and (hits.voucher_basics_run or 0) == 0,
    string.format("chain=%s basics=%s", tostring(hits.voucher_chain),
      tostring(hits.voucher_basics_run)))

  reset_hits()
  hand_forces, shop_forces = 0, 0
  local opening8 = play_round(8)
  check("the next round states the full rules block again, on the round clock",
    opening8:find("Rules: 1)", 1, true) ~= nil
      and #opening8 >= #reentry, tostring(#opening8))
  check("Q7b and every state claim is still on every force of it",
    (hits.rules_any or 0) == hand_forces
      and (hits.consumable_slots or 0) == hand_forces
      and (hits.bp_chain or 0) == (hand_forces + shop_forces),
    string.format("rules=%s cons=%s bp=%s", tostring(hits.rules_any),
      tostring(hits.consumable_slots), tostring(hits.bp_chain)))
  check("but the permanent mechanics the model already holds are not re-sent",
    (hits.voucher_chain or 0) == 0 and (hits.voucher_basics_run or 0) == 0,
    string.format("chain=%s basics=%s", tostring(hits.voucher_chain),
      tostring(hits.voucher_basics_run)))
  local revived8 = {}
  for tag in pairs(DELETED_MARK) do
    if (hits[tag] or 0) > 0 then revived8[#revived8 + 1] = tag end
  end
  table.sort(revived8)
  check("Q8b and nothing deleted came back in the second round either",
    #revived8 == 0, table.concat(revived8, ","))

  unstub_valid()
  _G.get_blind_amount = real_amount
end

done()
