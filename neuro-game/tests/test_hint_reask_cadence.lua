_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("hint-reask-cadence")
local Registry = require("facts.hint_registry")
local FactHints = require("facts.fact_hints")

check("the shipped registry validates clean", #Registry.validate() == 0,
  table.concat(Registry.validate(), " | "))

do
  local REFUSED = {
    { tag = "x_query_decision", claim = "state", cadence = "decision" },
    { tag = "x_query_state_entry", claim = "state", cadence = "state_entry" },
  }
  local missed = {}
  for _, bad in ipairs(REFUSED) do
    local entries = Registry.entries()
    entries[#entries + 1] = bad
    local faults = Registry.validate()
    entries[#entries] = nil
    if #faults == 0 then missed[#missed + 1] = bad.cadence end
  end
  check("validate refuses a query-channel hint gated per decision or per state entry",
    #missed == 0, table.concat(missed, ", "))
end

do
  local ACCEPTED = {
    { tag = "x_query_always", claim = "state", cadence = "always" },
    { tag = "x_query_round", claim = "state", cadence = "round" },
    { tag = "x_ctx_session", claim = "rule", cadence = "session" },
  }
  local wrongly_refused = {}
  for _, good in ipairs(ACCEPTED) do
    local entries = Registry.entries()
    entries[#entries + 1] = good
    if #Registry.validate() > 0 then wrongly_refused[#wrongly_refused + 1] = good.tag end
    entries[#entries] = nil
  end
  check("the cadences a re-ask can carry are still accepted",
    #wrongly_refused == 0, table.concat(wrongly_refused, ", "))
end

do
  _G.G = { NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 7, decision_serial = 3 }, GAME = { round = 2 } }
  FactHints.reset_pending()
  local Once = require("util.once")
  local first = Once.once_until("dhint:x_query_decision", G.NEURO.decision_serial) and "TEXT " or ""
  local reask = Once.once_until("dhint:x_query_decision", G.NEURO.decision_serial) and "TEXT " or ""
  check("C3a a decision-gated query hint is shown once and missing from the re-ask",
    first == "TEXT " and reask == "", string.format("%q / %q", first, reask))

  local s1 = Once.once_until("hint:x_query_state_entry", G.NEURO.state_enter_serial) and "TEXT " or ""
  local s2 = Once.once_until("hint:x_query_state_entry", G.NEURO.state_enter_serial) and "TEXT " or ""
  check("C3b and the same holds for a state-entry gate", s1 == "TEXT " and s2 == "",
    string.format("%q / %q", s1, s2))

  local a = FactHints.emit("pack_cons", "TEXT ")
  local b = FactHints.emit("pack_cons", "TEXT ")
  check("C3c the always cadence the registry does allow survives the re-ask",
    a == "TEXT " and b == "TEXT ", string.format("%q / %q", a, b))
end

do
  local function fresh()
    _G.G = { NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
      state_enter_serial = 11, decision_serial = 4 }, GAME = { round = 3 } }
    FactHints.reset_pending()
  end
  local lost, wrongly_kept = {}, {}
  for _, e in ipairs(Registry.entries()) do
    if e.claim == "state" then
      local tag = e.prefix and (e.tag .. "probe") or e.tag
      fresh()
      local first = FactHints.emit(tag, "PROBE ")
      local again = FactHints.emit(tag, "PROBE ")
      if e.cadence == "always" then
        if not (first == "PROBE " and again == "PROBE ") then
          lost[#lost + 1] = string.format("%s (%s): %q then %q", tag, e.cadence, first, again)
        end
      else
        if not (first == "PROBE " and again == "") then
          wrongly_kept[#wrongly_kept + 1] = string.format("%s (%s): %q then %q", tag, e.cadence, first, again)
        end
      end
    end
  end
  check("R1a every always-cadence state claim survives a re-ask at the same serials",
    #lost == 0, table.concat(lost, " | "))
  check("R1b and a scoped one is still spent exactly once, as its cadence says",
    #wrongly_kept == 0, table.concat(wrongly_kept, " | "))
end

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local TD = require("tests.test_deadlock")

  local STATE_IDS = {}
  do
    local n = 0
    for _, sc in ipairs(TD.SCENARIOS) do
      if not STATE_IDS[sc.state] then n = n + 1; STATE_IDS[sc.state] = n end
    end
  end

  local REAL_EMIT = FactHints.emit
  local capture = nil
  FactHints.emit = function(tag, text)
    local out = REAL_EMIT(tag, text)
    if capture then
      local entry = Registry.lookup(tag)
      local key = (entry and entry.tag) or tostring(tag)
      local rec = capture[key]
      if not rec then rec = { tag = key, entry = entry }; capture[key] = rec end
      if type(out) == "string" and out ~= "" then rec.text = out end
    end
    return out
  end

  local ORIG_VALID = Actions.is_action_valid

  local function build_twice(board)
    _G.G = { NEURO = { dispatcher = Dispatcher, actions = Actions }, FUNCS = {},
      GAME = { current_round = {} } }
    local mock = board.sc.mock()
    if board.tweak then board.tweak(mock) end
    TD.apply_mock(mock)
    G.STATES = G.STATES or {}
    for name, id in pairs(STATE_IDS) do G.STATES[name] = id end
    G.STATE = STATE_IDS[board.sc.state]
    G.NEURO.state = board.sc.state
    G.NEURO.state_enter_serial = 1
    G.NEURO.decision_serial = 0
    G.NEURO.once_serials = {}
    G.NEURO.session_once_serials = {}
    if board.block then
      Actions.is_action_valid = function(name, ...)
        if board.block[name] then return false end
        return ORIG_VALID(name, ...)
      end
    end
    local function one()
      capture = {}
      local ok, force = pcall(Dispatcher.get_force_for_state, board.sc.state)
      local q = (ok and type(force) == "table" and type(force.query) == "string") and force.query or nil
      local seen = capture
      capture = nil
      return q, seen
    end
    local q1, c1 = one()
    local q2, c2 = one()
    Actions.is_action_valid = ORIG_VALID
    return q1, c1, q2, c2
  end

  local function scenario(state, desc)
    for _, sc in ipairs(TD.SCENARIOS) do
      if sc.state == state and sc.desc == desc then return sc end
    end
    error("test_hint_reask_cadence: fixture not found -- " .. state .. " / " .. desc)
  end

  local BOARDS = {}
  for _, sc in ipairs(TD.SCENARIOS) do BOARDS[#BOARDS + 1] = { sc = sc } end
  local NO_PICK = { choose_pack_card = true, choose_directional_pack_card = true }
  BOARDS[#BOARDS + 1] = { sc = scenario("TAROT_PACK", "Full consumable slots during pack"), block = NO_PICK }
  BOARDS[#BOARDS + 1] = { sc = scenario("BUFFOON_PACK", "Full joker slots during buffoon pack"), block = NO_PICK }
  BOARDS[#BOARDS + 1] = { sc = scenario("BLIND_SELECT", "Small blind selectable"), tweak = function(mock)
    mock.GAME.round_resets.blind_tags = { Small = "tag_uncommon", Big = "tag_rare" }
    mock.FUNCS = mock.FUNCS or {}
    mock.FUNCS.skip_blind = function() end
  end }

  BOARDS[#BOARDS + 1] = { sc = scenario("SELECTING_HAND", "Has usable consumable"),
    tweak = function(mock)
      mock.consumeables = mock.consumeables or { cards = {} }
      mock.consumeables.cards = { { sort_id = 4242, sell_cost = 1, cost = 3,
        ability = { name = "Pluto", set = "Planet", consumeable = { max_highlighted = 0 } },
        config = { center = { key = "c_pluto", set = "Planet", name = "Pluto" } } } }
      mock.GAME.current_round = mock.GAME.current_round or {}
      mock.GAME.current_round.most_played_poker_hand = "High Card"
      mock.GAME.hands = { ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 9 } }
    end }
  BOARDS[#BOARDS + 1] = { sc = scenario("SHOP", "Normal: affordable joker, affordable booster, $10"),
    tweak = function(mock)
      mock.GAME.round_resets.ante = 3
      mock.GAME.hands = {
        Pair  = { visible = true, level = 1, chips = 10, mult = 2, played = 4 },
        Flush = { visible = true, level = 1, chips = 35, mult = 4, played = 0 },
      }
    end }

  local dropped, unstated, covered, boards_built = {}, {}, {}, 0
  for _, board in ipairs(BOARDS) do
    local ok, q1, c1, q2, c2 = pcall(build_twice, board)
    if ok and q1 and q2 then
      boards_built = boards_built + 1
      local where = board.sc.state .. "/" .. board.sc.desc
      for tag, rec in pairs(c1) do
        local e = rec.entry
        if rec.text and e and e.claim == "state" and e.cadence == "always" then
          covered[tag] = true
          if q1:find(rec.text, 1, true) == nil then
            unstated[#unstated + 1] = where .. ": " .. tag .. " (first ask)"
          elseif not (c2[tag] and c2[tag].text) then
            dropped[#dropped + 1] = where .. ": " .. tag
          elseif q2:find(c2[tag].text, 1, true) == nil then
            unstated[#unstated + 1] = where .. ": " .. tag .. " (re-ask)"
          end
        end
      end
      for tag, rec in pairs(c2) do
        local e = rec.entry
        if rec.text and e and e.claim == "state" and e.cadence == "always" and not c1[tag] then
          covered[tag] = true
          if q2:find(rec.text, 1, true) == nil then
            unstated[#unstated + 1] = where .. ": " .. tag .. " (re-ask only)"
          end
        end
      end
    end
  end
  FactHints.emit = REAL_EMIT

  check("R2a the sweep really rebuilt forces", boards_built >= 60, tostring(boards_built))
  check("R2b no always-cadence state claim disappears from the re-ask of its own window",
    #dropped == 0, table.concat(dropped, " | "))
  check("R2c and the claim is in the query text both times, not merely returned",
    #unstated == 0, table.concat(unstated, " | "))

  local uncovered = {}
  for _, e in ipairs(Registry.entries()) do
    if e.claim == "state" and e.cadence == "always" and not e.prefix and not covered[e.tag] then
      uncovered[#uncovered + 1] = e.tag
    end
  end
  table.sort(uncovered)
  check("R2d every always-cadence state entry is raised by at least one board in the sweep",
    #uncovered == 0, table.concat(uncovered, ", "))
end

done()
