require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("selecting-hand-channels")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local DebuffFacts = require("facts.debuff_facts")

local NORMAL = "Normal: 5 cards, 4 hands, 3 discards"
local function has(text, needle) return (text or ""):find(needle, 1, true) ~= nil end

local function frame(edit)
  LB.load("SELECTING_HAND", NORMAL)
  if edit then edit() end
  local p = FP.build("SELECTING_HAND") or {}
  return p.state or "", p.query or ""
end

local function section(state, heading)
  return state:match("## " .. heading .. "\n(.-)\n## ") or state:match("## " .. heading .. "\n(.*)$") or ""
end

do
  local s, q = frame(function()
    G.GAME.current_round.most_played_poker_hand = "High Card"
    G.GAME.hands.Pair.played = 7
  end)
  check("F4: the state names the hand actually played most, under Hand levels",
    has(section(s, "Hand levels"), "Played most this run: Pair, 7 times, level 3."), section(s, "Hand levels"))
  check("F4: not the stale engine snapshot", not has(s, "Played most this run: High Card"), s)
  check("F4: the query gives the advice and points at that line, with no numbers of its own",
    has(q, "prefer levelling the hand you play most (named under Hand levels)")
      and not has(q, "played 7") and not has(q, "lv 3") and not has(q, "Pair, played"), q)
  check("F4: The Ox still reads the engine's field, which is what the boss uses",
    DebuffFacts.most_played_hand() == "High Card", tostring(DebuffFacts.most_played_hand()))
end

do
  local s, q = frame(function()
    for _, h in pairs(G.GAME.hands) do h.played = 0 end
  end)
  check("F4: before any hand is played there is no most played hand and no advice",
    not has(s, "Played most this run") and not has(q, "prefer levelling the hand you play most"), q)
end

local function all_down(reverse)
  return function()
    for _, c in ipairs(G.hand.cards) do c.facing = "back" end
    if reverse then
      local r = {}
      for i = #G.hand.cards, 1, -1 do r[#r + 1] = G.hand.cards[i] end
      G.hand.cards = r
    end
  end
end
do
  local s, q = frame(all_down(false))
  check("F6: the state says all cards are face-down", has(s, "0 visible"), s)
  check("F6: no Ready fact rides the state", not has(s, "is Ready") and not has(s, "Ready to play now"), s)
  check("F6: the query keeps no Ready or one-card-away rule",
    not has(q, "Ready hand") and not has(q, "one-card-away") and not has(q, "Rules:\n\n"), q)
  check("F6: the neutral choice is the query's, the state carries no instruction",
    has(q, "With every hand card face-down, playing or discarding blind is your call.")
      and not has(s, "Your call"), q)
  local s2, q2 = frame(all_down(true))
  check("F6: which face-down card sits where changes no byte of the frame", s2 == s and q2 == q,
    s2 == s and q2 or s2)
end

do
  local s, q = frame(function() G.hand.cards[8].facing = "back" end)
  check("F18: the query tells her to decide from the visible cards", has(q, "Decide from the visible cards."), q)
  check("F18: the state no longer instructs", not has(s, "Decide from the visible cards"), s)
end

do
  local s, q = frame(function() G.GAME.current_round.hands_left = 1 end)
  local to_go = s:match("Score [^,]+, ([^ ]+) to go")
  check("F18: the state prints the chips still to go", to_go ~= nil, s:sub(1, 400))
  check("F18: the last-hand rule stays, without the figure",
    has(q, "This is your last hand: it must score all the chips still to go, or the blind is not cleared.")
      and not (to_go and has(q, to_go .. " chips")), q)
  check("F17: no 'fewer hands pays more' on the last hand", not has(q, "fewer hands pays more"), q)
end

do
  local function forced(boss)
    return function()
      G.GAME.current_round.hands_left, G.GAME.current_round.discards_left = 1, 0
      G.hand.cards = { G.hand.cards[1], G.hand.cards[6], G.hand.cards[8] }
      if boss then
        G.GAME.blind = { key = "bl_club", name = "The Club", boss = true, disabled = false, in_blind = true,
          config = { blind = { key = "bl_club", boss = { min = 1 } } } }
      end
    end
  end
  local _, q = frame(forced(false))
  check("F17: the forced-play note is offered", has(q, "there is nothing to weigh"), q)
  check("F17: no vague boss clause without a boss", not has(q, "something to say") and not has(q, "boss's rule"), q)
  local _, qb = frame(forced(true))
  check("F17: under a boss it names what the boss can do",
    has(qb, "commits immediately unless this boss's rule would score it 0 or debuff every scoring card")
      and not has(qb, "something to say"), qb)
end

done()
