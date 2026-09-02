local Receipt = require("core.action_receipt")
local Utils = require("util.utils")
local CardUtil = require("facts.card_util")

local M = {}

local function state_name()
  local ok, State = pcall(require, "core.state")
  if ok and State and State.get_state_name then
    local ok_name, name = pcall(State.get_state_name)
    if ok_name then return name end
  end
  return G and G.NEURO and G.NEURO.state
end

local function cards_signature(area)
  local out = {}
  for _, card in ipairs((area and area.cards) or {}) do out[#out + 1] = tostring(card) end
  return table.concat(out, "|")
end

local function selected_blind_key(data)
  local kind = data.blind == "small" and "Small" or data.blind == "big" and "Big" or "Boss"
  return kind, G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
    and G.GAME.round_resets.blind_choices[kind]
end

local function requested_seed(data)
  local raw = data.seed
  if raw == nil or tostring(raw) == "" then
    if G and G.CLIPBOARD and tostring(G.CLIPBOARD) ~= "" then
      raw = G.CLIPBOARD
    elseif love and love.system and love.system.getClipboardText then
      local ok, value = pcall(love.system.getClipboardText)
      if ok then raw = value end
    end
  end
  if raw == nil then return nil end
  return require("core.filtered").sanitize(tostring(raw), true):upper():gsub("[^A-Z0-9]", ""):sub(1, 8)
end

local function snapshot(name, data)
  local n = G and G.NEURO or {}
  local game = G and G.GAME or {}
  local round = game.current_round or {}
  local rr = game.round_resets or {}
  local snap = {
    state = state_name(),
    generation = tonumber(n.run_generation) or 0,
    overlay = G and G.OVERLAY_MENU,
    shop = G and G.shop,
    round_eval = G and G.round_eval,
    pack = CardUtil.pack_area(),
    pack_choices = tonumber(game.pack_choices) or 0,
    blind_on_deck = game.blind_on_deck,
    skips = tonumber(game.skips) or 0,
    boss_choice = rr.blind_choices and rr.blind_choices.Boss,
    boss_rerolled = rr.boss_rerolled,
    rerolls = game.round_scores and game.round_scores.times_rerolled
      and tonumber(game.round_scores.times_rerolled.amt) or 0,
    free_rerolls = tonumber(round.free_rerolls) or 0,
    shop_cards = cards_signature(G and G.shop_jokers),
    plan_revision = tonumber(n.plan_revision) or 0,
    seeded = G and G.run_setup_seed,
    target = data,
  }
  if name == "set_joker_order" then snap.card = G and G.jokers and G.jokers.cards[data.from_index] end
  if name == "select_blind" then snap.blind_kind, snap.blind_key = selected_blind_key(data) end
  if name == "paste_seed" then snap.requested_seed = requested_seed(data) end
  return snap
end

local function exact_goal(name, data, before)
  local n = G and G.NEURO or {}
  local game = G and G.GAME or {}
  local rr = game.round_resets or {}
  if name == "choose_persona" then return n.persona == data.persona end
  if name == "select_stake" then
    local profile = G and G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    return G and G.viewed_stake == data.to_key
      or profile and profile.MEMORY and profile.MEMORY.stake == data.to_key
  end
  if name == "select_deck" then return n.selected_back_key == data.back and n.deck_chosen == true end
  if name == "select_challenge" then
    local tab = G and G.challenge_tab
    return tab ~= nil and (tostring(tab.id) == tostring(data.id) or tostring(tab.name) == tostring(data.id)
      or type(data.id) == "number" and G.CHALLENGES and tab == G.CHALLENGES[data.id])
  end
  if name == "paste_seed" then
    return before.requested_seed ~= nil and before.requested_seed ~= ""
      and n.seed_pasted == before.requested_seed and G and G.setup_seed == before.requested_seed
  end
  if name == "toggle_seeded_run" then
    return G and ((not not G.run_setup_seed) ~= (not not before.seeded))
  end
  if name == "record_plan" then return (tonumber(n.plan_revision) or 0) > before.plan_revision end
  if name == "record_joker_roles" then
    for _, entry in ipairs(data.intents or {}) do
      local card = G and G.jokers and G.jokers.cards[entry.index]
      local intent = card and n.joker_intents and n.joker_intents[card.sort_id]
      if not intent or intent.tag ~= entry.tag then return false end
      if type(entry.note) == "string" then
        local expected = Utils.normalize_ws(entry.note)
        if expected == "" then expected = nil end
        if intent.note ~= expected then return false end
      end
    end
    return #(data.intents or {}) > 0
  end
  if name == "set_joker_order" then return G and G.jokers and G.jokers.cards[data.to_index] == before.card end
  if name == "exit_overlay_menu" then return G and G.OVERLAY_MENU == nil end
  if name == "open_run_setup" then
    return G and G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= before.overlay
  end
  if name == "select_blind" then
    local states = rr.blind_states or {}
    local live_key = game.blind and game.blind.config and game.blind.config.blind
      and game.blind.config.blind.key
    return rr.blind == before.blind_key or live_key == before.blind_key
      or states[before.blind_kind] == "Current"
        and rr.blind_choices and rr.blind_choices[before.blind_kind] == before.blind_key
  end
  if name == "skip_blind" then
    return game.blind_on_deck ~= before.blind_on_deck or (tonumber(game.skips) or 0) > before.skips
  end
  if name == "reroll_boss" then
    return rr.boss_rerolled == true and rr.blind_choices and rr.blind_choices.Boss ~= before.boss_choice
  end
  if name == "reroll_shop" then
    local count = game.round_scores and game.round_scores.times_rerolled
      and tonumber(game.round_scores.times_rerolled.amt) or 0
    return count > before.rerolls
  end
  if name == "leave_shop" then
    local locked = G and G.CONTROLLER and G.CONTROLLER.locks and G.CONTROLLER.locks.leave_shop
    return G and G.shop == nil and state_name() ~= "SHOP" and not locked
  end
  if name == "cash_out" then return G and G.round_eval == nil and state_name() == "SHOP" end
  if name == "skip_pack" then
    return CardUtil.pack_area() == nil or CardUtil.pack_area() ~= before.pack
      or (tonumber(game.pack_choices) or 0) < before.pack_choices
  end
  if name == "start_run" or name == "start_challenge_run" then
    return (tonumber(n.run_generation) or 0) ~= before.generation
      or (state_name() ~= before.state and not require("core.state_kinds").is_menu_state(state_name()))
  end
  if name == "copy_seed" then
    local seed = game.pseudorandom and game.pseudorandom.seed
    if seed ~= nil and G and G.CLIPBOARD == seed then return true end
    if seed ~= nil and love and love.system and love.system.getClipboardText then
      local ok, value = pcall(love.system.getClipboardText)
      return ok and value == seed
    end
    return false
  end
  return false
end

local ASYNC = {
  cash_out = true,
  exit_overlay_menu = true,
  reroll_boss = true,
  reroll_shop = true,
  select_blind = true,
  open_run_setup = true,
  skip_blind = true,
  skip_pack = true,
  start_challenge_run = true,
  start_run = true,
  leave_shop = true,
}

local NATIVE = {
  buy_from_shop = true,
  discard_hand = true,
  play_hand = true,
  sell_card = true,
  use_consumable = true,
  use_directional_consumable = true,
  choose_pack_card = true,
  choose_directional_pack_card = true,
}

local MUTATING = {
  "buy_from_shop", "cash_out", "select_challenge", "select_deck",
  "select_stake", "choose_persona", "copy_seed",
  "discard_hand", "exit_overlay_menu", "paste_seed", "play_hand", "reroll_boss", "reroll_shop",
  "select_blind", "sell_card", "record_joker_roles", "set_joker_order", "record_plan", "open_run_setup",
  "skip_blind", "skip_pack", "start_challenge_run",
  "start_run", "toggle_seeded_run", "leave_shop", "use_consumable",
  "use_directional_consumable", "choose_pack_card", "choose_directional_pack_card",
}

local KNOWN = {}
for _, name in ipairs(MUTATING) do KNOWN[name] = NATIVE[name] and "native" or ASYNC[name] and "async" or "sync" end

function M.wrap(name, data, exec)
  if type(exec) ~= "function" or not KNOWN[name] then return exec end
  local before = snapshot(name, data)
  return function()
    local result = exec()
    if Receipt.is_receipt(result) or Receipt.is_outcome(result) then return result end
    local message = type(result) == "string" and result or nil
    if exact_goal(name, data, before) then
      return Receipt.outcome("applied", message, { contract = KNOWN[name] })
    end
    if KNOWN[name] == "sync" then
      return Receipt.outcome("failed",
        "The accepted action did not reach its requested state. Inspect the current screen and choose again.",
        { contract = "sync", goal = name })
    end
    return Receipt.create({
      id = tostring(data._action_id or (name .. ":" .. Utils.now())),
      name = name,
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = Receipt.now() + ((name == "start_run" or name == "start_challenge_run") and 15 or 6),
      timeout_outcome = "ambiguous",
      allow_generation_change = name == "start_run" or name == "start_challenge_run",
      correction = "The accepted action '" .. name
        .. "' did not reach its requested state before the verification deadline. Inspect the current state and choose again.",
      applied_message = message,
      debug = { contract = "async", goal = name },
      probe = function()
        if exact_goal(name, data, before) then return "applied", { goal = name } end
        return "pending"
      end,
    })
  end
end

function M.classification(name)
  return KNOWN[name]
end

function M.validate(actions)
  local missing, extra = {}, {}
  for _, name in ipairs(actions or {}) do if not M.classification(name) then missing[#missing + 1] = name end end
  local expected = {}
  for _, name in ipairs(actions or {}) do expected[name] = true end
  for name in pairs(KNOWN) do if not expected[name] then extra[#extra + 1] = name end end
  table.sort(missing)
  table.sort(extra)
  return #missing == 0 and #extra == 0, missing, extra
end

return M
