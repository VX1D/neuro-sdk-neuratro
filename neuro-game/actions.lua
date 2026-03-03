local Actions = {}
local Utils = require "utils"
local has_playbook_extra = Utils.has_playbook_extra

local function action_def(name, description, schema)
  return {
    name = name,
    description = description or ("Trigger action " .. name .. "."),
    schema = schema or { type = "object" }
  }
end

local function generic_schema()
  return { type = "object" }
end

local function build_area_enum()
  local enum = {
    "hand",
    "jokers",
    "consumeables",
    "shop_jokers",
    "shop_vouchers",
    "shop_booster",
    "booster_pack",
    "play",
  }
  if has_playbook_extra() then
    enum[#enum + 1] = "playbook_extra"
  end
  return enum
end

local function build_param_actions()
  local area_enum = build_area_enum()
  return {
    select_blind = action_def("select_blind", "Select the active blind for this ante (small, big, or boss).", {
    type = "object",
    properties = { blind = { enum = { "small", "big", "boss" }, description = "Which blind to select" } },
    required = { "blind" }
    }),
    use_card = action_def("use_card", "Use a card from the specified area and index. For tarots that need hand cards, pass hand_indices to select them.", {
    type = "object",
    properties = {
      area = { enum = { "hand", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "booster_pack" }, description = "Which area the card is in" },
      index = { type = "integer", minimum = 1, description = "Card position (1-indexed from left to right)" },
      hand_indices = { type = "array", items = { type = "integer", minimum = 1 }, description = "Hand card positions to highlight before using (for tarots needing selected cards)" }
    },
    required = { "area", "index" }
    }),
    buy_from_shop = action_def("buy_from_shop", "Buy an item from the selected shop area and index.", {
    type = "object",
    properties = {
      area = { enum = { "shop_jokers", "shop_vouchers", "shop_booster" }, description = "Which shop section to buy from" },
      index = { type = "integer", minimum = 1, description = "Item position in shop (1-indexed from left)" },
      use = { type = "boolean", description = "Whether to use the item immediately after buying (for consumables)" }
    },
    required = { "area", "index" }
    }),
    sell_card = action_def("sell_card", "Sell a card from the selected area and index.", {
    type = "object",
    properties = {
      area = { enum = { "jokers", "consumeables" }, description = "Where the card is located" },
      index = { type = "integer", minimum = 1, description = "Card position to sell" }
    },
    required = { "area", "index" }
    }),
    card_click = action_def("card_click", "Click/interact with a card in a given area. Used for selecting cards in booster packs or other interactive card areas.", {
    type = "object",
    properties = {
      area = { enum = area_enum },
      index = { type = "integer", minimum = 1 }
    },
    required = { "area", "index" }
    }),
    highlight_card = action_def("highlight_card", "Highlight a card in a given area by index.", {
    type = "object",
    properties = {
      area = { enum = area_enum },
      index = { type = "integer", minimum = 1 }
    },
    required = { "area", "index" }
    }),
    unhighlight_all = action_def("unhighlight_all", "Clear highlights for a given area.", {
    type = "object",
    properties = { area = { enum = area_enum } },
    required = { "area" }
    }),
    text_input_key = action_def("text_input_key", "Send a text input key.", {
    type = "object",
    properties = { key = { type = "string" } },
    required = { "key" }
    }),
    set_hand_highlight = action_def("set_hand_highlight", "Select hand cards by 1-indexed positions and execute action 'play' or 'discard' (1-5 cards).", {
    type = "object",
    properties = {
      indices = {
        type = "array",
        description = "List of card positions to select (1-indexed)",
        items = { type = "integer", minimum = 1, description = "Card position" }
      },
      action = {
        type = "string",
        enum = { "play", "discard" },
        description = "Whether to 'play' the selected cards for score or 'discard' them to draw new cards"
      }
    },
    required = { "indices" }
    }),
    change_stake = action_def("change_stake", "Change run stake to a specific key.", {
    type = "object",
    properties = { to_key = { type = "integer", minimum = 1 } },
    required = { "to_key" }
    }),
    change_challenge_list_page = action_def("change_challenge_list_page", "Change challenge list page by number.", {
    type = "object",
    properties = { page = { type = "integer", minimum = 1 } },
    required = { "page" }
    }),
    change_challenge_description = action_def("change_challenge_description", "Select a challenge description by id.", {
    type = "object",
    properties = { id = { type = "string" } },
    required = { "id" }
    }),
    change_selected_back = action_def("change_selected_back", "Select a deck by its key (e.g. b_red, b_blue).", {
    type = "object",
    properties = { back = { type = "string", description = "Deck key, e.g. b_red" } },
    required = { "back" }
    }),
    change_viewed_back = action_def("change_viewed_back", "View a back by key.", {
    type = "object",
    properties = { to_key = { type = "string" } },
    required = { "to_key" }
    }),
    change_viewed_collab = action_def("change_viewed_collab", "View a collab by key.", {
    type = "object",
    properties = { to_key = { type = "string" } },
    required = { "to_key" }
    }),
    change_contest_name = action_def("change_contest_name", "Edit contest name input.", {
    type = "object",
    properties = { text = { type = "string" } },
    required = { "text" }
    }),
    get_poker_hand_information = action_def("get_poker_hand_information", "Get information about all poker hand types and their levels.", {
      type = "object",
      properties = {},
      required = {}
    }),
    joker_info = action_def("joker_info", "Get information about all jokers in your collection.", {
      type = "object",
      properties = {},
      required = {}
    }),
    card_modifiers_information = action_def("card_modifiers_information", "Get descriptions of all active card modifiers.", {
      type = "object",
      properties = {},
      required = {}
    }),
    deck_type = action_def("deck_type", "Get information about available deck types.", {
      type = "object",
      properties = {},
      required = {}
    }),
    choose_persona = action_def("choose_persona", "Set active persona to 'neuro' or 'evil'.", {
    type = "object",
    properties = {
      persona = {
        type = "string",
        enum = { "neuro", "evil" },
        description = "Pick 'neuro' for Neuro-sama or 'evil' for Evil Neuro"
      }
    },
    required = { "persona" }
    }),
    evaluate_play = action_def("evaluate_play", "Evaluate and score current hand in play area.", {
      type = "object",
      properties = {},
      required = {}
    }),
    scoring_explanation = action_def("scoring_explanation", "Get detailed scoring mechanics and formula.", {
      type = "object",
      properties = {},
      required = {}
    }),
    joker_strategy = action_def("joker_strategy", "Get factual joker state snapshot and order/effect details.", {
      type = "object",
      properties = {},
      required = {}
    }),
    shop_context = action_def("shop_context", "Get shop economy information and available items.", {
      type = "object",
      properties = {},
      required = {}
    }),
    blind_info = action_def("blind_info", "Get current blind information and resources.", {
      type = "object",
      properties = {},
      required = {}
    }),
    hand_levels_info = action_def("hand_levels_info", "Get all hand types and their current levels.", {
      type = "object",
      properties = {},
      required = {}
    }),
    full_game_context = action_def("full_game_context", "Get comprehensive game context including scoring, blind, jokers.", {
      type = "object",
      properties = {},
      required = {}
    }),
    quick_status = action_def("quick_status", "Get a compact summary of current game state.", {
      type = "object",
      properties = {},
      required = {}
    }),
    consumables_info = action_def("consumables_info", "Show tarot, planet, and spectral cards in inventory.", {
      type = "object",
      properties = {},
      required = {}
    }),
    hand_details = action_def("hand_details", "Show detailed information about cards in hand including enhancements and seals.", {
      type = "object",
      properties = {},
      required = {}
    }),
    deck_composition = action_def("deck_composition", "Analyze composition of remaining deck by suit, enhancement, seal, and edition.", {
      type = "object",
      properties = {},
      required = {}
    }),
    owned_vouchers = action_def("owned_vouchers", "Show all owned vouchers and their effects.", {
      type = "object",
      properties = {},
      required = {}
    }),
    round_history = action_def("round_history", "Show hands played and actions taken this round.", {
      type = "object",
      properties = {},
      required = {}
    }),
    neuratro_info = action_def("neuratro_info", "Show Neuratro mod status and special content.", {
      type = "object",
      properties = {},
      required = {}
    }),
    set_joker_order = action_def("set_joker_order", "Move a joker to a specific index position.", {
      type = "object",
      properties = {
        from_index = { type = "integer", minimum = 1 },
        to_index = { type = "integer", minimum = 1 }
      },
      required = { "from_index", "to_index" }
    }),
    reorder_hand_cards = action_def("reorder_hand_cards", "Reorder hand cards by index mapping.", {
      type = "object",
      properties = {
        order = {
          type = "array",
          items = { type = "integer", minimum = 1 }
        }
      },
      required = { "order" }
    }),
    simulate_hand = action_def("simulate_hand", "Simulate scoring for highlighted hand without playing.", {
      type = "object",
      properties = {},
      required = {}
    }),
    draw_from_deck = action_def("draw_from_deck", "Draw cards from deck to hand.", {
      type = "object",
      properties = {
        count = { type = "integer", minimum = 1, default = 1 }
      },
      required = {}
    }),
    help = action_def("help", "List all available actions and info commands.", {
      type = "object",
      properties = {},
      required = {}
    }),
  }
end

local function get_cheapest_shop_cost()
  local cheapest = nil
  local function scan(area)
    if not (area and area.cards) then return end
    for _, card in ipairs(area.cards) do
      local cost = card and card.cost
      if type(cost) == "number" and cost >= 0 then
        if not cheapest or cost < cheapest then
          cheapest = cost
        end
      end
    end
  end

  scan(G and G.shop_jokers)
  scan(G and G.shop_vouchers)
  scan(G and G.shop_booster)
  return cheapest
end

local function get_spendable_dollars()
  if not (G and G.GAME) then return 0 end
  local dollars = tonumber(G.GAME.dollars or 0) or 0
  local bankrupt_at = tonumber(G.GAME.bankrupt_at or 0) or 0
  return dollars - bankrupt_at
end

local function early_shop_buy_priority_active()
  if not (G and G.GAME and G.GAME.round_resets) then
    return false
  end
  local ante = tonumber(G.GAME.round_resets.ante or 0) or 0
  if ante <= 0 or ante > 2 then
    return false
  end

  local spendable = get_spendable_dollars()
  local boosters = 0
  local jokers = 0

  local function scan(area, key)
    if not (area and area.cards) then return end
    for _, card in ipairs(area.cards) do
      local cost = card and card.cost
      if type(cost) == "number" and cost >= 0 and cost <= spendable then
        if key == "boosters" then boosters = boosters + 1 end
        if key == "jokers" then jokers = jokers + 1 end
      end
    end
  end

  scan(G.shop_booster, "boosters")
  scan(G.shop_jokers, "jokers")

  local joker_space = true
  if G.jokers and G.jokers.cards and G.jokers.config and G.jokers.config.card_limit then
    joker_space = #G.jokers.cards < (G.jokers.config.card_limit or 0)
  end

  if boosters > 0 then return true end
  if jokers > 0 and joker_space then return true end
  return false
end

local function get_selectable_blind_key()
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return nil
  end

  local on_deck = G.GAME.blind_on_deck
  if on_deck == "Small" or on_deck == "Big" or on_deck == "Boss" then
    return on_deck
  end

  local bs = G.GAME.round_resets.blind_states
  if bs.Small == "Select" then return "Small" end
  if bs.Big == "Select" then return "Big" end
  if bs.Boss == "Select" then return "Boss" end
  return nil
end

local SIMPLE_ACTION_DESCS = {
  play_cards_from_highlighted = "Play currently highlighted hand cards.",
  discard_cards_from_highlighted = "Discard currently highlighted hand cards.",
  reroll_shop = "Reroll current shop inventory (cost applies).",
  toggle_shop = "Exit shop and continue run flow.",
  skip_blind = "Skip current blind and take skip reward.",
  reroll_boss = "Reroll current boss blind when available.",
  skip_booster = "Skip current booster pack.",
  end_consumeable = "Finish current consumable selection flow.",
  exit_overlay_menu = "Close an open overlay/popup menu and continue.",
  cash_out = "Collect round payout and continue to shop flow.",
  setup_run = "Open the run setup screen to choose your deck, stake, and seed before starting a run.",
  start_run = "Start a new game run with the current deck and settings.",
  start_challenge_run = "Start a challenge run with preset rules and restrictions.",
  start_setup_run = "Start a run from the setup screen with your chosen options.",
  toggle_seeded_run = "Toggle seeded run mode on or off for reproducible games.",
  clear_hand_highlight = "Deselect all currently highlighted cards in your hand.",
  copy_seed = "Copy the current run seed to clipboard.",
  paste_seed = "Paste a seed for a seeded run.",
  confirm_contest_name = "Confirm the entered contest name.",
  sort_hand_suit = "Sort hand cards by suit.",
  sort_hand_value = "Sort hand cards by rank.",
}

local UNIVERSAL_ACTIONS = {
  "exit_overlay_menu",
}

local SIMPLE_ACTIONS = {}
for name, _ in pairs(SIMPLE_ACTION_DESCS) do
  SIMPLE_ACTIONS[#SIMPLE_ACTIONS + 1] = name
end

local function build_action_set()
  local action_set = {}
  for _, name in ipairs(SIMPLE_ACTIONS) do
    action_set[name] = action_def(name, SIMPLE_ACTION_DESCS[name], generic_schema())
  end
  local param_actions = build_param_actions()
  for name, def in pairs(param_actions) do
    action_set[name] = def
  end
  return action_set
end

local STATE_ACTIONS = {
  SPLASH = {
    "choose_persona",
    "setup_run",
    "change_selected_back",
    "change_stake",
    "toggle_seeded_run",
    "paste_seed",
    "start_setup_run",
    "help",
  },
  MENU = {
    "choose_persona",
    "setup_run",
    "start_challenge_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_stake",
    "change_selected_back",
    "start_setup_run",
    "confirm_contest_name",
    "help",
  },
  RUN_SETUP = {
    "choose_persona",
    "setup_run",
    "start_challenge_run",
    "start_setup_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_stake",
    "change_challenge_list_page",
    "change_challenge_description",
    "change_selected_back",
    "change_viewed_back",
    "change_viewed_collab",
    "change_contest_name",
    "confirm_contest_name",
    "help",
  },
  GAME_OVER = {
    "choose_persona",
    "setup_run",
    "start_challenge_run",
    "exit_overlay_menu",
    "toggle_seeded_run",
    "paste_seed",
    "change_stake",
    "change_selected_back",
    "start_setup_run",
    "help",
  },
  BLIND_SELECT = {
    "select_blind",
    "skip_blind",
    "reroll_boss",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "blind_info",
    "joker_strategy",
    "scoring_explanation",
    "hand_levels_info",
    "quick_status",
    "neuratro_info",
    "help",
  },
  SELECTING_HAND = {
    "set_hand_highlight",
    "use_card",
    "highlight_card",
    "unhighlight_all",
    "card_click",
    "clear_hand_highlight",
    "play_cards_from_highlighted",
    "discard_cards_from_highlighted",
    "sort_hand_suit",
    "sort_hand_value",
    "reorder_hand_cards",
    "evaluate_play",
    "simulate_hand",
    "draw_from_deck",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "scoring_explanation",
    "joker_strategy",
    "blind_info",
    "hand_levels_info",
    "quick_status",
    "consumables_info",
    "hand_details",
    "deck_composition",
    "owned_vouchers",
    "round_history",
    "neuratro_info",
    "help",
  },
  SHOP = {
    "buy_from_shop",
    "sell_card",
    "use_card",
    "card_click",
    "reroll_shop",
    "toggle_shop",
    "set_joker_order",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "shop_context",
    "joker_strategy",
    "scoring_explanation",
    "blind_info",
    "quick_status",
    "consumables_info",
    "owned_vouchers",
    "deck_composition",
    "neuratro_info",
    "help",
  },
  ROUND_EVAL = {
    "cash_out",
    "evaluate_play",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "scoring_explanation",
    "joker_strategy",
    "hand_levels_info",
    "quick_status",
    "consumables_info",
    "deck_composition",
    "owned_vouchers",
    "round_history",
    "neuratro_info",
    "help",
  },
}

local PACK_ACTIONS = {
  "use_card",
  "card_click",
  "skip_booster",
  "end_consumeable",
  "get_poker_hand_information",
  "joker_info",
  "card_modifiers_information",
  "scoring_explanation",
  "joker_strategy",
  "deck_composition",
  "owned_vouchers",
  "hand_details",
  "neuratro_info",
  "help",
}
STATE_ACTIONS.TAROT_PACK = PACK_ACTIONS
STATE_ACTIONS.PLANET_PACK = PACK_ACTIONS
STATE_ACTIONS.SPECTRAL_PACK = PACK_ACTIONS
STATE_ACTIONS.STANDARD_PACK = PACK_ACTIONS
STATE_ACTIONS.BUFFOON_PACK = PACK_ACTIONS
STATE_ACTIONS.SMODS_BOOSTER_OPENED = PACK_ACTIONS

function Actions.get_action_defs(names)
  local action_set = build_action_set()
  local defs = {}
  for _, name in ipairs(names) do
    if action_set[name] then
      defs[#defs + 1] = action_set[name]
    end
  end
  return defs
end

function Actions.get_actions_for_state(state_name)
  local list = Actions.get_action_names_for_state(state_name)
  return Actions.get_action_defs(list)
end

function Actions.get_action_names_for_state(state_name)
  local list = STATE_ACTIONS[state_name]
  if not list and state_name and state_name:find("_PACK$") then
    list = PACK_ACTIONS
  end
  list = list or {}
  local res = {}
  local seen = {}
  for i = 1, #list do
    local name = list[i]
    if not seen[name] then
      res[#res + 1] = name
      seen[name] = true
    end
  end
  for i = 1, #UNIVERSAL_ACTIONS do
    local name = UNIVERSAL_ACTIONS[i]
    if not seen[name] then
      res[#res + 1] = name
      seen[name] = true
    end
  end
  return res
end

local HAND_ACTIONS = {
  highlight_card = true, unhighlight_all = true, set_hand_highlight = true,
  clear_hand_highlight = true, play_cards_from_highlighted = true,
  discard_cards_from_highlighted = true, hand_details = true,
}

function Actions.is_action_valid(action_name)
  if HAND_ACTIONS[action_name] then
    if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
      return false
    end
  end

  if action_name == "joker_info" or action_name == "joker_strategy" or action_name == "set_joker_order" then
    if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
      return false
    end
  end

  if action_name == "sell_card" then
    local has_jokers = G and G.jokers and G.jokers.cards and #G.jokers.cards > 0
    local has_consumables = G and G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0
    if not has_jokers and not has_consumables then
      return false
    end
  end

  if action_name == "consumables_info" then
    if not G or not G.consumeables or not G.consumeables.cards or #G.consumeables.cards == 0 then
      return false
    end
  end

  if action_name == "blind_info" then
    if not (G and G.GAME and G.GAME.blind and G.GAME.current_round) then
      return false
    end
  end

  if action_name == "use_card" then
    local function has_cards(area)
      return area and area.cards and #area.cards > 0
    end
    local has_any =
      has_cards(G and G.consumeables)
      or has_cards(G and G.booster_pack)
      or has_cards(G and G.shop_booster)
    if not has_any then
      return false
    end
  end

  if action_name == "buy_from_shop" then
    if not (G and G.GAME and G.GAME.dollars ~= nil) then
      return false
    end
    local reserved = tonumber(G.NEURO.reserved_dollars or 0) or 0
    local money = get_spendable_dollars() - reserved
    local function has_affordable(area)
      if not (area and area.cards and #area.cards > 0) then return false end
      for _, card in ipairs(area.cards) do
        local cost = card and card.cost or 0
        if type(cost) == "number" and cost <= money then
          return true
        end
      end
      return false
    end
    if not (has_affordable(G.shop_jokers) or has_affordable(G.shop_vouchers) or has_affordable(G.shop_booster)) then
      return false
    end
  end

  if action_name == "start_challenge_run" then
    if not (G and G.challenge_tab and G.CHALLENGES and G.CHALLENGES[G.challenge_tab]) then
      return false
    end
  end

  if action_name == "reroll_shop" then
    if not G or not G.GAME or not G.GAME.dollars then return false end
    local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost or 0
    if type(cost) ~= "number" or cost < 0 then
      return false
    end
    if get_spendable_dollars() < cost then
      return false
    end
    if early_shop_buy_priority_active() then
      return false
    end
  end

  if action_name == "skip_blind" then
    local on_deck = get_selectable_blind_key()
    if on_deck == nil or on_deck == "Boss" then
      return false
    end

    local opt = G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
    if not (opt and type(opt.get_UIE_by_ID) == "function") then
      return false
    end
    local tag = opt:get_UIE_by_ID("tag_container")
    if not (tag and tag.config and tag.config.ref_table) then
      return false
    end
  end

  if action_name == "exit_overlay_menu" then
    if not (G and G.OVERLAY_MENU) then
      return false
    end
  end

  if action_name == "reroll_boss" then
    if not G or not G.GAME then
      return false
    end
    local bankroll = (G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0)
    if bankroll < 10 then
      return false
    end
    local used = G.GAME.used_vouchers or {}
    local has_retcon = used["v_retcon"]
    local has_directors_cut = used["v_directors_cut"]
    local boss_rerolled = G.GAME.round_resets and G.GAME.round_resets.boss_rerolled
    local enabled = has_retcon or (has_directors_cut and not boss_rerolled)
    if not enabled then
      return false
    end
  end

  if action_name == "select_blind" then
    if not G or not G.GAME then
      return false
    end
  end

  return true
end

function Actions.get_valid_actions_for_state(state_name)
  local all_actions = Actions.get_action_names_for_state(state_name)
  local valid_actions = {}

  for _, action_name in ipairs(all_actions) do
    if Actions.is_action_valid(action_name) then
      table.insert(valid_actions, action_name)
    end
  end

  return valid_actions
end

local _state_action_sets = {}

function Actions.get_state_action_set(state_name)
  if not state_name then return {} end
  if _state_action_sets[state_name] then return _state_action_sets[state_name] end
  local list = STATE_ACTIONS[state_name]
  if not list and state_name:find("_PACK$") then
    list = PACK_ACTIONS
  end
  list = list or {}
  local set = {}
  for i = 1, #list do
    set[list[i]] = true
  end
  for i = 1, #UNIVERSAL_ACTIONS do
    set[UNIVERSAL_ACTIONS[i]] = true
  end
  _state_action_sets[state_name] = set
  return set
end

local _static_actions_cache = nil

function Actions.get_static_actions()
  if _static_actions_cache then return _static_actions_cache end
  local action_set = build_action_set()
  local res = {}
  for _, def in pairs(action_set) do
    res[#res + 1] = def
  end
  table.sort(res, function(a, b) return a.name < b.name end)
  _static_actions_cache = res
  return res
end

function Actions.get_all_actions()
  return Actions.get_static_actions()
end

return Actions
