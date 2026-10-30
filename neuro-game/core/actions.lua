local Actions = {}
local CtxEconomy = require("facts.economy_facts")
local StateKinds = require("core.state_kinds")
local ActionRegistry = require("core.action_registry")
local Limits = require("core.plan_limits")
local GameFacts = require("facts.game_facts")
local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local ActionResult = require("core.action_result")

local function unlocked_deck_keys()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back
  if type(pool) ~= "table" then return nil end
  local keys = {}
  for _, entry in ipairs(pool) do
    if type(entry) == "table" and type(entry.key) == "string" and entry.key ~= ""
        and entry.unlocked ~= false then
      keys[#keys + 1] = entry.key
    end
  end
  if #keys == 0 then return nil end
  table.sort(keys)
  return keys
end

local function challenge_ids()
  local ids = require("facts.deck_facts").selectable_challenge_ids()
  if #ids == 0 then return nil end
  return ids
end

local function stake_max()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  local n = type(pool) == "table" and #pool or 0
  return n >= 1 and n or 8
end

local function text_schema(max_length)
  return { type = "string", maxLength = max_length }
end
local function action_def(name, description, schema)
  return { name = name, description = description, schema = schema }
end

-- The available hand types form a bounded enum that grows at most three times per run.
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
    hand_plan = text_schema(Limits.PLAN_TEXT_MAX),
    build_plan = text_schema(Limits.PLAN_TEXT_MAX),
    money_plan = text_schema(Limits.PLAN_TEXT_MAX),
    hand_focus = hand_focus_schema(),
  }
  if opts and opts.boss then
    props.boss_plan = text_schema(Limits.PLAN_TEXT_MAX)
  end
  return { type = "object", properties = props }
end

local function boss_plan_schema()
  return {
    type = "object",
    properties = {
      boss_plan = text_schema(Limits.PLAN_TEXT_MAX),
    },
  }
end

local function confirm_hand_on()
  local HH = Utils.lazy_require("handlers.hand_handlers")
  return not (HH and HH.confirm_hand_on) or HH.confirm_hand_on()
end

local function resolve_play_schema()
  return {
    type = "object",
    properties = { answer = { type = "string", enum = { "yes", "no" } } },
    required = { "answer" },
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
        note = text_schema(Limits.JOKER_NOTE_MAX)
      },
      required = { "index", "tag" }
    }
  }
end

local function card_action_schema(area, directional)
  local properties = {
    area = { type = "string", enum = { area } },
    index = { type = "integer", minimum = 1 },
    name = { type = "string" },
    plan = plan_schema(),
  }
  local required = { "area", "index" }
  if directional then
    properties.name.minLength = 1
    properties.left_index = { type = "integer", minimum = 1 }
    properties.right_index = { type = "integer", minimum = 1 }
    required = { "area", "index", "name", "left_index", "right_index" }
  else
    properties.hand_indices = {
      type = "array", items = { type = "integer", minimum = 1 },
      minItems = 1, maxItems = Limits.hand_select_max(), uniqueItems = true,
    }
  end
  return { type = "object", properties = properties, required = required }
end

