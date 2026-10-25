require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("ready-no-score")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local HF = require("facts.hand_facts")

local SCORE_MARKS = { "%(scores %d", "scores at least %d", "%(=%d", "%(>=%d" }
local function score_mark(text)
  for _, pat in ipairs(SCORE_MARKS) do
    local hit = text:match(pat .. "[^\n]*")
    if hit then return hit end
  end
  return nil
end

local boards, hands, readies, leaks = 0, 0, 0, {}
for _, list in ipairs({ LB.BOARDS, LB.BLOCKED }) do
  for _, b in ipairs(list) do
    LB.load(b.state, b.desc)
    local p = FP.build(b.state)
    if p then
      boards = boards + 1
      local hit = score_mark(p.state .. "\n" .. p.query)
      if hit then leaks[#leaks + 1] = b.state .. " / " .. b.desc .. ": " .. hit end
      if b.state == "SELECTING_HAND" then
        hands = hands + 1
        if p.state:find("Ready to play now:", 1, true) then readies = readies + 1 end
        local chit = score_mark(require("context.context_readable").structure_prose(HF.structure()))
        if chit then leaks[#leaks + 1] = b.desc .. " (hand prose): " .. chit end
      end
    end
  end
end
check("every live board built a force frame", boards >= 14, tostring(boards))
check("the hand boards were reached, with Ready hands on them", hands >= 3 and readies >= 2,
  hands .. " hand boards, " .. readies .. " with a Ready line")
check("no frame carries a computed Ready score", #leaks == 0, table.concat(leaks, "\n"))

done()
