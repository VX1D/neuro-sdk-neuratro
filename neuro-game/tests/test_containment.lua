-- run: luajit test_containment.lua from neuro-game/; inert in-game (loaded by nothing)
package.path = "./?.lua;;" .. package.path
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local Utils = require("util.utils")
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

local HF = require("facts.hand_facts")

-- contained_types mirrors evaluate_poker_hand non-empty entries (misc_functions.lua: exact-count parts, two pair branch, 5->4->3->pair demotion)
do
  local ct = HF.contained_types
  local fh = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("Queen", "Hearts"), card("Queen", "Diamonds") }
  local t = ct(fh)
  check("FH group contains Full House", t["Full House"] == true)
  check("FH group contains Pair (demotion via trips)", t["Pair"] == true)
  check("FH group contains Two Pair (trips+pair branch)", t["Two Pair"] == true)
  check("FH group contains Three of a Kind", t["Three of a Kind"] == true)
  check("FH group does not contain Flush", not t["Flush"])

  local tp = ct({ card("King", "Hearts"), card("King", "Spades"), card("Queen", "Hearts"), card("Queen", "Diamonds") })
  check("2+2 contains Two Pair + Pair, not Full House",
    tp["Two Pair"] == true and tp["Pair"] == true and not tp["Full House"] and not tp["Three of a Kind"])

  local quads = ct({ card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("King", "Diamonds"), card("9", "Clubs") })
  check("quads contain Four/Three/Pair via demotion",
    quads["Four of a Kind"] and quads["Three of a Kind"] and quads["Pair"])
  check("quads+kicker contain no Full House (exact-count parts)", not quads["Full House"])
  check("quads+kicker contain no Two Pair", not quads["Two Pair"])

  local trips = ct({ card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs") })
  check("bare trips contain Pair, not Two Pair", trips["Pair"] == true and not trips["Two Pair"])
end

-- typed jokers tagged by containment on ready rows (card.lua fires via next(poker_hands[type])); debuffed jokers never tagged
do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2
  G.GAME.hands = {
    ["Full House"] = { visible = true, level = 1, chips = 40, mult = 4 },
    ["Pair"] = { visible = true, level = 1, chips = 10, mult = 2 },
  }
  G.jokers = { cards = {
    { ability = { name = "Jolly Joker", type = "Pair", t_mult = 8 }, config = { center = { key = "j_jolly" } } },
  }, config = { card_limit = 5 } }
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("4", "Diamonds"), card("8", "Clubs"), card("Queen", "Hearts"), card("Queen", "Diamonds") }, highlighted = {} }
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Full House", nil, {
      ["Full House"] = { { hc[1], hc[2], hc[3], hc[6], hc[7] } },
      ["Pair"] = { { hc[6], hc[7] } },
    }, { hc[1], hc[2], hc[3], hc[6], hc[7] }, nil
  end
  local s = HF.summary()
  check("Pair joker tagged on Full House row (containment)",
    s:find("Full House[1,2,3,6,7](lv1 40c x4)(J1 applies)", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("Pair joker tagged on Pair row (exact type still applies)",
    s:find("Pair[6,7](lv1 10c x2)(J1 applies)", 1, true) ~= nil, s:match("Ready:[^%.]*"))
  check("Pair joker tagged on synthesized Two Pair row",
    s:find("Two Pair[1,2,6,7](J1 applies)", 1, true) ~= nil, s:match("Ready:[^%.]*"))

  -- engine (common_events.lua:586) skips debuffed jokers entirely
  G.jokers.cards[1].debuff = true
  local s_deb = HF.summary()
  check("debuffed typed joker never tagged", s_deb:find("applies", 1, true) == nil, s_deb:match("Ready:[^%.]*"))
  G.jokers.cards[1].debuff = nil

  -- find_joker excludes debuffed, so a debuffed splash adds nothing
  G.jokers.cards[2] = { ability = { name = "Splash" }, config = { center = { key = "j_splash" } }, debuff = true }
  local s_spl = HF.summary()
  check("debuffed Splash -> no all-cards-score clause",
    s_spl:find("All played cards score (Splash).", 1, true) == nil, s_spl)
  G.jokers.cards[2].debuff = nil
  local s_spl2 = HF.summary()
  check("live Splash -> clause present",
    s_spl2:find("All played cards score (Splash).", 1, true) ~= nil, s_spl2)
  G.FUNCS.get_poker_hand_info = nil
  G.jokers = nil
end

-- composite ready shapes the full-hand evaluator understates
do
  mock_state("Normal", "SELECTING_HAND")
  G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 2

  -- 3 exact pairs: full-hand two pair entry is empty (#pairs==3 fails exactly-2 branch), but two highest pairs score a two pair
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("Queen", "Hearts"),
    card("Queen", "Diamonds"), card("9", "Clubs"), card("9", "Spades") }, highlighted = {} }
  local hc = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Pair", nil, {
      ["Pair"] = { { hc[1], hc[2] }, { hc[3], hc[4] }, { hc[5], hc[6] } },
      ["High Card"] = { { hc[1] } },
    }, { hc[1], hc[2] }, nil
  end
  local ready1 = HF.summary():match("Ready:[^%.]*") or ""
  check("3 pairs -> Two Pair Ready with the two highest pairs",
    ready1:find("Two Pair[1,2,3,4]", 1, true) ~= nil, ready1)

  -- two trips: full-hand full house and two pair entries empty, but playing 3+2 scores a full house
  G.hand = { cards = { card("King", "Hearts"), card("King", "Spades"), card("King", "Clubs"),
    card("9", "Clubs"), card("9", "Spades"), card("9", "Diamonds") }, highlighted = {} }
  local h2 = G.hand.cards
  G.FUNCS.get_poker_hand_info = function(_)
    return "Three of a Kind", nil, {
      ["Three of a Kind"] = { { h2[1], h2[2], h2[3] }, { h2[4], h2[5], h2[6] } },
      ["Pair"] = { { h2[1], h2[2] } },
    }, { h2[1], h2[2], h2[3] }, nil
  end
  local ready2 = HF.summary():match("Ready:[^%.]*") or ""
  check("two trips -> Full House Ready (trips + pair from second trips)",
    ready2:find("Full House[1,2,3,4,5]", 1, true) ~= nil, ready2)
  check("two trips -> Two Pair Ready synthesized too",
    ready2:find("Two Pair[1,2,4,5]", 1, true) ~= nil, ready2)
  G.FUNCS.get_poker_hand_info = nil
