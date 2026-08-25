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
  if type(card.highlight) == "function" then
    if not pcall(card.highlight, card, on) then card.highlighted = on end
  else
    card.highlighted = on
  end
  if G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = on or nil
  end
end

local function try_highlight(card, on) pcall(set_highlight, card, on) end

local function clear_area_highlight(area)
  if not area then return end
  clear_ai_flags(area.highlighted)

  if type(area.unhighlight_all) == "function" then
    pcall(function() area:unhighlight_all() end)
    return
  end

  local highlighted = area.highlighted
  if type(highlighted) ~= "table" then
    area.highlighted = {}
    return
  end

  if type(area.remove_from_highlighted) == "function" then
    for i = #highlighted, 1, -1 do
      local card = highlighted[i]
      if card then
        pcall(function() area:remove_from_highlighted(card) end)
      end
    end
  else
    for i = 1, #highlighted do
      local card = highlighted[i]
      if card then
        set_highlight(card, false)
      end
    end
    area.highlighted = {}
  end
end

local function add_area_highlight(area, card)
  if not area or not card then return false end
  if type(area.add_to_highlighted) == "function" then
    local ok = pcall(function() area:add_to_highlighted(card) end)
    if not ok then return false end
    local live = card.highlighted and true or false
    if G and G.NEURO and G.NEURO.ai_highlighted then
      G.NEURO.ai_highlighted[card] = live or nil
    end
    return true, live
  end
  area.highlighted = area.highlighted or {}
  set_highlight(card, true)
  table.insert(area.highlighted, card)
  return true
end

local function call_gfunc(name, config, uibox)
  local fn = G and G.FUNCS and G.FUNCS[name]
  if not fn then return false end
  return fn({ config = config or {}, UIBox = uibox or mock_UIBox }) ~= false
end

return {
  mock_UIBox = mock_UIBox,
  clear_area_highlight = clear_area_highlight,
  set_highlight = set_highlight,
  try_highlight = try_highlight,
  add_area_highlight = add_area_highlight,
  call_gfunc = call_gfunc,
}
