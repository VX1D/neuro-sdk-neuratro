require("tests.stubs").setup({ love = "lazy", localize = true })

local check, done = require("tests.helpers").harness("derivable-parameters")

local HANDS = {
  ["Flush Five"]     = { visible = false, order = 1,  played = 0, level = 1, chips = 160, mult = 16 },
  ["Flush House"]    = { visible = false, order = 2,  played = 0, level = 1, chips = 140, mult = 14 },
  ["Five of a Kind"] = { visible = false, order = 3,  played = 0, level = 1, chips = 120, mult = 12 },
  ["Straight Flush"] = { visible = true,  order = 4,  played = 0, level = 1, chips = 100, mult = 8 },
  ["Four of a Kind"] = { visible = true,  order = 5,  played = 1, level = 1, chips = 60,  mult = 7 },
  ["Full House"]     = { visible = true,  order = 6,  played = 0, level = 1, chips = 40,  mult = 4 },
  ["Flush"]          = { visible = true,  order = 7,  played = 3, level = 1, chips = 35,  mult = 4 },
  ["Straight"]       = { visible = true,  order = 8,  played = 0, level = 1, chips = 30,  mult = 4 },
  ["Three of a Kind"]= { visible = true,  order = 9,  played = 1, level = 1, chips = 30,  mult = 3 },
  ["Two Pair"]       = { visible = true,  order = 10, played = 4, level = 1, chips = 20,  mult = 2 },
  ["Pair"]           = { visible = true,  order = 11, played = 7, level = 1, chips = 10,  mult = 2 },
  ["High Card"]      = { visible = true,  order = 12, played = 2, level = 1, chips = 5,   mult = 1 },
}

local function blind_board()
  _G.G = {
    NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 1,
      once_serials = {}, session_once_serials = {}, run_generation = 1 },
    FUNCS = {},
    GAME = { hands = HANDS, dollars = 12, round = 1, win_ante = 8,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      used_vouchers = {}, round_resets = { ante = 1, blind_choices = {} } },
    hand = { cards = {}, config = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} }, playing_cards = {},
  }
end

local ContextReadable = require("context.context_readable")

