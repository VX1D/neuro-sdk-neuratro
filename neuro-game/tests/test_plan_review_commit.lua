local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("plan-review-commit")

local NOTE = "Lead with the pair so the Hook cannot strip it."
local OTHER = "Redraw toward a flush before committing a hand."
local BOSS = { name = "The Hook", key = "bl_hook", boss = true, in_blind = true, disabled = false, chips = 300 }

local function plan_boss() return G.NEURO.plan and G.NEURO.plan.boss or "<none>" end

local function review(indices)
  local id = H.send("play_hand", { indices = indices, plan = { boss_plan = NOTE } })
  H.tick(3)
  return H.result_for(id)
end

local function answer(value)
  local id = H.send("resolve_play", { answer = value })
  H.tick(5)
  return H.result_for(id)
end

do
  H.board({ blind = BOSS }); H.tick(8)
  local held = review({ 1, 2 })
  check("the reviewed play executed nothing",
    held and held.success == true and H.calls.play == 0 and tostring(held.message):find("Nothing was executed", 1, true),
    held and tostring(held.message))
  check("the reviewed play wrote no plan", plan_boss() ~= NOTE, plan_boss())
  answer("no")
  check("declining keeps the play unexecuted", H.calls.play == 0, H.calls.play)
  check("and drops the plan written with it", G.NEURO.held_plan_write == nil,
    G.NEURO.held_plan_write and tostring(G.NEURO.held_plan_write.values.boss_plan))
  local id = H.send("discard_hand", { indices = { 3 }, plan = { boss_plan = OTHER } })
  H.tick(5)
  local discard = H.result_for(id)
  check("a different action with its own plan goes through", discard and discard.success == true and H.calls.discard == 1,
    discard and tostring(discard.message))
  check("only the executed action's plan is committed", plan_boss() == OTHER, plan_boss())
  H.tick(3)
  local force = H.last_force()
  check("the next decision does not show the declined play's plan",
    force and not tostring(force.state):find(NOTE, 1, true), force and force.state)
end

do
  H.board({ blind = BOSS }); H.tick(8)
  review({ 1, 2 })
  answer("yes")
  check("confirming executes the reviewed play", H.calls.play == 1, H.calls.play)
  check("and commits the plan written with it", plan_boss() == NOTE, plan_boss())
end

H.finish(check, done)
