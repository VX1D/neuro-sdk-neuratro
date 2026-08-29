local Actions = {}
local CtxEconomy = require("facts.economy_facts")
local StateKinds = require("core.state_kinds")
local ActionRegistry = require("core.action_registry")
local Limits = require("core.plan_limits")
local GameFacts = require("facts.game_facts")
local Utils = require("util.utils")

local function action_def(name, description, schema, arg_hints)
  return {
    name = name,
    description = description or ("Trigger action " .. name .. "."),
    schema = schema or { type = "object" },
    arg_hints = arg_hints
  }
end

local function generic_schema()
  return { type = "object", properties = {}, required = {} }
end

local function hand_focus_schema()
  local names = GameFacts.visible_hand_names()
  if not names then return nil end
  return {
    type = "object",
    properties = {
      primary = { type = "string", enum = names },
      fallback = { type = "string", enum = names },
    },
    required = { "primary" },
  }
end

local function plan_schema(opts)
  local props = {
    hand_plan = { type = "string" },
    build_plan = { type = "string" },
    money_plan = { type = "string" },
    hand_focus = hand_focus_schema(),
  }
  if opts and opts.boss then
    props.boss_plan = { type = "string" }
  end
  return { type = "object", properties = props }
end

local function boss_plan_schema()
  return {
    type = "object",
    properties = {
      boss_plan = { type = "string" },
    },
  }
end

local function confirm_hand_on()
  local HH = Utils.lazy_require("handlers.hand_handlers")
  return not (HH and HH.confirm_hand_on) or HH.confirm_hand_on()
end

-- A fresh schema object per call, not an in-schema conditional: SPECIFICATION.md warns those
-- aren't reliably supported.
local function confirm_play_schema()
  local HH = Utils.lazy_require("handlers.hand_handlers")
  local pend = HH and HH.pending and HH.pending()
  local always_reason = require("core.config").bool("NEURO_CONFIRM_REASON_ALWAYS")
  local props = {
    answer = { type = "string", enum = { "yes", "no" } },
  }
  -- Advertised, never required: `required` would also reject a bare answer:"no", the discard path.
  -- handle_confirm_play enforces it on yes instead.
  if always_reason or (pend and pend.dominant_alt) then
    props.reason = { type = "string" }
  end
  return { type = "object", properties = props, required = { "answer" } }
end

local function joker_intents_schema()
  return {
    type = "array",
    minItems = 1,
    maxItems = 25,
    items = {
      type = "object",
      properties = {
        index = { type = "integer", minimum = 1 },
        tag = { type = "string", enum = { "CORE", "SCALING", "HOLD", "CHANGE" } },
        note = { type = "string" }
      },
      required = { "index", "tag" }
    }
  }
end

