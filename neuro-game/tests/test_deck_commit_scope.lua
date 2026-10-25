require("tests.stubs").setup({ love = "lazy", localize = true })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("deck-commit-scope")
local Compact = require("context.context_compact")
local Orchestrator = require("core.orchestrator")
local Delivery = require("core.context_delivery")
local MenuHandlers = require("handlers.menu_handlers")

local BROWSED = {
  { key = "b_red", name = "Red Deck" }, { key = "b_blue", name = "Blue Deck" },
  { key = "b_green", name = "Green Deck" }, { key = "b_black", name = "Black Deck" },
  { key = "b_plasma", name = "Plasma Deck" }, { key = "b_checkered", name = "Checkered Deck" },
  { key = "b_abandoned", name = "Abandoned Deck" },
}
local PLAYED = { key = "b_black", name = "Black Deck" }

local POOL, CENTERS = {}, require("tests.engine_centers").centers()
for i, d in ipairs(BROWSED) do
  local center = CENTERS[d.key]
  center.loc_txt = { name = d.name }
  POOL[i] = center
end

local function back(center)
  return {
    key = center.key, name = center.name, effect = { center = center },
    change_to = function(self, c)
      self.key, self.name, self.effect.center = c.key, c.name, c
    end,
  }
end

local wire = {}
local N = { enabled = true, stable_refresh_due = true, run_generation = 1,
  once_serials = {}, session_once_serials = {} }
N.send_context = require("tests.helpers").wire_context(wire)

local function world(stage)
  _G.G = {
    STAGE = stage, STAGES = { MAIN_MENU = 1, RUN = 2, SANDBOX = 3 },
    STATE = ES.SELECTING_HAND, STATES = ES,
    FUNCS = {}, P_CENTERS = CENTERS, P_CENTER_POOLS = { Back = POOL },
    GAME = {
      dollars = 4, chips = 0, used_vouchers = {}, modifiers = {},
      current_round = { hands_left = 3, discards_left = 2 }, round_resets = { ante = 1 },
      blind = { name = "Small Blind", chips = 300 },
      selected_back = back(CENTERS.b_red), viewed_back = back(CENTERS.b_red),
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } }, hand = { cards = {} },
    playing_cards = {}, NEURO = N,
  }
end

local function deck_frames()
  local named = {}
  for _, sent in ipairs(wire) do
    local name = sent.msg:match("Deck rules %-%- ([^:]+):")
    if name then named[#named + 1] = name end
  end
  return named
end

Delivery.reset_transport()

world(1)
require("core.window").emit_rules("MENU")
for _, deck in ipairs(BROWSED) do
  local already = require("facts.deck_facts").run_deck_center().key == deck.key
  local run_it, err = MenuHandlers.handle_change_selected_back({ back = deck.key })
  check("browsing " .. deck.name .. (already and " while it is selected changes nothing" or " is accepted by the handler"),
    already and run_it == nil and err.reason_code == "UNCHANGED" or not already and run_it ~= nil,
    tostring(err and err.message))
  if run_it then run_it() end
  require("core.window").emit_rules("MENU")
  require("core.window").emit_rules("RUN_SETUP")
end

check("a deck that was only LOOKED AT never reaches the channel that cannot retract it",
  #deck_frames() == 0, table.concat(deck_frames(), ", "))

-- start_run switches to RUN before rebuilding and applying the selected back.
world(2)
G.GAME.selected_back = back(CENTERS[PLAYED.key])
G.GAME.selected_back_key = CENTERS[PLAYED.key]
require("core.window").emit_rules("BLIND_SELECT")
require("core.window").emit_rules("SELECTING_HAND")

local named = deck_frames()
check("exactly one deck's rules are retained, and it is the deck being played",
  #named == 1 and named[1] == PLAYED.name, table.concat(named, ", "))

local state = Compact.build("SELECTING_HAND", nil, { split = "state" }) or ""
check("the force still names the deck in play",
  state:find("Your deck: " .. PLAYED.name .. ".", 1, true) ~= nil, state)

-- Returning to the menu resets the deck to Red; that default is not a retained choice.
local after_run = #deck_frames()
world(1)
require("core.window").emit_rules("MENU")
require("core.window").emit_rules("GAME_OVER")
check("returning to the menu retains no further deck", #deck_frames() == after_run,
  table.concat(deck_frames(), ", "))

done()
