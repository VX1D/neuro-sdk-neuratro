_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("force-prose-offer")
local H = require("tests.helpers")

local Actions = require("core.actions")
local TransitionGuard = require("core.transition_guard")
local Dispatcher = require("core.dispatcher")
local Registry = require("core.action_registry")
local FS = require("core.force_state")
local TD = require("tests.test_deadlock")

G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local AMBIGUOUS = { help = true }

local WITHHELD_NOTICE = {
  { action = "toggle_shop", clause = "toggle_shop is off the list until every joker has one" },
}

local NAMES = {}
for _, name in ipairs(Registry.names()) do
  if not AMBIGUOUS[name] then NAMES[#NAMES + 1] = name end
end

local function is_word_char(c) return c ~= "" and c:match("[%w_]") ~= nil end

local function mention_positions(text, name)
  local out, init = {}, 1
  while true do
    local s, e = text:find(name, init, true)
    if not s then return out end
    if not is_word_char(s > 1 and text:sub(s - 1, s - 1) or "")
      and not is_word_char(text:sub(e + 1, e + 1)) then
      out[#out + 1] = { s, e }
    end
    init = s + 1
  end
end

local function covered_by_notice(query, name, span, offered)
  for _, notice in ipairs(WITHHELD_NOTICE) do
    if notice.action == name and not offered[name] then
      local init = 1
      while true do
        local s, e = query:find(notice.clause, init, true)
        if not s then break end
        if span[1] >= s and span[2] <= e then return true end
        init = s + 1
      end
    end
  end
  return false
end

local ROUTES = {
  { first = "change_challenge_description", second = "start_challenge_run" },
}
local routes_seen = {}

local function covered_by_route(query, name, span, offered)
  local sentence_start = 1
  for pos = span[1], 1, -1 do
    local c = query:sub(pos, pos)
    if c == "." or c == "\n" then sentence_start = pos + 1; break end
  end
  local lead = query:sub(sentence_start, span[1] - 1)
  for i, route in ipairs(ROUTES) do
    if route.second == name and offered[route.first] then
      for _, other_span in ipairs(mention_positions(lead, route.first)) do
        if lead:sub(other_span[2] + 1):find("%f[%w]then%f[%W]") then
          routes_seen[i] = (routes_seen[i] or 0) + 1
          return true
        end
      end
    end
  end
  return false
end

local SETTLING_NOTE = "only these actions are accepted RIGHT NOW"

local WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster",
  "shop", "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU",
  "CHALLENGES" }

local function usable_consumable()
  return { cost = 3, sell_cost = 2, ability = { name = "Pluto", set = "Planet", consumeable = {} },
    config = { center = { key = "c_pluto", name = "Pluto", set = "Planet",
      loc_txt = { name = "Pluto", description = "Levels up High Card" } } } }
end

local function joker(key, sid)
  return { cost = 4, sell_cost = 2, sort_id = sid, ability = { set = "Joker", name = key },
    config = { center = { key = key, name = key, set = "Joker",
      loc_txt = { name = key, description = "+4 Mult" } } } }
end

local VARIANTS = {
  { name = "baseline", apply = function() end },
  { name = "plan gates armed", apply = function()
      G.NEURO.econ_plan_ok = false
      G.NEURO.blind_plan_ok = false
      G.NEURO.shop_plan_revision_required = { money = true, build = true }
    end },
  { name = "consumable mid-animation", apply = function()
      G.consumeables = { cards = { usable_consumable() }, config = { card_limit = 2 } }
      if G.GAME then G.GAME.STOP_USE = 1 end
    end },
  { name = "untagged roster", apply = function()
      G.jokers = { cards = { joker("j_blueprint", 901), joker("j_ice_cream", 902) },
        config = { card_limit = 5 } }
      G.NEURO.joker_intents = {}
      G.FUNCS.toggle_shop = G.FUNCS.toggle_shop or function() end
    end },
  { name = "single joker, nothing sellable", apply = function()
      G.jokers = { cards = {}, config = { card_limit = 5 } }
      G.consumeables = { cards = {}, config = { card_limit = 2 } }
    end },
  { name = "unusable targeting consumable", apply = function()
      G.consumeables = { cards = { { cost = 3, sell_cost = 2,
        ability = { name = "The Chariot", set = "Tarot",
          consumeable = { min_highlighted = 9, max_highlighted = 9 } },
        config = { center = { key = "c_chariot", name = "The Chariot", set = "Tarot",
          loc_txt = { name = "The Chariot", description = "Enhances 9 cards" } } } } },
        config = { card_limit = 2 } }
    end },
  { name = "challenges listed", apply = function()
      G.CHALLENGES = { { id = "c_omelette_1", name = "The Omelette" } }
    end },
}

local STATE_ID, next_id = {}, 0
local violations, forces, mentions_seen, notices_seen = {}, 0, 0, 0

for _, sc in ipairs(TD.SCENARIOS) do
  for _, variant in ipairs(VARIANTS) do
    for _, key in ipairs(WIPE) do G[key] = nil end
    G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", reserved_dollars = 0,
      _reservation_epoch = 0, shop_reroll_count = 0, _decision_windows = {},
      state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 5 }
    require("core.transition_guard").reset()
    local state = sc.state
    if not STATE_ID[state] then next_id = next_id + 1; STATE_ID[state] = next_id end
    local ok_mock = pcall(function()
      TD.apply_mock(sc.mock())
      G.STATES = G.STATES or {}
      G.STATES[state] = STATE_ID[state]
      G.STATE = STATE_ID[state]
      variant.apply()
    end)
    if ok_mock then
      local ok_force, force = pcall(Dispatcher.get_force_for_state, state)
      if ok_force and type(force) == "table" and type(force.query) == "string"
        and type(force.actions) == "table" then
        forces = forces + 1
        local offered = {}
        for _, name in ipairs(force.actions) do offered[name] = true end
        local settling = {}
        for _, name in ipairs(Actions.get_valid_actions_for_state(state)) do
          if not offered[name] and TransitionGuard.reject_reason(name) then settling[name] = true end
        end
        for _, name in ipairs(NAMES) do
          for _, span in ipairs(mention_positions(force.query, name)) do
            if offered[name] then
              mentions_seen = mentions_seen + 1
            elseif covered_by_notice(force.query, name, span, offered)
              or covered_by_route(force.query, name, span, offered)
              or (settling[name] and force.query:find(SETTLING_NOTE, 1, true) ~= nil) then
              notices_seen = notices_seen + 1
            else
              violations[#violations + 1] = state .. "/" .. variant.name .. " :: " .. name
            end
          end
        end
      end
    end
  end
end

check("the sweep built forces to scan (guards the invariant from passing empty)",
  forces >= 610, tostring(forces))
check("the scan actually recognises action names in prose (not a dead matcher)",
  mentions_seen >= 1900, tostring(mentions_seen))
check("the withheld-notice path is exercised by the sweep",
  notices_seen >= 110, tostring(notices_seen))
for i, route in ipairs(ROUTES) do
  check(string.format("P0: declared route %s -> %s is exercised by the sweep", route.first, route.second),
    (routes_seen[i] or 0) > 0, tostring(routes_seen[i] or 0))
end

local unique, order = {}, {}
for _, v in ipairs(violations) do
  if not unique[v] then unique[v] = 0; order[#order + 1] = v end
  unique[v] = unique[v] + 1
end
local report = {}
for _, v in ipairs(order) do report[#report + 1] = v .. " x" .. unique[v] end
check("no force names an action it does not offer",
  #violations == 0, table.concat(report, "; "))

do
  local real_valid = Actions.is_action_valid
  local ForceShop = require("force.force_shop")

  local function shop_G()
    _G.G = {
      STATE = 5, STATES = { SHOP = 5 }, P_BLINDS = {}, TIMERS = { REAL = 100 },
      FUNCS = { toggle_shop = function() end },
      GAME = { dollars = 8, interest_cap = 25, modifiers = {}, round = 4,
        round_resets = { ante = 2, blind_choices = {} },
        current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 } },
      NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1, joker_intents = {} },
      jokers = { cards = { joker("j_joker", 801), joker("j_ice_cream", 802) },
        config = { card_limit = 5 } },
      consumeables = { cards = {}, config = { card_limit = 2 } },
      shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    }
  end
  local PARAGRAPH = "As you plan, weigh your joker build"

  local function query_with(valid)
    Actions.is_action_valid = function(n) return valid[n] == true end
    shop_G()
    local res = ForceShop.build()
    return ((res or {}).query or "") .. H.drain_hints()
  end

  check("both actions offered -> the paragraph is present",
    query_with({ toggle_shop = true, sell_card = true, set_joker_order = true })
      :find(PARAGRAPH, 1, true) ~= nil)
  check("set_joker_order withheld -> the paragraph is gone",
    query_with({ toggle_shop = true, sell_card = true }):find(PARAGRAPH, 1, true) == nil)
  check("sell_card withheld -> the paragraph is gone",
    query_with({ toggle_shop = true, set_joker_order = true }):find(PARAGRAPH, 1, true) == nil)
  check("neither offered -> the paragraph is gone",
    query_with({ toggle_shop = true }):find(PARAGRAPH, 1, true) == nil)

  Actions.is_action_valid = real_valid
end

do
  local ForceHelpers = require("force.force_helpers")
  local LINE = "change_challenge_description then start_challenge_run"
  check("challenge route absent when change_challenge_description is not offered",
    ForceHelpers.menu_action_tree_query({}):find(LINE, 1, true) == nil)
  check("challenge route present once change_challenge_description is offered",
    ForceHelpers.menu_action_tree_query({ change_challenge_description = true })
      :find(LINE, 1, true) ~= nil)
end

do
  local MenuHandlers = require("handlers.menu_handlers")
  for _, key in ipairs(WIPE) do G[key] = nil end
  _G.G.GAME = { current_round = {} }
  _G.G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro" }
  TransitionGuard.reset()
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "MENU" then TD.apply_mock(sc.mock()); break end
  end
  G.NEURO.persona = "neuro"
  G.CHALLENGES = { { id = "c_omelette_1", name = "The Omelette" } }
  G.challenge_tab = nil

  local function menu_offer()
    local f = Dispatcher.get_force_for_state("MENU")
    local set = {}
    for _, n in ipairs((f or {}).actions or {}) do set[n] = true end
    return set, ((f or {}).query or "")
  end

  local before, query = menu_offer()
  check("MENU prose names start_challenge_run while it is not yet offered",
    query:find("start_challenge_run", 1, true) ~= nil and not before.start_challenge_run)
  check("the route's first step is offered", before.change_challenge_description == true)
  local exec = MenuHandlers.handle_change_challenge_description({ id = "c_omelette_1" })
  check("the route's first step is executable", type(exec) == "function")
  if type(exec) == "function" then exec() end
  local after = menu_offer()
  check("start_challenge_run is offered after the route's first step",
    after.start_challenge_run == true)
end

done()
