local M = {}

local NON_PROGRESS = {
  help = true,
  quick_status = true,
  shop_context = true,
  deck_composition = true,
  owned_vouchers = true,
  round_history = true,
  neuratro_info = true,
  scoring_explanation = true,
  joker_strategy = true,
  consumables_info = true,
  blind_info = true,
  hand_levels_info = true,
  hand_details = true,
  get_poker_hand_information = true,
  joker_info = true,
  card_modifiers_information = true,
  deck_type = true,
  full_game_context = true,
  evaluate_play = true,
  simulate_hand = true,
  clear_hand_highlight = true,
  reorder_hand_cards = true,
  set_joker_order = true,
  copy_seed = true,
}


local function make_card(overrides)
  local c = {
    cost = 0,
    ability = { set = "Default", name = "Mock" },
    config = { center = {} },
    base = { value = "10", suit = "Hearts" },
  }
  if overrides then
    for k, v in pairs(overrides) do c[k] = v end
  end
  return c
end

local SAVE_KEYS = {
  "GAME", "hand", "jokers", "consumeables",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack", "shop",
  "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "challenge_tab", "CHALLENGES",
  "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS",
}

local NEURO_SAVE_FIELDS = {
  "persona", "deck_chosen", "reserved_dollars",
  "shop_reroll_count", "rules_sent",
  "blind_info_sig", "blind_info_seen",
  "sim1_play", "dr_top", "pack_best",
  "state_entry_hints",
}

local SENTINEL = {}

local function snapshot()
  local snap = {}
  for _, k in ipairs(SAVE_KEYS) do
    local v = G[k]
    snap[k] = (v == nil) and SENTINEL or v
  end
  if G.NEURO then
    snap._neuro = {}
    for _, k in ipairs(NEURO_SAVE_FIELDS) do
      local v = G.NEURO[k]
      snap._neuro[k] = (v == nil) and SENTINEL or v
    end
  end
  return snap
end

local function restore(snap)
  for _, k in ipairs(SAVE_KEYS) do
    local v = snap[k]
    if v == SENTINEL then
      G[k] = nil
    else
      G[k] = v
    end
  end
  if G.NEURO and snap._neuro then
    for _, k in ipairs(NEURO_SAVE_FIELDS) do
      local v = snap._neuro[k]
      if v == SENTINEL then
        G.NEURO[k] = nil
      else
        G.NEURO[k] = v
      end
    end
  end
end

local function apply_mock(mock)
  G.NEURO = G.NEURO or {}
  for k, v in pairs(mock) do
    local nf = k:match("^NEURO_(.+)$")
    if nf then
      G.NEURO[nf:lower()] = v
    else
      G[k] = v
    end
  end
end

local function has_progress(actions)
  if not actions then return false end
  for _, name in ipairs(actions) do
    if type(name) == "string" and not NON_PROGRESS[name] then
      return true
    end
  end
  return false
end

local function base_game()
  return {
    dollars = 10,
    bankrupt_at = 0,
    current_round = {
      hands_left = 4,
      discards_left = 3,
      reroll_cost = 5,
    },
    round_resets = {
      ante = 3,
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
      blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" },
      boss_rerolled = false,
    },
    blind = { chips = 300, mult = 1 },
    blind_on_deck = "Boss",
    chips = 0,
    used_vouchers = {},
    stake = 1,
    pack_choices = 1,
  }
end

local function cards5()
  local t = {}
  for i = 1, 5 do t[i] = make_card() end
  return t
end

local function make_blind_select_opts(blind_key)
  local function make_opt()
    return {
      get_UIE_by_ID = function(_, id)
        if id == "tag_container" then
          return { config = { ref_table = { tag = { name = "Tag" } } } }
        end
        return nil
      end,
    }
  end
  local opts = {}
  if blind_key == "Small" or blind_key == "all" then opts.small = make_opt() end
  if blind_key == "Big" or blind_key == "all" then opts.big = make_opt() end
  if blind_key == "Boss" or blind_key == "all" then opts.boss = make_opt() end
  return opts
end