local function build_param_actions()
  local play_max = Limits.play_select_max()
  local discard_max = math.max(1, Limits.discard_select_max())
  local hand_max = Limits.hand_select_max()
  return {
    select_blind = action_def("select_blind", "Select the active blind for this ante. Pass `blind`: 'small', 'big', or 'boss'. When requested by `Your move`, include only the requested plan fields; they describe the plan after selecting this blind and are saved with the action. Optionally add `plan.hand_focus` with an exact visible hand name as `primary` and, if useful, `fallback`; this records your declaration but never blocks a different play.", {
      type = "object",
      properties = {
        blind = { type = "string", enum = { "small", "big", "boss" } },
        plan = plan_schema({ boss = true })
      },
      required = { "blind" }
    }),
    use_card = action_def("use_card", "Use a card from a consumeables slot (Consumables) or an open pack, by area + 1-indexed index. For a consumable that targets hand cards, also pass hand_indices as 1-indexed hand positions. Optionally pass `name` (the card's displayed name) to confirm the target: if the card now at `index` has a different name the action is rejected -- indices shift after every use/pick. When requested by `Your move`, include only the requested plan fields; they describe the plan after using the card and are saved with the action.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "consumeables", "booster_pack" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string" },
        hand_indices = { type = "array", items = { type = "integer", minimum = 1 }, minItems = 1, maxItems = hand_max, uniqueItems = true },
        plan = plan_schema()
      },
      required = { "area", "index" }
    }, { hand_indices = "hand positions" }),
    use_directional_card = action_def("use_directional_card", "Use a card whose two hand targets have different roles. Pass `area` ('consumeables' or 'booster_pack'), the card's 1-indexed `index`, and its displayed `name`. `left_index` is the visually left source hand card and `right_index` is the visually right destination hand card; they must be distinct and left_index < right_index. When requested by `Your move`, include only the requested plan fields.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "consumeables", "booster_pack" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string", minLength = 1 },
        left_index = { type = "integer", minimum = 1 },
        right_index = { type = "integer", minimum = 1 },
        plan = plan_schema()
      },
      required = { "area", "index", "name", "left_index", "right_index" }
    }),
    buy_from_shop = action_def("buy_from_shop", "Buy an item from a Shop items row by area + 1-indexed index. For a targeted consumable, buy with use=false then drive it with use_card, or use_directional_card when its two targets have different roles. Optionally pass `name` (the item's displayed name) to confirm the target: a mismatch with the item now at `index` rejects the buy -- shop rows shift after each purchase or reroll. When requested by `Your move`, include only the requested plan fields; they describe the plan after buying and are saved with the action.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "shop_jokers", "shop_vouchers", "shop_booster" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string" },
        use = { type = "boolean" },
        plan = plan_schema()
      },
      required = { "area", "index" }
    }),
    sell_card = action_def("sell_card", "Sell a joker (Your jokers) or consumable (Consumables) by area + 1-indexed index. Optionally pass `name` (the card's displayed name) to confirm the target: if the card now at `index` has a different name, the sell is rejected -- this protects you when indices shift right after another sell or use. When requested by `Your move`, include only the requested plan fields; they describe the plan after selling and are saved with the action.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "jokers", "consumeables" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string" },
        plan = plan_schema()
      },
      required = { "area", "index" }
    }),
    play_hand = action_def("play_hand", "Play {count:indices:hand card} as a poker hand. " .. (confirm_hand_on() and "Committing takes two sends: the first play_hand returns a confirmation with the engine verdict and spends nothing, and a `confirm_play` with `answer:\"yes\"` commits it, using one hand (H) and scoring. Sending different indices instead starts a fresh confirmation for that selection. On your last hand with no discards left and at most one ready hand there is nothing to weigh, so the first send commits immediately unless the hand is one of the three lowest-ranking types or the boss blind has something to say about it." or "This commits the selection on the first send, using one hand (H) and scoring.") .. " `indices` are the 1-indexed hand positions from Your hand. Judge the hand yourself from Your hand, the Hand levels, and the Ready/Close facts before playing. When requested by `Your move`, include only the requested plan fields (including `boss_plan` during boss blinds); they describe the plan for this round and are saved with the action.", {
      type = "object",
      properties = {
        indices = {
          type = "array",
          items = { type = "integer", minimum = 1 },
          minItems = 1, maxItems = play_max, uniqueItems = true
        },
        plan = boss_plan_schema()
      },
      required = { "indices" }
    }, { indices = "hand positions" }),
    confirm_play = action_def("confirm_play", "Answer the play_hand confirmation shown in the current prompt. `answer:\"yes\"` commits exactly the selection that confirmation names -- it spends one hand and scores. `answer:\"no\"` discards the confirmation and returns you to a fresh choice; nothing is spent. This action exists only while a confirmation is open, and it can only answer that one: if your hand changed since it was issued, `yes` is refused and the confirmation is discarded, so choose again. To confirm a different selection, send play_hand with those indices instead -- that opens its own confirmation. When the confirmation asks for one, `answer:\"yes\"` also takes `reason`: a specific, non-boilerplate sentence naming why this is the play, and naming why you prefer it over any other ready hand the confirmation points at.", confirm_play_schema()),
    discard_hand = action_def("discard_hand", "Discard {count:indices:hand card} immediately and draw the same number of replacements. This is FINAL and costs one discard, not a hand -- discards are the cheap re-draw resource (only usable while you have discards left). `indices` are the 1-indexed hand positions from Your hand. Use it to throw away weak cards and draw toward a better hand. When requested by `Your move`, include only the requested plan fields (including `boss_plan` during boss blinds); they describe the plan for this round and are saved with the action.", {
      type = "object",
      properties = {
        indices = {
          type = "array",
          items = { type = "integer", minimum = 1 },
          minItems = 1, maxItems = discard_max, uniqueItems = true
        },
        plan = boss_plan_schema()
      },
      required = { "indices" }
    }, { indices = "hand positions" }),
    change_stake = action_def("change_stake", "Change run stake. Pass `to_key`: the stake number from the Stakes list (1-indexed).", {
      type = "object",
      properties = { to_key = { type = "integer", minimum = 1 } },
      required = { "to_key" }
    }),
    change_challenge_description = action_def("change_challenge_description", "Select a challenge. Pass `id`: the challenge id or displayed name (from the challenge list).", {
      type = "object",
      properties = { id = { type = "string" } },
      required = { "id" }
    }),
    change_selected_back = action_def("change_selected_back", "Select a deck. Pass `back`: the deck key (e.g. b_red, b_blue).", {
      type = "object",
      properties = { back = { type = "string" } },
      required = { "back" }
    }),
    paste_seed = action_def("paste_seed", "Paste a seed for a seeded run (1-8 letters/digits); omit seed to paste from the clipboard.", {
      type = "object",
      properties = { seed = { type = "string", minLength = 1, maxLength = 8 } },
      required = {}
    }),
    choose_persona = action_def("choose_persona", "Set active persona. Pass `persona`: 'neuro' for Neuro-sama or 'evil' for Evil Neuro.", {
    type = "object",
    properties = {
      persona = {
        type = "string",
        enum = { "neuro", "evil" }
      }
    },
    required = { "persona" }
    }),
    set_joker_order = action_def("set_joker_order", "Move a joker. Pass `from_index` (its current 1-indexed position) and `to_index` (the target position).", {
      type = "object",
      properties = {
        from_index = { type = "integer", minimum = 1 },
        to_index = { type = "integer", minimum = 1 }
      },
      required = { "from_index", "to_index" }
    }),
    reroll_shop = action_def("reroll_shop", "Replace the current shop jokers with a new random set, not the voucher or packs; each reroll costs money and the price rises each time this shop visit. When requested by `Your move`, include only the requested plan fields; they describe the plan after rerolling and are saved with the action.", {
      type = "object",
      properties = {
        plan = plan_schema()
      },
      required = {}
    }),
    toggle_shop = action_def("toggle_shop", "Exit shop and continue run flow. Blocked while any joker carries no tag; set_joker_intents tags it first. When requested by `Your move`, include only the requested plan fields; they describe the plan after leaving and are saved with the action. `joker_order_confirmed`: true leaves on the current joker order.", {
      type = "object",
      properties = {
        plan = plan_schema(),
        joker_order_confirmed = { type = "boolean" }
      },
      required = {}
    }),
    set_joker_intents = action_def("set_joker_intents", "Record the role each joker plays in your build. Pass `intents`: a list of { index (1-indexed joker position), tag, note (optional) }. CORE: the piece your build is built around. SCALING: it grows over time and pays off later. HOLD: useful for now, keep it while it earns its slot. CHANGE: you want to swap it out when something better shows up. A tag stays on that joker for the rest of the run and follows the card, not the slot -- retag it whenever your view changes. Tagging never sells, buys or moves anything: every joker sale still needs its own fresh confirmation, and the tag only changes what that confirmation reminds you of. `note` records why, in your own words -- shown on that joker's row while shopping and echoed back if you later try to sell it. A note is stored exactly as you write it, at any length, and is never refused, so the tags in the same call always land. Leaving `note` out keeps any note already on file; passing `note`: '' clears it. While every joker carries a tag you can leave the shop; untagged jokers block toggle_shop until you tag them.", {
      type = "object",
      properties = {
        intents = joker_intents_schema()
      },
      required = { "intents" }
    }),
    set_plan = action_def("set_plan", "State committed decisions, verb first -- not analysis or a copy of the board. `hand_plan` = the line you will play this blind. `build_plan` = your build direction and next upgrade. `money_plan` = one spend-or-hold decision. Optional `hand_focus` declares an exact visible hand name as `primary` and optional `fallback`; it is echoed as your declaration and never blocks another play. Dynamic facts (cash, joker roster, boss text) come from live state; do not repeat them.", {
      type = "object",
      properties = plan_schema().properties,
      required = {}
    }),
  }
