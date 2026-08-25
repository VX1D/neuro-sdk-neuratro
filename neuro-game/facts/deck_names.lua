local function get_back_display_name(b)
  if not b then return "Unknown Deck" end
  if b.key and localize then
    local ok, loc = pcall(localize, {type = 'name_text', set = 'Back', key = b.key})
    if ok and type(loc) == "string" and loc ~= "" and loc ~= "ERROR" then
      return loc
    end
  end
  if b.loc_txt and type(b.loc_txt) == "table" and b.loc_txt.name and b.loc_txt.name ~= "" then
    return tostring(b.loc_txt.name)
  end
  if b.name and b.name ~= "" and b.name ~= b.key then
    return tostring(b.name)
  end
  if b.key then
    local humanized = b.key:gsub("^b_", ""):gsub("_", " ")
    return humanized:sub(1,1):upper() .. humanized:sub(2)
  end
  return "Unknown Deck"
end

local function deck_center_of(back)
  if not back then return nil end
  return (back.effect and back.effect.center)
    or (back.key and G and G.P_CENTERS and G.P_CENTERS[back.key])
    or nil
end

local function current_deck_center()
  return deck_center_of(G and G.GAME and (G.GAME.selected_back or G.GAME.back))
end

local function deck_name_of(back)
  local center = deck_center_of(back)
  if center then return get_back_display_name(center) end
  if back then return back.loc_name or back.name or "Red Deck" end
  return "Red Deck"
end

return {
  get_back_display_name = get_back_display_name,
  deck_center_of = deck_center_of,
  current_deck_center = current_deck_center,
  deck_name_of = deck_name_of,
}
