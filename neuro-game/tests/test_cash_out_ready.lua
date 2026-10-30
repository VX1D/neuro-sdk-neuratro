-- Before the Cash Out event runs, current_round.dollars still holds the prior payout.
local H = require("tests.hand_pipeline_harness")
local Helpers = require("tests.helpers")
local check, done = require("tests.helpers").harness("cash-out-ready")

local function forces_with(name)
  local out = {}
  for _, f in ipairs(H.frames()) do
    if f.command == "actions/force" then
      for _, n in ipairs(f.data.action_names or {}) do
        if n == name then out[#out + 1] = f.data end
      end
    end
  end
  return out
end

local function first_frame(command, name, from)
  for i, f in ipairs(H.frames()) do
    if i > (from or 0) and f.command == command then
      local names = f.data.action_names or {}
      for _, a in ipairs(f.data.actions or {}) do names[#names + 1] = a.name end
      for _, n in ipairs(names) do
        if n == name then return i end
      end
    end
  end
  return nil
end

local function round_eval_board()
  H.board()
  G.STATE = H.STATES.ROUND_EVAL
  G.NEURO.state = "ROUND_EVAL"
  G.round_eval = {}
  G.GAME.dollars = 4
  G.GAME.current_round.dollars = 0
  G.GAME.modifiers = { money_per_hand = 2, money_per_discard = 1, no_interest = true }
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.NEURO.blind_reward_cache = 3
  local paid = {}
  G.FUNCS.cash_out = function(e)
    paid[#paid + 1] = { dollars = G.GAME.current_round.dollars, e = e }
    e.config.button = nil
    G.round_eval = nil
    G.STATE = H.STATES.SHOP
  end
  return paid
end

do
  local paid = round_eval_board()
  H.tick(20)
  check("no cash_out force while the round summary is still counting", #forces_with("cash_out") == 0,
    tostring(#forces_with("cash_out")))

  local exec, why = H.Dispatcher.preflight("cash_out", {})
  check("an early cash_out is refused and pays nothing", exec == nil and #paid == 0, tostring(why))

  local button = Helpers.cash_out_ready(G, 11)
  H.tick(12)
  local offered = forces_with("cash_out")
  check("cash_out is forced once the Cash Out button exists", #offered >= 1, tostring(#offered))
  local state = offered[#offered] and tostring(offered[#offered].state) or ""
  check("the force states the sum the button will pay", state:find("Earnings: $11 (", 1, true) ~= nil, state)

  H.send("cash_out", "{}")
  H.tick(4)
  check("cash_out presses the live button and collects its payout",
    #paid == 1 and paid[1].dollars == 11 and paid[1].e == button,
    tostring(#paid) .. " " .. tostring(paid[1] and paid[1].dollars))
end

do
  round_eval_board()
  Helpers.cash_out_ready(G, 14)
  local line = require("context.ctx_blind").round_eval_section() or ""
  check("a payout above the fixed parts is attributed, and the parts still sum to it",
    line:find("Earnings: $14 (blind $3 + hands $6 + discards $2 + jokers/tags $3)", 1, true) ~= nil,
    line)
  G.I.UIBOX = {}
  line = require("context.ctx_blind").round_eval_section() or ""
  check("without the button no payout figure is stated", line:find("Earnings", 1, true) == nil, line)
end

do
  H.board()
  H.tick(5)
  local mark = #H.frames()
  G.STATE = H.STATES.ROUND_EVAL
  G.round_eval = {}
  H.tick(20)
  check("entering the round summary does not register cash_out while it is still counting (README.md:35)",
    first_frame("actions/register", "cash_out", mark) == nil, tostring(first_frame("actions/register", "cash_out", mark)))
  Helpers.cash_out_ready(G, 11)
  H.tick(12)
  local registered_at, forced_at = first_frame("actions/register", "cash_out", mark),
    first_frame("actions/force", "cash_out", mark)
  check("cash_out is registered once its button exists, right before the force that lists it",
    registered_at ~= nil and forced_at ~= nil and registered_at < forced_at,
    tostring(registered_at) .. "/" .. tostring(forced_at))
end

H.finish(check, done)
