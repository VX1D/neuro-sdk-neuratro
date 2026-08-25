local M = {}

local PACK_STATES = {
  TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true,
  STANDARD_PACK = true, BUFFOON_PACK = true, SMODS_BOOSTER_OPENED = true,
}
local MENU_STATES = { SPLASH = true, MENU = true, GAME_OVER = true, RUN_SETUP = true }
local SHOP_INTERLUDE_STATES = { PLAY_TAROT = true }

function M.is_pack_state(name)
  if type(name) ~= "string" then return false end
  return PACK_STATES[name] == true or name:find("_PACK$") ~= nil
end

function M.is_shop_interlude(name)
  if M.is_pack_state(name) then return true end
  return type(name) == "string" and SHOP_INTERLUDE_STATES[name] == true
end

function M.is_menu_state(name)
  return type(name) == "string" and MENU_STATES[name] == true
end

function M.is_run_setup_overlay()
  return G and G.OVERLAY_MENU
    and type(G.OVERLAY_MENU.get_UIE_by_ID) == "function"
    and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") ~= nil
end

function M.is_unlock_popup()
  return not not (G and G.OVERLAY_MENU and type(G.OVERLAY_MENU) == "table"
    and G.OVERLAY_MENU.joker_unlock_table ~= nil)
end

function M.is_progression_overlay()
  local om = G and G.OVERLAY_MENU
  if not (om and type(om.get_UIE_by_ID) == "function") then return false end
  return om:get_UIE_by_ID("from_game_over") ~= nil
    or om:get_UIE_by_ID("run_setup_seed") ~= nil
end

M.PACK_STATES = PACK_STATES
return M
