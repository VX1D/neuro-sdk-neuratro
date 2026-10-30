local M = {}

local next_sort_id = 0
local function make_card(overrides)
  next_sort_id = next_sort_id + 1
  local c = {
    cost = 0,
    sell_cost = 1,
    sort_id = next_sort_id,
    ability = { set = "Default", name = "Mock" },
    config = { center = {} },
    base = { value = "10", suit = "Hearts" },
  }
  if overrides then
    for k, v in pairs(overrides) do c[k] = v end
  end
  if c.base then require("tests.engine_hand_info").set_base(c) end
  return require("tests.engine_cards").card(c)
end

local function consumable(key, fields)
  fields = fields or {}
  next_sort_id = next_sort_id + 1
  fields.sort_id, fields.cost, fields.sell_cost = next_sort_id, fields.cost or 0, 1
  return require("tests.engine_cards").consumable(key, fields)
end

local function kind_card(set, key, name)
  if set ~= "Joker" then return consumable(key) end
  local c = make_card({ ability = { set = set, name = name }, config = { center = { key = key, set = set, name = name } } })
  c.base = nil
  return c
end

local SAVE_KEYS = {
  "STATES", "STATE", "GAME", "hand", "jokers", "consumeables",
  "shop_jokers", "shop_vouchers", "shop_booster",
  "pack_cards", "booster_pack", "shop",
  "blind_select_opts", "blind_select",
  "OVERLAY_MENU", "challenge_tab", "CHALLENGES",
  "P_CENTER_POOLS", "P_TAGS", "P_BLINDS", "SETTINGS",
}

local NEURO_SAVE_FIELDS = {
  "persona", "deck_chosen", "reserved_dollars",
  "shop_reroll_count",
  "blind_info_sig", "blind_info_seen",
  "state_entry_hints",
  "force_window",
  "last_failed_action", "last_failed_reason",
  "once_serials",
  "gameover_hold", "gameover_hold_until", "gameover_recovery", "gameover_exited_at",
}

local EXPLICIT_NIL = {}

local function snapshot()
  local snap = {}
  for _, k in ipairs(SAVE_KEYS) do
    local v = G[k]
    snap[k] = (v == nil) and EXPLICIT_NIL or v
  end
  if G.NEURO then
    snap._neuro = {}
    for _, k in ipairs(NEURO_SAVE_FIELDS) do
      local v = G.NEURO[k]
      snap._neuro[k] = (v == nil) and EXPLICIT_NIL or v
    end
  end
  return snap
end

local function restore(snap)
  for _, k in ipairs(SAVE_KEYS) do
    local v = snap[k]
    if v == EXPLICIT_NIL then
      G[k] = nil
    else
      G[k] = v
    end
  end
  if G.NEURO and snap._neuro then
    for _, k in ipairs(NEURO_SAVE_FIELDS) do
      local v = snap._neuro[k]
      if v == EXPLICIT_NIL then
        G.NEURO[k] = nil
      else
        G.NEURO[k] = v
      end
    end
  end
end

local function apply_mock(mock)
  G.NEURO = G.NEURO or {}
  if mock.P_BLINDS == nil then
    G.P_BLINDS = {
      bl_small = { name = "Small Blind" },
      bl_big = { name = "Big Blind" },
      bl_boss = { name = "Boss Blind" },
      bl_hook = { name = "The Hook" },
    }
  end
  for k, v in pairs(mock) do
    if v == EXPLICIT_NIL then v = nil end
    local nf = k:match("^NEURO_(.+)$")
    if nf then
      G.NEURO[nf:lower()] = v
    else
      G[k] = v
    end
  end
  if G.blind_select and not (G.FUNCS and G.FUNCS.select_blind) then
    G.FUNCS = G.FUNCS or {}
    G.FUNCS.select_blind = function() end
  end
  if mock.round_eval ~= nil and mock.round_eval ~= EXPLICIT_NIL and mock.I == nil then
    G.I = { UIBOX = {} }
    require("tests.helpers").cash_out_ready(G)
  end
  G.FUNCS = G.FUNCS or {}
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  if not G.FUNCS.toggle_shop then G.FUNCS.toggle_shop = function() end end
  if not G.FUNCS.cash_out then G.FUNCS.cash_out = function() end end
  if not G.FUNCS.skip_booster then G.FUNCS.skip_booster = function() end end
end

local function non_progress_set()
  return require("core.action_policy").NON_PROGRESS
end

local function has_progress(actions)
  if not actions then return false end
  local non_progress = non_progress_set()
  for _, name in ipairs(actions) do
    if type(name) == "string" and not non_progress[name] then
      return true
    end
  end
  return false
end