local SCENARIOS = {

  { state = "SELECTING_HAND", desc = "Normal: 5 cards, 4 hands, 3 discards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SIM1_PLAY = nil,
        NEURO_DR_TOP = nil,
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "No hands left, has discards",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 0
      g.current_round.discards_left = 3
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Has hands, no discards",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 4
      g.current_round.discards_left = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "No hands AND no discards (handler returns nil)",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 0
      g.current_round.discards_left = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Empty hand cards (all HAND_ACTIONS blocked)",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Has usable consumable",
    mock = function()
      local con = make_card({
        ability = {
          set = "Tarot",
          name = "The Fool",
          consumeable = { max_highlighted = 2, min_highlighted = 1 },
        },
      })
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },


  { state = "SHOP", desc = "Normal: affordable joker, affordable booster, $10",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 4 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 3, ability = { set = "Booster", name = "Arcana Pack" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "$0 nothing affordable, has jokers to sell",
    mock = function()
      local g = base_game()
      g.dollars = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card({ cost = 3 }) }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 4, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "$0 nothing to sell (toggle_shop must survive)",
    mock = function()
      local g = base_game()
      g.dollars = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Early game must_buy_phase: ante=1, affordable booster",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 4, ability = { set = "Booster", name = "Arcana Pack" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Must_buy_phase but nothing actually buyable",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      g.dollars = 2
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card(), make_card(), make_card(), make_card(), make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 4, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Full joker slots: 5/5, affordable jokers in shop",
    mock = function()
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card({ cost = 3 }) end
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 4 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Reroll blocked by early_shop_buy_priority",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 3, ability = { set = "Booster", name = "Buffoon Pack" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Everything blocked except toggle_shop",
    mock = function()
      local g = base_game()
      g.dollars = 0
      return {
        GAME = g,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },


  { state = "BLIND_SELECT", desc = "Small blind selectable",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = "Small"
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Small"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Boss blind only (no skip, no reroll voucher)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.blind_on_deck = "Boss"
      g.used_vouchers = {}
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Boss with directors_cut (not yet rerolled)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.round_resets.boss_rerolled = false
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_directors_cut = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Boss with retcon voucher, $10+",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_retcon = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "No blind_choices (edge case nil)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_choices = nil
      g.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = "Small"
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Small"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },


  { state = "TAROT_PACK", desc = "Has pack cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card(), make_card(), make_card() } },
        booster_pack = { cards = { make_card(), make_card(), make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "A" },
      }
    end,
  },

  { state = "TAROT_PACK", desc = "Empty pack cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = {} },
        booster_pack = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = nil,
      }
    end,
  },

  { state = "TAROT_PACK", desc = "No pack area at all (nil)",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = nil,
        booster_pack = nil,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = nil,
      }
    end,
  },

  { state = "BUFFOON_PACK", desc = "BUFFOON_PACK variant with pack cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card() } },
        booster_pack = { cards = { make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "B" },
      }
    end,
  },


  { state = "ROUND_EVAL", desc = "Normal: cash_out available",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "ROUND_EVAL", desc = "Minimal state: only G.GAME set",
    mock = function()
      return {
        GAME = base_game(),
        hand = nil,
        jokers = nil,
        consumeables = nil,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },


  { state = "GAME_OVER", desc = "No overlay (setup_run must work)",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "GAME_OVER", desc = "With overlay present",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "GAME_OVER", desc = "Persona gate: NEURO_PERSONA=hiyori",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "hiyori",
      }
    end,
  },


  { state = "MENU", desc = "Normal: has G.GAME",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "MENU", desc = "Overlay present",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },


  { state = "SPLASH", desc = "Normal: minimal state",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SPLASH", desc = "Overlay present",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },


  { state = "RUN_SETUP", desc = "Normal: G.GAME set, no overlay",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_DECK_CHOSEN = true,
      }
    end,
  },

  { state = "RUN_SETUP", desc = "Run setup overlay active",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {
          get_UIE_by_ID = function(_, id)
            if id == "run_setup_seed" then return {} end
            return nil
          end,
        },
        NEURO_PERSONA = "neuro",
        NEURO_DECK_CHOSEN = false,
        P_CENTER_POOLS = {
          Back = {
            { key = "b_red", unlocked = true, name = "Red Deck" },
            { key = "b_blue", unlocked = true, name = "Blue Deck" },
          },
        },
      }
    end,
  },

  { state = "SHOP", desc = "Reserved dollars blocks all purchases",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 4 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 3, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 10,
      }
    end,
  },

  { state = "SHOP", desc = "Completely empty shop areas",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Only vouchers affordable (no jokers/boosters)",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 99 }) } },
        shop_vouchers = { cards = { make_card({ cost = 8, ability = { set = "Voucher" } }) } },
        shop_booster = { cards = { make_card({ cost = 99, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Ante=2 early shop priority",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 2
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 4, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Bankrupt: bankrupt_at > dollars",
    mock = function()
      local g = base_game()
      g.dollars = 3
      g.bankrupt_at = 5
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card({ cost = 2 }) }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 1 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Has consumables to use in shop",
    mock = function()
      local g = base_game()
      g.dollars = 0
      local con = make_card({ ability = { set = "Planet", name = "Mercury", consumeable = { hand_type = "Pair" } } })
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Must_buy_phase + only sellable is consumable",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      local con = make_card({ cost = 2, ability = { set = "Tarot", name = "The Fool" } })
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 4, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Free items in shop (cost=0)",
    mock = function()
      local g = base_game()
      g.dollars = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 0 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Free reroll but early_shop blocks it",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      g.current_round.reroll_cost = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = { make_card({ cost = 3, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Full slots everywhere, $0, empty shop",
    mock = function()
      local g = base_game()
      g.dollars = 0
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card() end
      local cons = {}
      for i = 1, 2 do cons[i] = make_card({ ability = { set = "Tarot" } }) end
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = cons, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Nil shop areas (not initialized)",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = nil,
        shop_vouchers = nil,
        shop_booster = nil,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Single card in hand",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = { make_card() }, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Last hand, no discards, score already won",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 1
      g.current_round.discards_left = 0
      g.chips = 999
      g.blind = { chips = 300, mult = 1 }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "No blind set (G.GAME.blind=nil)",
    mock = function()
      local g = base_game()
      g.blind = nil
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Empty hand + no jokers + no consumables + 0/0",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 0
      g.current_round.discards_left = 0
      return {
        GAME = g,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Has consumable but hand is empty",
    mock = function()
      local con = make_card({ ability = { set = "Planet", name = "Jupiter", consumeable = { hand_type = "Flush" } } })
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Full jokers, no consumables, 1 hand left",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 1
      g.current_round.discards_left = 0
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card() end
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "G.GAME.current_round is nil",
    mock = function()
      local g = base_game()
      g.current_round = nil
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Big blind selectable (can skip)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Select", Boss = "Upcoming" }
      g.blind_on_deck = "Big"
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Big"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Directors cut already used (boss_rerolled=true)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.round_resets.boss_rerolled = true
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_directors_cut = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Retcon but too poor to reroll ($5)",
    mock = function()
      local g = base_game()
      g.dollars = 5
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_retcon = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "No blind_select_opts (nil)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = "Small"
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = nil,
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "No blind_states (nil round_resets)",
    mock = function()
      local g = base_game()
      g.round_resets = nil
      g.blind_on_deck = nil
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = nil,
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "All blind_states are Upcoming (none selectable)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = nil
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("all"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SPECTRAL_PACK", desc = "SPECTRAL_PACK with cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card() } },
        booster_pack = { cards = { make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "S" },
      }
    end,
  },

  { state = "PLANET_PACK", desc = "PLANET_PACK with cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card(), make_card() } },
        booster_pack = { cards = { make_card(), make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "A" },
      }
    end,
  },

  { state = "STANDARD_PACK", desc = "STANDARD_PACK with cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card(), make_card(), make_card() } },
        booster_pack = { cards = { make_card(), make_card(), make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 2, rank = "B" },
      }
    end,
  },

  { state = "SMODS_BOOSTER_OPENED", desc = "SMODS_BOOSTER_OPENED with cards",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card() } },
        booster_pack = { cards = { make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "C" },
      }
    end,
  },

  { state = "TAROT_PACK", desc = "Full consumable slots during pack",
    mock = function()
      local cons = {}
      for i = 1, 2 do cons[i] = make_card({ ability = { set = "Tarot" } }) end
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = cons, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card(), make_card() } },
        booster_pack = { cards = { make_card(), make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "B" },
      }
    end,
  },

  { state = "BUFFOON_PACK", desc = "Full joker slots during buffoon pack",
    mock = function()
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card() end
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card() } },
        booster_pack = { cards = { make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "A" },
      }
    end,
  },

  { state = "GAME_OVER", desc = "Persona nil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = nil,
      }
    end,
  },

  { state = "GAME_OVER", desc = "Persona evil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "evil",
      }
    end,
  },

  { state = "GAME_OVER", desc = "No G.GAME at all",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "MENU", desc = "No G.GAME at all",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "MENU", desc = "Persona nil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = nil,
      }
    end,
  },

  { state = "SPLASH", desc = "Persona nil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = nil,
      }
    end,
  },

  { state = "SPLASH", desc = "Persona evil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "evil",
      }
    end,
  },

  { state = "SPLASH", desc = "No G.GAME at all",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "ROUND_EVAL", desc = "With overlay blocking",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "ROUND_EVAL", desc = "No G.GAME",
    mock = function()
      return {
        GAME = nil,
        hand = nil,
        jokers = nil,
        consumeables = nil,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "RUN_SETUP", desc = "Overlay with deck already chosen",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {
          get_UIE_by_ID = function(_, id)
            if id == "run_setup_seed" then return {} end
            return nil
          end,
        },
        NEURO_PERSONA = "neuro",
        NEURO_DECK_CHOSEN = true,
        P_CENTER_POOLS = {
          Back = {
            { key = "b_red", unlocked = true, name = "Red Deck" },
          },
        },
      }
    end,
  },

  { state = "RUN_SETUP", desc = "No P_CENTER_POOLS",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {
          get_UIE_by_ID = function(_, id)
            if id == "run_setup_seed" then return {} end
            return nil
          end,
        },
        NEURO_PERSONA = "neuro",
        NEURO_DECK_CHOSEN = false,
        P_CENTER_POOLS = nil,
      }
    end,
  },

  { state = "SHOP", desc = "G.GAME is nil",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = {} },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Ante 1 only jokers affordable but slots full",
    mock = function()
      local g = base_game()
      g.round_resets.ante = 1
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card() end
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 3 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "All shop items unaffordable, high reroll cost",
    mock = function()
      local g = base_game()
      g.dollars = 3
      g.current_round.reroll_cost = 10
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card({ cost = 2 }) }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 5 }) } },
        shop_vouchers = { cards = { make_card({ cost = 10, ability = { set = "Voucher" } }) } },
        shop_booster = { cards = { make_card({ cost = 6, ability = { set = "Booster" } }) } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 5,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SHOP", desc = "Has both jokers and consumables to sell",
    mock = function()
      local g = base_game()
      g.dollars = 0
      local con = make_card({ cost = 3, ability = { set = "Tarot", name = "Strength" } })
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card({ cost = 4 }) }, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 8 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "G.GAME is nil",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "G.hand is nil entirely",
    mock = function()
      return {
        GAME = base_game(),
        hand = nil,
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Has jokers + consumable, 0 hands, 0 discards",
    mock = function()
      local g = base_game()
      g.current_round.hands_left = 0
      g.current_round.discards_left = 0
      local con = make_card({ ability = { set = "Tarot", name = "The Star", consumeable = { max_highlighted = 3, min_highlighted = 1 } } })
      local jokers = {}
      for i = 1, 3 do jokers[i] = make_card() end
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = { con }, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "2 cards in hand, full jokers, full consumables",
    mock = function()
      local jokers = {}
      for i = 1, 5 do jokers[i] = make_card() end
      local cons = {}
      for i = 1, 2 do cons[i] = make_card({ ability = { set = "Planet", name = "Mars", consumeable = { hand_type = "Pair" } } }) end
      return {
        GAME = base_game(),
        hand = { cards = { make_card(), make_card() }, highlighted = {} },
        jokers = { cards = jokers, config = { card_limit = 5 } },
        consumeables = { cards = cons, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Has both directors_cut and retcon",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_directors_cut = true, v_retcon = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Boss rerolled with retcon (can reroll again)",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.round_resets.boss_rerolled = true
      g.blind_on_deck = "Boss"
      g.used_vouchers = { v_retcon = true }
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "G.GAME is nil",
    mock = function()
      return {
        GAME = nil,
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = nil,
        blind_select = nil,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "$0, boss only, no vouchers",
    mock = function()
      local g = base_game()
      g.dollars = 0
      g.round_resets.blind_states = { Small = "Skipped", Big = "Skipped", Boss = "Select" }
      g.blind_on_deck = "Boss"
      g.used_vouchers = {}
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Boss"),
        blind_select = true,
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "TAROT_PACK", desc = "pack_choices=0 (no picks left)",
    mock = function()
      local g = base_game()
      g.pack_choices = 0
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = { make_card({ ability = { set = "Tarot" } }) }, config = { card_limit = 2 } },
        pack_cards = { cards = { make_card() } },
        booster_pack = { cards = { make_card() } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = { index = 1, rank = "B" },
      }
    end,
  },

  { state = "SPECTRAL_PACK", desc = "Empty spectral pack",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = {} },
        booster_pack = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = nil,
      }
    end,
  },

  { state = "SMODS_BOOSTER_OPENED", desc = "Empty modded booster",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        pack_cards = { cards = {} },
        booster_pack = { cards = {} },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "neuro",
        NEURO_PACK_BEST = nil,
      }
    end,
  },

  { state = "GAME_OVER", desc = "Overlay + persona hiyori",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "hiyori",
      }
    end,
  },

  { state = "MENU", desc = "Persona evil",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "evil",
      }
    end,
  },

  { state = "MENU", desc = "Persona hiyori",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = nil,
        NEURO_PERSONA = "hiyori",
      }
    end,
  },

  { state = "MENU", desc = "Overlay + persona hiyori",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = {}, highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "hiyori",
      }
    end,
  },

  { state = "SELECTING_HAND", desc = "Overlay blocks during hand selection",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },

  { state = "SHOP", desc = "Overlay blocks during shop",
    mock = function()
      return {
        GAME = base_game(),
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = { make_card() }, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        shop_jokers = { cards = { make_card({ cost = 4 }) } },
        shop_vouchers = { cards = {} },
        shop_booster = { cards = {} },
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
        NEURO_SHOP_REROLL_COUNT = 0,
        NEURO_RESERVED_DOLLARS = 0,
      }
    end,
  },

  { state = "BLIND_SELECT", desc = "Overlay blocks during blind select",
    mock = function()
      local g = base_game()
      g.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = "Small"
      return {
        GAME = g,
        hand = { cards = cards5(), highlighted = {} },
        jokers = { cards = {}, config = { card_limit = 5 } },
        consumeables = { cards = {}, config = { card_limit = 2 } },
        blind_select_opts = make_blind_select_opts("Small"),
        blind_select = true,
        OVERLAY_MENU = {},
        NEURO_PERSONA = "neuro",
      }
    end,
  },
}

