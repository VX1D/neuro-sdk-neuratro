local Actions = require("core.actions")
local ForceHelpers = require("force.force_helpers")
local DebuffFacts = require("facts.debuff_facts")
local failed_action_warning = ForceHelpers.failed_action_warning

local function build()
  local on_deck_key = Actions.get_selectable_blind_key()
  if not on_deck_key then return nil end
  local current_blind = string.lower(on_deck_key)

  local progress_actions, can = ForceHelpers.collect_actions(
    { "select_blind", "skip_blind", "reroll_boss", "sell_card", "use_card" })
  local can_select, can_skip, can_reroll =
    can.select_blind, can.skip_blind, can.reroll_boss

  local ox_hint = ""
  do
    local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
    local boss_key = choices and choices.Boss
    local bdef = boss_key and G.P_BLINDS and G.P_BLINDS[boss_key]
    if bdef and (bdef.name or boss_key) == "The Ox" then
      ox_hint = "Boss The Ox: playing your most-played hand (" .. tostring(DebuffFacts.most_played_hand() or "?") .. ") sets your money to $0. "
    end
  end

  local win_ante = G and G.GAME and G.GAME.win_ante or 8
  local cur_ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 0
  local ante_progress = string.format("Ante %d/%d (beat the final Boss to win). ", cur_ante, win_ante)
  local query = "State: BLIND_SELECT. " .. ante_progress
  query = query .. "Currently selectable: " .. current_blind .. ". "
    .. ox_hint
    .. failed_action_warning()
  local move_bits = {}
  if can_select then move_bits[#move_bits + 1] = 'select_blind|{"blind":"' .. current_blind .. '"}' end
  if can_skip then move_bits[#move_bits + 1] = 'skip_blind|{} (advance past this blind now and immediately gain its skip tag as a one-time reward -- shown in the BO row -- but forfeit the blind\'s cash payout, the chance to play it, AND the shop that would follow beating it (no buying that round))' end
  if can_reroll then move_bits[#move_bits + 1] = 'reroll_boss|{} (costs $10, from your Director\'s Cut / Retcon voucher; swaps this boss for a different one with a different debuff)' end
  if can.use_card then move_bits[#move_bits + 1] = 'use_card|{"area":"consumeables","index":N} before selecting' end
  if can.sell_card then move_bits[#move_bits + 1] = 'sell_card|{"area":"jokers|consumeables","index":N} sells a joker or consumable for money' end
  if #move_bits > 0 then
    query = query .. "Your move: " .. table.concat(move_bits, "; ") .. ". "
  end

  return {
    query = query:gsub("  +", " "),
    actions = progress_actions,
    blind = current_blind
  }
end

return { build = build }
