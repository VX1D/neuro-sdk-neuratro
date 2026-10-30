require("tests.stubs").setup({ love = "zero" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 1, TOTAL = 1 } }

local Engine = require("tests.real_engine")
Engine.load("exact-hand-selection", 17)

local check, done = require("tests.helpers").harness("exact-hand-selection")
local GameActions = require("core.game_actions")
local Receipt = require("core.action_result")
local Config = require("core.config")
local Hand = require("handlers.hand_handlers")
local UseCard = require("handlers.use_card")
local function use_card(data)
  return UseCard.handle_use_card(require("tests.helpers").with_card_names("use_consumable", data))
end

local captured, calls

local function board(opts)
  opts = opts or {}
  captured, calls = nil, 0
  local hand = Engine.area("hand", opts.limit or 5)
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = Engine.STATES.SELECTING_HAND, STATES = Engine.STATES,
    NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }), run_generation = 1 },
    TIMERS = { REAL = 1, TOTAL = 1 }, CONTROLLER = { locks = {} },
    GAME = { current_round = { hands_left = 4, discards_left = 3, discards_used = 0 },
      starting_params = { play_limit = 5, discard_limit = 5 },
      blind = { name = "Cerulean Bell" }, hands = {} },
    hand = hand, play = { cards = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = Engine.area("consumeable", 1, 2),
    FUNCS = {
      get_poker_hand_info = require("tests.engine_hand_info").stub("High Card", nil, {}),
      play_cards_from_highlighted = function()
        calls = calls + 1
        captured = Engine.ids(G.hand.highlighted)
      end,
      discard_cards_from_highlighted = function()
        calls = calls + 1
        captured = Engine.ids(G.hand.highlighted)
      end,
      use_card = function()
        calls = calls + 1
        captured = Engine.ids(G.hand.highlighted)
      end,
    },
  }
  for i = 1, 8 do hand.cards[i] = Engine.playing_card(i, hand) end
  if opts.forced then
    hand.cards[opts.forced].ability.forced_selection = true
    hand:add_to_highlighted(hand.cards[opts.forced])
  end
  return hand
end

Config.set("NEURO_CONFIRM_HAND", "off")

do
  local hand = board({ forced = 3 })
  hand:unhighlight_all()
  check("real CardArea keeps the forced card through unhighlight_all", Engine.ids(hand.highlighted) == "3")
  GameActions.add_area_highlight(hand, hand.cards[3])
  check("adding an already selected card leaves it selected once", Engine.ids(hand.highlighted) == "3",
    Engine.ids(hand.highlighted))
  local exact, refused, kept = GameActions.highlight_exactly(hand, { hand.cards[3], hand.cards[1] })
  check("an exact selection that includes the forced card is reached", exact and #refused == 0 and #kept == 0,
    Engine.ids(hand.highlighted))
  check("the forced card is in the engine set once", Engine.ids(hand.highlighted) == "3,1",
    Engine.ids(hand.highlighted))
  exact, refused, kept = GameActions.highlight_exactly(hand, { hand.cards[1] })
  check("a selection the engine cannot reach is reported, naming the card it kept",
    not exact and #kept == 1 and kept[1] == hand.cards[3], Engine.ids(hand.highlighted))
end

local function commit(action, indices, between)
  local handler = action == "play" and Hand.handle_play_hand or Hand.handle_discard_hand
  local exec, err = handler({ indices = indices, _action_id = action .. table.concat(indices, "") })
  if type(exec) ~= "function" then return nil, err end
  if between then between() end
  return exec()
end

do
  board({ forced = 3 })
  commit("play", { 3, 1, 2, 4, 5 })
  check("Cerulean Bell: five cards including the forced one reach the engine once each",
    captured == "3,1,2,4,5", captured)
  board({ forced = 3 })
  commit("play", { 3, 1 })
  check("Cerulean Bell: a two-card play is not a Pair of the same card", captured == "3,1", captured)
  board({ forced = 3 })
  commit("discard", { 1, 3, 2 })
  check("Cerulean Bell: a discard sends each card once", captured == "1,3,2" or captured == "3,1,2", captured)
end

do
  board()
  local result = commit("play", { 1, 2, 4 }, function() G.hand.config.highlighted_limit = 2 end)
  check("a card the engine refuses fails the play instead of playing a different hand",
    calls == 0 and Receipt.is_outcome(result) and result.status == "failed", tostring(captured))
  check("a failed selection leaves nothing highlighted", #G.hand.highlighted == 0, Engine.ids(G.hand.highlighted))
end

local function magician()
  return Engine.consumable(50, "The Magician", "c_magician", "Tarot",
    { max_highlighted = 2, mod_num = 2, mod_conv = "m_lucky" }, G.consumeables)
end

do
  board({ forced = 3 })
  G.consumeables.cards = { magician() }
  local exec, err = use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1, 2 }, _action_id = "magician-12" })
  check("Magician on two cards that omit the forced card is refused before execution",
    exec == nil and type(err) == "table",
    type(err) == "table" and err.message or tostring(exec))
  check("the refused use never reaches the engine", calls == 0, captured)

  board({ forced = 3 })
  G.consumeables.cards = { magician() }
  exec, err = use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1, 3 }, _action_id = "magician-13" })
  check("Magician on the forced card and one more is accepted", type(exec) == "function",
    type(err) == "table" and err.message or tostring(err))
  if type(exec) == "function" then exec() end
  check("the engine uses Magician with exactly its two targets selected", captured == "1,3" or captured == "3,1",
    captured)
