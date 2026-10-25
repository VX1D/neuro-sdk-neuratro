local DisplayNames = require("facts.display_names")

local function get_back_display_name(b)
  if not b then return "Unknown Deck" end
  if type(b.key) == "string" then return DisplayNames.of("Back", b.key, b) end
  local lt = type(b.loc_txt) == "table" and b.loc_txt.name
  if type(lt) == "string" and lt ~= "" then return lt end
  if type(b.name) == "string" and b.name ~= "" then return b.name end
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
  return back and (back.loc_name or back.name) or nil
end

return {
  get_back_display_name = get_back_display_name,
  deck_center_of = deck_center_of,
  current_deck_center = current_deck_center,
  deck_name_of = deck_name_of,
}
