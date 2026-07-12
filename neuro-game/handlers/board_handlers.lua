local Actions = require("core.actions")
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local safe_name_or = Utils.safe_name_or
local mock_UIBox = CardArea.mock_UIBox

local function handle_select_blind(data)
  local blind = data.blind
  if not G or not G.P_BLINDS then
    return nil, "Game is not ready yet."
  end
  local sel_key = Actions.get_selectable_blind_key()
  local function is_selectable(key)
    return sel_key == key
  end
  local current = sel_key and sel_key:lower() or nil

  if current and blind ~= current then
    return nil, string.format("'%s' is not selectable right now. Currently selectable: %s — use select_blind with blind='%s'.", tostring(blind), current, current)
  end

  if blind == "small" then
    if not is_selectable("Small") then
      return nil, "Small blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local small_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
      and G.GAME.round_resets.blind_choices.Small
    local bl_small = (small_key and G.P_BLINDS[small_key]) or G.P_BLINDS.bl_small
    if not bl_small then
      return nil, "Small blind definition not found."
    end
    local blind_name = bl_small.name or "Small Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_small }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "big" then
    if not is_selectable("Big") then
      return nil, "Big blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local big_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
      and G.GAME.round_resets.blind_choices.Big
    local bl_big = (big_key and G.P_BLINDS[big_key]) or G.P_BLINDS.bl_big
    if not bl_big then
      return nil, "Big blind definition not found."
    end
    local blind_name = bl_big.name or "Big Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_big }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "boss" then
    if not is_selectable("Boss") then
      return nil, "Boss blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local boss_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices and
      G.GAME.round_resets.blind_choices.Boss
    local boss = boss_key and G.P_BLINDS[boss_key] or nil
    if boss then
      local boss_name = boss.name or "Boss Blind"
      return function()
        local fn = G.FUNCS and G.FUNCS.select_blind
        if fn then fn({ config = { ref_table = boss }, UIBox = mock_UIBox }) end
        return "Selected: " .. boss_name
      end
    end
    return nil, "Boss blind definition not found."
  end
  return nil, "Blind must be one of: small, big, boss. Currently selectable: " .. tostring(current or "none") .. "."
end

local function handle_set_joker_order(data)
  if not G or not G.jokers or not G.jokers.cards then
    return nil, "Jokers are not available yet."
  end
  local from_idx = data.from_index
  local to_idx = data.to_index
  if not from_idx or not to_idx then
    return nil, "Both from_index and to_index are required."
  end
  local njok = #G.jokers.cards
  local ok_from, err_from = CardArea.validate_index(from_idx, njok, "from_index", "jokers")
  if not ok_from then return nil, err_from end
  local ok_to, err_to = CardArea.validate_index(to_idx, njok, "to_index", "jokers")
  if not ok_to then return nil, err_to end
  if from_idx == to_idx then
    return nil, "from_index and to_index are the same."
  end
  return function()
    local card = G.jokers.cards[from_idx]
    local card_name = safe_name_or(card)
    table.remove(G.jokers.cards, from_idx)
    table.insert(G.jokers.cards, to_idx, card)
    if G.jokers.set_ranks then G.jokers:set_ranks() end
    if G.jokers.align_cards then G.jokers:align_cards() end
    return string.format("Moved %s from position %d to %d", card_name, from_idx, to_idx)
  end
end

local function handle_skip_blind(_data)
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return nil, "Blind selection is not ready yet."
  end

  local on_deck = Actions.get_selectable_blind_key()

  if on_deck == "Boss" then
    return nil, "Skipping boss blind is not supported. Select the boss blind instead."
  end
  if on_deck ~= "Small" and on_deck ~= "Big" then
    return nil, "No skippable blind is currently selectable."
  end

  local opt = G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
  if not (opt and type(opt.get_UIE_by_ID) == "function") then
    return nil, "Blind UI option is unavailable; cannot skip right now."
  end

  local tag = opt:get_UIE_by_ID("tag_container")
  if not (tag and tag.config and tag.config.ref_table) then
    return nil, "Skip reward tag is unavailable; cannot skip right now."
  end

  return function()
    local before = G.GAME and G.GAME.blind_on_deck or on_deck
    local fn = G.FUNCS and G.FUNCS.skip_blind
    if fn then fn({ UIBox = opt, config = {} }) end
    local after = G.GAME and G.GAME.blind_on_deck or before
    return string.format("Skipped %s blind. Next selectable: %s", tostring(before), tostring(after))
  end
end

return {
  handle_select_blind = handle_select_blind,
  handle_set_joker_order = handle_set_joker_order,
  handle_skip_blind = handle_skip_blind,
}
