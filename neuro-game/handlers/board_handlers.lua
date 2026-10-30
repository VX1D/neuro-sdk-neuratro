local Actions = require("core.actions")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local ActionResult = require("core.action_result")
local mock_UIBox = GameActions.mock_UIBox
local function blind_selection_matches(kind, fallback_key, expected)
  if not (G and G.blind_select and G.P_BLINDS
      and Actions.get_selectable_blind_key() == kind) then
    return false
  end
  local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
  local key = choices and choices[kind]
  local current = key and G.P_BLINDS[key] or nil
  if not current and fallback_key then current = G.P_BLINDS[fallback_key] end
  return current == expected
end
local function deferred_blind_selection(kind, fallback_key, blind)
  return function()
    if not blind_selection_matches(kind, fallback_key, blind) then
      return nil, "Blind selection changed before execution; nothing was selected. Choose again."
    end
    local fn = G.FUNCS and G.FUNCS.select_blind
    if type(fn) ~= "function" then return nil, "Blind selection is unavailable; nothing was selected. Choose again." end
    fn({ config = { ref_table = blind }, UIBox = mock_UIBox })
    return ActionResult.done()
  end
end
local BLIND_SLOTS = { small = { "Small", "bl_small" }, big = { "Big", "bl_big" }, boss = { "Boss" } }

local function handle_select_blind(data)
  local blind = data.blind
  if not G or not G.P_BLINDS then
    return nil, ActionResult.wait("The game has not finished loading, so nothing was selected.",
      "Wait for the blind selection screen, then select the blind again.")
  end
  local sel_key = Actions.get_selectable_blind_key()
  local current = sel_key and sel_key:lower() or nil

  if current and blind ~= current then
    return nil, string.format("'%s' is not selectable right now. Currently selectable: %s — select it with blind='%s'.", tostring(blind), current, current)
  end

  if not G.blind_select then
    return nil, ActionResult.wait("The blind selection screen is not open yet, so nothing was selected.",
      "Wait for the blind selection screen, then select the blind again.")
  end
  if not (G.FUNCS and type(G.FUNCS.select_blind) == "function") then
    return nil, ActionResult.wait("Blind selection cannot run yet, so nothing was selected.",
      "Wait a moment, then select the blind again.")
  end
  local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
  local kind, fallback = BLIND_SLOTS[blind][1], BLIND_SLOTS[blind][2]
  if sel_key ~= kind then
    return nil, ActionResult.wait(kind .. " blind is not selectable yet (selectable: " .. tostring(current or "none")
      .. "), so nothing was selected.", "Wait for the blind selection screen to offer it, then select the blind again.")
  end
  local key = choices and choices[kind]
  local def = (key and G.P_BLINDS[key]) or (fallback and G.P_BLINDS[fallback]) or nil
  if not def then
    return nil, ActionResult.wait(kind .. " blind's details are not loaded yet, so nothing was selected.",
      "Wait a moment, then select the blind again.")
  end
  return deferred_blind_selection(kind, fallback, def)
end

local function handle_set_joker_order(data)
  if not G or not G.jokers or not G.jokers.cards then
    return nil, ActionResult.wait("Your jokers are not loaded yet, so nothing was reordered.",
      "Wait until a run is in progress, then move the joker again.")
  end
  local from_idx = data.from_index
  local to_idx = data.to_index
  local njok = #G.jokers.cards
  for _, arg in ipairs({ { "from_index", from_idx }, { "to_index", to_idx } }) do
    local ok, err = CardArea.validate_index(arg[2], njok, arg[1], "jokers")
    if not ok then return nil, err end
  end
  local card = G.jokers.cards[from_idx]
  if from_idx == to_idx then
    return ActionResult.unchanged(require("facts.public_card_identity").label(card, "jokers", from_idx)
      .. " is already at position " .. from_idx)
  end
  return function()
    local cards = G and G.jokers and G.jokers.cards
    if type(cards) ~= "table" or cards[from_idx] ~= card or to_idx > #cards then
      return nil, "Joker lineup changed before the reorder ran; nothing was moved. Inspect the current order and choose again."
    end
    table.remove(G.jokers.cards, from_idx)
    table.insert(G.jokers.cards, to_idx, card)
    for _, c in ipairs(G.jokers.cards) do if c.states and c.states.drag then c.states.drag.is = false end end
    if G.jokers.set_ranks then G.jokers:set_ranks() end
    if G.jokers.align_cards then G.jokers:align_cards() end
    if G.jokers.hard_set_cards then G.jokers:hard_set_cards() end
    return ActionResult.done()
  end
end

local function handle_skip_blind()
  local blocked = Actions.blind_skip_blocker()
  if blocked then
    return nil, blocked
  end
  local on_deck = Actions.get_selectable_blind_key()

  local opt = G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
  if not (opt and type(opt.get_UIE_by_ID) == "function") then
    return nil, ActionResult.wait("The skip button is not on screen yet, so nothing was skipped.",
      "Wait a moment, then skip the blind again, or select it to play it.")
  end

  return function()
    local live_key = Actions.get_selectable_blind_key()
    local live_opt = live_key and G.blind_select_opts
      and G.blind_select_opts[string.lower(live_key)] or nil
    if live_key ~= on_deck or live_opt ~= opt then
      return nil, "Blind selection changed before the skip ran; nothing was skipped. Choose again."
    end
    local fn = G.FUNCS and G.FUNCS.skip_blind
    if type(fn) ~= "function" then return nil, "Blind skip is unavailable; nothing was skipped. Choose again." end
    fn({ UIBox = opt, config = {} })
    return ActionResult.done()
  end
end

return {
  handle_select_blind = handle_select_blind,
  handle_set_joker_order = handle_set_joker_order,
  handle_skip_blind = handle_skip_blind,
}
