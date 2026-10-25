local H = require("tests.helpers")
local EngineCards = require("tests.engine_cards")
local engine_card = EngineCards.card
local VALN = H.VALN

local M = {}

local playing = EngineCards.playing
local function value_of(v) return VALN[v] or tostring(v) end

function M.ranked(v, suit) return playing(value_of(v), suit) end

M.ranked_front = M.ranked

function M.sorted_maker()
  local n = 0
  local function card(v, suit, debuff)
    n = n + 1
    return playing(value_of(v), suit, { debuff = debuff or nil, sort_id = n })
  end
  return card, function() n = 0 end
end

function M.deck_maker()
  local n = 0
  return function(v, suit)
    n = n + 1
    return playing(value_of(v), suit, { sort_id = n })
  end
end

M.held_maker = M.deck_maker

function M.bare(v, s, stone)
  return EngineCards.enhance(engine_card({ base = { value = v, suit = s } }), stone and "m_stone" or "c_base")
end

function M.five_of_spades(sort_id) return playing("5", "Spades", { sort_id = sort_id }) end

function M.pc(id, suit)
  for value, rank in pairs(EngineCards.RANKS) do
    if rank.id == id then return playing(value, suit) end
  end
end

function M.hand8(card, c7, c8)
  return { card("A","Spades"), card("K","Spades"), card("Q","Spades"), card("J","Spades"),
           card("7","Clubs"), card("4","Clubs"), c7, c8 }
end

function M.jk(key, name, extra)
  return engine_card({ sort_id = key, ability = { set = "Joker", name = name, extra = extra }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { "" } } } } })
end

function M.make_joker(key, name, desc)
  return engine_card({
    cost = 4, sell_cost = 2, debuff = false,
    ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = key, name = name, set = "Joker",
      loc_txt = { name = name, description = desc or "+4 Mult" } } },
  })
end

function M.fool()
  return EngineCards.consumable("c_fool", { sort_id = "c_fool", sell_cost = 1, juice_up = function() end })
end

function M.bare_tarot() return EngineCards.consumable("c_fool") end

return M
