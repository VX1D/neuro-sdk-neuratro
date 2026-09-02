
_G.NEURO_TEST = true
if not love then
  love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("once-scope")
local H = require("tests.helpers")

local BASE_MARK = "Level-1 starting hand values"

local function count_sub(s, sub)
  local n, pos = 0, 1
  while true do
    local a = s:find(sub, pos, true)
    if not a then break end
    n = n + 1; pos = a + #sub
  end
  return n
end

do
  local ContextCompact = require("context.context_compact")
  local ContextReadable = require("context.context_readable")
  local FactHints = require("facts.fact_hints")
  local Once = require("util.once")

  local function shop_world(hands)
    _G.G = {
      STATES = { SHOP = 5, SELECTING_HAND = 2 }, STATE = 5, STATE_COMPLETE = true,
      NEURO = { enabled = true },
      TIMERS = { REAL = 100 },
      FUNCS = {},
      GAME = {
        dollars = 10, chips = 0, used_vouchers = {}, modifiers = {},
        current_round = {}, round_resets = { ante = 1 },
        hands = hands,
      },
      jokers = { cards = {}, config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      deck = { cards = {} },
    }
    ContextCompact.invalidate_cache()
    FactHints.reset_pending()
    require("core.context_delivery").reset_transport()
  end

  local function build_stable()
    local ok, list = pcall(ContextCompact.build, "SHOP", nil,
      { split = "stable", full_jokers = true, no_cache = true, return_list = true })
    return ok and table.concat(list or {}, "\n") or nil
  end
  local function build_force()
    return ContextReadable.build("SHOP", { "buy_from_shop" }) or ""
  end

  shop_world({
    Pair  = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, s_chips = 35, s_mult = 4, l_chips = 0, l_mult = 0, played = 0 },
  })

  -- The exact order of core/orchestrator.lua:549-550 inside one force-arming pass.
  local stable_txt = build_stable()
  local force_txt = build_force()

  check("the stable pass really runs (it is the one that used to eat the gate)",
    stable_txt ~= nil, "ContextCompact.build(split='stable') raised")
  check("the discarded stable half never carries the base values",
    not (stable_txt or ""):find(BASE_MARK, 1, true), tostring(stable_txt))
  check("the force half still prints the compact #185 headline",
    force_txt:find("Hand levels: all level 1.", 1, true) ~= nil, force_txt)
  local GATE = "shint:hand_base_values:Flush,Pair"
  check("no build spends the session gate -- booking waits for a successful send",
    Once.peek(GATE, "session") == true)
  check("the two builds queue the base values exactly once between them",
    FactHints.pending_count() == 1, tostring(FactHints.pending_count()))

  local delivered = H.drain_hints()
  check("the delivered text carries a real base chips number (Flush=35)",
    delivered:find("Flush: 35 chips", 1, true) ~= nil, delivered)
  check("the delivered text carries a real base mult number (Pair x2)",
    delivered:find("Pair: 10 chips x 2 mult", 1, true) ~= nil, delivered)
  check("the gate is spent only once the text is on the wire",
    Once.peek(GATE, "session") == false)

  ContextCompact.invalidate_cache()
  build_stable()
  local again = build_force()
  check("a later SHOP rebuild queues nothing (once per session, not per rebuild)",
    FactHints.pending_count() == 0, tostring(FactHints.pending_count()))
  check("and the rebuilt force half is back to the bare compact line",
    again:find("Hand levels: all level 1.", 1, true) ~= nil
      and not again:find(BASE_MARK, 1, true), again)

  shop_world({
    Pair  = { visible = true, level = 3, chips = 30, mult = 4, s_chips = 10, s_mult = 2, l_chips = 10, l_mult = 1, played = 5 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, s_chips = 35, s_mult = 4, l_chips = 0, l_mult = 0, played = 0 },
  })
  local up = build_force()
  check("upgraded hand is still listed with its own numbers",
    up:find("Pair: level 3, 30 chips x 4 mult = 120 before any card or joker, played 5.", 1, true) ~= nil, up)
  check("'(all other hands: level 1)' summary is preserved",
    up:find("(all other hands: level 1)", 1, true) ~= nil, up)
  local up_hint = H.drain_hints()
  check("the summarized (non-upgraded) Flush still gets its base value",
    up_hint:find("Flush: 35 chips", 1, true) ~= nil, up_hint)
  check("the upgraded hand contributes its fixed level-1 base, not its current one",
    up_hint:find("Pair: 10 chips x 2 mult", 1, true) ~= nil
      and not up_hint:find("Pair: 30", 1, true)
      and not up_hint:find("level 3", 1, true), up_hint)

  shop_world({
    Pair  = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, s_chips = 35, s_mult = 4, l_chips = 0, l_mult = 0, played = 0 },
  })
  G.STATE = 2 -- SELECTING_HAND
  local ok_bs, blind = pcall(ContextCompact.build, "BLIND_SELECT", nil,
    { split = "volatile", no_cache = true })
  check("outside SHOP nothing is queued (no scope creep)",
    ok_bs and FactHints.pending_count() == 0,
    tostring(ok_bs) .. "/" .. tostring(FactHints.pending_count()) .. "/" .. tostring(blind))

  shop_world({
    Pair  = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 },
    Flush = { visible = true, level = 1, chips = 35, mult = 4, s_chips = 35, s_mult = 4, l_chips = 0, l_mult = 0, played = 0 },
    ["Five of a Kind"] = { visible = false, level = 1, chips = 120, mult = 12, s_chips = 120, s_mult = 12, l_chips = 0, l_mult = 0, played = 0 },
  })
  build_stable(); build_force()
  local first = H.drain_hints()
  check("the first delivery covers the hands that are visible then",
    first:find("Pair: 10 chips x 2 mult", 1, true) ~= nil
      and first:find("Flush: 35 chips", 1, true) ~= nil, first)
  check("a hand that is still secret is not quoted (it is not knowable yet)",
    not first:find("Five of a Kind", 1, true), first)

  G.GAME.hands.Pair.level = 3
  G.GAME.hands.Pair.chips = 30
  G.GAME.hands.Pair.mult = 4
  G.GAME.hands.Pair.played = 5
  ContextCompact.invalidate_cache()
  build_stable(); build_force()
  check("levelling a hand does not re-open the gate (#185 saving intact)",
    FactHints.pending_count() == 0, tostring(FactHints.pending_count()))

  G.GAME.hands["Five of a Kind"].visible = true
  ContextCompact.invalidate_cache()
  build_stable()
  local after = build_force()
  check("a newly revealed hand type re-opens the gate exactly once",
    FactHints.pending_count() == 1, tostring(FactHints.pending_count()))
  local revealed = H.drain_hints()
  check("and the secret hand finally gets its numbers",
    revealed:find("Five of a Kind: 120 chips x 12 mult", 1, true) ~= nil,
    revealed .. " | ctx=" .. after)
  ContextCompact.invalidate_cache()
  build_stable(); build_force()
  check("the very next rebuild queues nothing again",
    FactHints.pending_count() == 0, tostring(FactHints.pending_count()))