local function advertised_focus_values(text)
  local list = text:match("Unlocked hand types: (.-); no other hand type")
  if not list then return nil end
  local out = {}
  for name in list:gmatch("[^,]+") do
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then out[#out + 1] = name end
  end
  return out
end

do
  blind_board()
  local text = ContextReadable.build("BLIND_SELECT", { "select_blind", "skip_blind", "record_plan" }) or ""
  local missing, leaked = {}, {}
  for name, hd in pairs(HANDS) do
    local present = text:find(name, 1, true) ~= nil
    if hd.visible and not present then missing[#missing + 1] = name end
    if not hd.visible and present then leaked[#leaked + 1] = name end
  end
  table.sort(missing); table.sort(leaked)
  check("H1a every visible hand name rides in the BLIND_SELECT payload",
    #missing == 0, table.concat(missing, ", "))
  check("H1b no hidden hand type is offered as a legal focus",
    #leaked == 0, table.concat(leaked, ", "))
  local Actions = require("core.actions")
  local real_valid = Actions.is_action_valid
  Actions.is_action_valid = function(n) return n == "select_blind" or n == "skip_blind" or n == "record_plan" end
  G.GAME.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
  G.GAME.round_resets.blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" }
  G.P_BLINDS = G.P_BLINDS or { bl_small = { key = "bl_small", name = "Small Blind" },
    bl_big = { key = "bl_big", name = "Big Blind" }, bl_hook = { key = "bl_hook", name = "The Hook", boss = {} } }
  local ok, built = pcall(require("force.force_blind_select").build)
  Actions.is_action_valid = real_valid
  local query = (ok and type(built) == "table" and built.query) or tostring(built)
  check("H1c the query ties the field to the state's list (SPECIFICATION.md:157-158)",
    query:find("plan.hand_focus={primary=one of the Unlocked hand types", 1, true) ~= nil
      and text:find("Unlocked hand types: ", 1, true) ~= nil, query)

  local advertised = advertised_focus_values(text)
  check("H1d the accepted set is stated as an enumerable sentence, not scattered prose",
    advertised ~= nil and #advertised > 0, text)
  if advertised then
    local want = {}
    for name, hd in pairs(HANDS) do if hd.visible then want[name] = true end end
    local extra = {}
    for _, name in ipairs(advertised) do
      if want[name] then want[name] = nil else extra[#extra + 1] = name end
    end
    local absent = {}
    for name in pairs(want) do absent[#absent + 1] = name end
    table.sort(extra); table.sort(absent)
    check("H1e the advertised set is exactly the visible set -- no extra value, none missing",
      #extra == 0 and #absent == 0,
      "extra: [" .. table.concat(extra, ", ") .. "] absent: [" .. table.concat(absent, ", ") .. "]")
  end
end

do
  local Plans = require("handlers.plan_handlers")
  local rejected = {}
  for name, hd in pairs(HANDS) do
    blind_board()
    local ok = Plans.prepare_plan({ hand_focus = { primary = name } })
    if hd.visible and not ok then rejected[#rejected + 1] = name end
    if (not hd.visible) and ok then rejected[#rejected + 1] = name .. " (hidden, accepted!)" end
  end
  table.sort(rejected)
  check("H2a the offered set is exactly the set prepare_plan accepts",
    #rejected == 0, table.concat(rejected, ", "))

  blind_board()
  local text = ContextReadable.build("BLIND_SELECT", { "select_blind", "skip_blind", "record_plan" }) or ""
  local advertised = advertised_focus_values(text) or {}
  local refused = {}
  for _, name in ipairs(advertised) do
    blind_board()
    if not Plans.prepare_plan({ hand_focus = { primary = name } }) then
      refused[#refused + 1] = name
    end
  end
  check("H2b every value the window advertises survives prepare_plan",
    #advertised > 0 and #refused == 0,
    "advertised " .. #advertised .. ", refused: [" .. table.concat(refused, ", ") .. "]")

  local refused_fb = {}
  for _, name in ipairs(advertised) do
    blind_board()
    if not Plans.prepare_plan({ hand_focus = { primary = advertised[1], fallback = name } }) then
      refused_fb[#refused_fb + 1] = name
    end
  end
  check("H2c and in the fallback slot too",
    #advertised > 0 and #refused_fb == 0, table.concat(refused_fb, ", "))
end

do
  local Actions = require("core.actions")
  local POOL, P = {}, {}
  local DECKS = {
    { key = "b_red",    name = "Red Deck",    d = "+1 discard every round" },
    { key = "b_blue",   name = "Blue Deck",   d = "+1 hand every round" },
    { key = "b_yellow", name = "Yellow Deck", d = "Start with extra $10" },
  }
  for i, d in ipairs(DECKS) do
    local deck = { key = d.key, loc_txt = { name = d.name, description = { d.d } } }
    POOL[i] = deck; P[d.key] = deck
  end
  local function menu_board()
    _G.G = {
      NEURO = { enabled = true, decision_serial = 1, state_enter_serial = 1 },
      FUNCS = {}, P_CENTERS = P, P_CENTER_POOLS = { Back = POOL },
      GAME = { selected_back = { key = "b_red", name = "Red Deck" }, stake = 1, won = false,
        round = 5, round_resets = { ante = 4 }, hands = {}, current_round = {} },
      hand = { cards = {} }, jokers = { cards = {} }, consumeables = { cards = {} },
    }
  end

  local blind = {}
  for _, state in ipairs({ "SPLASH", "MENU", "RUN_SETUP", "GAME_OVER", "BLIND_SELECT" }) do
    local offers = Actions.get_state_action_set(state)["select_deck"] == true
    if offers then
      menu_board()
      local text = ContextReadable.build(state, { "open_run_setup", "select_deck" }) or ""
      if not (text:find("key b_blue", 1, true) and text:find("key b_yellow", 1, true)) then
        blind[#blind + 1] = state
      end
    end
  end
  check("every state that registers select_deck also lists the deck keys",
    #blind == 0, table.concat(blind, ", "))
end

done()
