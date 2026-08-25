_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("stable-epoch")
local Compact = require("context.context_compact")
local Orchestrator = require("core.orchestrator")
local Delivery = require("core.context_delivery")

local wire = {}
local N = { enabled = true, stable_refresh_due = true, run_generation = 1,
  once_serials = {}, session_once_serials = {} }
function N:send_context(msg, silent, receipt)
  wire[#wire + 1] = { msg = msg, silent = silent }
  receipt.status = "written"
  return true
end

-- A deck is only committed once Game:start_run has set G.STAGE = G.STAGES.RUN (dump game.lua:2067),
-- so a world that means to be inside a run has to say so.
local function world(dollars, joker_name)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1 },
    STAGES = { MAIN_MENU = 1, RUN = 2, SANDBOX = 3 }, STAGE = 2, GAME = {
      dollars = dollars, chips = 0, used_vouchers = {}, modifiers = {},
      current_round = { hands_left = 3, discards_left = 2 }, round_resets = { ante = 2 },
      blind = { name = "Small Blind", chips = 300 },
    },
    jokers = { cards = joker_name and { { ability = { name = joker_name, set = "Joker" },
      config = { center = { key = "j_test", set = "Joker" } } } } or {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } }, hand = { cards = {} },
    playing_cards = {}, NEURO = N,
  }
  Compact.invalidate_cache()
end