end

do
  local FactHints = require("facts.fact_hints")
  local ContextCompact = require("context.context_compact")
  require("core.context_delivery").reset_transport()
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4, MENU = 11 }

  _G.G = {
    STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
    GAME = {
      dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {}, pack_choices = 2,
      hands = {
        Pair  = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 },
        Flush = { visible = true, level = 1, chips = 35, mult = 4, s_chips = 35, s_mult = 4, l_chips = 0, l_mult = 0, played = 0 },
        ["Five of a Kind"] = { visible = false, level = 1, chips = 120, mult = 12, s_chips = 120, s_mult = 12, l_chips = 0, l_mult = 0, played = 0 },
      },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" } },
    jokers = { cards = { { cost = 4, sell_cost = 2,
      ability = { set = "Joker", name = "Joker", mult = 4 },
      config = { center = { key = "j_joker", name = "Joker", set = "Joker",
        loc_txt = { name = "Joker", description = "+4 Mult" } } } } }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} },
    blind_select = {},
    E_MANAGER = { queues = {} },
  }

  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local wire = {}   -- everything the bridge was handed, in order

  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, session_once_serials = {},
    decision_serial = 1, state_enter_serial = 1, reserved_dollars = 0,
    update = function() end,
    send_action_result = function() end,
  }
  function G.NEURO:send_context(msg, _silent) wire[#wire + 1] = tostring(msg) return true end
  function G.NEURO:register_actions() end
  function G.NEURO:unregister_actions() end
  function G.NEURO:force_actions(ctx, query)
    wire[#wire + 1] = tostring(ctx)
    wire[#wire + 1] = tostring(query)
  end

  require("core.transition_guard").reset()
  FactHints.reset_pending()
  ContextCompact.invalidate_cache()
  local Orchestrator = require("core.orchestrator")
  Orchestrator.reset_run_state()

  local forced = false
  local function ticks(n)
    for _ = 1, n do
      G.TIMERS.REAL = G.TIMERS.REAL + 0.1
      pcall(Orchestrator.update, 0.1)
      if require("core.force_state").window_is_open() then forced = true end
    end
  end
  ticks(200)   -- 20 s of ticks

  local transmitted = table.concat(wire, "\n")
  check("the SHOP force actually shipped (the run is meaningful)",
    forced and #wire > 0, "forced=" .. tostring(forced) .. " msgs=" .. #wire)
  check("the model still gets the compact #185 headline",
    transmitted:find("Hand levels: all level 1.", 1, true) ~= nil, transmitted)
  check("base values REACH the model through the real orchestrator",
    transmitted:find("Flush: 35 chips", 1, true) ~= nil
      and transmitted:find("Pair: 10 chips x 2 mult", 1, true) ~= nil,
    transmitted)
  check("they arrive once over 20 s of ticks, not once per rebuild (#185)",
    count_sub(transmitted, BASE_MARK) == 1, tostring(count_sub(transmitted, BASE_MARK)))
  check("the hand still secret at that point is not quoted",
    not transmitted:find("Five of a Kind", 1, true), transmitted)

  local mark = #wire
  G.GAME.hands["Five of a Kind"].visible = true
  require("core.force_state").clear_force_state()
  require("core.neuro_lifecycle").mark_force_dirty()
  G.NEURO.stable_refresh_due = true
  ticks(200)
  local after = table.concat(wire, "\n", math.min(mark + 1, #wire), #wire)
  check("a newly discovered hand type REACHES the model with its numbers",
    after:find("Five of a Kind: 120 chips x 12 mult", 1, true) ~= nil, after)
  check("it re-opens the gate exactly once, not once per rebuild",
    count_sub(after, BASE_MARK) == 1, tostring(count_sub(after, BASE_MARK)))

  require("core.force_state").clear_force_state()
  Orchestrator.reset_run_state()
end

do
  local TokenLegends = require("facts.token_legends")
  local Once = require("util.once")
  local FactHints = require("facts.fact_hints")
  local Actions = require("core.actions")

  local function emit_state_glossary_like_orchestrator(state_name)
    local epoch = "session"
    local sent = {}
    local function send_glossary(key, text)
      if not Once.peek(key, epoch) then return end
      sent[#sent + 1] = text
      Once.book(key, epoch)
    end
    send_glossary("gloss:readable_common", TokenLegends.READABLE_COMMON)
    local state_text = TokenLegends.READABLE_STATE[state_name]
    if state_text and state_text ~= "" then
      send_glossary("gloss:readable_state:" .. state_name, state_text)
    end
    return table.concat(sent)
  end

  local VALN = H.VALN
  local RANKS = { "A", "K", "Q", "J", "9", "8", "7", "6" }
  local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
  local cards = {}
  for i = 1, 8 do
    local suit = SUITS[((i - 1) % 4) + 1]
    cards[i] = {
      base = { value = VALN[RANKS[i]] or RANKS[i], suit = suit },
      sort_id = i,
      config = { center = { key = "c_base", set = "Default" } },
      is_suit = function(_, s) return s == suit end,
    }
  end
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = 5 }, highlighted = {} },
    GAME = {
      blind = { name = "Small Blind", debuff = {}, hands = {}, only_hand = false },
      hands = {}, probabilities = { normal = 1 }, starting_params = {},
      current_round = { hands_left = 3, discards_left = 2, most_played_poker_hand = "High Card" },
      dollars = 4,
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = {},
    jokers = { cards = {} }, consumeables = { cards = {} },
    playing_cards = cards, deck = { cards = {} }, play = nil,
  }
  local real_is_action_valid = Actions.is_action_valid
  Actions.is_action_valid = function(name)
    if name == "play_hand" or name == "discard_hand" then return real_is_action_valid(name) end
    return false
  end
  FactHints.reset_pending()

  local glossary_text = emit_state_glossary_like_orchestrator("SELECTING_HAND")
  local FSH = require("force.force_selecting_hand")
  local force = FSH.build()
  local query_text = (force and force.query) or ""
  local flushed = H.drain_hints()
  local transmitted = glossary_text .. query_text .. flushed

  check("force build actually ran (fixture is legal)", type(force) == "table", tostring(force))
  check("the rank-chip sentence reaches the model exactly once, not twice in a row",
    count_sub(transmitted, "Card rank chips") == 1, transmitted)
  check("force_selecting_hand.lua no longer emits its own copy",
    not query_text:find("Card rank chips", 1, true) and not flushed:find("Card rank chips", 1, true),
    "query=" .. query_text .. " | flushed=" .. flushed)
  check("facts/token_legends.lua stays the sole canonical source",
    TokenLegends.READABLE_STATE.SELECTING_HAND:find("Card rank chips", 1, true) ~= nil)
  Actions.is_action_valid = real_is_action_valid
end

do
  local Once = require("util.once")
  _G.G = { NEURO = {} }

  check("a 'session' epoch booking is recorded", Once.once_until("k_session", "session") == true)
  check("repeat booking at the same epoch is suppressed", Once.once_until("k_session", "session") == false)

  G.NEURO.once_serials = nil
  check("'session' epoch booking SURVIVES a run reset (once_serials wiped)",
    Once.peek("k_session", "session") == false,
    "expected already-seen (peek=false) right after a run reset")

  check("a default-epoch booking is recorded", Once.once_until("k_run", 1) == true)
  G.NEURO.once_serials = nil -- run reset again
  check("a default-epoch booking is GONE after a run reset (once_serials wiped)",
    Once.peek("k_run", 1) == true,
    "expected fresh again (peek=true) after a run reset")
end

do
  local FactHints = require("facts.fact_hints")
  _G.G = { NEURO = {} }

  local function fire(tag, txt)
    FactHints.once_per_session_hint(tag, txt)
    return H.drain_hints()
  end

  check("once_per_session_hint fires on first sight", fire("t214", "TXT") == "TXT")
  check("once_per_session_hint is suppressed on repeat (same run)", fire("t214", "TXT") == "")

  G.NEURO.once_serials = nil
  check("once_per_session_hint STAYS suppressed across a run reset",
    fire("t214", "TXT") == "")
end

do
  local FS = require("core.force_state")
  local Once = require("util.once")
  _G.G = { NEURO = { once_serials = {}, session_once_serials = {} } }

  local snap = FS.snapshot_once_serials()
  check("a snapshot is produced", snap ~= nil)

  Once.once_until("k_run", 1)
  Once.once_until("k_sess", "session")
  check("the discarded build did book the run-scoped gate", Once.peek("k_run", 1) == false)
  check("the discarded build did book the session gate", Once.peek("k_sess", "session") == false)

  FS.restore_once_serials(snap)
  check("the rollback rewinds the run-scoped store",
    Once.peek("k_run", 1) == true)
  check("the rollback rewinds the session store too",
    Once.peek("k_sess", "session") == true,
    "session booking survived the rollback -- a once-per-session line would be charged, never sent")

  _G.G = { NEURO = { once_serials = {}, session_once_serials = {} } }
  Once.once_until("k_old", "session")
  local snap2 = FS.snapshot_once_serials()
  Once.once_until("k_new", "session")
  FS.restore_once_serials(snap2)
  check("an already-delivered session booking survives the rollback",
    Once.peek("k_old", "session") == false)
  check("only the discarded build's session booking is rewound",
    Once.peek("k_new", "session") == true)
end

do
  local ContextCompact = require("context.context_compact")
  local FactHints = require("facts.fact_hints")
  require("core.context_delivery").reset_transport()

  local function joker(key, name, ability, desc)
    ability = ability or {}
    ability.name = name
    ability.set = "Joker"
    return { sort_id = key, ability = ability, sell_cost = 3, cost = 4,
      config = { center = { key = key, set = "Joker", name = name,
        loc_txt = { name = name, description = { desc or "" } } } } }
  end
  local function RAMEN() return joker("j_ramen", "Ramen", { x_mult = 1.84 }, "loses X0.01 Mult per card discarded") end
  local function POPCORN() return joker("j_popcorn", "Popcorn", { mult = 16 }, "loses 4 mult per round") end
  local function SLY() return joker("j_sly", "Sly Joker", { t_chips = 50 }, "+50 Chips if played hand contains a Pair") end

  _G.G = {
    STATE = 5, STATES = { SHOP = 5, SELECTING_HAND = 2 }, STATE_COMPLETE = true,
    TIMERS = { REAL = 100 }, FUNCS = {},
    NEURO = { enabled = true, run_generation = 1, jokers_sold_run = 0,
      once_serials = {}, session_once_serials = {} },
    GAME = { round = 1, consumeable_usage_total = { tarot = 9 }, hands = {},
      dollars = 10, chips = 0, modifiers = {}, used_vouchers = {},
      current_round = {}, round_resets = { ante = 1 }, probabilities = { normal = 1 } },
    jokers = { cards = { RAMEN(), POPCORN(), SLY() }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
  }

  local function frame()
    ContextCompact.invalidate_cache()
    FactHints.reset_pending()
    local rules = ContextCompact.build("SHOP", nil,
      { split = "rule", no_cache = true }) or ""
    ContextCompact.invalidate_cache()
    local state = ContextCompact.build("SHOP", { "buy_from_shop" },
      { split = "state", no_cache = true, force_phase = true }) or ""
    local retained = H.drain_hints()
    return state:find("Joker order:", 1, true) ~= nil,
      (rules .. retained):find("Joker order:", 1, true) ~= nil
  end

  local function store_size(store)
    local n = 0
    for _ in pairs(store or {}) do n = n + 1 end
    return n
  end
  local function order_keys(store)
    local hits = {}
    for k in pairs(store or {}) do
      if tostring(k):find("joker_order_gap", 1, true) then hits[#hits + 1] = k end
    end
    return hits
  end

  local on_force, retained = frame()
  check("the order fact reaches the model on the force payload", on_force == true)
  check("R1b: and never on the retained channel, which could not take it back", retained == false)
  local again, again_retained = frame()
  check("it is restated for as long as the arrangement stays broken",
    again == true and again_retained == false)

  local session_before = store_size(G.NEURO.session_once_serials)
  local run_before = store_size(G.NEURO.once_serials)
  check("it books no gate in the run store -- an ungated fact has no key to accumulate",
    #order_keys(G.NEURO.once_serials) == 0, table.concat(order_keys(G.NEURO.once_serials), ","))
  check("and nothing was parked in the session store",
    #order_keys(G.NEURO.session_once_serials) == 0,
    table.concat(order_keys(G.NEURO.session_once_serials), ","))

  local missed = {}
  for round = 2, 30 do
    G.GAME.round = round
    if not frame() then missed[#missed + 1] = round end
  end
  check("every round of the run states it, not just the round it first appeared in",
    #missed == 0, "missed rounds: " .. table.concat(missed, ","))
  check("thirty rounds of the same board add nothing to the session store",
    store_size(G.NEURO.session_once_serials) == session_before,
    store_size(G.NEURO.session_once_serials) .. " vs " .. session_before)
  check("R6b: nor to the run store",
    store_size(G.NEURO.once_serials) == run_before,
    store_size(G.NEURO.once_serials) .. " vs " .. run_before)

  require("core.lifecycle_registry").reset("run", G.NEURO, {})
  G.NEURO.run_generation = 2
  check("a run reset empties the run store",
    store_size(G.NEURO.once_serials) == 0, tostring(store_size(G.NEURO.once_serials)))
  G.GAME.round = 7
  check("round 7 of run 2 states it too", frame() == true)

  G.jokers.cards = { POPCORN(), SLY(), RAMEN() }
  local fixed = frame()
  check("fixing the arrangement retracts the fact by not restating it", fixed == false)
end

do
  local Once = require("util.once")
  local Orchestrator = require("core.orchestrator")
  local ContextCompact = require("context.context_compact")
  require("core.context_delivery").reset_transport()
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4, MENU = 11 }
  local wire = {}

  local function shop_joker(key, name, edition)
    return { sort_id = key, cost = 5, sell_cost = 2, debuff = false, edition = edition,
      ability = { set = "Joker", name = name, mult = 4 },
      config = { center = { key = key, name = name, set = "Joker", rarity = 1,
        loc_txt = { name = name, description = "+4 Mult" } } } }
  end
  local function shop_voucher(key, name)
    return { sort_id = key, cost = 10, sell_cost = 0,
      ability = { set = "Voucher", name = name },
      config = { center = { key = key, name = name, set = "Voucher",
        loc_txt = { name = name, description = "voucher" } } } }
  end

  local N = { enabled = true, persona = "neuro", llm_paused = false, reserved_dollars = 0,
    once_serials = {}, session_once_serials = {}, run_generation = 1 }
  function N:send_context(msg) wire[#wire + 1] = tostring(msg); return true end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:send_action_result() end
  function N:update() end
  function N:is_transport_saturated() return false end

  _G.G = {
    STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 }, CONTROLLER = { locks = {} },
    GAME = {
      dollars = 20, round = 3, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 2 }, blind = { name = "Small Blind" },
      used_vouchers = {}, modifiers = {}, pack_choices = 2,
      hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 } },
      consumeable_usage_total = { tarot = 0 }, probabilities = { normal = 1 },
    },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
    shop_jokers = { cards = { shop_joker("j_a", "Baron", { polychrome = true }) },
      config = { card_limit = 2 } },
    shop_vouchers = { cards = { shop_voucher("v_hone", "Hone") }, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end },
    blind_select = {}, NEURO = N,
  }
  ContextCompact.invalidate_cache()

  local function tick(seconds)
    for _ = 1, math.floor(seconds / 0.1) do
      G.TIMERS.REAL = G.TIMERS.REAL + 0.1
      pcall(Orchestrator.update, 0.1)
    end
  end
  local function on_wire(sub)
    for _, m in ipairs(wire) do if m:find(sub, 1, true) then return true end end
    return false
  end
  local function count_on_wire(sub)
    local n = 0
    for _, m in ipairs(wire) do if m:find(sub, 1, true) then n = n + 1 end end
    return n
  end

  tick(3.0)

  check("the primer reached the model even though every force was discarded",
    on_wire("A voucher is a permanent"), "voucher basics never left the retention channel")
  check("the glossary DID go out in that same frame (the frame really ran)",
    on_wire("How to decide:"), "no glossary -- the fixture never armed a force")
  check("and exactly once across all those frames, with the gate booked after delivery",
    count_on_wire("A voucher is a permanent") == 1
      and Once.peek("shint:voucher_basics_run", "session") == false,
    count_on_wire("A voucher is a permanent") .. " sends")
  check("the shop-edition fact never reaches the retained channel",
    count_on_wire("Shop editions:") == 0, count_on_wire("Shop editions:") .. " sends")
  check("R4b: it rides the shop force instead, on every build",
    (function()
      local FS = require("force.force_shop")
      local real = require("core.actions").is_action_valid
      require("core.actions").is_action_valid = function(n)
        return n == "leave_shop" or n == "buy_from_shop"
      end
      local a = ((FS.build() or {}).query or "")
      local b = ((FS.build() or {}).query or "")
      require("core.actions").is_action_valid = real
      return a:find("Baron (Polychrome)", 1, true) ~= nil
        and b:find("Baron (Polychrome)", 1, true) ~= nil, a
    end)())
  check("the ALREADY DELIVERED glossary is committed, out of the journal's reach",
    not pcall(require("core.context_delivery").rule, "gloss:readable_common", "DIFFERENT TEXT"),
    "the glossary was never committed, so a rollback could re-send it")

  local glossary_sends = count_on_wire("How to decide:")
  N.force_actions = function(_, ctx, query)
    wire[#wire + 1] = "FORCE:" .. tostring(ctx or "") .. " " .. tostring(query or "")
  end
  tick(3.0)
  check("a force that DOES go out does not re-send the primer",
    count_on_wire("A voucher is a permanent") == 1,
    count_on_wire("A voucher is a permanent") .. " sends")
  check("nor the shop-edition text",
    count_on_wire("Shop editions:") == 1, count_on_wire("Shop editions:") .. " sends")
  check("the glossary was not re-sent by the rollback",
    count_on_wire("How to decide:") == glossary_sends,
    count_on_wire("How to decide:") .. " sends, expected " .. glossary_sends)

  Once.begin_journal()
  check("a first build can reserve a gate", Once.once_until("orphaned-build", "run") == true)
  Once.begin_journal()
  check("beginning the next build rolls back an exception-orphaned journal",
    Once.once_until("orphaned-build", "run") == true)
  Once.rollback_journal()

  local function wire_line(sub)
    for _, m in ipairs(wire) do if m:find(sub, 1, true) then return m end end
    return nil
  end
  local SCORE_ORDER = "before any joker's flat +Mult"
  check("SO R1: the invariant frame carries the full score order",
    on_wire(SCORE_ORDER), "the score-order rule never reached the model")
  check("SO R2: it rides the RULES frame, not a force query",
    (wire_line(SCORE_ORDER) or ""):find("RULES. Score = Chips x Mult", 1, true) ~= nil,
    tostring(wire_line(SCORE_ORDER)))
  check("SO R3: and is sent once across every frame, not per decision",
    count_on_wire(SCORE_ORDER) == 1, count_on_wire(SCORE_ORDER) .. " sends")
end

do
  local ContextCompact = require("context.context_compact")
  local ContextReadable = require("context.context_readable")
  local CtxHand = require("context.ctx_hand")
  require("core.context_delivery").reset_transport()
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, TAROT_PACK = 6,
    STANDARD_PACK = 7, GAME_OVER = 4, MENU = 11 }
  local wire = {}

  local function plain_card(i)
    return { sort_id = i, base = { value = "10", suit = "Hearts", nominal = 10 },
      ability = { set = "Default", name = "10 of Hearts" },
      config = { center = { key = "c_base", set = "Default" } } }
  end
  local deck = {}
  for i = 1, 8 do deck[i] = plain_card(i) end

  local N = { enabled = true, persona = "neuro", llm_paused = false, reserved_dollars = 0,
    once_serials = {}, session_once_serials = {}, run_generation = 1 }
  function N:send_context(msg) wire[#wire + 1] = tostring(msg); return true end
  function N:register_actions() end
  function N:unregister_actions() end
  function N:send_action_result() end
  function N:update() end
  function N:is_transport_saturated() return false end

  _G.G = {
    STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 5000 }, SETTINGS = { GAMESPEED = 1 }, CONTROLLER = { locks = {} },
    GAME = {
      dollars = 20, round = 3, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 2 }, blind = { name = "Small Blind" },
      used_vouchers = {}, modifiers = {}, pack_choices = 2,
      hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, s_chips = 10, s_mult = 2, l_chips = 0, l_mult = 0, played = 0 } },
      consumeable_usage_total = { tarot = 0 }, probabilities = { normal = 1 },
    },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = deck }, playing_cards = deck,
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end },
    blind_select = {}, NEURO = N,
  }
  ContextCompact.invalidate_cache()

  local function count_on_wire(sub)
    local n = 0
    for _, m in ipairs(wire) do if m:find(sub, 1, true) then n = n + 1 end end
    return n
  end
  local MARK = "Card modifiers ("

  local function payload(state_name, actions)
    ContextCompact.invalidate_cache()
    return ContextReadable.build(state_name, actions)
      or ContextCompact.build(state_name, actions, { split = "state", no_cache = true }) or ""
  end
  local function rules_split(state_name)
    ContextCompact.invalidate_cache()
    return ContextCompact.build(state_name, nil, { split = "rule", no_cache = true }) or ""
  end

  check("CM R1: an unmodified starting deck states an explicit 'none'",
    (CtxHand.deck_modifiers_section() or ""):find("none", 1, true) ~= nil,
    tostring(CtxHand.deck_modifiers_section()))
  check("CM R2: and nothing about card modifiers reached the retained channel",
    count_on_wire(MARK) == 0, count_on_wire(MARK) .. " sends")

  deck[1].ability.enhancement = "m_steel"
  check("CM R3: the tally now renders, scoped to the full deck",
    (CtxHand.deck_modifiers_section() or ""):find("enhancements Steel x1", 1, true) ~= nil,
    tostring(CtxHand.deck_modifiers_section()))

  local before_steel = payload("SHOP", { "buy_from_shop" })
  deck[2].ability.enhancement = "m_glass"
  local after_glass = payload("SHOP", { "buy_from_shop" })
  check("CM R4: the decision payload follows the deck -- a second enhancement reaches the model",
    after_glass:find("Glass", 1, true) ~= nil and before_steel:find("Glass", 1, true) == nil,
    after_glass)
  check("CM R4b: and the tally is on every decision, not only the one that changed it",
    payload("SHOP", { "buy_from_shop" }):find(MARK, 1, true) ~= nil
      and after_glass:find(MARK, 1, true) ~= nil, after_glass)
  check("CM R5: and still none of it reached the retained channel",
    count_on_wire(MARK) == 0, count_on_wire(MARK) .. " sends")

  for _, st in ipairs({ "SELECTING_HAND", "SHOP", "BLIND_SELECT", "TAROT_PACK", "STANDARD_PACK" }) do
    local state_text = payload(st, nil)
    check("CM R6 " .. st .. ": the decision payload carries the tally",
      tostring(state_text):find(MARK, 1, true) ~= nil, tostring(state_text))
    check("CM R6 " .. st .. ": and the retained rules do not",
      rules_split(st):find(MARK, 1, true) == nil, rules_split(st))
  end

  do
    G.GAME.used_vouchers["v_overstock_norm"] = true
    G.jokers.cards[1] = { sort_id = 900, ability = { set = "Joker", name = "Joker", mult = 4 },
      sell_cost = 2, config = { center = { key = "j_joker", set = "Joker" } } }
    local IN_RUN_ELIGIBLE = { "SELECTING_HAND", "SHOP", "BLIND_SELECT",
      "TAROT_PACK", "PLANET_PACK", "SPECTRAL_PACK", "STANDARD_PACK", "BUFFOON_PACK",
      "SMODS_BOOSTER_OPENED" }
    local STABLE_ELIGIBLE = { "MENU", "RUN_SETUP", "SPLASH", "GAME_OVER" }
    for _, st in ipairs(IN_RUN_ELIGIBLE) do STABLE_ELIGIBLE[#STABLE_ELIGIBLE + 1] = st end
    local shape, mismatched = nil, {}
    for _, st in ipairs(STABLE_ELIGIBLE) do
      ContextCompact.invalidate_cache()
      local list = ContextCompact.build(st, nil,
        { split = "rule", no_cache = true, return_list = true }) or {}
      local joined = table.concat(list, "\n")
      if shape == nil then
        shape = joined
      elseif joined ~= shape then
        mismatched[#mismatched + 1] = st
      end
    end
    check("CM R9: every state the permanent-rules gate accepts offers the SAME rule sections",
      #mismatched == 0, table.concat(mismatched, ", ") .. " || first=" .. tostring(shape))

    local MUTABLE = { "RUN|", "Vouchers you own:", "Card modifiers (", "Your jokers (" }
    local leaked = {}
    for _, st in ipairs(STABLE_ELIGIBLE) do
      local rules = rules_split(st)
      for _, prefix in ipairs(MUTABLE) do
        if rules:find(prefix, 1, true) then leaked[#leaked + 1] = st .. " -> " .. prefix end
      end
    end
    check("CM R10: and no mutable section is among them",
      #leaked == 0, table.concat(leaked, "; "))

    local missing = {}
    for _, st in ipairs(IN_RUN_ELIGIBLE) do
      ContextCompact.invalidate_cache()
      local state_text = ContextCompact.build(st, nil, { split = "state", no_cache = true }) or ""
      for _, prefix in ipairs({ "RUN|", "Vouchers you own:", "Card modifiers (" }) do
        if not state_text:find(prefix, 1, true) then
          missing[#missing + 1] = st .. " lacks '" .. prefix .. "'"
        end
      end
    end
    check("CM R11: every one of those states carries the mutable sections on its own payload",
      #missing == 0, table.concat(missing, "; "))
  end
end

done()