end

local get_spendable_dollars = CtxEconomy.spendable

local function get_selectable_blind_key()
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return nil
  end

  local bs = G.GAME.round_resets.blind_states
  local on_deck = G.GAME.blind_on_deck
  if (on_deck == "Small" or on_deck == "Big" or on_deck == "Boss") and bs[on_deck] == "Select" then
    return on_deck
  end

  if bs.Small == "Select" then return "Small" end
  if bs.Big == "Select" then return "Big" end
  if bs.Boss == "Select" then return "Boss" end
  return nil
end
Actions.get_selectable_blind_key = get_selectable_blind_key

local SKIPPABLE_BLINDS = { Small = true, Big = true }

local function blind_skip_blocker()
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return "Blind selection is not ready yet."
  end
  local on_deck = get_selectable_blind_key()
  if on_deck == "Boss" then
    return "Skipping boss blind is not supported. Select the boss blind instead."
  end
  if not (on_deck and SKIPPABLE_BLINDS[on_deck]) then
    return "No skippable blind is currently selectable."
  end
  local rr = G.GAME.round_resets
  local choice = rr.blind_choices and rr.blind_choices[on_deck]
  local def = choice and G.P_BLINDS and G.P_BLINDS[choice]
  if def and def.unskippable then
    return "This blind cannot be skipped."
  end
  if not (rr.blind_tags and rr.blind_tags[on_deck]) then
    return "This blind offers no skip reward tag, so it cannot be skipped."
  end
  return nil
