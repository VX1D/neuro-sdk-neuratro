local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("review-acknowledgement")

H.board({ confirm_hand = true, ncards = 8 })
local function joker(sid, key, name)
  return { sort_id = sid, ability = { set = "Joker", name = name }, sell_cost = 2,
    config = { center = { key = key, name = name, set = "Joker" } } }
end
G.jokers.cards = { joker(801, "j_joker", "Joker"), joker(802, "j_greedy_joker", "Greedy Joker") }
check("fixture forced", H.wait_force(), H.phase())
local early = H.send("resolve_play", { answer = "yes" })
H.tick(1)
local e = H.result_for(early) or {}
local function unregistered(result)
  local text = tostring(result.message)
  return result.success == false
    and (text:find("Unknown action", 1, true) ~= nil or text:find("recently unregistered", 1, true) ~= nil)
end
check("an answer with no review open meets an unregistered action, as an SDK ActionWindow leaves it",
  unregistered(e), tostring(e.success) .. " " .. tostring(e.message))
local play = H.send("play_hand", { indices = { 1, 2 } })
H.tick(1)
check("the play opens a review", (H.result_for(play) or {}).success == true)
H.wait_force(5)
local note = H.send("set_joker_order", { order = { 1 } })
H.tick(1)
local r = H.result_for(note) or {}
local focus = H.send("record_plan", { build_plan = "Spend few hands", hand_focus = { primary = "High Card", fallback = "Pair" } })
H.tick(1)
local f = H.result_for(focus) or {}
check("record_plan is not part of the hand screen, so it is not registered there",
  unregistered(f), tostring(f.success) .. " " .. tostring(f.message))
H.G = G
G.STATE = G.STATES.SHOP
local moved = H.send("resolve_play", { answer = "yes" })
H.tick(0.1)
local m = H.result_for(moved) or {}
check("after the screen changes, the refusal lists this screen's moves, not the old review",
  not tostring(m.message):find("Answer the play review", 1, true), tostring(m.success) .. " " .. tostring(m.message))
G.STATE = G.STATES.SELECTING_HAND
check("a move the open review blocks is not registered in the review's window (action_window.gd add_action)",
  unregistered(r), tostring(r.success) .. " " .. tostring(r.message))
H.board({ confirm_hand = true, ncards = 8 })
H.wait_force()
H.send("play_hand", { indices = { 1, 2 } })
local early_yes = H.send("resolve_play", { answer = "yes" })
H.tick(0.1)
local y = H.result_for(early_yes) or {}
check("an answer sent before the review reaches her meets an unregistered action",
  unregistered(y), tostring(y.success) .. " " .. tostring(y.message))
done()