end

-- preview ride-alongs re-arm the force: non_progress answer clears force_inflight and fingerprint so unchanged force re-sends without waiting for stall watchdog
do
  local function bridge_mock()
    return {
      send_action_result = function(self, id, ok, msg) self.last = { id = id, ok = ok, msg = msg } end,
      send_context = function() end,
      register_actions = function() end,
    }
  end
  local function preview_msg(id)
    return { command = "action", data = { id = id, name = "simulate_hand", data = '{"indices":[1,2]}' } }
  end
  local function setup()
    mock_state("Normal", "SELECTING_HAND")
    G.STATES = { SELECTING_HAND = 7 }; G.STATE = 7
    G.TIMERS = { REAL = 5000 }
    G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
    G.GAME.current_round.hands_left = 3; G.GAME.current_round.discards_left = 3
    G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2 } }
    G.FUNCS.get_poker_hand_info = function(sel) return "Pair", nil, { Pair = { { sel[1], sel[2] } } }, { sel[1], sel[2] }, nil end
    G.NEURO.force_inflight = true
    G.NEURO.force_state = "SELECTING_HAND"
    G.NEURO.last_force_fingerprint = "FP-unchanged"
    G.NEURO.force_dirty = false
    require("core.enforce").post_action(nil, true)
  end

  -- ride-along: simulate_hand not in the force action set
  setup()
  G.NEURO.force_action_set = { play_hand = true }
  local b1 = bridge_mock()
  D.handle_message(preview_msg("pv-1"), b1)
  check("ride-along preview succeeded", b1.last and b1.last.ok == true, b1.last and b1.last.msg)
  check("ride-along preview clears force_inflight", G.NEURO.force_inflight == false)
  check("ride-along preview drops fingerprint (force re-sends)", G.NEURO.last_force_fingerprint == nil)
  check("ride-along preview dirties force", G.NEURO.force_dirty == true)

  -- in-set: simulate_hand offered by the force itself
  setup()
  G.NEURO.force_action_set = { play_hand = true, simulate_hand = true }
  local b2 = bridge_mock()
  D.handle_message(preview_msg("pv-2"), b2)
  check("in-set preview succeeded", b2.last and b2.last.ok == true, b2.last and b2.last.msg)
  check("in-set preview clears force_inflight", G.NEURO.force_inflight == false)
  check("in-set preview drops fingerprint", G.NEURO.last_force_fingerprint == nil)
  check("in-set preview dirties force", G.NEURO.force_dirty == true)

  -- progress action keeps the fingerprint (only non_progress re-arms the same force)
  setup()
  G.NEURO.force_action_set = { play_hand = true }
  local b3 = bridge_mock()
  D.handle_message({ command = "action", data = { id = "pv-3", name = "play_hand",
    data = '{"indices":[1,2]}' } }, b3)
  check("progress answer succeeded", b3.last and b3.last.ok == true, b3.last and b3.last.msg)
  check("progress answer clears inflight without dropping fingerprint",
    G.NEURO.force_inflight == false and G.NEURO.last_force_fingerprint == "FP-unchanged")
  G.FUNCS.get_poker_hand_info = nil
  G.TIMERS = nil
end

-- mixed valid/invalid indices priced with an explicit note; all-invalid still errors
do
  local Info = require("handlers.info_handlers")
  mock_state("Normal", "SELECTING_HAND")
  G.hand = { cards = { card("5", "Hearts"), card("5", "Spades"), card("9", "Clubs") }, highlighted = {} }
  G.GAME.hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2 } }
  G.FUNCS.get_poker_hand_info = function(sel) return "Pair", nil, { Pair = sel }, { sel[1] }, nil end
  local c = Info.handle_simulate_hand({ indices = { 1, 7, 9 } })
  local ok_s, r_s = pcall(c)
  check("mixed indices still price the valid set", type(c) == "function" and ok_s and r_s:find("Pair") ~= nil, r_s)
  check("mixed indices carry the invalid-note",
    ok_s and r_s:find("2 index(es) out of range 1-3 ignored", 1, true) ~= nil and r_s:find("(7,9)", 1, true) ~= nil, r_s)
  local c2, e2 = Info.handle_simulate_hand({ indices = { 7, 9 } })
  check("all-invalid indices still error", c2 == nil and type(e2) == "string" and e2:find("No valid indices") ~= nil, e2)
  local c3 = Info.handle_simulate_hand({ indices = { 1, 2 } })
  local ok3, r3 = pcall(c3)
  check("all-valid indices carry no note", ok3 and r3:find("invalid", 1, true) == nil, r3)
  G.FUNCS.get_poker_hand_info = nil
end

print(string.format("\n%d/%d passed", total - fails, total))
if fails > 0 then os.exit(1) end
