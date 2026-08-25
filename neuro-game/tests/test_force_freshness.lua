_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("force-freshness")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local function joker_key(card)
  return card and card.config and card.config.center and card.config.center.key
end
local function joker_name(card)
  return (card and card.ability and card.ability.name) or "?"
end

local function bank_claims(text)
  local out = {}
  for v in text:gmatch("(%-?%$%d+) in the bank") do out[#out + 1] = v end
  for v in text:gmatch("(%-?%$%d+) in bank") do out[#out + 1] = v end
  return out
end

local function contains(hay, needle)
  return needle ~= nil and needle ~= "" and hay:find(needle, 1, true) ~= nil
end

local ALL_IN_RUN = { SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true, ROUND_EVAL = true,
  TAROT_PACK = true, BUFFOON_PACK = true, STANDARD_PACK = true, PLANET_PACK = true,
  SPECTRAL_PACK = true, SMODS_BOOSTER_OPENED = true }

local MUTATIONS = {
  {
    id = "sold the leftmost joker",
    states = ALL_IN_RUN,
    applies = function()
      return G.jokers and G.jokers.cards and #G.jokers.cards > 1
        and G.jokers.cards[1].facing ~= "back"
    end,
    before = function()
      local c = G.jokers.cards[1]
      return { joker_name(c), LB.SIGIL[joker_key(c)] }
    end,
    apply = function()
      local c = table.remove(G.jokers.cards, 1)
      G.NEURO.jokers_sold_run = (G.NEURO.jokers_sold_run or 0) + 1
      G.GAME.dollars = (G.GAME.dollars or 0) + (c.sell_cost or 1)
    end,
  },
  {
    id = "spent the bank down",
    states = ALL_IN_RUN,
    applies = function() return G.GAME and tonumber(G.GAME.dollars) and G.GAME.dollars > 3 end,
    before = function() return {} end,
    apply = function() G.GAME.dollars = 3 end,
    bank = 3,
  },
  {
    id = "played a hand",
    states = { SELECTING_HAND = true, BLIND_SELECT = true },
    applies = function()
      local cr = G.GAME and G.GAME.current_round
      return cr and tonumber(cr.hands_left) and cr.hands_left > 1
        and G.GAME.blind and tonumber(G.GAME.blind.chips)
    end,
    before = function()
      local cr = G.GAME.current_round
      return { tostring(cr.hands_left) .. " hand" }
    end,
    apply = function()
      local cr = G.GAME.current_round
      cr.hands_left = cr.hands_left - 1
      G.GAME.chips = (tonumber(G.GAME.chips) or 0) + 137
      G.GAME.hands_played = (tonumber(G.GAME.hands_played) or 0) + 1
      if G.hand and G.hand.cards then table.remove(G.hand.cards, 1) end
    end,
  },
  {
    id = "the shop stock turned over",
    states = { SHOP = true },
    applies = function() return G.shop_jokers and G.shop_jokers.cards and #G.shop_jokers.cards > 1 end,
    before = function() return { joker_name(G.shop_jokers.cards[1]) } end,
    apply = function()
      local c = table.remove(G.shop_jokers.cards, 1)
      G.GAME.dollars = math.max(0, (G.GAME.dollars or 0) - (c.cost or 0))
    end,
  },
  {
    id = "used a consumable",
    states = { SHOP = true, BLIND_SELECT = true, TAROT_PACK = true, BUFFOON_PACK = true,
      STANDARD_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true,
      SMODS_BOOSTER_OPENED = true },
    applies = function() return G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 end,
    before = function()
      local c = G.consumeables.cards[1]
      return { c.ability and c.ability.name }
    end,
    apply = function() table.remove(G.consumeables.cards, 1) end,
  },
  {
    id = "took a card from the pack",
    states = { TAROT_PACK = true, BUFFOON_PACK = true, STANDARD_PACK = true, PLANET_PACK = true,
      SPECTRAL_PACK = true, SMODS_BOOSTER_OPENED = true },
    applies = function()
      local bp = require("facts.card_util").pack_area()
      return bp and bp.cards and #bp.cards > 1
    end,
    before = function()
      local bp = require("facts.card_util").pack_area()
      return { '"area":"booster_pack","index":' .. tostring(#bp.cards) }
    end,
    apply = function()
      local bp = require("facts.card_util").pack_area()
      table.remove(bp.cards, 1)
    end,
  },
}

local stale, vacuous, unchanged = {}, {}, {}
local exercised, per_mutation, per_state = 0, {}, {}

for _, board in ipairs(LB.BOARDS) do
  for _, mut in ipairs(MUTATIONS) do
    LB.load(board.state, board.desc)
    local tag = board.state .. "/" .. mut.id
    if mut.states[board.state] and mut.applies() then
      local first = FP.build(board.state)
      if first then
        local want_gone = mut.before() or {}
        local missing_up_front = {}
        for _, tok in ipairs(want_gone) do
          if not contains(first.message, tok) then missing_up_front[#missing_up_front + 1] = tostring(tok) end
        end
        local pre_bank = bank_claims(first.message)
        if mut.bank and #pre_bank == 0 then
          missing_up_front[#missing_up_front + 1] = "no bank figure at all"
        end
        if #missing_up_front > 0 then
          vacuous[#vacuous + 1] = tag .. " [" .. table.concat(missing_up_front, ", ") .. "]"
        else
          exercised = exercised + 1
          per_mutation[mut.id] = (per_mutation[mut.id] or 0) + 1
          per_state[mut.id] = per_state[mut.id] or {}
          per_state[mut.id][board.state] = true
          mut.apply()
          local second = FP.build(board.state)
          if not second then
            stale[#stale + 1] = tag .. ": no force after the mutation"
          else
            if second.message == first.message then
              unchanged[#unchanged + 1] = tag
            end
            for _, tok in ipairs(want_gone) do
              if contains(second.message, tok) then
                stale[#stale + 1] = tag .. ": still states " .. string.format("%q", tostring(tok))
              end
            end
            if mut.bank then
              local post = bank_claims(second.message)
              if #post == 0 then
                stale[#stale + 1] = tag .. ": the bank figure vanished instead of updating"
              end
              for _, v in ipairs(post) do
                if v ~= ("$" .. tostring(mut.bank)) then
                  stale[#stale + 1] = string.format("%s: payload says %s in bank, live figure is $%d",
                    tag, v, mut.bank)
                end
              end
            end
          end
        end
      end
    end
  end
end

check("the sweep really ran (a green run here must be a run that mutated something)",
  exercised >= 30, "board/mutation pairs exercised: " .. exercised)
do
  local never = {}
  for _, mut in ipairs(MUTATIONS) do
    if (per_mutation[mut.id] or 0) == 0 then never[#never + 1] = mut.id end
  end
  check("every scripted mutation was exercised on at least one board",
    #never == 0, table.concat(never, "; "))
  local unreached = {}
  for _, mut in ipairs(MUTATIONS) do
    for state in pairs(mut.states) do
      if not (per_state[mut.id] and per_state[mut.id][state]) then
        unreached[#unreached + 1] = state .. "/" .. mut.id
      end
    end
  end
  check("F2b every state the fact is rendered in was actually driven through the mutation",
    #unreached == 0, table.concat(unreached, "; "))
end
check("no fact was asserted absent that the payload never carried",
  #vacuous == 0, table.concat(vacuous, " | "))
check("a mutation that changes a rendered fact changes the payload",
  #unchanged == 0, table.concat(unchanged, " | "))
check("no payload restates a fact the mutation retired (stale roster / stale cash)",
  #stale == 0, table.concat(stale, " | "))

do
  local diffs = {}
  for _, board in ipairs(LB.BOARDS) do
    LB.load(board.state, board.desc)
    local a = FP.build(board.state)
    local b = FP.build(board.state)
    if a and b and a.message ~= b.message then
      if a.state ~= b.state then diffs[#diffs + 1] = board.state .. "/" .. board.desc end
    end
  end
  check("an untouched board renders the same state twice, so F4 measures freshness not noise",
    #diffs == 0, table.concat(diffs, " | "))
end

do
  local MODDED = "MYMOD_PACK"
  local CR = require("context.context_readable")
  local Dispatcher = require("core.dispatcher")
  LB.load("TAROT_PACK", "Has pack cards")
  local reachable = CR.SUPPORTED[MODDED] == nil
    and require("core.state_kinds").is_pack_state(MODDED)
    and Dispatcher.get_force_for_state(MODDED) ~= nil
  check("the cached fallback branch of build_force_payload is reachable and was driven",
    reachable, "SUPPORTED=" .. tostring(CR.SUPPORTED[MODDED]))
  if reachable then
    local sold = joker_name(G.jokers.cards[1])
    local sigil = LB.SIGIL[joker_key(G.jokers.cards[1])]
    local first = FP.build(MODDED)
    local had = first and contains(first.message, sold)
    table.remove(G.jokers.cards, 1)
    local second = FP.build(MODDED)
    check("and it is not served from a cache that outlived the board",
      had and second and not contains(second.message, sold)
        and not contains(second.message, sigil)
        and second.message ~= first.message,
      had and "still states " .. sold or "the joker was never in the first payload")
  end
end

check("every payload compared here was taken off G.NEURO.force_actions",
  FP.captures() >= exercised * 2, "payloads captured: " .. FP.captures() .. ", pairs: " .. exercised)

done()
