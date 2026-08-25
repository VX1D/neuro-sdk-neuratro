_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("roster-unconditional")

_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }
local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local ContextCompact = require("context.context_compact")
local TD = require("tests.test_deadlock")

G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local ROW = "Your jokers ("
local AGG_LINE = "Joker bonuses ("
local CEILING = "more from jokers gated on something other than the hand type"
local REFUSAL = "no number for "

local IN_RUN_STATES = {
  SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true, ROUND_EVAL = true,
  TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true, STANDARD_PACK = true,
  BUFFOON_PACK = true, SMODS_BOOSTER_OPENED = true,
}

local function jokers(n)
  local defs = { { "j_joker", "Joker", 4 }, { "j_greedy_joker", "Greedy Joker", 3 },
    { "j_jolly", "Jolly Joker", 8 } }
  local t = {}
  for i = 1, n do
    local d = defs[((i - 1) % 3) + 1]
    t[i] = { ability = { name = d[2], set = "Joker", mult = d[3], extra = {} },
      sell_cost = 2, cost = 4, debuff = false,
      config = { center = { key = d[1], set = "Joker", name = d[2] } } }
  end
  return t
end

local RESET = { "hand", "jokers", "consumeables", "deck", "shop_jokers", "shop_vouchers",
  "shop_booster", "pack_cards", "booster_pack", "shop", "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "STATES", "STATE", "P_CENTER_POOLS" }

local STATE_ID, next_state_id = {}, 0
local function enter_state(name)
  if not STATE_ID[name] then next_state_id = next_state_id + 1; STATE_ID[name] = next_state_id end
  G.STATES = G.STATES or {}
  G.STATES[name] = STATE_ID[name]
  G.STATE = STATE_ID[name]
end

local function sweep(njokers)
  local built, states, missing = 0, {}, {}
  local ceiling_in, agg_in = {}, {}
  local rows_seen = 0
  for _, sc in ipairs(TD.SCENARIOS) do
    if IN_RUN_STATES[sc.state] then
      for _, k in ipairs(RESET) do G[k] = nil end
      G.GAME = { current_round = {} }
      G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", run_generation = 1,
        once_serials = {}, session_once_serials = {} }
      local ok = pcall(function()
        TD.apply_mock(sc.mock())
        G.NEURO.persona = "neuro"
        G.NEURO.state_entry_hints = nil
        G.jokers = { cards = jokers(njokers), config = { card_limit = 5 } }
        enter_state(sc.state)
        local force = Dispatcher.get_force_for_state(sc.state)
        if not force then return end
        built = built + 1
        states[sc.state] = (states[sc.state] or 0) + 1
        ContextCompact.invalidate_cache()
        local ctx = ContextCompact.build(sc.state, force.actions,
          { no_cache = true, split = "volatile" }) or ""
        if not ctx:find(ROW, 1, true) then
          missing[#missing + 1] = string.format("%s (%s) actions=[%s]",
            sc.state, sc.desc, table.concat(force.actions or {}, ","))
        end
        if ctx:find(CEILING, 1, true) or ctx:find(REFUSAL, 1, true) then
          ceiling_in[sc.state] = (ceiling_in[sc.state] or 0) + 1
        end
        if ctx:find(AGG_LINE, 1, true) then
          agg_in[sc.state] = (agg_in[sc.state] or 0) + 1
        end
        if not ctx:find("sold this run): none.", 1, true) then rows_seen = rows_seen + 1 end
      end)
      if not ok then
        missing[#missing + 1] = sc.state .. " (" .. sc.desc .. ") ERRORED"
      end
    end
  end
  return built, states, missing, ceiling_in, agg_in, rows_seen
end

local owned_built, owned_states, owned_missing, owned_ceiling, owned_agg = sweep(3)
local bare_built, _, bare_missing, _, bare_agg_in, bare_rows = sweep(0)
local bare_agg = 0
for _, n in pairs(bare_agg_in) do bare_agg = bare_agg + n end

local covered = {}
for s in pairs(owned_states) do covered[#covered + 1] = s end
table.sort(covered)

check("the sweep actually built forces while jokers were owned",
  owned_built >= 20, "forces built: " .. owned_built)
check("the sweep reaches every in-run force state, not just the easy ones",
  owned_states.SELECTING_HAND and owned_states.SHOP and owned_states.BLIND_SELECT
    and owned_states.ROUND_EVAL and (owned_states.BUFFOON_PACK or owned_states.TAROT_PACK),
  "covered: " .. table.concat(covered, ","))
check("with no jokers owned the section says none and carries no joker content",
  bare_built >= 20 and #bare_missing == 0 and bare_rows == 0 and bare_agg == 0,
  string.format("built=%d without-row=%d not-none=%d agg=%d",
    bare_built, #bare_missing, bare_rows, bare_agg))

check("every force built while the run owns jokers carries the joker roster",
  #owned_missing == 0, table.concat(owned_missing, " | "))

do
  local elsewhere = {}
  for state, n in pairs(owned_ceiling) do
    if state ~= "SELECTING_HAND" then elsewhere[#elsewhere + 1] = state .. " x" .. n end
  end
  table.sort(elsewhere)
  check("the aggregate reaches SELECTING_HAND, so the check is not vacuous",
    (owned_agg.SELECTING_HAND or 0) >= 15, tostring(owned_agg.SELECTING_HAND))
  check("and no other state carries a ceiling or a refusal for a hand it cannot play",
    #elsewhere == 0, table.concat(elsewhere, ", "))
  check("C2a the aggregate itself does reach the states where a build is decided",
    (owned_agg.SHOP or 0) >= 26 and (owned_agg.BLIND_SELECT or 0) >= 12,
    "SHOP=" .. tostring(owned_agg.SHOP) .. " BLIND_SELECT=" .. tostring(owned_agg.BLIND_SELECT))
  -- The engine resets the round counters before the state flips to SHOP
  -- (game-dump functions/button_callbacks.lua:2982), so a joker priced off them reads its post-reset
  -- value at cash-out: Banner would show +0 Chips, Dusk would drop its "only on the last hand"
  -- qualifier. Wrong numbers, in the one state whose only answer is cash_out.
  check("C2b ROUND_EVAL stays silent, because its round counters are already reset",
    (owned_agg.ROUND_EVAL or 0) == 0, tostring(owned_agg.ROUND_EVAL))
  check("the states that must stay silent were actually swept",
    (owned_states.ROUND_EVAL or 0) >= 1 and (owned_states.SHOP or 0) >= 1
      and (owned_states.BLIND_SELECT or 0) >= 1,
    "covered: " .. table.concat(covered, ","))
end

do
  local Vanilla = require("tests.fixtures.vanilla_jokers")
  local CtxJokers = require("context.ctx_jokers")

  local function deck52()
    local d, n = {}, 0
    for _, suit in ipairs({ "Hearts", "Diamonds", "Spades", "Clubs" }) do
      for id = 2, 14 do
        n = n + 1
        d[n] = { sort_id = 500 + n, base = { id = id, suit = suit, nominal = math.min(id, 10) },
          get_id = function(self) return self.base.id end,
          is_suit = function(self, x) return self.base.suit == x end,
          is_face = function(self) return self.base.id >= 11 and self.base.id <= 13 end }
      end
    end
    return d
  end

  local function line(state_name, cards)
    local d = deck52()
    _G.G = {
      STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 5 },
      GAME = { round = 1, dollars = 8, round_resets = { ante = 2 },
        probabilities = { normal = 1 }, hands = {}, current_round = {} },
      NEURO = { once_serials = {}, jokers_sold_run = 0 },
      deck = { cards = d }, playing_cards = d,
      hand = { cards = {}, config = { card_limit = 8 } },
      jokers = { cards = cards, config = { card_limit = 5 } },
    }
    local out = select(2, pcall(CtxJokers.jokers_section, state_name)) or ""
    for l in tostring(out):gmatch("[^\n]+") do
      if l:find("^Joker bonuses") then return l end
    end
    return ""
  end

  local gated = { Vanilla.card("j_blackboard", 1), Vanilla.card("j_baron", 2) }
  local at_table = line("SELECTING_HAND", gated)
  local in_shop = line("SHOP", gated)

  check("with a hand, the gated ceiling is stated",
    at_table:find(CEILING, 1, true) ~= nil, at_table)
  check("without one it is withheld -- there is no hand to price it against",
    in_shop:find(CEILING, 1, true) == nil, in_shop)
  local refusing = { Vanilla.card("j_jolly", 1), Vanilla.card("j_sly", 2), Vanilla.card("j_raised_fist", 3) }
  check("a refusal that only exists because the hand is empty is withheld",
    line("SHOP", refusing):find(REFUSAL, 1, true) == nil, line("SHOP", refusing))
  check("D3a and the same board still states it where a hand can be played",
    line("SELECTING_HAND", refusing):find(REFUSAL, 1, true) ~= nil,
    line("SELECTING_HAND", refusing))

  local pair2 = { Vanilla.card("j_jolly", 1), Vanilla.card("j_sly", 2) }
  check("a bucket that sums two jokers survives away from the table",
    line("SHOP", pair2):find("if the hand contains a Pair", 1, true) ~= nil, line("SHOP", pair2))

  local pair1 = { Vanilla.card("j_jolly", 1) }
  check("a one-joker bucket is dropped away from the table",
    line("SHOP", pair1):find("if the hand contains a Pair", 1, true) == nil, line("SHOP", pair1))
  check("but kept with a hand, where the line claims to be the whole ledger",
    line("SELECTING_HAND", pair1):find("if the hand contains a Pair", 1, true) ~= nil,
    line("SELECTING_HAND", pair1))
end

done()
