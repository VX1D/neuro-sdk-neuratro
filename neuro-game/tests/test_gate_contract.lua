_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(a)
  if type(a) == "table" and a.type == "raw_descriptions" then return { "All Heart cards are debuffed" } end
  return ""
end

local check, done = require("tests.helpers").harness("gate-contract")
local H = require("tests.helpers")
local C = require("tests.cadence_contract")
local FactHints = require("facts.fact_hints")
local HintRegistry = require("facts.hint_registry")
local Delivery = require("core.context_delivery")
local Actions = require("core.actions")
local Once = require("util.once")

_G.get_blind_amount = function(a) return 300 * a end

local SEEN = {}       -- registry stem -> { inline = n, queued = n }
local BOOKED = {}     -- gate keys booked during this run, parsed
local TEXT = {}       -- tag -> last text handed to FactHints.emit

local function record(stem, field)
  local rec = SEEN[stem] or { inline = 0, queued = 0 }
  rec[field] = rec[field] + 1
  SEEN[stem] = rec
end

do
  local raw_emit = FactHints.emit
  FactHints.emit = function(tag, text)
    TEXT[tostring(tag)] = text
    return raw_emit(tag, text)
  end

  local armed = nil
  local raw_lookup = HintRegistry.lookup
  HintRegistry.lookup = function(tag)
    local entry = raw_lookup(tag)
    armed = nil
    if entry then
      if entry.cadence == "always" then
        record(entry.tag, "inline")
      else
        armed = entry
      end
    end
    return entry
  end

  local function note_key(key, epoch)
    local rec = C.parse_key(key, epoch)
    local N = (G and G.NEURO) or {}
    rec.at_round = G and G.GAME and G.GAME.round
    rec.at_state_entry = tonumber(N.state_enter_serial) or 0
    rec.at_decision = tonumber(N.decision_serial) or 0
    BOOKED[#BOOKED + 1] = rec
  end
  local raw_once_until, raw_peek, raw_book = Once.once_until, Once.peek, Once.book
  Once.once_until = function(key, epoch)
    local granted = raw_once_until(key, epoch)
    local entry = armed; armed = nil
    if granted then note_key(key, epoch) end
    if entry and granted then record(entry.tag, "inline") end
    return granted
  end
  Once.peek = function(key, epoch)
    local open = raw_peek(key, epoch)
    local entry = armed; armed = nil
    if entry and open then record(entry.tag, "queued") end
    return open
  end
  Once.book = function(key, epoch) note_key(key, epoch); armed = nil; return raw_book(key, epoch) end
end

local KIND_FOR_CADENCE = {
  state_entry = "state", decision = "decision", round = "round",
  session = "session", run = "run",
}

local function registered(tag)
  tag = tostring(tag or "")
  return HintRegistry.lookup(tag) or HintRegistry.lookup(tag .. ":")
end

local function gate_fault(rec)
  local entry = registered(rec.tag)
  if not entry then return "unregistered gated fact " .. tostring(rec.key) end
  if entry.cadence == "always" then
    return string.format("%s is cadence 'always' but booked a gate (%s): a gate on the ephemeral"
      .. " channel deletes the fact from every force after the first", entry.tag, rec.key)
  end
  local want = KIND_FOR_CADENCE[entry.cadence]
  if rec.kind ~= want then
    return string.format("%s is cadence %s but booked as %s (%s)",
      entry.tag, entry.cadence, tostring(rec.kind), rec.key)
  end
  if want == "round" then
    if rec.round ~= tostring(rec.at_round) then
      return rec.key .. " does not name round " .. tostring(rec.at_round)
    end
    if rec.epoch ~= "run" then return rec.key .. " is parked outside the run store" end
  elseif want == "run" then
    if rec.epoch ~= "run" then return rec.key .. " is parked outside the run store" end
  elseif want == "session" then
    if rec.epoch ~= "session" then return rec.key .. " is parked outside the session store" end
  elseif want == "state" then
    if rec.epoch ~= rec.at_state_entry then
      return rec.key .. " is not cut from this state entry"
    end
  elseif want == "decision" then
    if rec.epoch ~= rec.at_decision then
      return rec.key .. " is not cut from this decision"
    end
  end
  return nil
end

local FAULTS = {}
local function judge(rec)
  local f = gate_fault(rec)
  if f then FAULTS[#FAULTS + 1] = f end
end

local function fresh(neuro)
  Delivery.reset_transport()
  FactHints.reset_pending()
  return neuro or { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 1, decision_serial = 1 }
end

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

local BLUEPRINT = { config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint" } },
  ability = { name = "Blueprint", set = "Joker", mult = 0 }, sell_cost = 2 }
local PLAIN = { config = { center = { key = "j_joker", set = "Joker", name = "Joker" } },
  ability = { name = "Joker", set = "Joker", mult = 4 }, sell_cost = 2 }
local FAMILY = { config = { center = { key = "j_the_family", set = "Joker", name = "The Family" } },
  ability = { name = "The Family", set = "Joker", x_mult = 3 }, sell_cost = 2 }
local LOVERS = { ability = { name = "The Lovers", set = "Tarot",
    consumeable = { max_highlighted = 1, min_highlighted = 1 } },
  config = { center = { key = "c_lovers", set = "Tarot", name = "The Lovers" } } }
local VOUCHERS = {
  hone      = { cost = 10, ability = { set = "Voucher", name = "Hone" },
                config = { center = { key = "v_hone", name = "Hone", set = "Voucher" } } },
  telescope = { cost = 10, ability = { set = "Voucher", name = "Telescope" },
                config = { center = { key = "v_telescope", name = "Telescope", set = "Voucher" } } },
}
local BOSS = { name = "The Head", key = "bl_head", boss = true, disabled = false,
  debuff = {}, chips = 300, hands = {}, only_hand = false }
local PSYCHIC = { name = "The Psychic", key = "bl_psychic", boss = true, disabled = false,
  debuff = { h_size_ge = 5 }, chips = 300, hands = {}, only_hand = false }

local function merge(a, b)
  local o = {}
  for k, v in pairs(a or {}) do o[k] = v end
  for k, v in pairs(b or {}) do o[k] = v end
  return o
end

local function selecting_board(o)
  o = o or {}
  _G.G = {
    STATE = 2, STATES = { SELECTING_HAND = 2, SHOP = 5 }, P_BLINDS = {},
    GAME = {
      round = o.round or 7, dollars = 8, interest_cap = 25, interest_amount = 1, win_ante = 8,
      used_vouchers = {}, modifiers = {}, probabilities = { normal = 1 }, starting_params = {},
      round_resets = { ante = o.ante or 3, discards = 3, blind_choices = {} },
      current_round = { hands_left = 4, discards_left = o.discards_left or 0,
        discards_used = o.discards_used or 0, free_rerolls = 0, reroll_cost = 5,
        most_played_poker_hand = "High Card" },
      hands = { ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 3 } },
      blind = o.blind or BOSS,
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = o.neuro or fresh(),
    hand = { cards = hand_cards(), config = { highlighted_limit = 5 }, highlighted = {} },
    jokers = { cards = o.jokers or { BLUEPRINT, PLAIN }, config = { card_limit = 5 } },
    consumeables = { cards = o.consumeables or { LOVERS }, config = { card_limit = 2 } },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    playing_cards = {}, deck = { cards = {} }, play = nil,
  }
end

local function shop_joker(edition)
  return { ability = { name = "Baron", set = "Joker", mult = 0 }, cost = 5,
    edition = edition or { polychrome = true },
    config = { center = { key = "j_baron", set = "Joker" } } }
end

local function shop_board(o)
  o = o or {}
  _G.G = {
    STATE = 5, STATES = { SELECTING_HAND = 2, SHOP = 5 },
    P_BLINDS = { bl_head = BOSS },
    GAME = {
      round = o.round or 7, dollars = o.dollars or 8, interest_cap = 25, interest_amount = 1,
      win_ante = 8, used_vouchers = {}, modifiers = {}, probabilities = { normal = 1 },
      starting_params = {},
      round_resets = { ante = o.ante or 3, discards = 3,
        blind_choices = o.boss and { Boss = "bl_head" } or {} },
      current_round = { hands_left = 0, discards_left = 0, discards_used = 3, free_rerolls = 0,
        reroll_cost = 5, most_played_poker_hand = "High Card" },
      hands = {
        Pair  = { visible = true, level = 1, chips = 10, mult = 2, played = 0 },
        Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
      },
      blind = { name = "Small Blind", chips = 300 },
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = o.neuro or fresh(),
    hand = { cards = {}, config = { highlighted_limit = 5 }, highlighted = {} },
    jokers = { cards = o.jokers or { BLUEPRINT, PLAIN }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { shop_joker(o.edition) } },
    shop_vouchers = { cards = { VOUCHERS[o.voucher or "hone"] } },
    shop_booster = { cards = {} },
    playing_cards = {}, deck = { cards = {} }, play = nil,
  }
end

local function frame(build, ...)
  FactHints.reset_pending()
  local res = build(...)
  local query = (type(res) == "table" and res.query) or ""
  return query, H.drain_hints()
end

do
  local real = Actions.is_action_valid
  Actions.is_action_valid = function(n) return n == "select_blind" or n == "skip_blind" end
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = {},
    GAME = { win_ante = 8, dollars = 20, round = 3, blind_on_deck = "Small",
      round_resets = { ante = 2, blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" } } },
    NEURO = fresh(),
    jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local q, retained = frame(require("force.force_blind_select").build)
  check("the skip/play advice rides the blind-select force, where the choice is made",
    q:find("actively weigh skip_blind", 1, true) ~= nil, q)
  check("and never the retained channel -- it is a claim about THIS blind",
    retained:find("actively weigh skip_blind", 1, true) == nil, retained)
  local q2 = frame(require("force.force_blind_select").build)
  check("a second decision on the same screen restates it (nothing was kept from the first)",
    q2:find("actively weigh skip_blind", 1, true) ~= nil, q2)
  Actions.is_action_valid = real
end

do
  local real = Actions.is_action_valid
  Actions.is_action_valid = function(n)
    if n == "play_hand" or n == "discard_hand" then return real(n) end
    return n == "use_consumable" or n == "sell_card" or n == "set_joker_order"
  end
  local FSH = require("force.force_selecting_hand")

  local N = fresh()
  selecting_board({ neuro = N, discards_left = 3, blind = PSYCHIC })
  local q1, retained1 = frame(FSH.build)
  local full = TEXT["sh_rules_core"] or ""
  check("the round opens with the full rules block", full:find("Rules: 1)", 1, true) ~= nil, full)
  check("it rides the force, never the retained channel",
    q1:find("Rules: 1)", 1, true) ~= nil and retained1:find("Rules: 1)", 1, true) == nil,
    retained1)

  local order, clause = C.numbered_points(full)
  check("a round with discards and a boss minimum states five points, numbered without a gap",
    #C.numbering_faults(full) == 0 and #order == 5,
    table.concat(C.numbering_faults(full), " | ") .. " n=" .. tostring(#order))

  local q2 = frame(FSH.build)
  local brief = TEXT["sh_rules_brief"] or ""
  check("the next force of the same round carries the reminder, not the full block",
    brief ~= "" and q2:find("Rules: 1)", 1, true) ~= nil
      and q2:find(full, 1, true) == nil, q2)
  local border, bclause = C.numbered_points(brief)
  check("the reminder states the SAME NUMBER of points -- no rule is dropped from it",
    #border == #order, tostring(#border) .. " vs " .. tostring(#order) .. " || " .. brief)
  check("and it is genuinely shorter, not the same block under another tag",
    #brief < #full, #brief .. " vs " .. #full)
  local hollow = {}
  for i = 1, #order do
    local have, want = C.resources(bclause[i] or ""), C.resources(clause[i] or "")
    local shared = false
    for r in pairs(want) do if have[r] then shared = true end end
    if next(want) ~= nil and not shared then
      hollow[#hollow + 1] = string.format("point %d: '%s' shares no subject with '%s'",
        i, tostring(bclause[i]), tostring(clause[i]))
    end
  end
  check("no point of the reminder is summarised into filler",
    #hollow == 0, table.concat(hollow, " | "))

  local discard_point
  for i = 1, #order do
    if (clause[i] or ""):lower():find("discard", 1, true) then discard_point = i end
  end
  check("B7b the discard rule still names discards in the reminder",
    discard_point ~= nil and (bclause[discard_point] or ""):lower():find("discard", 1, true) ~= nil,
    tostring(discard_point) .. " || " .. tostring(discard_point and bclause[discard_point]))

  local boss_point
  for i = 1, #order do
    if (clause[i] or ""):find("boss", 1, true) or (clause[i] or ""):find("at least", 1, true) then
      boss_point = i
    end
  end
  if boss_point then
    check("the boss minimum is carried into the reminder verbatim",
      (bclause[boss_point] or "") == (clause[boss_point] or ""),
      tostring(clause[boss_point]) .. " || " .. tostring(bclause[boss_point]))
  end

  local N2 = fresh()
  selecting_board({ neuro = N2, discards_left = 0, discards_used = 0, blind = PSYCHIC })
  frame(FSH.build)
  local dry = TEXT["sh_rules_core"] or ""
  local dorder = C.numbered_points(dry)
  check("a round that never had discards states one point fewer, renumbered without a gap",
    #C.numbering_faults(dry) == 0 and #dorder == #order - 1,
    table.concat(C.numbering_faults(dry), " | ") .. " n=" .. tostring(#dorder))
  check("and no correction prose rides any frame -- the retraction IS the renumbering",
    not dry:find("Correction to the rules above", 1, true)
      and not (TEXT["sh_rules_brief"] or ""):find("Correction to the rules above", 1, true), dry)

  G.GAME.current_round.discards_left = 0
  G.GAME.current_round.discards_used = 3
  local N3 = fresh()
  selecting_board({ neuro = N3, discards_left = 3, blind = PSYCHIC })
  frame(FSH.build)
  local before = C.numbered_points(TEXT["sh_rules_core"] or "")
  G.GAME.current_round.discards_left = 0
  G.GAME.current_round.discards_used = 3
  frame(FSH.build)
  local after = C.numbered_points(TEXT["sh_rules_brief"] or "")
  check("spending the last discard drops that point from the rest of the round's forces",
    #after == #before - 1, tostring(#before) .. " -> " .. tostring(#after)
      .. " || " .. tostring(TEXT["sh_rules_brief"]))

  local N4 = fresh()
  selecting_board({ neuro = N4, discards_left = 3 })
  local qc, rc = frame(FSH.build)
  check("the consumable-slot fact and the copy chain ride the force, not the retained channel",
    qc:find("Joker copy order:", 1, true) ~= nil
      and rc:find("Joker copy order:", 1, true) == nil, rc)

  Actions.is_action_valid = real
end

do
  local real = Actions.is_action_valid
  Actions.is_action_valid = function(n)
    return n == "leave_shop" or n == "buy_from_shop" or n == "set_joker_order" or n == "sell_card"
  end
  local FS = require("force.force_shop")

  local N = fresh()
  shop_board({ neuro = N, dollars = 2, boss = true })
  local q, retained = frame(FS.build)
  check("the shop's state claims ride the force",
    q:find("below the first interest step", 1, true) ~= nil
      and q:find("Upcoming Boss", 1, true) ~= nil
      and q:find("Shop editions:", 1, true) ~= nil, q)
  check("the shop's permanent mechanics ride the retained channel instead",
    retained:find("A voucher is a permanent", 1, true) ~= nil
      and retained:find("unlocks", 1, true) ~= nil, retained)
  check("and no state claim leaked onto the retained channel",
    retained:find("Upcoming Boss", 1, true) == nil
      and retained:find("Shop editions:", 1, true) == nil
      and retained:find("below the first interest step", 1, true) == nil, retained)

  local q2, retained2 = frame(FS.build)
  check("the next decision restates every state claim",
    q2:find("below the first interest step", 1, true) ~= nil
      and q2:find("Upcoming Boss", 1, true) ~= nil
      and q2:find("Shop editions:", 1, true) ~= nil, q2)
  check("and does not re-send a permanent mechanic the model already holds",
    retained2:find("A voucher is a permanent", 1, true) == nil, retained2)

  local CASES = {
    { tag = "shop_edition", a = { edition = { polychrome = true } }, b = { edition = { foil = true } },
      mark_a = "Baron (Polychrome)", mark_b = "Baron (Foil)" },
    { tag = "bp_chain", a = { jokers = { BLUEPRINT, PLAIN } }, b = { jokers = { PLAIN, BLUEPRINT } },
      mark_a = "Blueprint (slot 1)", mark_b = "Blueprint (slot 2)" },
  }
  for _, case in ipairs(CASES) do
    local NC = fresh()
    shop_board(merge(case.a, { neuro = NC, round = 7 }))
    local qa = frame(FS.build)
    shop_board(merge(case.b, { neuro = NC, round = 7 }))
    NC.decision_serial = NC.decision_serial + 1
    local qb = frame(FS.build)
    shop_board(merge(case.a, { neuro = NC, round = 8 }))
    NC.decision_serial = NC.decision_serial + 1
    local qc = frame(FS.build)
    check("D " .. case.tag .. " states its content when it first appears",
      qa:find(case.mark_a, 1, true) ~= nil, qa)
    check("D " .. case.tag .. " follows the content when it changes",
      qb:find(case.mark_b, 1, true) ~= nil and qb:find(case.mark_a, 1, true) == nil, qb)
    check("D " .. case.tag .. " restates content the model was shown before -- it kept none of it",
      qc:find(case.mark_a, 1, true) ~= nil, qc)
  end

  local NB = fresh()
  shop_board({ neuro = NB })
  require("context.ctx_hand").levels_section()
  local base = H.drain_hints()
  check("the fixed level-1 base values are taught on the retained channel",
    base:find("Level-1 starting hand values", 1, true) ~= nil
      and base:find("Flush: 35 chips", 1, true) ~= nil, base)

  Actions.is_action_valid = real
end

do
  local real = Actions.is_action_valid
  Actions.is_action_valid = function(n) return n == "set_joker_order" or n == "sell_card" end
  local N = fresh()
  selecting_board({ neuro = N, discards_left = 3, jokers = { FAMILY, PLAIN } })
  local section = require("context.ctx_jokers").jokers_section("SELECTING_HAND") or ""
  local retained = H.drain_hints()
  check("the ordering gap is rendered into the roster section it describes",
    section:find("Joker order:", 1, true) ~= nil, section)
  check("and never onto the retained channel -- selling one joker makes it false",
    retained:find("Joker order:", 1, true) == nil, retained)
  local again = require("context.ctx_jokers").jokers_section("SELECTING_HAND") or ""
  check("it is restated for as long as the arrangement stays broken",
    again:find("Joker order:", 1, true) ~= nil, again)
  Actions.is_action_valid = real
end

do
  local TD = require("tests.test_deadlock")
  local FP = require("force.force_pack")
  local function scenario(state, desc)
    for _, s in ipairs(TD.SCENARIOS) do
      if s.state == state and s.desc == desc then return s end
    end
  end
  local function pack_frame(state, desc, valid)
    local s = assert(scenario(state, desc), "missing fixture " .. state .. "/" .. desc)
    TD.apply_mock(s.mock())
    G.NEURO = fresh(G.NEURO)
    G.NEURO.once_serials = {}
    G.NEURO.session_once_serials = {}
    G.NEURO.state_enter_serial = 1
    G.NEURO.decision_serial = 1
    G.NEURO.state = state
    local real = Actions.is_action_valid
    if valid then Actions.is_action_valid = valid end
    local q, retained = frame(FP.build, state)
    Actions.is_action_valid = real
    return q, retained
  end

  local qc, rc = pack_frame("TAROT_PACK", "Has pack cards")
  check("the consumable-pack rule rides the pack force",
    qc:find("is used the moment you pick it", 1, true) ~= nil, qc)
  check("and not the retained channel -- it is scoped to this pack",
    rc:find("is used the moment you pick it", 1, true) == nil, rc)

  local qs = pack_frame("STANDARD_PACK", "STANDARD_PACK with cards")
  check("the standard-pack rule rides the pack force",
    qs:find("never needs a free slot", 1, true) ~= nil, qs)

  local qb = pack_frame("TAROT_PACK", "Has pack cards", function(n) return n == "skip_pack" end)
  check("a blocked consumable pack says why, on the force",
    qb:find("You can't take a card from this pack right now", 1, true) ~= nil, qb)

  local qj = pack_frame("BUFFOON_PACK", "Full joker slots during buffoon pack",
    function(n) return n == "sell_card" or n == "skip_pack" end)
  check("a full joker board is told the sell-then-take route, on the force",
    qj:find("sell_card one of your jokers first to free a slot", 1, true) ~= nil, qj)
end

do
  local real = Actions.is_action_valid

  Actions.is_action_valid = function(n) return n == "leave_shop" or n == "buy_from_shop" end
  local FS = require("force.force_shop")
  local NJ = fresh()
  shop_board({ neuro = NJ, jokers = {} })
  local qj = frame(FS.build)
  check("an empty roster draws the jokerless priority onto the shop force",
    qj:find("You own NO jokers", 1, true) ~= nil, qj)

  Actions.is_action_valid = function(n) return n == "use_consumable" or n == "play_hand" end
  local FSH2 = require("force.force_selecting_hand")
  local NP = fresh()
  local PLANET = { sort_id = 77, sell_cost = 1, cost = 3,
    ability = { name = "Pluto", set = "Planet", consumeable = { max_highlighted = 0 } },
    config = { center = { key = "c_pluto", set = "Planet", name = "Pluto" } } }
  selecting_board({ neuro = NP, discards_left = 3, consumeables = { PLANET } })
  G.GAME.hands["High Card"].played = 9
  local qp = frame(FSH2.build)
  check("a held Planet draws the level-the-played-type fact onto the hand force",
    qp:find("You hold a Planet", 1, true) ~= nil, qp)

  Actions.is_action_valid = real
end

do
  local TD = require("tests.test_deadlock")
  local FP2 = require("force.force_pack")
  local function scenario2(state, desc)
    for _, s in ipairs(TD.SCENARIOS) do
      if s.state == state and s.desc == desc then return s end
    end
  end
  local function pack_frame2(state, desc, valid, prep)
    local s = assert(scenario2(state, desc), "missing fixture " .. state .. "/" .. desc)
    TD.apply_mock(s.mock())
    G.NEURO = fresh(G.NEURO)
    G.NEURO.once_serials = {}
    G.NEURO.session_once_serials = {}
    G.NEURO.state_enter_serial = 1
    G.NEURO.decision_serial = 1
    G.NEURO.state = state
    if prep then prep() end
    local real = Actions.is_action_valid
    if valid then Actions.is_action_valid = valid end
    local q = frame(FP2.build, state)
    Actions.is_action_valid = real
    return q
  end

  local qpl = pack_frame2("PLANET_PACK", "PLANET_PACK with cards",
    function(n) return n == "choose_pack_card" or n == "skip_pack" end)
  check("a Planet pack states what levelling a hand type does, on the force",
    qpl:find("A Planet permanently levels ONE hand type", 1, true) ~= nil, qpl)

  local qbf = pack_frame2("BUFFOON_PACK", "BUFFOON_PACK variant with pack cards",
    function(n) return n == "choose_pack_card" or n == "skip_pack" end,
    function() G.jokers.cards = {} end)
  check("a joker pack opened with no xMult owned states the scaling gap, on the force",
    qbf:find("None of your jokers multiply your score", 1, true) ~= nil, qbf)
end

do
  check("the registry is internally consistent",
    #HintRegistry.validate() == 0, table.concat(HintRegistry.validate(), " | "))

  for _, rec in ipairs(BOOKED) do judge(rec) end
  check("every gate key any builder cut was cut from the clock its cadence names",
    #FAULTS == 0, table.concat(FAULTS, " | "))

  local wrong = {}
  for stem, rec in pairs(SEEN) do
    local entry = registered(stem)
    local claim = entry and entry.claim
    if claim == "state" and rec.queued > 0 then
      wrong[#wrong + 1] = stem .. " is a state claim but reached the retained channel"
    elseif claim == "rule" and rec.inline > 0 then
      wrong[#wrong + 1] = stem .. " is a rule but was returned inline to an ephemeral force"
    end
  end
  table.sort(wrong)
  check("every sentence travelled the channel its claim requires",
    #wrong == 0, table.concat(wrong, " | "))

  local uncovered = {}
  for _, entry in ipairs(HintRegistry.entries()) do
    if not SEEN[entry.tag] then uncovered[#uncovered + 1] = entry.tag end
  end
  table.sort(uncovered)
  check("every tag the registry declares was produced by a live builder in this run",
    #uncovered == 0, table.concat(uncovered, ","))
end

done()
