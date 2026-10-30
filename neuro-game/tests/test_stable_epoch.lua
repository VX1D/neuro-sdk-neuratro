require("tests.stubs").setup({ love = "lazy", localize = true })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("stable-epoch")
local Compact = require("context.context_compact")
local Orchestrator = require("core.orchestrator")
local Delivery = require("core.context_delivery")
local ActionGuide = require("facts.token_legends").ACTION_SEMANTICS_V1

local wire = {}

local function guide_key()
  local scope = Delivery.rules_scope()
  return "rule\1" .. ActionGuide.key .. (scope and ("\1" .. scope) or "")
end

local N = { enabled = true, stable_refresh_due = true, run_generation = 1,
  once_serials = {}, session_once_serials = {} }
N.send_context = require("tests.helpers").wire_context(wire)

local function world(dollars, joker_name)
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = ES.SELECTING_HAND, STATES = ES,
    STAGES = { MAIN_MENU = 1, RUN = 2, SANDBOX = 3 }, STAGE = 2, GAME = {
      dollars = dollars, chips = 0, used_vouchers = {}, modifiers = {}, pseudorandom = { seed = "STABLE" },
      current_round = { hands_left = 3, discards_left = 2 }, round_resets = { ante = 2 },
      blind = { name = "Small Blind", chips = 300 },
    },
    jokers = { cards = joker_name and { { ability = { name = joker_name, set = "Joker" },
      config = { center = { key = "j_test", set = "Joker" } } } } or {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } }, hand = { cards = {} },
    playing_cards = {}, NEURO = N,
  }
end

