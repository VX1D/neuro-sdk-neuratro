_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.get_blind_amount = function(a) return 300 * a end

local check, done = require("tests.helpers").harness("round-unit")
local H = require("tests.helpers")
local FactHints = require("facts.fact_hints")
local Actions = require("core.actions")
Actions.is_action_valid = function(n) return n == "select_blind" or n == "skip_blind" end
local FBS = require("force.force_blind_select")

local ADVICE = "actively weigh skip_blind"

local function neuro()
  return { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 1, decision_serial = 1 }
end

local function board(N, w)
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = {},
    GAME = { win_ante = 8, dollars = 20, round = w.round, skips = w.skips,
      blind_on_deck = w.blind, starting_params = {},
      round_resets = { ante = w.ante,
        blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" } } },
    NEURO = N, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  G.GAME.round_resets.blind_states[w.blind] = "Select"
end

local function force(N, w)
  N.state_enter_serial = N.state_enter_serial + 1
  N.decision_serial = N.decision_serial + 1
  board(N, w)
  FactHints.reset_pending()
  local built = FBS.build()
  local query = (type(built) == "table" and built.query) or ""
  return query:find(ADVICE, 1, true) ~= nil
    and H.drain_hints():find(ADVICE, 1, true) == nil
end

local function round_keys(N)
  local out = {}
  for key in pairs(N.once_serials) do
    if key:find("blind_select_advice", 1, true) then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

local SKIPPED = {
  { ante = 1, round = 0, skips = 0, blind = "Small" },
  { ante = 1, round = 1, skips = 0, blind = "Big" },
  { ante = 2, round = 2, skips = 0, blind = "Small" },
  { ante = 2, round = 2, skips = 1, blind = "Big" },
}
local PLAYED = {
  { ante = 1, round = 0, skips = 0, blind = "Small" },
  { ante = 1, round = 1, skips = 0, blind = "Big" },
  { ante = 2, round = 2, skips = 0, blind = "Small" },
  { ante = 2, round = 3, skips = 0, blind = "Big" },
}

local function deliveries(seq)
  local N, got, missed = neuro(), 0, {}
  for _, w in ipairs(seq) do
    if force(N, w) then got = got + 1
    else missed[#missed + 1] = string.format("ante %d %s", w.ante, w.blind) end
  end
  return got, missed, N
end

local played, played_missed = deliveries(PLAYED)
check("every blind the model chooses gets the skip/play advice once", played == #PLAYED,
  tostring(played) .. "/" .. tostring(#PLAYED) .. " missed: " .. table.concat(played_missed, ", "))

local skipped, skipped_missed, Nskip = deliveries(SKIPPED)
check("a skipped blind does not swallow the advice of the blind it advances to",
  skipped == #SKIPPED,
  tostring(skipped) .. "/" .. tostring(#SKIPPED) .. " missed: " .. table.concat(skipped_missed, ", "))

check("always-current advice reserves no retained gate keys",
  #round_keys(Nskip) == 0, table.concat(round_keys(Nskip), " | "))

local N = neuro()
local first = force(N, SKIPPED[1])
local again = force(N, SKIPPED[1])
check("re-forcing the same window remains self-contained", first and again,
  tostring(first) .. "/" .. tostring(again))

done()
