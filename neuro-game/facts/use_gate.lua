local CardUtil = require("facts.card_util")

local M = {}

local HAND_STATES = { "SELECTING_HAND", "SMODS_BOOSTER_OPENED" }
local NEEDS_TWO_HAND_CARDS = { Familiar = true, Grim = true, Incantation = true, Immolate = true,
  Sigil = true, Ouija = true }
local NEEDS_EDITIONLESS_JOKER = { ["The Wheel of Fortune"] = true, Hex = true, Ectoplasm = true }
local JOKER_OUTPUT = { Judgement = true, ["The Soul"] = true, Wraith = true }
local CONSUMABLE_OUTPUT = { ["The Emperor"] = true, ["The High Priestess"] = true }

local function hand_cards()
  local cards = G and G.hand and G.hand.cards
  return type(cards) == "table" and cards or {}
end

local function in_hand_state()
  local states = G and G.STATES
  if type(states) ~= "table" then return false end
  for _, name in ipairs(HAND_STATES) do
    if states[name] ~= nil and G.STATE == states[name] then return true end
  end
  return false
end

local function engine_busy()
  local states = G and G.STATES or {}
  local state = G and G.STATE
  if state ~= nil and (state == states.HAND_PLAYED or state == states.DRAW_TO_HAND
      or state == states.PLAY_TAROT) then
    return true
  end
  return (G and G.play and type(G.play.cards) == "table" and #G.play.cards > 0)
    or (G and G.CONTROLLER and G.CONTROLLER.locked)
    or ((tonumber(G and G.GAME and G.GAME.STOP_USE) or 0) > 0)
end

local function selects_hidden(selection)
  for _, c in ipairs(selection or {}) do
    if CardUtil.is_hidden(c) then return true end
  end
  return false
end

-- Do not judge a verdict that would reveal a face-down target’s identity.
local function can_use(card, selection, live)
  if not live and selects_hidden(selection) then return true end
  local ok, usable = require("core.game_actions").with_hand_selection(selection, function()
    if live then return card:can_use_consumeable() end
    return card:can_use_consumeable(true, true)
  end)
  return ok and usable and true or false
end

local function check_use_refuses(card)
  local saved = rawget(_G, "alert_no_space")
  rawset(_G, "alert_no_space", function() end)
  local ok, refused = pcall(card.check_use, card)
  rawset(_G, "alert_no_space", saved)
  if not ok then return true end
  return refused and true or false
end

local function pack_select_area(card)
  local pack = rawget(_G, "booster_obj")
  if not (pack and G and G.pack_cards and card.area == G.pack_cards) then return nil end
  if type(card.selectable_from_pack) ~= "function" then return nil end
  local ok, area = pcall(card.selectable_from_pack, card, pack)
  return ok and type(area) == "string" and area or nil
end

local function select_area_has_room(area_name, card)
  local area = G and G[area_name]
  if not (area and area.cards and area.config) then return false end
  local ability = card.ability or {}
  local extra = (tonumber(ability.card_limit) or 0) - (tonumber(ability.extra_slots_used) or 0)
  return #area.cards < (tonumber(area.config.card_limit) or 0) + extra
end

local function sample_selection(card)
  local min_h = CardUtil.consumable_target_range(card)
  min_h = min_h or 1
  -- Prefer face-up targets for a public verdict; face-down cards count only toward the target count.
  local cards, hidden = {}, {}
  for _, c in ipairs(hand_cards()) do
    local into = CardUtil.is_hidden(c) and hidden or cards
    into[#into + 1] = c
  end
  for _, c in ipairs(hidden) do cards[#cards + 1] = c end
  if #cards < min_h then return nil end
  if min_h == 1 then
    for _, c in ipairs(cards) do
      if can_use(card, { c }, false) then return { c } end
    end
    return nil
  end
  local pick = {}
  for i = 1, min_h do pick[i] = cards[i] end
  return can_use(card, pick, false) and pick or nil
end

function M.usable(card, opts)
  opts = opts or {}
  if not (card and CardUtil.is_consumable_card(card)) then return true end
  local area = pack_select_area(card)
  if area then return select_area_has_room(area, card) end
  local selection = opts.targets
  if not selection and not opts.live then
    local _, max_h = CardUtil.consumable_target_range(card)
    if max_h and max_h > 0 then
      selection = sample_selection(card)
      if not selection then return false end
    end
  end
  if not can_use(card, selection, opts.live) then return false end
  return not check_use_refuses(card)
end

local function owned_or_room(card, area)
  if card.area ~= nil and card.area == area then return true end
  return area and area.cards and area.config and #area.cards < (tonumber(area.config.card_limit) or 0)
end

function M.reason(card, opts)
  opts = opts or {}
  if CardUtil.is_hidden(card) then
    return { kind = "other", text = "the game refuses it right now" }
  end
  if opts.live and engine_busy() then
    return { kind = "busy", text = "the game is still resolving the last action" }
  end
  local ability = card.ability or {}
  local name = ability.name
  local area = pack_select_area(card)
  if area then
    return { kind = "slot", text = "your " .. area .. " area is full -- free a slot to take it" }
  end
  if can_use(card, opts.targets, opts.live) and check_use_refuses(card) then
    if name == "Ankh" then
      return { kind = "slot", text = "joker slots are full and Ankh adds a copy -- sell a joker first" }
    end
    return { kind = "other", text = "the game refuses it right now" }
  end
  local min_h, max_h = CardUtil.consumable_target_range(card)
  if max_h and max_h > 0 then
    if opts.targets then
      return { kind = "other", text = "the game refuses that target selection" }
    end
    if #hand_cards() == 0 or not in_hand_state() then
      local shopping = G and G.STATES and G.STATE ~= nil and G.STATE == G.STATES.SHOP
      return { kind = "hand", text = "needs hand cards selected -- "
        .. (shopping and "normal while shopping" or "no hand is dealt on this screen")
        .. ", becomes usable once you're dealt a hand" }
    end
    if name == "Aura" then
      return { kind = "other", text = "needs a hand card without an edition" }
    end
    return { kind = "other", text = string.format("needs %d card(s) in hand", min_h or 1) }
  end
  if NEEDS_TWO_HAND_CARDS[name] then
    return { kind = "hand", text = "only usable while a hand of 2 or more cards is dealt, in a blind or an open pack" }
  end
  if NEEDS_EDITIONLESS_JOKER[name] then
    return { kind = "other", text = "needs a joker without an edition" }
  end
  if name == "Ankh" then
    return { kind = "other", text = "needs a joker to copy and more than 1 joker slot" }
  end
  if name == "The Fool" then
    if not owned_or_room(card, G and G.consumeables) then
      return { kind = "slot", text = "consumable slots are full -- free a slot to use it" }
    end
    local last = G and G.GAME and G.GAME.last_tarot_planet
    if last == "c_fool" then
      return { kind = "other", text = "the last Tarot/Planet used was The Fool, which it cannot copy" }
    end
    return { kind = "other", text = "no Tarot or Planet has been used yet this run, so there is nothing to copy" }
  end
  if CONSUMABLE_OUTPUT[name] then
    return { kind = "slot", text = "consumable slots are full -- free a slot to use it" }
  end
  if JOKER_OUTPUT[name] then
    return { kind = "slot", text = "joker slots are full -- sell a joker first" }
  end
  return { kind = "other", text = "the game refuses it right now" }
end

function M.blocked_note()
  local named, has_slot = {}, false
  for _, card in ipairs((G and G.consumeables and G.consumeables.cards) or {}) do
    if not M.usable(card) then
      local why = M.reason(card)
      if why.kind == "slot" then has_slot = true end
      if why.kind ~= "hand" and not CardUtil.is_hidden(card) then
        named[#named + 1] = require("util.utils").real_name_or(card)
      end
    end
  end
  local note = #named > 0 and ("Owned consumables marked not usable (its row says why): "
    .. table.concat(named, ", ") .. ". ") or ""
  if has_slot then note = note .. "Freeing a joker slot unblocks at least one of them. " end
  return note, has_slot
end

return M