Delivery.reset_transport()
world(8, "Joker")
require("core.window").emit_rules("SELECTING_HAND")
check("first eligible state writes immutable rules plus the canonical action guide",
  #wire == 2
    and wire[2] and wire[2].silent == true and wire[2].msg == ActionGuide.text
    and Delivery._delivered()[guide_key()] == ActionGuide.text,
  tostring(#wire) .. " " .. tostring(wire[2] and wire[2].msg))
check("retained frame is silent", wire[1] and wire[1].silent == true)
check("retained frame contains no run cash or roster", wire[1]
  and not wire[1].msg:find("$8", 1, true) and not wire[1].msg:find("Joker details:", 1, true),
  wire[1] and wire[1].msg)

world(23, "Bull")
require("core.window").emit_rules("SELECTING_HAND")
check("mutable run changes never produce a retained rewrite", #wire == 2, tostring(#wire))

require("core.neuro_lifecycle").reset_context_delivery()
require("core.window").emit_rules("SELECTING_HAND")
check("a new transport view replays the same immutable rule and guide",
  #wire == 4 and wire[3].msg == wire[1].msg and wire[4].msg == wire[2].msg
    and Delivery._delivered()[guide_key()] == ActionGuide.text,
  tostring(#wire))

local function play_deck(key, display)
  world(8, "Joker")
  G.STAGE = G.STAGES.RUN
  G.P_CENTERS = require("tests.engine_centers").with({ [key] = { loc_txt = { name = display } } })
  G.GAME.selected_back = { key = key }
end

local before = #wire
play_deck("b_red", "Red Deck")
require("core.window").emit_rules("SELECTING_HAND")
check("the deck's rules arrive as their own retained frame", #wire == before + 1
  and wire[#wire].msg:find("Red Deck", 1, true) ~= nil,
  tostring(#wire) .. " " .. tostring(wire[#wire] and wire[#wire].msg))

require("core.window").emit_rules("SELECTING_HAND")
check("the same deck is never retained twice", #wire == before + 1, tostring(#wire))

play_deck("b_blue", "Blue Deck")
require("core.window").emit_rules("SELECTING_HAND")
check("a second run on another deck appends a frame instead of rewriting the first",
  #wire == before + 2
    and wire[#wire].msg:find("Blue Deck", 1, true) ~= nil,
  tostring(#wire) .. " " .. tostring(wire[#wire] and wire[#wire].msg))
check("and the first deck's frame is still on the wire unchanged",
  wire[before + 1].msg:find("Deck rules -- Red Deck", 1, true) ~= nil, wire[before + 1].msg)

local state = Compact.build("SELECTING_HAND", nil, { split = "state" })
check("the force names the deck in play", state:find("Blue Deck", 1, true) ~= nil,
  state)

local MENU_STATES = { "MENU", "RUN_SETUP", "SPLASH", "GAME_OVER" }
local function rule_map(state_name)
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
  check("R12a an in-run state retains invariant and deck frames, not the separate action guide",
    in_run["frame"] ~= nil and in_run["deck:b_blue"] ~= nil
      and in_run[ActionGuide.key] == nil, table.concat(in_run_names, ", "))

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
  require("core.window").emit_rules("MENU")
  local from_menu = #wire - base
  check("a session that starts on the menu is told the rules and action guide", from_menu == 2,
    tostring(from_menu))
  for _, st in ipairs({ "SPLASH", "RUN_SETUP", "GAME_OVER" }) do
    require("core.window").emit_rules(st)
  end
  check("the other menu screens add nothing", #wire - base == from_menu, tostring(#wire - base))
  world(23, "Bull")
  require("core.window").emit_rules("SELECTING_HAND")
  require("core.window").emit_rules("SHOP")
  check("and entering the run delivers no retained frame or guide a second time",
    #wire - base == from_menu, tostring(#wire - base))
end

do
  Delivery.reset_transport()
  local base = #wire
  world(8, "Joker")
  require("core.window").emit_rules("SELECTING_HAND")
  local from_run = #wire - base
  check("an in-run start still writes the rules and action guide once", from_run == 2,
    tostring(from_run))
  for _, st in ipairs(MENU_STATES) do
    require("core.window").emit_rules(st)
  end
  check("returning to the menu delivers no frame a second time",
    #wire - base == from_run, tostring(#wire - base))
end

do
  Delivery.reset_transport()
  play_deck("b_green", "Green Deck")
  G.STAGE = G.STAGES.MAIN_MENU
  require("core.window").emit_rules("MENU")
  local after_menu = #wire
  local retained_green = false
  for i = 1, #wire do
    if wire[i].msg:find("Deck rules -- Green Deck", 1, true) then retained_green = true end
  end
  check("a deck the menu merely has selected retains nothing", not retained_green,
    tostring(after_menu))
  play_deck("b_green", "Green Deck")
  require("core.window").emit_rules("SELECTING_HAND")
  local green_deck_at
  for i = after_menu + 1, #wire do
    if wire[i].msg:find("Deck rules -- Green Deck", 1, true) then green_deck_at = i end
  end
  check("the run that commits to that deck retains its rules, now scoped to the run, once",
    #wire == after_menu + 3 and green_deck_at ~= nil and wire[#wire].msg == ActionGuide.text, tostring(#wire))
  require("core.window").emit_rules("BLIND_SELECT")
  check("R20b and every later screen of that ante restates nothing", #wire == after_menu + 3,
    tostring(#wire))
  play_deck("b_yellow", "Yellow Deck")
  require("core.window").emit_rules("SELECTING_HAND")
  check("a run on another deck still appends its own frame",
    #wire == after_menu + 4
      and wire[#wire].msg:find("Deck rules -- Yellow Deck", 1, true) ~= nil, tostring(#wire))
end

do
  Delivery.reset_transport()
  local GameRules = require("context.game_rules")
  local real_frame = GameRules.invariant_frame
  GameRules.invariant_frame = function() return "" end
  play_deck("b_red", "Red Deck")
  require("core.window").emit_rules("SELECTING_HAND")
  GameRules.invariant_frame = real_frame
  local base = #wire
  play_deck("b_red", "Red Deck")
  require("core.window").emit_rules("SELECTING_HAND")
  check("a first emission missing the invariant frame does not cost the session its rules",
    #wire == base + 1 and wire[#wire].msg:find("RULES.", 1, true) ~= nil,
    tostring(#wire - base) .. " " .. tostring(wire[#wire] and wire[#wire].msg:sub(1, 60)))
end

done()