end
Actions.blind_skip_blocker = blind_skip_blocker

local CardUtil = require("facts.card_util")
local can_buy_card_space = CardUtil.can_buy_card_space
local can_take_pack_card = CardUtil.can_take_pack_card
local consumable_usable_now = CardUtil.consumable_usable_now

local SIMPLE_ACTION_DESCS = {
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
  },
  GAME_OVER = {
    "choose_persona",
    "setup_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "change_selected_back",
    "start_setup_run",
  },
  BLIND_SELECT = {
    "select_blind",
    "skip_blind",
    "reroll_boss",
    "sell_card",
    "set_joker_order",
    "set_joker_intents",
    "set_plan",
    "use_card",
    "use_directional_card",
  },
  SELECTING_HAND = {
    "play_hand",
    "discard_hand",
    "confirm_play",
    "use_card",
    "use_directional_card",
    "sell_card",
    "set_joker_order",
  },
  SHOP = {
    "buy_from_shop",
    "sell_card",
    "use_card",
    "use_directional_card",
    "reroll_shop",
    "toggle_shop",
    "set_joker_order",
    "set_joker_intents",
    "set_plan",
  },
  ROUND_EVAL = {
    "cash_out",
    "set_plan",
  },
}

local PACK_ACTIONS = {
  "use_card",
  "use_directional_card",
  "sell_card",
  "skip_booster",
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

function Actions.state_is_modelled(state_name)
  return STATE_ACTIONS[state_name] ~= nil or StateKinds.is_pack_state(state_name)
end

-- Kept for core/dispatcher.lua:1081, which asks the same question under the older name.
function Actions.state_has_actions(state_name)
  return Actions.state_is_modelled(state_name)
end

function Actions.get_known_states()
  local states = {}
  for state_name in pairs(STATE_ACTIONS) do states[#states + 1] = state_name end
  table.sort(states)
  return states
end

local VALIDATORS = {}

VALIDATORS.choose_persona = function()
  if G and G.NEURO and G.NEURO.persona and G.NEURO.persona ~= "hiyori" then
    return false
  end
end

local function validate_play_or_discard(action_name)
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return false
  end
  local cr = G.GAME and G.GAME.current_round
  if action_name == "play_hand" then
    if not cr or (cr.hands_left or 0) <= 0 then
      return false
    end
    if G.GAME and G.GAME.blind and G.GAME.blind.block_play then
      return false
    end
    local ok_leg, Legality = pcall(require, "facts.boss.legality")
    if ok_leg and Legality and Legality.play_has_legal_size and not Legality.play_has_legal_size() then
      return false
    end
  end
  if action_name == "discard_hand" then
    if not cr or (cr.discards_left or 0) <= 0 then
      return false
    end
    if Limits.discard_select_max() <= 0 then
      return false
    end
  end
end
VALIDATORS.play_hand = validate_play_or_discard
VALIDATORS.discard_hand = validate_play_or_discard

VALIDATORS.confirm_play = function()
  if not confirm_hand_on() then return false end
  local HH = Utils.lazy_require("handlers.hand_handlers")
  if not (HH and type(HH.confirm_ready) == "function" and HH.confirm_ready()) then return false end
end

VALIDATORS.set_joker_order = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 2 then
    return false
  end
end
VALIDATORS.set_joker_intents = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 1 then
    return false
  end
end

VALIDATORS.use_card = function()
  local function has_usable_consumable(area)
    if not (area and area.cards and #area.cards > 0) then return false end
    for _, card in ipairs(area.cards) do
      if not require("facts.target_contracts").get(card) and consumable_usable_now(card) then return true end
    end
    return false
  end
  local function has_takeable_pack_card(area)
    if not (area and area.cards and #area.cards > 0) then return false end
    for _, card in ipairs(area.cards) do
      if not require("facts.target_contracts").get(card) and can_take_pack_card(card) then return true end
    end
    return false
  end
  local has_any =
    has_usable_consumable(G and G.consumeables)
    or has_takeable_pack_card(CardUtil.pack_area())
  if not has_any then
    return false
  end
end

VALIDATORS.use_directional_card = function()
  local Contracts = require("facts.target_contracts")
  if not (G and G.hand and G.hand.cards and #G.hand.cards >= 2) then return false end
  for _, area in ipairs({ G.consumeables, CardUtil.pack_area() }) do
    for _, card in ipairs((area and area.cards) or {}) do
      if Contracts.get(card) and consumable_usable_now(card) and not CardUtil.is_face_down(card) then return end
    end
  end
  return false
end

VALIDATORS.change_challenge_description = function()
  if not (G and G.CHALLENGES and #G.CHALLENGES > 0) then
    return false
  end
end

VALIDATORS.start_challenge_run = function()
  local tab = G and G.challenge_tab
  local selected = type(tab) == "table"
    or (type(tab) == "number" and G.CHALLENGES and G.CHALLENGES[tab] ~= nil)
  if not selected then
    return false
  end
end

VALIDATORS.copy_seed = function()
  if not (G and G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed) then
    return false
  end
  if not (G.FUNCS and type(G.FUNCS.copy_seed) == "function") then
    return false
  end
end

local function validate_run_setup_overlay()
  if not StateKinds.is_run_setup_overlay() then
    return false
  end
end
VALIDATORS.toggle_seeded_run = validate_run_setup_overlay
VALIDATORS.paste_seed = validate_run_setup_overlay
VALIDATORS.start_setup_run = validate_run_setup_overlay

VALIDATORS.reroll_shop = function()
  if not G or not G.GAME or not G.GAME.dollars then return false end
  local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost or 0
  if type(cost) ~= "number" or cost < 0 then
    return false
  end
  local spendable = get_spendable_dollars()
  local free = tonumber(G.GAME.current_round and G.GAME.current_round.free_rerolls or 0) or 0
  if free <= 0 then
    if cost > 0 and spendable < cost then
      return false
    end
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

VALIDATORS.skip_blind = function()
  if blind_skip_blocker() then
    return false
  end
end

VALIDATORS.exit_overlay_menu = function()
  if not (G and G.OVERLAY_MENU) then
    return false
  end
end

VALIDATORS.reroll_boss = function()
  if not G or not G.GAME then
    return false
  end
  if not CtxEconomy.can_reroll_boss() then
    return false
  end
end

VALIDATORS.cash_out = function()
  if not (G and G.round_eval) then
    return false
  end
  if not (G.FUNCS and type(G.FUNCS.cash_out) == "function") then
    return false
  end
end

VALIDATORS.skip_booster = function()
  if not CardUtil.pack_area() then
    return false
  end
  if not (G.FUNCS and type(G.FUNCS.skip_booster) == "function") then
    return false
  end
end

VALIDATORS.toggle_shop = function()
  if not (G and G.shop) then
    return false
  end
  if not (G.FUNCS and type(G.FUNCS.toggle_shop) == "function") then
    return false
  end
  if require("facts.card_util").untagged_joker_count() > 0 then
    return false
  end
end

for name, validator in pairs(VALIDATORS) do
  local predicate = validator
  local action_name = name
  ActionRegistry.bind_availability(name, function()
    return predicate(action_name) ~= false
  end)
end

-- API/README.md:19-21 -- a name the in-flight commit consumed is not on offer until that commit
-- ends, so the computed set says so and the reconciler withdraws it; nothing strips the registry.
local function consumed_by_commit(action_name)
  local set = G and G.NEURO and G.NEURO.consumed_actions
  return type(set) == "table" and set[action_name] == true
end

function Actions.is_action_valid(action_name)
  if consumed_by_commit(action_name) then return false end
  return ActionRegistry.available(action_name)
end

local function blocking_overlay_actions(state_name)
  if not Actions.is_action_valid("exit_overlay_menu") then return nil end
  local unlock_popup = StateKinds.is_unlock_popup()
  if not unlock_popup
      and (state_name == "RUN_SETUP" or StateKinds.is_progression_overlay()) then
    return nil
  end
  local out = { "exit_overlay_menu" }
  if not unlock_popup and (state_name == "MENU" or state_name == "SPLASH")
      and Actions.is_action_valid("setup_run") then
    out[#out + 1] = "setup_run"
  end
  return out
end

function Actions.get_valid_actions_for_state(state_name)
  Actions.get_static_actions()
  local overlay_actions = blocking_overlay_actions(state_name)
  if overlay_actions then return overlay_actions end
  local all_actions = Actions.get_action_names_for_state(state_name)
  local valid_actions = {}

  for _, action_name in ipairs(all_actions) do
    if Actions.is_action_valid(action_name) then
      table.insert(valid_actions, action_name)
    end
  end

  return valid_actions
end

function Actions.get_available_actions_for_state(state_name)
  return Actions.get_valid_actions_for_state(state_name)
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
local _static_actions_caps = nil

local function caps_signature()
  local names = GameFacts.visible_hand_names()
  local HH = Utils.lazy_require("handlers.hand_handlers")
  local pend = HH and HH.pending and HH.pending()
  return table.concat({
    Limits.play_select_max(), Limits.discard_select_max(), Limits.hand_select_max(),
    names and table.concat(names, ",") or "-",
    (pend and pend.dominant_alt) and "1" or "0",
    require("core.config").bool("NEURO_CONFIRM_REASON_ALWAYS") and "1" or "0",
    confirm_hand_on() and "1" or "0",
  }, "/")
end

function Actions.get_static_actions()
  local caps = caps_signature()
  if _static_actions_cache and _static_actions_caps == caps then return _static_actions_cache end
  local action_set = build_action_set()
  local res = {}
  for _, def in pairs(action_set) do
    res[#res + 1] = def
  end
  table.sort(res, function(a, b) return a.name < b.name end)
  _static_actions_cache = res
  _static_actions_caps = caps
  for _, def in ipairs(res) do
    local states = {}
    for _, state_name in ipairs(Actions.get_known_states()) do
      if Actions.get_state_action_set(state_name)[def.name] then states[state_name] = true end
    end
    ActionRegistry.register(def, states)
  end
  return res
end

Actions.get_static_actions()

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deep_copy(v) end
  return out
end

local function narrow_play_indices(schema)
  local indices = schema and schema.properties and schema.properties.indices
  if type(indices) ~= "table" then return nil end
  local ok_mod, Legality = pcall(require, "facts.boss.legality")
  if not ok_mod or type(Legality) ~= "table" or type(Legality.play_size_bounds) ~= "function" then
    return nil
  end
  local ok, min_items, max_items = pcall(Legality.play_size_bounds)
  if not ok or type(min_items) ~= "number" or type(max_items) ~= "number" then return nil end
  if min_items > max_items then return nil end
  if indices.minItems == min_items and indices.maxItems == max_items then return nil end
  local out = deep_copy(schema)
  out.properties.indices.minItems = min_items
  out.properties.indices.maxItems = max_items
  return out
end

ActionRegistry.bind_schema_narrower("play_hand", narrow_play_indices)

return Actions
