local UseGate = require("facts.use_gate")

local mock_UIBox = {
  get_UIE_by_ID = function() return nil end,
  set_role = function() end,
  recalculate = function() end,
  add_child = function() end
}

local function clear_ai_flags(list)
  if not (G and G.NEURO and G.NEURO.ai_highlighted and type(list) == "table") then return end
  for _, card in ipairs(list) do
    if card then G.NEURO.ai_highlighted[card] = nil end
  end
end

local function set_highlight(card, on)
  if not card then return end
  on = on and true or false
  if not pcall(card.highlight, card, on) then card.highlighted = on end
  if G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = on or nil
  end
end

local function try_highlight(card, on) pcall(set_highlight, card, on) end

local function clear_area_highlight(area)
  if not area then return end
  clear_ai_flags(area.highlighted)
  pcall(area.unhighlight_all, area)
end

local function contains(list, card)
  for _, item in ipairs(type(list) == "table" and list or {}) do
    if item == card then return true end
  end
  return false
end

local function add_area_highlight(area, card)
  if not area or not card then return false end
  if contains(area.highlighted, card) then
    if G and G.NEURO and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
    return true, true
  end
  local ok = pcall(function() area:add_to_highlighted(card) end)
  if not ok then return false end
  local live = card.highlighted and true or false
  if G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = live or nil
  end
  return true, live
end

local function highlight_exactly(area, cards)
  if not area then return false, {}, {} end
  clear_area_highlight(area)
  for _, card in ipairs(cards or {}) do add_area_highlight(area, card) end
  local wanted, refused, extra = {}, {}, {}
  for _, card in ipairs(cards or {}) do
    wanted[card] = true
    if not contains(area.highlighted, card) then refused[#refused + 1] = card end
  end
  local highlighted = type(area.highlighted) == "table" and area.highlighted or {}
  for _, card in ipairs(highlighted) do
    if not wanted[card] then extra[#extra + 1] = card end
  end
  local exact = #refused == 0 and #extra == 0 and #highlighted == #(cards or {})
  return exact, refused, extra
end

local function with_hand_selection(selection, fn)
  local hand = selection and G and G.hand or nil
  if not hand then return pcall(fn) end
  local saved = hand.highlighted
  local copy = {}
  for i, card in ipairs(selection) do copy[i] = card end
  hand.highlighted = copy
  local ok, value = pcall(fn)
  hand.highlighted = saved
  return ok, value
end

local function consumable_usable(card, targets, live)
  return UseGate.usable(card, { targets = targets, live = live })
end

local function consumable_refusal(card, targets, live)
  if consumable_usable(card, targets, live) then return nil end
  return UseGate.reason(card, { targets = targets, live = live }).text
end

local function call_gfunc(name, config, uibox)
  local fn = G and G.FUNCS and G.FUNCS[name]
  if not fn then return false end
  return fn({ config = config or {}, UIBox = uibox or mock_UIBox }) ~= false
end

local function observe_use(card)
  local watch = { used = false }
  local original_raw = rawget(card, "use_consumeable")
  local original = card.use_consumeable
  local wrapper
  function watch.restore()
    if wrapper and rawget(card, "use_consumeable") == wrapper then
      card.use_consumeable = original_raw
    end
  end
  if type(original) == "function" then
    wrapper = function(self, ...)
      if self == card then watch.used = true end
      watch.restore()
      return original(self, ...)
    end
    card.use_consumeable = wrapper
  end
  return watch
end

return {
  observe_use = observe_use,
  mock_UIBox = mock_UIBox,
  clear_area_highlight = clear_area_highlight,
  set_highlight = set_highlight,
  try_highlight = try_highlight,
  add_area_highlight = add_area_highlight,
  highlight_exactly = highlight_exactly,
  consumable_usable = consumable_usable,
  consumable_refusal = consumable_refusal,
  with_hand_selection = with_hand_selection,
  call_gfunc = call_gfunc,
}