Delivery.reset_transport()
world(8, "Joker")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("first eligible state writes one immutable rules frame", #wire == 1, tostring(#wire))
check("retained frame is silent", wire[1] and wire[1].silent == true)
check("retained frame contains no run cash or roster", wire[1]
  and not wire[1].msg:find("$8", 1, true) and not wire[1].msg:find("Joker details:", 1, true),
  wire[1] and wire[1].msg)

world(23, "Bull")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("mutable run changes never produce a retained rewrite", #wire == 1, tostring(#wire))

require("core.neuro_lifecycle").reset_context_delivery()
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("a new transport view replays the same immutable rule", #wire == 2 and wire[2].msg == wire[1].msg,
  tostring(#wire))

local function play_deck(key, display)
  world(8, "Joker")
  G.STAGE = G.STAGES.RUN
  G.P_CENTERS = { [key] = { key = key, loc_txt = { name = display } } }
  G.GAME.selected_back = { key = key }
  Compact.invalidate_cache()
end

local before = #wire
play_deck("b_red", "Red Deck")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("the deck's rules arrive as their own retained frame", #wire == before + 1
  and wire[#wire].msg:find("Deck rules -- Red Deck: +1 discard per round", 1, true) ~= nil,
  tostring(#wire) .. " " .. tostring(wire[#wire] and wire[#wire].msg))

Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("the same deck is never retained twice", #wire == before + 1, tostring(#wire))

play_deck("b_blue", "Blue Deck")
Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
check("a second run on another deck appends a frame instead of rewriting the first",
  #wire == before + 2
    and wire[#wire].msg:find("Deck rules -- Blue Deck: +1 hand per round", 1, true) ~= nil,
  tostring(#wire) .. " " .. tostring(wire[#wire] and wire[#wire].msg))
check("and the first deck's frame is still on the wire unchanged",
  wire[before + 1].msg:find("Deck rules -- Red Deck", 1, true) ~= nil, wire[before + 1].msg)

local state = Compact.build("SELECTING_HAND", nil, { split = "state", no_cache = true })
check("the force names the deck in play", state:find("Your deck: Blue Deck.", 1, true) ~= nil,
  state)
check("but never restates its rules there", state:find("+1 hand per round", 1, true) == nil,
  state)

local MENU_STATES = { "MENU", "RUN_SETUP", "SPLASH", "GAME_OVER" }
local function rule_map(state_name)
  Compact.invalidate_cache()
  local map, names = {}, {}
  for _, frame in ipairs(Compact.rule_frames(state_name)) do
    map[tostring(frame.key)] = frame.text
    names[#names + 1] = tostring(frame.key)
  end
  return map, names
end
local function rule_list(state_name)
  local map, names = rule_map(state_name)
  local texts = {}
  for _, name in ipairs(names) do texts[#texts + 1] = map[name] end
  return table.concat(texts, "\n")
end
do
  local in_run, in_run_names = rule_map("SELECTING_HAND")
  check("R12a an in-run state retains the invariant frame and the played deck, each under its name",
    in_run["frame"] ~= nil and in_run["deck:b_blue"] ~= nil, table.concat(in_run_names, ", "))

  local differ = {}
  for _, st in ipairs(MENU_STATES) do
    G.STAGE = G.STAGES.MAIN_MENU
    local menu, menu_names = rule_map(st)
    G.STAGE = G.STAGES.RUN
    for _, name in ipairs(menu_names) do
      if menu[name] ~= in_run[name] then differ[#differ + 1] = st .. " -> " .. name end
      if name:find("^deck:") then differ[#differ + 1] = st .. " retains a deck" end
    end
    if #menu_names == 0 then differ[#differ + 1] = st .. " retains nothing" end
  end
  check("every frame a menu screen offers is the in-run frame of the same name, and no deck",
    #differ == 0, table.concat(differ, ", "))

  local leaked = {}
  for _, st in ipairs(MENU_STATES) do
    G.STAGE = G.STAGES.MAIN_MENU
    local text = rule_list(st)
    G.STAGE = G.STAGES.RUN
    for _, claim in ipairs({ "Decks you can pick", "Stakes:", "Your deck:", "splash screen",
        "Run over", "$" }) do
      if text:find(claim, 1, true) then leaked[#leaked + 1] = st .. " -> " .. claim end
    end
  end
  check("nothing that is only true on that screen reaches the retained channel",
    #leaked == 0, table.concat(leaked, ", "))
end

do
  Delivery.reset_transport()
  local base = #wire
  world(8, "Joker")
  Orchestrator._maybe_emit_stable_context("MENU")
  local from_menu = #wire - base
  check("a session that starts on the menu is told the rules there", from_menu >= 1,
    tostring(from_menu))
  for _, st in ipairs({ "SPLASH", "RUN_SETUP", "GAME_OVER" }) do
    Orchestrator._maybe_emit_stable_context(st)
  end
  check("the other menu screens add nothing", #wire - base == from_menu, tostring(#wire - base))
  world(23, "Bull")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  Orchestrator._maybe_emit_stable_context("SHOP")
  check("and entering the run delivers no frame a second time",
    #wire - base == from_menu, tostring(#wire - base))
end

do
  Delivery.reset_transport()
  local base = #wire
  world(8, "Joker")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  local from_run = #wire - base
  check("an in-run start still writes the rules once", from_run >= 1, tostring(from_run))
  for _, st in ipairs(MENU_STATES) do
    Orchestrator._maybe_emit_stable_context(st)
  end
  check("returning to the menu delivers no frame a second time",
    #wire - base == from_run, tostring(#wire - base))
end

do
  Delivery.reset_transport()
  play_deck("b_green", "Green Deck")
  G.STAGE = G.STAGES.MAIN_MENU
  Compact.invalidate_cache()
  Orchestrator._maybe_emit_stable_context("MENU")
  local after_menu = #wire
  local retained_green = false
  for i = 1, #wire do
    if wire[i].msg:find("Deck rules -- Green Deck", 1, true) then retained_green = true end
  end
  check("a deck the menu merely has selected retains nothing", not retained_green,
    tostring(after_menu))
  play_deck("b_green", "Green Deck")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("the run that commits to that deck retains its rules once",
    #wire == after_menu + 1
      and wire[#wire].msg:find("Deck rules -- Green Deck", 1, true) ~= nil, tostring(#wire))
  Orchestrator._maybe_emit_stable_context("BLIND_SELECT")
  check("R20b and every later screen of that run restates nothing", #wire == after_menu + 1,
    tostring(#wire))
  play_deck("b_yellow", "Yellow Deck")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("a run on another deck still appends its own frame",
    #wire == after_menu + 2
      and wire[#wire].msg:find("Deck rules -- Yellow Deck", 1, true) ~= nil, tostring(#wire))
end

do
  Delivery.reset_transport()
  local GameRules = require("context.game_rules")
  local real_frame = GameRules.invariant_frame
  GameRules.invariant_frame = function() return "" end
  play_deck("b_red", "Red Deck")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  GameRules.invariant_frame = real_frame
  local base = #wire
  play_deck("b_red", "Red Deck")
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("a first emission missing the invariant frame does not cost the session its rules",
    #wire == base + 1 and wire[#wire].msg:find("RULES.", 1, true) ~= nil,
    tostring(#wire - base) .. " " .. tostring(wire[#wire] and wire[#wire].msg:sub(1, 60)))
end

done()