end

do
  board()
  G.consumeables.cards = { magician() }
  G.hand:add_to_highlighted(G.hand.cards[5])
  local before = G.hand.highlighted
  local exec = use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1, 2 }, _action_id = "magician-plain" })
  check("the usability check puts the live selection back untouched",
    G.hand.highlighted == before and Engine.ids(G.hand.highlighted) == "5", Engine.ids(G.hand.highlighted))
  if type(exec) == "function" then exec() end
  check("an earlier stray selection is not carried into the use", captured == "1,2", captured)
end

do
  board()
  G.consumeables.cards = { magician() }
  local exec, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1, 2 }, hand_cards = { "Ace of Spades", "Ace of Spades" }, _action_id = "magician-stale" })
  check("a consumable aimed at cards that moved is refused as stale and never used",
    exec == nil and type(err) == "table" and err.reason_code == "STALE_TARGET" and calls == 0,
    type(err) == "table" and tostring(err.reason_code) .. " " .. tostring(err.message) or tostring(exec))
  exec, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1, 2 }, _action_id = "magician-unnamed" })
  check("hand_cards is an optional echo: targets without names are accepted (handlers must not refuse an absent optional field)",
    type(exec) == "function", type(err) == "table" and tostring(err.message) or tostring(exec))
end

do
  board()
  G.consumeables.cards = { magician() }
  local exec, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "The Magician",
    hand_indices = { 1 }, hand_cards = {}, _action_id = "magician-empty-echo" })
  check("an empty hand_cards names nothing and counts as absent",
    type(exec) == "function", type(err) == "table" and tostring(err.message) or tostring(exec))
  G.consumeables.cards = { Engine.consumable(54, "Death", "c_death", "Tarot",
    { max_highlighted = 2, min_highlighted = 2, mod_num = 2 }, G.consumeables) }
  exec, err = require("handlers.directional_card").handle({ area = "consumables", index = 1, name = "Death",
    left_index = 1, left_card = "", right_index = 2,
    _action_name = "use_directional_consumable", _action_id = "death-empty-echo" })
  check("an empty left_card and an absent right_card count as absent",
    type(exec) == "function", type(err) == "table" and tostring(err.reason_code) .. " " .. tostring(err.message) or tostring(exec))
end

do
  board()
  G.consumeables.cards = { Engine.consumable(52, "Death", "c_death", "Tarot",
    { max_highlighted = 2, min_highlighted = 2, mod_num = 2 }, G.consumeables) }
  local exec, err = require("handlers.directional_card").handle({ area = "consumables", index = 1, name = "Death",
    left_index = 1, left_card = "Ace of Spades", right_index = 2, right_card = "Ace of Spades",
    _action_name = "use_directional_consumable", _action_id = "death-stale" })
  check("a directional card aimed at moved cards is refused as stale",
    exec == nil and type(err) == "table" and err.reason_code == "STALE_TARGET",
    type(err) == "table" and tostring(err.reason_code) .. " " .. tostring(err.message) or tostring(exec))
end

do
  board()
  G.consumeables.cards = { magician() }
  local _, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "The Magician", _action_id = "magician-none" })
  local text = type(err) == "table" and tostring(err.message) or ""
  check("a targeting card sent without targets states its range and a sendable example",
    text:find("needs 1 to 2 card(s)", 1, true) ~= nil and text:find('{"hand_indices":[1]}', 1, true) ~= nil, text)
  G.consumeables.cards = { Engine.consumable(53, "Aura", "c_aura", "Spectral", { max_highlighted = 1 }, G.consumeables) }
  _, err = UseCard.handle_use_card({ area = "consumables", index = 1, name = "Aura", hand_indices = {}, _action_id = "aura-none" })
  text = type(err) == "table" and tostring(err.message) or ""
  check("a one-target card asks for exactly one card", text:find("needs exactly 1 card(s)", 1, true) ~= nil, text)
end

done()
