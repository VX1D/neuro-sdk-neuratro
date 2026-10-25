local M = {}

function M.hand_can_score()
  return require("core.state").get_state_name() == "SELECTING_HAND"
end

function M.hands_left() return (G and G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left) or 0 end
function M.discards_left() return (G and G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left) or 0 end

function M.visible_hand_names()
  local hands = G and G.GAME and G.GAME.hands
  if type(hands) ~= "table" then return nil end
  local out = {}
  for name, hand in pairs(hands) do
    if type(hand) == "table" and hand.visible == true and type(name) == "string" and name ~= "" then
      out[#out + 1] = name
    end
  end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end

function M.round()
  local round = tonumber(G and G.GAME and G.GAME.round)
  if not round then return nil end
  return round + (tonumber(G.GAME.skips) or 0)
end

function M.ante(default) return (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or default end

function M.run_progress()
  local game = (G and G.GAME) or {}
  local rr = game.round_resets
  return {
    won = game.won == true and game.win_notified == true,
    win_ante = tonumber(game.win_ante) or 8,
    ante = rr and tonumber(rr.ante) or nil,
  }
end

function M.ante_progress()
  local run = M.run_progress()
  local ante = tostring(run.ante or "?")
  if run.won then
    return string.format("Ante %s, Endless mode: you already won this run by beating the Ante %d Boss",
      ante, run.win_ante)
  end
  return string.format("Ante %s/%d", ante, run.win_ante)
end

function M.round_outcome()
  local game = G and G.GAME
  local blind = game and game.blind
  if not blind then return nil end
  if (tonumber(game.chips) or 0) - (tonumber(blind.chips) or 0) >= 0 then return { beaten = true } end
  local saved = (_G.SMODS and _G.SMODS.saved) or game.saved_text
  return { beaten = false,
    rescue = saved and "A save effect kept the run alive" or "Something kept the run alive" }
end

function M.reserved_dollars() return tonumber(G and G.NEURO and G.NEURO.reserved_dollars or 0) or 0 end

function M.blind_reward()
  if not (G and G.NEURO) then return 0 end
  local stamped = tonumber(G.NEURO.blind_reward_round)
  local round = tonumber(G.GAME and G.GAME.round)
  if stamped and round and stamped ~= round then return 0 end
  return tonumber(G.NEURO.blind_reward_cache) or 0
end

function M.cash_out_button()
  if not (G and G.round_eval and G.I and type(G.I.UIBOX) == "table") then return nil end
  for _, box in ipairs(G.I.UIBOX) do
    if type(box) == "table" and box.config and box.config.major == G.round_eval
        and type(box.get_UIE_by_ID) == "function" then
      local button = box:get_UIE_by_ID("cash_out_button")
      if button and button.config and button.config.button == "cash_out" and not button.disable_button then
        return button
      end
    end
  end
  return nil
end

function M.cash_out_payout()
  if not M.cash_out_button() then return nil end
  return tonumber(G.GAME and G.GAME.current_round and G.GAME.current_round.dollars)
end

return M