local function base_game()
  return {
    dollars = 10,
    bankrupt_at = 0,
    round = 7,
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

local function menu_game()
  local game = base_game()
  game.selected_back = { name = "Red Deck", effect = { center = { key = "b_red", name = "Red Deck" } } }
  return game
end

local run_setup_overlay = require("tests.helpers").run_setup_overlay
local options_overlay = require("tests.helpers").options_overlay
local game_over_overlay = require("tests.helpers").game_over_overlay
local unlock_overlay = require("tests.helpers").unlock_overlay

local function cards5()
  local t = {}
  for i = 1, 5 do t[i] = make_card() end
  return t
end
local function varied_cards(n)
  n = n or 5
  local vals = { "2", "7", "10", "Jack", "King", "3", "Queen" }
  local suits = { "Spades", "Hearts", "Diamonds", "Clubs", "Spades", "Hearts", "Diamonds" }
  local t = {}
  for i = 1, n do
    t[i] = make_card({ base = { value = vals[i], suit = suits[i] } })
  end
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

local function area(limit, cards) return { cards = cards or {}, config = { card_limit = limit } } end
local function held(cards, highlighted) return { cards = cards, highlighted = highlighted or {} } end
local function row(...) return { cards = { ... } } end
local function const(v) return function() return v end end
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
local function n_cards(n, overrides)
  local t = {}
  for i = 1, n do t[i] = make_card(overrides) end
  return t
end
local function n_consumables(n, key)
  local t = {}
  for i = 1, n do t[i] = consumable(key) end
  return t
end
local function booster(cost, name) return make_card({ cost = cost, ability = { set = "Booster", name = name } }) end
local function boss(name, key, extra)
  local b = { name = name, chips = 800, mult = 2, boss = true, debuff = {}, in_blind = true, key = key }
  for k, v in pairs(extra or {}) do b[k] = copy(v) end
  return b
end

local BOARD = {
  { "hand", function() return held({}) end },
  { "jokers", function() return area(5) end },
  { "consumeables", function() return area(2) end },
  { "NEURO_PERSONA", const("neuro") },
}
local function with(extra)
  local t = {}
  for _, d in ipairs(extra) do t[#t + 1] = d end
  for _, d in ipairs(BOARD) do t[#t + 1] = d end
  return t
end
local KINDS = {
  board = BOARD,
  hand = with({ { "hand", function() return held(cards5()) end } }),
  shop = with({
    { "shop", function() return {} end },
    { "shop_jokers", function() return row() end },
    { "shop_vouchers", function() return row() end },
    { "shop_booster", function() return row() end },
    { "NEURO_SHOP_REROLL_COUNT", const(0) },
    { "NEURO_RESERVED_DOLLARS", const(0) },
  }),
  blind = with({ { "blind_select", const(true) } }),
  menu = {
    { "hand", const(EXPLICIT_NIL) },
    { "jokers", const(EXPLICIT_NIL) },
    { "consumeables", const(EXPLICIT_NIL) },
    { "NEURO_PERSONA", const("neuro") },
  },
}

local function mock(kind, game, extras)
  return function()
    local m = extras and extras() or {}
    if m.GAME == nil then
      if game == EXPLICIT_NIL then
        m.GAME = EXPLICIT_NIL
      else
        m.GAME = base_game()
        if game then game(m.GAME) end
      end
    end
    for _, d in ipairs(KINDS[kind]) do
      if m[d[1]] == nil then m[d[1]] = d[2]() end
    end
    return m
  end
end

local function set(fields)
  return function()
    local t = {}
    for k, v in pairs(fields) do t[k] = v end
    return t
  end
end
local function opts(key) return function() return { blind_select_opts = make_blind_select_opts(key) } end end
local function rounds(hands, discards)
  return function(g) g.current_round.hands_left, g.current_round.discards_left = hands, discards end
end
local function open_small(g)
  g.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
  g.blind_on_deck = "Small"
end
local function vouchers(v) return function(g) g.used_vouchers = copy(v) end end
local function shop_money(dollars, reroll_cost, free_rerolls)
  return function(g) g.dollars, g.current_round.reroll_cost, g.current_round.free_rerolls = dollars, reroll_cost, free_rerolls end
end
local function dollars(n) return function(g) g.dollars = n end end
local function ante(n) return function(g) g.round_resets.ante = n end end
local function blind_of(name, key, extra) return function(g) g.blind = boss(name, key, extra) end end

local SCENARIOS = {

  { state = "SELECTING_HAND", desc = "Normal: 5 cards, 4 hands, 3 discards", progress = { "discard_hand", "play_hand" },
    mock = mock("hand") },

  { state = "SELECTING_HAND", desc = "Amber Acorn: the boss that names reordering", progress = { "discard_hand", "play_hand" },
    mock = mock("hand", blind_of("Amber Acorn", "bl_final_acorn"), function() return {
      jokers = area(5, {
        { sort_id = 801, ability = { set = "Joker", name = "A" }, sell_cost = 1,
          config = { center = { key = "j_a", set = "Joker" } } },
        { sort_id = 802, ability = { set = "Joker", name = "B" }, sell_cost = 1,
          config = { center = { key = "j_b", set = "Joker" } } },
      }),
    } end) },

  { state = "SELECTING_HAND", desc = "No hands left, has discards", progress = { "discard_hand" },
    mock = mock("hand", rounds(0, 3)) },

  { state = "SELECTING_HAND", desc = "Has hands, no discards", progress = { "play_hand" },
    mock = mock("hand", rounds(4, 0)) },

  { state = "SELECTING_HAND", desc = "Atomic: hands+discards left (must offer play_hand/discard_hand)",
    progress = { "discard_hand", "play_hand" },
    mock = mock("hand", nil, function()
      local cards = cards5()
      return { hand = held(cards, { cards[1], cards[2] }) }
    end) },

  { state = "SELECTING_HAND", desc = "Atomic: 0 hands but discards left (must offer discard_hand for discard)",
    progress = { "discard_hand" },
    mock = mock("hand", rounds(0, 2), function()
      local cards = cards5()
      return { hand = held(cards, { cards[1] }) }
    end) },

  { state = "SELECTING_HAND", desc = "No hands AND no discards (handler returns nil)", no_force = true, allow_no_progress = true,
    mock = mock("hand", rounds(0, 0)) },

  { state = "SELECTING_HAND", desc = "Empty hand cards (all HAND_ACTIONS blocked)", no_force = true, allow_no_progress = true,
    mock = mock("board") },

  { state = "SELECTING_HAND", desc = "Has usable consumable", progress = { "discard_hand", "play_hand", "use_consumable" },
    mock = mock("hand", function(g) g.last_tarot_planet = "c_pluto" end,
      function() return { consumeables = area(2, { consumable("c_fool") }) } end) },

  { state = "SHOP", desc = "Reroll blocked: $5 reroll $5 leaves $0, cheapest item $3 (anti-waste guard)",
    forbid_actions = { "reroll_shop" },
    mock = mock("shop", shop_money(5, 5, 0), function() return { shop_booster = row(booster(3)) } end) },

  { state = "SHOP", desc = "Reroll allowed: $6 reroll $1 keeps $5 >= cheapest $3",
    require_actions = { "reroll_shop" },
    mock = mock("shop", shop_money(6, 1, 0), function() return { shop_booster = row(booster(3)) } end) },

  { state = "SHOP", desc = "Reroll allowed: free reroll available despite $5/$5",
    progress = { "buy_from_shop", "leave_shop", "reroll_shop" },
    mock = mock("shop", shop_money(5, 5, 1), function() return { shop_booster = row(booster(3)) } end) },

  { state = "SHOP", desc = "Reroll allowed: nothing buyable (joker slots full), escape shop",
    require_actions = { "reroll_shop" },
    mock = mock("shop", shop_money(5, 5, 0), function()
      local full = n_cards(5)
      return { jokers = area(5, full), shop_jokers = row(make_card({ cost = 4 })) }
    end) },

  { state = "SHOP", desc = "Normal: affordable joker, affordable booster, $10",
    mock = mock("shop", nil, function() return {
      jokers = area(5, { make_card() }),
      shop_jokers = row(make_card({ cost = 4 })),
      shop_booster = row(booster(3, "Arcana Pack")),
    } end) },

  { state = "SHOP", desc = "$0 nothing affordable, has jokers to sell",
    mock = mock("shop", dollars(0), function() return {
      jokers = area(5, { make_card({ cost = 3 }) }),
      shop_jokers = row(make_card({ cost = 5 })),
      shop_booster = row(booster(4)),
    } end) },

  { state = "SHOP", desc = "$0 nothing to sell (leave_shop must survive)",
    mock = mock("shop", dollars(0), function() return { shop_jokers = row(make_card({ cost = 5 })) } end) },

  { state = "SHOP", desc = "Early game must_buy_phase: ante=1, affordable booster",
    mock = mock("shop", ante(1), function() return {
      jokers = area(5, { make_card() }),
      shop_booster = row(booster(4, "Arcana Pack")),
    } end) },

  { state = "SHOP", desc = "Must_buy_phase but nothing actually buyable",
    mock = mock("shop", function(g) g.round_resets.ante = 1; g.dollars = 2 end, function() return {
      jokers = area(5, n_cards(5)),
      shop_jokers = row(make_card({ cost = 5 })),
      shop_booster = row(booster(4)),
    } end) },

  { state = "SHOP", desc = "Full joker slots: 5/5, affordable jokers in shop",
    mock = mock("shop", nil, function()
      local jokers = n_cards(5, { cost = 3 })
      return { jokers = area(5, jokers), shop_jokers = row(make_card({ cost = 4 })) }
    end) },

  { state = "SHOP", desc = "Reroll blocked by early_shop_buy_priority",
    mock = mock("shop", ante(1), function() return {
      jokers = area(5, { make_card() }),
      shop_booster = row(booster(3, "Buffoon Pack")),
    } end) },

  { state = "SHOP", desc = "Everything blocked except leave_shop",
    mock = mock("shop", dollars(0), function() return { shop_jokers = row(make_card({ cost = 5 })) } end) },

  { state = "BLIND_SELECT", desc = "Small blind selectable", progress = { "select_blind" }, mock = mock("blind", open_small, opts("Small")) },

  { state = "BLIND_SELECT", desc = "Boss blind only (no skip, no reroll voucher)", progress = { "select_blind" }, mock = mock("blind", nil, opts("Boss")) },

  { state = "BLIND_SELECT", desc = "Boss with directors_cut (not yet rerolled)", progress = { "reroll_boss", "select_blind" },
    mock = mock("blind", vouchers({ v_directors_cut = true }), opts("Boss")) },

  { state = "BLIND_SELECT", desc = "Boss with retcon voucher, $10+", progress = { "reroll_boss", "select_blind" },
    mock = mock("blind", vouchers({ v_retcon = true }), opts("Boss")) },

  { state = "BLIND_SELECT", desc = "No blind_choices (edge case nil)", progress = { "select_blind" },
    mock = mock("blind", function(g) open_small(g); g.round_resets.blind_choices = nil end, opts("Small")) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Has pack cards", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return {
      pack_cards = { cards = n_cards(3) },
      booster_pack = { cards = n_cards(3) },
    } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Empty pack cards", progress = { "skip_pack" },
    mock = mock("board", nil, function() return { pack_cards = row(), booster_pack = row() } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "No pack area at all (nil)", no_force = true, allow_no_progress = true,
    mock = mock("board", nil, set({ pack_cards = EXPLICIT_NIL, booster_pack = EXPLICIT_NIL })) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Buffoon pack with a joker", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return {
      pack_cards = row(kind_card("Joker", "j_joker", "Joker")),
      booster_pack = row(kind_card("Joker", "j_joker", "Joker")),
    } end) },

  { state = "ROUND_EVAL", desc = "Normal: cash_out available", no_force = true,
    mock = mock("board", function(g) g.current_round.dollars = 6; g.chips = g.blind.chips end,
      function() return { round_eval = true } end) },

  { state = "ROUND_EVAL", desc = "Minimal state: only G.GAME set", no_force = true,
    mock = mock("menu", nil, function() return { round_eval = true } end) },

  { state = "GAME_OVER", desc = "No overlay (open_run_setup must work)", progress = { "open_run_setup" }, no_force = true, mock = mock("board") },

  { state = "GAME_OVER", desc = "With overlay present", progress = { "open_run_setup" },
    mock = mock("board", nil, function() return { OVERLAY_MENU = game_over_overlay() } end) },

  { state = "GAME_OVER", desc = "With unlock popup",
    mock = mock("board", nil, function() return { OVERLAY_MENU = unlock_overlay(1) } end) },

  { state = "GAME_OVER", desc = "Persona gate: NEURO_PERSONA=hiyori", no_force = true,
    mock = mock("board", nil, function() return { NEURO_PERSONA = "hiyori" } end) },

  { state = "MENU", desc = "Normal: has G.GAME", progress = { "open_run_setup" }, no_force = true,
    mock = mock("menu", nil, function() return { GAME = menu_game() } end) },

  { state = "MENU", desc = "Overlay present", progress = { "exit_overlay_menu", "open_run_setup" },
    mock = mock("menu", nil, function() return { OVERLAY_MENU = options_overlay() } end) },

  { state = "MENU", desc = "gameover_hold leaked past GAME_OVER: MENU must still force open_run_setup (the hang)",
    progress = { "open_run_setup" },
    mock = mock("menu", nil, function() return { NEURO_PERSONA = "evil", NEURO_GAMEOVER_HOLD = true } end) },

  { state = "SPLASH", desc = "Normal: minimal state", no_force = true, mock = mock("menu") },

  { state = "SPLASH", desc = "Escape pressed: no overlay opens", no_force = true, mock = mock("menu") },

  { state = "RUN_SETUP", engine_state = "MENU", desc = "Run setup overlay active",
    mock = mock("board", nil, function() return {
      GAME = menu_game(),
      OVERLAY_MENU = run_setup_overlay(),
      NEURO_DECK_CHOSEN = false,
      P_CENTER_POOLS = {
        Back = {
          { key = "b_red", unlocked = true, name = "Red Deck" },
          { key = "b_blue", unlocked = true, name = "Blue Deck" },
        },
      },
    } end) },

  { state = "SHOP", desc = "Reserved dollars blocks all purchases",
    mock = mock("shop", nil, function() return {
      jokers = area(5, { make_card() }),
      shop_jokers = row(make_card({ cost = 4 })),
      shop_booster = row(booster(3)),
      NEURO_RESERVED_DOLLARS = 10,
    } end) },

  { state = "SHOP", desc = "Completely empty shop areas", mock = mock("shop") },

  { state = "SHOP", desc = "Only vouchers affordable (no jokers/boosters)",
    mock = mock("shop", nil, function() return {
      shop_jokers = row(make_card({ cost = 99 })),
      shop_vouchers = row(make_card({ cost = 8, ability = { set = "Voucher" } })),
      shop_booster = row(booster(99)),
    } end) },

  { state = "SHOP", desc = "Ante=2 early shop priority",
    mock = mock("shop", ante(2), function() return {
      jokers = area(5, { make_card() }),
      shop_booster = row(booster(4)),
    } end) },

  { state = "SHOP", desc = "Bankrupt: bankrupt_at > dollars",
    mock = mock("shop", function(g) g.dollars = 3; g.bankrupt_at = 5 end, function() return {
      jokers = area(5, { make_card({ cost = 2 }) }),
      shop_jokers = row(make_card({ cost = 1 })),
    } end) },

  { state = "SHOP", desc = "Has consumables to use in shop",
    mock = mock("shop", dollars(0), function()
      local con = consumable("c_mercury")
      return { consumeables = area(2, { con }), shop_jokers = row(make_card({ cost = 5 })) }
    end) },

  { state = "SHOP", desc = "Must_buy_phase + only sellable is consumable",
    mock = mock("shop", ante(1), function()
      local con = consumable("c_fool", { cost = 2 })
      return { consumeables = area(2, { con }), shop_booster = row(booster(4)) }
    end) },

  { state = "SHOP", desc = "Free items in shop (cost=0)",
    mock = mock("shop", dollars(0), function() return { shop_jokers = row(make_card({ cost = 0 })) } end) },

  { state = "SHOP", desc = "Free reroll but early_shop blocks it",
    mock = mock("shop", function(g) g.round_resets.ante = 1; g.current_round.reroll_cost = 0 end, function() return {
      jokers = area(5, { make_card() }),
      shop_booster = row(booster(3)),
    } end) },

  { state = "SHOP", desc = "Full slots everywhere, $0, empty shop",
    mock = mock("shop", dollars(0), function()
      local jokers = n_cards(5)
      local cons = n_consumables(2, "c_hermit")
      return { jokers = area(5, jokers), consumeables = area(2, cons) }
    end) },

  { state = "SHOP", desc = "Nil shop areas (not initialized)",
    mock = mock("shop", nil, set({ shop_jokers = EXPLICIT_NIL, shop_vouchers = EXPLICIT_NIL, shop_booster = EXPLICIT_NIL })) },

  { state = "SELECTING_HAND", desc = "Single card in hand",
    mock = mock("hand", nil, function() return { hand = held({ make_card() }) } end) },

  { state = "SELECTING_HAND", desc = "Last hand, no discards, score already won",
    mock = mock("hand", function(g)
      rounds(1, 0)(g)
      g.chips = 999
      g.blind = { chips = 300, mult = 1 }
    end) },

  { state = "SELECTING_HAND", desc = "No blind set (G.GAME.blind=nil)", mock = mock("hand", function(g) g.blind = nil end) },

  { state = "SELECTING_HAND", desc = "Empty hand + no jokers + no consumables + 0/0", no_force = true, allow_no_progress = true,
    mock = mock("board", rounds(0, 0)) },

  { state = "SELECTING_HAND", desc = "Has consumable but hand is empty", no_force = true,
    mock = mock("board", nil, function() return { consumeables = area(2, { consumable("c_jupiter") }) } end) },

  { state = "SELECTING_HAND", desc = "Full jokers, no consumables, 1 hand left",
    mock = mock("hand", rounds(1, 0), function() return { jokers = area(5, n_cards(5)) } end) },

  { state = "SELECTING_HAND", desc = "G.GAME.current_round is nil", no_force = true, allow_no_progress = true,
    mock = mock("hand", function(g) g.current_round = nil end) },

  { state = "BLIND_SELECT", desc = "Big blind selectable (can skip)", progress = { "select_blind", "skip_blind" },
    mock = mock("blind", function(g)
      g.round_resets.blind_states = { Small = "Skipped", Big = "Select", Boss = "Upcoming" }
      g.round_resets.blind_tags = { Small = "tag_economy", Big = "tag_economy" }
      g.blind_on_deck = "Big"
    end, opts("Big")) },

  { state = "BLIND_SELECT", desc = "Directors cut already used (boss_rerolled=true)", progress = { "select_blind" },
    mock = mock("blind", function(g)
      g.round_resets.boss_rerolled = true
      g.used_vouchers = { v_directors_cut = true }
    end, opts("Boss")) },

  { state = "BLIND_SELECT", desc = "Retcon but too poor to reroll ($5)", progress = { "select_blind" },
    mock = mock("blind", function(g) g.dollars = 5; g.used_vouchers = { v_retcon = true } end, opts("Boss")) },

  { state = "BLIND_SELECT", desc = "No blind_select_opts (nil)", progress = { "select_blind" },
    mock = mock("blind", open_small, set({ blind_select_opts = EXPLICIT_NIL })) },

  { state = "BLIND_SELECT", desc = "No blind_states (nil round_resets)", no_force = true, allow_no_progress = true,
    mock = mock("blind", function(g) g.round_resets = nil; g.blind_on_deck = nil end,
      set({ blind_select_opts = EXPLICIT_NIL })) },

  { state = "BLIND_SELECT", desc = "All blind_states are Upcoming (none selectable)", no_force = true, allow_no_progress = true,
    mock = mock("blind", function(g)
      g.round_resets.blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
      g.blind_on_deck = nil
    end, opts("all")) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Spectral pack with a card", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return {
      hand = held(cards5()),
      pack_cards = row(kind_card("Spectral", "c_black_hole", "Black Hole")),
      booster_pack = row(kind_card("Spectral", "c_black_hole", "Black Hole")),
    } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Celestial pack with planets", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return {
      pack_cards = row(kind_card("Planet", "c_pluto", "Pluto"), kind_card("Planet", "c_mercury", "Mercury")),
      booster_pack = row(kind_card("Planet", "c_pluto", "Pluto"), kind_card("Planet", "c_mercury", "Mercury")),
    } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Standard pack with playing cards", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return {
      pack_cards = { cards = n_cards(3) },
      booster_pack = { cards = n_cards(3) },
    } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "SMODS_BOOSTER_OPENED with cards", progress = { "choose_pack_card", "skip_pack" },
    mock = mock("board", nil, function() return { pack_cards = row(make_card()), booster_pack = row(make_card()) } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Full consumable slots during pack", progress = { "choose_pack_card", "sell_card", "skip_pack", "use_consumable" },
    mock = mock("board", nil, function()
      local cons = n_consumables(2, "c_hermit")
      return {
        hand = held(cards5()),
        consumeables = area(2, cons),
        pack_cards = row(kind_card("Tarot", "c_hermit", "The Hermit"), kind_card("Tarot", "c_temperance", "Temperance")),
        booster_pack = row(kind_card("Tarot", "c_hermit", "The Hermit"), kind_card("Tarot", "c_temperance", "Temperance")),
      }
    end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Full joker slots during buffoon pack", progress = { "sell_card", "skip_pack" },
    mock = mock("board", nil, function()
      local jokers = n_cards(5)
      return {
        jokers = area(5, jokers),
        pack_cards = row(kind_card("Joker", "j_joker", "Joker")),
        booster_pack = row(kind_card("Joker", "j_joker", "Joker")),
      }
    end) },

  { state = "GAME_OVER", desc = "Persona nil", progress = { "choose_persona", "open_run_setup" }, no_force = true,
    mock = mock("board", nil, set({ NEURO_PERSONA = EXPLICIT_NIL })) },

  { state = "GAME_OVER", desc = "Persona evil", progress = { "open_run_setup" }, no_force = true,
    mock = mock("board", nil, function() return { NEURO_PERSONA = "evil" } end) },

  { state = "GAME_OVER", desc = "No G.GAME at all", progress = { "open_run_setup" }, no_force = true, mock = mock("board", EXPLICIT_NIL) },

  { state = "MENU", desc = "No G.GAME at all", progress = { "open_run_setup" }, no_force = true, mock = mock("menu", EXPLICIT_NIL) },

  { state = "MENU", desc = "Persona nil", progress = { "choose_persona", "open_run_setup" }, no_force = true,
    mock = mock("menu", nil, set({ NEURO_PERSONA = EXPLICIT_NIL })) },

  { state = "SPLASH", desc = "Persona nil", no_force = true,
    mock = mock("menu", nil, set({ NEURO_PERSONA = EXPLICIT_NIL })) },

  { state = "SPLASH", desc = "Persona evil", no_force = true,
    mock = mock("menu", nil, function() return { NEURO_PERSONA = "evil" } end) },

  { state = "SPLASH", desc = "No G.GAME at all", no_force = true, mock = mock("menu", EXPLICIT_NIL) },

  { state = "ROUND_EVAL", desc = "With overlay blocking",
    mock = mock("board", nil, function() return { OVERLAY_MENU = options_overlay() } end) },

  { state = "ROUND_EVAL", desc = "No G.GAME", no_force = true,
    mock = mock("menu", EXPLICIT_NIL, function() return { round_eval = true } end) },

  { state = "RUN_SETUP", engine_state = "GAME_OVER", desc = "Overlay with deck already chosen",
    mock = mock("board", nil, function() return {
      OVERLAY_MENU = run_setup_overlay(),
      NEURO_DECK_CHOSEN = true,
      P_CENTER_POOLS = {
        Back = {
          { key = "b_red", unlocked = true, name = "Red Deck" },
        },
      },
    } end) },

  { state = "RUN_SETUP", engine_state = "GAME_OVER", desc = "No P_CENTER_POOLS",
    mock = mock("board", nil, function() return { OVERLAY_MENU = run_setup_overlay(), NEURO_DECK_CHOSEN = false } end) },

  { state = "SHOP", desc = "G.GAME is nil", mock = mock("shop", EXPLICIT_NIL) },

  { state = "SHOP", desc = "Ante 1 only jokers affordable but slots full",
    mock = mock("shop", ante(1), function()
      local jokers = n_cards(5)
      return { jokers = area(5, jokers), shop_jokers = row(make_card({ cost = 3 })) }
    end) },

  { state = "SHOP", desc = "All shop items unaffordable, high reroll cost",
    mock = mock("shop", function(g) g.dollars = 3; g.current_round.reroll_cost = 10 end, function() return {
      jokers = area(5, { make_card({ cost = 2 }) }),
      shop_jokers = row(make_card({ cost = 5 })),
      shop_vouchers = row(make_card({ cost = 10, ability = { set = "Voucher" } })),
      shop_booster = row(booster(6)),
      NEURO_SHOP_REROLL_COUNT = 5,
    } end) },

  { state = "SHOP", desc = "Has both jokers and consumables to sell",
    mock = mock("shop", dollars(0), function()
      local con = consumable("c_strength", { cost = 3 })
      return {
        jokers = area(5, { make_card({ cost = 4 }) }),
        consumeables = area(2, { con }),
        shop_jokers = row(make_card({ cost = 8 })),
      }
    end) },

  { state = "SELECTING_HAND", desc = "G.GAME is nil", no_force = true, allow_no_progress = true,
    mock = mock("hand", EXPLICIT_NIL) },

  { state = "SELECTING_HAND", desc = "G.hand is nil entirely", no_force = true, allow_no_progress = true,
    mock = mock("board", nil, set({ hand = EXPLICIT_NIL })) },

  { state = "SELECTING_HAND", desc = "Has jokers + consumable, 0 hands, 0 discards", no_force = true,
    mock = mock("hand", rounds(0, 0), function()
      local con = consumable("c_star")
      return { jokers = area(5, n_cards(3)), consumeables = area(2, { con }) }
    end) },

  { state = "SELECTING_HAND", desc = "Empty hand AND empty deck, consumable held",
    no_force = true,
    mock = mock("board", nil, function() return { deck = row(), consumeables = area(2, { consumable("c_jupiter") }) } end) },

  { state = "SELECTING_HAND", desc = "2 cards in hand, full jokers, full consumables",
    mock = mock("hand", nil, function()
      local jokers = n_cards(5)
      local cons = n_consumables(2, "c_mars")
      return { hand = held({ make_card(), make_card() }), jokers = area(5, jokers), consumeables = area(2, cons) }
    end) },

  { state = "BLIND_SELECT", desc = "Has both directors_cut and retcon", progress = { "reroll_boss", "select_blind" },
    mock = mock("blind", vouchers({ v_directors_cut = true, v_retcon = true }), opts("Boss")) },

  { state = "BLIND_SELECT", desc = "Boss rerolled with retcon (can reroll again)", progress = { "reroll_boss", "select_blind" },
    mock = mock("blind", function(g)
      g.round_resets.boss_rerolled = true
      g.used_vouchers = { v_retcon = true }
    end, opts("Boss")) },

  { state = "BLIND_SELECT", desc = "G.GAME is nil [XFAIL: unreachable in-engine, known 1 FAIL]",
    xfail = true,
    mock = mock("board", EXPLICIT_NIL, set({ blind_select_opts = EXPLICIT_NIL })) },

  { state = "BLIND_SELECT", desc = "$0, boss only, no vouchers", progress = { "select_blind" }, mock = mock("blind", dollars(0), opts("Boss")) },

  { state = "SMODS_BOOSTER_OPENED", desc = "pack_choices=0 (no picks left)", progress = { "choose_pack_card", "sell_card", "skip_pack", "use_consumable" },
    mock = mock("board", function(g) g.pack_choices = 0 end, function() return {
      consumeables = area(2, { consumable("c_hermit") }),
      pack_cards = row(make_card()),
      booster_pack = row(make_card()),
    } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Empty spectral pack", progress = { "skip_pack" },
    mock = mock("board", nil, function() return { hand = held(cards5()), pack_cards = row(), booster_pack = row() } end) },

  { state = "SMODS_BOOSTER_OPENED", desc = "Empty modded booster", progress = { "skip_pack" },
    mock = mock("board", nil, function() return { pack_cards = row(), booster_pack = row() } end) },

  { state = "GAME_OVER", desc = "Overlay + persona hiyori",
    mock = mock("board", nil, function() return { OVERLAY_MENU = game_over_overlay(), NEURO_PERSONA = "hiyori" } end) },

  { state = "MENU", desc = "Persona evil", progress = { "open_run_setup" }, no_force = true,
    mock = mock("menu", nil, function() return { NEURO_PERSONA = "evil" } end) },

  { state = "MENU", desc = "Persona hiyori", no_force = true,
    mock = mock("menu", nil, function() return { NEURO_PERSONA = "hiyori" } end) },

  { state = "MENU", desc = "Overlay + persona hiyori", progress = { "exit_overlay_menu" },
    mock = mock("menu", nil, function() return { OVERLAY_MENU = options_overlay(), NEURO_PERSONA = "hiyori" } end) },

  { state = "SELECTING_HAND", desc = "Overlay blocks during hand selection",
    mock = mock("hand", nil, function() return { OVERLAY_MENU = options_overlay() } end) },

  { state = "SHOP", desc = "Overlay blocks during shop",
    mock = mock("shop", nil, function() return {
      jokers = area(5, { make_card() }),
      shop_jokers = row(make_card({ cost = 4 })),
      OVERLAY_MENU = options_overlay(),
    } end) },

  { state = "BLIND_SELECT", desc = "Overlay blocks during blind select",
    mock = mock("blind", open_small, function() return {
      blind_select_opts = make_blind_select_opts("Small"),
      OVERLAY_MENU = options_overlay(),
    } end) },

  { state = "SELECTING_HAND", desc = "The Psychic: 7 held cards under the five-card cap",
    mock = mock("hand", blind_of("The Psychic", "bl_psychic"),
      function() return { hand = held(varied_cards(7)) } end) },

  { state = "SELECTING_HAND", desc = "The Eye: Straight already played this round",
    mock = mock("hand", blind_of("The Eye", "bl_eye", { hands = { ["Straight"] = true } }),
      function() return { hand = held(varied_cards()) } end) },

  { state = "SELECTING_HAND", desc = "The Mouth: round locked to Flush",
    mock = mock("hand", blind_of("The Mouth", "bl_mouth", { only_hand = "Flush" }),
      function() return { hand = held(varied_cards()) } end) },

  { state = "SELECTING_HAND", desc = "The Ox: most played hand is Two Pair",
    mock = mock("hand", function(g)
      g.current_round.most_played_poker_hand = "Two Pair"
      g.blind = boss("The Ox", "bl_ox")
    end, function() return { hand = held(varied_cards()) } end) },

  { state = "SELECTING_HAND", desc = "The Serpent: only 3 deck cards left for the after-play draw",
    mock = mock("hand", blind_of("The Serpent", "bl_serpent"),
      function() return { deck = row({}, {}, {}), hand = held(varied_cards()) } end) },

  { state = "SELECTING_HAND", desc = "The Needle: exactly 1 hand this round",
    mock = mock("hand", function(g)
      g.current_round.hands_left = 1
      g.blind = boss("The Needle", "bl_needle")
    end, function() return { hand = held(varied_cards()) } end) },

  { state = "SELECTING_HAND", desc = "The Pillar: two held cards were played earlier this ante",
    mock = mock("hand", blind_of("The Pillar", "bl_pillar"), function()
      local cards = varied_cards()
      cards[2] = make_card({ ability = { set = "Default", name = "Mock", played_this_ante = true },
        debuff = true })
      cards[4] = make_card({ ability = { set = "Default", name = "Mock", played_this_ante = true },
        debuff = true })
      return { hand = held(cards) }
    end) },

  { state = "SHOP", desc = "Seed Money + Money Tree owned ($20 interest cap, first $100 counts)",
    mock = mock("shop", function(g)
      g.used_vouchers = { ["v_seed_money"] = true, ["v_money_tree"] = true }
      g.interest_cap = 100
    end, function() return {
      jokers = area(5, { make_card() }),
      shop_jokers = row(make_card({ cost = 4 })),
    } end) },

  { state = "SELECTING_HAND", desc = "Ghost Deck selected (deck reference prose)",
    mock = mock("hand", function(g) g.selected_back = { key = "b_ghost", name = "Ghost Deck" } end, function() return {
      P_CENTERS = require("tests.engine_centers").centers(),
      hand = held(varied_cards()),
    } end) },

  { state = "SELECTING_HAND", desc = "Painted Deck selected (+1 hand size, card_limit 9)",
    mock = mock("hand", function(g) g.selected_back = { key = "b_painted", name = "Painted Deck" } end, function() return {
      P_CENTERS = require("tests.engine_centers").centers(),
      hand = { cards = varied_cards(), config = { card_limit = 9 }, highlighted = {} },
    } end) },

}

local function names_str(list)
  if not list or #list == 0 then return "none" end
  local t = {}
  for i, v in ipairs(list) do t[i] = tostring(v) end
  return table.concat(t, ", ")
end

function M.run()
  local Dispatcher = G.NEURO.dispatcher
  local Actions = G.NEURO.actions

  if not Dispatcher or not Actions then
    error("test_deadlock: G.NEURO.dispatcher/actions not set (wire them before M.run)")
  end

  print("====================================================")
  print("[test] Deadlock test suite starting (" .. #SCENARIOS .. " scenarios)")
  print("====================================================")

  local pass, fail, xfail = 0, 0, 0
  local failures = {}

  for i, sc in ipairs(SCENARIOS) do
    local snap = snapshot()
    local ok_outer, res = pcall(function()
      apply_mock(sc.mock())
      require("tests.helpers").in_scenario_state(sc)
      local read = require("core.state").get_state_name()
      if read ~= sc.state then return { reason = "board reads as " .. read .. ", not " .. sc.state } end

      G.NEURO.state_entry_hints = nil
      G.NEURO.blind_info_sig = nil
      G.NEURO.blind_info_seen = nil

      local force = require("force.force_router").get_force_for_state(sc.state)
      local actions = force and force.actions or nil

      local aset = {}
      for _, list in ipairs({ actions or {}, force and force.tools or {} }) do
        for _, n in ipairs(list) do
          if type(n) == "string" then aset[n] = true end
        end
      end
      for _, n in ipairs(sc.forbid_actions or {}) do
        if aset[n] then
          return { reason = string.format("forbidden action '%s' offered\n      force_actions: %s", n, names_str(actions)) }
        end
      end
      for _, n in ipairs(sc.require_actions or {}) do
        if not aset[n] then
          return { reason = string.format("required action '%s' missing\n      force_actions: %s", n, names_str(actions)) }
        end
      end

      if sc.progress then
        local got, np, seen = {}, non_progress_set(), {}
        for n in pairs(aset) do
          if not np[n] and not seen[n] then seen[n] = true; got[#got + 1] = n end
        end
        table.sort(got)
        local want = copy(sc.progress)
        table.sort(want)
        if table.concat(got, ",") ~= table.concat(want, ",") then
          return { reason = string.format("progressing actions %s, expected exactly %s", names_str(got), names_str(want)) }
        end
      end

      if #(actions or {}) == 0 and not sc.allow_no_progress then
        local valid = Actions.get_valid_actions_for_state(sc.state)
        if not sc.no_force then
          return { reason = string.format("forcer gave no progress action\n      force_actions: %s\n      valid_actions: %s",
            names_str(actions), names_str(valid)) }
        end
        if not has_progress(valid) then
          return { reason = string.format("no progress action anywhere\n      force_actions: %s\n      valid_actions: %s",
            names_str(actions), names_str(valid)) }
        end
      end
      return {}
    end)

    restore(snap)

    local reason
    if not ok_outer then
      reason = "ERROR: " .. tostring(res)
    elseif res.reason then
      reason = res.reason
    end

    if not reason then
      pass = pass + 1
      print(string.format("[test] %s #%02d [%s] %s", sc.xfail and "XPASS" or "PASS", i, sc.state, sc.desc))
      if sc.xfail then
        print(string.format("[test] !!! XPASS #%02d [%s] %s — fix confirmed? remove xfail tag", i, sc.state, sc.desc))
      end
    elseif sc.xfail then
      xfail = xfail + 1
      print(string.format("[test] XFAIL #%02d [%s] %s", i, sc.state, sc.desc))
    else
      fail = fail + 1
      failures[#failures + 1] = string.format("  #%d [%s] %s\n      %s", i, sc.state, sc.desc, reason)
      print(string.format("[test] FAIL #%02d [%s] %s", i, sc.state, sc.desc))
    end
  end

  print("====================================================")
  print(string.format("[test] Results: %d PASS, %d FAIL, %d XFAIL out of %d", pass, fail, xfail, #SCENARIOS))
  if #failures > 0 then
    print("[test] Failures:")
    for _, f in ipairs(failures) do
      print(f)
    end
  end
  print("====================================================")
  return fail
end

M.SCENARIOS = SCENARIOS
M.apply_mock = apply_mock

return M
