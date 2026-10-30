local M = {}

local PACK_STATES = { SMODS_BOOSTER_OPENED = true }
local MENU_STATES = { SPLASH = true, MENU = true, GAME_OVER = true, RUN_SETUP = true }

function M.is_pack_state(name)
  return PACK_STATES[name] == true
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
  local om = G and G.OVERLAY_MENU
  if type(om) ~= "table" then return false end
  if om.joker_unlock_table ~= nil then return true end
  if type(om.get_UIE_by_ID) ~= "function" then return false end
  local back = om:get_UIE_by_ID("overlay_menu_back_button")
  return type(back) == "table" and type(back.config) == "table" and back.config.button == "continue_unlock"
end

-- Escape closes any overlay but a no_esc one (engine/controller.lua:801); of those only the win screen has a close button, Endless (UI_definitions.lua:2987).
function M.is_closable_overlay()
  local om = G and G.OVERLAY_MENU
  if type(om) ~= "table" then return false end
  if not (type(om.config) == "table" and om.config.no_esc) then return true end
  return type(om.get_UIE_by_ID) == "function" and om:get_UIE_by_ID("you_win_UI") ~= nil
end

function M.is_progression_overlay()
  local om = G and G.OVERLAY_MENU
  if not (om and type(om.get_UIE_by_ID) == "function") then return false end
  return om:get_UIE_by_ID("from_game_over") ~= nil
    or om:get_UIE_by_ID("run_setup_seed") ~= nil
end

return M
