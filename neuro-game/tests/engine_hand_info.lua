local M = {}

M.HANDLIST = { "Flush Five", "Flush House", "Five of a Kind", "Straight Flush", "Four of a Kind", "Full House",
  "Flush", "Straight", "Three of a Kind", "Two Pair", "Pair", "High Card" }

function M.stub(text, scoring, hands)
  return function(cards)
    local scoring_hand = scoring
    if type(scoring) == "function" then scoring_hand = scoring(cards) end
    if scoring_hand == nil then scoring_hand = cards end
    local poker_hands = {}
    for _, h in ipairs(M.HANDLIST) do poker_hands[h] = {} end
    local extra = hands
    if type(hands) == "function" then extra = hands(cards, scoring_hand) end
    if extra == nil then
      poker_hands[text] = { scoring_hand }
    else
      for k, v in pairs(extra) do poker_hands[k] = v end
    end
    return text, text, poker_hands, scoring_hand, text
  end
end

M.RANK_ORDER = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }
M.RANKS = {}
for i, key in ipairs(M.RANK_ORDER) do
  local id = i + 1
  M.RANKS[key] = { key = key, id = id, nominal = (id == 14 and 11) or math.min(id, 10),
    face_nominal = ({ Jack = 0.1, Queen = 0.2, King = 0.3, Ace = 0.4 })[key], face = id >= 11 and id <= 13,
    straight_edge = key == "Ace", next = { M.RANK_ORDER[i + 1] or "2" } }
end
M.SUIT_NOMINAL = { Diamonds = 0.01, Clubs = 0.02, Hearts = 0.03, Spades = 0.04 }

function M.set_base(card)
  local b = card.base
  local rank = M.RANKS[b.value] or {}
  b.nominal, b.face_nominal, b.id = rank.nominal or 0, rank.face_nominal or 0, rank.id
  b.suit_nominal = M.SUIT_NOMINAL[b.suit] or 0
  b.suit_nominal_original = b.suit_nominal
  b.times_played = b.times_played or 0
  card.unique_val = card.unique_val or (1 - (card.sort_id or 0) / 1603301)
  return card
end

local function source_block(path, header, indent)
  local fh = assert(io.open(path, "r"), "engine_hand_info: cannot read " .. path)
  local lines = {}
  for l in fh:lines() do lines[#lines + 1] = l end
  fh:close()
  local close = (indent or "") .. (header:sub(-1) == "{" and "}" or "end")
  for i = 1, #lines do
    if lines[i] == header or lines[i]:find(header, 1, true) == 1 then
      for j = i + 1, #lines do
        if lines[j] == close then return table.concat(lines, "\n", i, j) end
      end
    end
  end
  error("engine_hand_info: " .. header .. " not found in " .. path)
end

local engine

function M.engine()
  if engine then return engine end
  local dump = os.getenv("BALATRO_DUMP")
  assert(dump and dump ~= "", "engine_hand_info: BALATRO_DUMP is unset; set it to the lovely dump directory")
  local misc, smods = dump .. "/functions/misc_functions.lua", dump .. "/../../smods/src"
  local S = setmetatable({}, { __index = function(_, k) return rawget(_G, "SMODS") and _G.SMODS[k] end })
  local env_G = setmetatable({ FUNCS = {}, handlist = M.HANDLIST }, { __index = function(_, k) return _G.G[k] end })
  local env = setmetatable({ SMODS = S, G = env_G, localize = function(key) return key end }, { __index = _G })
  S.Ranks, S.Rank = M.RANKS, { obj_buffer = M.RANK_ORDER, max_id = { value = 14 } }
  S.PokerHandParts, S.PokerHands = {}, {}
  S.PokerHandPart = setmetatable({ obj_buffer = {} }, { __call = function(self, t)
    S.PokerHandParts[t.key] = t
    self.obj_buffer[#self.obj_buffer + 1] = t.key
  end })
  S.calculate_context = function() return {} end
  local function run(src, name)
    local fn = assert(loadstring(src, "@" .. name))
    setfenv(fn, env)
    return fn()
  end
  for _, h in ipairs({ "function get_flush(", "function get_X_same(", "function get_highest(" }) do
    run(source_block(misc, h), "misc_functions.lua")
  end
  for _, h in ipairs({ "function SMODS.merge_lists(", "function SMODS.find_card(", "function SMODS.get_card_areas(",
    "function SMODS.four_fingers(", "function SMODS.shortcut(", "function SMODS.wrap_around_straight(" }) do
    run(source_block(smods .. "/utils.lua", h), "smods/src/utils.lua")
  end
  local go = smods .. "/game_object.lua"
  local fh = assert(io.open(go, "r"))
  local src = fh:read("*a")
  fh:close()
  local first = assert(src:find("\n    SMODS.PokerHandPart {\n        key = '_highest'", 1, true))
  local stop = assert(src:find("\n    local hands = G:init_game_object().hands", first, true))
  run(src:sub(first, stop), "smods/src/game_object.lua")
  local evals = run(source_block(go, "    local eval_functions = {", "    ") .. "\nreturn eval_functions",
    "smods/src/game_object.lua")
  for _, name in ipairs(M.HANDLIST) do S.PokerHands[name] = { key = name, evaluate = evals[name] } end
  for _, h in ipairs({ "function get_straight(", "function evaluate_poker_hand(", "function G.FUNCS.get_poker_hand_info(" }) do
    run(source_block(smods .. "/overrides.lua", h), "smods/src/overrides.lua")
  end
  engine = env_G.FUNCS.get_poker_hand_info
  return engine
end

return M
