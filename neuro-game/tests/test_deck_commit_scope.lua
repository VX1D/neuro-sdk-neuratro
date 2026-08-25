_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

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

local POOL, CENTERS = {}, {}
for i, d in ipairs(BROWSED) do
  local center = { key = d.key, name = d.name, loc_txt = { name = d.name }, config = {} }
  POOL[i] = center
  CENTERS[d.key] = center
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
function N:send_context(msg, silent, receipt)
  wire[#wire + 1] = { msg = msg, silent = silent }
  receipt.status = "written"
  return true
end

local function world(stage)
  _G.G = {
    STAGE = stage, STAGES = { MAIN_MENU = 1, RUN = 2, SANDBOX = 3 },
    STATE = 1, STATES = { SELECTING_HAND = 1 },
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
  Compact.invalidate_cache()
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
Orchestrator._maybe_emit_stable_context("MENU")
for _, deck in ipairs(BROWSED) do
  local run_it, err = MenuHandlers.handle_change_selected_back({ back = deck.key })
  check("browsing " .. deck.name .. " is accepted by the handler", run_it ~= nil, tostring(err))
  if run_it then run_it() end
  Compact.invalidate_cache()
  Orchestrator._maybe_emit_stable_context("MENU")
  Orchestrator._maybe_emit_stable_context("RUN_SETUP")
end

check("a deck that was only LOOKED AT never reaches the channel that cannot retract it",
  #deck_frames() == 0, table.concat(deck_frames(), ", "))

-- The commit: Game:start_run sets G.STAGE = G.STAGES.RUN (dump game.lua:2067) and only then rebuilds
-- G.GAME.selected_back from the choice and applies it (game.lua:2085-2116).
world(2)
G.GAME.selected_back = back(CENTERS[PLAYED.key])
G.GAME.selected_back_key = CENTERS[PLAYED.key]
Compact.invalidate_cache()
Orchestrator._maybe_emit_stable_context("BLIND_SELECT")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")

local named = deck_frames()
check("exactly one deck's rules are retained, and it is the deck being played",
  #named == 1 and named[1] == PLAYED.name, table.concat(named, ", "))

local state = Compact.build("SELECTING_HAND", nil, { split = "state", no_cache = true }) or ""
check("the force still names the deck in play",
  state:find("Your deck: " .. PLAYED.name .. ".", 1, true) ~= nil, state)

for _, sent in ipairs(wire) do
  if sent.msg:find("Deck rules --", 1, true) then
    check("the retained deck frame claims no current run",
      sent.msg:find("Your deck", 1, true) == nil
        and sent.msg:find("you are playing", 1, true) == nil, sent.msg)
  end
end

-- Back to the menu: Game:main_menu resets the deck to Red (dump game.lua:1554-1566), which is a
-- screen default, not a choice -- it may not retain anything either.
local after_run = #deck_frames()
world(1)
Orchestrator._maybe_emit_stable_context("MENU")
Orchestrator._maybe_emit_stable_context("GAME_OVER")
check("returning to the menu retains no further deck", #deck_frames() == after_run,
  table.concat(deck_frames(), ", "))

done()