local function build_param_actions()
  return {
    select_blind = action_def("select_blind", "Select the active blind for this ante via required blind: 'small', 'big', or 'boss'. Optional plan.hand_focus names an exact visible hand as primary with an optional fallback.", {
      type = "object",
      properties = {
        blind = { type = "string", enum = { "small", "big", "boss" } },
        plan = plan_schema({ boss = true })
      },
      required = { "blind" }
    }),
    use_consumable = action_def("use_consumable", "Use an owned consumable at required area and index (include its name, and hand_indices when it targets hand cards).",
      card_action_schema("consumables")),
    use_directional_consumable = action_def("use_directional_consumable", "Use a directional consumable with required area, index, name, left_index (the hand card it applies to), and right_index (the card it takes from).",
      card_action_schema("consumables", true)),
    choose_pack_card = action_def("choose_pack_card", "Take a card from the open, already-paid pack at required area and index (include its name, and hand_indices when it targets hand cards). A picked consumable is used at once.",
      card_action_schema("booster_pack")),
    choose_directional_pack_card = action_def("choose_directional_pack_card", "Choose a directional card from the already-paid open pack with required area, index, name, left_index (the hand card it applies to), and right_index (the card it takes from). A picked consumable is used at once.",
      card_action_schema("booster_pack", true)),
    buy_from_shop = action_def("buy_from_shop", "Buy the shop item at required area and index (include its offered name); use=true only for a direct-use consumable. The first voucher buy executes nothing and returns a review; the next is final.",
      {
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
    sell_card = action_def("sell_card", "Sell the card at required area and index (include its offered name). The first joker sale executes nothing and returns a review; the next sale is final.",
      {
      type = "object",
      properties = {
        area = { type = "string", enum = { "jokers", "consumables" } },
        index = { type = "integer", minimum = 1 },
        name = { type = "string" },
        plan = plan_schema()
      },
      required = { "area", "index" }
    }),
    play_hand = action_def("play_hand",
      "Play the hand cards at the required 1-based indices as one poker hand. "
      .. (confirm_hand_on() and "A first send that returns a review plays nothing; answer the review yes or no." or "It commits on the first send, spending one hand."),
      {
      type = "object",
      properties = {
        indices = {
          type = "array",
          items = { type = "integer", minimum = 1 },
          minItems = 1, maxItems = Limits.play_select_max(), uniqueItems = true
        },
        plan = boss_plan_schema()
      },
      required = { "indices" }
    }),
    resolve_play = action_def("resolve_play", "Answer the open play review with required answer: yes plays the reviewed cards, no plays nothing.",
      resolve_play_schema()),
    discard_hand = action_def("discard_hand", "Discard distinct 1-based hand indices via required indices then draw replacement cards. It is final and spends one discard, not a hand.", {
      type = "object",
      properties = {
        indices = {
          type = "array",
          items = { type = "integer", minimum = 1 },
          minItems = 1, maxItems = math.max(1, Limits.discard_select_max()), uniqueItems = true
        },
        plan = boss_plan_schema()
      },
      required = { "indices" }
    }),
    select_stake = action_def("select_stake", "Set the stake with required to_key: the number of a stake from the Stakes list that is unlocked for the current deck.", {
      type = "object",
      properties = { to_key = { type = "integer", minimum = 1, maximum = stake_max() } },
      required = { "to_key" }
    }),
    select_challenge = action_def("select_challenge", "Select an unlocked challenge by its exact id, the value shown before each challenge name in the challenge list.", {
      type = "object",
      properties = { id = { type = "string", enum = challenge_ids() } },
      required = { "id" }
    }),
    select_deck = action_def("select_deck", "Select a deck with the required back key.", {
      type = "object",
      properties = { back = { type = "string", enum = unlocked_deck_keys() } },
      required = { "back" }
    }),
    paste_seed = action_def("paste_seed", "Paste an optional alphanumeric seed (1-8 characters); omit it or send it empty to use the clipboard.", {
      type = "object",
      properties = { seed = { type = "string", pattern = "^[A-Za-z0-9]*$", maxLength = 8 } },
      required = {}
    }),
    choose_persona = action_def("choose_persona", "Set the persona with required persona (neuro or evil).", {
    type = "object",
    properties = {
      persona = {
        type = "string",
        enum = { "neuro", "evil" }
      }
    },
    required = { "persona" }
    }),
    set_joker_order = action_def("set_joker_order", "Move a joker from required from_index to required to_index.", {
      type = "object",
      properties = {
        from_index = { type = "integer", minimum = 1 },
        to_index = { type = "integer", minimum = 1 }
      },
      required = { "from_index", "to_index" }
    }),
    reroll_shop = action_def("reroll_shop", "Reroll the shop's card offerings, replacing them with a new random set -- not the voucher and not the packs. It costs the current reroll price, which the shop state shows together with the next one.", {
      type = "object",
      properties = {
        plan = plan_schema()
      },
      required = {}
    }),
    leave_shop = action_def("leave_shop", "Leave the shop; optional intents tags untagged jokers, and joker_order_confirmed: true keeps the order when a reorder gain is shown. The first send executes nothing and returns a review when leaving forfeits interest or your lineup changed.", {
      type = "object",
      properties = {
        plan = plan_schema(),
        joker_order_confirmed = { type = "boolean" },
        intents = joker_intents_schema()
      },
      required = {}
    }),
    record_joker_roles = action_def("record_joker_roles", "Record each joker's role in your build via required intents: a list of { index, tag, optional note of up to "
      .. Limits.JOKER_NOTE_MAX .. " characters }. Tagging never sells, buys or moves a joker.", {
      type = "object",
      properties = {
        intents = joker_intents_schema()
      },
      required = { "intents" }
    }),
    record_plan = action_def("record_plan", "State committed decisions, verb first: hand_plan for this blind, build_plan for your build direction and next upgrade, money_plan for one spend-or-hold call. Optional hand_focus names an exact visible hand as primary with an optional fallback.", {
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
    return "The blind selection screen is not loaded yet, so nothing was skipped. Wait for it to be shown, then skip the blind again."
  end
  local on_deck = get_selectable_blind_key()
  if on_deck == "Boss" then
    return "The boss blind cannot be skipped. Select it with blind 'boss' to play it."
  end
  if not (on_deck and SKIPPABLE_BLINDS[on_deck]) then
    return "No Small or Big blind is selectable right now, so there is nothing to skip. Choose one of the other actions offered for this screen."
  end
  local rr = G.GAME.round_resets
  local choice = rr.blind_choices and rr.blind_choices[on_deck]
  local def = choice and G.P_BLINDS and G.P_BLINDS[choice]
  if def and def.unskippable then
    return "This blind cannot be skipped. Select it with blind '" .. string.lower(on_deck) .. "' to play it."
  end
  if not (rr.blind_tags and rr.blind_tags[on_deck]) then
    return "This blind offers no skip reward tag, so it cannot be skipped. Select it with blind '" .. string.lower(on_deck) .. "' to play it."
  end
  return nil
end
Actions.blind_skip_blocker = blind_skip_blocker

local can_take_pack_card = CardUtil.can_take_pack_card
local consumable_usable_now = CardUtil.consumable_usable_now

local SIMPLE_ACTION_DESCS = {
  skip_blind = "Skip the current blind for its reward.",
  reroll_boss = "Reroll the current boss blind.",
  skip_pack = "Skip the open booster pack.",
  exit_overlay_menu = "Close the open overlay menu.",
  cash_out = "Collect the round payout.",
  open_run_setup = "Open run setup.",
  start_challenge_run = "Start a challenge run.",
  start_run = "Start the configured run.",
  toggle_seeded_run = "Toggle seeded-run mode.",
  copy_seed = "Copy the current run seed.",
}

local UNIVERSAL_ACTIONS = {
  "exit_overlay_menu",
}

local function build_action_set()
  local action_set = build_param_actions()
  for name, desc in pairs(SIMPLE_ACTION_DESCS) do
    action_set[name] = action_def(name, desc, { type = "object", properties = {}, required = {} })
  end
  return action_set
end

local STATE_ACTIONS = {
  SPLASH = {
    "choose_persona",
    "open_run_setup",
    "select_deck",
  },
  MENU = {
    "choose_persona",
    "open_run_setup",
    "copy_seed",
    "select_stake",
    "select_deck",
    "select_challenge",
    "start_challenge_run",
  },
  RUN_SETUP = {
    "choose_persona",
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
    "copy_seed",
    "select_deck",
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
STATE_ACTIONS.SMODS_BOOSTER_OPENED = PACK_ACTIONS

local function state_action_list(state_name)
  local list = STATE_ACTIONS[state_name]
  if not list and StateKinds.is_pack_state(state_name) then list = PACK_ACTIONS end
  return list or {}
end

local function state_action_names(state_name)
  local res, seen = {}, {}
  for _, list in ipairs({ state_action_list(state_name), UNIVERSAL_ACTIONS }) do
    for i = 1, #list do
      local name = list[i]
      if not seen[name] then
        res[#res + 1] = name
        seen[name] = true
      end
    end
  end
  return res, seen
end

function Actions.get_action_names_for_state(state_name)
  return (state_action_names(state_name))
end

-- A screen is a state with its own action set; transitional states and screen wipes have none.
function Actions.screen_action_set(state_name)
  if G and G.screenwipe then return nil end
  if not (STATE_ACTIONS[state_name] or StateKinds.is_pack_state(state_name)) then return nil end
  return Actions.get_state_action_set(state_name)
end

function Actions.get_known_states()
  local states = {}
  for state_name in pairs(STATE_ACTIONS) do states[#states + 1] = state_name end
  table.sort(states)
  return states
end

local VALIDATORS = {}
local CHOOSE_OFFERED = "; choose one of the actions offered now."

-- A gate replaces the validator where registration must lead usability: a review is answerable once it opens.
local REGISTRATION_GATES = {
  resolve_play = function()
    local Gate = Utils.lazy_require("core.gate")
    return confirm_hand_on() and Gate ~= nil and Gate.proposal() ~= nil
  end,
}

VALIDATORS.choose_persona = function()
  if G and G.NEURO and G.NEURO.persona and G.NEURO.persona ~= "hiyori" then
    return false, "Your persona is already set for this session; continue with the actions offered now."
  end
end

local function validate_play_or_discard(action_name)
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return false, "Your hand has no cards yet; wait for the draw, then choose again."
  end
  local cr = G.GAME and G.GAME.current_round
  if action_name == "play_hand" then
    if not cr or (cr.hands_left or 0) <= 0 then
      return false, "No hands are left this round; choose another offered action."
    end
    if G.GAME and G.GAME.blind and G.GAME.blind.block_play then
      return false, "The current blind blocks playing a hand right now; choose another offered action."
    end
    local ok_leg, Legality = pcall(require, "facts.boss.legality")
    if ok_leg and Legality and Legality.play_has_legal_size and not Legality.play_has_legal_size() then
      return false, "No selection of your hand is a legal play under the current boss rule; discard to change your hand instead."
    end
  end
  if action_name == "discard_hand" then
    if not cr or (cr.discards_left or 0) <= 0 then
      return false, "No discards are left this round; play a hand instead."
    end
    if Limits.discard_select_max() <= 0 then
      return false, "The current rules let you discard no cards; play a hand instead."
    end
  end
end
VALIDATORS.play_hand = validate_play_or_discard
VALIDATORS.discard_hand = validate_play_or_discard

VALIDATORS.resolve_play = function()
  if not confirm_hand_on() then
    return false, "Play confirmation is off, so there is no review to answer; a play commits directly."
  end
  local HH = Utils.lazy_require("handlers.hand_handlers")
  if not (HH and type(HH.confirm_ready) == "function" and HH.confirm_ready()) then
    return false, "No play review is waiting for an answer; play a hand to open one."
  end
end

VALIDATORS.set_joker_order = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 2 then
    return false, "Reordering needs at least two jokers, and you have fewer" .. CHOOSE_OFFERED
  end
end
VALIDATORS.record_joker_roles = function()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards < 1 then
    return false, "You own no jokers, so there is nothing to tag" .. CHOOSE_OFFERED
  end
end

VALIDATORS.use_consumable = function()
  local area = G and G.consumeables
  if not (area and area.cards and #area.cards > 0) then
    return false, "You hold no consumables to use" .. CHOOSE_OFFERED
  end
  for _, card in ipairs(area.cards) do
    if not require("facts.target_contracts").get(card) and consumable_usable_now(card) then return end
  end
  return false, "None of your consumables can be used right now (no valid target or condition); choose another action."
end

VALIDATORS.choose_pack_card = function()
  local area = CardUtil.pack_area()
  for _, card in ipairs((area and area.cards) or {}) do
    if not require("facts.target_contracts").get(card) and can_take_pack_card(card) then return end
  end
  return false, "No card in the open pack can be taken right now (no free slot or no valid target); skip the pack or make room first."
end

local function directional_available(area)
  local Contracts = require("facts.target_contracts")
  if not (G and G.hand and G.hand.cards and #G.hand.cards >= 2) then
    return false, "A directional card needs at least two cards in your hand" .. CHOOSE_OFFERED
  end
  for _, card in ipairs((area and area.cards) or {}) do
    if Contracts.get(card) and consumable_usable_now(card) and not CardUtil.is_hidden(card) then return end
  end
  return false, "No directional card here can be used right now; choose another action."
end
VALIDATORS.use_directional_consumable = function() return directional_available(G and G.consumeables) end
VALIDATORS.choose_directional_pack_card = function() return directional_available(CardUtil.pack_area()) end

VALIDATORS.select_challenge = function()
  if not challenge_ids() then
    return false, "No challenge is unlocked yet; set up a normal run instead."
  end
end

VALIDATORS.start_challenge_run = function()
  if not require("facts.deck_facts").selected_challenge() then
    return false, "No challenge is selected. Select an unlocked challenge by id first, then start the challenge run."
  end
end

VALIDATORS.copy_seed = function()
  if not (G and G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed) then
    return false, "There is no run seed to copy yet" .. CHOOSE_OFFERED
  end
end

local function validate_run_setup_overlay()
  if not StateKinds.is_run_setup_overlay() then
    return false, "The run setup screen is not open. Open run setup first, then choose again."
  end
end
VALIDATORS.toggle_seeded_run = validate_run_setup_overlay
VALIDATORS.paste_seed = validate_run_setup_overlay
VALIDATORS.start_run = validate_run_setup_overlay

VALIDATORS.reroll_shop = function()
  if not G or not G.GAME or not G.GAME.dollars then return false, "The shop is not open" .. CHOOSE_OFFERED end
  local cost = G.GAME.current_round and G.GAME.current_round.reroll_cost or 0
  if type(cost) ~= "number" or cost < 0 then
    return false, "The reroll price is not set yet; choose another action."
  end
  local spendable = get_spendable_dollars()
  local free = tonumber(G.GAME.current_round and G.GAME.current_round.free_rerolls or 0) or 0
  if free <= 0 then
    if cost > 0 and spendable < cost then
      return false, string.format("A reroll costs %s and you have %s to spend; buy, sell or leave instead.",
        Utils.money(cost), Utils.money(spendable))
    end
    -- The game permits this reroll; this gate is mod policy, not a game restriction.
    local cheapest = cost > 0 and CtxEconomy.cheapest_buyable(spendable, true)
    if cheapest and (spendable - cost) < cheapest then
      return false, string.format("The game allows this %s reroll, but this mod withholds it: afterwards you could not afford even the cheapest pack or voucher it leaves on offer (%s), and only a card in the new row could cost less; buy something or leave instead.",
        Utils.money(cost), Utils.money(cheapest))
    end
  end
end

VALIDATORS.skip_blind = function()
  local blocked = blind_skip_blocker()
  if blocked then return false, blocked end
end

VALIDATORS.exit_overlay_menu = function()
  if not StateKinds.is_closable_overlay() then
    return false, "No overlay menu that can be closed is open. Choose one of the actions offered for this screen."
  end
end

VALIDATORS.select_deck = function()
  if #require("facts.deck_facts").list_selectable_backs() == 1 then
    return false, "Only one deck is unlocked, so there is no other deck to select" .. CHOOSE_OFFERED
  end
end

VALIDATORS.select_stake = function()
  if #require("facts.deck_facts").selectable_stakes() == 1 then
    return false, "Only one stake is unlocked for this deck, so there is no other stake to select" .. CHOOSE_OFFERED
  end
end

VALIDATORS.reroll_boss = function()
  if not G or not G.GAME then
    return false, "Blind select is not open" .. CHOOSE_OFFERED
  end
  local can, enabled = CtxEconomy.can_reroll_boss()
  if not enabled then
    return false, "Rerolling the boss needs the Director's Cut or Retcon voucher" .. CHOOSE_OFFERED
  end
  if not can then
    return false, string.format("You can't afford the %s boss reroll right now", Utils.money(CtxEconomy.BOSS_REROLL_COST)) .. CHOOSE_OFFERED
  end
end

VALIDATORS.cash_out = function()
  if not GameFacts.cash_out_button() then
    return false, G and G.round_eval
      and "The round summary is still counting up the payout, so there is no Cash Out button yet; cash out again once it appears."
      or "There is no round payout to collect on this screen; choose one of the actions offered now."
  end
end

VALIDATORS.skip_pack = function()
  if not CardUtil.pack_area() then
    return false, "No booster pack is open, so there is nothing to skip" .. CHOOSE_OFFERED
  end
end

VALIDATORS.leave_shop = function()
  if not (G and G.shop) then
    return false, "The shop is not open" .. CHOOSE_OFFERED
  end
end

for name, validator in pairs(VALIDATORS) do
  local predicate = validator
  local action_name = name
  ActionRegistry.bind_availability(name, function()
    local verdict, reason = predicate(action_name)
    if verdict ~= false then return true end
    assert(type(reason) == "string" and reason ~= "", "validator for " .. action_name .. " refused without a reason")
    return false, reason
  end)
end

local function proposal_blocks(action_name)
  local Gate = Utils.lazy_require("core.gate")
  return Gate ~= nil and Gate.stale_mutator(action_name)
end

local function available_on_screen(action_name)
  if proposal_blocks(action_name) then return false end
  return ActionRegistry.available(action_name)
end

local function blocking_overlay_actions(state_name)
  if not (G and G.OVERLAY_MENU) then return nil end
  local unlock_popup = StateKinds.is_unlock_popup()
  if not unlock_popup
      and (state_name == "RUN_SETUP" or StateKinds.is_progression_overlay()) then
    return nil
  end
  if not available_on_screen("exit_overlay_menu") then
    -- A modal she cannot close leaves no in-run move beneath it; on a menu screen its buttons are the screen's moves.
    if StateKinds.is_menu_state(state_name) then return nil end
    return {}
  end
  local out = { "exit_overlay_menu" }
  if not unlock_popup and (state_name == "MENU" or state_name == "SPLASH")
      and available_on_screen("open_run_setup") then
    out[#out + 1] = "open_run_setup"
  end
  return out
end

Actions.overlay_actions = blocking_overlay_actions

Actions.OVERLAY_FACT = "A popup or menu is open over the game, so nothing was applied."
Actions.OVERLAY_RETRY = "Close the overlay, then choose again."
Actions.OVERLAY_REASKED = "The next decision offers closing the overlay."
local OVERLAY_REASON = Actions.OVERLAY_FACT .. " " .. Actions.OVERLAY_RETRY

function Actions.overlay_block_reason(action_name)
  local offer = blocking_overlay_actions(require("core.state").get_state_name())
  if not offer then return nil end
  for i = 1, #offer do
    if offer[i] == action_name then return nil end
  end
  return OVERLAY_REASON
end

function Actions.is_action_valid(action_name)
  if Actions.overlay_block_reason(action_name) then return false end
  return available_on_screen(action_name)
end

-- Registered only while usable at window build, like an SDK ActionWindow (README.md:35); nil while it waits on the game keeps the current registration.
function Actions.registrable(name)
  if Actions.overlay_block_reason(name) or proposal_blocks(name) then return false end
  local gate = REGISTRATION_GATES[name]
  if gate then return gate() == true end
  local usable, reason = ActionRegistry.availability(name)
  if usable then return true end
  if ActionResult.is_wait(reason) then return nil end
  return false
end

function Actions.unavailable_reason(action_name)
  local overlay = Actions.overlay_block_reason(action_name)
  if overlay then return overlay end
  if proposal_blocks(action_name) then
    return "A play review is open; answer it yes or no first."
  end
  return ActionRegistry.unavailable_reason(action_name)
end

function Actions.get_valid_actions_for_state(state_name)
  Actions.get_static_actions()
  local overlay_actions = blocking_overlay_actions(state_name)
  if overlay_actions then return overlay_actions end
  if state_name == "SELECTING_HAND" then
    local Gate = Utils.lazy_require("core.gate")
    if Gate and Gate.proposal() then
      local HH = Utils.lazy_require("handlers.hand_handlers")
      if HH and HH.confirm_ready and HH.confirm_ready() then return { "resolve_play" } end
      return {}
    end
  end
  local valid_actions = {}
  for _, action_name in ipairs(Actions.get_action_names_for_state(state_name)) do
    if Actions.is_action_valid(action_name) then valid_actions[#valid_actions + 1] = action_name end
  end
  return valid_actions
end

local _state_action_sets = {}

function Actions.get_state_action_set(state_name)
  if not state_name then return {} end
  if not _state_action_sets[state_name] then _state_action_sets[state_name] = select(2, state_action_names(state_name)) end
  return _state_action_sets[state_name]
end

local _static_actions_cache = nil
local _static_actions_caps = nil

local function caps_signature()
  return table.concat({
    Limits.play_select_max(), Limits.discard_select_max(), Limits.hand_select_max(),
    stake_max(),
    table.concat(unlocked_deck_keys() or {}, ","),
    table.concat(challenge_ids() or {}, ","),
    table.concat(GameFacts.visible_hand_names() or {}, ","),
    confirm_hand_on() and "1" or "0",
  }, "/")
end

Actions.catalogue_signature = caps_signature

function Actions.get_static_actions()
  local caps = caps_signature()
  if _static_actions_cache and _static_actions_caps == caps then return _static_actions_cache end
  _static_actions_caps = caps
  local action_set = build_action_set()
  local res = {}
  for _, def in pairs(action_set) do
    res[#res + 1] = def
  end
  table.sort(res, function(a, b) return a.name < b.name end)
  _static_actions_cache = res
  for _, def in ipairs(res) do
    local states = {}
    for _, state_name in ipairs(Actions.get_known_states()) do
      if Actions.get_state_action_set(state_name)[def.name] then states[state_name] = true end
    end
    ActionRegistry.register(def, states)
  end
  return res
end

local function copy_schema(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy_schema(item) end
  return out
end

local function narrow_prompt_schema(schema)
  local out = copy_schema(schema)
  local indices = out.properties and out.properties.indices
  if indices then
    local lo, hi = 1, Limits.play_select_max()
    local ok, Legality = pcall(require, "facts.boss.legality")
    if ok and Legality and Legality.play_size_bounds then
      local bounded_lo, bounded_hi = Legality.play_size_bounds()
      lo, hi = tonumber(bounded_lo) or lo, tonumber(bounded_hi) or hi
    end
    indices.minItems = math.max(1, lo)
    indices.maxItems = math.max(indices.minItems, hi)
  end
  return out
end

local function narrow_joker_intents(schema)
  local out = copy_schema(schema)
  local intents = out.properties and out.properties.intents
  if intents then
    local owned = (G and G.jokers and G.jokers.cards) and #G.jokers.cards or 0
    intents.maxItems = math.max(tonumber(intents.minItems) or 1, owned)
  end
  return out
end

Actions.get_static_actions()

ActionRegistry.bind_prompt_narrower("play_hand", narrow_prompt_schema)
ActionRegistry.bind_prompt_narrower("record_joker_roles", narrow_joker_intents)
ActionRegistry.bind_payload_guard("buy_from_shop", function(data)
  if type(data) ~= "table" or data.use ~= true then return true end
  local area = G and type(data.area) == "string" and G[data.area]
  local index = tonumber(data.index)
  local card = area and area.cards and index and area.cards[index]
  if not card then return true end
  local set = card.ability and card.ability.set
  if set == "Booster" or set == "Voucher" then return true end
  if not (card.ability and card.ability.consumeable) then
    return false, require("core.action_result").error("INVALID_SELECTION",
      "The use option is valid only for a consumable shop card; buy this item without use.")
  end
  return true
end)


return Actions
