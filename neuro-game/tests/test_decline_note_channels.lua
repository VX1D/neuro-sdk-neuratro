require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("decline-note-channels")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Gate = require("core.gate")

local function has(text, needle) return (text or ""):find(needle, 1, true) ~= nil end
local COMPARISON = "At that review, Ready hands that would score more were: Pair (cards 5, 6)."

local function frame(record, edit)
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  if edit then edit() end
  local real_final, real_decline = Gate.final_play_required, Gate.decline_context
  Gate.final_play_required = function() return true end
  Gate.decline_context = function() return record end
  local p = FP.build("SELECTING_HAND") or {}
  Gate.final_play_required, Gate.decline_context = real_final, real_decline
  return p.state or "", p.query or ""
end

do
  local s, q = frame({ indices = { 1 }, hand_type = "High Card", dominant_alt = { "Pair (cards 5, 6)" } })
  check("the comparison is in state", has(s, COMPARISON), s)
  check("and not in the query", not has(q, "would score more"), q)
end

do
  local s, q = frame({ indices = { 1, 2 } }, function()
    for _, c in ipairs(G.hand.cards) do c.facing = "back" end
  end)
  check("all face-down: the state lists no Ready hand", not has(s, "Ready to play now"), s)
  check("all face-down: the query names no Ready hand to play", not has(q, "Ready hand"), q)
end

done()