function M.run()
  local Dispatcher = G.NEURO.test_dispatcher
  local Actions = G.NEURO.test_actions

  if not Dispatcher or not Actions then
    print("[test] ERROR: G.NEURO.test_dispatcher or G.NEURO.test_actions not set.")
    print("[test] Make sure neuro-game.lua exposes these globals.")
    return
  end

  print("====================================================")
  print("[test] Deadlock test suite starting (" .. #SCENARIOS .. " scenarios)")
  print("====================================================")

  local pass, fail = 0, 0
  local failures = {}

  for i, sc in ipairs(SCENARIOS) do
    local snap = snapshot()
    local ok_outer, err_outer = pcall(function()
      apply_mock(sc.mock())

      G.NEURO.state_entry_hints = nil
      G.NEURO.blind_info_sig = nil
      G.NEURO.blind_info_seen = nil
      G.NEURO.rules_sent = true

      local force = Dispatcher.get_force_for_state(sc.state)
      local actions = force and force.actions or nil
      local found_progress = has_progress(actions)

      if not found_progress then
        local valid = Actions.get_valid_actions_for_state(sc.state)
        found_progress = has_progress(valid)
        if not found_progress then
          local action_str = "none"
          if valid and #valid > 0 then
            action_str = table.concat(valid, ", ")
          end
          local force_str = "nil"
          if actions and #actions > 0 then
            force_str = table.concat(actions, ", ")
          end
          fail = fail + 1
          failures[#failures + 1] = string.format(
            "  #%d [%s] %s\n      force_actions: %s\n      valid_actions: %s",
            i, sc.state, sc.desc, force_str, action_str
          )
          print(string.format("[test] FAIL #%02d [%s] %s", i, sc.state, sc.desc))
          return  -- pcall inner
        end
      end

      pass = pass + 1
      print(string.format("[test] PASS #%02d [%s] %s", i, sc.state, sc.desc))
    end)

    restore(snap)

    if not ok_outer then
      fail = fail + 1
      failures[#failures + 1] = string.format(
        "  #%d [%s] %s\n      ERROR: %s",
        i, sc.state, sc.desc, tostring(err_outer)
      )
      print(string.format("[test] FAIL #%02d [%s] %s  ERROR: %s", i, sc.state, sc.desc, tostring(err_outer)))
    end
  end

  print("====================================================")
  print(string.format("[test] Results: %d PASS, %d FAIL out of %d", pass, fail, #SCENARIOS))
  if #failures > 0 then
    print("[test] Failures:")
    for _, f in ipairs(failures) do
      print(f)
    end
  end
  print("====================================================")
  return fail
end

return M
