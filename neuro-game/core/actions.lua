local Actions = {}
local CtxEconomy = require("context.ctx_economy")
local StateKinds = require("core.state_kinds")

local function action_def(name, description, schema)
  return {
    name = name,
    description = description or ("Trigger action " .. name .. "."),
    schema = schema or { type = "object" }
  }
end

local function generic_schema()
  return { type = "object", properties = {}, required = {} }
end

local function build_param_actions()
  return {
    select_blind = action_def("select_blind", "Select the active blind for this ante (small, big, or boss).", {
      type = "object",
      properties = { blind = { type = "string", enum = { "small", "big", "boss" }, description = "Which blind to select" } },
      required = { "blind" }
    }),
    use_card = action_def("use_card", "Use a card from a consumeables slot (C: rows) or an open pack, by area + 1-indexed index. For a consumable that targets hand cards, also pass hand_indices as 1-indexed H: positions.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "consumeables", "consumables", "booster_pack" }, description = "Which area the card is in (consumeables is the engine spelling; consumables is also accepted)" },
        index = { type = "integer", minimum = 1, description = "Card position (1-indexed from left to right)" },
        hand_indices = { type = "array", items = { type = "integer", minimum = 1 }, minItems = 1, maxItems = 5, uniqueItems = true, description = "Hand card positions to select for this consumable (for tarots that act on chosen cards)" }
      },
      required = { "area", "index" }
    }),
    buy_from_shop = action_def("buy_from_shop", "Buy an item from an I: shop row by area + 1-indexed index. For a targeted consumable, buy with use=false then drive it with use_card.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "shop_jokers", "shop_vouchers", "shop_booster" }, description = "Which shop section to buy from" },
        index = { type = "integer", minimum = 1, description = "Item position in shop (1-indexed from left)" },
        use = { type = "boolean", description = "Only for no-target consumables: use immediately after buying. Targeted consumables must be bought (use=false) then used via use_card + hand_indices; boosters and vouchers are always opened/redeemed automatically." }
      },
      required = { "area", "index" }
    }),
    sell_card = action_def("sell_card", "Sell a joker (J: rows) or consumable (C: rows) by area + 1-indexed index.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "jokers", "consumeables", "consumables" }, description = "Where the card is located (consumeables is the engine spelling; consumables is also accepted)" },
        index = { type = "integer", minimum = 1, description = "Card position to sell" }
      },
      required = { "area", "index" }
    }),
    play_hand = action_def("play_hand", "Play 1-5 hand cards immediately as a poker hand. This IS your move and is FINAL -- it uses one hand (H) and scores right away; it is not a preview. `indices` are the 1-indexed hand positions from the H: list. Judge the hand yourself from H:, the L: hand-type levels, and the Ready/Close facts before playing.", {
      type = "object",
      properties = {
        indices = {
          type = "array",
          description = "Hand positions to play (1-indexed, 1-5 cards)",
          items = { type = "integer", minimum = 1, description = "Card position" },
          minItems = 1, maxItems = 5, uniqueItems = true
        }
      },
      required = { "indices" }
    }),
    discard_hand = action_def("discard_hand", "Discard 1-5 hand cards immediately and draw the same number of replacements. This is FINAL and costs one discard (D), not a hand (H) -- discards are the cheap re-draw resource (only usable while D>0). `indices` are the 1-indexed hand positions from the H: list. Use it to throw away weak cards and draw toward a better hand.", {
      type = "object",
      properties = {
        indices = {
          type = "array",
          description = "Hand positions to discard (1-indexed, 1-5 cards)",
          items = { type = "integer", minimum = 1, description = "Card position" },
          minItems = 1, maxItems = 5, uniqueItems = true
        }
      },
      required = { "indices" }
    }),
    change_stake = action_def("change_stake", "Change run stake to a specific key.", {
      type = "object",
      properties = { to_key = { type = "integer", minimum = 1 } },
      required = { "to_key" }
    }),
    change_challenge_description = action_def("change_challenge_description", "Select a challenge by its id or displayed name (from the challenge list).", {
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
    paste_seed = action_def("paste_seed", "Paste a seed for a seeded run (1-8 letters/digits); omit seed to paste from the clipboard.", {
      type = "object",
      properties = { seed = { type = "string", minLength = 1, maxLength = 8, description = "Seed string to paste for a seeded run (1-8 letters/digits); omit to paste from clipboard" } },
      required = {}
    }),
    get_poker_hand_information = action_def("get_poker_hand_information", "Get information about all poker hand types and their levels.", {
      type = "object",
      properties = {},
      required = {}
    }),
    joker_info = action_def("joker_info", "Get information about the jokers currently in your run.", {
      type = "object",
      properties = {},
      required = {}
    }),
    card_modifiers_information = action_def("card_modifiers_information", "Get a count of the editions, seals, and enhancements on your deck's cards.", {
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
    scoring_explanation = action_def("scoring_explanation", "Get detailed scoring mechanics and formula.", {
      type = "object",
      properties = {},
      required = {}
    }),
    simulate_hand = action_def("simulate_hand", "Preview a hypothetical selection WITHOUT playing it: reports the poker hand type, its base chips/mult at the current level, which cards score, and any debuff warning. Use it to compare candidate plays before committing; jokers and card editions still decide the real total. Pass `indices` (1-indexed).", {
      type = "object",
      properties = {
        indices = { type = "array", description = "Card positions to preview (1-indexed)", items = { type = "integer", minimum = 1 }, minItems = 1, maxItems = 5, uniqueItems = true }
      },
      required = { "indices" }
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
    owned_vouchers = action_def("owned_vouchers", "Show all owned vouchers and their effects.", {
      type = "object",
      properties = {},
      required = {}
    }),
    round_history = action_def("round_history", "Show the count of hands played and discards used this round.", {
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
    help = action_def("help", "List all available actions and info commands.", {
      type = "object",
      properties = {},
      required = {}
    }),
  }
end

local get_spendable_dollars = CtxEconomy.spendable

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
Actions.get_selectable_blind_key = get_selectable_blind_key

local CardUtil = require("facts.card_util")
local can_buy_card_space = CardUtil.can_buy_card_space
local can_take_pack_card = CardUtil.can_take_pack_card
local consumable_usable_now = CardUtil.consumable_usable_now

local SIMPLE_ACTION_DESCS = {
  reroll_shop = "Replace all current shop items (jokers, vouchers, packs) with a new random set; each reroll costs money and the price rises each time this shop visit.",
  toggle_shop = "Exit shop and continue run flow.",
  skip_blind = "Skip current blind and take skip reward.",
  reroll_boss = "Reroll current boss blind when available.",
  skip_booster = "Skip current booster pack.",
  exit_overlay_menu = "Close an open overlay/popup menu and continue.",
  cash_out = "Collect round payout and continue to shop flow.",
  setup_run = "Open the run setup screen to choose your deck, stake, and seed before starting a run.",
  start_challenge_run = "Start a challenge run with preset rules and restrictions.",
  start_setup_run = "Start a run from the setup screen with your chosen options.",
  toggle_seeded_run = "Toggle seeded run mode on or off for reproducible games.",
  copy_seed = "Copy the current run seed to clipboard.",
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
    "toggle_seeded_run",
    "paste_seed",
    "start_setup_run",
    "help",
  },
  MENU = {
    "choose_persona",
    "setup_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_stake",
    "change_selected_back",
    "start_setup_run",
    "change_challenge_description",
    "start_challenge_run",
    "help",
  },
  RUN_SETUP = {
    "choose_persona",
    "setup_run",
    "start_setup_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_stake",
    "change_selected_back",
    "change_viewed_back",
    "change_viewed_collab",
    "help",
  },
  GAME_OVER = {
    "choose_persona",
    "setup_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_selected_back",
    "start_setup_run",
    "help",
  },
  BLIND_SELECT = {
    "select_blind",
    "skip_blind",
    "reroll_boss",
    "sell_card",
    "use_card",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "blind_info",
    "scoring_explanation",
    "hand_levels_info",
    "consumables_info",
    "quick_status",
    "full_game_context",
    "help",
  },
  SELECTING_HAND = {
    "play_hand",
    "discard_hand",
    "use_card",
    "sort_hand_suit",
    "sort_hand_value",
    "get_poker_hand_information",
    "simulate_hand",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "scoring_explanation",
    "set_joker_order",
    "blind_info",
    "hand_levels_info",
    "quick_status",
    "full_game_context",
    "consumables_info",
    "hand_details",
    "owned_vouchers",
    "round_history",
    "help",
  },
  SHOP = {
    "buy_from_shop",
    "sell_card",
    "use_card",
    "reroll_shop",
    "toggle_shop",
    "set_joker_order",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "shop_context",
    "scoring_explanation",
    "blind_info",
    "quick_status",
    "full_game_context",
    "consumables_info",
    "owned_vouchers",
    "help",
  },
  ROUND_EVAL = {
    "cash_out",
    "get_poker_hand_information",
    "joker_info",
    "card_modifiers_information",
    "deck_type",
    "scoring_explanation",
    "hand_levels_info",
    "quick_status",
    "full_game_context",
    "consumables_info",
    "owned_vouchers",
    "round_history",
    "help",
  },
}

local PACK_ACTIONS = {
  "use_card",
  "sell_card",
  "skip_booster",
  "get_poker_hand_information",
  "joker_info",
  "card_modifiers_information",
  "scoring_explanation",
  "owned_vouchers",
  "hand_details",
  "help",
}
STATE_ACTIONS.TAROT_PACK = PACK_ACTIONS
STATE_ACTIONS.PLANET_PACK = PACK_ACTIONS
STATE_ACTIONS.SPECTRAL_PACK = PACK_ACTIONS
STATE_ACTIONS.STANDARD_PACK = PACK_ACTIONS
STATE_ACTIONS.BUFFOON_PACK = PACK_ACTIONS
STATE_ACTIONS.SMODS_BOOSTER_OPENED = PACK_ACTIONS

function Actions.get_action_names_for_state(state_name)
  local list = STATE_ACTIONS[state_name]
  if not list and StateKinds.is_pack_state(state_name) then
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
  hand_details = true,
  simulate_hand = true,
}

function Actions.is_action_valid(action_name)
  -- choose_persona is dead once persona ~= "hiyori" (dispatcher rejects it); hide it to avoid a locked-choice retry
  if action_name == "choose_persona" then
    if G and G.NEURO and G.NEURO.persona and G.NEURO.persona ~= "hiyori" then
      return false
    end
  end

  if HAND_ACTIONS[action_name] then
    if not G or not G.hand or not G.hand.cards or #G.hand.cards == 0 then
      return false
    end
  end

  if action_name == "play_hand" or action_name == "discard_hand" then
    if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
      return false
    end
    local cr = G.GAME and G.GAME.current_round
    if action_name == "play_hand" and (not cr or (cr.hands_left or 0) <= 0) then
      return false
    end
    if action_name == "discard_hand" and (not cr or (cr.discards_left or 0) <= 0) then
      return false
    end
  end

  if action_name == "joker_info" then
    if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
      return false
    end
  end

  if action_name == "set_joker_order" then
    if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 2 then
      return false
    end
  end

  if action_name == "sell_card" then
    -- jokers/consumables can only be sold between rounds, never during SELECTING_HAND
    if require("core.state").get_state_name() == "SELECTING_HAND" then
      return false
    end
    local has_sellable_joker = false
    if G and G.jokers and G.jokers.cards then
      for _, c in ipairs(G.jokers.cards) do
        if not (c.ability and c.ability.eternal) then has_sellable_joker = true break end
      end
    end
    local has_consumables = G and G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0
    if not has_sellable_joker and not has_consumables then
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
    -- a creator consumable (Judgement/Soul/Emperor/Fool) blocked by a full output slot must not count as usable
    local function has_usable_consumable(area)
      if not (area and area.cards and #area.cards > 0) then return false end
      for _, card in ipairs(area.cards) do
        if consumable_usable_now(card) then return true end
      end
      return false
    end
    local function has_takeable_pack_card(area)
      if not (area and area.cards and #area.cards > 0) then return false end
      for _, card in ipairs(area.cards) do
        if can_take_pack_card(card) then return true end
      end
      return false
    end
    local has_any =
      has_usable_consumable(G and G.consumeables)
      or has_takeable_pack_card(G and G.booster_pack)
      or has_takeable_pack_card(G and G.pack_cards)
    if not has_any then
      return false
    end
  end

  if action_name == "buy_from_shop" then
    if not (G and G.GAME and G.GAME.dollars ~= nil) then
      return false
    end
    local money = get_spendable_dollars()
    local function has_affordable(area, area_name)
      if not (area and area.cards and #area.cards > 0) then return false end
      for _, card in ipairs(area.cards) do
        local cost = tonumber(card and card.cost or 0) or 0
        if cost >= 0 and cost <= money and can_buy_card_space(card, area_name) then
          return true
        end
      end
      return false
    end
    if not (has_affordable(G.shop_jokers, "shop_jokers")
        or has_affordable(G.shop_vouchers, "shop_vouchers")
        or has_affordable(G.shop_booster, "shop_booster")) then
      return false
    end
  end

  if action_name == "change_challenge_description" then
    if not (G and G.CHALLENGES and #G.CHALLENGES > 0) then
      return false
    end
  end

  if action_name == "start_challenge_run" then
    local tab = G and G.challenge_tab
    local selected = type(tab) == "table"
      or (type(tab) == "number" and G.CHALLENGES and G.CHALLENGES[tab] ~= nil)
    if not selected then
      return false
    end
  end

  if action_name == "copy_seed" then
    if not (G and G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed) then
      return false
    end
    if not (G.FUNCS and type(G.FUNCS.copy_seed) == "function") then
      return false
    end
  end

  if action_name == "toggle_seeded_run" or action_name == "paste_seed"
    or action_name == "start_setup_run" then
    if not StateKinds.is_run_setup_overlay() then
      return false
    end
  end

  if action_name == "sort_hand_suit" or action_name == "sort_hand_value" then
    if not (G and G.hand and G.hand.cards and #G.hand.cards >= 2) then
      return false
    end
  end

  if action_name == "reroll_shop" then
    if not G or not G.GAME or not G.GAME.dollars then return false end
    local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost or 0
    if type(cost) ~= "number" or cost < 0 then
      return false
    end
    local spendable = get_spendable_dollars()
    local free = tonumber(G.GAME.current_round and G.GAME.current_round.free_rerolls or 0) or 0
    -- engine forces reroll_cost=0 whenever free_rerolls>0, so a free reroll is always allowed
    if free <= 0 then
      if spendable < cost then
        return false
      end
      -- mod-only guard: blocks a paid reroll if nothing in the current shop is currently buyable
      local cheapest
      local function scan(area, area_name)
        if not (area and area.cards) then return end
        for _, card in ipairs(area.cards) do
          local c = tonumber(card and card.cost or 0) or 0
          if c >= 0 and can_buy_card_space(card, area_name) and (not cheapest or c < cheapest) then
            cheapest = c
          end
        end
      end
      scan(G.shop_jokers, "shop_jokers")
      scan(G.shop_vouchers, "shop_vouchers")
      scan(G.shop_booster, "shop_booster")
      if cheapest and (spendable - cost) < cheapest then
        return false
      end
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
    if not CtxEconomy.can_reroll_boss() then
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

local INFO_ACTIONS = {
  help = true, quick_status = true, full_game_context = true,
  shop_context = true, owned_vouchers = true, round_history = true,
  scoring_explanation = true, simulate_hand = true,
  consumables_info = true, blind_info = true, hand_levels_info = true, hand_details = true,
  get_poker_hand_information = true, joker_info = true, card_modifiers_information = true,
  deck_type = true,
}

function Actions.get_available_actions_for_state(state_name)
  local out = {}
  for _, name in ipairs(Actions.get_valid_actions_for_state(state_name)) do
    if not INFO_ACTIONS[name] then out[#out + 1] = name end
  end
  return out
end

local _state_action_sets = {}

function Actions.get_state_action_set(state_name)
  if not state_name then return {} end
  if _state_action_sets[state_name] then return _state_action_sets[state_name] end
  local list = STATE_ACTIONS[state_name]
  if not list and StateKinds.is_pack_state(state_name) then
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

Actions.INFO_ACTIONS = INFO_ACTIONS

return Actions
