local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("play-review-paths")

local result_for = H.result_for

local function last_force() return H.last_force() or {} end

local PATHS = {
  { "weak Pair with discards left", function() end },
  { "boss zero verdict", function()
    G.hand.cards[1].debuff = true; G.hand.cards[2].debuff = true
  end },
  { "hand focus mismatch", function()
    G.NEURO.plan = { hand_focus = { primary = "Flush" },
      hand_focus_scope = require("core.gate").current_blind_scope() }
  end },
}

local function send_play(setup, payload, board)
  H.board(board); H.tick(8)
  setup()
  local id = H.send("play_hand", payload)
  H.tick(3)
  return result_for(id)
end

for _, path in ipairs(PATHS) do
  local label, setup = path[1], path[2]
  local plain = send_play(setup, { indices = { 1, 2 } })
  local stray = send_play(setup, { indices = { 1, 2 }, confirm = true })
  check(label .. ": with hand confirmation on the play is reviewed despite a stray confirm",
    H.calls.play == 0 and (last_force().action_names or {})[1] == "resolve_play",
    H.calls.play)
  check(label .. ": the stray confirm is ignored, not refused",
    stray and plain and stray.success == plain.success
      and tostring(stray.message):find(plain.message, 1, true) == 1 and stray.message ~= plain.message,
    tostring(stray and stray.message))

  send_play(setup, { indices = { 1, 2 }, confirm = true }, { confirm_hand = false })
  local staged_first = H.Staging.is_busy() and H.calls.play == 0
  H.tick(5)
  check(label .. ": with hand confirmation off the play commits at once, staged",
    staged_first and H.calls.play == 1, tostring(staged_first) .. "/" .. H.calls.play)
end

do
  H.board(); H.tick(8)
  local lifted, glowing = {}, {}
  for i = 1, 2 do
    local c = G.hand.cards[i]
    c.highlight = function(self, on) if on then lifted[self] = true end end
  end
  H.send("play_hand", { indices = { 1, 2 } }); H.tick(3)
  local picked = { G.hand.cards[1], G.hand.cards[2] }
  local answered_at = H.CLOCK
  H.send("resolve_play", { answer = "yes" })
  local played_at
  for _ = 1, 100 do
    H.tick(0.1)
    for _, c in ipairs(picked) do
      local w = G.NEURO.ai_glow and G.NEURO.ai_glow[c]
      if type(w) == "table" and w.t1 and w.t0 and w.t1 > w.t0 then glowing[c] = true end
    end
    if H.calls.play > 0 then played_at = H.CLOCK break end
  end
  check("review yes: the confirmed play is staged with glow on both cards",
    glowing[picked[1]] and glowing[picked[2]])
  check("review yes: both cards are lifted before the play", lifted[picked[1]] and lifted[picked[2]])
  check("review yes: the engine call waits a visible delay",
    played_at ~= nil and played_at - answered_at >= 0.5,
    played_at and string.format("%.2fs", played_at - answered_at) or "never")
end

H.finish(check, done)
