require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local EC = require("tests.engine_cards")
local V = require("tests.fixtures.vanilla_jokers")
local HandInfo = require("tests.engine_hand_info")
local A = require("core.actions")
local D = require("core.dispatcher")
local check, done = H.harness("hidden joker rule effects")

local RULE_JOKERS = { j_four_fingers = true, j_shortcut = true, j_smeared = true, j_pareidolia = true }
local PARTNERS = { "j_greedy_joker", "j_scary_face", "j_swashbuckler", "j_runner" }

local DECK = {
  { "Ace", "Spades" }, { "2", "Spades" }, { "3", "Spades" }, { "4", "Diamonds" }, { "5", "Spades", "m_gold" },
  { "6", "Hearts" }, { "7", "Clubs" }, { "10", "Diamonds" }, { "Jack", "Spades" }, { "Queen", "Hearts" },
  { "King", "Clubs" }, { "King", "Hearts" }, { "Queen", "Spades" },
}
local IN_HAND = { QueenSpades = true, ["4Diamonds"] = true, ["2Spades"] = true, ["3Spades"] = true,
                  AceSpades = true, ["6Hearts"] = true, ["7Clubs"] = true }

local function board(jokers)
  local g = H.base_G()
  g.NEURO.dispatcher = D; g.NEURO.actions = A; g.NEURO.persona = "neuro"
  g.deck = { cards = {}, config = { card_limit = #DECK } }
  g.discard = { cards = {} }
  g.play = { cards = {} }
  local hand = {}
  for i, d in ipairs(DECK) do
    local c = EC.playing(d[1], d[2], { sort_id = i, enhancement = d[3] })
    c.cost, c.sell_cost = 1, 1
    g.playing_cards[#g.playing_cards + 1] = c
    if IN_HAND[d[1] .. d[2]] then
      hand[#hand + 1] = c; c.area = g.hand
    else
      g.deck.cards[#g.deck.cards + 1] = c; c.area = g.deck; c.facing = "back"
    end
  end
  g.hand.cards = hand
  g.GAME.current_round.idol_card = { id = 14, suit = "Spades", rank = "Ace" }
  g.GAME.current_round.ancient_card = { suit = "Hearts" }
  local js = {}
  for i, spec in ipairs(jokers) do
    local j = V.card_played(spec.key, 900 + i)
    j.area, j.facing = g.jokers, spec.hidden and "back" or "front"
    if spec.hidden then j.sell_cost = 3 end
    js[i] = j
  end
  g.jokers.cards = js
  g.NEURO.joker_intents = {}
  g.FUNCS.get_poker_hand_info = HandInfo.engine()
  for _, n in ipairs(HandInfo.HANDLIST) do
    g.GAME.hands[n] = { level = 1, chips = 10, mult = 2, played = 0, played_this_round = 0, visible = true, order = 1 }
  end
  H.in_engine_state("SELECTING_HAND")
  require("core.validate").reset_run_state()
  return g
end

local function emitted(jokers)
  local g = board(jokers)
  local parts = {}
  local function add(tag, f)
    local ok, r = pcall(f)
    parts[#parts + 1] = "[" .. tag .. "] " .. (ok and tostring(r) or ("ERR " .. tostring(r)))
  end
  add("jokers", function() return require("context.ctx_jokers").jokers_section("SELECTING_HAND") or "" end)
  add("force", function() local s, q = H.force_frame("SELECTING_HAND"); return s .. "\n--Q--\n" .. q end)
  add("board", function()
    return require("context.context_readable").build("SELECTING_HAND", A.get_valid_actions_for_state("SELECTING_HAND"))
  end)
  add("review", function()
    local sel, idx = {}, {}
    for i, c in ipairs(g.hand.cards) do if #sel < 4 then sel[#sel + 1] = c; idx[#idx + 1] = i end end
    local ask, _, facts = require("handlers.hand_handlers").play_review_reason(sel, idx)
    return require("context.state_doc").lines(facts, ask)
  end)
  return table.concat(parts, "\n")
end

local function line_set(text)
  local set = {}
  for l in text:gmatch("[^\n]+") do set[l] = true end
  return set
end

local function only_in(a, b)
  local out = {}
  for l in pairs(a) do if not b[l] then out[#out + 1] = l end end
  return out
end

local keys = V.keys()
local moved = {}
local leaks = {}
for _, partner in ipairs(PARTNERS) do
  local base = line_set(emitted({ { key = partner }, { key = "j_joker", hidden = true } }))
  for _, k in ipairs(keys) do
    if k ~= "j_joker" then
      local text = emitted({ { key = partner }, { key = k, hidden = true } })
      local hidden = line_set(text)
      local changed = only_in(hidden, base)
      for _, l in ipairs(only_in(base, hidden)) do changed[#changed + 1] = l end
      if RULE_JOKERS[k] then
        if #changed > 0 then moved[k] = true end
        local name = V.card(k, 1).ability.name
        local rule = emitted({ { key = partner }, { key = k } }):match("\n%d+%. " .. name:gsub("%W", "%%%0") .. " %-%- ([^\n]+)")
        if text:find(name, 1, true) or not rule or text:find(rule, 1, true) then
          leaks[k] = leaks[k] or (partner .. ": names " .. name .. " or its rule")
        end
      elseif #changed > 0 then
        leaks[k] = partner .. ": " .. changed[1]:sub(1, 200)
      end
    end
  end
end

local leak_list = {}
for k, l in pairs(leaks) do leak_list[#leak_list + 1] = k .. " (" .. l .. ")" end
table.sort(leak_list)
check("only a face-down hand-rule joker moves the text, and never by name",
  #leak_list == 0, table.concat(leak_list, " | "))

for k in pairs(RULE_JOKERS) do
  check("the sweep sees " .. k .. " move a hand-rule line", moved[k] == true)
end

local slot_leaks = {}
for _, k in ipairs(keys) do
  if k ~= "j_joker" then
    local a = emitted({ { key = k, hidden = true }, { key = "j_joker", hidden = true } })
    local b = emitted({ { key = "j_joker", hidden = true }, { key = k, hidden = true } })
    if a ~= b then slot_leaks[#slot_leaks + 1] = k .. ": " .. tostring(only_in(line_set(a), line_set(b))[1]):sub(1, 200) end
  end
end
check("which slot a face-down joker occupies never shows", #slot_leaks == 0, table.concat(slot_leaks, " | "))

done()
