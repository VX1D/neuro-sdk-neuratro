_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("joker-text-once")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Semantics = require("facts.card_semantics")

check("T0a the payload assembler still mirrors core/orchestrator.lua", FP.drift() == nil, FP.drift())

local function numbers_in(text)
  local out, seen = {}, {}
  local function add(tok)
    tok = tok:lower()
    if not seen[tok] then seen[tok] = true; out[#out + 1] = tok end
  end
  for tok in tostring(text):gmatch("[Xx]%d+%.?%d*") do add(tok) end
  for tok in tostring(text):gmatch("%+%d+%.?%d*") do add(tok) end
  for tok in tostring(text):gmatch("%$%d+") do add(tok) end
  return out
end

local WINDOW = 160

local function rule_statements(message, name, nums)
  local hits, from, last = {}, 1, nil
  while true do
    local at = message:find(name, from, true)
    if not at then break end
    from = at + 1
    local win = message:sub(math.max(1, at - WINDOW), at + #name + WINDOW)
    local tok
    for _, candidate in ipairs(nums) do
      if win:find(candidate, 1, true) then tok = candidate break end
    end
    if tok and (last == nil or (at - last) > WINDOW) then
      last = at
      hits[#hits + 1] = tok .. " @" .. at .. ": "
        .. message:sub(math.max(1, at - 24), at + 60):gsub("\n", " ")
    end
  end
  return hits
end

local restated, checked, boards = {}, 0, 0

for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local payload, force = FP.build(board.state)
  if payload and force and #(force.actions or {}) > 0 then
    boards = boards + 1
    local message = payload.message:lower()
    for _, card in ipairs(G.jokers.cards) do
      local name = tostring(card.ability.name):lower()
      local nums = numbers_in(Semantics.description(card))
      if #nums > 0 then
        checked = checked + 1
        local hits = rule_statements(message, name, nums)
        if #hits > 1 then
          restated[#restated + 1] = string.format("%s/%s x%d: %s",
            board.state, card.ability.name, #hits, table.concat(hits, " ## "))
        end
      end
    end
  end
end

check("the sweep compared real joker rules on real force payloads",
  boards >= 8 and checked >= 40,
  string.format("boards=%d joker/board pairs=%d", boards, checked))
check("no assembled force states one joker's rule twice, however the second copy is worded",
  #restated == 0, table.concat(restated, " | "))

do
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  local payload = FP.build("SELECTING_HAND")
  local msg = payload.message
  check("the roster is the one place the rule text is rendered",
    msg:find("Your jokers (", 1, true) ~= nil
      and msg:find("Joker details:", 1, true) == nil, msg:sub(1, 200))
  local carried, absent = 0, {}
  for _, card in ipairs(G.jokers.cards) do
    local desc = Semantics.description(card)
    if #desc > 24 then
      if msg:find(desc, 1, true) then carried = carried + 1 else absent[#absent + 1] = card.ability.name end
    end
  end
  check("and the roster still carries every joker's live text, it was not merely deleted",
    #absent == 0 and carried >= 5, "missing: " .. table.concat(absent, ", "))
end

do
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  local want = {}
  for i, card in ipairs(G.jokers.cards) do
    G.NEURO.joker_observations = G.NEURO.joker_observations or {}
    G.NEURO.joker_hits = G.NEURO.joker_hits or {}
    G.NEURO.joker_observations[card.sort_id] = { score_mult = true }
    G.NEURO.joker_hits[card.sort_id] = { hands = 8 + i, fired = i }
  end
  for i, card in ipairs(G.jokers.cards) do
    local hits, hands = require("core.joker_hits").condition_counts(card)
    want[#want + 1] = { i = i, text = hits and ("Mult, held " .. hits .. "/" .. hands) or "Mult" }
  end
  local payload = FP.build("SELECTING_HAND")
  local msg = payload.message
  check("the observation wording is written once for the whole roster",
    select(2, msg:gsub("Observed this run", "")) == 1
      and select(2, msg:gsub("of your last", "")) == 1
      and msg:find("Observed from your Jokers this run", 1, true) == nil,
    msg:match("Observed[^\n]*") or "no observation line")
  local lost = {}
  for _, w in ipairs(want) do
    if not msg:find(w.i .. ". " .. w.text, 1, true) then lost[#lost + 1] = w.i .. ". " .. w.text end
  end
  check("and every per-joker number it used to carry is still there",
    #lost == 0 and #want >= 5, "missing: " .. table.concat(lost, " | "))
end

do
  local Vanilla = require("tests.fixtures.vanilla_jokers")
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  local mystic = Vanilla.card_played("j_mystic_summit", 901)
  mystic.config.center.loc_txt = { name = "Mystic Summit",
    description = { "+15 Mult when 0 discards remaining" } }
  mystic.debuff = false
  G.jokers.cards = { mystic, LB.joker("j_scary_face", 902) }
  G.GAME.current_round.discards_left = 0
  local section = require("context.ctx_jokers").jokers_section("SELECTING_HAND")
  check("a ceiling source whose why is its own row's condition keeps only the attribution",
    section:find("(Mystic Summit +15 Mult;", 1, true) ~= nil, section)
  check("a ceiling source whose why derived the figure keeps it",
    section:find("Scary Face +150 Chips -- 16 such cards in your deck", 1, true) ~= nil, section)
  check("and the cap it was derived against is not restated beside it",
    section:find("holds at most", 1, true) == nil, section)
end

done()
