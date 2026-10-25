local H = require("tests.hand_pipeline_harness")
local Helpers = require("tests.helpers")
local check, done = Helpers.harness("saved-round-channels")

local function channels(chips, saved)
  H.board({ blind = { name = "The Head", chips = 22000, dollars = 5, boss = true } })
  G.GAME.chips = chips
  G.GAME.round = 15
  G.GAME.round_resets.ante = 6
  G.GAME.round_resets.blind_ante = 5
  _G.SMODS = { saved = saved }
  G.STATE = H.STATES.ROUND_EVAL
  G.round_eval = {}
  G.GAME.dollars = 1
  Helpers.cash_out_ready(G, 0)
  H.tick(12)
  local context, state = {}, nil
  for _, f in ipairs(H.frames()) do
    if f.command == "context" then context[#context + 1] = tostring(f.data.message) end
    if f.command == "actions/force" then
      for _, n in ipairs(f.data.action_names or {}) do
        if n == "cash_out" then state = tostring(f.data.state) end
      end
    end
  end
  _G.SMODS = nil
  return table.concat(context, "\n"), state or ""
end

do
  local ctx, state = channels(19431, true)
  check("saved round: context says the blind was not beaten", ctx:find("did NOT beat The Head", 1, true) ~= nil, ctx)
  check("saved round: force state does not call the round cleared", state:find("cleared", 1, true) == nil, state)
end

do
  local ctx, state = channels(23000, false)
  check("cleared boss: context says it was beaten", ctx:find("You beat the Boss Blind, The Head", 1, true) ~= nil, ctx)
  check("cleared boss: no save wording", (ctx .. state):find("save effect", 1, true) == nil, ctx .. "\n" .. state)
end

H.finish(check, done)
