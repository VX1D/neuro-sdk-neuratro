require("tests.stubs").setup({ love = "zero" })

local check, done = require("tests.helpers").harness("destruction-log")

local Card = {}
Card.__index = Card
function Card.calculate_joker(self, context) return self.impl and self.impl(self, context) end
function Card.use_consumeable(self) return self.impl and self.impl(self) end
_G.Card = Card
local context_log = {}
require("tests.engine_cards").install_smods({
  calculate_context = function(context)
    context_log[#context_log + 1] = context
    return context.flags or {}
  end,
})

local function area(cards) return { cards = cards or {}, config = { card_limit = 5 } } end
_G.G = {
  P_CENTERS = require("tests.engine_centers").centers(),
  GAME = { dollars = 10, used_vouchers = {}, hands = {}, modifiers = {} },
  jokers = area(), consumeables = area(), hand = area(), play = area(), deck = area(),
  playing_cards = {}, P_SEALS = { Purple = { key = "Purple" } },
  NEURO = { run_generation = 4, decision_serial = 1 },
}

local Log = require("core.destruction_log")
local DD = require("facts.decision_delta")
check("the hooks install over the engine's SMODS and Card", Log.install() == true)
check("installing twice does not stack the hooks", Log.install() == false)

local function playing(value, suit, extra)
  local c = setmetatable({ base = { value = value, suit = suit }, facing = "front",
    ability = { set = "Default" }, config = { center = { key = "c_base", set = "Default" } } }, Card)
  for k, v in pairs(extra or {}) do c[k] = v end
  G.playing_cards[#G.playing_cards + 1] = c
  return c
end
local function joker(key, name, impl)
  local j = setmetatable({ facing = "front", ability = { set = "Joker" }, impl = impl,
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name } } } }, Card)
  G.jokers.cards[#G.jokers.cards + 1] = j
  j.area = G.jokers
  return j
end
local function consumable(key, name, impl)
  return setmetatable({ facing = "front", ability = { set = "Tarot", consumeable = {} }, impl = impl,
    config = { center = { key = key, set = "Tarot", name = name, loc_txt = { name = name } } } }, Card)
end
local function remove_playing(cards) SMODS.calculate_context({ remove_playing_cards = true, removed = cards }) end
local function since(before) return table.concat(Log.between(before, Log.cursor()) or {}, " | ") end

do
  local before = Log.cursor()
  local glass = playing("5", "Diamonds", { seal = "Purple", shattered = true,
    config = { center = { key = "m_glass", set = "Enhanced" } }, ability = { set = "Enhanced" } })
  glass.area = G.play
  remove_playing({ glass })
  local text = since(before)
  check("a glass card that breaks after scoring is named with its enhancement and seal, and shattered",
    text == "5 of Diamonds (" .. require("facts.card_util").enhancement_name("m_glass") .. ", Purple Seal) shattered", text)
end

do
  -- Before Card:shatter runs, use SMODS.shatters to detect pending destruction.
  SMODS.shatters = function(card) return card.config.center.key == "m_glass" or nil end
  local before = Log.cursor()
  local glass = playing("7", "Clubs", { config = { center = { key = "m_glass", set = "Enhanced" } },
    ability = { set = "Enhanced" } })
  local plain = playing("8", "Clubs")
  glass.area, plain.area = G.play, G.play
  remove_playing({ glass, plain })
  SMODS.shatters = nil
  local text = since(before)
  check("SMODS.shatters marks an enhancement that shatters, and only that card",
    text == "7 of Clubs (" .. require("facts.card_util").enhancement_name("m_glass") .. ") shattered | 8 of Clubs destroyed",
    text)
end

do
  local before = Log.cursor()
  local six = playing("6", "Spades")
  six.area = G.play
  local sense = joker("j_sixth_sense", "Sixth Sense", function(_, ctx) return ctx.destroying_card and true or nil end)
  sense:calculate_joker({ destroying_card = six, destroy_card = six, full_hand = { six } })
  remove_playing({ six })
  check("a card a joker destroys during scoring names that joker",
    since(before) == "6 of Spades destroyed by Sixth Sense", since(before))
  G.jokers.cards = {}
end

do
  local before = Log.cursor()
  local c = playing("2", "Clubs")
  c.area = G.hand
  local trading = joker("j_trading", "Trading Card", function(_, ctx)
    if ctx.discard then return { remove = true } end
  end)
  trading:calculate_joker({ discard = true, other_card = c, full_hand = { c } })
  remove_playing({ c })
  check("a card destroyed on discard names the joker that removed it",
    since(before) == "2 of Clubs destroyed by Trading Card", since(before))
  G.jokers.cards = {}
end

do
  local before = Log.cursor()
  local a, b = playing("Q", "Hearts"), playing("3", "Hearts")
  a.area, b.area = G.hand, G.hand
  G.hand.cards = { a, b }
  local hanged = consumable("c_hanged_man", "The Hanged Man", function() remove_playing({ a, b }) end)
  G.TAROT_INTERRUPT = 1
  hanged:use_consumeable()
  G.TAROT_INTERRUPT = nil
  check("cards a consumable destroys name the consumable",
    since(before) == "Queen of Hearts destroyed by The Hanged Man | 3 of Hearts destroyed by The Hanged Man"
      or since(before) == "Q of Hearts destroyed by The Hanged Man | 3 of Hearts destroyed by The Hanged Man",
    since(before))
  G.hand.cards = {}
end

do
  local before = Log.cursor()
  local hidden = playing("A", "Spades")
  hidden.facing = "back"
  hidden.area = G.hand
  G.hand.cards = { hidden }
  local immolate = consumable("c_immolate", "Immolate", function() remove_playing({ hidden }) end)
  G.TAROT_INTERRUPT = 1
  immolate:use_consumeable()
  G.TAROT_INTERRUPT = nil
  local text = since(before)
  check("a face-down card's destruction names its slot, never its rank or suit",
    text:find("face-down", 1, true) ~= nil and not text:find("Ace", 1, true)
      and not text:find("Spades", 1, true) and text:find("Immolate", 1, true) ~= nil, text)
  G.hand.cards = {}
end

do
  local before = Log.cursor()
  -- SMODS.destroy_cards dissolves immediately inside the joker’s calculation.
  local gros = joker("j_gros_michel", "Gros Michel", function(self)
    self.getting_sliced = true
    SMODS.calculate_context({ joker_type_destroyed = true, card = self })
  end)
  gros:calculate_joker({ end_of_round = true })
  check("a joker that destroys itself (extinction) says so",
    since(before) == "Gros Michel destroyed itself", since(before))
  G.jokers.cards = {}
end

do
  local before = Log.cursor()
  local victim = joker("j_egg", "Egg")
  local dagger = joker("j_ceremonial", "Ceremonial Dagger", function() victim.getting_sliced = true end)
  dagger:calculate_joker({ setting_blind = true })
  SMODS.calculate_context({ joker_type_destroyed = true, card = victim })
  check("a joker another joker slices names the slicer",
    since(before) == "Egg destroyed by Ceremonial Dagger", since(before))
  G.jokers.cards = {}
end

do
  local before = Log.cursor()
  local saved = joker("j_saved", "Saved Joker")
  saved.getting_sliced = true
  SMODS.calculate_context({ joker_type_destroyed = true, card = saved, flags = { no_destroy = true } })
  check("a destruction the game cancels (no_destroy) is not reported", since(before) == "", since(before))
  G.jokers.cards = {}
end

do
  G.NEURO.decision_snapshot = nil
  local glass = playing("5", "Diamonds", { seal = "Purple", shattered = true,
    config = { center = { key = "m_glass", set = "Enhanced" } }, ability = { set = "Enhanced" } })
  glass.area = G.play
  local first = DD.capture()
  remove_playing({ glass })
  table.remove(G.playing_cards)
  local text = DD.render(first, DD.capture()) or ""
  check("the decision delta names the shattered card beside the deck count",
    text:find("5 of Diamonds (", 1, true) ~= nil and text:find("Purple Seal) shattered", 1, true) ~= nil
      and text:find("deck ", 1, true) ~= nil, text)
  check("a later delta does not repeat it", (DD.render(DD.capture(), DD.capture()) or "") == "")
  G.NEURO.run_generation = 5
  local stale = DD.render(first, DD.capture()) or ""
  check("a new run does not inherit the old run's destructions", not stale:find("shattered", 1, true), stale)
  G.NEURO.run_generation = 4
end

do
  local dump = os.getenv("BALATRO_DUMP")
  local function read(rel)
    local fh = dump and io.open(dump .. "/" .. rel, "r")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
  end
  local state, card = read("functions/state_events.lua"), read("card.lua")
  local smods_utils = dump and read("../../smods/src/utils.lua")
  if not (state and card and smods_utils) then
    require("tests.skip_ledger").bail("destruction-log", 6, "BALATRO_DUMP unset or game/smods source unreadable")
  end
  local _, n_state = state:gsub("SMODS%.calculate_context%(%{[^}]*remove_playing_cards = true", "")
  check("engine: discard and play both raise remove_playing_cards", n_state >= 2, n_state)
  check("engine: consumable destruction raises remove_playing_cards",
    card:find("SMODS%.calculate_context%(%{ remove_playing_cards = true, removed = destroyed_cards %}%)") ~= nil)
  local _, n_joker = card:gsub("if self%.getting_sliced and not SMODS%.is_playing_card%(self%)[^\n]*then%s+local flags = SMODS%.calculate_context%(%{joker_type_destroyed = true, card = self", "")
  check("engine: shatter and start_dissolve raise joker_type_destroyed for sliced non-playing cards",
    n_joker == 2, n_joker)
  check("engine: extinction goes through SMODS.destroy_cards on the joker itself",
    card:find("SMODS%.destroy_cards%(self, nil, nil, true%)") ~= nil)
  check("engine: Ceremonial Dagger and Madness mark their victim inside their own calculation",
    card:find("sliced_card%.getting_sliced = true") ~= nil and card:find("joker_to_destroy%.getting_sliced = true") ~= nil)
  check("smods: destroy_cards marks getting_sliced and raises remove_playing_cards for playing cards",
    smods_utils:find("card%.getting_sliced = true") ~= nil
      and smods_utils:find("remove_playing_cards = true, removed = playing_cards") ~= nil)
end

done()
