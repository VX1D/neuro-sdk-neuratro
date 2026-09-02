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
local function resolve_play_schema()
  local props = {
    transaction_id = { type = "integer", minimum = 1 },
    answer = { type = "string", enum = { "yes", "no" } },
    reason = { type = "string" },
  }
  return {
    type = "object", properties = props,
    required = { "transaction_id", "answer" },
  }
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

local function card_action_schema(area, hand_max, directional, require_name)
  local properties = {
    area = { type = "string", enum = { area } },
    index = { type = "integer", minimum = 1 },
    name = { type = "string" },
    plan = plan_schema(),
  }
  local required = require_name and { "area", "index", "name" } or { "area", "index" }
  if directional then
    properties.name.minLength = 1
    properties.left_index = { type = "integer", minimum = 1 }
    properties.right_index = { type = "integer", minimum = 1 }
    required = { "area", "index", "name", "left_index", "right_index" }
  else
    properties.hand_indices = {
      type = "array", items = { type = "integer", minimum = 1 },
      minItems = 1, maxItems = hand_max, uniqueItems = true,
    }
  end
  return { type = "object", properties = properties, required = required }
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
    use_consumable = action_def("use_consumable", "Use one owned Consumable by area='consumeables', 1-indexed index, and its complete displayed name. A targeting card also needs hand_indices. Copy the offered payload; name binds the identity if slots shift. This consumes the card; include plan only when requested.",
      card_action_schema("consumeables", hand_max), { hand_indices = "hand positions" }),
    use_directional_consumable = action_def("use_directional_consumable", "Use one owned directional Consumable. Pass area='consumeables', index, displayed name, left_index as the visual-left source, and right_index as the visual-right destination; left_index < right_index. Include plan only when requested.",
      card_action_schema("consumeables", hand_max, true)),
    choose_pack_card = action_def("choose_pack_card", "Choose one card from the open pack by area='booster_pack' and 1-indexed index. A targeting card also needs hand_indices. Optional name rejects a shifted slot. This spends one pack choice; include plan only when requested.",
      card_action_schema("booster_pack", hand_max), { hand_indices = "hand positions" }),
    choose_directional_pack_card = action_def("choose_directional_pack_card", "Choose one directional card from the open pack. Pass area='booster_pack', index, displayed name, left_index as the visual-left source, and right_index as the visual-right destination; left_index < right_index. Include plan only when requested.",
      card_action_schema("booster_pack", hand_max, true)),
    buy_from_shop = action_def("buy_from_shop", "Buy an item from a Shop items row by area + 1-indexed index and its complete displayed `name`. Copy the offered payload: name binds the target if shop rows shift. For a targeted consumable, buy with use=false then use_consumable, or use_directional_consumable when its two targets have different roles. When requested by `Your move`, include only the requested plan fields; they describe the plan after buying and are saved with the action.", {
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
    sell_card = action_def("sell_card", "Sell a joker (Your jokers) or consumable (Consumables) by area + 1-indexed index and its complete displayed `name`. Copy the offered payload: name binds the exact target if slots shift. When requested by `Your move`, include only the requested plan fields; they describe the plan after selling and are saved with the action.", {
      type = "object",
      properties = {
        area = { type = "string", enum = { "jokers", "consumeables" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string" },
        plan = plan_schema()
      },
      required = { "area", "index" }
    }),
    play_hand = action_def("play_hand", "Play {count:indices:hand card} as a poker hand. " .. (confirm_hand_on() and "The first play_hand either commits immediately when no guard applies, or opens one confirmation without spending a hand. Once a confirmation is open, only `resolve_play` is valid: use the exact integer `transaction_id` shown in the prompt with `answer:\"yes\"` to commit or `answer:\"no\"` to cancel. Cancelling spends the single review for this unchanged hand: the next play_hand is the final choice and commits immediately, so use discard_hand first if you want the cards to change. On your last hand with no discards left and at most one ready hand there is nothing to weigh, so the first send commits immediately unless the hand is one of the three lowest-ranking types or the boss blind has something to say about it." or "This commits the selection on the first send, using one hand (H) and scoring.") .. " `indices` are the 1-indexed hand positions from Your hand. Judge the hand yourself from Your hand, the Hand levels, and the Ready/Close facts before playing. When requested by `Your move`, include only the requested plan fields (including `boss_plan` during boss blinds); they describe the plan for this round and are saved with the action.", {
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
    resolve_play = action_def("resolve_play", "Resolve the delivered play_hand proposal. Pass the exact integer `transaction_id` and required `answer`. `answer:\"yes\"` commits the named cards, spends one hand, and scores; omit `reason` for yes. `answer:\"no\"` cancels without playing, discarding, or drawing. No spends the one review for this unchanged hand: use discard_hand next for a redraw, or play_hand for a specific alternative; that next play commits immediately. For no, optional `reason` should name that next action and its exact indices; a compact reminder is carried into the final-choice prompt. While the transaction is open, no other hand-decision action is valid. A stale or mismatched transaction_id is acknowledged without mutation.", resolve_play_schema()),
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
    select_stake = action_def("select_stake", "Change run stake. Pass `to_key`: the stake number from the Stakes list (1-indexed).", {
      type = "object",
      properties = { to_key = { type = "integer", minimum = 1 } },
      required = { "to_key" }
    }),
    select_challenge = action_def("select_challenge", "Select a challenge. Pass `id`: the challenge id or displayed name (from the challenge list).", {
      type = "object",
      properties = { id = { type = "string" } },
      required = { "id" }
    }),
    select_deck = action_def("select_deck", "Select a deck. Pass `back`: the deck key (e.g. b_red, b_blue).", {
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
    leave_shop = action_def("leave_shop", "Exit shop and continue run flow. Blocked while any joker carries no tag; record_joker_roles tags it first. When requested by `Your move`, include only the requested plan fields; they describe the plan after leaving and are saved with the action. `joker_order_confirmed`: true leaves on the current joker order.", {
      type = "object",
      properties = {
        plan = plan_schema(),
        joker_order_confirmed = { type = "boolean" }
      },
      required = {}
    }),
    record_joker_roles = action_def("record_joker_roles", "Record the role each joker plays in your build. Pass `intents`: a list of { index (1-indexed joker position), tag, note (optional) }. CORE: the piece your build is built around. SCALING: it grows over time and pays off later. HOLD: useful for now, keep it while it earns its slot. CHANGE: you want to swap it out when something better shows up. A tag stays on that joker for the rest of the run and follows the card, not the slot -- retag it whenever your view changes. Tagging never sells, buys or moves anything: every joker sale still needs its own fresh confirmation, and the tag only changes what that confirmation reminds you of. `note` records why, in your own words -- shown on that joker's row while shopping and echoed back if you later try to sell it. A note is stored exactly as you write it, at any length, and is never refused, so the tags in the same call always land. Leaving `note` out keeps any note already on file; passing `note`: '' clears it. While every joker carries a tag you can leave the shop; untagged jokers block leave_shop until you tag them.", {
      type = "object",
      properties = {
        intents = joker_intents_schema()
      },
      required = { "intents" }
    }),
    record_plan = action_def("record_plan", "State committed decisions, verb first -- not analysis or a copy of the board. `hand_plan` = the line you will play this blind. `build_plan` = your build direction and next upgrade. `money_plan` = one spend-or-hold decision. Optional `hand_focus` declares an exact visible hand name as `primary` and optional `fallback`; it is echoed as your declaration and never blocks another play. Dynamic facts (cash, joker roster, boss text) come from live state; do not repeat them.", {
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
  skip_pack = "Skip current booster pack.",
  exit_overlay_menu = "Close an open overlay/popup menu and continue.",
  cash_out = "Collect round payout and continue to shop flow.",
  open_run_setup = "Open the run setup screen to choose your deck, stake, and seed before starting a run.",
  start_challenge_run = "Start a challenge run with preset rules and restrictions.",
  start_run = "Start a run from the setup screen with your chosen options.",
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
    "open_run_setup",
    "select_deck",
    "toggle_seeded_run",
    "paste_seed",
    "start_run",
  },
  MENU = {
    "choose_persona",
    "open_run_setup",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "select_stake",
    "select_deck",
    "start_run",
    "select_challenge",
    "start_challenge_run",
  },
  RUN_SETUP = {
    "choose_persona",
    "open_run_setup",
    "start_run",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "select_stake",
    "select_deck",
  },
  GAME_OVER = {
    "choose_persona",
    "open_run_setup",
    "toggle_seeded_run",
    "copy_seed",
    "paste_seed",
    "select_deck",
    "start_run",
  },
  BLIND_SELECT = {
    "select_blind",
    "skip_blind",
    "reroll_boss",
    "sell_card",
    "set_joker_order",
    "record_joker_roles",
    "record_plan",
    "use_consumable",
    "use_directional_consumable",
  },
  SELECTING_HAND = {
    "play_hand",
    "discard_hand",
    "resolve_play",
    "use_consumable",
    "use_directional_consumable",
    "sell_card",
    "set_joker_order",
  },
  SHOP = {
    "buy_from_shop",
    "sell_card",
    "use_consumable",
    "use_directional_consumable",
    "reroll_shop",
    "leave_shop",
    "set_joker_order",
    "record_joker_roles",
    "record_plan",
  },
  ROUND_EVAL = {
    "cash_out",
    "record_plan",
  },
}

local PACK_ACTIONS = {
  "choose_pack_card",
  "choose_directional_pack_card",
  "use_consumable",
  "use_directional_consumable",
  "sell_card",
  "skip_pack",
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

VALIDATORS.resolve_play = function()
  if not confirm_hand_on() then return false end
  local HH = Utils.lazy_require("handlers.hand_handlers")
  if not (HH and type(HH.confirm_ready) == "function" and HH.confirm_ready()) then return false end
end

VALIDATORS.set_joker_order = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 2 then
    return false
  end
end
VALIDATORS.record_joker_roles = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 1 then
    return false
  end
end

VALIDATORS.use_consumable = function()
  local function has_usable_consumable(area)
    if not (area and area.cards and #area.cards > 0) then return false end
    for _, card in ipairs(area.cards) do
      if not require("facts.target_contracts").get(card) and consumable_usable_now(card) then return true end
    end
    return false
  end
  if not has_usable_consumable(G and G.consumeables) then
    return false
  end
end

VALIDATORS.choose_pack_card = function()
  local area = CardUtil.pack_area()
  for _, card in ipairs((area and area.cards) or {}) do
    if not require("facts.target_contracts").get(card) and can_take_pack_card(card) then return end
  end
  return false
end

local function directional_available(area)
  local Contracts = require("facts.target_contracts")
  if not (G and G.hand and G.hand.cards and #G.hand.cards >= 2) then return false end
  for _, card in ipairs((area and area.cards) or {}) do
    if Contracts.get(card) and consumable_usable_now(card) and not CardUtil.is_face_down(card) then return end
  end
  return false
end
VALIDATORS.use_directional_consumable = function() return directional_available(G and G.consumeables) end
VALIDATORS.choose_directional_pack_card = function() return directional_available(CardUtil.pack_area()) end

VALIDATORS.select_challenge = function()
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
VALIDATORS.start_run = validate_run_setup_overlay

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

VALIDATORS.skip_pack = function()
  if not CardUtil.pack_area() then
    return false
  end
  if not (G.FUNCS and type(G.FUNCS.skip_booster) == "function") then
    return false
  end
end

VALIDATORS.leave_shop = function()
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

local function hand_transaction_blocks(action_name)
  local HandTx = Utils.lazy_require("core.hand_transaction")
  if not HandTx or not HandTx.stale_mutator then return false end
  return HandTx.stale_mutator(action_name)
end

function Actions.is_action_valid(action_name)
  if hand_transaction_blocks(action_name) then return false end
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
      and Actions.is_action_valid("open_run_setup") then
    out[#out + 1] = "open_run_setup"
  end
  return out
end

function Actions.get_valid_actions_for_state(state_name)
  Actions.get_static_actions()
  local overlay_actions = blocking_overlay_actions(state_name)
  if overlay_actions then return overlay_actions end
  if state_name == "SELECTING_HAND" then
    local HandTx = Utils.lazy_require("core.hand_transaction")
    if HandTx then
      local mode = HandTx.mode()
      if mode == "publishing" then return {} end
      if mode == "resolution" then
        local HH = Utils.lazy_require("handlers.hand_handlers")
        if HH and HH.confirm_ready and HH.confirm_ready() then return { "resolve_play" } end
        return {}
      end
    end
  end
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
  return table.concat({
    Limits.play_select_max(), Limits.discard_select_max(), Limits.hand_select_max(),
    names and table.concat(names, ",") or "-",
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
