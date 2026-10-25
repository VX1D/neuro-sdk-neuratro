local M = {}
local Utils = require("util.utils")

function M.effect_text(key)
  local eff = require("facts.debuff_facts").voucher_effect_text(key)
  if eff ~= "" then return eff end
  local center = G and G.P_CENTERS and G.P_CENTERS[key]
  return (center and require("util.utils").safe_description(center.loc_txt)) or ""
end

local function upgrade_of(base_key)
  local found
  for key, up in pairs(G and G.P_CENTERS or {}) do
    if type(up) == "table" and up.set == "Voucher" and type(up.requires) == "table" and up.requires[1] == base_key
      and (not found or key < found) then
      found = key
    end
  end
  return found
end

function M.unlock_sentence(base_key)
  local up_key = upgrade_of(base_key)
  local base, up = G.P_CENTERS[base_key], up_key and G.P_CENTERS[up_key]
  if not (base and up) then return nil end
  if up.unlocked == false then
    return string.format("%s's upgrade %s is still locked on this profile, so owning %s will not bring it to later shops",
      base.name, up.name, base.name)
  end
  local eff = M.effect_text(up_key):gsub("%s+", " "):gsub("^ ", ""):gsub("[ %.]+$", "")
  return string.format("Owning %s unlocks %s in later shops%s", base.name, up.name,
    eff ~= "" and (" (" .. up.name .. ": " .. eff .. ")") or "")
end

local ANTE_BACK = {
  v_hieroglyph = { unit = "hand", field = "hands" },
  v_petroglyph = { unit = "discard", field = "discards" },
}

local plural = require("facts.text").plural

function M.row_note(key)
  local spec = ANTE_BACK[key]
  local game = G and G.GAME
  if not (spec and game) then return nil end
  local center = G.P_CENTERS and G.P_CENTERS[key]
  local extra = tonumber(center and center.config and center.config.extra) or 1
  local ante = tonumber(game.round_resets and game.round_resets.ante)
  local win = tonumber(game.win_ante) or 8
  local parts = {}
  if ante then
    -- Blind selection reads the reset ante; antes below one still use the minimum blind amount.
    local back = ante - extra
    local ok_to, to_amt = pcall(get_blind_amount, back)
    local ok_from, from_amt = pcall(get_blind_amount, ante)
    local amounts = (ok_to and ok_from and tonumber(to_amt) and tonumber(from_amt))
      and string.format(" (base %d instead of %d)", to_amt, from_amt) or ""
    parts[1] = string.format(
      "Buying it moves the ante back from %d to %d: blinds from here on use ante %d's chip targets%s, ante %d has to be reached again, and a win still needs the ante %d boss, so the run gets longer, not shorter",
      ante, back, back, amounts, ante, win)
  else
    parts[1] = string.format("Buying it moves the ante back by %d: that ante is played again and the run gets longer, not shorter", extra)
  end
  local per_round = tonumber(game.round_resets and game.round_resets[spec.field])
  local fewer = string.format("every round after it has %s fewer", plural(extra, spec.unit))
  if per_round then fewer = fewer .. string.format(" (%d instead of %d)", per_round - extra, per_round) end
  local mods = game.modifiers or {}
  local pay
  if spec.unit == "hand" then
    pay = (not mods.no_extra_hand_money) and (tonumber(mods.money_per_hand) or 1) or 0
  else
    pay = tonumber(mods.money_per_discard) or 0
  end
  if pay > 0 then
    fewer = fewer .. string.format(", and each unused %s pays %s at cash-out on this run, so up to %s less per round",
      spec.unit, Utils.money(pay), Utils.money(pay * extra))
  end
  parts[2] = fewer
  return table.concat(parts, "; ")
end

return M
