_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("action surface")

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Registry = require("core.action_registry")
local Enforce = require("core.enforce")
local FS = require("core.force_state")
local ContextCompact = require("context.context_compact")
local TD = require("tests.test_deadlock")

G.NEURO.dispatcher = Dispatcher
G.NEURO.actions = Actions

local WIPE = { "hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster",
  "shop", "pack_cards", "booster_pack", "blind_select_opts", "blind_select", "OVERLAY_MENU" }
local function wipe_board()
  for _, key in ipairs(WIPE) do G[key] = nil end
end

do
  local STATE_ID, next_id = {}, 0
  local violations, forces = {}, 0
  for _, sc in ipairs(TD.SCENARIOS) do
    wipe_board()
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
      G.NEURO.persona = G.NEURO.persona or "neuro"
    end)
    if ok_mock then
      local ok_force, force = pcall(Dispatcher.get_force_for_state, state)
      if ok_force and type(force) == "table" and type(force.actions) == "table" then
        forces = forces + 1
        local registered = {}
        for _, name in ipairs(Actions.get_valid_actions_for_state(state)) do registered[name] = true end
        for _, name in ipairs(force.actions) do
          if not registered[name] then violations[#violations + 1] = state .. ":" .. name end
        end
      end
    end
  end
  check("the scenario sweep actually built forces (guards the invariant from passing empty)",
    forces >= 40, tostring(forces))
  check("every offered action is registered in that state",
    #violations == 0, table.concat(violations, ", "))
end

local BossLegality = require("facts.boss.legality")

do
  local offered_cosmetic, eligible_forces, reorder_bosses = {}, 0, 0
  local reorder_offered, reorder_named = {}, {}
  local STATE_ID = { SELECTING_HAND = 91 }
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == "SELECTING_HAND" then
      wipe_board()
      G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", reserved_dollars = 0,
        _decision_windows = {}, state_enter_serial = 40 }
      require("core.transition_guard").reset()
      local ok_mock = pcall(function()
        TD.apply_mock(sc.mock())
        G.STATES = { SELECTING_HAND = STATE_ID.SELECTING_HAND }
        G.STATE = STATE_ID.SELECTING_HAND
        G.jokers = { cards = {
          { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
            config = { center = { key = "j_a", set = "Joker" } } },
          { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
            config = { center = { key = "j_b", set = "Joker" } } },
        }, config = { card_limit = 5 } }
      end)
      local ok_reorder, names_reorder = pcall(BossLegality.boss_names_reorder)
      if ok_mock and ok_reorder and names_reorder then
        reorder_bosses = reorder_bosses + 1
        local ok_force, force = pcall(Dispatcher.get_force_for_state, "SELECTING_HAND")
        if ok_force and type(force) == "table" then
          local offers = false
          for _, name in ipairs(force.actions or {}) do
            if name == "set_joker_order" then offers = true end
          end
          reorder_offered[#reorder_offered + 1] = offers
          reorder_named[#reorder_named + 1] =
            tostring(force.query or ""):find("set_joker_order", 1, true) ~= nil
        end
      end
      if ok_mock and not (ok_reorder and names_reorder) then
        local ok_force, force = pcall(Dispatcher.get_force_for_state, "SELECTING_HAND")
        if ok_force and type(force) == "table" and type(force.actions) == "table"
            and Actions.is_action_valid("set_joker_order") then
          eligible_forces = eligible_forces + 1
          for _, name in ipairs(force.actions) do
            if name == "set_joker_order" then
              offered_cosmetic[#offered_cosmetic + 1] = name .. " (" .. sc.desc .. ")"
            end
          end
        end
      end
    end
  end
  check("the sweep reached SELECTING_HAND forces where set_joker_order is valid",
    eligible_forces >= 5, tostring(eligible_forces))
  check("the corpus still contains a boss that names reordering, so the exclusion is exercised",
    reorder_bosses >= 1, tostring(reorder_bosses))
  check("no ordinary SELECTING_HAND force offers set_joker_order",
    #offered_cosmetic == 0, table.concat(offered_cosmetic, ", "))
  do
    local all_offered, all_named = #reorder_offered > 0, #reorder_named > 0
    for _, v in ipairs(reorder_offered) do all_offered = all_offered and v end
    for _, v in ipairs(reorder_named) do all_named = all_named and v end
    check("under a reordering boss the force offers set_joker_order",
      all_offered, tostring(#reorder_offered) .. " forces")
    check("and names it in the query, so the offer is not silent",
      all_named, tostring(#reorder_named) .. " forces")
  end
  local set = Actions.get_state_action_set("SELECTING_HAND")
  check("it stays registered in SELECTING_HAND (she can still reach for it)",
    set.set_joker_order == true)
end

do
  local sh = Actions.get_state_action_set("SELECTING_HAND")
  local shop = Actions.get_state_action_set("SHOP")
  local re = Actions.get_state_action_set("ROUND_EVAL")

  check("record_plan stays registered in ROUND_EVAL, so she can still revise the plan there",
    re.record_plan == true)
  check("but the ROUND_EVAL force offers cash_out alone", (function()
    local overlay = G.OVERLAY_MENU
    G.OVERLAY_MENU = nil
    local ok, force = pcall(require("force.force_router").get_force_for_state, "ROUND_EVAL")
    G.OVERLAY_MENU = overlay
    if not ok or type(force) ~= "table" or type(force.actions) ~= "table" then return false, tostring(force) end
    return #force.actions == 1 and force.actions[1] == "cash_out",
      table.concat(force.actions, ",")
  end)())

  check("record_joker_roles is not registered in SELECTING_HAND", sh.record_joker_roles ~= true)
  check("record_joker_roles stays registered in SHOP, where it is offered",
    shop.record_joker_roles == true)

  local REMOVED = { "help", "quick_status", "full_game_context", "shop_context", "owned_vouchers",
    "round_history", "scoring_explanation", "consumables_info", "blind_info", "hand_levels_info",
    "hand_details", "get_poker_hand_information", "joker_info", "card_modifiers_information",
    "deck_type" }
  local removed_set = {}
  for _, n in ipairs(REMOVED) do removed_set[n] = true end
  local resurrected = {}
  for _, d in ipairs(Registry.definitions()) do
    if removed_set[d.name] then resurrected[#resurrected + 1] = d.name end
  end
  check("the sweep has definitions to scan", #Registry.definitions() >= 20,
    tostring(#Registry.definitions()))
  check("no removed information action is registered in any state",
    #resurrected == 0, table.concat(resurrected, ", "))

  local RETIRED_ACTIONS = {
    "confirm_play", "use_card", "use_directional_card", "toggle_shop", "skip_booster",
    "setup_run", "start_setup_run", "change_selected_back", "change_stake",
    "change_challenge_description", "set_joker_intents", "set_plan",
  }
  local retired_set, retired_found = {}, {}
  for _, name in ipairs(RETIRED_ACTIONS) do retired_set[name] = true end
  for _, definition in ipairs(Registry.definitions()) do
    if retired_set[definition.name] then retired_found[#retired_found + 1] = definition.name end
  end
  check("no retired action alias survives in the model registry",
    #retired_found == 0, table.concat(retired_found, ", "))
  check("cash_out stays the progress action of ROUND_EVAL", re.cash_out == true)
end

do
  local homeless = {}
  for _, contract in ipairs(Registry.all()) do
    if not next(contract.states or {}) then homeless[#homeless + 1] = contract.name end
  end
  check("no action lost its last state", #homeless == 0, table.concat(homeless, ", "))
end

do
  local function play_card(i, value, suit)
    return { sort_id = i, cost = 0, sell_cost = 0, ability = { set = "Default", name = "Mock" },
      config = { center = {} }, base = { value = value, suit = suit },
      juice_up = function() end, highlight = function() end }
  end
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.NEURO = { dispatcher = Dispatcher, actions = Actions, persona = "neuro", _decision_windows = {} }
  G.GAME = {
    dollars = 17, chips = 40, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2, hands_played = 1, discards_used = 1 },
    round_resets = { ante = 3, blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind = { name = "The Hook", chips = 800, mult = 2, boss = true, debuff = {} },
    blind_on_deck = "Boss",
    hands = { Pair = { level = 4, chips = 30, mult = 3, visible = true, played = 6 },
      Flush = { level = 2, chips = 40, mult = 5, visible = true, played = 2 } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1, "10", "Hearts"), play_card(2, "10", "Spades"),
    play_card(3, "7", "Clubs"), play_card(4, "K", "Diamonds"), play_card(5, "A", "Hearts") },
    highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  G.jokers = { cards = { { sort_id = 100, cost = 4, sell_cost = 2,
    ability = { set = "Joker", name = "Joker" },
    config = { center = { key = "j_joker", name = "Joker", set = "Joker",
      loc_txt = { name = "Joker", description = "+4 Mult" } } } } }, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.P_BLINDS = { bl_hook = { name = "The Hook" } }
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }

  local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
  local blob = ContextCompact.build("SELECTING_HAND", valid, { no_cache = true })
  local force = Dispatcher.get_force_for_state("SELECTING_HAND")
  local delivered = tostring(blob) .. "\n" .. tostring(force and force.query or "")
  local function carries(needle) return delivered:find(needle, 1, true) ~= nil end

  check("the fixture built a SELECTING_HAND force to compare against",
    type(force) == "table" and type(force.query) == "string" and #delivered > 400)

  check("the roster and its joker text are delivered",
    carries("Joker") and carries("+4 Mult"))
  check("hand levels, base values and play counts are delivered",
    carries("Pair: level 4, 30 chips x 3 mult = 90 before any card or joker, played 6.")
      and carries("Flush: level 2, 40 chips x 5 mult = 200 before any card or joker, played 2."))
  check("the blind, the resources and the money are delivered",
    carries("The Hook") and carries("3 hands and 2 discards left") and carries("$17 in the bank"))
  check("every held card is delivered",
    carries("10 of Hearts") and carries("10 of Spades") and carries("7 of Clubs")
      and carries("K of Diamonds") and carries("A of Hearts"))
  check("the blind, roster and hand read together in one delivery",
    carries("760 to go") and carries("Joker") and carries("A of Hearts"))
end

do
  local function play_card(i)
    return { sort_id = i, cost = 0, sell_cost = 0, ability = { set = "Default", name = "Mock" },
      config = { center = {} }, base = { value = tostring(i + 4), suit = "Hearts" },
      juice_up = function() end, highlight = function() end }
  end
  G.TIMERS.REAL = 100
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  G.NEURO = { enabled = true, decision_serial = 1 }

  local bridge = { emitted = {} }
  function bridge:send_context(msg) self.emitted[#self.emitted + 1] = tostring(msg) end
  bridge.register_actions = function() end
  bridge.unregister_actions = function() end
  bridge.is_transition_cooldown = function() return false end

  local function send(payload)
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    G.NEURO.force_inflight = false
    FS.arm("SELECTING_HAND", { "play_hand", "discard_hand" },
      { play_hand = true, discard_hand = true }, 1)
    return Enforce.pre_action(bridge, "play_hand", payload) == true
  end

  local blocked = 0
  for _ = 1, 60 do
    if not send('{"indices":[1,2]}') then blocked = blocked + 1 end
  end
  check("a run of identical sends is capped", blocked > 0, tostring(blocked))
  check("a different selection of the same action passes -- escape needs no second action name",
    send('{"indices":[3,4]}'))
  check("and the capped selection is live again after it",
    send('{"indices":[1,2]}'))
end

done()
